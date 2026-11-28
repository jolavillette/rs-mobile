import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:retroshare/apiUtils/retroshare_service.dart' as mobile_service;

/// Android only: the core runs in a foreground service that outlives the
/// activity, so closing the app leaves RetroShare running. This stops the
/// service, then closes the app. Opening the app starts it again.
Future<void> confirmAndQuit(BuildContext context) async {
  final quit = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Quit RetroShare?'),
        content: const Text(
          'RetroShare stops running in the background: your friends cannot '
          'reach you and nothing is transferred until you open it again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quit'),
          ),
        ],
      );
    },
  );
  if (quit != true) return;

  // The service shuts the core down in its own process; the app does not
  // have to wait for it before closing.
  try {
    await mobile_service.RsServiceControl.stopRetroshare(wait: false);
  } catch (e) {
    debugPrint('Quit: could not stop the service: $e');
  }
  await SystemNavigator.pop();
}
