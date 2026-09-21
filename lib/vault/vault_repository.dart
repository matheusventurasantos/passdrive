import '../settings/app_strings.dart';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'vault_crypto.dart';
import 'vault_database.dart';
import 'vault_models.dart';
import 'vault_access.dart';
import 'master_password_policy.dart';

class VaultNotInitializedException implements Exception {
  const VaultNotInitializedException();

  @override
  String toString() => tr('O cofre ainda não foi criado.');
}

class VaultRepository {
  VaultRepository._(
    Database database,
    VaultCrypto crypto,
    VaultMetadata metadata,
    SecretKey vaultKey,
    VaultSnapshot snapshot,
  ) : _database = database,
      _crypto = crypto,
      _metadata = metadata,
      _vaultKey = vaultKey,
      _snapshot = snapshot;

  @visibleForTesting
  VaultRepository.forTesting({
    required Database database,
    required VaultCrypto crypto,
    required VaultMetadata metadata,
    required SecretKey vaultKey,
    required VaultSnapshot snapshot,
  }) : this._(database, crypto, metadata, vaultKey, snapshot);

  final Database _database;
  final VaultCrypto _crypto;
  VaultMetadata _metadata;
  SecretKey? _vaultKey;
  VaultSnapshot _snapshot;
  final VaultWriteQueue _writes = VaultWriteQueue();
  Future<void>? _closeFuture;
  final changes = VaultChanges();
  Future<void> Function()? beforeClose;
  Future<void> flush() => _writes.drain();

  VaultSnapshot get snapshot => _snapshot;
  List<VaultAccount> get accounts => _snapshot.accounts;
  List<VaultService> get services => _snapshot.services;
  VaultAutoLock get autoLock => _snapshot.autoLock;
  VaultClipboardClear get clipboardClear => _snapshot.clipboardClear;
  bool get allowScreenCapture => _snapshot.allowScreenCapture;
  Map<String, VaultBreachCheck> get breachChecks => _snapshot.breachChecks;

  Future<void> setAutoLock(VaultAutoLock value) {
    if (_closeFuture != null) {
      return Future.error(StateError(tr('Cofre bloqueado.')));
    }
    return _writes.enqueue(
      () => _replaceSnapshot(_snapshot.copyWith(autoLock: value)),
    );
  }

  Future<void> setClipboardClear(VaultClipboardClear value) {
    if (_closeFuture != null) {
      return Future.error(StateError(tr('Cofre bloqueado.')));
    }
    return _writes.enqueue(
      () => _replaceSnapshot(_snapshot.copyWith(clipboardClear: value)),
    );
  }

  Future<void> setAllowScreenCapture(bool value) {
    if (_closeFuture != null) {
      return Future.error(StateError(tr('Cofre bloqueado.')));
    }
    return _writes.enqueue(
      () => _replaceSnapshot(_snapshot.copyWith(allowScreenCapture: value)),
    );
  }

  Future<void> setBreachChecks(Map<String, VaultBreachCheck> values) {
    if (_closeFuture != null) {
      return Future.error(StateError(tr('Cofre bloqueado.')));
    }
    final serviceIds = _snapshot.services.map((service) => service.id).toSet();
    final filtered = Map<String, VaultBreachCheck>.unmodifiable({
      for (final entry in values.entries)
        if (serviceIds.contains(entry.key)) entry.key: entry.value,
    });
    return _writes.enqueue(
      () => _replaceSnapshot(_snapshot.copyWith(breachChecks: filtered)),
    );
  }

  Future<bool> verifyMasterPassword(String password) async {
    if (_closeFuture != null || password.isEmpty) return false;
    try {
      final candidate = await _crypto.unlock(password, _metadata);
      return await _sameSecretKey(candidate);
    } on Object {
      return false;
    }
  }

