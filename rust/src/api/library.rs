use std::fs::File;
use std::io::{self, BufReader};
use std::path::Path;

use lofty::file::{AudioFile, FileType, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::tag::{Accessor, ItemKey, Tag};

/// Outcome of reading one audio file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadStatus {
    Ok,
    /// The file is valid audio, but in a format owntune does not import.
    Unsupported,
    /// The file is missing, unreadable or not valid audio.
    Unreadable,
}

/// Embedded cover art, ready to be cached by the app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoverArt {
    pub data: Vec<u8>,
    /// `"jpg"` or `"png"`.
    pub extension: String,
    /// BLAKE3 hash of `data`, hex encoded.
    pub hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackInfo {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<u32>,
    pub duration_ms: u64,
    /// BLAKE3 hash of the whole file, hex encoded.
    pub content_hash: String,
    pub cover: Option<CoverArt>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadResult {
    pub status: ReadStatus,
    pub track: Option<TrackInfo>,
    pub message: Option<String>,
}

impl ReadResult {
    fn unreadable(message: String) -> Self {
        Self {
            status: ReadStatus::Unreadable,
            track: None,
            message: Some(message),
        }
    }
}

/// Reads tags, duration, content hash and cover art of one audio file.
/// Never panics; every failure is reported through `status` and `message`.
pub fn read_track(path: String) -> ReadResult {
    let path = Path::new(&path);

    let tagged = match lofty::read_from_path(path) {
        Ok(tagged) => tagged,
        Err(e) => return ReadResult::unreadable(e.to_string()),
    };

    let file_type = tagged.file_type();
    if !is_supported(file_type) {
        return ReadResult {
            status: ReadStatus::Unsupported,
            track: None,
            message: Some(format!("Unsupported audio format: {file_type:?}")),
        };
    }

    let content_hash = match hash_file(path) {
        Ok(hash) => hash,
        Err(e) => return ReadResult::unreadable(e.to_string()),
    };

    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());
    let duration_ms = u64::try_from(tagged.properties().duration().as_millis()).unwrap_or(u64::MAX);

    let track = TrackInfo {
        title: tag.and_then(|t| clean(t.title())),
        artist: tag.and_then(|t| clean(t.artist())),
        album: tag.and_then(|t| clean(t.album())),
        album_artist: tag.and_then(|t| clean(t.get_string(ItemKey::AlbumArtist))),
        genre: tag.and_then(|t| clean(t.genre())),
        track_number: tag.and_then(|t| t.track()),
        disc_number: tag.and_then(|t| t.disk()),
        year: tag.and_then(|t| t.date()).map(|d| u32::from(d.year)),
        duration_ms,
        content_hash,
        cover: tag.and_then(cover_of),
    };

    ReadResult {
        status: ReadStatus::Ok,
        track: Some(track),
        message: None,
    }
}

fn is_supported(file_type: FileType) -> bool {
    matches!(
        file_type,
        FileType::Mpeg | FileType::Mp4 | FileType::Aac | FileType::Flac | FileType::Wav
    )
}

/// Trims the value; empty or whitespace-only strings become `None`.
fn clean<S: AsRef<str>>(value: Option<S>) -> Option<String> {
    value
        .map(|s| s.as_ref().trim().to_owned())
        .filter(|s| !s.is_empty())
}

fn hash_file(path: &Path) -> io::Result<String> {
    let mut hasher = blake3::Hasher::new();
    hasher.update_reader(BufReader::new(File::open(path)?))?;
    Ok(hasher.finalize().to_hex().to_string())
}

/// Front cover if present, otherwise the first picture. Pictures that are
/// neither JPEG nor PNG are skipped.
fn cover_of(tag: &Tag) -> Option<CoverArt> {
    let pictures = tag.pictures();
    let picture = pictures
        .iter()
        .find(|p| p.pic_type() == PictureType::CoverFront)
        .or_else(|| pictures.first())?;
    cover_from(picture)
}

