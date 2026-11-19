use std::fs::File;
use std::io::{self, BufReader};
use std::path::Path;

use lofty::config::WriteOptions;
use lofty::file::{AudioFile, FileType, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::tag::items::Timestamp;
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
    pub file_extension: String,
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
    pub duration_ms: u32,
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
    let duration_ms = u32::try_from(tagged.properties().duration().as_millis()).unwrap_or(u32::MAX);

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

/// The editable tag fields; `None` removes the item from the file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TagValues {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<u32>,
}

/// Writes `tags` into the primary tag of the file at `path` (created if
/// missing). The file is copied to `<stem>.part.<ext>` next to it, written
/// there and renamed over the original, so an interrupted write leaves the
/// original intact. Returns an error message, or `None` on success. Never
/// panics.
pub fn write_tags(path: String, tags: TagValues) -> Option<String> {
    let path = Path::new(&path);
    let part = match part_path(path) {
        Some(part) => part,
        None => return Some(format!("Not an audio file name: {}", path.display())),
    };
    let result = write_via(path, &part, &tags);
    if result.is_some() {
        let _ = std::fs::remove_file(&part);
    }
    result
}

/// `<dir>/<stem>.part.<ext>`; lofty picks the parser by extension.
fn part_path(path: &Path) -> Option<std::path::PathBuf> {
    let stem = path.file_stem()?.to_str()?;
    let ext = path.extension()?.to_str()?;
    Some(path.with_file_name(format!("{stem}.part.{ext}")))
}

fn write_via(path: &Path, part: &Path, tags: &TagValues) -> Option<String> {
    if let Err(e) = std::fs::copy(path, part) {
        return Some(e.to_string());
    }
    let mut tagged = match lofty::read_from_path(part) {
        Ok(tagged) => tagged,
        Err(e) => return Some(e.to_string()),
    };
    let tag_type = tagged.primary_tag_type();
    if tagged.tag(tag_type).is_none() {
        tagged.insert_tag(Tag::new(tag_type));
    }
    let Some(tag) = tagged.tag_mut(tag_type) else {
        return Some(format!("No {tag_type:?} tag in {}", path.display()));
    };
    apply(tag, tags);
    if let Err(e) = tagged.save_to_path(part, WriteOptions::default()) {
        return Some(e.to_string());
    }
    std::fs::rename(part, path).err().map(|e| e.to_string())
}

