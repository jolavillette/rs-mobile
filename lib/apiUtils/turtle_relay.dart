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
// chats, downloads) and its own searches work either way.

/// setMaxTRForwardRate(): the lowest value the core accepts, 10, makes it
/// forward no tunnel request at all; 20 is its default.
const _noTunnelRequestForwarding = 10;
const _defaultTunnelRequestForwarding = 20;

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

/// Sets the core's relay as the user chose it. Called at each login: the
/// core saves its turtle settings on a clean stop only, and reads its lowest
/// tunnel request setting back as out of range. Errors are logged, never
/// thrown: the login must not fail on them. A libretroshare without
/// setSearchRequestForwarding() answers an error for that part only.
Future<void> applyTurtleRelay(AuthToken token, String locationId) async {
  final on = await turtleRelayOn(locationId);
  try {
    await rsApiCall(
      '/rsTurtle/setMaxTRForwardRate',
      authToken: token,
      params: {
        'max_tr_up_rate':
            on ? _defaultTunnelRequestForwarding : _noTunnelRequestForwarding,
      },
    );
  } catch (error) {
    debugPrint('Turtle relay: cannot set the tunnel request relay: $error');
  }
  try {
    await rsApiCall(
      '/rsTurtle/setSearchRequestForwarding',
      authToken: token,
      params: {'forward': on},
    );
  } catch (error) {
    debugPrint('Turtle relay: cannot set the search request relay: $error');
  }
  debugPrint('Turtle relay: ${on ? 'on' : 'off'}');
}
