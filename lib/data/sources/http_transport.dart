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
  /// [OnlineError] on a non-200 status or when the network is unreachable.
  Future<Map<String, Object?>> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers,
  });

  /// GETs [url]; the caller checks the status and reads (or cancels) the
  /// body stream. Fails with an [OnlineError] when the network is
  /// unreachable.
  Future<HttpBody> get(Uri url, {Map<String, String> headers});
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
  }) => _guard(() async {
    final req = await _client.postUrl(url);
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode != 200) {
      throw OnlineError("YouTube didn't answer: HTTP ${res.statusCode}");
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw _changed;
    }
    if (json is! Map<String, Object?>) throw _changed;
    return json;
  });

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

  static const _changed = OnlineError(
    'YouTube changed something; owntune needs an update',
  );

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
