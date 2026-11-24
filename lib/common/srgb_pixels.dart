import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// [image] with its colours in sRGB and no colour profile left, changed in
/// place. Phones store their photos with a wide-gamut profile (Display P3);
/// a viewer that ignores profiles shows such a photo dull, and an image
/// without one is read as sRGB by every viewer. The pixels go through the
/// profile when it is a matrix/TRC RGB profile, the kind cameras write; a
/// profile of another kind is dropped as it is. An image without a profile
/// is taken as sRGB already.
img.Image srgbPixels(img.Image image) {
  final icc = image.iccProfile;
  image.iccProfile = null;
  if (icc == null ||
      image.hasPalette ||
      image.formatType != img.FormatType.uint) {
    return image;
  }
  final profile = _RgbProfile.parse(icc.decompressed());
  if (profile == null || profile.isSrgb) return image;

  final max = image.maxChannelValue.toInt();
  List<double> linear(_Curve curve) =>
      List.generate(max + 1, (v) => curve.apply(v / max), growable: false);
  final red = linear(profile.red);
  final green = linear(profile.green);
  final blue = linear(profile.blue);
  const steps = 4095;
  final encode = List.generate(
    steps + 1,
    (i) => (_srgbEncode(i / steps) * max).round(),
    growable: false,
  );
  int out(double v) => encode[(v.clamp(0.0, 1.0) * steps).round()];

  final m = profile.toSrgb;
  for (final pixel in image) {
    final r = red[pixel.r.toInt()];
    final g = green[pixel.g.toInt()];
    final b = blue[pixel.b.toInt()];
    pixel
      ..r = out(m[0] * r + m[1] * g + m[2] * b)
      ..g = out(m[3] * r + m[4] * g + m[5] * b)
      ..b = out(m[6] * r + m[7] * g + m[8] * b);
  }
  return image;
}

