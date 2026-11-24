import 'package:flutter/foundation.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

// MobileLink: the phone asks the friends that run it to spare its battery
// and mobile data. Such a friend sends it no search request and only the
// tunnel requests for its own identities. Every rs-mobile node is a phone; a
// friend without MobileLink sees no change.

/// Tells the core that it runs on a phone. Called at each login. Errors are
/// logged, never thrown: a libretroshare without MobileLink answers an error,
/// and the app works as before.
Future<void> applyPhoneMode(AuthToken token) async {
  try {
    await rsApiCall(
      '/rsMobileLink/setPhoneMode',
      authToken: token,
      params: {'phone': true},
    );
    debugPrint('MobileLink: phone mode on');
  } catch (error) {
    debugPrint('MobileLink: /rsMobileLink/setPhoneMode failed: $error');
  }
}
