import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_changes.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/channel_post_screen.dart';
import 'package:retroshare/ui/gxs/gxs_file_tile.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';
import 'package:retroshare/ui/gxs/gxs_group_menu.dart';

/// A channel, in the desktop's three tabs: its details; the thumbnails of
/// its posts, the newest first, read from the core a few at a time as the
/// page is scrolled, a tap opening the post; and the files of those posts.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({required this.group, super.key});

  final GxsGroup group;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  static const _batch = 12;

  GxsContent? _content;
  GxsChangeWatch? _watch;
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;
  bool _subscribed = false;
  String _description = '';
  GxsGroupInfo? _info;
  List<GxsPostMeta> _metas = const [];
  final List<GxsPost> _posts = [];
  int _asked = 0;

  /// The reads of the page, one after the other: each starts from what the
  /// one before left.
  Future<void> _reads = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _subscribed = widget.group.subscribed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _serial(Future<void> Function() read) {
    final done = _reads.then<void>((_) => mounted ? read() : null);
    _reads = done.catchError((Object _) {});
    return done;
  }

  /// Reads the channel from its start.
  Future<void> _load() => _serial(() async {
        await _readGroup(keep: false);
        await _readMore();
      });

  /// Reads the channel again, when the page is pulled or the core reports
  /// news: the posts already read stay, the new ones are added, and the
  /// page keeps its place.
  Future<void> _refresh() => _serial(() => _readGroup(keep: true));

  /// Reads the next posts.
  Future<void> _loadMore() {
    if (_loadingMore || _asked >= _metas.length) return Future<void>.value();
    _loadingMore = true;
    return _serial(_readMore);
  }

  Future<void> _readGroup({required bool keep}) async {
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    final content = _content ??= GxsContent(GxsContentKind.channels, token);
    _watch ??= GxsChangeWatch(
      token,
      GxsContentKind.channels,
      _refresh,
      groupId: widget.group.id,
    );
    try {
      final info = await content.groupInfo(widget.group.id);
      final metas = await content.postMetas(widget.group.id)
        ..sort((a, b) => b.published.compareTo(a.published));
      // The posts to show now: none from the start; when kept, those shown
      // and the new ones, a batch of them at most.
      final known = {for (final meta in _metas) meta.id};
      final added = metas.where((meta) => !known.contains(meta.id)).length;
      final count = keep
          ? (_asked + added.clamp(0, _batch)).clamp(0, metas.length)
          : 0;
      final wanted = metas.take(count).toList();
      final shown = {for (final post in _posts) post.meta.id: post};
      final missing = [
        for (final meta in wanted)
          if (!shown.containsKey(meta.id)) meta.id,
      ];
      if (missing.isNotEmpty) {
        for (final post in await content.posts(widget.group.id, missing)) {
          shown[post.meta.id] = post;
        }
      }
      if (!mounted) return;
      setState(() {
        _subscribed = info?.group.subscribed ?? _subscribed;
        _description = info?.description ?? '';
        _info = info;
        _metas = metas;
        _posts
          ..clear()
          ..addAll([
            for (final meta in wanted)
              if (shown[meta.id] case final post?) post,
          ]);
        _asked = count;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Channel ${widget.group.id}: $error');
      if (!mounted || (keep && _posts.isNotEmpty)) return;
      setState(() {
        _error = 'Could not read this channel.';
        _loading = false;
      });
    }
  }

  Future<void> _readMore() async {
    final content = _content;
    if (content == null || _asked >= _metas.length) {
      _loadingMore = false;
      return;
    }
    final slice = _metas.sublist(
      _asked,
      (_asked + _batch).clamp(0, _metas.length),
    );
    setState(() => _loadingMore = true);
    try {
      final loaded = await content.posts(
        widget.group.id,
        slice.map((meta) => meta.id).toList(),
      )
        ..sort((a, b) => b.meta.published.compareTo(a.meta.published));
      _posts.addAll(loaded);
    } catch (error) {
      debugPrint('Channel ${widget.group.id}: $error');
    }
    _asked += slice.length;
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _subscribe(bool subscribe) async {
    final content = _content;
    if (content == null) return;
    setState(() => _busy = true);
    try {
      await content.subscribe(widget.group.id, subscribe);
      _subscribed = subscribe;
    } catch (error) {
      debugPrint('Channel ${widget.group.id}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change this channel.')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  /// Every post of the channel: the one shown in the grid where it is
  /// loaded, as that is the one whose read mark the grid draws.
  List<GxsPostMeta> _knownMetas() {
    final shown = {for (final post in _posts) post.meta.id: post.meta};
    return [for (final meta in _metas) shown[meta.id] ?? meta];
  }

  Future<void> _openPost(GxsPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChannelPostScreen(groupId: widget.group.id, post: post),
      ),
    );
    // The post is read now.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      // The posts first, as the desktop opens a channel.
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.group.name),
          actions: [
            GxsGroupMenu(
              content: _content,
              groupId: widget.group.id,
              subscribed: _subscribed,
              posts: _knownMetas,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Posts'),
              Tab(text: 'All files'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [_details(), _postsTab(), _filesTab()],
              ),
      ),
    );
  }

  /// Loads older posts as a list nears its end.
  Widget _scrolling(Widget child) => RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (scroll) {
            if (scroll.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: child,
        ),
      );

  /// The channel's picture, description and figures, and the button to
  /// subscribe or unsubscribe.
  Widget _details() {
    final rs = context.rs;
    final group = _info?.group ?? widget.group;
    final image = _info?.image;
    final figures = [
      if (group.visiblePosts > 0) '${group.visiblePosts} posts',
      if (group.lastPost > 0) 'last post ${gxsDate(group.lastPost)}',
      if (group.popularity > 0)
        group.popularity == 1
            ? '1 friend subscribed'
            : '${group.popularity} friends subscribed',
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RsScale.s4,
                RsScale.s4,
                RsScale.s4,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RsScale.rMd),
                  child: Image.memory(
                    image,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          if (figures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RsScale.s4,
                RsScale.s3,
                RsScale.s4,
                0,
              ),
              child: Text(
                figures.join(' · '),
                style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
              ),
            ),
          GxsGroupBar(
            kind: GxsContentKind.channels,
            subscribed: _subscribed,
            description: _description,
            busy: _busy,
            onSubscribe: _subscribe,
          ),
        ],
      ),
    );
  }

  /// What a tab says before its content: an error, no post yet, or not
  /// subscribed, with the button to subscribe.
  List<Widget> _notice() {
    final rs = context.rs;
    return [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(RsScale.s4),
          child: Text(_error!, style: TextStyle(color: rs.inkDim)),
        )
      else if (!_subscribed)
        Padding(
          padding: const EdgeInsets.all(RsScale.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Not subscribed: this phone gets none of its posts.',
                  style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _subscribe(true),
                child: const Text('Subscribe'),
              ),
            ],
          ),
        )
      else if (_metas.isEmpty)
        Padding(
          padding: const EdgeInsets.all(RsScale.s4),
          child: Text(
            'No post yet. They arrive a few at a time while the app is on '
            'screen: pull down to read again.',
            style: TextStyle(color: rs.inkDim),
          ),
        ),
    ];
  }

  /// The end of a list: loading, or the button for the older posts.
  Widget _more() {
    final remaining = _metas.length - _asked;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(RsScale.s4),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (remaining <= 0) return const SizedBox.shrink();
    return TextButton(
      onPressed: _loadMore,
      child: Text('$remaining older'),
    );
  }

  Widget _postsTab() {
    final notice = _notice();
    return _scrolling(
      CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (notice.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: notice,
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(RsScale.s2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                // Three to a row on a phone.
                maxCrossAxisExtent: 130,
                mainAxisSpacing: RsScale.s2,
                crossAxisSpacing: RsScale.s2,
                childAspectRatio: 0.6,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _card(_posts[index]),
                childCount: _posts.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _more()),
        ],
      ),
    );
  }

  /// The files of the posts read so far, newest post first, each under the
  /// title of its post.
  Widget _filesTab() {
    final rs = context.rs;
    final notice = _notice();
    final withFiles = _posts.where((post) => post.files.isNotEmpty).toList();
    return _scrolling(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ...notice,
          if (notice.isEmpty && withFiles.isEmpty && !_loadingMore)
            Padding(
              padding: const EdgeInsets.all(RsScale.s4),
              child: Text(
                'No file in the posts read so far.',
                style: TextStyle(color: rs.inkDim),
              ),
            ),
          for (final post in withFiles) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RsScale.s4,
                RsScale.s3,
                RsScale.s4,
                0,
              ),
              child: Text(
                '${post.meta.title.isEmpty ? '(no title)' : post.meta.title}'
                ' · ${gxsDate(post.meta.published)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
              ),
            ),
            for (final file in post.files)
              GxsFileTile(file, key: ValueKey('${post.meta.id}/${file.hash}')),
          ],
          _more(),
        ],
      ),
    );
  }

  static String _fileCount(int count) =>
      count == 1 ? '1 file' : '$count files';

  /// A post in the grid: its thumbnail, its title and its date.
  Widget _card(GxsPost post) {
    final rs = context.rs;
    final thumbnail = post.thumbnail;
    final placeholder = ColoredBox(
      color: rs.sunken,
      child: Center(
        child: Icon(Icons.campaign_outlined, size: 32, color: rs.inkFaint),
      ),
    );
    return Material(
      color: rs.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: rs.line),
        borderRadius: BorderRadius.circular(RsScale.rMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPost(post),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // The whole picture, whatever its shape: never cropped.
              child: thumbnail == null
                  ? placeholder
                  : ColoredBox(
                      color: rs.sunken,
                      child: Image.memory(
                        thumbnail,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            placeholder,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(RsScale.s1 + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.meta.title.isEmpty ? '(no title)' : post.meta.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RsScale.tLabel,
                      fontWeight:
                          post.meta.unread ? FontWeight.w700 : FontWeight.w500,
                      color: rs.ink,
                    ),
                  ),
                  Text(
                    [
                      gxsDate(post.meta.published),
                      if (post.files.isNotEmpty)
                        _fileCount(post.files.length),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: RsScale.tMicro, color: rs.inkDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
