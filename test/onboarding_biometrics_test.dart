import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/onboarding/onboarding_step_two.dart';

void main() {
  testWidgets('biometria inicia desligada e aguarda confirmação ao ativar', (
    tester,
  ) async {
    final confirmation = Completer<bool>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingStepTwo(
            initialPassword: '',
            onPasswordChanged: (_) {},
            onContinue: () {},
            onBiometricsChanged: (value) {
              requests++;
              return confirmation.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(requests, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    confirmation.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
