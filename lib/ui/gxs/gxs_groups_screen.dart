import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_changes.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/apiUtils/mobile_services.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';

/// The forums, or the channels: those this phone is subscribed to, then,
/// folded, those only the friends that serve it are subscribed to. While the
/// service is off the page says so and offers to turn it on.
class GxsGroupsScreen extends StatefulWidget {
  const GxsGroupsScreen({required this.kind, this.open, super.key});

  final GxsContentKind kind;

  /// Set when the list is a tab of the home, which then supplies the title
  /// bar: opens a named route, the future ending when the page is closed.
  final Future<void> Function(String route, {Object? arguments})? open;

  @override
  State<GxsGroupsScreen> createState() => _GxsGroupsScreenState();
}

class _GxsGroupsScreenState extends State<GxsGroupsScreen> {
  GxsContent? _content;
  GxsChangeWatch? _watch;
  bool _loading = true;
  bool _serviceOn = false;
  String? _error;
  List<GxsGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    final content = _content ??= GxsContent(widget.kind, token);
    // The list follows the groups and posts that arrive.
    _watch ??= GxsChangeWatch(token, widget.kind, _load);
    try {
      final on = await content.serviceOn();
      final groups = (on ? await content.groups() : <GxsGroup>[])
        ..sort((a, b) {
          final byActivity = b.lastPost.compareTo(a.lastPost);
          return byActivity != 0
              ? byActivity
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _serviceOn = on;
        _groups = groups;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      debugPrint('${widget.kind.title}: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not read the ${widget.kind.noun}s.';
        _loading = false;
      });
    }
  }

  Future<void> _turnOn() async {
    final auth = Provider.of<AccountCredentials>(context, listen: false);
    final locationId = auth.loggedinAccount?.locationId;
    final content = _content;
    if (content == null || locationId == null) return;
    setState(() => _loading = true);
    try {
      if (!await content.setServiceOn(true)) {
        throw Exception('the core refused');
      }
      // Remembered for this node, or the next login turns it off again.
      await setOptedIn(locationId, widget.kind.serviceType, true);
    } catch (error) {
      debugPrint('${widget.kind.title}: could not turn on: $error');
    }
    await _load();
  }

  Future<void> _open(GxsGroup group) async {
    final route = widget.kind == GxsContentKind.forums ? '/forum' : '/channel';
    final open = widget.open;
    if (open != null) {
      await open(route, arguments: group);
    } else {
      await Navigator.pushNamed(context, route, arguments: group);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _load, child: _body(context));
    if (widget.open != null) return body;
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.title)),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    final rs = context.rs;
    if (_error != null) return _message(_error!);
    if (!_serviceOn) {
      return ListView(
        padding: const EdgeInsets.all(RsScale.s5),
        children: [
          Text(
            '${widget.kind.title} are off on this phone.',
            style: TextStyle(fontSize: RsScale.tH3, color: rs.ink),
          ),
          const SizedBox(height: RsScale.s3),
          Text(
            'Turned on, this phone gets the ${widget.kind.noun}s of the '
            'friends that serve it, while the app is on screen only. It '
            'uses some mobile data and storage. You can turn it off again in '
            'Preferences, Permissions.',
            style: TextStyle(fontSize: RsScale.tBody, color: rs.inkBody),
          ),
          const SizedBox(height: RsScale.s5),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _turnOn,
              child: Text('Turn on ${widget.kind.title}'),
            ),
          ),
        ],
      );
    }
    if (_groups.isEmpty) {
      return _message(
        'No ${widget.kind.noun} yet. They come from the friends that serve '
        'this phone: pull down to read the list again.',
      );
    }
    final subscribed = _groups.where((g) => g.subscribed).toList();
    final others = _groups.where((g) => !g.subscribed).toList();
    return ListView(
      children: [
        _header('Subscribed'),
        if (subscribed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RsScale.s4,
              vertical: RsScale.s2,
            ),
            child: Text(
              'None yet. Open one below to subscribe to it.',
              style: TextStyle(fontSize: RsScale.tRow, color: rs.inkDim),
            ),
          ),
        for (final group in subscribed) _tile(group),
        if (others.isNotEmpty)
          Theme(
            // No rule above and below the open section.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'UNSUBSCRIBED (${others.length})',
                style: TextStyle(
                  fontSize: RsScale.tLabel,
                  letterSpacing: 0.6,
                  color: rs.inkDim,
                ),
              ),
              children: [for (final group in others) _tile(group)],
            ),
          ),
      ],
    );
  }

  Widget _message(String text) => ListView(
        padding: const EdgeInsets.all(RsScale.s5),
        children: [
          Text(
            text,
            style: TextStyle(fontSize: RsScale.tBody, color: context.rs.inkDim),
          ),
        ],
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
          RsScale.s4,
          RsScale.s4,
          RsScale.s4,
          RsScale.s1,
        ),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: RsScale.tLabel,
            letterSpacing: 0.6,
            color: context.rs.inkDim,
          ),
        ),
      );

  Widget _tile(GxsGroup group) {
    final rs = context.rs;
    final details = [
      if (group.visiblePosts > 0) '${group.visiblePosts} posts',
      if (group.lastPost > 0) 'last ${gxsDate(group.lastPost)}',
    ].join(' · ');
    return ListTile(
      leading: Icon(
        widget.kind == GxsContentKind.forums
            ? Icons.forum_outlined
            : Icons.campaign_outlined,
        color: group.subscribed ? rs.brand : rs.inkFaint,
      ),
      title: Text(
        group.name.isEmpty ? group.id : group.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: details.isEmpty ? null : Text(details),
      onTap: () => _open(group),
    );
  }
}
