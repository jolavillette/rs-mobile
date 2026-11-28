import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/gxs_body.dart';
import 'package:retroshare/ui/gxs/gxs_group_bar.dart';
import 'package:retroshare/ui/gxs/gxs_group_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three views of the desktop's forum page.
enum ForumView {
  threaded('Threaded'),
  flat('Flat'),
  latestPost('Latest post');

  const ForumView(this.label);

  final String label;
}

/// A row of the forum page: a post, how deep it answers, and whether it has
/// answers to show under it.
class _Row {
  _Row(this.post, this.depth, {required this.hasAnswers});

  final GxsPostMeta post;
  final int depth;
  final bool hasAnswers;
}

/// A forum, as the desktop's list of its posts, newest first: threaded, each
/// answer under the post it answers, shown on demand; flat, every post; or
/// threaded with the threads of the latest answers first. The view chosen is
/// kept. A tap opens the post.
class ForumViewScreen extends StatefulWidget {
  const ForumViewScreen({required this.group, super.key});

  final GxsGroup group;

  @override
  State<ForumViewScreen> createState() => _ForumViewScreenState();
}

class _ForumViewScreenState extends State<ForumViewScreen> {
  static const _viewKey = 'forum_view';

  GxsContent? _content;
  GxsAuthorNames? _names;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _subscribed = false;
  bool _showDetails = false;
  String _description = '';
  ForumView _view = ForumView.threaded;

  List<GxsPostMeta> _posts = const [];
  List<GxsPostMeta> _tops = const [];
  Map<String, List<GxsPostMeta>> _answers = const {};

  /// Per post: the date of the latest post of its subtree, how many posts
  /// are under it, and how many of those are unread.
  final Map<String, int> _latest = {};
  final Map<String, int> _below = {};
  final Map<String, int> _unreadBelow = {};
  final Set<String> _expanded = {};
  List<_Row> _rows = const [];

  final Set<String> _namesWanted = {};
  bool _namesPlanned = false;

