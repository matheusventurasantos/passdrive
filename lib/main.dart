import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'windows/desktop_window_frame.dart';
import 'windows/desktop_layout.dart';
import 'vault/vault_gate_page.dart';
import 'windows/desktop_update_page.dart';
import 'autofill/autofill_bridge.dart';
import 'settings/appearance_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppearancePreferences.instance.load();
  AutofillBridge.initialize();
  runApp(const PassDriveApp());
}

class PassDriveApp extends StatelessWidget {
  const PassDriveApp({this.home, super.key});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppearancePreferences.instance,
      builder: (context, _) => _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    final preferences = AppearancePreferences.instance;
    final content =
        home ??
        (isWindowsDesktop ? const DesktopUpdatePage() : const VaultGatePage());
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PassDrive',
      locale: preferences.language == 'en'
          ? const Locale('en')
          : const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: preferences.effectiveMode,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101827),
        canvasColor: const Color(0xFF101827),
        cardColor: const Color(0xFF182235),
        dividerColor: const Color(0xFF2C3A52),
        fontFamily: 'Kumbh Sans',
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF4862E0),
              brightness: Brightness.dark,
            ).copyWith(
              surface: const Color(0xFF182235),
              surfaceContainerHighest: const Color(0xFF243149),
              outline: const Color(0xFF2C3A52),
              onSurface: const Color(0xFFEAF0FA),
            ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF182235),
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF182235),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Kumbh Sans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4862E0),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scaled = MediaQuery(
          data: media.copyWith(
            textScaler: _PreferenceTextScaler(
              media.textScaler,
              preferences.fontScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        return isWindowsDesktop
            ? Overlay.wrap(child: DesktopWindowFrame(child: scaled))
            : scaled;
      },
      home: content,
    );
  }
}

class _PreferenceTextScaler extends TextScaler {
  const _PreferenceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  // Required by TextScaler until Flutter removes the legacy compatibility API.
  // ignore: deprecated_member_use
  double get textScaleFactor => system.textScaleFactor * factor;
}
