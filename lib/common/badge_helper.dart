import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/notifications.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';

class BadgeHelper {
  static Future<void> updateAppBadge(BuildContext context) async {
    try {
      final chatLobby = Provider.of<ChatLobby>(context, listen: false);
      final roomChatLobby = Provider.of<RoomChatLobby>(context, listen: false);

      // Aggregate room unreads
      final roomUnread = chatLobby.subscribedlist.fold(0, (sum, chat) => sum + chat.unreadCount);
      
      final totalUnread = roomUnread +
          roomChatLobby.distantUnreadCount +
          roomChatLobby.peerUnreadCount +
          chatLobby.pendingInviteCount;
      debugPrint(
        '[ChatUnread] badge rooms=$roomUnread '
        'distant=${roomChatLobby.distantUnreadCount} '
        'peer=${roomChatLobby.peerUnreadCount} '
        'invites=${chatLobby.pendingInviteCount} total=$totalUnread',
      );

      await _clearReadNotifications(
        chats: totalUnread - chatLobby.pendingInviteCount == 0,
        invites: chatLobby.pendingInviteCount == 0,
      );

      if (await FlutterAppBadger.isAppBadgeSupported()) {
        if (totalUnread > 0) {
          FlutterAppBadger.updateBadgeCount(totalUnread);
        } else {
          FlutterAppBadger.removeBadge();
        }
      }
    } catch (e) {
      debugPrint('Error updating app badge: $e');
    }
  }

  /// A chat notification stays in the shade once its message was read, and
  /// Samsung's launcher counts the notifications on the app's icon: the icon
  /// showed 1 with nothing new in the app. Those of chats go once no chat
  /// message is unread, those of invitations once none is pending.
  static Future<void> _clearReadNotifications({
    required bool chats,
    required bool invites,
  }) async {
    if (!Platform.isAndroid || (!chats && !invites)) return;
    try {
      final active =
          await flutterLocalNotificationsPlugin.getActiveNotifications();
      for (final notification in active) {
        final channel = notification.channelId;
        final read = (chats && channel == chatNotificationChannel) ||
            (invites && channel == lobbyInviteNotificationChannel);
        final id = notification.id;
        if (read && id != null) {
          await flutterLocalNotificationsPlugin.cancel(
            id: id,
            tag: notification.tag,
          );
        }
      }
    } catch (e) {
      debugPrint('Cannot clear the read notifications: $e');
    }
  }
}
