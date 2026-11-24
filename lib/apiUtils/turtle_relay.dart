import 'package:flutter/foundation.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Whether the node relays the other nodes' tunnels and searches.
//
// A node passes the tunnel requests and search requests of the other nodes
// on to its friends, then carries the data of the tunnels built through it.
// On a phone that relay makes most of the traffic (the turtle router comes
// far ahead in the traffic by service), paid in battery and mobile data, so
// the app keeps it off unless the user turns it on. Its own tunnels (distant
// chats, downloads) and its own searches work either way. The friends still
// send it their requests: the phone receives them and drops them.

String _relayKey(String locationId) => 'turtle_relay_on_$locationId';

/// Whether the user turned the relay on for this node (location).
Future<bool> turtleRelayOn(String locationId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_relayKey(locationId)) ?? false;
}

Future<void> setTurtleRelayOn(String locationId, bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_relayKey(locationId), on);
}

/// Sets the core's relay as the user chose it. Called at each login, so the
/// core follows the app's setting whatever its own saved one. Errors are
/// logged, never thrown: the login must not fail on them. A libretroshare
/// without these switches answers an error and keeps relaying.
Future<void> applyTurtleRelay(AuthToken token, String locationId) async {
  final on = await turtleRelayOn(locationId);
  for (final path in [
    '/rsTurtle/setTunnelRequestForwarding',
    '/rsTurtle/setSearchRequestForwarding',
  ]) {
    try {
      await rsApiCall(path, authToken: token, params: {'forward': on});
    } catch (error) {
      debugPrint('Turtle relay: $path failed: $error');
    }
  }
  debugPrint('Turtle relay: ${on ? 'on' : 'off'}');
}
