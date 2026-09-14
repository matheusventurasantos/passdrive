import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/autofill/autofill_bridge.dart';
import 'package:passdrive/vault/vault_models.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('classifica uma identidade com arroba como email', () {
    final candidate = AutofillSaveCandidate.fromMap({
      'id': 'candidate-1',
      'packageName': 'org.mozilla.firefox',
      'domain': 'WWW.Example.com',
      'username': 'pessoa@example.com',
      'password': 'segredo',
    });

    expect(candidate.hasEmail, isTrue);
    expect(candidate.email, 'pessoa@example.com');
    expect(candidate.username, isEmpty);
    expect(candidate.domain, 'www.example.com');
  });

  test('classifica uma identidade sem arroba como usuário', () {
    final candidate = AutofillSaveCandidate.fromMap({
      'id': 'candidate-2',
      'packageName': 'com.example.app',
      'domain': '',
      'username': 'arthur',
      'password': 'segredo',
    });

    expect(candidate.hasEmail, isFalse);
    expect(candidate.email, isEmpty);
    expect(candidate.username, 'arthur');
    expect(candidate.domain, isNull);
  });

  test(
    'cache do Autofill não replica o cofre e limita o handoff ativo',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('passdrive/autofill'), (
            call,
          ) async {
            calls.add(call);
            return null;
          });
      final now = DateTime.utc(2026, 1, 1);
      final snapshot = VaultSnapshot(
        accounts: const [],
        services: List.generate(
          20,
          (index) => VaultService(
            id: 'service-$index',
            name: 'Example $index',
            email: 'user@example.com',
            url: 'example.com',
            username: 'user$index',
            password: 'Senha!$index',
            favorite: false,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );

      await AutofillBridge.cacheSnapshot(snapshot);
      expect(calls.single.method, 'clear');

      calls.clear();
      AutofillBridge.pending.value = const AutofillRequest(
        id: 'active-request',
        packageName: 'org.mozilla.firefox',
        domain: 'example.com',
        hasUsername: true,
        hasPassword: true,
      );
      await AutofillBridge.cacheSnapshot(snapshot, transient: true);
      final arguments = calls.single.arguments as Map;
      expect(arguments['credentials'], hasLength(8));
      expect(arguments['transient'], true);
      AutofillBridge.pending.value = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('passdrive/autofill'),
            null,
          );
    },
  );
}
