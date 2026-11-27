import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:retroshare/apiUtils/retroshare_service.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

// MobilePush: the phone gives its homes what they need to reach it through
// the platform's push service while the application is not running: the
// address the service gave this installation, and a key the homes seal the
// notifications with. The core passes it on to each home (rsMobilePush).

/// Hands the push registration of this installation to the core. Called at
/// each login. Errors are logged, never thrown: a libretroshare without
/// MobilePush answers an error, and the app works as before.
Future<void> applyPushRegistration(AuthToken token) async {
  if (!Platform.isIOS) return;
  try {
    final registration =
        await rsPlatform.invokeMapMethod<String, dynamic>('pushRegistration');
    final pushToken = registration?['token'];
    final key = registration?['key'];
    if (pushToken is! String || key is! String) {
      debugPrint('MobilePush: no push token on this installation');
      return;
    }
    final answer = await rsApiCall(
      '/rsMobilePush/setRegistration',
      authToken: token,
      params: {
        'registration': {
          'mProvider': registration?['provider'],
          'mToken': pushToken,
          'mTopic': registration?['topic'],
          'mKey': key,
        },
      },
    );
    debugPrint('MobilePush: registration given to the core: ${answer['retval']}');
  } catch (error) {
    debugPrint('MobilePush: /rsMobilePush/setRegistration failed: $error');
  }
}
