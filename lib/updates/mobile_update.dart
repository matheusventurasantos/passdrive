import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MobileUpdateEvent { downloaded, failed, immediateResult }

class MobileUpdateOffer {
  const MobileUpdateOffer({
    required this.available,
    required this.immediate,
    required this.flexible,
    required this.resumeImmediate,
  });

  final bool available;
  final bool immediate;
  final bool flexible;
  final bool resumeImmediate;

  bool get canStart => immediate || flexible || resumeImmediate;
}

/// Thin bridge to Google Play In-App Updates. It deliberately does nothing for
/// APK/debug installs, iOS, Windows or any device without a Play-managed copy.
class MobileUpdate {
  static const _channel = MethodChannel('passdrive/update');
  static final ValueNotifier<MobileUpdateEvent?> events = ValueNotifier(null);
  static bool _ready = false;

  static Future<MobileUpdateOffer?> check() async {
    if (!Platform.isAndroid) return null;
    _installHandler();
    try {
      final reply = await _channel.invokeMapMethod<String, dynamic>('check');
      if (reply == null) return null;
      return MobileUpdateOffer(
        available: reply['available'] == true,
        immediate: reply['immediate'] == true,
        flexible: reply['flexible'] == true,
        resumeImmediate: reply['resumeImmediate'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> start({required bool immediate}) async {
    if (!Platform.isAndroid) return false;
    _installHandler();
    try {
      return await _channel.invokeMethod<bool>('start', {
            'mode': immediate ? 'immediate' : 'flexible',
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> complete() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('complete') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static void _installHandler() {
    if (_ready) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      events.value = switch (call.method) {
        'downloaded' => MobileUpdateEvent.downloaded,
        'failed' => MobileUpdateEvent.failed,
        'immediateResult' => MobileUpdateEvent.immediateResult,
        _ => null,
      };
    });
  }
}
