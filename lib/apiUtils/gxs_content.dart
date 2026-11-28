import 'dart:convert';
import 'dart:typed_data';

import 'package:retroshare/apiUtils/service_ids.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// Forums and channels as the app reads them: the lists, the posts and their
/// read state. Reading only; the phone gets them from the friends that serve
/// it and from nobody else.

/// The two services, and what differs between them in the core's interface.
enum GxsContentKind {
  forums('Forums', 'forum', '/rsGxsForums', RsServiceTypes.forums),
  channels('Channels', 'channel', '/rsGxsChannels', RsServiceTypes.channels);

  const GxsContentKind(this.title, this.noun, this.api, this.serviceType);

  final String title;
  final String noun;

  /// The interface's path prefix.
  final String api;

  /// 16-bit service type.
  final int serviceType;
}

/// What a phone asks for and keeps of a group it follows: less than a
/// desktop (30 days asked for, a year kept). The core rounds to its own
/// steps, of which 15 and 90 days are two.
const int phoneSyncSeconds = 15 * 86400;
const int phoneStorageSeconds = 90 * 86400;

const int _subscribeAdmin = 0x01;
const int _subscribeSubscribed = 0x04;
const int _statusUnread = 0x02;

/// A 64-bit number comes as a number or as {xint64, xstr64}.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is Map) {
    final text = value['xstr64'];
    if (text is String) return int.tryParse(text) ?? 0;
    return _int(value['xint64']);
  }
  return 0;
}

String _str(Object? value) => value is String ? value : '';

/// An id made of zeros stands for "none".
bool _isNullId(String id) => id.isEmpty || RegExp(r'^0+$').hasMatch(id);

bool _succeeded(Map<String, dynamic> response) {
  final retval = response['retval'];
  return retval == true || retval == 1;
}

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : const <Map<String, dynamic>>[];

/// A forum or a channel, as the lists show it.
class GxsGroup {
  GxsGroup.fromMeta(Map<String, dynamic> meta)
      : id = _str(meta['mGroupId']),
        name = _str(meta['mGroupName']),
        subscribeFlags = _int(meta['mSubscribeFlags']),
        lastPost = _int(meta['mLastPost']),
        visiblePosts = _int(meta['mVisibleMsgCount']),
        popularity = _int(meta['mPop']);

  final String id;
  final String name;
  final int subscribeFlags;

  /// Seconds since the epoch, 0 when unknown.
  final int lastPost;
  final int visiblePosts;

  /// How many of this node's friends follow it.
  final int popularity;

  bool get subscribed =>
      subscribeFlags & (_subscribeSubscribed | _subscribeAdmin) != 0;
}

/// A group with its description and, for a channel, its picture.
class GxsGroupInfo {
  GxsGroupInfo(this.group, this.description, this.image);

  final GxsGroup group;
  final String description;
  final Uint8List? image;
}

/// What the core says of a post without its content.
class GxsPostMeta {
  GxsPostMeta.fromJson(Map<String, dynamic> meta)
      : id = _str(meta['mMsgId']),
        origId = _str(meta['mOrigMsgId']),
        threadId = _str(meta['mThreadId']),
        parentId = _str(meta['mParentId']),
        authorId = _str(meta['mAuthorId']),
        title = _str(meta['mMsgName']),
        published = _int(meta['mPublishTs']),
        status = _int(meta['mMsgStatus']);

  final String id;
  final String origId;
  final String threadId;
  final String parentId;
  final String authorId;
  final String title;

  /// Seconds since the epoch.
  final int published;
  int status;

  bool get unread => status & _statusUnread != 0;

  /// Starts a thread (forum) or is a post, not a comment or a vote (channel).
  bool get isRoot => _isNullId(parentId);

  /// The post this one is a new version of; itself for a first version.
  String get versionOf => _isNullId(origId) ? id : origId;
}

/// A file a channel post offers.
class GxsFile {
  GxsFile(this.name, this.hash, this.size);

  final String name;
  final String hash;
  final int size;
}

/// A post with its content.
class GxsPost {
  GxsPost(this.meta, this.body, this.files, this.thumbnail);

  final GxsPostMeta meta;

  /// Rich text (HTML).
  final String body;
  final List<GxsFile> files;
  final Uint8List? thumbnail;
}

Uint8List? _image(Object? image) {
  if (image is! Map) return null;
  final data = image['mData'];
  final base64Text = data is Map ? data['base64'] : null;
  if (base64Text is! String || base64Text.isEmpty) return null;
  try {
    return base64.decode(base64Text);
  } on FormatException {
    return null;
  }
}

