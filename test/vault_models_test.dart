import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/vault_models.dart';
import 'package:passdrive/vault/vault_repository.dart';
import 'dart:async';

void main() {
  final now = DateTime.utc(2026, 1, 1);

  VaultAccount account({bool favorite = false}) => VaultAccount(
    id: 'account-1',
    email: 'pessoal@example.com',
    provider: 'Email',
    favorite: favorite,
    createdAt: now,
    updatedAt: now,
  );

  VaultService service({bool favorite = false}) => VaultService(
    id: 'service-1',
    name: 'Exemplo',
    email: 'pessoal@example.com',
    url: 'example.com',
    username: 'pessoal',
    password: 'segredo',
    favorite: favorite,
    createdAt: now,
    updatedAt: now,
  );

  test('cofre antigo recebe bloqueio imediato como padrão', () {
    final decoded = VaultSnapshot.fromJson(const {
      'accounts': <Object>[],
      'services': <Object>[],
    });
    expect(decoded.autoLock, VaultAutoLock.immediately);
    expect(decoded.clipboardClear, VaultClipboardClear.oneMinute);
  });

  test('snapshot novo grava uma versão explícita sem quebrar cofre antigo', () {
    final current = VaultSnapshot(accounts: [account()], services: []).toJson();
    expect(current['formatVersion'], VaultSnapshot.formatVersion);
    expect(
      VaultSnapshot.fromJson(const {
        'accounts': <Object>[],
        'services': <Object>[],
      }).accounts,
      isEmpty,
    );
  });

  test('rejeita uma versão futura do cofre com erro compreensível', () {
    expect(
      () => VaultSnapshot.fromJson(const {
        'formatVersion': 99,
        'accounts': <Object>[],
        'services': <Object>[],
      }),
      throwsA(isA<VaultSnapshotUnsupportedVersionException>()),
    );
  });

  test(
    'migra snapshots legados e da versão anterior sem alterar a entrada',
    () {
      final legacy = {
        'formatVersion': 1,
        'accounts': [account().toJson()],
        'services': [service().toJson()],
      };
      final migrated = VaultSnapshot.fromJson(legacy);

      expect(migrated.accounts.single.email, account().email);
      expect(migrated.services.single.name, service().name);
      expect(migrated.autoLock, VaultAutoLock.immediately);
      expect(legacy['formatVersion'], 1);
      expect(migrated.toJson()['formatVersion'], VaultSnapshot.formatVersion);
    },
  );

  test('preserva emails legados e valida URL e datas ao abrir um item', () {
    final invalidEmail = account().toJson()..['email'] = 'sem-email';
    final legacy = VaultSnapshot.fromJson({
      'accounts': [invalidEmail],
      'services': <Object>[],
    });
    expect(legacy.accounts.single.email, 'sem-email');

    final invalidUrl = service().toJson()..['url'] = 'não é uma url';
    expect(
      () => VaultSnapshot.fromJson({
        'accounts': <Object>[],
        'services': [invalidUrl],
      }),
      throwsA(isA<VaultSnapshotFormatException>()),
    );

    final invalidDate = account().toJson()..['createdAt'] = 'quandova';
    expect(
      () => VaultSnapshot.fromJson({
        'accounts': [invalidDate],
        'services': <Object>[],
      }),
      throwsA(isA<VaultSnapshotFormatException>()),
    );
  });

  test('rejeita estrutura inválida e IDs duplicados ao abrir o cofre', () {
    expect(
      () => VaultSnapshot.fromJson(const {
        'accounts': 'não é uma lista',
        'services': <Object>[],
      }),
      throwsA(isA<VaultSnapshotFormatException>()),
    );

    final duplicate = account().toJson();
    expect(
      () => VaultSnapshot.fromJson({
        'accounts': [duplicate],
        'services': [
          service().toJson(),
          {...service().toJson(), 'id': duplicate['id']},
        ],
      }),
      throwsA(isA<VaultSnapshotFormatException>()),
    );
  });

  test(
    'campos futuros desconhecidos não impedem abrir um snapshot conhecido',
    () {
      final decoded = VaultSnapshot.fromJson({
        'formatVersion': VaultSnapshot.formatVersion,
        'accounts': <Object>[],
        'services': <Object>[],
        'campoFuturo': {'não': 'interfere'},
      });
      expect(decoded.services, isEmpty);
    },
  );

  test('configuração de bloqueio persiste no conteúdo criptografável', () {
    final original = VaultSnapshot(
      accounts: [account()],
      services: [service()],
      autoLock: VaultAutoLock.fiveMinutes,
    );
    final restored = VaultSnapshot.decode(original.encode());
    expect(restored.autoLock, VaultAutoLock.fiveMinutes);
    expect(restored.autoLock.seconds, 300);
  });

  test('preferência de limpeza da área de transferência persiste', () {
    final original = VaultSnapshot(
      accounts: [account()],
      services: [service()],
      clipboardClear: VaultClipboardClear.fiveMinutes,
    );
    final restored = VaultSnapshot.decode(original.encode());

    expect(restored.clipboardClear, VaultClipboardClear.fiveMinutes);
    expect(restored.clipboardClear.duration, const Duration(minutes: 5));
  });

  test(
    'preferência de captura de tela persiste com bloqueio seguro padrão',
    () {
      final allowed = VaultSnapshot(
        accounts: [account()],
        services: [service()],
        allowScreenCapture: true,
      );
      expect(VaultSnapshot.decode(allowed.encode()).allowScreenCapture, isTrue);

      final migrated = VaultSnapshot.fromJson({
        'formatVersion': 3,
        'accounts': <Object>[account().toJson()],
        'services': <Object>[service().toJson()],
        'autoLock': VaultAutoLock.immediately.name,
        'clipboardClear': VaultClipboardClear.oneMinute.name,
      });
      expect(migrated.allowScreenCapture, isFalse);
    },
  );

  test('resultado de vazamento persiste sem armazenar a senha', () {
    final check = VaultBreachCheck(
      compromised: true,
      checkedAt: now,
      serviceUpdatedAt: now,
    );
    final restored = VaultSnapshot.decode(
      VaultSnapshot(
        accounts: [account()],
        services: [service()],
        breachChecks: {'service-1': check},
      ).encode(),
    );

    expect(restored.breachChecks['service-1']?.compromised, isTrue);
    final saved =
        (restored.toJson()['breachChecks'] as Map)['service-1'] as Map;
    expect(
      saved.keys,
      unorderedEquals(['compromised', 'checkedAt', 'serviceUpdatedAt']),
    );
  });

  test('migra a versão 2 com a limpeza segura padrão', () {
    final migrated = VaultSnapshot.fromJson({
      'formatVersion': 2,
      'accounts': <Object>[account().toJson()],
      'services': <Object>[service().toJson()],
      'autoLock': VaultAutoLock.oneMinute.name,
    });

    expect(migrated.autoLock, VaultAutoLock.oneMinute);
    expect(migrated.clipboardClear, VaultClipboardClear.oneMinute);
  });

  test('alterações preservam configuração e favoritos', () {
    final original = VaultSnapshot(
      accounts: [account(favorite: true)],
      services: [service(favorite: true)],
      autoLock: VaultAutoLock.fifteenMinutes,
    );
    final edited = original.copyWith(
      services: [service(favorite: true).copyWith(name: 'Editado')],
    );
    final restored = VaultSnapshot.decode(edited.encode());
    expect(restored.autoLock, VaultAutoLock.fifteenMinutes);
    expect(restored.accounts.single.favorite, isTrue);
    expect(restored.services.single.favorite, isTrue);
    expect(restored.services.single.name, 'Editado');
  });

  test('as cinco opções possuem tempos esperados', () {
    expect(VaultAutoLock.immediately.seconds, 0);
    expect(VaultAutoLock.oneMinute.seconds, 60);
    expect(VaultAutoLock.fiveMinutes.seconds, 300);
    expect(VaultAutoLock.fifteenMinutes.seconds, 900);
    expect(VaultAutoLock.never.seconds, isNull);
    expect(VaultClipboardClear.thirtySeconds.seconds, 30);
    expect(VaultClipboardClear.never.seconds, isNull);
  });

  test('bloqueio aguarda alterações pendentes antes de fechar', () async {
    final queue = VaultWriteQueue();
    final write = Completer<void>();
    var persisted = false;
    queue.enqueue(() async {
      await write.future;
      persisted = true;
    });
    var drained = false;
    final closing = queue.drain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    write.complete();
    await closing;
    expect(persisted, isTrue);
    expect(drained, isTrue);
  });
}
