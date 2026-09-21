import 'package:flutter/material.dart';

import 'onboarding_header.dart';

/// Provides the shared entrance animation for the onboarding pages.
///
/// The layout itself stays responsive: content can scroll independently from
/// its fixed action area when a device is short, the keyboard is open or the
/// user has increased the system font size.
class OnboardingCanvas extends StatefulWidget {
  const OnboardingCanvas({required this.child, this.animate = true, super.key});

  final Widget child;
  final bool animate;

  @override
  State<OnboardingCanvas> createState() => _OnboardingCanvasState();
}

class _OnboardingCanvasState extends State<OnboardingCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
      value: widget.animate ? 0 : 1,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant OnboardingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;

    if (widget.animate) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Keeps the primary action reachable while the page content adapts to the
/// available height. The ordinary onboarding composition does not scroll; the
/// scroll view only becomes useful when content no longer fits.
class OnboardingMobileLayout extends StatelessWidget {
  const OnboardingMobileLayout({
    required this.step,
    required this.content,
    required this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final int step;
  final Widget content;
  final Widget primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePadding = constraints.maxWidth < 380 ? 22.0 : 35.0;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 0),
              child: OnboardingHeader(step: step),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(sidePadding, 16, sidePadding, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: content,
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(sidePadding, 10, sidePadding, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        primaryAction,
                        if (secondaryAction != null) ...[
                          const SizedBox(height: 2),
                          secondaryAction!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