double _srgbDecode(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _srgbEncode(double v) => v <= 0.0031308
    ? v * 12.92
    : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;

/// The sRGB primaries in the ICC connection space (D50), as the standard
/// sRGB profile gives them; columns red, green, blue.
const _srgbColorants = <double>[
  0.4360747, 0.3850649, 0.1430804, //
  0.2225045, 0.7168786, 0.0606169, //
  0.0139322, 0.0971045, 0.7141733, //
];

/// A tone curve of an ICC profile: from an encoded value to a linear one.
class _Curve {
  _Curve.gamma(double gamma) : _apply = ((x) => math.pow(x, gamma).toDouble());
  _Curve.table(List<double> table) : _apply = ((x) => _lookUp(table, x));
  _Curve.parametric(int type, List<double> p) : _apply = _parametric(type, p);

  final double Function(double) _apply;

  double apply(double x) => _apply(x.clamp(0.0, 1.0)).clamp(0.0, 1.0);

  static double _lookUp(List<double> table, double x) {
    final at = x * (table.length - 1);
    final i = at.floor().clamp(0, table.length - 2);
    final t = at - i;
    return table[i] * (1 - t) + table[i + 1] * t;
  }

  // ICC.1 parametricCurveType, functions 0 to 4.
  static double Function(double) _parametric(int type, List<double> p) {
    final g = p[0];
    double pw(double v) => v <= 0 ? 0 : math.pow(v, g).toDouble();
    switch (type) {
      case 0:
        return pw;
      case 1:
        return (x) => x >= -p[2] / p[1] ? pw(p[1] * x + p[2]) : 0;
      case 2:
        return (x) => x >= -p[2] / p[1] ? pw(p[1] * x + p[2]) + p[3] : p[3];
      case 3:
        return (x) => x >= p[4] ? pw(p[1] * x + p[2]) : p[3] * x;
      default:
        return (x) => x >= p[4] ? pw(p[1] * x + p[2]) + p[5] : p[3] * x + p[6];
    }
  }
}

/// What srgbPixels() needs of a matrix/TRC RGB profile.
class _RgbProfile {
  _RgbProfile(this.colorants, this.red, this.green, this.blue);

  /// The red, green and blue primaries in the connection space (D50), as
  /// the columns of a 3 × 3 matrix in row order.
  final List<double> colorants;
  final _Curve red;
  final _Curve green;
  final _Curve blue;

  /// Linear values of this profile to linear sRGB, a 3 × 3 matrix in row
  /// order.
  List<double> get toSrgb => _multiply(_invert(_srgbColorants), colorants);

  /// Whether this profile is sRGB, give or take rounding: no need to touch
  /// the pixels then.
  bool get isSrgb {
    for (var i = 0; i < 9; i++) {
      if ((colorants[i] - _srgbColorants[i]).abs() > 0.003) return false;
    }
    for (final curve in [red, green, blue]) {
      for (final x in [0.02, 0.2, 0.5, 0.8]) {
        if ((curve.apply(x) - _srgbDecode(x)).abs() > 0.002) return false;
      }
    }
    return true;
  }

  static _RgbProfile? parse(Uint8List d) {
    final data = ByteData.sublistView(d);
    String sig(int at) => String.fromCharCodes(d.sublist(at, at + 4));
    if (d.length < 132 || sig(16) != 'RGB ' || sig(20) != 'XYZ ') return null;
    final tags = <String, (int, int)>{};
    final count = data.getUint32(128);
    for (var k = 0; k < count && 132 + 12 * k + 12 <= d.length; k++) {
      final at = 132 + 12 * k;
      final offset = data.getUint32(at + 4);
      final size = data.getUint32(at + 8);
      if (offset + size <= d.length) tags[sig(at)] = (offset, size);
    }
    double fixed(int at) => data.getInt32(at) / 65536;

    List<double>? xyz(String name) {
      final tag = tags[name];
      if (tag == null || tag.$2 < 20 || sig(tag.$1) != 'XYZ ') return null;
      return [fixed(tag.$1 + 8), fixed(tag.$1 + 12), fixed(tag.$1 + 16)];
    }

    _Curve? curve(String name) {
      final tag = tags[name];
      if (tag == null || tag.$2 < 12) return null;
      final at = tag.$1;
      if (sig(at) == 'curv') {
        final n = data.getUint32(at + 8);
        if (tag.$2 < 12 + 2 * n) return null;
        if (n == 0) return _Curve.gamma(1);
        if (n == 1) return _Curve.gamma(data.getUint16(at + 12) / 256);
        return _Curve.table([
          for (var i = 0; i < n; i++) data.getUint16(at + 12 + 2 * i) / 65535,
        ]);
      }
      if (sig(at) == 'para') {
        final type = data.getUint16(at + 8);
        const params = [1, 3, 4, 5, 7];
        if (type > 4 || tag.$2 < 12 + 4 * params[type]) return null;
        return _Curve.parametric(type, [
          for (var i = 0; i < params[type]; i++) fixed(at + 12 + 4 * i),
        ]);
      }
      return null;
    }

    final r = xyz('rXYZ');
    final g = xyz('gXYZ');
    final b = xyz('bXYZ');
    final rc = curve('rTRC');
    final gc = curve('gTRC');
    final bc = curve('bTRC');
    if (r == null || g == null || b == null) return null;
    if (rc == null || gc == null || bc == null) return null;
    return _RgbProfile(
      [r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]],
      rc,
      gc,
      bc,
    );
  }
}

List<double> _multiply(List<double> a, List<double> b) => [
      for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++)
          a[3 * i] * b[j] + a[3 * i + 1] * b[3 + j] + a[3 * i + 2] * b[6 + j],
    ];

List<double> _invert(List<double> m) {
  final det = m[0] * (m[4] * m[8] - m[5] * m[7]) -
      m[1] * (m[3] * m[8] - m[5] * m[6]) +
      m[2] * (m[3] * m[7] - m[4] * m[6]);
  return [
    (m[4] * m[8] - m[5] * m[7]) / det,
    (m[2] * m[7] - m[1] * m[8]) / det,
    (m[1] * m[5] - m[2] * m[4]) / det,
    (m[5] * m[6] - m[3] * m[8]) / det,
    (m[0] * m[8] - m[2] * m[6]) / det,
    (m[2] * m[3] - m[0] * m[5]) / det,
    (m[3] * m[7] - m[4] * m[6]) / det,
    (m[1] * m[6] - m[0] * m[7]) / det,
    (m[0] * m[4] - m[1] * m[3]) / det,
  ];
}