fn cover_from(picture: &Picture) -> Option<CoverArt> {
    let extension = match picture.mime_type()? {
        MimeType::Jpeg => "jpg",
        MimeType::Png => "png",
        _ => return None,
    };
    let data = picture.data().to_vec();
    let hash = blake3::hash(&data).to_hex().to_string();
    Some(CoverArt {
        data,
        extension: extension.to_owned(),
        hash,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../test/fixtures/audio/");

    fn read(name: &str) -> ReadResult {
        read_track(format!("{FIXTURES}{name}"))
    }

    fn track(name: &str) -> TrackInfo {
        let r = read(name);
        assert_eq!(r.status, ReadStatus::Ok, "{name}: {:?}", r.message);
        r.track.expect("track present when status is Ok")
    }

    #[test]
    fn tagged_mp3_reads_all_fields() {
        let t = track("tagged.mp3");
        assert_eq!(t.title.as_deref(), Some("After the Rain"));
        assert_eq!(t.artist.as_deref(), Some("Juno Vale"));
        assert_eq!(t.album.as_deref(), Some("Paper Lanterns"));
        assert_eq!(t.album_artist.as_deref(), Some("Juno Vale"));
        assert_eq!(t.genre.as_deref(), Some("Indie Folk"));
        assert_eq!(t.track_number, Some(2));
        assert_eq!(t.disc_number, Some(1));
        assert_eq!(t.year, Some(2021));
        // The fixture is 1 s of audio; lofty reports the MP3 frame count
        // (1152 ms), which includes the encoder delay and padding frames.
        assert!((900..=1200).contains(&t.duration_ms), "{}", t.duration_ms);
        assert_eq!(t.content_hash.len(), 64);
        let cover = t.cover.expect("cover");
        assert_eq!(cover.extension, "png");
        assert!(!cover.data.is_empty());
        assert_eq!(cover.hash.len(), 64);
    }

    #[test]
    fn flac_cover_is_jpeg() {
        let t = track("tagged.flac");
        assert_eq!(t.title.as_deref(), Some("Blue Hour"));
        assert_eq!(t.cover.expect("cover").extension, "jpg");
    }

    #[test]
    fn m4a_reads_tags_without_cover() {
        let t = track("tagged.m4a");
        assert_eq!(t.title.as_deref(), Some("Amber Lights"));
        assert_eq!(t.artist.as_deref(), Some("Neon Harbor"));
        assert_eq!(t.album.as_deref(), Some("Velvet Hours"));
        assert_eq!(t.track_number, Some(3));
        assert_eq!(t.year, Some(2021));
        assert!(t.cover.is_none());
    }

    #[test]
    fn untagged_wav_has_no_tags() {
        let t = track("demo_3.wav");
        assert_eq!(t.title, None);
        assert_eq!(t.artist, None);
        assert_eq!(t.album, None);
        assert!(t.cover.is_none());
    }

    #[test]
    fn unicode_tags_survive() {
        let t = track("unicode.mp3");
        assert_eq!(t.title.as_deref(), Some("Grüße aus Köln"));
        assert_eq!(t.artist.as_deref(), Some("Ärzte & Söhne"));
    }

    #[test]
    fn ogg_is_unsupported() {
        let r = read("evening-walk.ogg");
        assert_eq!(r.status, ReadStatus::Unsupported);
        assert!(r.track.is_none());
        let msg = r.message.expect("message");
        assert!(
            msg.contains("ogg") || msg.contains("Vorbis"),
            "unexpected message: {msg}"
        );
    }

    #[test]
    fn broken_file_is_unreadable() {
        let r = read("broken.mp3");
        assert_eq!(r.status, ReadStatus::Unreadable);
        assert!(r.track.is_none());
        assert!(r.message.is_some());
    }

    #[test]
    fn missing_file_is_unreadable() {
        let r = read("does-not-exist.mp3");
        assert_eq!(r.status, ReadStatus::Unreadable);
        assert!(r.track.is_none());
        assert!(r.message.is_some());
    }

    #[test]
    fn same_bytes_same_hash() {
        let a = track("tagged.mp3");
        let b = track("tagged.mp3");
        assert_eq!(a.content_hash, b.content_hash);
        assert_ne!(a.content_hash, track("unicode.mp3").content_hash);
    }
}
