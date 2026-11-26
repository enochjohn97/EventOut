import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/client_model.dart';
import 'client_session.dart';

/// Result of the first step of a client login: the password was accepted and
/// a 6-digit code is on its way to the account email.
class ClientLoginChallenge {
  final int authId;
  final String email;

  const ClientLoginChallenge({required this.authId, required this.email});
}

/// Email/password authentication for the organizer (client) portal.
///
/// There are deliberately no social sign-in options here: clients are
/// business accounts on the web portal, which only accepts email + password
/// (plus the emailed login code).
class ClientAuthService {
  static final Dio _dio = ApiClient().dio;

  static Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const ApiException(
      'EventOut server returned an invalid response. Please try again.',
    );
  }

  /// Step 1 — verify the password and trigger the login code email.
  static Future<ClientLoginChallenge> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/client/login',
        data: {'email': email.trim(), 'password': password, 'intent': 'client'},
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Login failed. Please try again.',
        );
      }
      final authId = int.tryParse(data['auth_id']?.toString() ?? '');
      final otpRequired =
          data['otp_required'] == true ||
          data['next_step']?.toString() == 'otp_verification';
      if (!otpRequired) {
        // Defensive: if the backend ever completes login directly, surface a
        // clear message instead of silently dropping the response.
        throw const ApiException(
          'This account needs a verification code. Please try again.',
        );
      }
      if (authId == null || authId <= 0) {
        throw const ApiException(
          'Login could not be completed. Please try again.',
        );
      }
      return ClientLoginChallenge(
        authId: authId,
        email: data['user_email']?.toString() ?? email.trim(),
      );
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not sign you in. Please try again.');
    }
  }

  /// Step 2 — exchange the emailed code for a session token.
  static Future<ClientModel> verifyLoginCode({
    required int authId,
    required String email,
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp',
        data: {
          'intent': 'client_login_otp',
          'auth_id': authId,
          'identity': email.trim(),
          'otp': code.trim(),
        },
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Invalid verification code.',
        );
      }
      final user = data['user'];
      if (user is! Map) {
        throw const ApiException('Login could not be completed.');
      }
      final client = ClientModel.fromJson(Map<String, dynamic>.from(user));
      final token = data['token']?.toString() ?? client.token;
      if (token == null || token.isEmpty) {
        throw const ApiException('Login could not be completed.');
      }
      await ClientSession.save(token, client);
      return client;
    } on DioException catch (error) {
      throw apiErrorFromDio(
        error,
        'Could not verify the code. Please try again.',
      );
    }
  }

  /// Creates a client account — the same request the web sign-up form sends.
  static Future<String> register({
    required String name,
    required String businessName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'name': name.trim(),
          'business_name': businessName.trim(),
          'email': email.trim(),
          'password': password,
          'role': 'client',
        },
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Could not create your account.',
        );
      }
      return data['message']?.toString() ??
          'Account created successfully! You may now log in.';
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not create your account.');
    }
  }

  /// Password recovery, step 1 — ask the server to email a reset code.
  /// Mirrors the web portal's "Forgot Password?" flow
  /// (`/api/auth/forgot-password.php`).
  static Future<String> requestPasswordReset(String email) async {
    try {
      final response = await _dio.post(
        '/auth/forgot-password',
        data: {'identity': email.trim(), 'email': email.trim()},
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Could not send the reset code.',
        );
      }
      return data['message']?.toString() ??
          'If an account exists with this email, you will receive a code shortly.';
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not send the reset code.');
    }
  }

  /// Password recovery, step 2 — verify the emailed code and return the reset
  /// token the server issues for the final step.
  static Future<String> verifyResetCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp',
        data: {
          'identity': email.trim(),
          'otp': code.trim(),
          'intent': 'password_reset',
        },
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Invalid verification code.',
        );
      }
      final token = data['reset_token']?.toString();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          'Your reset session expired. Request a new code.',
        );
      }
      return token;
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not verify the code.');
    }
  }

  /// Password recovery, step 3 — save the new password.
  static Future<String> resetPassword({
    required String resetToken,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/reset-password',
        data: {
          'reset_token': resetToken,
          'new_password': password,
          'password': password,
          'password_confirm': password,
        },
        options: Options(extra: ClientSession.requestExtra()),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Could not reset your password.',
        );
      }
      return data['message']?.toString() ??
          'Your password has been reset. You can now sign in.';
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not reset your password.');
    }
  }

  /// Re-reads the signed-in profile so web edits appear on the phone.
  static Future<ClientModel> fetchProfile() async {
    try {
      final response = await _dio.get(
        '/client/auth/check-session',
        queryParameters: {'portal': 'client'},
        options: Options(
          headers: ClientSession.headers(),
          extra: ClientSession.requestExtra(),
        ),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Session expired. Please sign in.',
        );
      }
      final user = data['user'];
      if (user is! Map) {
        throw const ApiException('Could not load your profile.');
      }
      return ClientModel.fromJson(Map<String, dynamic>.from(user));
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not load your profile.');
    }
  }

  /// Updates the client profile with the same fields the web portal saves.
  static Future<ClientModel> updateProfile(
    Map<String, String> fields, {
    String? profilePicPath,
    Map<String, String> kycFilePaths = const {},
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      final form = FormData();
      for (final entry in fields.entries) {
        form.fields.add(MapEntry(entry.key, entry.value.trim()));
      }
      if (profilePicPath != null && profilePicPath.isNotEmpty) {
        form.files.add(
          MapEntry('profile_pic', await MultipartFile.fromFile(profilePicPath)),
        );
      }

      const allowedKycFields = {
        'kyc_nin_file',
        'kyc_voter_card_file',
        'kyc_driver_license_file',
        'kyc_cac_file',
      };

      for (final entry in kycFilePaths.entries) {
        if (!allowedKycFields.contains(entry.key)) continue;
        if (entry.value.trim().isEmpty) continue;

        form.files.add(
          MapEntry(
            entry.key,
            await MultipartFile.fromFile(
              entry.value,
              filename: entry.value.replaceAll('\\', '/').split('/').last,
            ),
          ),
        );
      }

      // POST, not PUT: PHP only parses multipart bodies into $_POST for POST
      // requests, so a PUT would silently update nothing.
      final response = await _dio.post(
        '/clients/update-profile',
        data: form,
        options: Options(
          headers: ClientSession.headers(json: false),
          extra: ClientSession.requestExtra(),
        ),
        onSendProgress: onSendProgress,
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Could not update your profile.',
        );
      }
      final user = data['user'];
      if (user is! Map) {
        throw const ApiException('Could not update your profile.');
      }
      return ClientModel.fromJson(Map<String, dynamic>.from(user));
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not update your profile.');
    }
  }

  /// Permanently deletes the organizer account (the server cascades to the
  /// client profile, events, tickets and payment records).
  static Future<void> deleteAccount() async {
    try {
      final response = await _dio.post(
        '/clients/delete-profile',
        options: Options(
          headers: ClientSession.headers(),
          extra: {'skipAuthRecovery': true},
        ),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) {
        throw ApiException(
          data['message']?.toString() ?? 'Could not delete your account.',
        );
      }
      await ClientSession.clear();
    } on DioException catch (error) {
      throw apiErrorFromDio(error, 'Could not delete your account.');
    }
  }

  /// Revokes the token on the server; ignores failures so local sign-out
  /// always works (the token also expires on its own).
  static Future<void> logout() async {
    final token = ClientSession.token;
    if (token == null || token.isEmpty) {
      await ClientSession.clear();
      return;
    }
    try {
      await _dio.post(
        '/clients/logout',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          extra: {'skipAuthRecovery': true},
        ),
      );
    } catch (_) {
      // Best-effort.
    } finally {
      await ClientSession.clear();
    }
  }
}
