import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:retroshare/apiUtils/retroshare_service.dart';

// "Stay logged in": the password of a node, kept in the secure store of the
// device so that the app logs in by itself when it starts. On iOS the system
// may end the app at any time while it is in background; without this, a
// notification then opens on the sign-in screen.

/// Whether this platform has the secure store.
bool get stayLoggedInAvailable => Platform.isIOS;

String _name(String locationId) => 'password.$locationId';

/// The password kept for the node, null when there is none.
Future<String?> storedPassword(String locationId) async {
  if (!stayLoggedInAvailable) return null;
  try {
    return await rsPlatform.invokeMethod<String>(
      'secretGet',
      {'name': _name(locationId)},
    );
  } catch (error) {
    debugPrint('Stay logged in: cannot read the secure store: $error');
    return null;
  }
}

/// Keeps the node's password on this device.
Future<void> storePassword(String locationId, String password) async {
  if (!stayLoggedInAvailable) return;
  try {
    await rsPlatform.invokeMethod<bool>(
      'secretSet',
      {'name': _name(locationId), 'value': password},
    );
  } catch (error) {
    debugPrint('Stay logged in: cannot write the secure store: $error');
  }
}

/// Removes the node's password from this device.
Future<void> forgetPassword(String locationId) async {
  if (!stayLoggedInAvailable) return;
  try {
    await rsPlatform.invokeMethod<bool>(
      'secretDelete',
      {'name': _name(locationId)},
    );
  } catch (error) {
    debugPrint('Stay logged in: cannot clear the secure store: $error');
  }
}
