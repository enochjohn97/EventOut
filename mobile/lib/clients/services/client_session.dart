import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../models/client_model.dart';

/// Holds the organizer (client) Bearer token in memory and secure storage.
///
/// Tokens live under their own keys (`client_auth_token`) so a client session
/// never overwrites — or is wiped by — the attendee Google session.
class ClientSession {
  ClientSession._();

  static String? _token;
  static String? get token => _token;

  static final Dio _dio = ApiClient().dio;

  static Future<void> load() async {
    _token = await SecureStorage.getClientToken();
  }

  static Future<void> save(String token, ClientModel client) async {
    _token = token;
    await SecureStorage.saveClientToken(token);
    await SecureStorage.saveClientUser(client.toJson());
  }

  static Future<void> clear() async {
    _token = null;
    await SecureStorage.clearClientSession();
  }

  /// Headers for an authenticated client call. Any call made with these is
  /// flagged so a 401 can never trigger the attendee Google re-auth flow.
  static Map<String, dynamic> headers({bool json = true}) => {
    if (json) 'Content-Type': 'application/json',
    if ((_token ?? '').isNotEmpty) 'Authorization': 'Bearer $_token',
    // Some shared hosts strip the Authorization header; the API also reads
    // this fallback header, so sending both keeps the session working.
    if ((_token ?? '').isNotEmpty) 'X-Access-Token': _token,
  };

  static Map<String, dynamic> requestExtra({bool retry = false}) => {
    'skipAuthRecovery': true,
    if (retry) '_clientRetried': true,
  };

  static Future<bool>? _refreshing;

  /// Exchanges the current access token for a fresh one.
  ///
  /// Client access tokens expire after an hour (same policy as the web
  /// portal), which is too short for a phone that is opened at a venue all
  /// evening. This silently extends the session instead of forcing another
  /// email OTP. Returns true when a new token was stored.
  ///
  /// Only one refresh runs at a time: the dashboard fires several authenticated
  /// requests in parallel, and the server keeps a single active token per
  /// account — concurrent refreshes would invalidate each other's token and
  /// surface as "Unauthorized" even though the organizer was signed in.
  static Future<bool> refresh() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _refreshOnce();
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  static Future<bool> _refreshOnce() async {
    final current = _token ?? await SecureStorage.getClientToken();
    if (current == null || current.isEmpty) return false;
    try {
      final response = await _dio.post(
        '/clients/refresh-session',
        options: Options(
          headers: {'Authorization': 'Bearer $current'},
          extra: {'skipAuthRecovery': true},
        ),
      );
      final data = response.data;
      if (data is! Map) return false;
      if (data['success'] != true) return false;
      final newToken = data['token']?.toString();
      if (newToken == null || newToken.isEmpty) return false;
      _token = newToken;
      await SecureStorage.saveClientToken(newToken);
      final user = data['user'];
      if (user is Map) {
        await SecureStorage.saveClientUser(Map<String, dynamic>.from(user));
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