/// Of the versions of each post, the latest one only.
List<GxsPostMeta> _latestVersions(Iterable<GxsPostMeta> metas) {
  final latest = <String, GxsPostMeta>{};
  for (final meta in metas) {
    final known = latest[meta.versionOf];
    if (known == null || meta.published > known.published) {
      latest[meta.versionOf] = meta;
    }
  }
  return latest.values.toList();
}

class GxsContent {
  GxsContent(this.kind, this.authToken);

  final GxsContentKind kind;
  final AuthToken authToken;

  bool get _forums => kind == GxsContentKind.forums;

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? params,
  ]) =>
      rsApiCall('${kind.api}/$method', authToken: authToken, params: params);

  /// Whether the service exchanges with friends. Off, the core runs it but
  /// neither asks for nor receives anything.
  Future<bool> serviceOn() async {
    final permissions = await RsServiceControl.getServicePermissions(
      rsFullServiceId(kind.serviceType),
      authToken,
    );
    final allowed = permissions['mPeersAllowed'];
    return permissions['mDefaultAllowed'] == true ||
        (allowed is List && allowed.isNotEmpty);
  }

  Future<bool> setServiceOn(bool on) => RsServiceControl.setServiceEnabled(
        rsFullServiceId(kind.serviceType),
        on,
        authToken,
      );

  /// Every group this node knows of: those it follows, and those the friends
  /// that serve it follow.
  Future<List<GxsGroup>> groups() async {
    final response =
        await _call(_forums ? 'getForumsSummaries' : 'getChannelsSummaries');
    if (!_succeeded(response)) {
      throw Exception('Could not read the list of ${kind.noun}s');
    }
    return _maps(response[_forums ? 'forums' : 'channels'])
        .map(GxsGroup.fromMeta)
        .where((group) => group.id.isNotEmpty)
        .toList();
  }

  Future<GxsGroupInfo?> groupInfo(String groupId) async {
    final response = _forums
        ? await _call('getForumsInfo', {
            'forumIds': [groupId],
          })
        : await _call('getChannelsInfo', {
            'chanIds': [groupId],
          });
    final infos = _maps(response[_forums ? 'forumsInfo' : 'channelsInfo']);
    if (infos.isEmpty) return null;
    final meta = infos.first['mMeta'];
    if (meta is! Map<String, dynamic>) return null;
    return GxsGroupInfo(
      GxsGroup.fromMeta(meta),
      _str(infos.first['mDescription']),
      _image(infos.first['mImage']),
    );
  }

  /// Follows or leaves a group. A group just followed gets the phone's
  /// shorter periods.
  Future<void> subscribe(String groupId, bool subscribe) async {
    final response = _forums
        ? await _call('subscribeToForum', {
            'forumId': groupId,
            'subscribe': subscribe,
          })
        : await _call('subscribeToChannel', {
            'channelId': groupId,
            'subscribe': subscribe,
          });
    if (!_succeeded(response)) {
      throw Exception('The core refused');
    }
    if (!subscribe) return;
    // The storage period first: the core keeps the sync period below it.
    await _call('setStoragePeriod', {
      'groupId': groupId,
      'storageSecs': phoneStorageSeconds,
    });
    await _call('setSyncPeriod', {
      'groupId': groupId,
      'syncAge': phoneSyncSeconds,
    });
  }

  /// The posts of a group without their content, one entry per post (its
  /// latest version). For a channel: the posts, not their comments or votes.
  Future<List<GxsPostMeta>> postMetas(String groupId) async {
    final response = _forums
        ? await _call('getForumMsgMetaData', {'forumId': groupId})
        : await _call('getContentSummaries', {'channelId': groupId});
    if (!_succeeded(response)) {
      throw Exception('Could not read the posts');
    }
    final metas = _maps(response[_forums ? 'msgMetas' : 'summaries'])
        .map(GxsPostMeta.fromJson)
        .where((meta) => meta.id.isNotEmpty);
    return _latestVersions(_forums ? metas : metas.where((m) => m.isRoot));
  }

  /// The content of some posts of a group. Ask for few at a time: a post may
  /// carry pictures.
  Future<List<GxsPost>> posts(String groupId, List<String> postIds) async {
    if (postIds.isEmpty) return const <GxsPost>[];
    final response = _forums
        ? await _call('getForumContent', {
            'forumId': groupId,
            'msgsIds': postIds,
          })
        : await _call('getChannelContent', {
            'channelId': groupId,
            'contentsIds': postIds,
          });
    if (!_succeeded(response)) {
      throw Exception('Could not read the posts');
    }
    final posts = <GxsPost>[];
    for (final post in _maps(response[_forums ? 'msgs' : 'posts'])) {
      final meta = post['mMeta'];
      if (meta is! Map<String, dynamic>) continue;
      posts.add(
        GxsPost(
          GxsPostMeta.fromJson(meta),
          _str(post['mMsg']),
          [
            for (final file in _maps(post['mFiles']))
              GxsFile(
                _str(file['mName']),
                _str(file['mHash']),
                _int(file['mSize']),
              ),
          ],
          _image(post['mThumbnail']),
        ),
      );
    }
    return posts;
  }

  Future<void> markRead(String groupId, GxsPostMeta post) =>
      setRead(groupId, post, read: true);

  /// Marks a post read or unread, in the core and in [post].
  Future<void> setRead(
    String groupId,
    GxsPostMeta post, {
    required bool read,
  }) async {
    if (post.unread != read) return;
    final pair = {'first': groupId, 'second': post.id};
    final response = _forums
        ? await _call('markRead', {'messageId': pair, 'read': read})
        : await _call('setMessageReadStatus', {'msgId': pair, 'read': read});
    if (!_succeeded(response)) return;
    if (read) {
      post.status &= ~_statusUnread;
    } else {
      post.status |= _statusUnread;
    }
  }

  /// Marks every one of [posts] read or unread. The core has no call for a
  /// whole group: one per post whose mark changes.
  Future<void> setAllRead(
    String groupId,
    List<GxsPostMeta> posts, {
    required bool read,
  }) async {
    for (final post in posts) {
      await setRead(groupId, post, read: read);
    }
  }

  Future<int> _days(String method, String groupId) async {
    final response = await _call(method, {'groupId': groupId});
    final seconds = response['retval'];
    return seconds is num ? seconds.toInt() ~/ 86400 : 0;
  }

  /// How far back the posts of a group are asked for, in days; 0 is no
  /// limit.
  Future<int> syncDays(String groupId) => _days('getSyncPeriod', groupId);

  /// How long the posts of a group are kept, in days; 0 is no limit.
  Future<int> storageDays(String groupId) => _days('getStoragePeriod', groupId);

  Future<void> setSyncDays(String groupId, int days) =>
      _call('setSyncPeriod', {'groupId': groupId, 'syncAge': days * 86400});

  Future<void> setStorageDays(String groupId, int days) => _call(
        'setStoragePeriod',
        {'groupId': groupId, 'storageSecs': days * 86400},
      );
}

