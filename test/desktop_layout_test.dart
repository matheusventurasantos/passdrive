import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/main.dart';
import 'package:passdrive/navigation/passdrive_shell.dart';
import 'package:passdrive/onboarding/onboarding_step_one.dart';
import 'package:passdrive/onboarding/onboarding_step_two.dart';
import 'package:passdrive/onboarding/onboarding_step_three.dart';
import 'package:passdrive/windows/desktop_sidebar.dart';
import 'package:passdrive/windows/desktop_window_frame.dart';

Future<void> preview(WidgetTester tester, String name) async {
  if (const bool.fromEnvironment('DESKTOP_PREVIEWS')) {
    await expectLater(
      find.byType(PassDriveApp),
      matchesGoldenFile('../.dart_tool/desktop-previews/$name.png'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Kumbh Sans');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/KumbhSans-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(1280, 800),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(PassDriveApp(home: page));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text(label),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  testWidgets('desktop usa lateral fixa e layouts próprios nas quatro áreas', (
    tester,
  ) async {
    await mount(tester, const PassDriveShell());
    expect(find.byType(DesktopSidebar), findsOneWidget);
    final sidebar = tester.getRect(find.byType(DesktopSidebar));
    await preview(tester, 'inicio');
    await select(tester, 'Senhas');
    expect(find.text('Contas'), findsOneWidget);
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('joao@gmail.com'), findsWidgets);
    expect(tester.getRect(find.byType(DesktopSidebar)), sidebar);
    await preview(tester, 'senhas');
    await tester.enterText(find.byType(TextField).first, 'Netflix');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Netflix'), findsWidgets);
    expect(find.text('PayPal'), findsNothing);
    await select(tester, 'Gerador');
    expect(find.text('Letras maiúsculas (A–Z)'), findsOneWidget);
    await preview(tester, 'gerador');
    await select(tester, 'Ajustes');
    expect(find.text('Backup e recuperação'), findsOneWidget);
    await preview(tester, 'ajustes');
    await tester.tap(find.text('Sobre'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Fechar janela'), findsOneWidget);
    expect(find.byType(DesktopWindowFrame), findsOneWidget);
    await preview(tester, 'janela-interna');
    await tester.tap(find.byTooltip('Fechar janela'));
    await tester.pump(const Duration(milliseconds: 400));
    await select(tester, 'Início');
    expect(find.text('Saúde das senhas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'adicionar abre seletor e formulário centralizados, sem alterar navegação',
    (tester) async {
      await mount(tester, const PassDriveShell());
      await select(tester, 'Senhas');
      await tester.tap(find.text('Adicionar').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Adicionar conta'), findsOneWidget);
      await tester.tap(find.text('Adicionar conta'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await preview(tester, 'adicionar-conta');
      expect(find.byTooltip('Fechar janela'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar janela'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('janela menor e texto 2x sem overflow', (tester) async {
    await mount(
      tester,
      const PassDriveShell(),
      size: const Size(1000, 720),
      scale: 2,
    );
    for (final label in ['Senhas', 'Gerador', 'Ajustes', 'Início']) {
      await select(tester, label);
    }
    await select(tester, 'Senhas');
    await tester.tap(find.text('Adicionar').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Adicionar serviço'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byTooltip('Fechar janela'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await preview(tester, 'formulario-texto-2x');
    await tester.tap(find.byTooltip('Fechar janela'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('atalhos de teclado navegam mantendo a lateral', (tester) async {
    await mount(tester, const PassDriveShell());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Gerador de senhas'), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('onboarding desktop horizontal preserva validação e ações', (
    tester,
  ) async {
    var continued = 0;
    await mount(
      tester,
      Scaffold(body: OnboardingStepOne(onContinue: () => continued++)),
    );
    await preview(tester, 'onboarding-1');
    await tester.tap(find.text('Continuar'));
    expect(continued, 1);
    await mount(
      tester,
      Scaffold(
        body: OnboardingStepTwo(
          initialPassword: '',
          onPasswordChanged: (_) {},
          onContinue: () => continued++,
        ),
      ),
    );
    await preview(tester, 'onboarding-2');
    await tester.enterText(find.byType(TextField).at(0), 'vR9!mT4@xK7#pZ2&');
    await tester.enterText(find.byType(TextField).at(1), 'diferente');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('As senhas são diferentes.'), findsOneWidget);
    expect(continued, 1);
    await tester.enterText(find.byType(TextField).at(1), 'vR9!mT4@xK7#pZ2&');
    await tester.tap(find.text('Continuar'));
    expect(continued, 2);
    await mount(
      tester,
      Scaffold(
        body: OnboardingStepThree(onDownload: () {}, onSkip: () {}),
      ),
    );
    await preview(tester, 'onboarding-3');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
