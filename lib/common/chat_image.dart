import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:retroshare/common/srgb_pixels.dart';
import 'package:retroshare/common/upright_image.dart';

/// The most pixels the desktop puts in a chat image (640 × 480, in
/// ChatWidget::addExtraPicture()). It shows a received image at its own
/// size: a larger one overflowed its chat window.
const chatImageMaxPixels = 640 * 480;

/// The longest message a chat room carries: friends drop a longer one
/// (MAX_MESSAGE_SECURITY_SIZE in libretroshare's chat/p3chatservice.cc).
const roomMessageMaxLength = 31000;

/// The most bytes an image may take in a chat room message, worked out as
/// the desktop does (ChatWidget, then ImageUtil::optimizeSizeHtml()): 200
/// characters left for the HTML around it, then base64's 4/3 and 50 more.
const roomImageMaxBytes = (roomMessageMaxLength - 200) * 3 ~/ 4 - 50;

/// What [prepareChatImage] works on, in one object for compute().
class ChatImageRequest {
  const ChatImageRequest(this.bytes, {this.maxBytes = 0});

  /// The image file as picked.
  final Uint8List bytes;

  /// The most bytes the encoded image may take; 0 for no limit.
  final int maxBytes;
}

/// An image ready to be put in a chat message.
class ChatImage {
  const ChatImage(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

/// [request]'s image made ready for a chat message as the desktop makes its
/// own (RsHtml::makeEmbeddedImage()): turned upright, at most
/// [chatImageMaxPixels] pixels with its proportions kept, encoded as PNG when
/// it has transparent pixels and as JPEG (quality 85) otherwise, and, when
/// there is a byte limit, made narrower until it fits. The desktop also cuts
/// the colours down to 256 before narrowing; here only the size changes, so
/// a photo keeps its colours. Its colours are turned into sRGB and it goes
/// without colour profile nor EXIF data, which every viewer reads alike.
///
/// Returns null when the bytes are no image this can read, or when even a
/// tiny version does not fit the limit. Decoding a photo takes a while: run
/// it off the UI thread (compute()).
ChatImage? prepareChatImage(ChatImageRequest request) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(request.bytes);
  } catch (_) {
    // Some decoders throw on bytes that are no image of theirs.
  }
  if (decoded == null) return null;
  final upright = uprightPixels(decoded);
  final png = _hasTransparentPixels(upright);
  final mimeType = png ? 'image/png' : 'image/jpeg';
  Uint8List encode(img.Image i) =>
      png ? img.encodePng(i) : img.encodeJpg(i, quality: 85);
  bool fits(Uint8List bytes) =>
      request.maxBytes <= 0 || bytes.length <= request.maxBytes;
  img.Image narrow(img.Image from, int width) => width >= from.width
      ? from
      : img.copyResize(
          from,
          width: width,
          interpolation: img.Interpolation.average,
        );

  // At most chatImageMaxPixels, in sRGB: what follows works on this.
  final ratio = upright.width / upright.height;
  final maxWidth = math.max(
    1,
    math.min(upright.width, math.sqrt(chatImageMaxPixels * ratio).floor()),
  );
  final image = srgbPixels(
    upright.width * upright.height <= chatImageMaxPixels
        ? upright
        : narrow(upright, maxWidth),
  );
  final largest = encode(image);
  if (fits(largest)) return ChatImage(largest, mimeType);

  // The widest version that fits, between one of about 100 pixels (the
  // desktop's smallest) and the largest above.
  var low = math.max(1, math.sqrt(100 * ratio).floor());
  var best = encode(narrow(image, low));
  if (!fits(best)) return null;
  var high = image.width;
  while (high - low > 1) {
    final middle = (low + high) ~/ 2;
    final candidate = encode(narrow(image, middle));
    if (fits(candidate)) {
      low = middle;
      best = candidate;
    } else {
      high = middle;
    }
  }
  return ChatImage(best, mimeType);
}

bool _hasTransparentPixels(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}
