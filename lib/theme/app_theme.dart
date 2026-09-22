import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Koyu tema renkleri (degismez). Ana ekran widget'i her zaman koyu cizilir.
class DarkColors {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF161A22);
  static const surfaceAlt = Color(0xFF1E232E);
  static const accent = Color(0xFF4ADE80);
  static const accentSoft = Color(0xFF1B3A2A);
  static const best = Color(0xFFFACC15);
  static const bestSoft = Color(0xFF3A3310);
  static const text = Color(0xFFF1F4F9);
  static const textDim = Color(0xFF8A93A6);
  static const divider = Color(0xFF232937);
  static const water = Color(0xFF3B82F6);
  static const waterSoft = Color(0xFF1B2E4B);
  static const error = Color(0xFFEF5350);
  static const km = Color(0xFF38BDF8);
  static const kcal = Color(0xFFFF7043);
  static const time = Color(0xFFA78BFA);
}

/// Acik tema renkleri: yalniz Ayarlar > Gorunum'den Acik secilince kullanilir.
class LightColors {
  static const bg = Color(0xFFF3F5F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEBEFF5);
  static const accent = Color(0xFF16A34A);
  static const accentSoft = Color(0xFFDCFCE7);
  static const best = Color(0xFFCA8A04);
  static const bestSoft = Color(0xFFFEF3C7);
  static const text = Color(0xFF111827);
  static const textDim = Color(0xFF6B7280);
  static const divider = Color(0xFFE2E6ED);
  static const water = Color(0xFF2563EB);
  static const waterSoft = Color(0xFFDBEAFE);
  static const error = Color(0xFFE53935);
  static const km = Color(0xFF0284C7);
  static const kcal = Color(0xFFF4511E);
  static const time = Color(0xFF7C3AED);
}

/// AMOLED: koyu temanin tam siyah zeminli cesidi (OLED ekranda pil
/// tasarrufu, daha derin kontrast). Yalniz zemin/kart/cizgi farklidir.
class AmoledColors {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF0E1116);
  static const surfaceAlt = Color(0xFF181C24);
  static const divider = Color(0xFF1E232D);
}

/// Tema secenekleri. Kayitta [name] kullanilir.
enum AppThemeMode { dark, amoled, light }

/// Etkin temanin renkleri. Varsayilan koyu; [isLight] yalniz kullanici
/// Acik temayi sectiginde true olur.
class AppColors {
  static bool isLight = false;

  /// Koyu temanin AMOLED cesidi secili mi (isLight ile birlikte true olmaz).
  static bool isAmoled = false;

  /// Koyu temadaki degeri aynen korur, acik temada [light] doner.
  static Color pick(Color dark, Color light) => isLight ? light : dark;

  static Color get bg => isLight
      ? LightColors.bg
      : isAmoled
          ? AmoledColors.bg
          : DarkColors.bg;
  static Color get surface => isLight
      ? LightColors.surface
      : isAmoled
          ? AmoledColors.surface
          : DarkColors.surface;
  static Color get surfaceAlt => isLight
      ? LightColors.surfaceAlt
      : isAmoled
          ? AmoledColors.surfaceAlt
          : DarkColors.surfaceAlt;
  static Color get accent => isLight ? LightColors.accent : DarkColors.accent;
  static Color get accentSoft =>
      isLight ? LightColors.accentSoft : DarkColors.accentSoft;
  // En iyi gun / rozet: altin (kalorinin turuncusundan ayri).
  static Color get best => isLight ? LightColors.best : DarkColors.best;
  static Color get bestSoft => isLight ? LightColors.bestSoft : DarkColors.bestSoft;
  static Color get text => isLight ? LightColors.text : DarkColors.text;
  static Color get textDim => isLight ? LightColors.textDim : DarkColors.textDim;
  static Color get divider => isLight
      ? LightColors.divider
      : isAmoled
          ? AmoledColors.divider
          : DarkColors.divider;
  static Color get water => isLight ? LightColors.water : DarkColors.water;
  static Color get waterSoft =>
      isLight ? LightColors.waterSoft : DarkColors.waterSoft;
  static Color get error => isLight ? LightColors.error : DarkColors.error;

