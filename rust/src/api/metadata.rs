use lofty::file::FileType;

/// Audio formats owntune imports in M1, filtered by what lofty can read.
#[flutter_rust_bridge::frb(sync)]
pub fn supported_formats() -> Vec<String> {
    ["mp3", "m4a", "flac", "ogg", "wav"]
        .into_iter()
        .filter(|ext| FileType::from_ext(ext).is_some())
        .map(String::from)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supported_formats_lists_m1_formats_in_order() {
        assert_eq!(
            supported_formats(),
            vec!["mp3", "m4a", "flac", "ogg", "wav"]
        );
    }
}
