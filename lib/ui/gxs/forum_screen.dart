import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/gxs_body.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';
import 'package:retroshare/ui/gxs/gxs_group_menu.dart';

/// A thread of a forum: the post that starts it and its answers.
class ForumThread {
  ForumThread(this.root, this.posts);

  final GxsPostMeta root;

  /// Every post of the thread, the first included, oldest first.
  final List<GxsPostMeta> posts;

  int get lastActivity => posts.last.published;
  int get unread => posts.where((post) => post.unread).length;
}

/// A forum: its threads, the most recently active first.
class ForumScreen extends StatefulWidget {
  const ForumScreen({required this.group, super.key});

  final GxsGroup group;

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  GxsContent? _content;
  GxsAuthorNames? _names;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _subscribed = false;
  String _description = '';
  List<ForumThread> _threads = const [];

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
    final content = _content ??= GxsContent(GxsContentKind.forums, token);
    final names = _names ??= GxsAuthorNames(token);
    try {
      final info = await content.groupInfo(widget.group.id);
      final metas = await content.postMetas(widget.group.id);
      final threads = _threadsOf(metas);
      if (!mounted) return;
      setState(() {
        _subscribed = info?.group.subscribed ?? _subscribed;
        _description = info?.description ?? '';
        _threads = threads;
        _error = null;
        _loading = false;
      });
      if (await names.load(threads.map((t) => t.root.authorId)) && mounted) {
        setState(() {});
      }
    } catch (error) {
      debugPrint('Forum ${widget.group.id}: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not read this forum.';
        _loading = false;
      });
    }
  }

  /// Groups the posts by the thread they belong to. An answer whose first
  /// post is not here yet (not received, or older than what the phone asks
  /// for) is left out until it comes.
  static List<ForumThread> _threadsOf(List<GxsPostMeta> metas) {
    final roots = <String, GxsPostMeta>{
      for (final meta in metas)
        if (meta.isRoot) meta.versionOf: meta,
    };
    final posts = <String, List<GxsPostMeta>>{
      for (final key in roots.keys) key: [roots[key]!],
    };
    for (final meta in metas) {
      if (meta.isRoot) continue;
      posts[meta.threadId]?.add(meta);
    }
    return [
      for (final key in roots.keys)
        ForumThread(
          roots[key]!,
          posts[key]!..sort((a, b) => a.published.compareTo(b.published)),
        ),
    ]..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  Future<void> _subscribe(bool subscribe) async {
    final content = _content;
    if (content == null) return;
    setState(() => _busy = true);
    try {
      await content.subscribe(widget.group.id, subscribe);
      _subscribed = subscribe;
    } catch (error) {
      debugPrint('Forum ${widget.group.id}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change this forum.')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _open(ForumThread thread) async {
    await Navigator.pushNamed(
      context,
      '/forum_thread',
      arguments: {'group': widget.group, 'thread': thread},
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          GxsGroupMenu(
            content: _content,
            groupId: widget.group.id,
            subscribed: _subscribed,
            posts: () => [for (final thread in _threads) ...thread.posts],
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
              child: ListView(
                children: [
                  GxsGroupBar(
                    kind: GxsContentKind.forums,
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
                  else if (_threads.isEmpty && _subscribed)
                    Padding(
                      padding: const EdgeInsets.all(RsScale.s4),
                      child: Text(
                        'No post yet. They arrive a few at a time while the '
                        'app is on screen: pull down to read again.',
                        style: TextStyle(color: rs.inkDim),
                      ),
                    ),
                  for (final thread in _threads) _tile(thread),
                ],
              ),
            ),
    );
  }

  Widget _tile(ForumThread thread) {
    final rs = context.rs;
    final unread = thread.unread;
    final answers = thread.posts.length - 1;
    final details = [
      _names?.nameOf(thread.root.authorId) ?? '',
      gxsDate(thread.lastActivity),
      if (answers > 0) '$answers answers',
    ].where((text) => text.isNotEmpty).join(' · ');
    final author = _names?.identityOf(thread.root.authorId);
    return ListTile(
      leading: author == null
          ? const SizedBox(width: 40, child: Icon(Icons.person_outline))
          : IdentityAvatar(identity: author),
      title: Text(
        thread.root.title.isEmpty ? '(no title)' : thread.root.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(details),
      trailing: unread > 0
          ? CircleAvatar(
              radius: 11,
              backgroundColor: rs.brand,
              child: Text(
                '$unread',
                style: TextStyle(fontSize: RsScale.tMicro, color: rs.onBrand),
              ),
            )
          : null,
      onTap: () => _open(thread),
    );
  }
}

/// The posts of a thread, oldest first. Their text is read from the core a
/// few posts at a time, and a post shown is marked as read.
class ForumThreadScreen extends StatefulWidget {
  const ForumThreadScreen({
    required this.group,
    required this.thread,
    super.key,
  });

  final GxsGroup group;
  final ForumThread thread;

  @override
  State<ForumThreadScreen> createState() => _ForumThreadScreenState();
}

class _ForumThreadScreenState extends State<ForumThreadScreen> {
  static const _batch = 10;

  GxsContent? _content;
  GxsAuthorNames? _names;
  final Map<String, String> _bodies = {};
  int _asked = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  Future<void> _loadMore() async {
    final posts = widget.thread.posts;
    if (_loadingMore || _asked >= posts.length) return;
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    final content = _content ??= GxsContent(GxsContentKind.forums, token);
    final names = _names ??= GxsAuthorNames(token);
    final slice = posts.sublist(
      _asked,
      (_asked + _batch).clamp(0, posts.length),
    );
    setState(() => _loadingMore = true);
    try {
      final loaded = await content.posts(
        widget.group.id,
        slice.map((post) => post.id).toList(),
      );
      for (final post in loaded) {
        _bodies[post.meta.id] = post.body;
      }
      await names.load(slice.map((post) => post.authorId));
      for (final post in slice) {
        await content.markRead(widget.group.id, post);
      }
    } catch (error) {
      debugPrint('Forum thread ${widget.thread.root.id}: $error');
    }
    _asked += slice.length;
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final posts = widget.thread.posts;
    final shown = _asked.clamp(0, posts.length);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.thread.root.title.isEmpty
              ? widget.group.name
              : widget.thread.root.title,
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: RsScale.s2),
        itemCount: shown + 1,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == shown) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(RsScale.s4),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (shown >= posts.length) return const SizedBox.shrink();
            return TextButton(
              onPressed: _loadMore,
              child: Text('${posts.length - shown} more'),
            );
          }
          final post = posts[index];
          final body = _bodies[post.id];
          final author = _names?.identityOf(post.authorId);
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RsScale.s4,
              vertical: RsScale.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (author != null) ...[
                      IdentityAvatar(identity: author, size: 28),
                      const SizedBox(width: RsScale.s2),
                    ],
                    Expanded(
                      child: Text(
                        '${_names?.nameOf(post.authorId) ?? ''} · '
                        '${gxsDate(post.published)}',
                        style: TextStyle(
                          fontSize: RsScale.tMeta,
                          color: rs.inkDim,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RsScale.s1),
                if (body == null)
                  Text(
                    'This post could not be read.',
                    style: TextStyle(color: rs.inkFaint),
                  )
                else
                  GxsBody(body),
              ],
            ),
          );
        },
      ),
    );
  }
}
