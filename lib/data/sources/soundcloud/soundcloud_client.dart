import 'dart:async';
import 'dart:convert';

import 'package:owntune/data/sources/http_transport.dart';
import 'package:owntune/data/sources/online_source.dart';
import 'package:owntune/data/sources/soundcloud/client_id_store.dart';
import 'package:owntune/data/sources/soundcloud/soundcloud_api.dart';

/// The SoundCloud web API calls owntune makes. Finds the `client_id` the web
/// app uses (in its scripts) and keeps it; when the API refuses it, scrapes a
/// new one once and repeats the request once.
class SoundcloudClient {
  SoundcloudClient(this._http, this._store);

  final HttpTransport _http;
  final SoundcloudClientIdStore _store;

  String? _clientId;

  /// The running read or scrape, shared by calls that wait for the id.
  Future<String>? _pending;

  Future<Map<String, Object?>> search(String query) =>
      _api(searchPath, {queryParam: query, limitParam: searchLimit});

  Future<Map<String, Object?>> track(String id) => _api(trackPath(id), {});

  /// What a pasted SoundCloud link points to: a track, a playlist, a user.
  Future<Map<String, Object?>> resolveUrl(Uri url) =>
      _api(resolvePath, {urlParam: url.toString()});

  /// Where the short link [url] redirects to.
  Future<Uri> finalUrl(Uri url) => _http.finalUrl(url);

  /// The media playlist URL that [transcodingUrl] points to.
  Future<Uri> streamUrl(Uri transcodingUrl, String trackAuthorization) =>
      _withClientId((id) async {
        final json = await _http.getJson(
          transcodingUrl.replace(
            queryParameters: {
              ...transcodingUrl.queryParameters,
              clientIdParam: id,
              trackAuthorizationParam: trackAuthorization,
            },
          ),
          headers: _headers,
          service: soundcloudService,
        );
        final url = json['url'];
        if (url is! String) throw changedError(soundcloudService);
        return Uri.parse(url);
      });

  /// GETs [url] as text (the home page, a script, a media playlist).
  Future<String> text(Uri url) async {
    final res = await _http.get(url, headers: _headers);
    if (res.statusCode != 200) {
      unawaited(res.stream.drain<void>().catchError((_) {}));
      throw HttpStatusError(soundcloudService, res.statusCode);
    }
    return const Utf8Decoder(allowMalformed: true).bind(res.stream).join();
  }

  static const _headers = {'User-Agent': soundcloudUserAgent};

  Future<Map<String, Object?>> _api(String path, Map<String, String> params) =>
      _withClientId(
        (id) => _http.getJson(
          Uri.https(apiHost, path, {
            ...params,
            clientIdParam: id,
            localeParam: locale,
          }),
          headers: _headers,
          service: soundcloudService,
        ),
      );

  /// Runs [call] with the client_id; if the API says the id is stale,
  /// scrapes a new one and runs it once more.
  Future<T> _withClientId<T>(Future<T> Function(String id) call) async {
    final id = await _currentId();
    try {
      return await call(id);
    } on HttpStatusError catch (e) {
      if (!staleClientIdStatuses.contains(e.statusCode)) rethrow;
      return call(await _freshId(stale: id));
    }
  }

  Future<String> _currentId() async {
    final cached = _clientId;
    if (cached != null) return cached;
    return _shared(() async => await _store.read() ?? await _scrape());
  }

  Future<String> _freshId({required String stale}) async {
    // Another call may have replaced the stale id already.
    final cached = _clientId;
    if (cached != null && cached != stale) return cached;
    return _shared(_scrape);
  }

  Future<String> _shared(Future<String> Function() run) => _pending ??= run()
      .then((id) => _clientId = id)
      .whenComplete(() => _pending = null);

  /// Reads the `client_id` from the web app's scripts, last script first.
  Future<String> _scrape() async {
    final home = await text(soundcloudHomeUrl);
    final scripts = [
      for (final m in scriptSrcPattern.allMatches(home)) m.group(1)!,
    ].reversed;
    for (final src in scripts) {
      final String script;
      try {
        script = await text(Uri.parse(src));
      } on HttpStatusError {
        continue; // this script is gone; the id may be in another one
      }
      final match = clientIdPattern.firstMatch(script);
      if (match == null) continue;
      final id = match.group(1)!;
      try {
        await _store.write(id);
      } on Object {
        // Not cached; the next start scrapes again.
      }
      return id;
    }
    throw changedError(soundcloudService);
  }
}
