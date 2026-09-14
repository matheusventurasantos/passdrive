import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/health/password_health_page.dart';
import 'package:passdrive/generator/password_generator_page.dart';
import 'package:passdrive/passwords/passwords_page.dart';
import 'package:passdrive/settings/settings_page.dart';
import 'package:passdrive/vault/vault_access_sheet.dart';
import 'package:passdrive/vault/vault_models.dart';
import 'package:passdrive/onboarding/onboarding_step_one.dart';
import 'package:passdrive/onboarding/onboarding_step_two.dart';
import 'package:passdrive/onboarding/onboarding_step_three.dart';

void main() {
  testWidgets('seletor de bloqueio expõe e altera as cinco opções', (
    tester,
  ) async {
    VaultAutoLock? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultAutoLockPicker(
            value: VaultAutoLock.immediately,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Imediatamente'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<VaultAutoLock>));
    await tester.pumpAndSettle();
    expect(find.text('Após 1 minuto'), findsOneWidget);
    expect(find.text('Após 5 minutos'), findsOneWidget);
    expect(find.text('Após 15 minutos'), findsOneWidget);
    expect(find.text('Nunca'), findsOneWidget);
    await tester.tap(find.text('Após 5 minutos').last);
    expect(selected, VaultAutoLock.fiveMinutes);
  });

  testWidgets('Senhas suporta escala de texto ampliada sem exceção', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(home: PasswordsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saúde suporta escala 2x e mantém cartões acessíveis', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(home: PasswordHealthPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('indicadores de saúde abrem o filtro correspondente', (
    tester,
  ) async {
    String? selectedFilter;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordHealthPage(
          onOpenPasswords: (filter) => selectedFilter = filter,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final weakLabel = find.text('Fracas');
    await tester.ensureVisible(weakLabel);
    await tester.pump();
    await tester.tap(weakLabel);
    expect(selectedFilter, 'weak');
  });

  testWidgets('Gerador e Ajustes suportam escala 2x sem overflow', (
    tester,
  ) async {
    const mediaQuery = MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2)),
      child: MaterialApp(home: PasswordGeneratorPage()),
    );
    await tester.pumpWidget(mediaQuery);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ajustes mostra privacidade em um menu inferior', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.tap(find.text('Privacidade'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Seu cofre fica neste aparelho e é criptografado.'),
      findsOneWidget,
    );
  });

  testWidgets('onboarding se adapta a tela curta e fonte ampliada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    Future<void> pump(Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    }

    await pump(OnboardingStepOne(onContinue: () {}));
    expect(find.text('Continuar'), findsOneWidget);

    await pump(
      OnboardingStepTwo(
        initialPassword: '',
        onPasswordChanged: (_) {},
        onContinue: () {},
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);

    await pump(OnboardingStepThree(onDownload: () {}, onSkip: () {}));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -360),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
}
