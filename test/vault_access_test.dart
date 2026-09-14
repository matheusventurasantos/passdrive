import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/vault_access.dart';
import 'package:passdrive/vault/vault_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final metadata = VaultMetadata(
    formatVersion: 1,
    salt: List.filled(16, 1),
    wrappedKey: SecretBox(
      List.filled(32, 2),
      nonce: List.filled(12, 3),
      mac: Mac(List.filled(16, 4)),
    ),
  );
  final key = SecretKey(List.generate(32, (index) => index));

  test('arquivo exportado desbloqueia o conteúdo autenticado', () async {
    final crypto = VaultCrypto();
    final encrypted = await crypto.encryptSnapshot('conteúdo do cofre', key);
    final bytes = await RecoveryKeyFile.encode(metadata, key);
    final recovered = await RecoveryKeyFile.decode(bytes, metadata);
    expect(
      await crypto.decryptSnapshot(encrypted, recovered),
      'conteúdo do cofre',
    );
  });

  test(
    'arquivo de outro cofre falha ao validar o conteúdo autenticado',
    () async {
      final other = VaultMetadata(
        formatVersion: 1,
        salt: [9],
        wrappedKey: metadata.wrappedKey,
      );
      final bytes = await RecoveryKeyFile.encode(other, key);
      await expectLater(
        RecoveryKeyFile.decode(bytes, metadata),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('rejeita arquivos vazios, inválidos e grandes', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([255]),
      Uint8List(16385),
    ]) {
      await expectLater(
        RecoveryKeyFile.decode(bytes, metadata),
        throwsFormatException,
      );
    }
  });

  test('chave adulterada não consegue decifrar o cofre', () async {
    final crypto = VaultCrypto();
    final encrypted = await crypto.encryptSnapshot('segredo', key);
    final value =
        jsonDecode(utf8.decode(await RecoveryKeyFile.encode(metadata, key)))
            as Map;
    value['key'] = base64Encode(List.filled(32, 99));
    final recovered = await RecoveryKeyFile.decode(
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      metadata,
    );
    await expectLater(
      crypto.decryptSnapshot(encrypted, recovered),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('backup guarda apenas estado cifrado e exige o mesmo cofre', () async {
    final crypto = VaultCrypto();
    final encrypted = await crypto.encryptSnapshot('segredo preservado', key);
    final bytes = await VaultBackupFile.encode(metadata, encrypted);
    final restored = await VaultBackupFile.decode(bytes, metadata);
    expect(await crypto.decryptSnapshot(restored, key), 'segredo preservado');

    final other = VaultMetadata(
      formatVersion: 1,
      salt: List.filled(16, 9),
      wrappedKey: metadata.wrappedKey,
    );
    await expectLater(
      VaultBackupFile.decode(bytes, other),
      throwsFormatException,
    );
  });

  test('metadados rejeitam campos criptográficos truncados ou adulterados', () {
    final malformed = Map<String, Object?>.from(metadata.toJson());
    final wrapped = Map<String, Object?>.from(malformed['wrappedKey']! as Map);
    wrapped['nonce'] = base64Encode(List.filled(11, 0));
    malformed['wrappedKey'] = wrapped;
    expect(() => VaultMetadata.fromJson(malformed), throwsFormatException);

    final invalidSalt = Map<String, Object?>.from(metadata.toJson())
      ..['salt'] = 'não é base64';
    expect(() => VaultMetadata.fromJson(invalidSalt), throwsFormatException);
  });

  test('payload cifrado rejeita nonce e MAC fora do tamanho do GCM', () async {
    final crypto = VaultCrypto();
    final encrypted = await crypto.encryptSnapshot('segredo', key);
    final invalidNonce = Map<String, Object?>.from(encrypted.toJson())
      ..['nonce'] = base64Encode(List.filled(1, 0));
    expect(
      () => EncryptedVaultPayload.fromJson(invalidNonce),
      throwsFormatException,
    );
    final invalidMac = Map<String, Object?>.from(encrypted.toJson())
      ..['mac'] = base64Encode(List.filled(15, 0));
    expect(
      () => EncryptedVaultPayload.fromJson(invalidMac),
      throwsFormatException,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VaultAccess.channel, null);
  });

  test(
    'cancelar arquivos não confirma download nem deixa acesso ocupado',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VaultAccess.channel, (_) async => null);
      expect(await VaultAccess.save(Uint8List(1)), isFalse);
      expect(await VaultAccess.pick(), isNull);
      expect(VaultAccess.busy, isFalse);
    },
  );

  test(
    'arquivo selecionado é copiado para um buffer que pode ser limpo',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            VaultAccess.channel,
            (_) async => Uint8List.fromList([1, 2, 3]),
          );
      final bytes = await VaultAccess.pick();
      expect(bytes, [1, 2, 3]);
      bytes!.fillRange(0, bytes.length, 0);
      expect(bytes, [0, 0, 0]);
    },
  );

  test('cancelar biometria libera o estado para senha e arquivo', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          VaultAccess.channel,
          (_) async => throw PlatformException(code: 'cancelled'),
        );
    await expectLater(
      VaultAccess.authenticate(),
      throwsA(isA<PlatformException>()),
    );
    expect(VaultAccess.busy, isFalse);
  });
}
