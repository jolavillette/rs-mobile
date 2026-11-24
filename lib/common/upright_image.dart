import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// [bytes] with its pixels turned upright, for a JPEG whose EXIF data says
/// the camera was held sideways or upside down. A phone stores a photo as
/// its sensor took it and tags how to turn it; the desktop, as many viewers,
/// ignores the tag and showed such a photo turned by 90°. The photo is then
/// encoded again, without EXIF data, as the desktop sends its images. Any
/// other image comes back unchanged.
///
/// Decoding a photo takes a while: run this off the UI thread (compute()).
Uint8List uprightImage(Uint8List bytes) {
  try {
    final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
    if (orientation == null || orientation == 1) return bytes;
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) return bytes;
    return img.encodeJpg(uprightPixels(decoded), quality: 90);
  } catch (_) {
    return bytes;
  }
}

/// [image] turned as its EXIF orientation says, without EXIF data.
img.Image uprightPixels(img.Image image) =>
    img.bakeOrientation(image)..exif = img.ExifData();
