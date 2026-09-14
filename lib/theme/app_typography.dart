import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const appPageTitle = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 20,
    height: 1,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
  );

  static const sectionTitle = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 20,
    height: 1,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
  );

  static const itemTitle = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 16,
    height: 1.05,
    fontWeight: FontWeight.w500,
    color: AppColors.navy,
  );

  static const secondary = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 14,
    height: 1.05,
    fontWeight: FontWeight.w400,
    color: AppColors.bodyText,
  );

  static const buttonLabel = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 17,
    height: 1,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );

  static const title = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 54,
    height: 1.02,
    fontWeight: FontWeight.w700,
    color: Colors.black,
    letterSpacing: -1.8,
  );

  static const pageTitle = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 52,
    height: 1.02,
    fontWeight: FontWeight.w700,
    color: Colors.black,
    letterSpacing: -1.8,
  );

  static const body = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 27,
    height: 1.04,
    fontWeight: FontWeight.w400,
    color: AppColors.bodyText,
    letterSpacing: -0.8,
  );

  static const button = TextStyle(
    fontFamily: 'Kumbh Sans',
    fontSize: 26,
    height: 1,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    letterSpacing: -0.5,
  );
}
