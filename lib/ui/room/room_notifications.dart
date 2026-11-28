import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

// Which lines of a room notify this phone while the application is not
// running. The notifications come from the phone's home nodes (MobilePush):
// the choice is sent to them, and a home notifies of a line only when its own
// rule and this choice both let it through.

/// Whether this platform gets its notifications from the home nodes.
bool get roomNotificationsAvailable => Platform.isIOS;

/// The values of RsMobilePushLobbyMode.
const int _all = 0;
const int _homeOnly = 1;
const int _none = 2;

const Map<int, (String, String)> _choices = {
  _all: ('All messages', 'Every message your home node lets through.'),
  _homeOnly: (
    'Announcements only',
    'Only what your home node itself writes in this room.'
  ),
  _none: ('None', 'Messages still wait for you in the room.'),
};

/// Lets the user choose which lines of room [lobbyId] notify.
Future<void> chooseRoomNotifications(
    BuildContext context, String lobbyId) async {
  final authToken =
      Provider.of<AccountCredentials>(context, listen: false).authtoken;
  if (authToken == null) return;
  final messenger = ScaffoldMessenger.of(context);

  var current = _all;
  try {
    final response = await rsApiCall(
      '/rsMobilePush/getLobbyPreferences',
      authToken: authToken,
    );
    for (final entry in response['modes'] as List<dynamic>? ?? const []) {
      if (entry['key']?['xstr64']?.toString() == lobbyId) {
        current = (entry['value'] as num?)?.toInt() ?? _all;
      }
    }
  } catch (e) {
    debugPrint('MobilePush: cannot read the notification choices: $e');
    messenger.showSnackBar(const SnackBar(
        content: Text('Notifications cannot be set on this version.')));
    return;
  }
  if (!context.mounted) return;

  final picked = await showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Notifications of this room'),
      children: [
        for (final choice in _choices.entries)
          ListTile(
            leading: Icon(
              choice.key == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(choice.value.$1),
            subtitle: Text(choice.value.$2),
            onTap: () => Navigator.of(dialogContext).pop(choice.key),
          ),
      ],
    ),
  );
  if (picked == null || picked == current) return;

  try {
    await rsApiCall(
      '/rsMobilePush/setLobbyPreference',
      authToken: authToken,
      params: {
        'lobbyId': {'xstr64': lobbyId},
        'mode': picked,
      },
    );
  } catch (e) {
    debugPrint('MobilePush: cannot set the notification choice: $e');
    messenger.showSnackBar(
        const SnackBar(content: Text('The choice could not be saved.')));
  }
}
