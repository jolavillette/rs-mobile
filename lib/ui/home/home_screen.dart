import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/eventsource.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/badge_helper.dart';
import 'package:retroshare/common/logout.dart';
import 'package:retroshare/common/quit.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare/routes.dart';
import 'package:retroshare/ui/gxs/gxs_groups_screen.dart';
import 'package:retroshare/ui/home/chats_tab.dart';
import 'package:retroshare/ui/home/home_tab.dart';
import 'package:retroshare/ui/home/network_tab.dart';
import 'package:retroshare/ui/home/people_tab.dart';
import 'package:retroshare/ui/home/scroll_nav_bar.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Chat, Location;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retroshare/common/rs_tokens.dart';

const double _desktopBreakpoint = 840;
const double _desktopSidebarWidth = 380;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // The bottom navigation: the tabs Home, Network, People, Chat, Forums and
  // Channels, then the pages Preferences and Statistics, then Quit or Log out.
  static const _chatTab = 3;
  static const _forumsTab = 4;
  static const _channelsTab = 5;
  static const _tabCount = 6;
  // The tab the app was on when it was left, opened again at start.
  static const _tabKey = 'home_tab';
  int _tab = _chatTab;
  // Forums and Channels are built, and read from the core, once opened.
  final Set<int> _opened = {};
  bool _desktop = false;
  bool _isInit = true;
  bool _isLoading = false;
  bool _isEventRegistered = false;
  Timer? _inviteCheckTimer;
  final GlobalKey<NavigatorState> _desktopNavigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> _openRoom(Chat chat, bool isRoom) async {
    _showDesktopRoute(
      '/room',
      arguments: {'isRoom': isRoom, 'chatData': chat},
    );
  }

  Future<void> _openPeerChat(Location location) async {
    _showDesktopRoute(
      '/peer_chat',
      arguments: {'location': location},
    );
  }

  void _showDesktopRoute(String routeName, {Object? arguments}) {
    final navigator = _desktopNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.pushNamed(routeName, arguments: arguments);
  }

  @override
  void initState() {
    super.initState();
    _isInit = true;
    _restoreTab();

    // Start periodic invite check
    _inviteCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        Provider.of<ChatLobby>(context, listen: false).checkForNewInvites();
      }
    });
  }

  @override
  void didChangeDependencies() {
    if (_isInit) {
      _fetchInitialData();

      // Listen to both providers for unread changes to update the app icon badge
      Provider.of<ChatLobby>(context).addListener(_updateAppBadge);
      Provider.of<RoomChatLobby>(context).addListener(_updateAppBadge);
    }
    _isInit = false;
    super.didChangeDependencies();
  }

  /// Opens the tab the app was on when it was left; Chat the first time.
  Future<void> _restoreTab() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getInt(_tabKey);
      if (saved != null && saved >= 0 && saved < _tabCount && mounted) {
        setState(() {
          _tab = saved;
          _opened.add(saved);
        });
      }
    } catch (e) {
      debugPrint('Cannot read the last tab: $e');
    }
  }

  void _selectTab(int tab) {
    setState(() {
      _tab = tab;
      _opened.add(tab);
    });
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_tabKey, tab))
        .catchError((Object e) {
      debugPrint('Cannot keep the tab: $e');
      return false;
    });
  }

  void _updateAppBadge() {
    if (mounted) {
      BadgeHelper.updateAppBadge(context);
    }
  }

  /// Runs one step of the data loading. A failing step is logged and does
  /// not stop the others: an identity whose details the core has not loaded
  /// yet must not leave the friends, the invitations or the live chat events
  /// unloaded. Returns whether the step succeeded.
  static Future<bool> _loadStep(
    String name,
    Future<void> Function() step,
  ) async {
    try {
      await step();
      return true;
    } catch (e) {
      debugPrint('Data loading: $name failed: $e');
      return false;
    }
  }

  /// Loads rooms, identities, friends and invitations, each on its own. The
  /// providers are looked up before the first await: the screen may be gone
  /// by the time a step ends.
  Future<List<String>> _loadData(BuildContext context) async {
    final chatLobby = Provider.of<ChatLobby>(context, listen: false);
    final roomChat = Provider.of<RoomChatLobby>(context, listen: false);
    final friends = Provider.of<FriendLocations>(context, listen: false);
    final failed = <String>[];
    for (final (name, step) in <(String, Future<void> Function())>[
      ('chat rooms', chatLobby.fetchAndUpdate),
      ('identities', roomChat.fetchAndUpdate),
      ('friends', friends.fetchfriendLocation),
      ('invitations', chatLobby.checkForNewInvites),
    ]) {
      if (!await _loadStep(name, step)) failed.add(name);
    }
    return failed;
  }

  Future<void> _fetchInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final failed = await _loadData(context);
    if (mounted) {
      await _loadStep('badge', () => BadgeHelper.updateAppBadge(context));
    }
    // The live chat events are registered whatever failed above.
    if (mounted && authToken != null && !_isEventRegistered) {
      final registered = await _loadStep(
        'chat events',
        () => registerChatEvent(context, authToken),
      );
      if (registered) {
        _isEventRegistered = true;
      } else {
        failed.add('chat events');
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load: ${failed.join(', ')}')),
      );
    }
  }

  Future<void> fetchdata(BuildContext context) async {
    final failed = await _loadData(context);
    if (!mounted || failed.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not refresh: ${failed.join(', ')}')),
    );
  }

  @override
  void dispose() {
    _inviteCheckTimer?.cancel();
    // Remove listeners to avoid memory leaks
    try {
      Provider.of<ChatLobby>(context, listen: false)
          .removeListener(_updateAppBadge);
      Provider.of<RoomChatLobby>(context, listen: false)
          .removeListener(_updateAppBadge);
    } catch (_) {
      // Providers might be already disposed during logout/shutdown
    }
    super.dispose();
  }

  /// Opens [route] in the detail pane on a desktop layout, as a page on a
  /// phone, and refreshes the lists when the page is closed.
  /// The returned future ends when the page is closed (at once on a desktop
  /// layout).
  Future<void> _open(String route, {Object? arguments}) async {
    if (_desktop) {
      _showDesktopRoute(route, arguments: arguments);
      return;
    }
    await Navigator.pushNamed(context, route, arguments: arguments);
    if (mounted) unawaited(fetchdata(context));
  }

  static const _titles = [
    'Home',
    'Network',
    'People',
    'Chat',
    'Forums',
    'Channels',
  ];

  /// The entries of the bottom navigation, in the order of [_titles] for the
  /// tabs.
  List<ScrollNavItem> _navItems(BuildContext context) {
    ScrollNavItem tab(int index, Widget icon, Widget selectedIcon) =>
        ScrollNavItem(
          label: _titles[index],
          icon: icon,
          selectedIcon: selectedIcon,
          onTap: () => _selectTab(index),
        );
    return [
      tab(0, const Icon(Icons.home_outlined), const Icon(Icons.home)),
      tab(
        1,
        _badged(Icons.share_outlined, _peerUnread),
        _badged(Icons.share, _peerUnread),
      ),
      tab(2, const Icon(Icons.people_outline), const Icon(Icons.people)),
      tab(
        _chatTab,
        _badged(Icons.chat_bubble_outline, _chatUnread),
        _badged(Icons.chat_bubble, _chatUnread),
      ),
      tab(
        _forumsTab,
        const Icon(Icons.forum_outlined),
        const Icon(Icons.forum),
      ),
      tab(
        _channelsTab,
        const Icon(Icons.campaign_outlined),
        const Icon(Icons.campaign),
      ),
      ScrollNavItem(
        label: 'Preferences',
        icon: const Icon(Icons.settings_outlined),
        onTap: () => _open('/settings'),
      ),
      ScrollNavItem(
        label: 'Statistics',
        icon: const Icon(Icons.query_stats_outlined),
        onTap: () => _open('/statistics'),
      ),
      if (Platform.isAndroid)
        ScrollNavItem(
          label: 'Quit',
          icon: const Icon(Icons.power_settings_new),
          color: context.rs.downInk,
          onTap: () => confirmAndQuit(context),
        ),
      if (Platform.isIOS)
        ScrollNavItem(
          label: 'Log out',
          icon: const Icon(Icons.logout),
          color: context.rs.downInk,
          onTap: () => confirmAndLogOut(context),
        ),
    ];
  }

  /// A navigation icon with the count of what is unread behind it, as the
  /// web UI badges its menu: open chats, rooms and invitations on Chat,
  /// direct chats on Network too.
  Widget _badged(IconData icon, int Function(ChatLobby, RoomChatLobby) count) {
    return Consumer2<ChatLobby, RoomChatLobby>(
      builder: (context, chatLobby, roomChatLobby, _) {
        final unread = count(chatLobby, roomChatLobby);
        if (unread == 0) return Icon(icon);
        return Badge(
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(icon),
        );
      },
    );
  }

  static int _chatUnread(ChatLobby chatLobby, RoomChatLobby roomChatLobby) =>
      chatLobby.subscribedlist.fold(0, (sum, chat) => sum + chat.unreadCount) +
      chatLobby.pendingInviteCount +
      roomChatLobby.distantUnreadCount +
      roomChatLobby.peerUnreadCount;

  static int _peerUnread(ChatLobby _, RoomChatLobby roomChatLobby) =>
      roomChatLobby.peerUnreadCount;

  Widget _buildHomeScaffold({required bool desktop}) {
    _desktop = desktop;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // The root of the app: nothing to go back to.
        automaticallyImplyLeading: false,
        title: Text(_titles[_tab]),
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              HomeTab(open: _open),
              NetworkTab(
                open: _open,
                onOpenPeerChat: desktop ? _openPeerChat : null,
              ),
              PeopleTab(
                open: _open,
                onOpenRoom: desktop ? _openRoom : null,
              ),
              ChatsTab(
                open: _open,
                onOpenRoom: desktop ? _openRoom : null,
                onOpenPeerChat: desktop ? _openPeerChat : null,
              ),
              for (final (tab, kind) in const [
                (_forumsTab, GxsContentKind.forums),
                (_channelsTab, GxsContentKind.channels),
              ])
                if (_opened.contains(tab))
                  GxsGroupsScreen(kind: kind, open: _open)
                else
                  const SizedBox.shrink(),
            ],
          ),
          if (_isLoading)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ScrollNavBar(
        selectedIndex: _tab,
        items: _navItems(context),
      ),
    );
  }

  Widget _emptyDesktopDetail() {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 72,
                color: context.rs.brand,
              ),
              const SizedBox(height: 20),
              Text(
                'Select a conversation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a chat or contact from the list to start messaging.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= _desktopBreakpoint;
          if (!desktop) return _buildHomeScaffold(desktop: false);

          final sidebarWidth =
              constraints.maxWidth < 1050 ? 340.0 : _desktopSidebarWidth;
          return Row(
            children: [
              SizedBox(
                width: sidebarWidth,
                child: _buildHomeScaffold(desktop: true),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              ),
              Expanded(
                child: Navigator(
                  key: _desktopNavigatorKey,
                  initialRoute: '/',
                  onGenerateInitialRoutes: (_, initialRoute) => [
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: '/'),
                      builder: (_) => _emptyDesktopDetail(),
                    ),
                  ],
                  onGenerateRoute: RouteGenerator.generateRoute,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
