import 'package:flutter/material.dart';

/// The design tokens of the RetroShare web UI (RSNewWebUI,
/// webui-src/app/scss/abstracts/_tokens.scss), so the app looks like the web
/// UI and the desktop. Keep the values in step with that file.
@immutable
class RsTokens extends ThemeExtension<RsTokens> {
  const RsTokens({
    required this.ground,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.lineSoft,
    required this.lineStrong,
    required this.press,
    required this.ink,
    required this.inkBody,
    required this.inkDim,
    required this.inkFaint,
    required this.brand,
    required this.brandDeep,
    required this.brandPale,
    required this.accent,
    required this.actionTop,
    required this.actionBottom,
    required this.onBrand,
    required this.select,
    required this.selectSoft,
    required this.selectFaint,
    required this.up,
    required this.upInk,
    required this.upBg,
    required this.down,
    required this.downInk,
    required this.downBg,
    required this.warn,
    required this.warnInk,
    required this.warnBg,
    required this.chromeTop,
    required this.chromeBottom,
  });

  /// App background, content panels, recessed fields.
  final Color ground, surface, sunken;

  /// Control borders, quiet row separators, dialog borders, pressed controls.
  final Color line, lineSoft, lineStrong, press;

  /// Headings, body text, secondary text, placeholders.
  final Color ink, inkBody, inkDim, inkFaint;

  /// Readable brand blue and its variants.
  final Color brand, brandDeep, brandPale, accent;

  /// Primary actions: a top to bottom gradient, with [onBrand] on it.
  final Color actionTop, actionBottom, onBrand;

  /// Selected rows, soft selection, quiet selected surfaces.
  final Color select, selectSoft, selectFaint;

  /// Status: mark, readable ink and background. Always add a label too.
  final Color up, upInk, upBg, down, downInk, downBg, warn, warnInk, warnBg;

  /// Bars and headers: a quiet top to bottom gradient, not a brand color.
  final Color chromeTop, chromeBottom;

  /// The fill of a primary action.
  LinearGradient get actionGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [actionTop, actionBottom],
      );

  /// The fill of bars and headers.
  LinearGradient get chromeGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [chromeTop, chromeBottom],
      );

  static const light = RsTokens(
    ground: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFF0F2F3),
    line: Color(0xFFC9CDD0),
    lineSoft: Color(0xFFE8E8E8),
    lineStrong: Color(0xFF9AA3A9),
    press: Color(0xFFE9ECEE),
    ink: Color(0xFF19232D),
    inkBody: Color(0xFF3D4A55),
    inkDim: Color(0xFF566B7A),
    inkFaint: Color(0xFF5A6E7B),
    brand: Color(0xFF0B7CB2),
    brandDeep: Color(0xFF0A6899),
    brandPale: Color(0xFFABE3FF),
    accent: Color(0xFF0099CC),
    actionTop: Color(0xFF0B7CB2),
    actionBottom: Color(0xFF0A6899),
    onBrand: Color(0xFFFFFFFF),
    select: Color(0xFFA9D7ED),
    selectSoft: Color(0xFFC9E5F4),
    selectFaint: Color(0xFFE4F1FA),
    up: Color(0xFF32CD32),
    upInk: Color(0xFF217A21),
    upBg: Color(0xFFEFF8EF),
    down: Color(0xFFCD3232),
    downInk: Color(0xFFC23636),
    downBg: Color(0xFFFBEFEF),
    warn: Color(0xFFDCDC41),
    warnInk: Color(0xFF8A6D1F),
    warnBg: Color(0xFFFDF8E3),
    chromeTop: Color(0xFFFFFFFF),
    chromeBottom: Color(0xFFF4F6F7),
  );

  static const dark = RsTokens(
    ground: Color(0xFF161B21),
    surface: Color(0xFF1E252D),
    sunken: Color(0xFF192027),
    line: Color(0xFF485563),
    lineSoft: Color(0xFF343F4B),
    lineStrong: Color(0xFF8092A3),
    press: Color(0xFF354351),
    ink: Color(0xFFEDF2F7),
    inkBody: Color(0xFFD1DCE5),
    inkDim: Color(0xFFA7B8C7),
    inkFaint: Color(0xFF95A7B7),
    brand: Color(0xFF6DC9F5),
    brandDeep: Color(0xFF9BDCFF),
    brandPale: Color(0xFF354F63),
    accent: Color(0xFF6DC9F5),
    actionTop: Color(0xFF12618C),
    actionBottom: Color(0xFF0B4F76),
    onBrand: Color(0xFFFFFFFF),
    select: Color(0xFF254D67),
    selectSoft: Color(0xFF234054),
    selectFaint: Color(0xFF203544),
    up: Color(0xFF32CD32),
    upInk: Color(0xFF8CD68C),
    upBg: Color(0xFF203A2A),
    down: Color(0xFFCD3232),
    downInk: Color(0xFFFFAAAA),
    downBg: Color(0xFF432B31),
    warn: Color(0xFFDCDC41),
    warnInk: Color(0xFFEAD38D),
    warnBg: Color(0xFF3B3523),
    chromeTop: Color(0xFF29333E),
    chromeBottom: Color(0xFF222B35),
  );

  @override
  RsTokens copyWith() => this;

  @override
  RsTokens lerp(RsTokens? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Spacing, corners, control sizes and type sizes of the web UI, in logical
/// pixels (the web UI's CSS pixels).
abstract final class RsScale {
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32;
  static const double rSm = 2, rMd = 4, rFull = 999;
  static const double control = 30, glyph = 26;
  static const double tTitle = 30, tH2 = 21, tH3 = 16, tBody = 15;
  static const double tRow = 14, tMeta = 13, tLabel = 12, tMicro = 11;
  static const String fontSans = 'Archivo', fontMono = 'DM Mono';
}

extension RsTokensOf on BuildContext {
  /// The web UI tokens of the current theme (light or dark).
  RsTokens get rs => Theme.of(this).extension<RsTokens>() ?? RsTokens.light;
}
