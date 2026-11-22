import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Error of the backend: `{ error, message }` with the HTTP status. The app shows the
/// text of the code in its language (errorText in format.dart).
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Where the app keeps the session token: the encrypted storage of the system
class TokenStore {
  const TokenStore();

  static const _key = 'session_token';
  static const _storage = FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String? token) => token == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);
}

/// HTTP client of the platform API.
///
/// On the web the app is served by the backend: same origin, the session is an
/// HttpOnly cookie and the browser sends it by itself. On Android the session is a
/// bearer token kept in the encrypted storage of the system.
class ApiClient {
  ApiClient(this.baseUrl, this._token, {http.Client? client, this.store = const TokenStore(), this.web = kIsWeb})
      : _http = client ?? http.Client();

  static const _serverKey = 'server_url';

  /// Address of the platform, e.g. https://tracking.example.com (no trailing slash)
  String baseUrl;
  String? _token;
  final http.Client _http;
  final TokenStore store;

  /// Browser: cookie session, no token to keep
  final bool web;

  /// Client type for the backend: different session lifetimes and transport
  String get clientType => web ? 'web' : 'app';

  static Future<ApiClient> create() async {
    if (kIsWeb) {
      // Development override (flutter run -d chrome --dart-define=API_URL=...)
      const override = String.fromEnvironment('API_URL');
      return ApiClient(override.isNotEmpty ? override : Uri.base.origin, null);
    }
    final prefs = await SharedPreferences.getInstance();
    const store = TokenStore();
    return ApiClient(prefs.getString(_serverKey) ?? '', await store.read());
  }

  bool get hasServer => baseUrl.isNotEmpty;
  String? get token => _token;

  Future<void> setServer(String url) async {
    baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, baseUrl);
  }

  /// Stores the token of the app sessions (the backend rotates it at every stage)
  Future<void> setToken(String? token) async {
    if (web) return;
    _token = token;
    await store.write(token);
  }

  Map<String, String> get authHeaders => {if (_token != null) 'authorization': 'Bearer $_token'};

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);

  Future<dynamic> get(String path, [Map<String, String>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  /// A file of the server (exports): its bytes and the name of the content-disposition
  Future<({Uint8List bytes, String name})> download(String path, [Map<String, String>? query]) async {
    final response = await _request('GET', path, query: query);
    final disposition = response.headers['content-disposition'] ?? '';
    final name = RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1);
    return (bytes: response.bodyBytes, name: Uri.decodeComponent(name ?? path.split('/').last));
  }

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final response = await _request(method, path, query: query, body: body);
    return response.body.isEmpty ? null : _decode(response.body);
  }

  Future<http.Response> _request(String method, String path, {Map<String, String>? query, Object? body}) async {
    final request = http.Request(method, uri(path, query));
    request.headers.addAll(authHeaders);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 30)));
    } catch (_) {
      throw ApiException(0, 'network', 'Server unreachable');
    }
    if (response.statusCode >= 400) {
      final dynamic data = response.body.isEmpty ? null : _decode(response.body);
      final map = data is Map ? data : const {};
      throw ApiException(
        response.statusCode,
        map['error']?.toString() ?? 'http_${response.statusCode}',
        map['message']?.toString() ?? 'HTTP ${response.statusCode}',
      );
    }
    return response;
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