  Future<bool> verifyRecoveryKey(Uint8List bytes) async {
    if (_closeFuture != null) return false;
    try {
      final candidate = await RecoveryKeyFile.decode(bytes, _metadata);
      return await _sameSecretKey(candidate);
    } on Object {
      return false;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<bool> verifyBiometrics() async {
    if (_closeFuture != null) return false;
    final candidate = await VaultAccess.authenticate();
    return _sameSecretKey(candidate);
  }

  SecretKey _requireVaultKey() {
    final key = _vaultKey;
    if (key == null || key.isDestroyed) {
      throw StateError(tr('Cofre bloqueado.'));
    }
    return key;
  }

  Future<bool> _sameSecretKey(SecretKey candidate) async {
    final expectedBytes = List<int>.from(
      await _requireVaultKey().extractBytes(),
    );
    final candidateBytes = List<int>.from(await candidate.extractBytes());
    try {
      return _sameBytes(expectedBytes, candidateBytes);
    } finally {
      expectedBytes.fillRange(0, expectedBytes.length, 0);
      candidateBytes.fillRange(0, candidateBytes.length, 0);
      candidate.destroy();
    }
  }

  Future<bool> enableBiometrics() => VaultAccess.enable(_requireVaultKey());

  Future<void> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    MasterPasswordPolicy.validateChange(
      newPassword: newPassword,
      confirmation: confirmation,
    );
    if (_closeFuture != null) {
      throw StateError(tr('Cofre bloqueado.'));
    }

    final verifiedKey = await _crypto.unlock(currentPassword, _metadata);
    final vaultKey = _requireVaultKey();
    final expectedBytes = List<int>.from(await vaultKey.extractBytes());
    final verifiedBytes = List<int>.from(await verifiedKey.extractBytes());
    try {
      if (!_sameBytes(expectedBytes, verifiedBytes)) {
        throw const VaultUnlockException();
      }
    } finally {
      expectedBytes.fillRange(0, expectedBytes.length, 0);
      verifiedBytes.fillRange(0, verifiedBytes.length, 0);
      verifiedKey.destroy();
    }

    // Only the wrapper around the existing vault key changes. The encrypted
    // snapshot is deliberately not read or rewritten in this operation.
    final nextMetadata = await _crypto.rewrapVaultKey(
      newPassword,
      _metadata,
      vaultKey,
    );
    await _writes.enqueue(() async {
      if (_closeFuture != null) throw StateError(tr('Cofre bloqueado.'));
      await _database.transaction((transaction) async {
        final changed = await transaction.update('vault_metadata', {
          'value': jsonEncode(nextMetadata.toJson()),
        }, where: 'id = 1');
        if (changed != 1) {
          throw VaultStorageException(
            tr('Não foi possível salvar a nova senha com segurança.'),
          );
        }
      });
      _metadata = nextMetadata;
    });
  }

  Future<bool> downloadRecoveryKey() async {
    final bytes = await RecoveryKeyFile.encode(_metadata, _requireVaultKey());
    try {
      return await VaultAccess.save(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<bool> exportBackup() async {
    if (_closeFuture != null) throw StateError(tr('Cofre bloqueado.'));
    await _writes.drain();
    final state = await _database.query('vault_state', limit: 1);
    if (state.length != 1) throw const VaultStorageException();
    final payload = EncryptedVaultPayload.fromJson(
      Map<String, Object?>.from(
        jsonDecode(state.single['value']! as String) as Map,
      ),
    );
    final bytes = await VaultBackupFile.encode(_metadata, payload);
    try {
      return await VaultAccess.save(bytes, filename: 'passdrive-backup.pdbak');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> restoreBackup(Uint8List bytes) async {
    if (_closeFuture != null) throw StateError(tr('Cofre bloqueado.'));
    try {
      final payload = await VaultBackupFile.decode(bytes, _metadata);
      final decoded = await _crypto.decryptSnapshot(
        payload,
        _requireVaultKey(),
      );
      final snapshot = VaultSnapshot.decode(decoded);
      await _writes.enqueue(() async {
        if (_closeFuture != null) throw StateError(tr('Cofre bloqueado.'));
        await _database.transaction((transaction) async {
          final changed = await transaction.update('vault_state', {
            'value': jsonEncode(payload.toJson()),
          }, where: 'id = 1');
          if (changed != 1) throw const VaultStorageException();
        });
        _snapshot = snapshot;
      });
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<VaultRepository> openWithFile(Uint8List bytes) =>
      _openWithKey((metadata) => RecoveryKeyFile.decode(bytes, metadata));

  static Future<VaultRepository> openWithBiometrics() =>
      _openWithKey((_) => VaultAccess.authenticate());

  static Future<VaultRepository> _openWithKey(
    Future<SecretKey> Function(VaultMetadata) resolve,
  ) async {
    final database = await VaultDatabase.open();
    try {
      final rows = await database.query('vault_metadata', limit: 1);
      if (rows.isEmpty) throw const VaultNotInitializedException();
      final metadata = VaultMetadata.fromJson(
        Map<String, Object?>.from(
          jsonDecode(rows.single['value']! as String) as Map,
        ),
      );
      final key = await resolve(metadata);
      final state = await database.query('vault_state', limit: 1);
      final payload = EncryptedVaultPayload.fromJson(
        Map<String, Object?>.from(
          jsonDecode(state.single['value']! as String) as Map,
        ),
      );
      final crypto = VaultCrypto();
      final snapshot = VaultSnapshot.decode(
        await crypto.decryptSnapshot(payload, key),
      );
      return VaultRepository._(database, crypto, metadata, key, snapshot);
    } on VaultUnlockException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultNotInitializedException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultStorageException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultSnapshotFormatException catch (error) {
      await _closeDatabaseQuietly(database);
      throw VaultStorageException(error.message);
    } on FormatException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on PlatformException {
      // A biometric cancellation or temporary platform error is not evidence
      // of a damaged vault. Preserve it so the gate can show the right action.
      await _closeDatabaseQuietly(database);
      rethrow;
    } on Object {
      await _closeDatabaseQuietly(database);
      throw const VaultStorageException();
    }
  }

  static Future<bool> isInitialized() async {
    final database = await VaultDatabase.open();
    try {
      final metadata = await database.query('vault_metadata', limit: 1);
      return metadata.isNotEmpty;
    } finally {
      await _closeDatabaseQuietly(database);
    }
  }

  static Future<VaultRepository> create({
    required String masterPassword,
    SecretKey? vaultKey,
    VaultCrypto? crypto,
  }) async {
    final database = await VaultDatabase.open();
    try {
      final existing = await database.query('vault_metadata', limit: 1);
      if (existing.isNotEmpty) {
        throw StateError(tr('O cofre já foi criado.'));
      }

      final vaultCrypto = crypto ?? VaultCrypto();
      final created = await vaultCrypto.create(
        masterPassword,
        vaultKey: vaultKey,
      );
      final repository = VaultRepository._(
        database,
        vaultCrypto,
        created.metadata,
        created.vaultKey,
        const VaultSnapshot(accounts: [], services: []),
      );
      await repository._writeInitialState();
      return repository;
    } catch (error, stack) {
      await _closeDatabaseQuietly(database);
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<VaultRepository> open({
    required String masterPassword,
    VaultCrypto? crypto,
  }) async {
    final database = await VaultDatabase.open();
    try {
      final metadataRows = await database.query('vault_metadata', limit: 1);
      if (metadataRows.isEmpty) {
        throw const VaultNotInitializedException();
      }

      final vaultCrypto = crypto ?? VaultCrypto();
      final metadata = VaultMetadata.fromJson(
        Map<String, Object?>.from(
          jsonDecode(metadataRows.single['value']! as String) as Map,
        ),
      );
      final vaultKey = await vaultCrypto.unlock(masterPassword, metadata);
      final stateRows = await database.query('vault_state', limit: 1);
      final encrypted = EncryptedVaultPayload.fromJson(
        Map<String, Object?>.from(
          jsonDecode(stateRows.single['value']! as String) as Map,
        ),
      );
      final snapshotJson = await vaultCrypto
          .decryptSnapshot(encrypted, vaultKey)
          .catchError((error) {
            if (error is VaultUnlockException) {
              throw VaultStorageException(
                tr(
                  'O conteúdo do cofre não pôde ser validado. Nenhum dado foi alterado.',
                ),
              );
            }
            throw error;
          });
      final snapshot = VaultSnapshot.decode(snapshotJson);

      return VaultRepository._(
        database,
        vaultCrypto,
        metadata,
        vaultKey,
        snapshot,
      );
    } on VaultUnlockException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultNotInitializedException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultStorageException {
      await _closeDatabaseQuietly(database);
      rethrow;
    } on VaultSnapshotFormatException catch (error) {
      await _closeDatabaseQuietly(database);
      throw VaultStorageException(error.message);
    } on Object {
      await _closeDatabaseQuietly(database);
      throw const VaultStorageException();
    }
  }

  Future<void> replaceSnapshot(VaultSnapshot snapshot) {
    if (_closeFuture != null) {
      return Future.error(StateError(tr('Cofre bloqueado.')));
    }
    return _writes.enqueue(() => _replaceSnapshot(snapshot));
  }

  Future<void> _replaceSnapshot(VaultSnapshot snapshot) async {
    final serviceIds = snapshot.services.map((service) => service.id).toSet();
    final normalized = snapshot.copyWith(
      breachChecks: Map<String, VaultBreachCheck>.unmodifiable({
        for (final entry in snapshot.breachChecks.entries)
          if (serviceIds.contains(entry.key)) entry.key: entry.value,
      }),
    );
    final encrypted = await _crypto.encryptSnapshot(
      normalized.encode(),
      _requireVaultKey(),
    );
    final encoded = jsonEncode(encrypted.toJson());
    await _database.transaction((transaction) async {
      final changed = await transaction.update('vault_state', {
        'value': encoded,
      }, where: 'id = 1');
      if (changed != 1) {
        throw VaultStorageException(
          tr('Não foi possível salvar o estado completo do cofre.'),
        );
      }
    });
    _snapshot = normalized;
    changes.changed();
  }

  Future<void> close() => _closeFuture ??= _closeSafely();

  Future<void> _closeSafely() async {
    Object? failure;
    StackTrace? failureStack;

    try {
      await _writes.drain();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }

    try {
      await beforeClose?.call();
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }

    try {
      await _database.close();
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    } finally {
      _snapshot = const VaultSnapshot(accounts: [], services: []);
      final vaultKey = _vaultKey;
      _vaultKey = null;
      // SecretKeyData destroys its backing bytes when configured with
      // overwriteWhenDestroyed. Other implementations still become
      // unusable through SecretKey.destroy().
      vaultKey?.destroy();
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }

  static Future<void> _closeDatabaseQuietly(Database database) async {
    try {
      await database.close();
    } on Object {
      // Preserve the original open/create error when cleanup itself fails.
    }
  }

  Future<void> _writeInitialState() async {
    final encrypted = await _crypto.encryptSnapshot(
      _snapshot.encode(),
      _requireVaultKey(),
    );
    await _database.transaction((transaction) async {
      await transaction.insert('vault_metadata', {
        'id': 1,
        'value': jsonEncode(_metadata.toJson()),
      });
      await transaction.insert('vault_state', {
        'id': 1,
        'value': jsonEncode(encrypted.toJson()),
      });
    });
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var result = 0;
    for (var index = 0; index < left.length; index++) {
      result |= left[index] ^ right[index];
    }
    return result == 0;
  }
}

class VaultChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

class VaultWriteQueue {
  Future<void> _tail = Future.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> drain() => _tail;
}
