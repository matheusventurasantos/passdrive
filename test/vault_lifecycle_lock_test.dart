import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/vault_lifecycle_lock.dart';

void main() {
  final start = DateTime(2026, 9, 14, 10);

  test('perda momentânea de foco não inicia bloqueio', () {
    final tracker = VaultLifecycleLockTracker();

    tracker.update(AppLifecycleState.resumed, start);
    final inactive = tracker.update(
      AppLifecycleState.inactive,
      start.add(const Duration(milliseconds: 100)),
    );
    final resumed = tracker.update(
      AppLifecycleState.resumed,
      start.add(const Duration(milliseconds: 500)),
    );

    expect(inactive.awaySince, isNotNull);
    expect(inactive.current, AppLifecycleState.inactive);
    expect(resumed.confirmedBackground, isFalse);
    expect(tracker.actuallyBackgrounded, isFalse);
  });

  test('inactive seguido de hidden confirma a saída e preserva o início', () {
    final tracker = VaultLifecycleLockTracker();

    tracker.update(AppLifecycleState.resumed, start);
    final inactiveAt = start.add(const Duration(seconds: 1));
    tracker.update(AppLifecycleState.inactive, inactiveAt);
    final hidden = tracker.update(
      AppLifecycleState.hidden,
      start.add(const Duration(seconds: 2)),
    );
    final paused = tracker.update(
      AppLifecycleState.paused,
      start.add(const Duration(seconds: 2, milliseconds: 20)),
    );
    final resumed = tracker.update(
      AppLifecycleState.resumed,
      start.add(const Duration(seconds: 62)),
    );

    expect(hidden.awaySince, inactiveAt);
    expect(paused.awaySince, inactiveAt);
    expect(resumed.confirmedBackground, isTrue);
    expect(resumed.awaySince, inactiveAt);
    expect(tracker.actuallyBackgrounded, isFalse);
  });

  test('detached também é tratado como saída protegida', () {
    final tracker = VaultLifecycleLockTracker();

    tracker.update(AppLifecycleState.resumed, start);
    tracker.update(
      AppLifecycleState.detached,
      start.add(const Duration(seconds: 1)),
    );
    final resumed = tracker.update(
      AppLifecycleState.resumed,
      start.add(const Duration(seconds: 2)),
    );

    expect(resumed.confirmedBackground, isTrue);
  });
}
