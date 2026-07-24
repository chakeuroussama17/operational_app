import 'package:flutter/material.dart';

import 'config/constants.dart';
import 'config/theme_controller.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const HicomOpsApp());
}

/// HICOM Diecastings production shift-log app.
///
/// Listens to [themeController] and to platform-brightness changes so the
/// whole tree rebuilds — and [AppColors.brightness] is re-synced — whenever
/// the effective light/dark mode changes.
class HicomOpsApp extends StatefulWidget {
  const HicomOpsApp({super.key});

  @override
  State<HicomOpsApp> createState() => _HicomOpsAppState();
}

class _HicomOpsAppState extends State<HicomOpsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  // Fired when the device switches light/dark while mode == system.
  @override
  void didChangePlatformBrightness() => setState(() {});

  Brightness _effectiveBrightness(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode = themeController.value;
    // Keep the hardcoded AppColors getters in sync with what MaterialApp
    // will actually render this frame.
    AppColors.brightness = _effectiveBrightness(mode);

    return MaterialApp(
      title: 'HDSB Operations',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      // Not const: a new instance each rebuild forces HomeScreen (and its
      // subtree) to rebuild on a theme toggle so the AppColors getters are
      // re-read. A const HomeScreen would be canonicalised and skipped.
      // ignore: prefer_const_constructors
      home: HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final surface = AppColors.surfaceOf(brightness);
    final background = AppColors.backgroundOf(brightness);
    final onSurface = AppColors.textPrimaryOf(brightness);
    final border = AppColors.borderOf(brightness);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        brightness: brightness,
        primary: AppColors.navy,
        secondary: AppColors.steelBlue,
        tertiary: AppColors.amber,
        error: AppColors.danger,
        surface: surface,
      ).copyWith(onSurface: onSurface),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      // Filled inputs with a strong focus ring — legible on the factory floor
      // and easy to hit with gloves.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        hintStyle: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.steelBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        errorStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: const TextStyle(fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: surface,
        shadowColor: AppColors.navy.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.steelBlue,
      ),
    );
  }
}
