import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'master_password_policy.dart';

const _vaultSaltBytes = 16;
const _vaultKeyBytes = 32;
const _gcmNonceBytes = 12;
const _gcmMacBytes = 16;
const _maxEncryptedPayloadBytes = 5 * 1024 * 1024;

List<int> _decodeBase64Field(
  Object? value,
  String field, {
  required int maxBytes,
  int? exactBytes,
}) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Campo criptográfico inválido: $field.');
  }
  final maxEncodedLength = ((maxBytes + 2) * 4 ~/ 3) + 4;
  if (value.length > maxEncodedLength) {
    throw FormatException('Campo criptográfico inválido: $field.');
  }
  late final List<int> decoded;
  try {
    decoded = base64Decode(value);
  } on Object {
    throw FormatException('Campo criptográfico inválido: $field.');
  }
  if (decoded.length > maxBytes ||
      (exactBytes != null && decoded.length != exactBytes)) {
    throw FormatException('Campo criptográfico inválido: $field.');
  }
  return decoded;
}

class VaultUnlockException implements Exception {
  const VaultUnlockException();

  @override
  String toString() => 'A senha mestra não pôde desbloquear o cofre.';
}

class VaultStorageException implements Exception {
  const VaultStorageException([
    this.message = 'O armazenamento local do cofre precisa ser recuperado.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class VaultMetadata {
  const VaultMetadata({
    required this.formatVersion,
    required this.salt,
    required this.wrappedKey,
    this.recoveryIdentity = '',
  });

  final int formatVersion;
  final List<int> salt;
  final SecretBox wrappedKey;
  final String recoveryIdentity;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'salt': base64Encode(salt),
    'wrappedKey': {
      'nonce': base64Encode(wrappedKey.nonce),
      'cipherText': base64Encode(wrappedKey.cipherText),
      'mac': base64Encode(wrappedKey.mac.bytes),
    },
    if (recoveryIdentity.isNotEmpty) 'recoveryIdentity': recoveryIdentity,
  };

  factory VaultMetadata.fromJson(Map<String, Object?> json) {
    try {
      if (json['formatVersion'] != VaultCrypto.formatVersion) {
        throw const FormatException('Versão do cofre não suportada.');
      }
      final rawWrappedKey = json['wrappedKey'];
      if (rawWrappedKey is! Map) {
        throw const FormatException('Metadados do cofre inválidos.');
      }
      final wrappedKey = Map<String, Object?>.from(rawWrappedKey);
      final recoveryIdentity = json['recoveryIdentity'];
      if (recoveryIdentity != null &&
          (recoveryIdentity is! String ||
              (recoveryIdentity.isNotEmpty &&
                  !RegExp(
                    r'^[A-Za-z0-9_-]{43}=?$',
                  ).hasMatch(recoveryIdentity)))) {
        throw const FormatException('Identidade do cofre inválida.');
      }
      return VaultMetadata(
        formatVersion: VaultCrypto.formatVersion,
        salt: _decodeBase64Field(
          json['salt'],
          'salt',
          maxBytes: _vaultSaltBytes,
          exactBytes: _vaultSaltBytes,
        ),
        wrappedKey: SecretBox(
          _decodeBase64Field(
            wrappedKey['cipherText'],
            'wrappedKey.cipherText',
            maxBytes: _vaultKeyBytes,
            exactBytes: _vaultKeyBytes,
          ),
          nonce: _decodeBase64Field(
            wrappedKey['nonce'],
            'wrappedKey.nonce',
            maxBytes: _gcmNonceBytes,
            exactBytes: _gcmNonceBytes,
          ),
          mac: Mac(
            _decodeBase64Field(
              wrappedKey['mac'],
              'wrappedKey.mac',
              maxBytes: _gcmMacBytes,
              exactBytes: _gcmMacBytes,
            ),
          ),
        ),
        recoveryIdentity: recoveryIdentity as String? ?? '',
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Metadados do cofre inválidos.');
    }
  }
}

class EncryptedVaultPayload {
  const EncryptedVaultPayload(this.box);

  final SecretBox box;

  Map<String, Object?> toJson() => {
    'nonce': base64Encode(box.nonce),
    'cipherText': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };

  factory EncryptedVaultPayload.fromJson(Map<String, Object?> json) {
    try {
      return EncryptedVaultPayload(
        SecretBox(
          _decodeBase64Field(
            json['cipherText'],
            'cipherText',
            maxBytes: _maxEncryptedPayloadBytes,
          ),
          nonce: _decodeBase64Field(
            json['nonce'],
            'nonce',
            maxBytes: _gcmNonceBytes,
            exactBytes: _gcmNonceBytes,
          ),
          mac: Mac(
            _decodeBase64Field(
              json['mac'],
              'mac',
              maxBytes: _gcmMacBytes,
              exactBytes: _gcmMacBytes,
            ),
          ),
        ),
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Payload cifrado inválido.');
    }
  }
}

class VaultCrypto {
  VaultCrypto({Cryptography? cryptography})
    : _cryptography = cryptography ?? Cryptography.instance;

  static const formatVersion = 1;
  static const _memory = 64 * 1024;
  static const _iterations = 3;
  static const _parallelism = 2;
  static const _keyLength = 32;

  final Cryptography _cryptography;

  Cipher get _cipher => _cryptography.aesGcm(secretKeyLength: _keyLength);

  KdfAlgorithm get _kdf => Argon2id(
    memory: _memory,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: _keyLength,
  );

  Future<VaultCreationResult> create(
    String masterPassword, {
    SecretKey? vaultKey,
  }) async {
    _validatePassword(masterPassword);
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final wrappingKey = await _deriveKey(masterPassword, salt);
    vaultKey ??= await _cipher.newSecretKey();
    final vaultKeyBytes = List<int>.from(await vaultKey.extractBytes());
    try {
      final wrappedKey = await _cipher.encrypt(
        vaultKeyBytes,
        secretKey: wrappingKey,
      );
      return VaultCreationResult(
        metadata: VaultMetadata(
          formatVersion: formatVersion,
          salt: salt,
          wrappedKey: wrappedKey,
        ),
        vaultKey: vaultKey,
      );
    } finally {
      vaultKeyBytes.fillRange(0, vaultKeyBytes.length, 0);
      wrappingKey.destroy();
    }
  }

  Future<SecretKey> unlock(
    String masterPassword,
    VaultMetadata metadata,
  ) async {
    if (masterPassword.isEmpty) {
      throw const VaultUnlockException();
    }
    SecretKey? wrappingKey;
    List<int>? vaultKeyBytes;
    try {
      wrappingKey = await _deriveKey(masterPassword, metadata.salt);
      vaultKeyBytes = List<int>.from(
        await _cipher.decrypt(metadata.wrappedKey, secretKey: wrappingKey),
      );
      return SecretKeyData(
        Uint8List.fromList(vaultKeyBytes),
        overwriteWhenDestroyed: true,
      );
    } on Object {
      throw const VaultUnlockException();
    } finally {
      // SecretKeyData owns a separate copy with deterministic destruction.
      vaultKeyBytes?.fillRange(0, vaultKeyBytes.length, 0);
      wrappingKey?.destroy();
    }
  }

  Future<EncryptedVaultPayload> encryptSnapshot(
    String encodedSnapshot,
    SecretKey vaultKey,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(encodedSnapshot),
      secretKey: vaultKey,
      aad: utf8.encode('passdrive-vault-$formatVersion'),
    );
    return EncryptedVaultPayload(box);
  }

  Future<String> decryptSnapshot(
    EncryptedVaultPayload payload,
    SecretKey vaultKey,
  ) async {
    try {
      final clearText = List<int>.from(
        await _cipher.decrypt(
          payload.box,
          secretKey: vaultKey,
          aad: utf8.encode('passdrive-vault-$formatVersion'),
        ),
      );
      try {
        return utf8.decode(clearText);
      } finally {
        clearText.fillRange(0, clearText.length, 0);
      }
    } on Object {
      throw const VaultUnlockException();
    }
  }

  Future<VaultMetadata> rewrapVaultKey(
    String newMasterPassword,
    VaultMetadata metadata,
    SecretKey vaultKey,
  ) async {
    _validatePassword(newMasterPassword);
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final wrappingKey = await _deriveKey(newMasterPassword, salt);
    final keyBytes = List<int>.from(await vaultKey.extractBytes());
    try {
      final wrappedKey = await _cipher.encrypt(
        keyBytes,
        secretKey: wrappingKey,
      );
      return VaultMetadata(
        formatVersion: metadata.formatVersion,
        salt: salt,
        wrappedKey: wrappedKey,
        recoveryIdentity: metadata.recoveryIdentity.isNotEmpty
            ? metadata.recoveryIdentity
            : await vaultMetadataIdentity(metadata),
      );
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
      wrappingKey.destroy();
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  void _validatePassword(String password) {
    MasterPasswordPolicy.validate(password);
  }
}

Future<String> vaultMetadataIdentity(VaultMetadata metadata) async {
  if (metadata.recoveryIdentity.isNotEmpty) {
    return metadata.recoveryIdentity;
  }
  return base64UrlEncode(
    (await Sha256().hash([
      ...metadata.salt,
      ...metadata.wrappedKey.cipherText,
      ...metadata.wrappedKey.mac.bytes,
    ])).bytes,
  );
}

class VaultCreationResult {
  const VaultCreationResult({required this.metadata, required this.vaultKey});

  final VaultMetadata metadata;
  final SecretKey vaultKey;
}
