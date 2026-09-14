import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({required this.step, super.key});

  final int step;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(width: 32, height: 32, child: SvgPicture.asset('logo.svg')),
          Expanded(
            child: Text(
              '$step de 3',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 19,
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
