use std::collections::HashSet;
use std::fs::File;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

use ebur128::{EbuR128, Mode};
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::errors::Error;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::TrackType;
use symphonia::core::io::MediaSourceStream;

/// Outcome of measuring one file.
#[derive(Debug, Clone, PartialEq)]
pub struct LoudnessResult {
    /// EBU R128 integrated loudness in LUFS; `None` if not measured.
    pub lufs: Option<f64>,
    /// The job was cancelled with [cancel_loudness] before it finished.
    pub cancelled: bool,
    /// Why the file could not be measured.
    pub message: Option<String>,
}

impl LoudnessResult {
    fn failed(message: impl Into<String>) -> Self {
        Self {
            lufs: None,
            cancelled: false,
            message: Some(message.into()),
        }
    }

    fn cancelled() -> Self {
        Self {
            lufs: None,
            cancelled: true,
            message: None,
        }
    }
}

static NEXT_JOB: AtomicU32 = AtomicU32::new(1);
static CANCELLED: Mutex<Option<HashSet<u32>>> = Mutex::new(None);

/// A fresh id for [measure_loudness]. Rust owns the counter, so a Dart hot
/// restart never reuses an id that was cancelled before.
#[flutter_rust_bridge::frb(sync)]
pub fn new_loudness_job() -> u32 {
    NEXT_JOB.fetch_add(1, Ordering::Relaxed)
}

/// Cancels the job [job]: a running [measure_loudness] for it stops at the
/// next packet, a later one returns at once.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_loudness(job: u32) {
    if let Ok(mut set) = CANCELLED.lock() {
        set.get_or_insert_with(HashSet::new).insert(job);
    }
}

fn is_cancelled(job: u32) -> bool {
    CANCELLED
        .lock()
        .map(|set| set.as_ref().is_some_and(|s| s.contains(&job)))
        .unwrap_or(false)
}

/// Forgets a finished job, so the set only holds jobs still running.
fn forget(job: u32) {
    if let Ok(mut set) = CANCELLED.lock() {
        if let Some(s) = set.as_mut() {
            s.remove(&job);
        }
    }
}

/// Decodes the whole file at [path] and measures its integrated loudness
/// (EBU R128). Never panics; every failure is reported in the result.
pub fn measure_loudness(path: String, job: u32) -> LoudnessResult {
    let outcome = measure(Path::new(&path), job);
    forget(job);
    match outcome {
        Ok(Some(lufs)) => LoudnessResult {
            lufs: Some(lufs),
            cancelled: false,
            message: None,
        },
        Ok(None) => LoudnessResult::cancelled(),
        Err(message) => LoudnessResult::failed(message),
    }
}