fn apply(tag: &mut Tag, tags: &TagValues) {
    match clean(tags.title.as_deref()) {
        Some(v) => tag.set_title(v),
        None => tag.remove_title(),
    }
    match clean(tags.artist.as_deref()) {
        Some(v) => tag.set_artist(v),
        None => tag.remove_artist(),
    }
    match clean(tags.album.as_deref()) {
        Some(v) => tag.set_album(v),
        None => tag.remove_album(),
    }
    match clean(tags.album_artist.as_deref()) {
        Some(v) => {
            tag.insert_text(ItemKey::AlbumArtist, v);
        }
        None => tag.remove_key(ItemKey::AlbumArtist),
    }
    match clean(tags.genre.as_deref()) {
        Some(v) => tag.set_genre(v),
        None => tag.remove_genre(),
    }
    match tags.track_number {
        Some(n) => tag.set_track(n),
        None => tag.remove_track(),
    }
    match tags.disc_number {
        Some(n) => tag.set_disk(n),
        None => tag.remove_disk(),
    }
    // Dart sends every field on each save; an unchanged year must not cut a
    // full date (e.g. 2003-04-01) down to the year.
    match tags.year.and_then(|y| u16::try_from(y).ok()) {
        Some(year) if tag.date().map(|d| d.year) == Some(year) => {}
        Some(year) => tag.set_date(Timestamp {
            year,
            ..Timestamp::default()
        }),
        None => {
            tag.remove_date();
            tag.remove_key(ItemKey::Year);
        }
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
        file_extension: extension.to_owned(),
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
        assert_eq!(cover.file_extension, "png");
        assert!(!cover.data.is_empty());
        assert_eq!(cover.hash.len(), 64);
    }

    #[test]
    fn flac_cover_is_jpeg() {
        let t = track("tagged.flac");
        assert_eq!(t.title.as_deref(), Some("Blue Hour"));
        assert_eq!(t.cover.expect("cover").file_extension, "jpg");
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

    use std::sync::atomic::{AtomicUsize, Ordering};

    /// A fresh copy of the fixture [name] in its own temp folder.
    fn copy_fixture(name: &str) -> std::path::PathBuf {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "owntune-write-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let ext = Path::new(name).extension().unwrap().to_str().unwrap();
        let target = dir.join(format!("copy.{ext}"));
        std::fs::copy(format!("{FIXTURES}{name}"), &target).unwrap();
        target
    }

    fn all_fields() -> TagValues {
        TagValues {
            title: Some("New Title".into()),
            artist: Some("New Artist".into()),
            album: Some("New Album".into()),
            album_artist: Some("New Album Artist".into()),
            genre: Some("Ambient".into()),
            track_number: Some(7),
            disc_number: Some(2),
            year: Some(1999),
        }
    }

    fn read_path(path: &Path) -> TrackInfo {
        let r = read_track(path.to_str().unwrap().to_owned());
        assert_eq!(r.status, ReadStatus::Ok, "{:?}", r.message);
        r.track.unwrap()
    }

    #[test]
    fn write_tags_round_trips_each_format() {
        for name in ["tagged.mp3", "tagged.m4a", "tagged.flac", "demo_3.wav"] {
            let path = copy_fixture(name);
            let error = write_tags(path.to_str().unwrap().to_owned(), all_fields());
            assert_eq!(error, None, "{name}");
            let t = read_path(&path);
            assert_eq!(t.title.as_deref(), Some("New Title"), "{name}");
            assert_eq!(t.artist.as_deref(), Some("New Artist"), "{name}");
            assert_eq!(t.album.as_deref(), Some("New Album"), "{name}");
            assert_eq!(
                t.album_artist.as_deref(),
                Some("New Album Artist"),
                "{name}"
            );
            assert_eq!(t.genre.as_deref(), Some("Ambient"), "{name}");
            assert_eq!(t.track_number, Some(7), "{name}");
            assert_eq!(t.disc_number, Some(2), "{name}");
            assert_eq!(t.year, Some(1999), "{name}");
        }
    }

    #[test]
    fn cleared_fields_are_removed() {
        let path = copy_fixture("tagged.mp3");
        let none = TagValues {
            title: None,
            artist: None,
            album: None,
            album_artist: None,
            genre: None,
            track_number: None,
            disc_number: None,
            year: None,
        };
        assert_eq!(write_tags(path.to_str().unwrap().to_owned(), none), None);
        let t = read_path(&path);
        assert_eq!(t.title, None);
        assert_eq!(t.artist, None);
        assert_eq!(t.album, None);
        assert_eq!(t.album_artist, None);
        assert_eq!(t.genre, None);
        assert_eq!(t.track_number, None);
        assert_eq!(t.disc_number, None);
        assert_eq!(t.year, None);
    }

    #[test]
    fn write_keeps_audio_and_cover() {
        for name in ["tagged.mp3", "tagged.flac"] {
            let path = copy_fixture(name);
            let before = read_path(&path);
            assert_eq!(
                write_tags(path.to_str().unwrap().to_owned(), all_fields()),
                None
            );
            let after = read_path(&path);
            assert!(
                before.duration_ms.abs_diff(after.duration_ms) <= 50,
                "{name}"
            );
            assert_eq!(
                before.cover.map(|c| c.hash),
                after.cover.map(|c| c.hash),
                "{name}"
            );
        }
    }

    #[test]
    fn write_reports_a_missing_file() {
        let error = write_tags(format!("{FIXTURES}does-not-exist.mp3"), all_fields());
        assert!(error.is_some());
    }

    #[test]
    fn no_part_file_is_left() {
        let path = copy_fixture("tagged.m4a");
        assert_eq!(
            write_tags(path.to_str().unwrap().to_owned(), all_fields()),
            None
        );
        let names: Vec<_> = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        assert_eq!(names, vec!["copy.m4a".to_owned()]);
    }

    #[test]
    fn an_unchanged_year_keeps_the_full_date() {
        let path = copy_fixture("tagged.mp3");
        let mut tagged = lofty::read_from_path(&path).unwrap();
        let tag = tagged.primary_tag_mut().unwrap();
        tag.set_date(Timestamp {
            year: 2003,
            month: Some(4),
            day: Some(1),
            ..Timestamp::default()
        });
        tagged.save_to_path(&path, WriteOptions::default()).unwrap();

        let tags = TagValues {
            genre: Some("Folk".into()),
            year: Some(2003),
            ..all_fields()
        };
        assert_eq!(write_tags(path.to_str().unwrap().to_owned(), tags), None);
        let date = lofty::read_from_path(&path)
            .unwrap()
            .primary_tag()
            .unwrap()
            .date()
            .unwrap();
        assert_eq!((date.year, date.month, date.day), (2003, Some(4), Some(1)));
    }
}
