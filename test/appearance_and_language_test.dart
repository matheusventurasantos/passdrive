import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/main.dart';
import 'package:passdrive/settings/app_strings.dart';
import 'package:passdrive/settings/appearance_preferences.dart';
import 'package:passdrive/theme/app_palette.dart';
import 'package:passdrive/windows/desktop_layout.dart';

void main() {
  final preferences = AppearancePreferences.instance;

  tearDown(() {
    preferences.language = 'pt';
    preferences.mode = ThemeMode.system;
    preferences.fontScale = 1;
    preferences.shareTheme = false;
    preferences.applyRemoteTheme(null);
  });

  test('catálogo traduz os textos centrais para inglês', () {
    preferences.language = 'en';
    expect(tr('Ajustes'), 'Settings');
    expect(tr('Saúde das senhas'), 'Password health');
    expect(tx('Senha copiada.', 'Password copied.'), 'Password copied.');
  });

  testWidgets('aplicativo aplica idioma, tema e escala escolhidos', (
    tester,
  ) async {
    preferences.language = 'en';
    preferences.mode = ThemeMode.dark;
    preferences.fontScale = 1.2;

    await tester.pumpWidget(
      const PassDriveApp(home: Scaffold(body: Text('PassDrive'))),
    );

    final context = tester.element(find.text('PassDrive'));
    expect(Localizations.localeOf(context).languageCode, 'en');
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(12, .01));
  });

  test('tema remoto só substitui o tema enquanto conectado', () {
    preferences.mode = ThemeMode.light;
    preferences.applyRemoteTheme('dark');
    expect(preferences.effectiveMode, ThemeMode.dark);
    preferences.applyRemoteTheme(null);
    expect(preferences.effectiveMode, ThemeMode.light);
  });

  test('tokens do desktop formam uma hierarquia escura coerente', () {
    preferences.mode = ThemeMode.dark;

    expect(desktopBackground, isNot(const Color(0xFFF8FAFE)));
    expect(desktopSurface, isNot(desktopBackground));
    expect(desktopLine, isNot(desktopSurface));
    expect(desktopMuted, isNot(const Color(0xFF748099)));
  });

  test('tokens do mobile preservam superfícies, bordas e anel de saúde', () {
    preferences.mode = ThemeMode.dark;

    expect(AppPalette.canvas, const Color(0xFF101827));
    expect(AppPalette.surface, const Color(0xFF182235));
    expect(AppPalette.resolve(const Color(0xFFE5EAF3)), isNot(Colors.white));
    expect(AppPalette.scoreRingOuter, isNot(AppPalette.scoreRingTrack));
    expect(AppPalette.scoreRingBlue, isNot(const Color(0xFF2F6FEB)));
  });
}
