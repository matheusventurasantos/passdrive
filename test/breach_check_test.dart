import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/health/breach_check.dart';
import 'package:passdrive/vault/vault_models.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);

  VaultService service({required String id, required String password}) =>
      VaultService(
        id: id,
        name: id,
        email: 'pessoal@example.com',
        url: 'example.com',
        username: 'pessoal',
        password: password,
        favorite: false,
        createdAt: now,
        updatedAt: now,
      );

  test('consulta somente o prefixo SHA-1 e encontra senha vazada', () async {
    String? sentPrefix;
    final client = PwnedPasswordsClient(
      lookup: (prefix) async {
        sentPrefix = prefix;
        return '1E4C9B93F3F0682250B6CF8331B7EE68FD8:46658894\r\n';
      },
    );

    expect(await client.isCompromised('password'), isTrue);
    expect(sentPrefix, '5BAA6');
    expect(sentPrefix, isNot(contains('password')));
  });

  test('não marca senha ausente da resposta como comprometida', () async {
    final client = PwnedPasswordsClient(
      lookup: (_) async => 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1\r\n',
    );

    expect(await client.isCompromised('password'), isFalse);
  });

  test('rejeita resposta da API acima do limite de memória', () async {
    final client = PwnedPasswordsClient(
      lookup: (_) async => 'A' * (pwnedPasswordsMaxRangeResponseBytes + 1),
    );

    expect(
      () => client.isCompromised('password'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita linha da API com formato inválido', () async {
    final client = PwnedPasswordsClient(
      lookup: (_) async => 'nao-e-um-sufixo:1\r\n',
    );

    expect(
      () => client.isCompromised('password'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'resultado indisponível não é apresentado como zero comprometidas',
    () async {
      final controller = BreachCheckController(
        client: PwnedPasswordsClient(lookup: (_) async => throw Exception()),
      );
      await controller.refresh([service(id: 'a', password: 'Senha!12345')]);

      expect(controller.status, BreachVerificationStatus.unavailable);
      expect(controller.compromisedCount, isNull);
    },
  );

  test('não consulta a mesma senha duas vezes na mesma sessão', () async {
    var calls = 0;
    final controller = BreachCheckController(
      client: PwnedPasswordsClient(
        lookup: (_) async {
          calls++;
          return 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1\r\n';
        },
      ),
    );
    final services = [
      service(id: 'a', password: 'Senha!12345'),
      service(id: 'b', password: 'Senha!12345'),
    ];

    await controller.refresh(services);
    await controller.refresh(services);

    expect(calls, 1);
    expect(controller.compromisedCount, 0);
  });

  test('mantém senhas diferentes como credenciais independentes', () async {
    var calls = 0;
    final controller = BreachCheckController(
      client: PwnedPasswordsClient(
        lookup: (_) async {
          calls++;
          return 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1\r\n';
        },
      ),
    );
    final services = [
      service(id: 'a', password: 'Senha!12345'),
      service(id: 'b', password: 'Outra!98765'),
    ];

    await controller.refresh(services);

    expect(calls, 2);
    expect(controller.compromisedCount, 0);
  });

  test('uma nova abertura reinicia a verificação da sessão', () async {
    var calls = 0;
    final controller = BreachCheckController(
      client: PwnedPasswordsClient(
        lookup: (_) async {
          calls++;
          return 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1\r\n';
        },
      ),
    );
    final services = [service(id: 'a', password: 'Senha!12345')];

    await controller.refresh(services);
    await controller.beginSession(services);

    expect(calls, 2);
  });

  test(
    'resultado salvo mantém a contagem enquanto uma nova checagem começa',
    () async {
      final response = Completer<String>();
      final controller = BreachCheckController(
        client: PwnedPasswordsClient(lookup: (_) => response.future),
      );
      final item = service(id: 'a', password: 'Senha!12345');
      final check = VaultBreachCheck(
        compromised: true,
        checkedAt: now,
        serviceUpdatedAt: item.updatedAt,
      );

      final checking = controller.beginSession(
        [item],
        cachedChecks: {'a': check},
      );

      expect(controller.isChecking, isTrue);
      expect(controller.compromisedCount, 1);
      response.complete('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1\r\n');
      await checking;
      expect(controller.compromisedCount, 0);
    },
  );
}
