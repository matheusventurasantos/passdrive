import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps copied secrets available briefly without clearing newer clipboard data.
abstract final class SecureClipboard {
  /// Gives the user a short window to paste after leaving the app, while
  /// still clearing a copied secret shortly after focus is lost.
  static const focusLossGracePeriod = Duration(seconds: 20);
  static Timer? _clearTimer;
  static int _generation = 0;
  static Duration? _defaultClearAfter = const Duration(minutes: 1);
  static String? _lastCopied;

  static Future<void> clear() async {
    final value = _lastCopied;
    _lastCopied = null;
    _clearTimer?.cancel();
    if (value != null) await _clearIfUnchanged(value, _generation);
    _generation++;
  }

  static void scheduleClearAfterFocusLoss() {
    final value = _lastCopied;
    if (value == null) return;

    final generation = ++_generation;
    _clearTimer?.cancel();
    _clearTimer = Timer(focusLossGracePeriod, () {
      unawaited(_clearIfUnchanged(value, generation));
    });
  }

  static String get clearAfterMessage {
    final duration = _defaultClearAfter;
    if (duration == null) return 'Não será limpa automaticamente.';
    if (duration.inSeconds == 30) return 'Limpa em 30 segundos.';
    if (duration.inMinutes == 1) return 'Limpa em 1 minuto.';
    return 'Limpa em ${duration.inMinutes} minutos.';
  }

  static void configure(Duration? clearAfter) {
    _defaultClearAfter = clearAfter;
    _clearTimer?.cancel();
    _clearTimer = null;
    _generation++;
  }

  static Future<void> copy(String value, {Duration? clearAfter}) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _lastCopied = value;

    final generation = ++_generation;
    _clearTimer?.cancel();
    final duration = clearAfter ?? _defaultClearAfter;
    if (duration == null) return;
    _clearTimer = Timer(duration, () {
      unawaited(_clearIfUnchanged(value, generation));
    });
  }

  static Future<void> _clearIfUnchanged(String value, int generation) async {
    if (generation != _generation) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (generation == _generation && current?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on Object {
      // Clipboard access is best effort and must never interrupt the app.
    }
  }

  @visibleForTesting
  static void resetForTests() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _generation++;
    _defaultClearAfter = const Duration(minutes: 1);
    _lastCopied = null;
  }
}
