import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/retroshare_service.dart' as mobile_service;
import 'package:retroshare/apiUtils/stay_logged_in.dart';
import 'package:retroshare/provider/auth.dart';

/// iOS: the core runs inside the app and there is no Quit. Logging out
/// forgets the password kept on this device, starts the core again without
/// any node logged in, and goes back to the start of the app, where another
/// node can be chosen.
Future<void> confirmAndLogOut(BuildContext context) async {
  final logOut = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'RetroShare stops for this node: your friends cannot reach you '
          'until you log in again. The password kept on this device, if '
          'any, is forgotten.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      );
    },
  );
  if (logOut != true || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final account =
      Provider.of<AccountCredentials>(context, listen: false).loggedinAccount;
  if (account != null) await forgetPassword(account.locationId);

  try {
    await mobile_service.RsServiceControl.restartRetroshare();
  } catch (e) {
    debugPrint('Log out: could not restart the core: $e');
  }
  await navigator.pushNamedAndRemoveUntil('/', (_) => false);
}
