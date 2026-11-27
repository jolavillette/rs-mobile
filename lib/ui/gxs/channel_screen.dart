import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/gxs_body.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';

/// A channel: its posts, the newest first, read from the core a few at a
/// time. The files of a post are listed, not downloaded.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({required this.group, super.key});

  final GxsGroup group;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  static const _batch = 5;

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
      for (final post in loaded) {
        await content.markRead(widget.group.id, post.meta);
      }
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

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final remaining = _metas.length - _asked;
    return Scaffold(
      appBar: AppBar(title: Text(widget.group.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
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
                      child: Text(_error!, style: TextStyle(color: rs.inkDim)),
                    )
                  else if (_metas.isEmpty && _subscribed)
                    Padding(
                      padding: const EdgeInsets.all(RsScale.s4),
                      child: Text(
                        'No post yet. They arrive a few at a time while the '
                        'app is on screen: pull down to read again.',
                        style: TextStyle(color: rs.inkDim),
                      ),
                    ),
                  for (final post in _posts) _post(post),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(RsScale.s4),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (remaining > 0)
                    TextButton(
                      onPressed: _loadMore,
                      child: Text('$remaining older'),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _post(GxsPost post) {
    final rs = context.rs;
    final thumbnail = post.thumbnail;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        RsScale.s3,
        RsScale.s3,
        RsScale.s3,
        0,
      ),
      padding: const EdgeInsets.all(RsScale.s3),
      decoration: BoxDecoration(
        color: rs.surface,
        border: Border.all(color: rs.line),
        borderRadius: BorderRadius.circular(RsScale.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.meta.title.isEmpty ? '(no title)' : post.meta.title,
            style: TextStyle(
              fontSize: RsScale.tH3,
              fontWeight: FontWeight.w600,
              color: rs.ink,
            ),
          ),
          Text(
            gxsDate(post.meta.published),
            style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
          ),
          if (thumbnail != null)
            Padding(
              padding: const EdgeInsets.only(top: RsScale.s2),
              child: Image.memory(
                thumbnail,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          if (post.body.trim().isNotEmpty) GxsBody(post.body),
          for (final file in post.files)
            Padding(
              padding: const EdgeInsets.only(top: RsScale.s1),
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                    color: rs.inkDim,
                  ),
                  const SizedBox(width: RsScale.s2),
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: RsScale.tRow),
                    ),
                  ),
                  Text(
                    gxsSize(file.size),
                    style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
