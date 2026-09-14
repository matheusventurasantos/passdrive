import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
const desktopMuted = Color(0xFF748099);
const desktopLine = Color(0xFFE9EDF5);
const desktopBackground = Color(0xFFF8FAFE);

class DesktopPrimaryButton extends StatelessWidget {
  const DesktopPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: icon,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    label: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
  );
}

class DesktopHeading extends StatelessWidget {
  const DesktopHeading(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              letterSpacing: -.8,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    ),
  );
}

class DesktopSurface extends StatelessWidget {
  const DesktopSurface({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: desktopLine),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class DesktopPage extends StatelessWidget {
  const DesktopPage({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: desktopBackground,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 700 ? 24 : 36),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class DesktopColumns extends StatelessWidget {
  const DesktopColumns({
    required this.leading,
    required this.trailing,
    this.breakpoint = 800,
    this.leadingFlex = 1,
    this.trailingFlex = 1,
    this.equalHeight = false,
    super.key,
  });
  final Widget leading;
  final Widget trailing;
  final double breakpoint;
  final int leadingFlex;
  final int trailingFlex;
  final bool equalHeight;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <
          breakpoint *
              MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [leading, const SizedBox(height: 24), trailing],
        );
      }
      final row = Row(
        crossAxisAlignment: equalHeight
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          Expanded(flex: leadingFlex, child: leading),
          const SizedBox(width: 28),
          Expanded(flex: trailingFlex, child: trailing),
        ],
      );
      return equalHeight ? IntrinsicHeight(child: row) : row;
    },
  );
}

class DesktopAuthLayout extends StatelessWidget {
  const DesktopAuthLayout({
    required this.title,
    required this.child,
    this.step,
    this.illustration,
    super.key,
  });
  final String title;
  final Widget child;
  final int? step;
  final Widget? illustration;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final form = SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 48 : 28,
            vertical: 36,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step != null) ...[
                    Text(
                      'ETAPA $step DE 3',
                      style: const TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: desktopMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 36,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        );
        if (!wide) return form;
        return Row(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                color: const Color(0xFFEEF3FF),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PassDrive',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 48),
                        if (illustration != null) Center(child: illustration!),
                        const SizedBox(height: 40),
                        const Text(
                          'Senhas organizadas.\nAcesso fácil.',
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Cofre local criptografado',
                          style: TextStyle(fontSize: 16, color: desktopMuted),
                        ),
                        if (step != null) ...[
                          const SizedBox(height: 40),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (var index = 1; index <= 3; index++)
                                Chip(
                                  avatar: Icon(
                                    index < step!
                                        ? Icons.check_rounded
                                        : Icons.circle_outlined,
                                    size: 16,
                                    color: index <= step!
                                        ? AppColors.blue
                                        : desktopMuted,
                                  ),
                                  label: Text(
                                    ['Cofre', 'Proteção', 'Recuperação'][index -
                                        1],
                                  ),
                                  backgroundColor: index == step
                                      ? Colors.white
                                      : const Color(0xFFEEF3FF),
                                  side: BorderSide.none,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(flex: 6, child: Center(child: form)),
          ],
        );
      },
    ),
  );
}