/// `Ok(None)` when cancelled.
fn measure(path: &Path, job: u32) -> Result<Option<f64>, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, mss, Default::default(), Default::default())
        .map_err(|e| e.to_string())?;
    let track = format
        .default_track(TrackType::Audio)
        .ok_or("No audio track")?;
    let track_id = track.id;
    let params = track
        .codec_params
        .as_ref()
        .and_then(|p| p.audio())
        .ok_or("No audio track")?;
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(params, &AudioDecoderOptions::default())
        .map_err(|e| e.to_string())?;

    let mut meter: Option<(EbuR128, u32, usize)> = None;
    let mut samples: Vec<f32> = Vec::new();
    loop {
        if is_cancelled(job) {
            return Ok(None);
        }
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };
        if packet.track_id != track_id {
            continue;
        }
        let buf = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        };
        if buf.frames() == 0 {
            continue;
        }
        let rate = buf.spec().rate();
        let channels = buf.spec().channels().count();
        let (ebu, _, _) = match &mut meter {
            Some(m) if m.1 == rate && m.2 == channels => m,
            Some(_) => return Err("The audio format changes mid-stream".into()),
            None => {
                let ebu =
                    EbuR128::new(channels as u32, rate, Mode::I).map_err(|e| e.to_string())?;
                meter.insert((ebu, rate, channels))
            }
        };
        buf.copy_to_vec_interleaved(&mut samples);
        ebu.add_frames_f32(&samples).map_err(|e| e.to_string())?;
    }

    let (ebu, _, _) = meter.ok_or("No audio could be decoded")?;
    let lufs = ebu.loudness_global().map_err(|e| e.to_string())?;
    if lufs.is_finite() {
        Ok(Some(lufs))
    } else {
        Err("Silent or too short".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::PI;
    use std::path::PathBuf;

    fn fixture(name: &str) -> String {
        format!(
            "{}/../test/fixtures/audio/{name}",
            env!("CARGO_MANIFEST_DIR")
        )
    }

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("owntune-loudness-{}-{name}", std::process::id()))
    }

    /// Writes a 16-bit PCM WAV with [channels] identical channels.
    fn write_wav(name: &str, rate: u32, channels: u16, samples: &[f64]) -> String {
        let data_len = (samples.len() * channels as usize * 2) as u32;
        let mut out = Vec::with_capacity(44 + data_len as usize);
        out.extend(b"RIFF");
        out.extend((36 + data_len).to_le_bytes());
        out.extend(b"WAVEfmt ");
        out.extend(16u32.to_le_bytes());
        out.extend(1u16.to_le_bytes());
        out.extend(channels.to_le_bytes());
        out.extend(rate.to_le_bytes());
        out.extend((rate * u32::from(channels) * 2).to_le_bytes());
        out.extend((channels * 2).to_le_bytes());
        out.extend(16u16.to_le_bytes());
        out.extend(b"data");
        out.extend(data_len.to_le_bytes());
        for s in samples {
            let v = (s * f64::from(i16::MAX)).round() as i16;
            for _ in 0..channels {
                out.extend(v.to_le_bytes());
            }
        }
        let path = temp_path(name);
        std::fs::write(&path, out).unwrap();
        path.to_string_lossy().into_owned()
    }

    fn reference_tone() -> String {
        let rate = 48_000;
        let amplitude = 10f64.powf(-23.0 / 20.0);
        let samples: Vec<f64> = (0..rate * 10)
            .map(|i| amplitude * (2.0 * PI * 1000.0 * f64::from(i) / f64::from(rate)).sin())
            .collect();
        write_wav("tone.wav", rate, 2, &samples)
    }

    /// The HLS fixture joined the way a SoundCloud download is.
    fn joined_hls() -> String {
        let mut joined = std::fs::read(fixture("hls_init.mp4")).unwrap();
        for i in 0..3 {
            joined.extend(std::fs::read(fixture(&format!("hls_seg{i}.m4s"))).unwrap());
        }
        let path = temp_path("hls.m4a");
        std::fs::write(&path, joined).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn measures_a_reference_tone() {
        // EBU Tech 3341 case 1: stereo 1 kHz sine at -23 dBFS reads -23 LUFS.
        let r = measure_loudness(reference_tone(), new_loudness_job());
        let lufs = r.lufs.expect("measured");
        assert!((lufs + 23.0).abs() < 0.3, "{lufs}");
        assert!(!r.cancelled);
        assert_eq!(r.message, None);
    }

    #[test]
    fn measures_every_fixture() {
        // References from: ffmpeg -nostats -i <file> -af ebur128 -f null - 2>&1 | grep ' I:'
        let cases = [
            (fixture("tagged.mp3"), -22.0),
            (fixture("tagged.flac"), -21.6),
            (fixture("tagged.m4a"), -21.6),
            (fixture("dash.m4a"), -21.8),
            (fixture("demo_3.wav"), -21.6),
            (joined_hls(), -21.8),
        ];
        for (path, expected) in cases {
            let r = measure_loudness(path.clone(), new_loudness_job());
            let lufs = r.lufs.unwrap_or_else(|| panic!("{path}: {:?}", r.message));
            assert!((lufs - expected).abs() < 1.0, "{path}: {lufs}");
        }
    }

    /// tagged.mp3 with its ID3v2 tag replaced by one padded past 1 MB, like
    /// an MP3 with a big embedded cover.
    fn mp3_with_big_tag() -> String {
        let mp3 = std::fs::read(fixture("tagged.mp3")).unwrap();
        assert_eq!(&mp3[..3], b"ID3");
        let syncsafe = |b: &[u8]| b.iter().fold(0usize, |acc, &x| (acc << 7) | x as usize);
        let audio = &mp3[10 + syncsafe(&mp3[6..10])..];
        let padding = 1_500_000usize;
        let mut out = b"ID3\x03\x00\x00".to_vec();
        out.extend((0..4).rev().map(|i| ((padding >> (7 * i)) & 0x7f) as u8));
        out.extend(std::iter::repeat_n(0u8, padding));
        out.extend(audio);
        let path = temp_path("big-tag.mp3");
        std::fs::write(&path, out).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn measures_an_mp3_with_a_tag_over_one_megabyte() {
        let r = measure_loudness(mp3_with_big_tag(), new_loudness_job());
        let lufs = r.lufs.unwrap_or_else(|| panic!("{:?}", r.message));
        assert!((lufs + 22.0).abs() < 1.0, "{lufs}");
    }

    #[test]
    fn fails_on_garbage() {
        let r = measure_loudness(fixture("broken.mp3"), new_loudness_job());
        assert_eq!(r.lufs, None);
        assert!(!r.cancelled);
        assert!(!r.message.unwrap_or_default().is_empty());
    }

    #[test]
    fn fails_on_silence() {
        let path = write_wav("silence.wav", 48_000, 2, &vec![0.0; 96_000]);
        let r = measure_loudness(path, new_loudness_job());
        assert_eq!(r.lufs, None);
        assert!(!r.message.unwrap_or_default().is_empty());
    }

    #[test]
    fn missing_file_fails() {
        let r = measure_loudness("/nonexistent/owntune.mp3".into(), new_loudness_job());
        assert_eq!(r.lufs, None);
        assert!(!r.cancelled);
        assert!(!r.message.unwrap_or_default().is_empty());
    }

    #[test]
    fn cancelled_job_stops() {
        let job = new_loudness_job();
        cancel_loudness(job);
        let r = measure_loudness(fixture("tagged.flac"), job);
        assert!(r.cancelled);
        assert_eq!(r.lufs, None);

        let later = measure_loudness(fixture("tagged.flac"), new_loudness_job());
        assert!(!later.cancelled);
        assert!(later.lufs.is_some());
    }
}
