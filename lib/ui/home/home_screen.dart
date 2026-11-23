import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/eventsource.dart';
import 'package:retroshare/common/badge_helper.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare/routes.dart';
import 'package:retroshare/ui/home/chats_tab.dart';
import 'package:retroshare/ui/home/home_tab.dart';
import 'package:retroshare/ui/home/more_tab.dart';
import 'package:retroshare/ui/home/network_tab.dart';
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
  static const _chatTab = 3;
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

  Future<void> _fetchInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final chatLobby = Provider.of<ChatLobby>(context, listen: false);
      await chatLobby.fetchAndUpdate();
      await Provider.of<RoomChatLobby>(context, listen: false).fetchAndUpdate();
      await Provider.of<FriendLocations>(context, listen: false)
          .fetchfriendLocation();
      await chatLobby.checkForNewInvites();
      await BadgeHelper.updateAppBadge(context);

      final authToken =
          Provider.of<AccountCredentials>(context, listen: false).authtoken;
      if (authToken != null && !_isEventRegistered) {
        await registerChatEvent(context, authToken);
        _isEventRegistered = true;
      }
    } catch (e) {
      debugPrint('Error during initial data fetch: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load initial data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> fetchdata(BuildContext context) async {
    try {
      final chatLobby = Provider.of<ChatLobby>(context, listen: false);
      await chatLobby.fetchAndUpdate();
      await Provider.of<RoomChatLobby>(context, listen: false).fetchAndUpdate();
      await Provider.of<FriendLocations>(context, listen: false)
          .fetchfriendLocation();
      await chatLobby.checkForNewInvites();
    } catch (e) {
      debugPrint('Error during fetchdata: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to refresh data: $e')),
      );
    }
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: _badged(Icons.share_outlined, _peerUnread),
            selectedIcon: _badged(Icons.share, _peerUnread),
            label: 'Network',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: _badged(Icons.forum_outlined, _chatUnread),
            selectedIcon: _badged(Icons.forum, _chatUnread),
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
