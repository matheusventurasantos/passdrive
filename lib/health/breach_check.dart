import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../vault/vault_models.dart';

enum BreachVerificationStatus { idle, checking, completed, unavailable }

/// The range endpoint normally returns a small list of SHA-1 suffixes. Keep a
/// hard limit so a bad proxy/server response cannot grow without bound in the
/// app process.
const pwnedPasswordsMaxRangeResponseBytes = 4 * 1024 * 1024;
const _maxRangeRows = 150000;
final _sha1SuffixPattern = RegExp(r'^[0-9A-Fa-f]{35}$');
final _countPattern = RegExp(r'^\d+$');

/// Checks Pwned Passwords with k-anonymity. The network only receives the
/// first five characters of a SHA-1 digest; neither the password nor its full
/// digest leaves the device.
class PwnedPasswordsClient {
  PwnedPasswordsClient({Future<String> Function(String prefix)? lookup})
    : _lookup = lookup ?? _lookupRange;

  final Future<String> Function(String prefix) _lookup;
  final Map<String, String> _rangeCache = {};

  void clearSessionCache() => _rangeCache.clear();

  Future<bool> isCompromised(String password) async {
    final digest = await Sha1().hash(utf8.encode(password));
    final hash = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);
    final range = await _rangeFor(prefix);
    return range.split('\n').any((line) {
      final separator = line.indexOf(':');
      return separator > 0 &&
          line.substring(0, separator).trim().toUpperCase() == suffix;
    });
  }

  Future<String> _rangeFor(String prefix) async {
    final cached = _rangeCache[prefix];
    if (cached != null) return cached;

    final value = await _lookup(prefix);
    if (utf8.encode(value).length > pwnedPasswordsMaxRangeResponseBytes) {
      throw const FormatException('Resposta da base muito grande.');
    }
    _validateRange(value);
    _rangeCache[prefix] = value;
    return value;
  }

  static Future<String> _lookupRange(String prefix) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.https('api.pwnedpasswords.com', '/range/$prefix'),
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'PassDrive/1.0');
      request.headers.set('Add-Padding', 'true');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Não foi possível consultar a base.');
      }
      return await _readBoundedRange(response);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readBoundedRange(HttpClientResponse response) async {
    if (response.contentLength > pwnedPasswordsMaxRangeResponseBytes) {
      throw const FormatException('Resposta da base muito grande.');
    }

    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > pwnedPasswordsMaxRangeResponseBytes) {
        throw const FormatException('Resposta da base muito grande.');
      }
      bytes.add(chunk);
    }

    return utf8.decode(bytes.takeBytes(), allowMalformed: false);
  }

  static void _validateRange(String value) {
    var rows = 0;
    for (final line in const LineSplitter().convert(value)) {
      final normalized = line.trim();
      if (normalized.isEmpty) continue;
      rows++;
      if (rows > _maxRangeRows) {
        throw const FormatException('Resposta da base muito grande.');
      }
      final separator = normalized.indexOf(':');
      if (separator != 35 || normalized.lastIndexOf(':') != separator) {
        throw const FormatException('Resposta da base inválida.');
      }
      final suffix = normalized.substring(0, separator);
      final count = normalized.substring(separator + 1);
      if (!_sha1SuffixPattern.hasMatch(suffix) ||
          !_countPattern.hasMatch(count)) {
        throw const FormatException('Resposta da base inválida.');
      }
    }
  }
}

class BreachCheckController extends ChangeNotifier {
  BreachCheckController({PwnedPasswordsClient? client, this.onPersist})
    : _client = client ?? PwnedPasswordsClient();

  final PwnedPasswordsClient _client;
  final Future<void> Function(Map<String, VaultBreachCheck> checks)? onPersist;
  final Map<String, bool> _sessionResults = {};
  Map<String, VaultBreachCheck> _cachedChecks = const {};
  Set<String> _compromisedServiceIds = const {};
  bool _hasCompleteResult = false;
  BreachVerificationStatus _status = BreachVerificationStatus.idle;
  int _generation = 0;

  BreachVerificationStatus get status => _status;
  bool get isChecking => _status == BreachVerificationStatus.checking;
  bool get isAvailable => _status == BreachVerificationStatus.completed;
  int? get compromisedCount =>
      _hasCompleteResult ? _compromisedServiceIds.length : null;

