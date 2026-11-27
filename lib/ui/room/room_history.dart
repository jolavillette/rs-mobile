import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

// The lines of a room that this phone missed, asked to the friends that are
// in the room and kept them, as the desktop does: each friend is first asked
// what it has, then for its lines. A friend answers only if its user allowed
// the sharing of the history, and with the lines its node stored.

/// RsChatLobbyEventCode values of the two answers.
const _probeResponse = 0x0a;
const _historyData = 0x0b;

const _probeWait = Duration(seconds: 5);
const _dataIdleWait = Duration(seconds: 10);

/// The library accepts the answers to a request for two minutes.
const _dataMaxWait = Duration(seconds: 120);

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

/// Asks the user how far back to go, then retrieves the lines of the room
/// [lobbyId] from the connected friends and adds the new ones to the chat.
Future<void> retrieveRoomHistory(
  BuildContext context,
  String lobbyId,
  ChatId apiChatId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final rooms = Provider.of<RoomChatLobby>(context, listen: false);
  final token =
      Provider.of<AccountCredentials>(context, listen: false).authtoken;
  final friends = Provider.of<FriendLocations>(context, listen: false)
      .friendlist
      .where((location) => location.isOnline)
      .map((location) => location.rsPeerId)
      .toList();
  if (token == null) return;

  final hours = await showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Retrieve the history from friends'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Your connected friends that are in this room send the lines '
            'they kept, if they allow it in their chat settings.',
          ),
        ),
        for (final choice in const [
          (1, 'The last hour'),
          (6, 'The last 6 hours'),
          (24, 'The last 24 hours'),
          (168, 'The last 7 days'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, choice.$1),
            child: Text(choice.$2),
          ),
      ],
    ),
  );
  if (hours == null) return;

  void say(String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  if (_fetch != null) {
    say('A history is already being retrieved.');
    return;
  }
  if (friends.isEmpty) {
    say('No friend is connected.');
    return;
  }

  final oldest = DateTime.now().millisecondsSinceEpoch ~/ 1000 - hours * 3600;
  final fetch = _Fetch(lobbyId);
  _fetch = fetch;
  try {
    final lobby = {'xstr64': lobbyId};
    final asked = await rsApiCall(
      '/rsChats/requestLobbyHistory',
      authToken: token,
      params: {'lobby_id': lobby, 'peer_ids': friends},
    );
    if (asked['retval'] != true) {
      say('None of your connected friends is in this room.');
      return;
    }
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
      say('No friend answered: none shares the history of this room.');
      return;
    }

    for (final probe in fetch.probes.entries) {
      final from = probe.value != 0 && probe.value > oldest
          ? probe.value
          : oldest;
      final sent = await rsApiCall(
        '/rsChats/requestLobbyHistoryFromPeer',
        authToken: token,
        params: {
          'lobby_id': lobby,
          'peer_id': probe.key,
          'max_count': _maxLines,
          'oldest_ts': from,
        },
      );
      if (sent['retval'] == true) fetch.pending.add(probe.key);
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
