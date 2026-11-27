import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Side of an avatar in pixels, as the desktop makes them.
const avatarSide = 96;

/// The most a node avatar may weigh: the size of a chat avatar item.
const _maxAvatarBytes = 32767;

/// The picture in [path] as an avatar: upright, cropped to a square of
/// [avatarSide] pixels, a PNG when it has transparency and a JPEG otherwise,
/// as the desktop does. Null when the picture cannot be read.
Future<Uint8List?> avatarFromFile(String path) => compute(_avatarOf, path);

Uint8List? _avatarOf(String path) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(File(path).readAsBytesSync());
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: avatarSide,
    interpolation: img.Interpolation.average,
  );
  if (_hasTransparency(square)) {
    final png = img.encodePng(square);
    if (png.length <= _maxAvatarBytes) return png;
  }
  return img.encodeJpg(_onWhite(square), quality: 85);
}

bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

/// JPEG has no transparency: the picture is laid on white.
img.Image _onWhite(img.Image image) {
  if (!image.hasAlpha) return image;
  final white = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  return img.compositeImage(white, image);
}