  bool isCompromised(String serviceId) =>
      _compromisedServiceIds.contains(serviceId);

  Future<void> beginSession(
    List<VaultService> services, {
    Map<String, VaultBreachCheck> cachedChecks = const {},
  }) {
    _generation++;
    _sessionResults.clear();
    _client.clearSessionCache();
    _cachedChecks = Map.unmodifiable(cachedChecks);
    final valid = _validCachedChecks(services);
    _compromisedServiceIds = {
      for (final entry in valid.entries)
        if (entry.value.compromised) entry.key,
    };
    _hasCompleteResult = _hasResultForEveryPassword(services, valid);
    _status = BreachVerificationStatus.idle;
    notifyListeners();
    return refresh(services, recheckKnownPasswords: true);
  }

  Future<void> refresh(
    List<VaultService> services, {
    bool recheckKnownPasswords = false,
  }) async {
    final generation = ++_generation;
    final validCached = _validCachedChecks(services);
    _compromisedServiceIds = {
      for (final entry in validCached.entries)
        if (entry.value.compromised) entry.key,
    };
    _hasCompleteResult = _hasResultForEveryPassword(services, validCached);
    // String equality is intentional here. `hashCode` is not a unique or
    // stable identity and a collision could apply one password's result to a
    // different credential. This map exists only for the current session.
    final passwords = <String>{
      for (final service in services)
        if (service.password.isNotEmpty) service.password,
    };
    if (passwords.isEmpty) {
      _compromisedServiceIds = const {};
      _hasCompleteResult = true;
      _status = BreachVerificationStatus.completed;
      notifyListeners();
      _persist(const {});
      return;
    }

    final missing = passwords
        .where(
          (password) =>
              recheckKnownPasswords || !_sessionResults.containsKey(password),
        )
        .toList(growable: false);
    if (missing.isNotEmpty) {
      _status = BreachVerificationStatus.checking;
      notifyListeners();
      try {
        final results = await Future.wait(
          missing.map(
            (password) async =>
                MapEntry(password, await _client.isCompromised(password)),
          ),
        );
        if (generation != _generation) return;
        for (final result in results) {
          _sessionResults[result.key] = result.value;
        }
      } on Object {
        if (generation != _generation) return;
        _status = BreachVerificationStatus.unavailable;
        notifyListeners();
        return;
      }
    }

    if (generation != _generation) return;
    _compromisedServiceIds = {
      for (final service in services)
        if (service.password.isNotEmpty &&
            (_sessionResults[service.password] == true ||
                (!_sessionResults.containsKey(service.password) &&
                    validCached[service.id]?.compromised == true)))
          service.id,
    };
    _hasCompleteResult = _hasResultForEveryPassword(services, validCached);
    _status = BreachVerificationStatus.completed;
    notifyListeners();
    _persist(_checksFor(services, validCached));
  }

  Map<String, VaultBreachCheck> _validCachedChecks(
    List<VaultService> services,
  ) => Map.unmodifiable({
    for (final service in services)
      if (service.password.isNotEmpty)
        if (_cachedChecks[service.id] case final check?)
          if (check.serviceUpdatedAt.isAtSameMomentAs(service.updatedAt))
            service.id: check,
  });

  bool _hasResultForEveryPassword(
    List<VaultService> services,
    Map<String, VaultBreachCheck> cached,
  ) => services
      .where((service) => service.password.isNotEmpty)
      .every(
        (service) =>
            _sessionResults.containsKey(service.password) ||
            cached.containsKey(service.id),
      );

  Map<String, VaultBreachCheck> _checksFor(
    List<VaultService> services,
    Map<String, VaultBreachCheck> cached,
  ) {
    final now = DateTime.now().toUtc();
    return Map.unmodifiable({
      for (final service in services)
        if (service.password.isNotEmpty)
          if (_sessionResults[service.password] case final result?)
            service.id: VaultBreachCheck(
              compromised: result,
              checkedAt: now,
              serviceUpdatedAt: service.updatedAt,
            )
          else if (cached[service.id] case final check?)
            service.id: check,
    });
  }

  void _persist(Map<String, VaultBreachCheck> checks) {
    final callback = onPersist;
    if (callback != null) unawaited(callback(checks));
  }
}
