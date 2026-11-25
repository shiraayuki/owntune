/// Every value that identifies owntune to SoundCloud lives here, so a change
/// on SoundCloud's side is a one-file fix: hosts, paths, query parameters,
/// the patterns that find the `client_id`, the presets and the artwork
/// sizes. `tool/record_online_fixtures.sh` uses the same values.
library;

/// Names SoundCloud in error messages and in the HTTP transport.
const soundcloudService = 'SoundCloud';

/// SoundCloud answers the web app's browser; this is a desktop Chrome.
const soundcloudUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// The web app; its scripts hold the `client_id`.
final soundcloudHomeUrl = Uri.parse('https://soundcloud.com/');

const apiHost = 'api-v2.soundcloud.com';
const searchPath = '/search/tracks';
String trackPath(String id) => '/tracks/$id';
const resolvePath = '/resolve';

const queryParam = 'q';
const limitParam = 'limit';
const urlParam = 'url';
const searchLimit = '20';
const localeParam = 'app_locale';
const locale = 'en';
const clientIdParam = 'client_id';
const trackAuthorizationParam = 'track_authorization';

/// The script tags of the home page, and the `client_id` in a script (the
/// same way yt-dlp finds it).
final scriptSrcPattern = RegExp(
  r'<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
);
final clientIdPattern = RegExp(r'client_id\s*:\s*"([A-Za-z0-9]{32})"');

/// The key of the cached `client_id` in `settings_entries`.
const clientIdSettingsKey = 'soundcloud_client_id';

/// Answers that mean the `client_id` is stale.
const staleClientIdStatuses = {401, 403};

/// The downloadable transcodings: unencrypted HLS of AAC in MP4, the better
/// preset first.
const hlsProtocol = 'hls';
const mp4MimePrefix = 'audio/mp4';
const aacPresets = [
  (preset: 'aac_160k', kbps: 160),
  (preset: 'aac_96k', kbps: 96),
];

/// Policies that never give the full track.
const previewPolicy = 'SNIP';
const blockedPolicy = 'BLOCK';

/// Artwork sizes: the result row and the cover written into the file.
const rowArtworkSize = 't300x300';
const coverArtworkSize = 't500x500';

/// The size SoundCloud's API names in `artwork_url` and `avatar_url`.
final artworkSizeSuffix = RegExp(r'-large(?=\.\w+(?:\?|$))');
