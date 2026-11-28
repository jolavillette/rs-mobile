import 'package:flutter/foundation.dart';
import 'package:retroshare/apiUtils/service_ids.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A core service as the Services page shows it.
class MobileService {
  const MobileService(this.type, this.name, this.role, {this.offWarning});

  /// 16-bit service type.
  final int type;
  final String name;

  /// What the service does, shown under its switch and in the warning.
  final String role;

  /// What stops working when the user turns the service off, for the
  /// services of [switchableServices].
  final String? offWarning;

  int get fullId => rsFullServiceId(type);
}

/// The services the app needs (chats, rooms, distant chats, identities,
/// presence, attachments) or that keep the connections healthy. Mobile
/// Services shows them, it does not let the user turn them off.
const neededServices = <MobileService>[
  MobileService(
    RsServiceTypes.mobileLink,
    'Mobile link',
    'Lets the friends that serve this phone spare its battery and data.',
  ),
  MobileService(
    RsServiceTypes.serviceInfo,
    'Service info',
    'Tells friends which services this node runs.',
  ),
  MobileService(
    RsServiceTypes.heartbeat,
    'Heartbeat',
    'Keeps the connections with friends alive.',
  ),
  MobileService(
    RsServiceTypes.chat,
    'Chat',
    'Chats with friends, chat rooms and their invitations.',
  ),
  MobileService(
    RsServiceTypes.status,
    'Status',
    'Online, away or busy.',
  ),
  MobileService(
    RsServiceTypes.identities,
    'Identities',
    'Your identities and those of the people you talk to.',
  ),
  MobileService(
    RsServiceTypes.reputation,
    'Reputation',
    'Opinions on identities, used by the identities.',
  ),
  MobileService(
    RsServiceTypes.turtle,
    'Turtle',
    'Anonymous tunnels, used by distant chats.',
  ),
  MobileService(
    RsServiceTypes.gxsTunnels,
    'GXS tunnels',
    'Distant chats with identities.',
  ),
  MobileService(
    RsServiceTypes.fileTransfer,
    'File transfer',
    'Files attached to chat messages.',
  ),
  MobileService(
    RsServiceTypes.bandwidthControl,
    'Bandwidth control',
    'Shares the bandwidth between friends.',
  ),
  MobileService(
    RsServiceTypes.rtt,
    'RTT',
    'Measures the delay to each friend.',
  ),
  MobileService(
    RsServiceTypes.banList,
    'Ban list',
    'Shares banned IP addresses with friends.',
  ),
];

/// The services the app can work without, on unless the user turns them off
/// in Permissions. The core remembers the choice.
const switchableServices = <MobileService>[
  MobileService(
    RsServiceTypes.discovery,
    'Discovery',
    "Exchanges addresses, keys and versions with your friends.",
    offWarning: 'Without it this phone no longer learns the new addresses of '
        'your friends, nor tells them its own: it reaches a friend only at '
        'the addresses it already knows. A friend added with a short '
        'RetroShare ID stays unverified, since its key comes through this '
        "service. The friends' RetroShare version is no longer shown.",
  ),
];

/// The optional services the app has a page for: off like the others until
/// the user turns them on, in Permissions or from their page.
const servicesWithPage = <int>{RsServiceTypes.forums, RsServiceTypes.channels};

