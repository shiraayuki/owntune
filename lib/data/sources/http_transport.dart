import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:owntune/data/sources/online_source.dart';

/// The response of a GET: status and body, streamed.
class HttpBody {
  const HttpBody(this.statusCode, this.stream);

  final int statusCode;
  final Stream<List<int>> stream;
}

/// The HTTP calls the online sources and the downloader need; tests replace
/// it with a fake.
abstract interface class HttpTransport {
  /// POSTs [body] as JSON and returns the decoded JSON object. Fails with an
  /// [OnlineError] on a non-200 status or when the network is unreachable;
  /// [service] names the source in the message.
  Future<Map<String, Object?>> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers,
    String service,
  });

  /// GETs [url] and returns the decoded JSON object. A non-200 status fails
  /// with an [HttpStatusError], a body that is not a JSON object with
  /// [changedError]; an unreachable network with an [OnlineError].
  Future<Map<String, Object?>> getJson(
    Uri url, {
    Map<String, String> headers,
    required String service,
  });

  /// GETs [url]; the caller checks the status and reads (or cancels) the
  /// body stream. Fails with an [OnlineError] when the network is
  /// unreachable.
  Future<HttpBody> get(Uri url, {Map<String, String> headers});

  /// The URL [url] ends at after following its redirects (at most five
  /// hops; the response bodies are not read). [url] itself when it does not
  /// redirect.
  Future<Uri> finalUrl(Uri url);
}

/// [HttpTransport] on `dart:io`. Every wait (connect, response headers,
/// each body chunk) is bounded, so a half-open connection after a network
/// switch or an iOS suspend ends as "No connection" instead of hanging.
class IoHttpTransport implements HttpTransport {
  IoHttpTransport({this.timeout = const Duration(seconds: 30)})
    : _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _client;

  /// The longest wait for response headers or the next body chunk.
  final Duration timeout;

  @override
  Future<Map<String, Object?>> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
    String service = 'YouTube',
  }) => _guard(() async {
    final req = await _client.postUrl(url);
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    return _readJson(res, service);
  });

  @override
  Future<Map<String, Object?>> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    required String service,
  }) => _guard(() async {
    final req = await _client.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    return _readJson(res, service);
  });

  Future<Map<String, Object?>> _readJson(
    HttpClientResponse res,
    String service,
  ) async {
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode != 200) throw HttpStatusError(service, res.statusCode);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw changedError(service);
    }
    if (json is! Map<String, Object?>) throw changedError(service);
    return json;
  }

  @override
  Future<HttpBody> get(Uri url, {Map<String, String> headers = const {}}) =>
      _guard(() async {
        final req = await _client.getUrl(url);
        headers.forEach(req.headers.set);
        final res = await req.close().timeout(timeout);
        return HttpBody(
          res.statusCode,
          res.timeout(
            timeout,
            onTimeout: (sink) {
              sink.addError(const OnlineError('No connection'));
              sink.close();
            },
          ),
        );
      });

  @override
  Future<Uri> finalUrl(Uri url) => _guard(() async {
    var current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final req = await _client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close().timeout(timeout);
      final location = res.headers.value(HttpHeaders.locationHeader);
      final redirects = res.isRedirect && location != null;
      // Cancelling the body closes the connection without reading it.
      unawaited(res.listen((_) {}).cancel());
      if (!redirects || hop == maxRedirects) return current;
      current = current.resolve(location);
    }
    return current;
  });

  /// The most redirects [finalUrl] follows.
  static const maxRedirects = 5;

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SocketException {
      throw const OnlineError('No connection');
    } on TimeoutException {
      throw const OnlineError('No connection');
    } on HttpException catch (e) {
      throw OnlineError('Connection failed: ${e.message}');
    }
  }
}
