import 'dart:convert';
import '../settings/app_strings.dart';

enum VaultItemType { account, service }

class VaultSnapshotFormatException implements Exception {
  const VaultSnapshotFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VaultSnapshotUnsupportedVersionException
    extends VaultSnapshotFormatException {
  const VaultSnapshotUnsupportedVersionException(int version)
    : super('Esta versão do cofre ($version) é mais recente que o app.');
}

enum VaultAutoLock {
  immediately(0, 'Imediatamente'),
  oneMinute(60, 'Após 1 minuto'),
  fiveMinutes(300, 'Após 5 minutos'),
  fifteenMinutes(900, 'Após 15 minutos'),
  never(null, 'Nunca');

  const VaultAutoLock(this.seconds, this.label);
  final int? seconds;
  final String label;

  static VaultAutoLock fromJson(Object? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => VaultAutoLock.immediately,
  );
}

enum VaultClipboardClear {
  thirtySeconds(30, 'Após 30 segundos'),
  oneMinute(60, 'Após 1 minuto'),
  fiveMinutes(300, 'Após 5 minutos'),
  never(null, 'Nunca');

  const VaultClipboardClear(this.seconds, this.label);
  final int? seconds;
  final String label;

  Duration? get duration =>
      seconds == null ? null : Duration(seconds: seconds!);

  static VaultClipboardClear fromJson(Object? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => VaultClipboardClear.oneMinute,
  );
}

/// Minimal persisted result of a breach check. It deliberately never stores a
/// password, its SHA-1 digest, or the response received from the service.
class VaultBreachCheck {
  const VaultBreachCheck({
    required this.compromised,
    required this.checkedAt,
    required this.serviceUpdatedAt,
  });

  final bool compromised;
  final DateTime checkedAt;
  final DateTime serviceUpdatedAt;

  Map<String, Object?> toJson() => {
    'compromised': compromised,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'serviceUpdatedAt': serviceUpdatedAt.toUtc().toIso8601String(),
  };

