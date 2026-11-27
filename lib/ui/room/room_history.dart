import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/ui/manual/manual_screen.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The lines of a room that this phone missed, asked to the friends that are
// in the room and kept them, as the desktop does: each friend is first asked
// what it has, then for its lines. A friend answers only if its user allowed
// the sharing of the history, and with the lines its node stored.
//
// The lines come back unsigned: a friend could send lines nobody wrote. So
// only the friends the user designated, in the chat settings or from the
// room menu, are asked.

/// RsChatLobbyEventCode values of the two answers.
const _probeResponse = 0x0a;
const _historyData = 0x0b;

const _probeWait = Duration(seconds: 5);
const _dataIdleWait = Duration(seconds: 10);

/// The library accepts the answers to a request for two minutes.
const _dataMaxWait = Duration(seconds: 120);

/// A friend answers the same friend once per 30 seconds and room, and stays
/// silent in between: asking again sooner would look like a refusal.
const _askAgainAfter = Duration(seconds: 32);

/// Room -> when its history was last asked.
final Map<String, DateTime> _lastAsked = {};

/// Lines asked to each friend, and shown: the most recent ones.
const _maxLines = 500;

class _Line {
  _Line(this.nick, this.sendTime, this.message);
  final String nick;
  final int sendTime;
  final String message;
}

/// One retrieval at a time, for one room.
class _Fetch {
  _Fetch(this.lobbyId);
  final String lobbyId;

  /// Friend -> the oldest time it has lines for.
  final Map<String, int> probes = {};
  final Set<String> pending = {};
  final List<_Line> lines = [];
  final Set<String> relays = {};
  bool waitingProbes = true;
  Completer<void> changed = Completer<void>();

  void signal() {
    if (!changed.isCompleted) changed.complete();
  }
}

_Fetch? _fetch;

int _number(dynamic value) {
  if (value is num) return value.toInt();
  if (value is Map) {
    return _number(value['xint64'] ?? value['xstr64']);
  }
  return int.tryParse('${value ?? ''}') ?? 0;
}

/// Takes the room history answers out of the chat events. Returns whether
/// [event] was one of them.
bool handleRoomHistoryEvent(dynamic event) {
  // Only the room events carry this field; other chat events have their
  // own codes, which may use the same numbers.
  if (event is! Map || !event.containsKey('mHistoryComplete')) return false;
  final code = _number(event['mEventCode']);
  if (code != _probeResponse && code != _historyData) return false;

  final fetch = _fetch;
  final lobby = event['mLobbyId'];
  final lobbyId = lobby is Map ? '${lobby['xstr64'] ?? ''}' : '$lobby';
  final peer = '${event['mPeerId'] ?? ''}'.toLowerCase();
  if (fetch == null || lobbyId != fetch.lobbyId || peer.isEmpty) return true;

  if (code == _probeResponse) {
    if (fetch.waitingProbes) fetch.probes[peer] = _number(event['mTimeShift']);
  } else if (fetch.pending.contains(peer)) {
    final messages = event['mHistoryMsgs'];
    if (messages is List) {
      for (final m in messages.whereType<Map>()) {
        fetch.lines.add(
          _Line(
            '${m['nick'] ?? ''}',
            _number(m['send_time']),
            '${m['message'] ?? ''}',
          ),
        );
      }
      if (messages.isNotEmpty) fetch.relays.add(peer);
    }
    if (event['mHistoryComplete'] == true) fetch.pending.remove(peer);
  }
  fetch.signal();
  return true;
}

String _friendsKey(String locationId) => 'history_friends_$locationId';

/// The friend nodes (SSL ids) the user designated to be asked for the
/// history, for the node [locationId].
Future<Set<String>> historyFriends(String locationId) async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_friendsKey(locationId)) ?? const <String>[])
      .toSet();
}

