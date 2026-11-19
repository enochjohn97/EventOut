import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/secure_storage.dart';
import '../models/client_model.dart';
import '../services/client_auth_service.dart';
import '../services/client_session.dart';

enum ClientAuthStatus { unknown, unauthenticated, authenticated }

class ClientAuthProvider extends ChangeNotifier {
  ClientAuthStatus status = ClientAuthStatus.unknown;
  ClientModel? client;
  bool isLoading = false;
  String? error;
  bool sessionExpired = false;

  /// Login step 1 result — the code has been emailed.
  int? pendingAuthId;
  String? pendingEmail;
  String? notice;

  bool get awaitingCode => pendingAuthId != null;

  Future<void> bootstrap() async {
    isLoading = true;
    error = null;
    sessionExpired = false;
    notifyListeners();
    try {
      await ClientSession.load();
      final token = ClientSession.token;
      final cached = await SecureStorage.getClientUser();
      if (token == null || token.isEmpty) {
        client = null;
        status = ClientAuthStatus.unauthenticated;
        return;
      }
      if (cached != null) {
        // Paint the saved profile immediately, then confirm it with the API.
        client = ClientModel.fromJson(cached);
        status = ClientAuthStatus.authenticated;
        notifyListeners();
      }
      try {
        client = await ClientAuthService.fetchProfile();
        await SecureStorage.saveClientUser(client!.toJson());
        status = ClientAuthStatus.authenticated;
      } catch (e) {
        final expired = e is ApiException && e.unauthorized;
        if (expired) {
          final refreshed = await ClientSession.refresh();
          if (refreshed) {
            try {
              client = await ClientAuthService.fetchProfile();
              await SecureStorage.saveClientUser(client!.toJson());
              status = ClientAuthStatus.authenticated;
              return;
            } catch (_) {}
          }
          await ClientSession.clear();
          client = null;
          sessionExpired = true;
          status = ClientAuthStatus.unauthenticated;
        } else if (client == null) {
          // Offline with no cached profile: the cached copy check above did
          // not run, so treat it as unauthenticated rather than a crash.
          status = ClientAuthStatus.unauthenticated;
        }
      }
    } catch (_) {
      status = ClientAuthStatus.unauthenticated;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<ClientLoginChallenge> startLogin({
    required String email,
    required String password,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final challenge = await ClientAuthService.login(
        email: email,
        password: password,
      );
      pendingAuthId = challenge.authId;
      pendingEmail = challenge.email;
      return challenge;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyLoginCode(String code) async {
    final authId = pendingAuthId;
    final email = pendingEmail;
    if (authId == null || email == null) {
      error = 'Please sign in again.';
      notifyListeners();
      return false;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final signedIn = await ClientAuthService.verifyLoginCode(
        authId: authId,
        email: email,
        code: code,
      );
      client = signedIn;
      await SecureStorage.saveClientUser(signedIn.toJson());
      pendingAuthId = null;
      pendingEmail = null;
      sessionExpired = false;
      notice = 'Signed in successfully.';
      status = ClientAuthStatus.authenticated;
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> register({
    required String name,
    required String businessName,
    required String email,
    required String password,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final message = await ClientAuthService.register(
        name: name,
        businessName: businessName,
        email: email,
        password: password,
      );
      notice = message;
      return message;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void cancelCodeStep() {
    pendingAuthId = null;
    pendingEmail = null;
    error = null;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (status != ClientAuthStatus.authenticated) return;
    try {
      final fresh = await ClientAuthService.fetchProfile();
      client = fresh;
      await SecureStorage.saveClientUser(fresh.toJson());
      notifyListeners();
    } catch (_) {
      // Keep the last known profile; a hiccup must not log the organizer out.
    }
  }

  Future<bool> updateProfile(
    Map<String, String> fields, {
    String? profilePicPath,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final updated = await ClientAuthService.updateProfile(
        fields,
        profilePicPath: profilePicPath,
      );
      client = client == null
          ? updated
          : ClientModel.fromJson({
              ...updated.toJson(),
              // The update endpoint returns the profile row without the auth
              // e-mail; keep the verified address already on the device.
              'email': updated.email.isEmpty ? client!.email : updated.email,
              'token': client!.token,
            });
      await SecureStorage.saveClientUser(client!.toJson());
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAccount() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await ClientAuthService.deleteAccount();
      client = null;
      pendingAuthId = null;
      pendingEmail = null;
      sessionExpired = false;
      status = ClientAuthStatus.unauthenticated;
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await ClientAuthService.logout();
    client = null;
    error = null;
    sessionExpired = false;
    pendingAuthId = null;
    pendingEmail = null;
    status = ClientAuthStatus.unauthenticated;
    notifyListeners();
  }
}
