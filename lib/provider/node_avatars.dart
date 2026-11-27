import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

class _Entry {
  _Entry(this.image) : read = DateTime.now();

  final Uint8List? image;
  final DateTime read;
  bool stale = false;
}

/// The avatars of the nodes: my own and my friends'. RetroShare has no
/// avatar for a profile: as on the desktop, a friend is shown with the
/// avatar of the first of their nodes that has one, and I am shown with the
/// avatar of this node.
///
/// A widget asks with [of] or [ofAny] at each build and listens to this
/// object: an avatar not known yet is read from the core, and the widget is
/// told when it arrives. The core's friend list events say when a node
/// changed its avatar. "No avatar" is only kept for a minute, because asking
/// the core is also what makes it request the avatar from the node.
class NodeAvatars extends ChangeNotifier {
  NodeAvatars._();

  static final NodeAvatars instance = NodeAvatars._();

  /// The key of my own node in the cache.
  static const _own = '';

  static const _noAvatarRetry = Duration(seconds: 60);

  /// An avatar is read again after this long even without an event, in case
  /// the event stream was down when the node changed it.
  static const _maxAge = Duration(minutes: 10);

  /// Values of RsFriendListEventCode in libretroshare.
  static const _nodeAvatarChanged = 8;
  static const _ownAvatarChanged = 10;

  final Map<String, _Entry> _entries = {};
  final Set<String> _reading = {};
  bool _listening = false;

  /// The login the cache belongs to: another one starts from nothing.
  String? _login;

  /// False once the core answered that it has no node avatar calls (a core
  /// older than the app): nothing is asked any more.
  bool _supported = true;

  /// The avatar of my own node, or null.
  Uint8List? own(AuthToken authToken) => _get(_own, authToken);

  /// The avatar of the node [sslId], or null.
  Uint8List? of(String sslId, AuthToken authToken) =>
      sslId.isEmpty ? null : _get(sslId.toLowerCase(), authToken);

  /// The first avatar found among the nodes [sslIds] of one profile.
  Uint8List? ofAny(Iterable<String> sslIds, AuthToken authToken) {
    Uint8List? found;
    for (final id in sslIds) {
      // Every node is asked, so that all of them get read.
      found ??= of(id, authToken);
    }
    return found;
  }

  /// Sets the avatar of my own node; empty [image] removes it. False when
  /// the core refused it.
  Future<bool> setOwn(Uint8List image, AuthToken authToken) async {
    if (!await RsChats.setOwnAvatar(image, authToken)) return false;
    _get(_own, authToken);
    _entries[_own] = _Entry(image.isEmpty ? null : image);
    notifyListeners();
    return true;
  }

  Uint8List? _get(String key, AuthToken authToken) {
    final login = authToken.toString();
    if (_login != login) {
      _login = login;
      _entries.clear();
      _supported = true;
      _listening = false;
    }
    final entry = _entries[key];
    final age = entry == null ? null : DateTime.now().difference(entry.read);
    final fresh = entry != null &&
        !entry.stale &&
        age! < (entry.image == null ? _noAvatarRetry : _maxAge);
    if (!fresh && _supported && _reading.add(key)) {
      unawaited(_read(key, authToken));
    }
    return entry?.image;
  }

  Future<void> _read(String key, AuthToken authToken) async {
    _listen(authToken);
    try {
      final image = key == _own
          ? await RsChats.getOwnAvatar(authToken)
          : await RsChats.getAvatar(key, authToken);
      if (_login != authToken.toString()) return;
      final before = _entries[key]?.image;
      _entries[key] = _Entry(image);
      if (!_sameImage(before, image)) notifyListeners();
    } catch (e) {
      if ('$e'.contains('404')) _supported = false;
      _entries[key] = _Entry(_entries[key]?.image);
      final node = key == _own ? 'my node' : key;
      debugPrint('Cannot read the avatar of $node: $e');
    } finally {
      _reading.remove(key);
    }
  }

  static bool _sameImage(Uint8List? a, Uint8List? b) =>
      identical(a, b) || (a != null && b != null && listEquals(a, b));

  /// Follows the friend list events of the core, once.
  void _listen(AuthToken authToken) {
    if (_listening) return;
    _listening = true;
    unawaited(
      RsEvents.registerEventsHandler(
        // The lib's FRIEND_LIST, under its former name.
        RsEventType.PEER_CONNECTION,
        (_, dynamic event) {
          if (event is! Map) return;
          final code = event['mEventCode'];
          if (code == _ownAvatarChanged) {
            _markStale(_own);
          } else if (code == _nodeAvatarChanged) {
            final id = event['mSslId'];
            if (id is String) _markStale(id.toLowerCase());
          }
        },
        authToken,
        onError: (Object e, [StackTrace? _]) {
          debugPrint('Friend list events lost: $e');
        },
      ).catchError((Object e) {
        _listening = false;
        debugPrint('Cannot follow the friend list events: $e');
        return null;
      }),
    );
  }

  void _markStale(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    entry.stale = true;
    notifyListeners();
  }
}