  /// Kart golgesi: yalniz acik temada yumusak derinlik; koyu temada yok
  /// (koyu tema ince cerceveyle aynen kalir).
  static List<BoxShadow>? get cardShadow => isLight
      ? const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ]
      : null;

  /// Yesil vurgunun ustundeki yazi/ikon.
  static Color get onAccent =>
      isLight ? Colors.white : const Color(0xFF07160E);
}

/// Olcu renkleri: tum ekranlarda ayni olcu ayni renkte (ilk bakista ayirt
/// edilsin diye birbirinden belirgin tonlar).
class MetricColors {
  static Color get steps => AppColors.accent; // yesil
  static Color get km => AppColors.pick(DarkColors.km, LightColors.km); // gok mavisi
  static Color get kcal =>
      AppColors.pick(DarkColors.kcal, LightColors.kcal); // turuncu-kirmizi
  static Color get time => AppColors.pick(DarkColors.time, LightColors.time); // mor
  static Color get water => AppColors.water; // mavi
}

/// Durum cubugu / sistem gezinme cubugu temaya uygun.
void applySystemUiStyle() {
  final light = AppColors.isLight;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
  ));
}

/// Tema secimi. Renkler statik getter oldugu icin degisimde tum agac
/// yeniden cizilir (durum korunur, sayfa/sekme kaybolmaz).
class ThemeController {
  static final mode = ValueNotifier<AppThemeMode>(AppThemeMode.dark);

  static void _apply(AppThemeMode m) {
    AppColors.isLight = m == AppThemeMode.light;
    AppColors.isAmoled = m == AppThemeMode.amoled;
    mode.value = m;
  }

  /// Kayitli ada gore tema (bilinmeyen/eksik -> koyu).
  static AppThemeMode parse(String? name) => AppThemeMode.values
      .firstWhere((m) => m.name == name, orElse: () => AppThemeMode.dark);

  /// Acilista kayitli secimi uygular (runApp oncesi).
  static void init(AppThemeMode m) => _apply(m);

  static void set(AppThemeMode m) {
    if (mode.value == m) return;
    _apply(m);
    applySystemUiStyle();
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(Element e) {
      e.markNeedsBuild();
      if (e is RenderObjectElement) e.renderObject.markNeedsPaint();
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
}

ThemeData buildAppTheme() {
  final light = AppColors.isLight;
  final scheme = light
      ? ColorScheme.light(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          onSurface: AppColors.text,
          error: AppColors.error,
        )
      : AppColors.isAmoled
          ? const ColorScheme.dark(
              primary: DarkColors.accent,
              onPrimary: Color(0xFF07160E),
              secondary: DarkColors.accent,
              surface: AmoledColors.surface,
              onSurface: DarkColors.text,
              error: Color(0xFFEF5350),
            )
          : const ColorScheme.dark(
              primary: DarkColors.accent,
              onPrimary: Color(0xFF07160E),
              secondary: DarkColors.accent,
              surface: DarkColors.surface,
              onSurface: DarkColors.text,
              error: Color(0xFFEF5350),
            );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    // Acik temada SnackBar yazisi acik zemin uzerinde okunabilsin.
    snackBarTheme: light
        ? SnackBarThemeData(
            backgroundColor: AppColors.surfaceAlt,
            contentTextStyle: TextStyle(color: AppColors.text, fontSize: 14),
          )
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accentSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.accent : AppColors.textDim,
          size: 24,
        );
      }),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(color: AppColors.divider, space: 1),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surfaceAlt,
      thumbColor: AppColors.accent,
      overlayColor: AppColors.pick(
        const Color(0x334ADE80),
        LightColors.accent.withValues(alpha: 0.2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(color: AppColors.textDim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );

  // Rakamlar esit genislikte: canli sayimda sayilar titremez/kaymaz.
  return base.copyWith(
    textTheme: _tabular(base.textTheme),
    primaryTextTheme: _tabular(base.primaryTextTheme),
  );
}

const _tnum = [FontFeature.tabularFigures()];

TextTheme _tabular(TextTheme t) {
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFeatures: _tnum);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

