import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/channel_post_screen.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';
import 'package:retroshare/ui/gxs/gxs_group_menu.dart';

/// A channel: the thumbnails of its posts, the newest first, read from the
/// core a few at a time as the page is scrolled. A tap opens the post.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({required this.group, super.key});

  final GxsGroup group;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  static const _batch = 12;

  GxsContent? _content;
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;
  bool _subscribed = false;
  String _description = '';
  List<GxsPostMeta> _metas = const [];
  final List<GxsPost> _posts = [];
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _subscribed = widget.group.subscribed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    final content = _content ??= GxsContent(GxsContentKind.channels, token);
    try {
      final info = await content.groupInfo(widget.group.id);
      final metas = await content.postMetas(widget.group.id)
        ..sort((a, b) => b.published.compareTo(a.published));
      if (!mounted) return;
      setState(() {
        _subscribed = info?.group.subscribed ?? _subscribed;
        _description = info?.description ?? '';
        _metas = metas;
        _posts.clear();
        _asked = 0;
        _error = null;
        _loading = false;
      });
      await _loadMore();
    } catch (error) {
      debugPrint('Channel ${widget.group.id}: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not read this channel.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final content = _content;
    if (content == null || _loadingMore || _asked >= _metas.length) return;
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
    final rs = context.rs;
    final remaining = _metas.length - _asked;
    return Scaffold(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scroll) {
                  if (scroll.metrics.extentAfter < 600) _loadMore();
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GxsGroupBar(
                            kind: GxsContentKind.channels,
                            subscribed: _subscribed,
                            description: _description,
                            busy: _busy,
                            onSubscribe: _subscribe,
                          ),
                          const Divider(height: 1),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(RsScale.s4),
                              child: Text(
                                _error!,
                                style: TextStyle(color: rs.inkDim),
                              ),
                            )
                          else if (_metas.isEmpty && _subscribed)
                            Padding(
                              padding: const EdgeInsets.all(RsScale.s4),
                              child: Text(
                                'No post yet. They arrive a few at a time '
                                'while the app is on screen: pull down to '
                                'read again.',
                                style: TextStyle(color: rs.inkDim),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(RsScale.s2),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
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
                    SliverToBoxAdapter(
                      child: _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(RsScale.s4),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : remaining > 0
                              ? TextButton(
                                  onPressed: _loadMore,
                                  child: Text('$remaining older'),
                                )
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
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