  factory VaultBreachCheck.fromJson(Map<String, Object?> json) =>
      VaultBreachCheck(
        compromised: _optionalBool(json, 'compromised'),
        checkedAt: _requiredDate(json, 'checkedAt'),
        serviceUpdatedAt: _requiredDate(json, 'serviceUpdatedAt'),
      );
}

class VaultAccount {
  const VaultAccount({
    required this.id,
    required this.email,
    required this.provider,
    this.label = '',
    this.note = '',
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String provider;
  final String label;
  final String note;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultAccount copyWith({
    String? email,
    String? provider,
    String? label,
    String? note,
    bool? favorite,
    DateTime? updatedAt,
  }) {
    return VaultAccount(
      id: id,
      email: email ?? this.email,
      provider: provider ?? this.provider,
      label: label ?? this.label,
      note: note ?? this.note,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'provider': provider,
    'label': label,
    'note': note,
    'favorite': favorite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory VaultAccount.fromJson(Map<String, Object?> json) {
    return VaultAccount(
      id: _requiredString(json, 'id', maxLength: 160),
      // O formulário exige um email válido. Ao abrir, porém, aceitamos o
      // valor legado como texto para que um cofre criado por uma versão
      // anterior nunca fique inacessível por causa dessa validação.
      email: _requiredString(json, 'email', maxLength: 320),
      provider: _requiredString(json, 'provider', maxLength: 100),
      label: _optionalString(json, 'label', maxLength: 160),
      note: _optionalString(json, 'note', maxLength: 1000),
      favorite: _optionalBool(json, 'favorite'),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
    );
  }
}

class VaultService {
  const VaultService({
    required this.id,
    required this.name,
    required this.email,
    required this.url,
    required this.username,
    required this.password,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    this.brand = '',
  });

  final String id;
  final String name;
  final String email;
  final String url;
  final String username;
  final String password;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String brand;

  VaultService copyWith({
    String? name,
    String? email,
    String? url,
    String? username,
    String? password,
    bool? favorite,
    String? brand,
    DateTime? updatedAt,
  }) {
    return VaultService(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      brand: brand ?? this.brand,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'url': url,
    'username': username,
    'password': password,
    'favorite': favorite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'brand': brand,
  };

  factory VaultService.fromJson(Map<String, Object?> json) {
    return VaultService(
      id: _requiredString(json, 'id', maxLength: 160),
      name: _requiredString(json, 'name', maxLength: 200),
      email: _optionalString(json, 'email', maxLength: 320),
      url: _optionalUrl(json, 'url'),
      username: _optionalString(json, 'username', maxLength: 320),
      password: _requiredString(json, 'password', maxLength: 4096),
      favorite: _optionalBool(json, 'favorite'),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
      brand: _optionalString(json, 'brand', maxLength: 100),
    );
  }
}

class VaultSnapshot {
  static const formatVersion = 5;

  const VaultSnapshot({
    required this.accounts,
    required this.services,
    this.autoLock = VaultAutoLock.immediately,
    this.clipboardClear = VaultClipboardClear.oneMinute,
    this.allowScreenCapture = false,
    this.breachChecks = const {},
  });

  final List<VaultAccount> accounts;
  final List<VaultService> services;
  final VaultAutoLock autoLock;
  final VaultClipboardClear clipboardClear;
  final bool allowScreenCapture;
  final Map<String, VaultBreachCheck> breachChecks;

  VaultSnapshot copyWith({
    List<VaultAccount>? accounts,
    List<VaultService>? services,
    VaultAutoLock? autoLock,
    VaultClipboardClear? clipboardClear,
    bool? allowScreenCapture,
    Map<String, VaultBreachCheck>? breachChecks,
  }) => VaultSnapshot(
    accounts: accounts ?? this.accounts,
    services: services ?? this.services,
    autoLock: autoLock ?? this.autoLock,
    clipboardClear: clipboardClear ?? this.clipboardClear,
    allowScreenCapture: allowScreenCapture ?? this.allowScreenCapture,
    breachChecks: breachChecks ?? this.breachChecks,
  );

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'services': services.map((item) => item.toJson()).toList(),
    'autoLock': autoLock.name,
    'clipboardClear': clipboardClear.name,
    'allowScreenCapture': allowScreenCapture,
    'breachChecks': {
      for (final entry in breachChecks.entries) entry.key: entry.value.toJson(),
    },
  };

  factory VaultSnapshot.fromJson(Map<String, Object?> json) {
    try {
      final migrated = migrateJson(json);
      final encodedVersion = migrated['formatVersion'];
      if (encodedVersion is! int || encodedVersion < 1) {
        throw const VaultSnapshotFormatException(
          'A versão do cofre é inválida.',
        );
      }
      if (encodedVersion > formatVersion) {
        throw VaultSnapshotUnsupportedVersionException(encodedVersion);
      }

      final rawAccounts = migrated['accounts'] ?? const <Object>[];
      final rawServices = migrated['services'] ?? const <Object>[];
      if (rawAccounts is! List || rawServices is! List) {
        throw const VaultSnapshotFormatException(
          'A estrutura do cofre é inválida.',
        );
      }
      final accounts = rawAccounts
          .map(
            (item) =>
                VaultAccount.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false);
      final services = rawServices
          .map(
            (item) =>
                VaultService.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false);
      _validateIds(accounts, services);
      final breachChecks = _readBreachChecks(migrated['breachChecks']);
      if (breachChecks.keys.any(
        (id) => !services.any((service) => service.id == id),
      )) {
        throw const VaultSnapshotFormatException(
          'A verificação de segurança do cofre é inválida.',
        );
      }
      return VaultSnapshot(
        accounts: accounts,
        services: services,
        autoLock: VaultAutoLock.fromJson(migrated['autoLock']),
        clipboardClear: VaultClipboardClear.fromJson(
          migrated['clipboardClear'],
        ),
        allowScreenCapture: migrated['allowScreenCapture'] == true,
        breachChecks: breachChecks,
      );
    } on VaultSnapshotFormatException {
      rethrow;
    } on Object {
      throw const VaultSnapshotFormatException(
        'Os dados do cofre estão em um formato inválido.',
      );
    }
  }

  String encode() => jsonEncode(toJson());

  factory VaultSnapshot.decode(String value) {
    try {
      return VaultSnapshot.fromJson(
        Map<String, Object?>.from(jsonDecode(value) as Map),
      );
    } on VaultSnapshotFormatException {
      rethrow;
    } on Object {
      throw const VaultSnapshotFormatException(
        'Os dados do cofre não puderam ser lidos.',
      );
    }
  }

  static Map<String, Object?> migrateJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version != null && version is! int) {
      throw VaultSnapshotFormatException(tr('A versão do cofre é inválida.'));
    }
    if (version is int && version > formatVersion) {
      throw VaultSnapshotUnsupportedVersionException(version);
    }
    if (version is int && version < 1) {
      throw VaultSnapshotFormatException(tr('A versão do cofre é inválida.'));
    }

    var currentVersion = version is int ? version : 1;
    final migrated = Map<String, Object?>.from(json);
    while (currentVersion < formatVersion) {
      if (currentVersion == 1) {
        migrated['autoLock'] ??= VaultAutoLock.immediately.name;
        currentVersion = 2;
      } else if (currentVersion == 2) {
        migrated['clipboardClear'] ??= VaultClipboardClear.oneMinute.name;
        currentVersion = 3;
      } else if (currentVersion == 3) {
        migrated['allowScreenCapture'] ??= false;
        currentVersion = 4;
      } else if (currentVersion == 4) {
        migrated['breachChecks'] ??= <String, Object?>{};
        currentVersion = 5;
      } else {
        throw VaultSnapshotFormatException(tr('A versão do cofre é inválida.'));
      }
    }
    migrated['formatVersion'] = currentVersion;
    return migrated;
  }

  static void _validateIds(
    List<VaultAccount> accounts,
    List<VaultService> services,
  ) {
    final ids = <String>{};
    for (final account in accounts) {
      if (account.id.trim().isEmpty || !ids.add(account.id)) {
        throw VaultSnapshotFormatException(
          tr('O cofre possui identificadores inválidos ou duplicados.'),
        );
      }
    }
    for (final service in services) {
      if (service.id.trim().isEmpty || !ids.add(service.id)) {
        throw VaultSnapshotFormatException(
          tr('O cofre possui identificadores inválidos ou duplicados.'),
        );
      }
    }
  }

  static Map<String, VaultBreachCheck> _readBreachChecks(Object? value) {
    if (value == null) return const {};
    if (value is! Map || value.length > 10000) {
      throw VaultSnapshotFormatException(
        tr('A verificação de segurança do cofre é inválida.'),
      );
    }
    final checks = <String, VaultBreachCheck>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).length > 160 ||
          entry.value is! Map) {
        throw VaultSnapshotFormatException(
          tr('A verificação de segurança do cofre é inválida.'),
        );
      }
      checks[entry.key as String] = VaultBreachCheck.fromJson(
        Map<String, Object?>.from(entry.value as Map),
      );
    }
    return Map.unmodifiable(checks);
  }
}

