import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class OnboardingButton extends StatelessWidget {
  const OnboardingButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: icon ?? const SizedBox.shrink(),
        label: Text(label, style: AppTypography.button),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.paleGray,
          disabledForegroundColor: AppColors.bodyText,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
    );
  }
}
