import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/main.dart';
import 'package:passdrive/onboarding/onboarding_page.dart';

void main() {
  testWidgets('Voltar preserva o cadastro e o texto digitado', (tester) async {
    await tester.pumpWidget(const PassDriveApp(home: OnboardingPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Continuar').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Example-password!17');
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Example-password!17',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('menu de seleção usa a localização oficial em português', (
    tester,
  ) async {
    await tester.pumpWidget(
      const PassDriveApp(home: Scaffold(body: TextField())),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TextField));
    final labels = MaterialLocalizations.of(context);
    expect(labels.copyButtonLabel, 'Copiar');
    expect(labels.pasteButtonLabel, 'Colar');
    expect(labels.cutButtonLabel, 'Cortar');
  });
}
