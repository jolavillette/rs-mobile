import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/eventsource.dart';
import 'package:retroshare/common/badge_helper.dart';
import 'package:retroshare/common/drawer.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare/routes.dart';
import 'package:retroshare/ui/home/chats_tab.dart';
import 'package:retroshare/ui/home/friends_tab.dart';
import 'package:retroshare/ui/home/home_tab.dart';
import 'package:retroshare/ui/home/more_tab.dart';
import 'package:retroshare/ui/home/people_tab.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Chat, Location;
import 'package:retroshare/common/rs_tokens.dart';

const double _desktopBreakpoint = 840;
const double _desktopSidebarWidth = 380;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // The bottom navigation of the web UI: Home, Network, People, Chat, More.
  static const _networkTab = 1, _peopleTab = 2, _chatTab = 3;
  int _tab = _chatTab;
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
  void _open(String route, {Object? arguments}) {
    if (_desktop) {
      _showDesktopRoute(route, arguments: arguments);
      return;
    }
    Navigator.pushNamed(context, route, arguments: arguments)
        .then((_) => fetchdata(context));
  }

  static const _titles = ['Home', 'Network', 'People', 'Chat', 'More'];

  List<Widget> _actions() {
    switch (_tab) {
      case _networkTab:
        return [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _open('/search', arguments: 1),
          ),
          IconButton(
            tooltip: "Friends' devices",
            icon: const Icon(Icons.devices_outlined),
            onPressed: () => _open('/friends_locations'),
          ),
        ];
      case _peopleTab:
        return [
          IconButton(
            tooltip: 'Change the active identity',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _open('/change_identity'),
          ),
        ];
      case _chatTab:
        return [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _open('/search', arguments: 0),
          ),
          IconButton(
            tooltip: 'Public chat rooms',
            icon: const Icon(Icons.public),
            onPressed: () => _open('/discover_chats'),
          ),
          IconButton(
            tooltip: 'Invitations',
            icon: const NotificationIcon(),
            onPressed: () => _open('/notification'),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget? _fab() {
    switch (_tab) {
      case _networkTab:
        return FloatingActionButton(
          tooltip: 'Add a friend',
          onPressed: () => _open('/add_friend'),
          child: const Icon(Icons.person_add_alt),
        );
      case _peopleTab:
        return FloatingActionButton(
          tooltip: 'New identity',
          onPressed: () => _open('/create_identity'),
          child: const Icon(Icons.add),
        );
      case _chatTab:
        return FloatingActionButton(
          tooltip: 'New chat room',
          onPressed: () => _open('/create_room'),
          child: const Icon(Icons.add_comment_outlined),
        );
      default:
        return null;
    }
  }

  Widget _chatIcon(bool selected) {
    return Consumer2<ChatLobby, RoomChatLobby>(
      builder: (context, chatLobby, roomChatLobby, _) {
        final unread = chatLobby.subscribedlist
                .fold(0, (sum, chat) => sum + chat.unreadCount) +
            roomChatLobby.distantUnreadCount +
            roomChatLobby.peerUnreadCount +
            chatLobby.pendingInviteCount;
        final icon = Icon(selected ? Icons.forum : Icons.forum_outlined);
        if (unread == 0) return icon;
        return Badge(
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: icon,
        );
      },
    );
  }

  Widget _buildHomeScaffold({required bool desktop}) {
    _desktop = desktop;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // The root of the app: nothing to go back to.
        automaticallyImplyLeading: false,
        title: Text(_titles[_tab]),
        actions: _actions(),
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              HomeTab(open: _open),
              FriendsTab(onOpenRoom: desktop ? _openRoom : null),
              PeopleTab(open: _open),
              ChatsTab(
                onOpenRoom: desktop ? _openRoom : null,
                onOpenPeerChat: desktop ? _openPeerChat : null,
              ),
              MoreTab(open: _open),
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
      floatingActionButton: _fab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.share_outlined),
            selectedIcon: Icon(Icons.share),
            label: 'Network',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: _chatIcon(false),
            selectedIcon: _chatIcon(true),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
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
