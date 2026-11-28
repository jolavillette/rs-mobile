import 'package:flutter/foundation.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Whether the node takes part in the DHT. The DHT finds a friend whose
// address changed and helps two nodes behind network address translators
// reach each other. It costs a steady flow of UDP packets that keeps a phone's
// radio awake: measured on 4G, about 7.5 MB and 50,000 packets an hour, most
// of it trying to reach friends that were offline. A phone whose friend has a
// fixed address (a home) does not need it, so the app keeps it off unless the
// user turns it on.

/// RS_VS_DHT_OFF and RS_VS_DHT_FULL in libretroshare's retroshare/rspeers.h.
const _dhtOff = 0;
const _dhtFull = 2;

String _dhtKey(String locationId) => 'dht_on_$locationId';

/// Whether the user turned the DHT on for this node (location).
Future<bool> dhtOn(String locationId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_dhtKey(locationId)) ?? false;
}

Future<void> setDhtOn(String locationId, bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_dhtKey(locationId), on);
}

/// Sets the core's DHT as the user chose it, keeping its discovery setting.
/// Called at each login. locationId is the node's own SSL id. Errors are
/// logged, never thrown.
Future<void> applyDht(AuthToken token, String locationId) async {
  final on = await dhtOn(locationId);
  try {
    final details = await rsApiCall(
      '/rsPeers/getPeerDetails',
      authToken: token,
      params: {'sslId': locationId},
    );
    final det = details['det'];
    final vsDisc = det is Map ? det['vs_disc'] : null;
    await rsApiCall(
      '/rsPeers/setVisState',
      authToken: token,
      params: {
        'sslId': locationId,
        'vsDisc': vsDisc is int ? vsDisc : 2,
        'vsDht': on ? _dhtFull : _dhtOff,
      },
    );
    debugPrint('DHT: ${on ? 'on' : 'off'}');
  } catch (error) {
    debugPrint('DHT: cannot set it: $error');
  }
}
