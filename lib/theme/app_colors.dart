import 'package:flutter/material.dart';
import 'app_palette.dart';

abstract final class AppColors {
  static const blue = Color(0xFF4862E0);
  static Color get navy => AppPalette.resolve(const Color(0xFF152A96));
  static Color get bodyText => AppPalette.resolve(const Color(0xFF9B9B9B));
  static Color get border => AppPalette.resolve(const Color(0xFFD6DAE7));
  static Color get inputFill => AppPalette.resolve(const Color(0xFFFDFEFF));
  static Color get paleBlue => AppPalette.resolve(const Color(0xFFE2EBFD));
  static Color get paleBlueStrong =>
      AppPalette.resolve(const Color(0xFFDCE7FC));
  static Color get paleGray => AppPalette.resolve(const Color(0xFFE9EBF1));
  static const success = Color(0xFF50B85A);
  static const warning = Color(0xFFE9B43B);
  static const weak = Color(0xFFD96A6A);
}