String _requiredString(
  Map<String, Object?> json,
  String field, {
  required int maxLength,
}) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw VaultSnapshotFormatException('O campo "$field" do cofre é inválido.');
  }
  return value;
}

String _optionalString(
  Map<String, Object?> json,
  String field, {
  required int maxLength,
}) {
  final value = json[field];
  if (value == null) return '';
  if (value is! String || value.length > maxLength) {
    throw VaultSnapshotFormatException('O campo "$field" do cofre é inválido.');
  }
  return value;
}

bool _optionalBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return false;
  if (value is! bool) {
    throw VaultSnapshotFormatException('O campo "$field" do cofre é inválido.');
  }
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw VaultSnapshotFormatException('A data "$field" do cofre é inválida.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw VaultSnapshotFormatException('A data "$field" do cofre é inválida.');
  }
  return parsed.toUtc();
}

String _optionalUrl(Map<String, Object?> json, String field) {
  final value = _optionalString(json, field, maxLength: 2048);
  if (value.isEmpty) return value;
  final candidate = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(candidate);
  if (value.contains(RegExp(r'\s')) ||
      uri == null ||
      uri.host.isEmpty ||
      uri.host.contains(' ')) {
    throw VaultSnapshotFormatException(tr('A URL do cofre é inválida.'));
  }
  return value;
}
