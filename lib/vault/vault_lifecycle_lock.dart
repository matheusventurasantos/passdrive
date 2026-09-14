import 'package:flutter/widgets.dart';

/// Tracks the distinction between a short loss of input focus and the app
/// actually leaving the foreground. Android can emit `inactive` for both
/// cases, so the lock countdown only starts after `hidden`/`paused` confirms
/// that the protected surface is no longer in front of the user.
class VaultLifecycleLockTracker {
  AppLifecycleState? _state;
  DateTime? _awaySince;
  bool _actuallyBackgrounded = false;

  AppLifecycleState? get state => _state;
  bool get actuallyBackgrounded => _actuallyBackgrounded;
  DateTime? get awaySince => _awaySince;

  VaultLifecycleTransition update(AppLifecycleState next, DateTime timestamp) {
    final previous = _state;
    if (next == AppLifecycleState.inactive) {
      _awaySince ??= timestamp;
    } else if (next == AppLifecycleState.hidden ||
        next == AppLifecycleState.paused ||
        next == AppLifecycleState.detached) {
      _awaySince ??= timestamp;
      _actuallyBackgrounded = true;
    }

    if (next == AppLifecycleState.resumed) {
      final resumedFromBackgroundAt = _actuallyBackgrounded ? _awaySince : null;
      _state = next;
      _awaySince = null;
      _actuallyBackgrounded = false;
      return VaultLifecycleTransition(
        previous: previous,
        current: next,
        awaySince: resumedFromBackgroundAt,
      );
    }

    _state = next;
    return VaultLifecycleTransition(
      previous: previous,
      current: next,
      awaySince: _awaySince,
    );
  }

  void reset() {
    _state = null;
    _awaySince = null;
    _actuallyBackgrounded = false;
  }
}

class VaultLifecycleTransition {
  const VaultLifecycleTransition({
    required this.previous,
    required this.current,
    required this.awaySince,
  });

  final AppLifecycleState? previous;
  final AppLifecycleState current;

  /// The timestamp from which a confirmed background transition started.
  /// It is populated only on the transition back to `resumed`.
  final DateTime? awaySince;

  bool get confirmedBackground => awaySince != null;
}
