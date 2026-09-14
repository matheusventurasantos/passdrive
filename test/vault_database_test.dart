import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/vault_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('migração valida o schema existente sem apagar o cofre', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE vault_metadata (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE vault_state (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
    );

    await VaultDatabase.runMigrationForTesting(database, 1, 2);

    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ),
      hasLength(2),
    );
  });

  test('migração falha fechada quando falta uma tabela do cofre', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE vault_metadata (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
    );

    await expectLater(
      VaultDatabase.runMigrationForTesting(database, 1, 2),
      throwsStateError,
    );
  });
}
