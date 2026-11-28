import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:retroshare/apiUtils/mobile_push.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

// MobileLink: the phone asks the friends that run it to spare its battery
// and mobile data. Such a friend sends it no search request and only the
// tunnel requests for its own identities; while the app is in background it
// also keeps the lobby traffic for later and stops the periodic heartbeat
// and sync. Every rs-mobile node is a phone; a friend without MobileLink sees
// no change.

/// The token of the logged-in account, for the calls made when the app goes
/// to the background or comes back.
AuthToken? _token;

/// Tells the core that it runs on a phone. Called at each login. Errors are
/// logged, never thrown: a libretroshare without MobileLink answers an error,
/// and the app works as before.
Future<void> applyPhoneMode(AuthToken token) async {
  _token = token;
  try {
    await rsApiCall(
      '/rsMobileLink/setPhoneMode',
      authToken: token,
      params: {'phone': true},
    );
    debugPrint('MobileLink: phone mode on');
    await applyPushRegistration(token);
  } catch (error) {
    debugPrint('MobileLink: /rsMobileLink/setPhoneMode failed: $error');
  }
}

/// Tells the core whether the app is in background. Errors are logged.
Future<void> setPhoneQuiet(bool quiet) async {
  final token = _token;
  if (token == null) return;
  try {
    await rsApiCall(
      '/rsMobileLink/setQuiet',
      authToken: token,
      params: {'quiet': quiet},
    );
    debugPrint('MobileLink: ${quiet ? 'quiet' : 'active'}');
  } catch (error) {
    debugPrint('MobileLink: /rsMobileLink/setQuiet failed: $error');
  }
}

/// Puts the core in quiet mode while the app is in background (screen off
/// included), and back to active when the app shows again.
class MobileLinkLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(setPhoneQuiet(false));
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(setPhoneQuiet(true));
      case AppLifecycleState.inactive:
        // A passing state (notification shade, app switcher): no change.
        break;
    }
  }
}
