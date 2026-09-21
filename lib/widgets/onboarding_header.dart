import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../settings/app_strings.dart';
import '../theme/app_colors.dart';

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({required this.step, super.key});

  final int step;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: SvgPicture.asset('assets/branding/logo.svg'),
          ),
          Expanded(
            child: Text(
              tx('$step de 3', '$step of 3'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w400,
                color: AppColors.bodyText,
              ),
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}
