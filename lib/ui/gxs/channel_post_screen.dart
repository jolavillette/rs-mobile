import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/gxs/gxs_body.dart';
import 'package:retroshare/ui/gxs/gxs_file_tile.dart';

/// A channel post, in two tabs: its text, which may be long, and its files,
/// each with its download. Opening the post marks it read.
class ChannelPostScreen extends StatefulWidget {
  const ChannelPostScreen({
    required this.groupId,
    required this.post,
    super.key,
  });

  final String groupId;
  final GxsPost post;

  @override
  State<ChannelPostScreen> createState() => _ChannelPostScreenState();
}

class _ChannelPostScreenState extends State<ChannelPostScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    final token =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (token == null) return;
    try {
      await GxsContent(GxsContentKind.channels, token)
          .markRead(widget.groupId, widget.post.meta);
    } catch (error) {
      debugPrint('Channel post ${widget.post.meta.id}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final title = post.meta.title.isEmpty ? '(no title)' : post.meta.title;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Text'),
              Tab(text: 'Files (${post.files.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_text(context, title), _files(context)],
        ),
      ),
    );
  }

  Widget _text(BuildContext context, String title) {
    final rs = context.rs;
    final post = widget.post;
    final thumbnail = post.thumbnail;
    return ListView(
      padding: const EdgeInsets.all(RsScale.s4),
      children: [
        Text(
          title,
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
            padding: const EdgeInsets.only(top: RsScale.s3),
            child: Image.memory(
              thumbnail,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (post.body.trim().isNotEmpty)
          GxsBody(post.body)
        else
          Padding(
            padding: const EdgeInsets.only(top: RsScale.s3),
            child: Text(
              'This post has no text.',
              style: TextStyle(color: rs.inkDim),
            ),
          ),
      ],
    );
  }

  Widget _files(BuildContext context) {
    final files = widget.post.files;
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(RsScale.s4),
        child: Text(
          'This post has no file.',
          style: TextStyle(color: context.rs.inkDim),
        ),
      );
    }
    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          GxsFileTile(files[index], key: ValueKey(files[index].hash)),
    );
  }
}
