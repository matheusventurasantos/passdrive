import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PageIndicator extends StatelessWidget {
  const PageIndicator({required this.currentPage, super.key});

  final int currentPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: index == currentPage ? AppColors.blue : AppColors.paleGray,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
