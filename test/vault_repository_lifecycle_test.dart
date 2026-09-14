import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/vault_crypto.dart';
import 'package:passdrive/vault/vault_models.dart';
import 'package:passdrive/vault/vault_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'fecha banco e limpa o snapshot mesmo com falha de sincronização',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      final crypto = VaultCrypto();
      final created = await crypto.create('Senha-teste!42');
      final repository = VaultRepository.forTesting(
        database: database,
        crypto: crypto,
        metadata: created.metadata,
        vaultKey: created.vaultKey,
        snapshot: const VaultSnapshot(accounts: [], services: []),
      );
      repository.beforeClose = () async {
        throw StateError('falha simulada de sincronização');
      };

      await expectLater(repository.close(), throwsStateError);
      expect(repository.snapshot.accounts, isEmpty);
      expect(repository.snapshot.services, isEmpty);
      expect(created.vaultKey.isDestroyed, isTrue);
      await expectLater(created.vaultKey.extractBytes(), throwsStateError);

      var databaseClosed = false;
      try {
        await database.query('sqlite_master');
      } on Object {
        databaseClosed = true;
      }
      expect(databaseClosed, isTrue);
    },
  );
}
