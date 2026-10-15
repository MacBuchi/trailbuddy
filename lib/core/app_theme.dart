import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_colors.dart';
import 'errors.dart';
import 'settings.dart';

/// Die Schriften — als Assets gebündelt (`assets/fonts/`, SIL OFL), nicht
/// zur Laufzeit geladen: Die App muss offline genauso aussehen.
abstract final class AppFonts {
  /// Fließtext, 400–600.
  static const body = 'Barlow';

  /// Titel, 700/800, gern in Großbuchstaben.
  static const display = 'BarlowCondensed';

  /// ALLE Zahlen: km, Hm, S-Grad. Nur 500 ist gebündelt.
  static const mono = 'JetBrainsMono';

  /// Der Stil für Zahlen, auf einen vorhandenen gelegt
  /// (`AppFonts.numbers(theme.textTheme.bodyMedium)`).
  static TextStyle numbers([TextStyle? base]) =>
      (base ?? const TextStyle()).copyWith(
        fontFamily: mono,
        fontWeight: FontWeight.w500,
        // Mono ist breiter als Barlow; ohne das lief eine Zahl neben
        // ihrem Text aus der Zeile.
        letterSpacing: -0.2,
      );
}

/// Das Theme eines Modus aus seiner Palette.
ThemeData buildAppTheme(AppPalette p) {
  final dark = p.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: p.brightness,
  ).copyWith(
    // Primär ist die Marke als TEXT (Links, Schalter, Textknöpfe) — im
    // Hellen darum das dunkle Grün. Gefüllte Knöpfe bekommen unten
    // ausdrücklich Lime.
    primary: p.accentText,
    onPrimary: dark ? AppColors.onBrand : Colors.white,
    primaryContainer: AppColors.brand,
    onPrimaryContainer: AppColors.onBrand,
    secondary: p.buddyText,
    tertiary: p.warningText,
    surface: p.ground,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: dark ? p.ground : p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surface2,
    surfaceContainerHighest: p.surface2,
    outline: p.muted,
    outlineVariant: p.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: p.brightness,
    fontFamily: AppFonts.body,
    // Barlow hat keine Pfeile (↑ ↓ → ←) und kein ✓, JetBrains Mono schon.
    // Ohne Ersatz holte Flutter Web eine Schrift aus dem Netz — offline
    // standen dort leere Kästchen (#338).
    fontFamilyFallback: const [AppFonts.mono],
    scaffoldBackgroundColor: p.ground,
    extensions: [p],
  );

  TextStyle? display(TextStyle? s, FontWeight w) =>
      s?.copyWith(fontFamily: AppFonts.display, fontWeight: w, letterSpacing: 0.2);
  final t = base.textTheme;
  final textTheme = t.copyWith(
    displayLarge: display(t.displayLarge, FontWeight.w800),
    displayMedium: display(t.displayMedium, FontWeight.w800),
    displaySmall: display(t.displaySmall, FontWeight.w800),
    headlineLarge: display(t.headlineLarge, FontWeight.w800),
    headlineMedium: display(t.headlineMedium, FontWeight.w700),
    headlineSmall: display(t.headlineSmall, FontWeight.w700),
    titleLarge: display(t.titleLarge, FontWeight.w700),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  ).apply(bodyColor: p.text, displayColor: p.text);

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: p.ground,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      // MIT Größe: `textTheme` bekommt seine Größen erst in `Theme.of`
      // (Typografie), dieser Stil aber nie — ohne sie stand jeder Titel
      // in 14 px da.
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22),
    ),
    // Der Knopf bleibt in beiden Modi Lime mit dunkler Schrift.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? p.line : AppColors.brand),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? p.muted : AppColors.onBrand),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: AppColors.onBrand,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.brand : null),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.onBrand : p.text),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.ground,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brand,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.onBrand : p.muted)),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: p.line),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: p.line),
      selectedColor: p.surface2,
    ),
    // Die Leiste ist in beiden Modi dunkel (im Hellen: die Textfarbe als
    // Fläche), die Aktion deshalb immer Lime — die Marke auf Dunkel.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? p.surface2 : p.text,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? p.text : p.ground),
      actionTextColor: AppColors.brand,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accentText),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(p.accentText)),
    ),
  );
}

/// „Erscheinungsbild" (System/Hell/Dunkel), gerätelokal. Vorgabe: wie
/// das System.
class AppearanceNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => parseThemeMode(ref.read(settingsProvider).appearance);

  void set(ThemeMode mode) {
    state = mode;
    ref
        .read(settingsProvider)
        .setAppearance(mode.name)
        .catchError((Object e, StackTrace s) => logError('Erscheinungsbild merken', e, s));
  }
}

ThemeMode parseThemeMode(String? name) =>
    ThemeMode.values.where((m) => m.name == name).firstOrNull ?? ThemeMode.system;

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, ThemeMode>(AppearanceNotifier.new);

/// Die Lizenztexte der gebündelten Schriften in „Open-Source-Lizenzen" —
/// die OFL verlangt, dass sie mitreisen.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Barlow', 'Barlow Condensed'],
        await rootBundle.loadString('assets/fonts/Barlow-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'],
        await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Noto Sans (Kartenbeschriftung)'],
        await rootBundle.loadString('assets/map_glyphs/OFL.txt'));
  });
}
