import '../settings/app_strings.dart';
import '../settings/appearance_preferences.dart';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:cryptography/cryptography.dart';

import 'vault_crypto.dart';

/// A bearer credential, not a backup: possession grants access to this vault.
class RecoveryKeyFile {
  static Future<String> identity(VaultMetadata metadata) async =>
      vaultMetadataIdentity(metadata);

  static Future<Uint8List> encode(VaultMetadata metadata, SecretKey key) async {
    final keyBytes = List<int>.from(await key.extractBytes());
    try {
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'passdrive-recovery',
            'version': 1,
            'vault': await identity(metadata),
            'key': base64Encode(keyBytes),
          }),
        ),
      );
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  static Future<SecretKey> decode(
    Uint8List bytes,
    VaultMetadata metadata,
  ) async {
    if (bytes.isEmpty || bytes.length > 16384) throw const FormatException();
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value['format'] != 'passdrive-recovery' ||
          value['version'] != 1 ||
          value['vault'] != await identity(metadata) ||
          value['key'] is! String) {
        throw const FormatException();
      }
      final key = base64Decode(value['key'] as String);
      if (key.length != 32) throw const FormatException();
      try {
        return SecretKeyData(
          Uint8List.fromList(key),
          overwriteWhenDestroyed: true,
        );
      } finally {
        key.fillRange(0, key.length, 0);
      }
    } on VaultUnlockException {
      rethrow;
    } on Object {
      throw FormatException(tr('Arquivo de chave-mestra inválido.'));
    }
  }
}

/// A portable copy of the encrypted vault state. It never includes the
/// master password or the unencrypted snapshot.
class VaultBackupFile {
  static const maxBytes = 5 * 1024 * 1024;

  static Future<Uint8List> encode(
    VaultMetadata metadata,
    EncryptedVaultPayload payload,
  ) async => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'passdrive-backup',
        'version': 1,
        'vault': await vaultMetadataIdentity(metadata),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'state': payload.toJson(),
      }),
    ),
  );

  static Future<EncryptedVaultPayload> decode(
    Uint8List bytes,
    VaultMetadata metadata,
  ) async {
    if (bytes.isEmpty || bytes.length > maxBytes) throw const FormatException();
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value['format'] != 'passdrive-backup' ||
          value['version'] != 1 ||
          value['vault'] != await vaultMetadataIdentity(metadata) ||
          value['state'] is! Map) {
        throw const FormatException();
      }
      return EncryptedVaultPayload.fromJson(
        Map<String, Object?>.from(value['state'] as Map),
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException(tr('Backup inválido ou de outro cofre.'));
    }
  }
}

class VaultAccess {
  static const channel = MethodChannel('passdrive/access');
  static bool busy = false;

  static Future<T?> _invoke<T>(
    String method, [
    Map<String, Object>? args,
  ]) async {
    busy = true;
    try {
      return await channel.invokeMethod<T>(method, args);
    } finally {
      busy = false;
    }
  }

  static Future<bool> enabled() async =>
      await channel.invokeMethod<bool>('enabled') ?? false;
  static Future<void> disable() => channel.invokeMethod<void>('disable');
  static Future<void> setScreenCaptureAllowed(bool allowed) => channel
      .invokeMethod<void>('setScreenCaptureAllowed', {'allowed': allowed});
  static Future<bool> enable(SecretKey key) async {
    final bytes = Uint8List.fromList(await key.extractBytes());
    try {
      return await _invoke<bool>('enable', {
            'key': bytes,
            'language': AppearancePreferences.instance.language,
          }) ??
          false;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<SecretKey> authenticate() async {
    final received = await _invoke<Uint8List>('unlock', {
      'language': AppearancePreferences.instance.language,
    });
    return keyFromBiometricBytes(received);
  }

  static SecretKey keyFromBiometricBytes(Uint8List? received) {
    // Platform codec buffers may be read-only. Only wipe our owned copy.
    final bytes = received == null ? null : Uint8List.fromList(received);
    if (bytes == null || bytes.length != 32) {
      bytes?.fillRange(0, bytes.length, 0);
      throw const VaultUnlockException();
    }
    final result = SecretKeyData(
      Uint8List.fromList(bytes),
      overwriteWhenDestroyed: true,
    );
    bytes.fillRange(0, bytes.length, 0);
    return result;
  }

  static Future<bool> save(
    Uint8List bytes, {
    String filename = 'passdrive-chave-mestra.pdkey',
  }) async =>
      await _invoke<bool>('save', {'bytes': bytes, 'filename': filename}) ??
      false;
  static Future<Uint8List?> pick({int maxBytes = 16384}) async {
    final received = await _invoke<Uint8List>('pick', {'maxBytes': maxBytes});
    // A plataforma pode entregar um buffer imutável. A cópia também permite
    // limpar o conteúdo após a tentativa de abertura sem tocar no canal nativo.
    return received == null ? null : Uint8List.fromList(received);
  }
}
