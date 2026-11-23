import 'package:flutter/material.dart';
import 'package:retroshare/common/rs_tokens.dart';

/// The app themes, built from the web UI tokens (see rs_tokens.dart): quiet,
/// compact, RetroShare blue, fine borders and small corners.
final lightTheme = _rsTheme(RsTokens.light, Brightness.light);
final darkTheme = _rsTheme(RsTokens.dark, Brightness.dark);

ThemeData _rsTheme(RsTokens t, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.brand,
    onPrimary: t.onBrand,
    primaryContainer: t.selectSoft,
    onPrimaryContainer: t.ink,
    secondary: t.accent,
    onSecondary: t.onBrand,
    secondaryContainer: t.select,
    onSecondaryContainer: t.ink,
    error: t.down,
    onError: t.onBrand,
    errorContainer: t.downBg,
    onErrorContainer: t.downInk,
    surface: t.surface,
    onSurface: t.ink,
    onSurfaceVariant: t.inkDim,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.ground,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.sunken,
    surfaceContainerHighest: t.sunken,
    outline: t.line,
    outlineVariant: t.lineSoft,
    inverseSurface: t.ink,
    onInverseSurface: t.surface,
    inversePrimary: t.brandPale,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  TextStyle text(double size, FontWeight weight, Color color) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color);
  const body = FontWeight.w400, label = FontWeight.w500, state = FontWeight.w600;

  final textTheme = TextTheme(
    displaySmall: text(RsScale.tTitle, state, t.ink),
    headlineLarge: text(RsScale.tTitle, state, t.ink),
    headlineMedium: text(RsScale.tH2, state, t.ink),
    headlineSmall: text(RsScale.tH2, state, t.ink),
    titleLarge: text(RsScale.tH2, state, t.ink),
    titleMedium: text(RsScale.tH3, state, t.ink),
    titleSmall: text(RsScale.tRow, state, t.ink),
    bodyLarge: text(RsScale.tBody, body, t.inkBody),
    bodyMedium: text(RsScale.tRow, body, t.inkBody),
    bodySmall: text(RsScale.tMeta, body, t.inkDim),
    labelLarge: text(RsScale.tRow, label, t.ink),
    labelMedium: text(RsScale.tLabel, label, t.inkDim),
    labelSmall: text(RsScale.tMicro, label, t.inkDim),
  );

  const smallCorners = BorderRadius.all(Radius.circular(RsScale.rSm));
  const sheetCorners = BorderRadius.all(Radius.circular(RsScale.rMd));
  const controlSize = Size(RsScale.control, RsScale.control);
  final primaryAction = ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(t.actionTop),
    foregroundColor: WidgetStatePropertyAll(t.onBrand),
    overlayColor: WidgetStatePropertyAll(t.actionBottom),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(controlSize),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: RsScale.s3),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: smallCorners),
    ),
    textStyle: WidgetStatePropertyAll(text(RsScale.tRow, label, t.onBrand)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [t],
    fontFamily: RsScale.fontSans,
    textTheme: textTheme,
    scaffoldBackgroundColor: t.ground,
    canvasColor: t.surface,
    dividerColor: t.lineSoft,
    iconTheme: IconThemeData(color: t.inkDim),
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: t.lineSoft)),
      titleTextStyle: text(RsScale.tH3, state, t.ink),
      iconTheme: IconThemeData(color: t.inkDim),
    ),
    dividerTheme: DividerThemeData(color: t.lineSoft, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: const EdgeInsets.all(RsScale.s1),
      shape: RoundedRectangleBorder(
        borderRadius: sheetCorners,
        side: BorderSide(color: t.lineSoft),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primaryAction),
    filledButtonTheme: FilledButtonThemeData(style: primaryAction),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: controlSize,
        side: BorderSide(color: t.line),
        shape: const RoundedRectangleBorder(borderRadius: smallCorners),
        textStyle: text(RsScale.tRow, label, t.ink),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.brand,
        minimumSize: controlSize,
        shape: const RoundedRectangleBorder(borderRadius: smallCorners),
        textStyle: text(RsScale.tRow, label, t.brand),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.actionTop,
      foregroundColor: t.onBrand,
      elevation: 2,
      shape: const RoundedRectangleBorder(borderRadius: sheetCorners),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: RsScale.s3,
        vertical: RsScale.s2,
      ),
      hintStyle: text(RsScale.tRow, body, t.inkFaint),
      border: OutlineInputBorder(
        borderRadius: smallCorners,
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: smallCorners,
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: smallCorners,
        borderSide: BorderSide(color: t.brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: smallCorners,
        borderSide: BorderSide(color: t.down),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: t.ink,
      iconColor: t.inkDim,
      selectedColor: t.ink,
      selectedTileColor: t.select,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: sheetCorners,
        side: BorderSide(color: t.lineStrong),
      ),
      titleTextStyle: text(RsScale.tH3, state, t.ink),
      contentTextStyle: text(RsScale.tRow, body, t.inkBody),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RsScale.rMd),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: sheetCorners,
        side: BorderSide(color: t.line),
      ),
      textStyle: text(RsScale.tRow, body, t.ink),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.brand,
      unselectedLabelColor: t.inkDim,
      indicatorColor: t.brand,
      dividerColor: t.lineSoft,
      labelStyle: text(RsScale.tRow, state, t.brand),
      unselectedLabelStyle: text(RsScale.tRow, label, t.inkDim),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.sunken,
      selectedColor: t.selectSoft,
      side: BorderSide(color: t.line),
      shape: const StadiumBorder(),
      labelStyle: text(RsScale.tLabel, label, t.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: text(RsScale.tRow, body, t.surface),
      shape: const RoundedRectangleBorder(borderRadius: sheetCorners),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.brand),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.selectSoft,
      elevation: 0,
    ),
  );
}
