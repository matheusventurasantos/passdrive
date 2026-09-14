import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class MasterPasswordThrottleStore {
  Future<String?> read();
  Future<void> write(String value);
}

class ProtectedMasterPasswordThrottleStore
    implements MasterPasswordThrottleStore {
  const ProtectedMasterPasswordThrottleStore();

  static const storage = FlutterSecureStorage();
  static const key = 'passdrive.master-password-attempts.v1';

  @override
  Future<String?> read() => storage.read(key: key);

  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
}

/// Small, non-secret state used to slow repeated master-password guesses.
/// It intentionally stores only a counter and an expiry timestamp.
class MasterPasswordAttemptThrottle {
  MasterPasswordAttemptThrottle({
    MasterPasswordThrottleStore? store,
    DateTime Function()? now,
  }) : _store = store ?? const ProtectedMasterPasswordThrottleStore(),
       _now = now ?? DateTime.now;

  static const _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
  ];

  final MasterPasswordThrottleStore _store;
  final DateTime Function() _now;
  int _failures = 0;
  DateTime? _lockedUntil;
  bool _loaded = false;
  bool _persistenceAvailable = true;

  bool get loaded => _loaded;
  bool get persistenceAvailable => _persistenceAvailable;

  Duration get remaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final value = until.difference(_now());
    return value.isNegative ? Duration.zero : value;
  }

  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is! Map || value['version'] != 1) {
          throw const FormatException();
        }
        final failures = value['failures'];
        final lockedUntil = value['lockedUntil'];
        if (failures is! int || failures < 0 || failures > _backoff.length) {
          throw const FormatException();
        }
        if (lockedUntil != null && lockedUntil is! String) {
          throw const FormatException();
        }
        _failures = failures;
        _lockedUntil = lockedUntil == null
            ? null
            : DateTime.parse(lockedUntil).toUtc();
      }
    } on Object {
      // A malformed or unreadable throttle record fails closed. It contains
      // no vault data, so refusing password attempts is the safe fallback.
      _persistenceAvailable = false;
    } finally {
      _loaded = true;
    }
  }

  Future<Duration> registerFailure() async {
    if (!_loaded) throw StateError('Limitador ainda não foi carregado.');
    if (!_persistenceAvailable) return remaining;
    if (_failures < _backoff.length) _failures++;
    _lockedUntil = _now().add(_backoff[_failures - 1]);
    await _persist();
    return remaining;
  }

  Future<void> reset() async {
    _failures = 0;
    _lockedUntil = null;
    if (_persistenceAvailable) await _persist();
  }

  Future<void> _persist() async {
    try {
      await _store.write(
        jsonEncode({
          'version': 1,
          'failures': _failures,
          'lockedUntil': _lockedUntil?.toUtc().toIso8601String(),
        }),
      );
    } on Object {
      _persistenceAvailable = false;
    }
  }
}
