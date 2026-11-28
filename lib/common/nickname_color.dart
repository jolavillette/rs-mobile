import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The colour of [name] in a chat room, computed as the desktop computes its
/// coloured nicknames (ChatStyle::formatMessage(), then
/// RsHtml::findBestColor()): a hue taken from a hash of the name, then the
/// lightness that gives [desiredContrast] against [background]. A name keeps
/// the same hue on the desktop and on the phone.
Color nicknameColor(
  String name,
  Color background, {
  double desiredContrast = 4.5,
}) {
  final color =
      HSVColor.fromAHSV(1, nicknameHue(name), 1, 150 / 255).toColor();
  return _findBestColor(
    color,
    background.computeLuminance(),
    desiredContrast,
  );
}

/// The hue of [name], in degrees, from the desktop's hash of the name.
double nicknameHue(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    // QChar::toLatin1() gives 0 outside Latin-1, and a signed char inside.
    final latin1 = unit > 0xff ? 0 : (unit >= 0x80 ? unit - 0x100 : unit);
    hash = (((hash << 1) + (hash >> 14)) ^ latin1) & 0x3fff;
  }
  return (hash % 360).toDouble();
}

/// The fill and border of [name]'s message bubbles in a chat room, in the
/// hue of its nickname. The fill is as vivid as the green of my own
/// bubbles, made lighter only where black text would lack contrast (blues
/// and purples); the border is the dark shade of the same hue.
({Color fill, Color border}) nicknameBubbleColors(String name) {
  final hue = nicknameHue(name);
  var lightness = 0.62;
  var fill = HSLColor.fromAHSL(1, hue, 1, lightness).toColor();
  // Contrast 6 with black text.
  while (fill.computeLuminance() < 0.25 && lightness < 0.95) {
    lightness += 0.01;
    fill = HSLColor.fromAHSL(1, hue, 1, lightness).toColor();
  }
  final border = HSLColor.fromAHSL(1, hue, 1, 0.35).toColor();
  return (fill: fill, border: border);
}

double _contrast(double lum1, double lum2) =>
    (math.max(lum1, lum2) + 0.05) / (math.min(lum1, lum2) + 0.05);

/// The colour of the same hue whose contrast with [bglum] is
/// [desiredContrast]: darker than the background when that can reach the
/// contrast, lighter otherwise.
Color _findBestColor(Color color, double bglum, double desiredContrast) {
  final lum = color.computeLuminance();
  final lowContrast = _contrast(bglum, 0);
  final highContrast = _contrast(bglum, 1);
  final searchDown = (lum <= bglum && lowContrast >= desiredContrast) ||
      (lum > bglum &&
          highContrast < desiredContrast &&
          lowContrast >= highContrast);

  // A dark text on a light background is never too dark. A light text on a
  // dark background is held to the contrast, as more makes it glare.
  if (searchDown && _contrast(lum, bglum) >= desiredContrast) return color;

  final hsl = HSLColor.fromColor(color);
  var minl = searchDown ? 0.0 : bglum;
  var maxl = searchDown ? bglum : 1.0;
  do {
    final midl = (minl + maxl) / 2;
    final midLum = hsl.withLightness(midl).toColor().computeLuminance();
    if ((_contrast(midLum, bglum) < desiredContrast) != searchDown) {
      minl = midl;
    } else {
      maxl = midl;
    }
  } while (maxl - minl > 0.01);
  return hsl.withLightness(minl).toColor();
}