/// Lets the user designate the friends asked for the history. Returns the
/// new choice, or null when the user cancelled.
Future<Set<String>?> chooseHistoryFriends(BuildContext context) async {
  final locationId = Provider.of<AccountCredentials>(context, listen: false)
      .loggedinAccount
      ?.locationId;
  if (locationId == null) return null;
  final nodes = [
    ...Provider.of<FriendLocations>(context, listen: false).friendlist,
  ]..sort(
      (a, b) => a.accountName.toLowerCase().compareTo(
            b.accountName.toLowerCase(),
          ),
    );
  final picked = await historyFriends(locationId);
  if (!context.mounted) return null;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Friends asked for the history'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'When you retrieve the history of a room, these friends are '
                'asked for the lines they kept. Select only friends you '
                'trust: the lines they send are not signed, so a friend '
                'could send lines that nobody wrote.',
              ),
              const SizedBox(height: 8),
              if (nodes.isEmpty) const Text('You have no friend yet.'),
              for (final node in nodes)
                CheckboxListTile(
                  value: picked.contains(node.rsPeerId),
                  title: Text(node.accountName),
                  subtitle: Text(node.locationName),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (on) => setDialogState(() {
                    if (on == true) {
                      picked.add(node.rsPeerId);
                    } else {
                      picked.remove(node.rsPeerId);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_friendsKey(locationId), picked.toList());
  return picked;
}

/// Asks the user how far back to go, then retrieves the lines of the room
/// [lobbyId] from the designated friends that are connected and adds the
/// new ones to the chat.
Future<void> retrieveRoomHistory(
  BuildContext context,
  String lobbyId,
  ChatId apiChatId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final rooms = Provider.of<RoomChatLobby>(context, listen: false);
  final token =
      Provider.of<AccountCredentials>(context, listen: false).authtoken;
  final locationId = Provider.of<AccountCredentials>(context, listen: false)
      .loggedinAccount
      ?.locationId;
  if (token == null || locationId == null) return;

  // The period, or -1 to designate the friends first.
  const chooseFriends = -1;
  int? hours;
  var designated = await historyFriends(locationId);
  while (true) {
    if (!context.mounted) return;
    final locations =
        Provider.of<FriendLocations>(context, listen: false).friendlist;
    final names = [
      for (final location in locations)
        if (designated.contains(location.rsPeerId))
          location.isOnline
              ? location.accountName
              : '${location.accountName} (not connected)',
    ];
    hours = await _askPeriod(context, names, chooseFriends);
    if (hours != chooseFriends) break;
    designated = await chooseHistoryFriends(context) ?? designated;
  }
  if (hours == null || !context.mounted) return;

  final friends = Provider.of<FriendLocations>(context, listen: false)
      .friendlist
      .where((l) => l.isOnline && designated.contains(l.rsPeerId))
      .map((l) => l.rsPeerId)
      .toList();

  void say(String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  if (_fetch != null) {
    say('A history is already being retrieved.');
    return;
  }
  if (designated.isEmpty) {
    say('Designate first the friends to ask.');
    return;
  }
  if (friends.isEmpty) {
    say('None of the designated friends is connected.');
    return;
  }
  final asked = _lastAsked[lobbyId];
  if (asked != null) {
    final left = _askAgainAfter - DateTime.now().difference(asked);
    if (left > Duration.zero) {
      say(
        'This history was asked a moment ago, and a friend answers once '
        'every 30 seconds. Ask again in ${left.inSeconds + 1} seconds.',
      );
      return;
    }
  }

  final oldest = DateTime.now().millisecondsSinceEpoch ~/ 1000 - hours * 3600;
  final fetch = _Fetch(lobbyId);
  _fetch = fetch;
  try {
    final lobby = {'xstr64': lobbyId};
    final sent = await rsApiCall(
      '/rsChats/requestLobbyHistory',
      authToken: token,
      params: {'lobby_id': lobby, 'peer_ids': friends},
    );
    if (sent['retval'] != true) {
      say('None of the designated friends is in this room.');
      return;
    }
    _lastAsked[lobbyId] = DateTime.now();
    say('Asking your friends what they have...');

    // What each friend has, for a few seconds or until all answered.
    final probeEnd = DateTime.now().add(_probeWait);
    while (fetch.probes.length < friends.length) {
      final left = probeEnd.difference(DateTime.now());
      if (left <= Duration.zero) break;
      fetch.changed = Completer<void>();
      await fetch.changed.future.timeout(left, onTimeout: () {});
    }
    fetch.waitingProbes = false;
    if (fetch.probes.isEmpty) {
      say(
        'No friend answered. A friend answers if it shares its history and '
        'already sees this phone in the room: just after a connection, ask '
        'again in a minute.',
      );
      return;
    }

    for (final probe in fetch.probes.entries) {
      final from = probe.value != 0 && probe.value > oldest
          ? probe.value
          : oldest;
      final accepted = await rsApiCall(
        '/rsChats/requestLobbyHistoryFromPeer',
        authToken: token,
        params: {
          'lobby_id': lobby,
          'peer_id': probe.key,
          'max_count': _maxLines,
          'oldest_ts': from,
        },
      );
      if (accepted['retval'] == true) fetch.pending.add(probe.key);
    }

    // Each friend marks the end of what it sends; the waits only cover a
    // friend that stops answering.
    final dataEnd = DateTime.now().add(_dataMaxWait);
    while (fetch.pending.isNotEmpty) {
      final left = dataEnd.difference(DateTime.now());
      if (left <= Duration.zero) break;
      fetch.changed = Completer<void>();
      var idle = false;
      await fetch.changed.future.timeout(
        left < _dataIdleWait ? left : _dataIdleWait,
        onTimeout: () => idle = true,
      );
      if (idle) break;
    }

    // The lines this phone does not have yet, once each: two friends relay
    // the same lines. They are not signed, so they carry the name the friend
    // gives and no identity.
    final known = (rooms.messagesList[lobbyId] ?? const <ChatMessage>[])
        .map((m) => '${m.sendTime}_${m.msg}')
        .toSet();
    final fresh = <_Line>[];
    for (final line in fetch.lines) {
      if (line.sendTime < oldest) continue;
      if (known.add('${line.sendTime}_${line.message}')) fresh.add(line);
    }
    fresh.sort((a, b) => a.sendTime.compareTo(b.sendTime));
    final shown = fresh.length > _maxLines
        ? fresh.sublist(fresh.length - _maxLines)
        : fresh;
    for (final line in shown) {
      rooms.addChatMessage(
        ChatMessage(
          chatId: apiChatId,
          msg: line.message,
          incoming: true,
          sendTime: line.sendTime,
          recvTime: line.sendTime,
          lobbyPeerGxsId: line.nick,
          chatflags: 0x0004, // rsChatFlagsHistory
        ),
        lobbyId,
      );
    }

    final from = fetch.relays.length;
    say(
      shown.isEmpty
          ? 'Nothing new: your friends have no line that is missing here.'
          : '${shown.length} lines retrieved from $from '
              '${from == 1 ? 'friend' : 'friends'}.',
    );
  } catch (error) {
    debugPrint('Room history: $error');
    say('Could not retrieve the history.');
  } finally {
    _fetch = null;
  }
}

/// The period to retrieve, in hours; [chooseFriends] when the user wants to
/// designate the friends; null when cancelled. [names] are the designated
/// friends.
Future<int?> _askPeriod(
  BuildContext context,
  List<String> names,
  int chooseFriends,
) =>
    showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Retrieve the history from friends'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              names.isEmpty
                  ? 'No friend is designated yet. The friends you designate '
                      'send the lines they kept, if they are in this room '
                      'and allow it in their chat settings.'
                  : 'Asked: ${names.join(', ')}. They send the lines they '
                      'kept, if they are in this room and allow it in their '
                      'chat settings.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, chooseFriends),
            child: const Text('Designate the friends to ask...'),
          ),
          SimpleDialogOption(
            onPressed: () => openManual(dialogContext, 'history'),
            child: const Text('How it works'),
          ),
          const Divider(),
          for (final choice in const [
            (1, 'The last hour'),
            (6, 'The last 6 hours'),
            (24, 'The last 24 hours'),
            (168, 'The last 7 days'),
          ])
            SimpleDialogOption(
              onPressed: names.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, choice.$1),
              child: Text(choice.$2),
            ),
        ],
      ),
    );
