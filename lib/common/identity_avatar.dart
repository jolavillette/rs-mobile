import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:retroshare/common/identicon.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Identity;

/// The avatar of an identity, or its identicon when it has none.
class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({required this.identity, this.size = 40, super.key});

  /// The decoded avatars, by their base64 text: a list of messages draws the
  /// same few avatars at every build, and bytes decoded anew each time are a
  /// new picture for Flutter's image cache.
  static final _decoded = LinkedHashMap<String, Uint8List?>();
  static const _decodedMax = 200;

  static Uint8List? _bytes(String avatar) {
    if (_decoded.containsKey(avatar)) return _decoded[avatar];
    Uint8List? bytes;
    try {
      bytes = base64.decode(avatar);
    } catch (_) {
      bytes = null;
    }
    if (_decoded.length >= _decodedMax) _decoded.remove(_decoded.keys.first);
    return _decoded[avatar] = bytes;
  }

  final Identity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = identity.avatar;
    final avatar = text == null || text.isEmpty ? null : _bytes(text);
    final shape = BoxDecoration(
      borderRadius: BorderRadius.circular(RsScale.rMd),
      border: Border.all(color: context.rs.line),
      image: avatar != null
          ? DecorationImage(fit: BoxFit.cover, image: MemoryImage(avatar))
          : null,
    );
    return Container(
      width: size,
      height: size,
      decoration: shape,
      child: avatar == null
          ? Identicon(id: identity.mId, size: size, borderRadius: RsScale.rMd)
          : null,
    );
  }
}
