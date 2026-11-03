import 'package:flutter/foundation.dart';
import '../services/app_config_service.dart';
import '../services/google_auth_service.dart';

class AppConfigProvider extends ChangeNotifier {
  bool isLoaded = false;
  bool isLoading = false;
  String? snackbar;
  String googleClientId = '';
  String mapsApiKey = '';
  String paystackPublicKey = '';
  String paystackMode = '';
  bool paystackIsTestMode = false;
  String appUrl = '';

  /// In-flight load, so concurrent callers (main + splash) share one request
  /// instead of the second one returning before config is actually ready.
  Future<void>? _inflight;

  Future<void> load({bool force = false}) async {
    if (isLoaded && !force) return;
    if (_inflight != null) return _inflight!;
    final future = _load(force: force);
    _inflight = future;
    try {
      await future;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _load({required bool force}) async {
    if ((isLoaded && !force) || isLoading) return;
    isLoading = true;
    snackbar = null;
    notifyListeners();
    try {
      await GoogleAuthService.configure();
      final config = await AppConfigService.load();
      googleClientId = config.googleClientId;
      mapsApiKey = config.mapsApiKey;
      paystackPublicKey = config.paystackPublicKey;
      paystackMode = config.paystackMode;
      paystackIsTestMode = config.paystackIsTestMode;
      appUrl = config.appUrl;
      if (googleClientId.isEmpty) {
        // We no longer rely on the server's googleClientId for mobile sign-in.
        debugPrint(
          'Server googleClientId is empty, but continuing with native config.',
        );
      }
      isLoaded = true;
    } catch (e) {
      snackbar = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
