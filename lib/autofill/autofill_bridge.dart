import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../vault/vault_models.dart';

class AutofillRequest {
  const AutofillRequest({
    required this.id,
    required this.packageName,
    required this.domain,
    required this.hasUsername,
    required this.hasPassword,
  });

  final String id;
  final String packageName;
  final String? domain;
  final bool hasUsername;
  final bool hasPassword;

  factory AutofillRequest.fromMap(Map<Object?, Object?> map) => AutofillRequest(
    id: map['id'] as String? ?? '',
    packageName: map['packageName'] as String? ?? '',
    domain: (map['domain'] as String?)?.trim().toLowerCase(),
    hasUsername: map['hasUsername'] == true,
    hasPassword: map['hasPassword'] == true,
  );
}

/// A credential submitted through Android Autofill's save callback. It is
/// received only after the source app submits its form and is consumed from
/// native encrypted temporary storage after the vault is unlocked.
class AutofillSaveCandidate {
  const AutofillSaveCandidate({
    required this.id,
    required this.packageName,
    required this.domain,
    required this.identity,
    required this.password,
  });

  final String id;
  final String packageName;
  final String? domain;
  final String identity;
  final String password;

  bool get hasEmail => identity.contains('@');
  String get email => hasEmail ? identity : '';
  String get username => hasEmail ? '' : identity;

  factory AutofillSaveCandidate.fromMap(Map<Object?, Object?> map) =>
      AutofillSaveCandidate(
        id: map['id'] as String? ?? '',
        packageName: map['packageName'] as String? ?? '',
        domain: _normalizedDomain(map['domain'] as String?),
        identity: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
      );

  static String? _normalizedDomain(String? value) {
    final domain = value?.trim().toLowerCase() ?? '';
    return domain.isEmpty ? null : domain;
  }
}

class AutofillBridge {
  AutofillBridge._();

  static const _channel = MethodChannel('passdrive/autofill');
  static final pending = ValueNotifier<AutofillRequest?>(null);
  static final pendingSaveCaptureId = ValueNotifier<String?>(null);
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'request':
          _receiveRequest(call.arguments);
          return true;
        case 'saveRequest':
          _receiveSaveCaptureId(call.arguments);
          return true;
        default:
          return null;
      }
    });
    _channel
        .invokeMethod<Object?>('ready')
        .then(_receiveRequest)
        .catchError((_) {});
  }

  static void _receiveRequest(Object? raw) {
    if (raw is! Map) return;
    final request = AutofillRequest.fromMap(Map<Object?, Object?>.from(raw));
    pending.value = request;
  }

  static void _receiveSaveCaptureId(Object? raw) {
    if (raw is! Map) return;
    final id = raw['id'] as String? ?? '';
    if (id.isNotEmpty) pendingSaveCaptureId.value = id;
  }

  static Future<AutofillSaveCandidate?> consumePendingSaveCandidate() async {
    var id = pendingSaveCaptureId.value;
    if (id == null || id.isEmpty) {
      try {
        id = await _channel.invokeMethod<String>('consumeSaveCaptureId');
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    }
    pendingSaveCaptureId.value = null;
    if (id == null || id.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('consumeSaveCapture', {
        'id': id,
      });
      if (raw is! Map) return null;
      final candidate = AutofillSaveCandidate.fromMap(
        Map<Object?, Object?>.from(raw),
      );
      return candidate.identity.isEmpty || candidate.password.isEmpty
          ? null
          : candidate;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> enabled() async {
    try {
      return await _channel.invokeMethod<bool>('enabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openSettings() async {
    await _channel.invokeMethod<void>('openSettings');
  }

  static Future<void> disable() async {
    await _channel.invokeMethod<void>('disable');
  }

  static Future<void> cacheSnapshot(
    VaultSnapshot snapshot, {
    bool transient = false,
  }) async {
    try {
      final request = pending.value;
      // A normal unlocked session must not mirror the vault into the native
      // process. The only allowed cache is the short handoff after an active
      // Autofill authentication request, and it is scoped to that request.
      if (!transient || request == null || request.id.isEmpty) {
        await clearCache();
        return;
      }
      final matched = snapshot.services
          .where((service) => _matches(request, service))
          .toList(growable: false);
      final source =
          request.domain == null || request.domain!.isEmpty || matched.isEmpty
          ? snapshot.services
          : matched;
      await _channel.invokeMethod<void>('cache', {
        'credentials': source
            .take(8)
            .map(
              (service) => <String, String>{
                'name': service.name,
                'brand': service.brand,
                'url': service.url,
                'email': service.email,
                'username': service.username,
                'password': service.password,
              },
            )
            .toList(growable: false),
        'transient': transient,
      });
    } on MissingPluginException {
      // Autofill is Android-only; other platforms simply do not cache it.
    } on PlatformException {
      // The vault itself remains available if the optional bridge is absent.
    }
  }

  static Future<void> clearCache() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Autofill is Android-only.
    } on PlatformException {
      // There is no persisted data to clean up here.
    }
  }

  static Future<void> cancel() async {
    final request = pending.value;
    if (request == null) return;
    pending.value = null;
    await _channel.invokeMethod<void>('complete', {
      'id': request.id,
      'credentials': const <Map<String, String>>[],
    });
  }

  static Future<bool> fillFromSnapshot(VaultSnapshot snapshot) async {
    final request = pending.value;
    if (request == null || request.id.isEmpty) return false;
    final matched = snapshot.services
        .where((service) => _matches(request, service))
        .toList(growable: false);
    // Browsers and some IMEs can omit the web domain from the autofill
    // request. Keep the chooser useful in that case: the user can select the
    // correct credential instead of seeing an empty suggestion and a silent
    // cancellation.
    final source =
        request.domain == null || request.domain!.isEmpty || matched.isEmpty
        ? snapshot.services
        : matched;
    final candidates = source
        .take(8)
        .map(
          (service) => <String, String>{
            'name': service.name,
            'username': service.username.isNotEmpty
                ? service.username
                : service.email,
            'password': service.password,
          },
        )
        .where(
          (credential) =>
              (request.hasUsername && credential['username']!.isNotEmpty) ||
              (request.hasPassword && credential['password']!.isNotEmpty),
        )
        .toList(growable: false);
    pending.value = null;
    final completed =
        await _channel.invokeMethod<bool>('complete', {
          'id': request.id,
          'credentials': candidates,
        }) ??
        false;
    return completed;
  }

  static bool _matches(AutofillRequest request, VaultService service) {
    final domain = request.domain;
    final serviceHost = _host(service.url);
    if (domain != null && domain.isNotEmpty && serviceHost != null) {
      if (domain == serviceHost ||
          domain.endsWith('.$serviceHost') ||
          serviceHost.endsWith('.$domain')) {
        return true;
      }
    }
    if (request.packageName.isEmpty) return false;
    final package = _compact(request.packageName);
    final names = <String>{
      _compact(service.name),
      _compact(service.brand),
      if (serviceHost != null) _compact(serviceHost.split('.').first),
    }..removeWhere((value) => value.length < 3);
    return names.any(package.contains);
  }

  static String? _host(String value) {
    if (value.trim().isEmpty) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
