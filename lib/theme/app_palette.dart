import 'package:flutter/material.dart';
import '../settings/appearance_preferences.dart';

/// Shared mapping for the existing light palette. The UI keeps its geometry
/// and semantic accent colors; neutral surfaces and text adapt to night mode.
abstract final class AppPalette {
  static Color choose(Color light, Color dark) =>
      AppearancePreferences.instance.dark ? dark : light;

  /// The page background intentionally differs from [surface] at night so
  /// cards, sheets and navigation remain visually separated.
  static Color get canvas => choose(Colors.white, const Color(0xFF101827));

  static Color get surface => choose(Colors.white, const Color(0xFF182235));

  static Color get scoreRingOuter =>
      choose(const Color(0xFFE2EBFD), const Color(0xFF38547E));

  static Color get scoreRingTrack =>
      choose(const Color(0xFFF1F3F8), const Color(0xFF273950));

  static Color get scoreRingBlue =>
      choose(const Color(0xFF2F6FEB), const Color(0xFF6D9BFF));

  static Color scoreBubble(Color light) =>
      choose(light, const Color(0xFF526D9E));

  static Color resolve(Color light) {
    if (!AppearancePreferences.instance.dark || light.a == 0) return light;
    final hsl = HSLColor.fromColor(light);
    final luminance = light.computeLuminance();
    final Color result;
    if (luminance > .985) {
      // Pure white is the elevated card / title-bar surface.
      result = const Color(0xFF182235);
    } else if (luminance > .94) {
      // Page backgrounds retain a subtle distinction from cards.
      result = const Color(0xFF1D283B);
    } else if (luminance > .84) {
      // Pale grays are primarily borders, separators and disabled fills.
      result = const Color(0xFF2C3A52);
    } else if (luminance > .72) {
      result = const Color(0xFF35435B);
    } else if (luminance > .48) {
      result = const Color(0xFF303C52);
    } else if (hsl.saturation < .15) {
      result = luminance < .08
          ? const Color(0xFFEAF0FA)
          : const Color(0xFFAAB6CA);
    } else if (hsl.lightness < .42) {
      result = hsl.withLightness(.73).toColor();
    } else {
      result = light;
    }
    return result.withValues(alpha: light.a);
  }

  static T watch<T>(BuildContext context, T Function() build) {
    Theme.of(context);
    return build();
  }
}
