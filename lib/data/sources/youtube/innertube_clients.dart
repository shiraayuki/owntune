/// Every value that identifies owntune's YouTube clients lives here, so a
/// change on YouTube's side is a one-file fix. Values follow yt-dlp
/// (`yt_dlp/extractor/youtube/_base.py`, `INNERTUBE_CLIENTS`); when YouTube
/// breaks a client, compare with yt-dlp's current defaults
/// (`_DEFAULT_CLIENTS`, `_DEFAULT_JSLESS_CLIENTS`).
///
/// `tool/record_online_fixtures.sh` uses the same values.
library;

/// Locale sent with every request.
const innertubeLanguage = 'en';
const innertubeRegion = 'US';

/// YouTube Music search (songs).
final musicSearchUrl = Uri.parse(
  'https://music.youtube.com/youtubei/v1/search?prettyPrint=false',
);
const musicClientName = 'WEB_REMIX';
const musicClientVersion = '1.20260707.12.00';

/// The "Songs" filter of YouTube Music search.
const musicSongsFilter = 'EgWKAQIIAWoKEAoQAxAEEAkQBQ==';

/// YouTube search (videos).
final videoSearchUrl = Uri.parse(
  'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
);
const webClientName = 'WEB';
const webClientVersion = '2.20260708.00.00';

/// The "Videos" filter of YouTube search.
const videoFilter = 'EgIQAfABAQ==';

/// Player: the visionOS client gets direct audio URLs without PO token or
/// JavaScript challenges (yt-dlp's `_DEFAULT_JSLESS_CLIENTS`). It needs a
/// visitorData, else YouTube answers "Sign in to confirm you're not a bot".
final playerUrl = Uri.parse(
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
);
const playerOrigin = 'https://www.youtube.com';
const visionClientName = 'VISIONOS';
const visionClientId = '101';
const visionClientVersion = '1.02';
const visionUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';
const visionDeviceMake = 'Apple';
const visionDeviceModel = 'RealityDevice17,1';
const visionOsName = 'visionOS';
const visionOsVersion = '26.5.23O471';

/// itag of the AAC audio stream (M4A, about 128 kbps).
const m4aAudioItag = 140;
