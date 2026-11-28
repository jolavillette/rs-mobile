import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/gxs_body.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';
import 'package:retroshare/ui/gxs/gxs_group_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final metas = await content.forumPosts(widget.group.id);
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

/// The posts of a thread, in either view of the desktop: threaded, each
/// answer under the post it answers, or flat, oldest first. Their text is read
/// from the core a few posts at a time, and a post shown is marked as read.
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

  /// For a post shown in an older version, the id of that version.
  final Map<String, String> _shownVersion = {};

  // The view chosen last, as the desktop keeps it; threaded at first.
  static const _threadedKey = 'forum_threaded_view';
  bool _threaded = true;
  List<GxsPostMeta> _order = const [];
  Map<String, int> _depth = const {};

  /// The posts in the order of the view, with how deep each one answers.
  void _arrange() {
    final posts = widget.thread.posts;
    final ids = {for (final post in posts) post.id};
    final answers = <String, List<GxsPostMeta>>{};
    for (final post in posts) {
      if (ids.contains(post.parentId)) {
        answers.putIfAbsent(post.parentId, () => []).add(post);
      }
    }
    final depth = <String, int>{};
    final order = <GxsPostMeta>[];
    void walk(GxsPostMeta post, int level) {
      if (depth.containsKey(post.id)) return;
      depth[post.id] = level;
      order.add(post);
      for (final answer in answers[post.id] ?? const <GxsPostMeta>[]) {
        walk(answer, level + 1);
      }
    }

    // The posts list is oldest first, so are the answers to each post.
    for (final post in posts) {
      if (!ids.contains(post.parentId)) walk(post, 0);
    }
    _depth = depth;
    _order = _threaded ? order : posts;
  }

  /// Switches the view. The posts whose text is read already stay read.
  Future<void> _setThreaded(bool threaded) async {
    if (threaded == _threaded) return;
    setState(() {
      _threaded = threaded;
      _arrange();
      _asked = _order.takeWhile((post) => _bodies.containsKey(post.id)).length;
    });
    if (_asked == 0) await _loadMore();
    try {
      await (await SharedPreferences.getInstance())
          .setBool(_threadedKey, threaded);
    } catch (error) {
      debugPrint('Cannot keep the forum view: $error');
    }
  }

  Future<void> _start() async {
    try {
      final saved =
          (await SharedPreferences.getInstance()).getBool(_threadedKey);
      if (saved != null) _threaded = saved;
    } catch (error) {
      debugPrint('Cannot read the forum view: $error');
    }
    if (!mounted) return;
    setState(_arrange);
    await _loadMore();
  }

  /// How far an answer is moved right in the threaded view: a step per
  /// level, at most five, so that deep threads stay readable on a phone.
  double _indent(GxsPostMeta post) =>
      _threaded ? (_depth[post.id] ?? 0).clamp(0, 5) * RsScale.s4 : 0;

  @override
  void initState() {
    super.initState();
    _arrange();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _loadMore() async {
    final posts = _order;
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

  /// Shows another version of an edited post, as the desktop's version
  /// list does.
  Future<void> _showVersion(GxsPostMeta post, String versionId) async {
    final content = _content;
    if (content == null) return;
    try {
      final loaded = await content.posts(widget.group.id, [versionId]);
      if (loaded.isEmpty || !mounted) return;
      setState(() {
        _bodies[post.id] = loaded.first.body;
        _shownVersion[post.id] = versionId;
      });
    } catch (error) {
      debugPrint('Forum post $versionId: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read this version.')),
        );
      }
    }
  }

  /// Under an edited post: the version shown, and the choice of another.
  Widget _versions(GxsPostMeta post) {
    final rs = context.rs;
    final shownId = _shownVersion[post.id] ?? post.id;
    final shown = post.versions.firstWhere(
      (version) => version.id == shownId,
      orElse: () => post.versions.first,
    );
    final latest = shown.id == post.versions.first.id;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: 'Versions of this post',
        onSelected: (versionId) => _showVersion(post, versionId),
        itemBuilder: (context) => [
          for (final (index, version) in post.versions.indexed)
            CheckedPopupMenuItem(
              value: version.id,
              checked: version.id == shown.id,
              child: Text(
                '${gxsDateTime(version.published)}${index == 0 ? ' (latest)' : ''}',
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(top: RsScale.s2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 16, color: rs.inkDim),
              const SizedBox(width: RsScale.s1),
              Text(
                '${latest ? 'Edited' : 'Older version'}, '
                '${gxsDateTime(shown.published)} · '
                '${post.versions.length} versions',
                style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: rs.inkDim),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final posts = _order;
    final shown = _asked.clamp(0, posts.length);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.thread.root.title.isEmpty
              ? widget.group.name
              : widget.thread.root.title,
        ),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'View',
            icon: Icon(
              _threaded ? Icons.account_tree_outlined : Icons.view_agenda_outlined,
            ),
            onSelected: _setThreaded,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: true,
                checked: _threaded,
                child: const Text('Threaded view'),
              ),
              CheckedPopupMenuItem(
                value: false,
                checked: !_threaded,
                child: const Text('Flat view'),
              ),
            ],
          ),
        ],
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
            padding: EdgeInsets.fromLTRB(
              RsScale.s4 + _indent(post),
              RsScale.s3,
              RsScale.s4,
              RsScale.s3,
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
                if (post.versions.length > 1) _versions(post),
              ],
            ),
          );
        },
      ),
    );
  }
}