/// The services that stay off unless the user turns them on: on a phone they
/// cost CPU, mobile data, battery or storage, for nothing the user can see
/// (no page in the app) or for content not everybody reads (forums,
/// channels). The app turns them off at every login, except those the user
/// turned on, in Permissions or from their page.
const optionalServices = <MobileService>[
  MobileService(
    RsServiceTypes.forums,
    'Forums',
    "Synchronizes your friends' forums.",
  ),
  MobileService(
    RsServiceTypes.channels,
    'Channels',
    "Synchronizes your friends' channels, the heaviest of these services.",
  ),
  MobileService(
    RsServiceTypes.boards,
    'Boards',
    "Synchronizes your friends' boards.",
  ),
  MobileService(
    RsServiceTypes.circles,
    'Circles',
    "Synchronizes your friends' circles.",
  ),
  MobileService(
    RsServiceTypes.calendar,
    'Calendar',
    "Synchronizes your friends' calendars.",
  ),
  MobileService(
    RsServiceTypes.messages,
    'Mail',
    'Mail between friends.',
  ),
  MobileService(
    RsServiceTypes.gxsMails,
    'Distant mail (GXS Trans)',
    'Stores and relays the encrypted distant mail of the network for 15 days.',
  ),
  MobileService(
    RsServiceTypes.globalRouter,
    'Global router',
    'Routes, relays and caches distant mail for other nodes.',
  ),
  MobileService(
    RsServiceTypes.fileDatabase,
    'File lists',
    'Exchanges the lists of shared files with your friends.',
  ),
];

/// Whether [permissions] (rsServiceControl) let the service talk to friends.
bool isServiceOn(Map<String, dynamic> permissions) {
  final allowed = permissions['mPeersAllowed'];
  return permissions['mDefaultAllowed'] == true ||
      (allowed is List && allowed.isNotEmpty);
}

/// Whether [permissions] belong to a service this core runs: for an unknown
/// service the core answers with empty permissions (service id 0).
bool isServiceKnown(Map<String, dynamic> permissions, MobileService service) =>
    permissions['mServiceId'] == service.fullId;

String _optedInKey(String locationId) => 'optional_services_on_$locationId';

/// The optional services the user turned on for this node (location).
Future<Set<int>> optedInServices(String locationId) async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_optedInKey(locationId)) ?? const <String>[])
      .map(int.tryParse)
      .whereType<int>()
      .toSet();
}

Future<void> setOptedIn(String locationId, int type, bool on) async {
  final prefs = await SharedPreferences.getInstance();
  final types = await optedInServices(locationId);
  on ? types.add(type) : types.remove(type);
  await prefs.setStringList(
    _optedInKey(locationId),
    types.map((t) => '$t').toList(),
  );
}

/// Turns off every optional service the user did not turn on in the app.
/// Called at each login: a service turned on another way (the web UI for
/// instance) goes off again. Errors are logged, never thrown: the login must
/// not fail on them.
Future<void> turnOffOptionalServices(AuthToken token, String locationId) async {
  final optedIn = await optedInServices(locationId);
  for (final service in optionalServices) {
    if (optedIn.contains(service.type)) continue;
    try {
      final permissions =
          await RsServiceControl.getServicePermissions(service.fullId, token);
      if (!isServiceKnown(permissions, service) || !isServiceOn(permissions)) {
        continue;
      }
      final done =
          await RsServiceControl.setServiceEnabled(service.fullId, false, token);
      debugPrint(
        done
            ? 'Mobile services: ${service.name} turned off'
            : 'Mobile services: the core did not turn ${service.name} off',
      );
    } catch (error) {
      debugPrint('Mobile services: cannot turn ${service.name} off: $error');
    }
  }
}

/// Every service this core runs, by 16-bit type, with the name the core gives
/// it (rsServiceControl getOwnServices).
Future<Map<int, String>> coreServices(AuthToken token) async {
  final response = await rsApiCall(
    '/rsServiceControl/getOwnServices',
    authToken: token,
  );
  final info = response['info'];
  final list = info is Map ? info['mServiceList'] : null;
  final entries = list is List
      ? list.whereType<Map>().map((e) => e['value'])
      : list is Map
          ? list.values
          : const Iterable<Object?>.empty();
  final result = <int, String>{};
  for (final service in entries.whereType<Map>()) {
    var rawType = service['mServiceType'];
    if (rawType is Map) rawType = rawType['xint64'] ?? rawType['xstr64'];
    final fullId = rawType is num
        ? rawType.toInt()
        : int.tryParse('${rawType ?? ''}') ?? 0;
    if (fullId == 0) continue;
    result[rsServiceType(fullId)] =
        service['mServiceName']?.toString().trim() ?? '';
  }
  return result;
}
