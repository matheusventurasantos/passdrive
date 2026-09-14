import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/master_password_policy.dart';
import 'package:passdrive/vault/vault_access.dart';
import 'package:passdrive/vault/vault_crypto.dart';
import 'package:passdrive/vault/vault_repository.dart';
import 'package:passdrive/vault/master_password_throttle.dart';

class MemoryThrottleStore implements MasterPasswordThrottleStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  test('a política rejeita senha curta, comum e previsível', () {
    expect(
      MasterPasswordPolicy.errorFor('curta'),
      'A senha mestra precisa ter pelo menos 12 caracteres.',
    );
    expect(
      MasterPasswordPolicy.errorFor('Senha!123'),
      'A senha mestra precisa ter pelo menos 12 caracteres.',
    );
    expect(
      MasterPasswordPolicy.errorFor('senha1234'),
      'Escolha uma senha menos comum e previsível.',
    );
    expect(
      MasterPasswordPolicy.errorFor('12345678'),
      'Escolha uma senha menos comum e previsível.',
    );
    expect(MasterPasswordPolicy.errorFor('Vento!Azul27'), isNull);
    expect(
      MasterPasswordPolicy.errorFor('MinhaSenha20200101'),
      'Evite datas, telefones e sequências numéricas previsíveis.',
    );
    expect(
      MasterPasswordPolicy.errorFor('abcabcabcabc'),
      'Evite sequências previsíveis de caracteres.',
    );
  });

  test('tentativas da senha mestra usam backoff persistido', () async {
    var now = DateTime.utc(2026, 1, 1);
    final store = MemoryThrottleStore();
    final first = MasterPasswordAttemptThrottle(store: store, now: () => now);
    await first.load();
    expect(first.remaining, Duration.zero);
    expect(await first.registerFailure(), const Duration(seconds: 1));

    final reopened = MasterPasswordAttemptThrottle(
      store: store,
      now: () => now,
    );
    await reopened.load();
    expect(reopened.remaining, const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 1));
    expect(await reopened.registerFailure(), const Duration(seconds: 2));
    await reopened.reset();
    expect(reopened.remaining, Duration.zero);
  });

  test(
    'troca de senha reempacota somente a chave e mantém o conteúdo',
    () async {
      final crypto = VaultCrypto();
      final created = await crypto.create('Senha-atual!27');
      final encrypted = await crypto.encryptSnapshot(
        jsonEncode({
          'services': ['credencial preservada'],
        }),
        created.vaultKey,
      );
      final recoveryFile = await RecoveryKeyFile.encode(
        created.metadata,
        created.vaultKey,
      );

      final nextMetadata = await crypto.rewrapVaultKey(
        'Senha-nova!48',
        created.metadata,
        created.vaultKey,
      );
      final nextKey = await crypto.unlock('Senha-nova!48', nextMetadata);

      expect(
        await crypto.decryptSnapshot(encrypted, nextKey),
        jsonEncode({
          'services': ['credencial preservada'],
        }),
      );
      await expectLater(
        crypto.unlock('Senha-atual!27', nextMetadata),
        throwsA(isA<VaultUnlockException>()),
      );

      // A troca de senha não invalida um arquivo de recuperação já exportado:
      // a chave do cofre é a mesma, apenas o seu invólucro mudou.
      final recovered = await RecoveryKeyFile.decode(
        recoveryFile,
        nextMetadata,
      );
      expect(
        await recovered.extractBytes(),
        await created.vaultKey.extractBytes(),
      );
    },
  );

  test(
    'confirmação divergente é rejeitada antes da operação criptográfica',
    () {
      expect(
        () => MasterPasswordPolicy.validateChange(
          newPassword: 'Senha-nova!48',
          confirmation: 'Senha-nova!49',
        ),
        throwsA(isA<MasterPasswordConfirmationException>()),
      );
    },
  );

  test('fila de gravação continua recuperável depois de uma falha', () async {
    final queue = VaultWriteQueue();
    final failed = queue.enqueue<void>(() async {
      throw StateError('falha simulada de gravação');
    });
    final recovered = queue.enqueue<String>(() async => 'gravação seguinte');

    await expectLater(failed, throwsStateError);
    expect(await recovered, 'gravação seguinte');
    await queue.drain();
  });

  test(
    'metadados preservam a identidade de recuperação durante a troca',
    () async {
      final crypto = VaultCrypto();
      final created = await crypto.create('Senha-atual!27');
      final oldIdentity = await RecoveryKeyFile.identity(created.metadata);
      final next = await crypto.rewrapVaultKey(
        'Senha-nova!48',
        created.metadata,
        created.vaultKey,
      );

      expect(next.recoveryIdentity, oldIdentity);
      expect(next.salt, isNot(equals(created.metadata.salt)));
      expect(
        next.wrappedKey.cipherText,
        isNot(equals(created.metadata.wrappedKey.cipherText)),
      );
    },
  );
}
