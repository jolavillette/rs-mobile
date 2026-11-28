import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// News from the core about a forum or a channel: a group of [kind] or its
/// posts changed. [groupId] is empty when the core does not say which.
class GxsChange {
  const GxsChange(this.kind, this.groupId);

  final GxsContentKind kind;
  final String groupId;
}

/// The forum and channel events of the core, followed once per login, of
/// which only those a page shows are passed on: a group or a post that
/// arrived, changed or went, a subscription that changed. Read marks,
/// statistics and sync periods are left out: the pages change those
/// themselves, or do not show them.
class GxsChanges {
  GxsChanges._();

  static final _changes = StreamController<GxsChange>.broadcast();
  static String? _login;

  // RsChannelEventCode: NEW_CHANNEL, UPDATED_CHANNEL, NEW_MESSAGE,
  // UPDATED_MESSAGE, SUBSCRIBE_STATUS_CHANGED, DELETED_CHANNEL.
  static const _channelCodes = {0x01, 0x02, 0x03, 0x04, 0x06, 0x0d};

  // RsForumEventCode: NEW_FORUM, UPDATED_FORUM, NEW_MESSAGE, UPDATED_MESSAGE,
  // SUBSCRIBE_STATUS_CHANGED, PINNED_POSTS_CHANGED, DELETED_FORUM,
  // DELETED_POST.
  static const _forumCodes = {0x01, 0x02, 0x03, 0x04, 0x05, 0x0b, 0x0c, 0x0d};

  /// The news, the events being followed from the first call of a login.
  static Stream<GxsChange> of(AuthToken token) {
    final login = token.toString();
    if (_login != login) {
      _login = login;
      _follow(
        token,
        GxsContentKind.channels,
        RsEventType.GXS_CHANNELS,
        'mChannelEventCode',
        'mChannelGroupId',
        _channelCodes,
      );
      _follow(
        token,
        GxsContentKind.forums,
        RsEventType.GXS_FORUMS,
        'mForumEventCode',
        'mForumGroupId',
        _forumCodes,
      );
    }
    return _changes.stream;
  }

  static void _follow(
    AuthToken token,
    GxsContentKind kind,
    RsEventType type,
    String codeKey,
    String groupKey,
    Set<int> codes,
  ) {
    unawaited(
      RsEvents.registerEventsHandler(
        type,
        (_, dynamic event) {
          if (event is! Map) return;
          final code = event[codeKey];
          if (code is! int || !codes.contains(code)) return;
          final groupId = event[groupKey];
          _changes.add(GxsChange(kind, groupId is String ? groupId : ''));
        },
        token,
        onError: (Object e, [StackTrace? _]) {
          debugPrint('${kind.title} events lost: $e');
        },
      ).catchError((Object e) {
        // Followed again at the next call.
        if (_login == token.toString()) _login = null;
        debugPrint('Cannot follow the ${kind.noun} events: $e');
        return null;
      }),
    );
  }
}

/// Calls [reload] a second after the core reports news about the groups of
/// a kind, or about one group only when its id is given. The news of that
/// second wait for the same reload.
class GxsChangeWatch {
  GxsChangeWatch(
    AuthToken token,
    GxsContentKind kind,
    this.reload, {
    String? groupId,
  }) {
    _changes = GxsChanges.of(token)
        .where(
          (change) =>
              change.kind == kind &&
              (groupId == null ||
                  change.groupId.isEmpty ||
                  change.groupId == groupId),
        )
        .listen((_) => _timer ??= Timer(const Duration(seconds: 1), _fire));
  }

  final VoidCallback reload;
  late final StreamSubscription<GxsChange> _changes;
  Timer? _timer;

  void _fire() {
    _timer = null;
    reload();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    unawaited(_changes.cancel());
  }
}