  @override
  void initState() {
    super.initState();
    _subscribed = widget.group.subscribed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_viewKey);
      _view = ForumView.values.firstWhere(
        (view) => view.name == saved,
        orElse: () => ForumView.threaded,
      );
    } catch (error) {
      debugPrint('Cannot read the forum view: $error');
    }
    await _load();
  }

  Future<void> _load() async {
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    final content = _content ??= GxsContent(GxsContentKind.forums, token);
    _names ??= GxsAuthorNames(token);
    try {
      final info = await content.groupInfo(widget.group.id);
      final posts = await content.forumPosts(widget.group.id);
      if (!mounted) return;
      setState(() {
        _subscribed = info?.group.subscribed ?? _subscribed;
        _description = info?.description ?? '';
        _index(posts);
        _error = null;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Forum ${widget.group.id}: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not read this forum.';
        _loading = false;
      });
    }
  }

  /// Who answers whom.
  void _index(List<GxsPostMeta> posts) {
    final ids = {for (final post in posts) post.id};
    final answers = <String, List<GxsPostMeta>>{};
    final tops = <GxsPostMeta>[];
    for (final post in posts) {
      if (ids.contains(post.parentId)) {
        answers.putIfAbsent(post.parentId, () => []).add(post);
      } else {
        tops.add(post);
      }
    }
    _posts = posts;
    _tops = tops;
    _answers = answers;
    _count();
    _arrange();
  }

  /// The latest date, the size and the unread posts of each subtree.
  void _count() {
    _latest.clear();
    _below.clear();
    _unreadBelow.clear();
    void walk(GxsPostMeta post) {
      if (_latest.containsKey(post.id)) return;
      _latest[post.id] = post.published;
      var latest = post.published;
      var below = 0;
      var unread = 0;
      for (final answer in _answers[post.id] ?? const <GxsPostMeta>[]) {
        walk(answer);
        if (_latest[answer.id]! > latest) latest = _latest[answer.id]!;
        below += 1 + _below[answer.id]!;
        unread += (answer.unread ? 1 : 0) + _unreadBelow[answer.id]!;
      }
      _latest[post.id] = latest;
      _below[post.id] = below;
      _unreadBelow[post.id] = unread;
    }

    for (final top in _tops) {
      walk(top);
    }
  }

  /// As the desktop sorts by date: the post's own date, or in the latest
  /// post view the date of the latest post under it.
  int _date(GxsPostMeta post) => _view == ForumView.latestPost
      ? _latest[post.id] ?? post.published
      : post.published;

  List<GxsPostMeta> _newestFirst(Iterable<GxsPostMeta> posts) =>
      posts.toList()..sort((a, b) => _date(b).compareTo(_date(a)));

  /// The rows shown, in the order of the view.
  void _arrange() {
    if (_view == ForumView.flat) {
      _rows = [
        for (final post in _newestFirst(_posts.where((post) => !post.missing)))
          _Row(post, 0, hasAnswers: false),
      ];
      return;
    }
    final rows = <_Row>[];
    final seen = <String>{};
    void add(GxsPostMeta post, int depth) {
      if (!seen.add(post.id)) return;
      final answers = _answers[post.id] ?? const <GxsPostMeta>[];
      rows.add(_Row(post, depth, hasAnswers: answers.isNotEmpty));
      if (!_expanded.contains(post.id)) return;
      for (final answer in _newestFirst(answers)) {
        add(answer, depth + 1);
      }
    }

    for (final top in _newestFirst(_tops)) {
      add(top, 0);
    }
    _rows = rows;
  }

  Future<void> _setView(ForumView view) async {
    if (view == _view) return;
    setState(() {
      _view = view;
      _arrange();
    });
    try {
      await (await SharedPreferences.getInstance())
          .setString(_viewKey, view.name);
    } catch (error) {
      debugPrint('Cannot keep the forum view: $error');
    }
  }

  void _toggle(GxsPostMeta post) => setState(() {
        if (!_expanded.remove(post.id)) _expanded.add(post.id);
        _arrange();
      });

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

  /// Opens a post; the page can go on to the rows before and after it.
  Future<void> _open(int index) async {
    final content = _content;
    final names = _names;
    if (content == null || names == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ForumPostScreen(
          groupId: widget.group.id,
          posts: [for (final row in _rows) row.post],
          index: index,
          content: content,
          names: names,
        ),
      ),
    );
    // Posts read meanwhile.
    if (mounted) setState(_count);
  }

  /// The author's name, asked from the core once the row is drawn.
  String _author(GxsPostMeta post) {
    final names = _names;
    if (post.missing || names == null) return '';
    _namesWanted.add(post.authorId);
    if (!_namesPlanned) {
      _namesPlanned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNames());
    }
    return names.nameOf(post.authorId);
  }

  Future<void> _loadNames() async {
    final names = _names;
    final wanted = _namesWanted.toList();
    _namesWanted.clear();
    final learnt = names != null && await names.load(wanted);
    _namesPlanned = false;
    if (learnt && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final header = <Widget>[
      if (_showDetails) ...[
        GxsGroupBar(
          kind: GxsContentKind.forums,
          subscribed: _subscribed,
          description: _description,
          busy: _busy,
          onSubscribe: _subscribe,
        ),
        const Divider(height: 1),
      ] else if (!_subscribed)
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
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(RsScale.s4),
          child: Text(_error!, style: TextStyle(color: rs.inkDim)),
        )
      else if (_rows.isEmpty && _subscribed)
        Padding(
          padding: const EdgeInsets.all(RsScale.s4),
          child: Text(
            'No post yet. They arrive a few at a time while the app is on '
            'screen: pull down to read again.',
            style: TextStyle(color: rs.inkDim),
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: _showDetails ? 'Hide the details' : 'Details',
            icon: Icon(_showDetails ? Icons.info : Icons.info_outline),
            onPressed: () => setState(() => _showDetails = !_showDetails),
          ),
          GxsGroupMenu(
            content: _content,
            groupId: widget.group.id,
            subscribed: _subscribed,
            posts: () => _posts.where((post) => !post.missing).toList(),
            onChanged: () {
              if (mounted) setState(_count);
            },
          ),
        ],
        // The desktop's three views, always in sight above the posts.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RsScale.s3,
              0,
              RsScale.s3,
              RsScale.s2,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ForumView>(
                showSelectedIcon: false,
                segments: [
                  for (final view in ForumView.values)
                    // Words only: three fit on the narrowest phone.
                    ButtonSegment(value: view, label: Text(view.label)),
                ],
                selected: {_view},
                onSelectionChanged: (views) => _setView(views.first),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: header.length + _rows.length,
                separatorBuilder: (context, index) => index < header.length
                    ? const SizedBox.shrink()
                    : Divider(height: 1, color: rs.lineSoft),
                itemBuilder: (context, index) => index < header.length
                    ? header[index]
                    : _row(index - header.length),
              ),
            ),
    );
  }

  Widget _row(int index) {
    final rs = context.rs;
    final row = _rows[index];
    final post = row.post;
    final open = _expanded.contains(post.id);
    final below = _below[post.id] ?? 0;
    final unreadBelow = _unreadBelow[post.id] ?? 0;
    final details = [
      _author(post),
      gxsDate(post.published),
      if (row.hasAnswers) below == 1 ? '1 answer' : '$below answers',
    ].where((text) => text.isNotEmpty).join(' · ');
    final tree = _view != ForumView.flat;
    return InkWell(
      onTap: post.missing ? null : () => _open(index),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tree ? row.depth.clamp(0, 5) * RsScale.s4 : RsScale.s4,
          RsScale.s2,
          RsScale.s4,
          RsScale.s2,
        ),
        child: Row(
          children: [
            if (tree)
              SizedBox(
                width: 40,
                child: row.hasAnswers
                    ? IconButton(
                        tooltip: open ? 'Hide the answers' : 'Show the answers',
                        icon: Icon(
                          open ? Icons.expand_more : Icons.chevron_right,
                          color: rs.inkDim,
                        ),
                        onPressed: () => _toggle(post),
                      )
                    : null,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title.isEmpty ? '(no title)' : post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RsScale.tRow,
                      fontWeight:
                          post.unread ? FontWeight.w700 : FontWeight.w400,
                      color: post.missing ? rs.inkFaint : rs.ink,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
                    ),
                ],
              ),
            ),
            if (tree && !open && unreadBelow > 0)
              CircleAvatar(
                radius: 11,
                backgroundColor: rs.brand,
                child: Text(
                  unreadBelow > 99 ? '99+' : '$unreadBelow',
                  style: TextStyle(fontSize: RsScale.tMicro, color: rs.onBrand),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A forum post, as the desktop shows the selected one: its title, author,
/// date and text, the choice of its versions when it was edited, and the
/// way to the post before or after it in the forum's list. A post shown is
/// marked read.
class ForumPostScreen extends StatefulWidget {
  const ForumPostScreen({
    required this.groupId,
    required this.posts,
    required this.index,
    required this.content,
    required this.names,
    super.key,
  });

  final String groupId;

  /// The rows of the forum page, in their order.
  final List<GxsPostMeta> posts;
  final int index;
  final GxsContent content;
  final GxsAuthorNames names;

  @override
  State<ForumPostScreen> createState() => _ForumPostScreenState();
}

class _ForumPostScreenState extends State<ForumPostScreen> {
  late int _index;
  final Map<String, String> _bodies = {};
  final Set<String> _failed = {};

  /// For a post shown in an older version, the id of that version.
  final Map<String, String> _shownVersion = {};

  GxsPostMeta get _post => widget.posts[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final post = _post;
    if (post.missing) return;
    try {
      if (!_bodies.containsKey(post.id)) {
        final loaded = await widget.content.posts(widget.groupId, [post.id]);
        if (loaded.isNotEmpty) _bodies[post.id] = loaded.first.body;
        if (loaded.isEmpty) _failed.add(post.id);
      }
      await widget.names.load([post.authorId]);
      await widget.content.markRead(widget.groupId, post);
    } catch (error) {
      debugPrint('Forum post ${post.id}: $error');
      _failed.add(post.id);
    }
    if (mounted) setState(() {});
  }

  void _go(int index) {
    setState(() => _index = index);
    _show();
  }

  /// Shows another version of an edited post, as the desktop's version
  /// list does.
  Future<void> _showVersion(GxsPostMeta post, String versionId) async {
    try {
      final loaded = await widget.content.posts(widget.groupId, [versionId]);
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

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final post = _post;
    final body = _bodies[post.id];
    final previous = _previous();
    final next = _next();
    return Scaffold(
      appBar: AppBar(
        title: Text(post.title.isEmpty ? '(no title)' : post.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RsScale.s4),
        children: [
          Text(
            post.title.isEmpty ? '(no title)' : post.title,
            style: TextStyle(
              fontSize: RsScale.tH3,
              fontWeight: FontWeight.w600,
              color: rs.ink,
            ),
          ),
          Text(
            [
              widget.names.nameOf(post.authorId),
              gxsDateTime(post.published),
            ].where((text) => text.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
          ),
          const SizedBox(height: RsScale.s3),
          if (post.missing)
            Text(
              'This post has not reached this phone.',
              style: TextStyle(color: rs.inkFaint),
            )
          else if (body != null)
            GxsBody(body)
          else if (_failed.contains(post.id))
            Text(
              'This post could not be read.',
              style: TextStyle(color: rs.inkFaint),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (post.versions.length > 1) _versions(post),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: previous == null ? null : () => _go(previous),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
            TextButton.icon(
              onPressed: next == null ? null : () => _go(next),
              icon: const Icon(Icons.chevron_right),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }

  int? _previous() {
    for (var i = _index - 1; i >= 0; i--) {
      if (!widget.posts[i].missing) return i;
    }
    return null;
  }

  int? _next() {
    for (var i = _index + 1; i < widget.posts.length; i++) {
      if (!widget.posts[i].missing) return i;
    }
    return null;
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
                gxsDateTime(version.published) +
                    (index == 0 ? ' (latest)' : ''),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(top: RsScale.s3),
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
}