/// The names of the identities that sign posts, asked from the core once.
class GxsAuthorNames {
  GxsAuthorNames(this.authToken);

  final AuthToken authToken;
  final Map<String, String> _names = {};
  final Map<String, String> _avatars = {};

  /// The name known so far, or a short form of the id.
  String nameOf(String authorId) {
    if (authorId.isEmpty || _isNullId(authorId)) return 'Anonymous';
    return _names[authorId] ?? authorId.substring(0, 8);
  }

  /// The author as an identity, to draw the avatar: the one read from the
  /// core, or the identicon of the id. Null for an anonymous post.
  Identity? identityOf(String authorId) {
    if (authorId.isEmpty || _isNullId(authorId)) return null;
    return Identity(
      mId: authorId,
      name: _names[authorId],
      avatar: _avatars[authorId],
      signed: false,
      isContact: false,
    );
  }

  /// Asks the core for the names not known yet. True when one was learnt.
  Future<bool> load(Iterable<String> authorIds) async {
    var learnt = false;
    for (final id in authorIds.toSet()) {
      if (id.isEmpty || _isNullId(id) || _names.containsKey(id)) continue;
      try {
        final response = await rsApiCall(
          '/rsIdentity/getIdDetails',
          authToken: authToken,
          params: {'id': id},
        );
        final details = response['details'];
        final name = details is Map ? details['mNickname'] : null;
        if (_succeeded(response) && name is String && name.isNotEmpty) {
          _names[id] = name;
          final avatar = details['mAvatar']?['mData']?['base64'];
          if (avatar is String && avatar.isNotEmpty) _avatars[id] = avatar;
          learnt = true;
        }
      } catch (_) {
        // The identity is not here yet: the short id stays.
      }
    }
    return learnt;
  }
}

/// "14:05" today, "27 Nov" this year, "27 Nov 2025" before.
String gxsDate(int secondsSinceEpoch) {
  if (secondsSinceEpoch <= 0) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000);
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${two(date.hour)}:${two(date.minute)}';
  }
  final day = '${date.day} ${months[date.month - 1]}';
  return date.year == now.year ? day : '$day ${date.year}';
}

/// "1.2 MB".
String gxsSize(int bytes) {
  const units = ['B', 'kB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1000 && unit < units.length - 1) {
    size /= 1000;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${size.toStringAsFixed(2)} ${units[unit]}';
}
