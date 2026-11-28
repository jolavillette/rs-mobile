import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:retroshare/main.dart';
import 'package:rxdart/rxdart.dart';

NotificationAppLaunchDetails? notificationAppLaunchDetails;
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final BehaviorSubject<String?> selectNotificationSubject =
    BehaviorSubject<String?>();

/// Android notification channels: chat messages alert the user, plain
/// information does not.
const chatNotificationChannel = 'retroshare_chat';
const infoNotificationChannel = 'retroshare_info';
const lobbyInviteNotificationChannel = 'RetroshareInvites';

Future<void> initializeNotifications() async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

  // Chat messages and plain information shared one channel, and Android
  // keeps a channel as its first notification made it: where "Invite
  // copied!" came first, chat messages stayed silent for good. Each has its
  // own channel now, and the shared one goes.
  if (!kIsWeb && Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.deleteNotificationChannel(channelId: 'RetroshareFlutter');
  }

  notificationAppLaunchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  const initializationSettingsAndroid =
      AndroidInitializationSettings('@drawable/ic_stat_retroshare');
  const initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) async {
      final payload = notificationResponse.payload;
      selectNotificationSubject.add(payload);
    },
  );

  // Android 13 and later drop the notifications of an app that does not hold
  // POST_NOTIFICATIONS, silently: chat messages and lobby invitations never
  // showed. The app has to ask for it; Android asks the user only once.
  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }
}

void configureSelectNotificationSubject(BuildContext context) {
  selectNotificationSubject.stream.listen((String? payload) async {
    if (payload != null && payload == '/notification') {
      navigatorKey.currentState?.pushNamed('/notification');
    }
  });
}

Future<void> showChatNotification(
  String chatId,
  String title,
  String body,
) async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

  // For multiple messages check: inbox notification
  //  var largeIconPath = await _downloadAndSaveFile(
  //      'http://via.placeholder.com/128x128/00FF00/000000', 'largeIcon');

  const androidPlatformChannelSpecifics = AndroidNotificationDetails(
    chatNotificationChannel,
    'Chat messages',
    channelDescription: 'Messages of chats and chat rooms',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
    color: Color.fromARGB(255, 35, 144, 191),
    ledColor: Color.fromARGB(255, 35, 144, 191),
    ledOnMs: 1000,
    ledOffMs: 500,
    // largeIcon: FilePathAndroidBitmap(largeIconPath),
  );
  const platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(
    id: int.tryParse(chatId) ?? 0,
    title: title,
    body: body,
    notificationDetails: platformChannelSpecifics,
    payload: chatId,
  );
}

Future<void> showLobbyInviteNotification(
  String lobbyId,
  String lobbyName,
  String senderName,
) async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

  const androidPlatformChannelSpecifics = AndroidNotificationDetails(
    lobbyInviteNotificationChannel,
    'RetroShare Invites',
    channelDescription: 'RetroShare chat lobby invitations',
    importance: Importance.max,
    priority: Priority.high,
    color: Colors.purple,
  );
  const platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await flutterLocalNotificationsPlugin.show(
    id: lobbyId.hashCode,
    title: 'New Chat Room Invite',
    body: '$senderName invited you to join "$lobbyName"',
    notificationDetails: platformChannelSpecifics,
    payload: '/notification', // Navigate to notifications screen on tap
  );
}

Future<void> showInviteCopyNotification() async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

  const androidPlatformChannelSpecifics = AndroidNotificationDetails(
    infoNotificationChannel,
    'Information',
    channelDescription: 'What the application just did',
    ticker: 'ticker',
  );
  const platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(
    id: 1111,
    title: 'Invite copied!',
    body: 'Your RetroShare invite was copied to your clipboard',
    notificationDetails: platformChannelSpecifics,
  );
}
