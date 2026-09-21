import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../settings/app_strings.dart';
import 'sync_protocol.dart';

enum ConnectionDuration {
  minutes15(900, '15 minutos'),
  hour(3600, '1 hora'),
  day(86400, '1 dia'),
  week(604800, '7 dias'),
  month(2592000, '30 dias'),
  forever(null, 'Para sempre');

  const ConnectionDuration(this.seconds, this.label);
  final int? seconds;
  final String label;
  DateTime? expiry(DateTime now) =>
      seconds == null ? null : now.add(Duration(seconds: seconds!));
}

class DeviceGrant {
  const DeviceGrant({
    required this.id,
    required this.name,
    required this.secret,
    required this.createdAt,
    required this.lastSeen,
    required this.expiresAt,
    this.trusted = false,
    this.lockOnFocusLoss = true,
  });
  final String id, name, secret;
  final DateTime createdAt, lastSeen;
  final DateTime? expiresAt;

  /// A trusted desktop may resume the encrypted local connection on launch.
  final bool trusted;

  /// Kept per desktop so a user can allow safe multitasking when desired.
  final bool lockOnFocusLoss;
  bool valid([DateTime? now]) =>
      expiresAt == null || (now ?? DateTime.now()).isBefore(expiresAt!);
  DeviceGrant update({
    DateTime? seen,
    ConnectionDuration? duration,
    bool? trusted,
    bool? lockOnFocusLoss,
  }) => DeviceGrant(
    id: id,
    name: name,
    secret: secret,
    createdAt: createdAt,
    lastSeen: seen ?? lastSeen,
    expiresAt: duration == null ? expiresAt : duration.expiry(DateTime.now()),
    trusted: trusted ?? this.trusted,
    lockOnFocusLoss: lockOnFocusLoss ?? this.lockOnFocusLoss,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'secret': secret,
    'created': createdAt.toUtc().toIso8601String(),
    'seen': lastSeen.toUtc().toIso8601String(),
    'expires': expiresAt?.toUtc().toIso8601String(),
    'trusted': trusted,
    'lockOnFocusLoss': lockOnFocusLoss,
  };
  factory DeviceGrant.fromJson(Map<String, dynamic> json) {
    final secret = safeString(json['secret']);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret)) {
      throw const FormatException();
    }
    return DeviceGrant(
      id: safeString(json['id']),
      name: safeString(json['name'], max: 80),
      secret: secret,
      createdAt: DateTime.parse(safeString(json['created'])),
      lastSeen: DateTime.parse(safeString(json['seen'])),
      expiresAt: json['expires'] == null
          ? null
          : DateTime.parse(safeString(json['expires'])),
      trusted: json['trusted'] == true,
      lockOnFocusLoss: json['lockOnFocusLoss'] != false,
    );
  }
}

abstract class SyncStore {
  Future<String?> read();
  Future<void> write(String value);
}

class ProtectedSyncStore implements SyncStore {
  const ProtectedSyncStore(this.role);
  final String role;
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'passdrive.lan.v1.$role');
  @override
  Future<void> write(String value) =>
      storage.write(key: 'passdrive.lan.v1.$role', value: value);
}

class SyncPreferences {
  SyncPreferences(this.store);
  final SyncStore store;
  String id = randomToken(16);
  bool autoQr = false;
  final Map<String, DeviceGrant> devices = {};
  Future<void> _writes = Future.value();
  Future<void> load() async {
    final raw = await store.read();
    if (raw == null) {
      await save();
      return;
    }
    final data = jsonObject(raw);
    if (data['version'] != 1) {
      throw FormatException(tr('Configuração de conexão incompatível.'));
    }
    id = safeString(data['id']);
    autoQr = data['autoQr'] == true;
    for (final value in (data['devices'] as List)) {
      final grant = DeviceGrant.fromJson(
        Map<String, dynamic>.from(value as Map),
      );
      if (grant.valid()) devices[grant.id] = grant;
    }
  }

  Future<void> save() {
    final data = jsonEncode({
      'version': 1,
      'id': id,
      'autoQr': autoQr,
      'devices': devices.values.map((g) => g.toJson()).toList(),
    });
    final next = _writes.then((_) => store.write(data));
    _writes = next.catchError((_) {});
    return next;
  }
}

enum RemoteActionKind {
  addAccount,
  addService,
  editAccount,
  editService,
  deleteAccount,
  deleteService,
  favoriteAccount,
  favoriteService,
}

class RemoteAction {
  RemoteAction(this.kind, {this.itemId = '', String? requestId})
    : requestId = requestId ?? randomToken(16);
  final RemoteActionKind kind;
  final String itemId, requestId;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'itemId': itemId,
    'requestId': requestId,
  };
  factory RemoteAction.fromJson(Map<String, dynamic> json) => RemoteAction(
    RemoteActionKind.values.byName(safeString(json['kind'])),
    itemId: json['itemId'] == '' ? '' : safeString(json['itemId']),
    requestId: safeString(json['requestId']),
  );
}
