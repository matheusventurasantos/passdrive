import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

class VaultDatabase {
  static const name = 'passdrive_vault.sqlite';
  // Version 2 establishes a checked, transactional migration boundary. The
  // first migration does not rewrite user data because the schema itself did
  // not need a change; future schema changes must add an explicit step below.
  static const version = 2;

  static Future<Database> open() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      throw UnsupportedError(
        'O Windows acessa apenas o cofre autorizado pelo celular.',
      );
    }
    final directory = await getApplicationDocumentsDirectory();
    final databasePath = path.join(directory.path, name);

    return sqflite.openDatabase(
      databasePath,
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _validateSchema,
    );
  }

  @visibleForTesting
  static Future<void> runMigrationForTesting(
    Database database,
    int oldVersion,
    int newVersion,
  ) => _onUpgrade(database, oldVersion, newVersion);

  static Future<void> _onCreate(Database database, int version) async {
    await database.execute('''
      CREATE TABLE vault_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE vault_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1 || oldVersion > newVersion) {
      throw StateError('Versão do banco de dados inválida.');
    }
    for (var current = oldVersion; current < newVersion; current++) {
      switch (current) {
        case 1:
          // Version 1 and 2 have the same tables. Validating inside sqflite's
          // upgrade transaction makes a partial or foreign database fail
          // closed without deleting the existing file.
          await _validateSchema(database);
        default:
          throw StateError(
            'Não existe migração segura da versão $current para $newVersion.',
          );
      }
    }
  }

  static Future<void> _validateSchema(Database database) async {
    for (final table in ['vault_metadata', 'vault_state']) {
      final columns = await database.rawQuery('PRAGMA table_info($table)');
      final names = columns
          .map((column) => column['name'])
          .whereType<String>()
          .toSet();
      if (!names.contains('id') || !names.contains('value')) {
        throw StateError('Estrutura do cofre inválida.');
      }
    }
  }
}
