import 'dart:math' as math;
import '../windows/desktop_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/onboarding_button.dart';
import '../widgets/onboarding_canvas.dart';

class OnboardingStepOne extends StatelessWidget {
  const OnboardingStepOne({
    required this.onContinue,
    this.isActive = true,
    super.key,
  });

  final VoidCallback onContinue;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (isWindowsDesktop) {
      return DesktopAuthLayout(
        title: 'Crie seu cofre seguro',
        step: 1,
        illustration: const _SafeIllustration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Guarde suas senhas com segurança no dispositivo.',
              style: TextStyle(fontSize: 18, height: 1.6, color: desktopMuted),
            ),
            const SizedBox(height: 32),
            DesktopPrimaryButton(label: 'Continuar', onPressed: onContinue),
          ],
        ),
      );
    }
    return OnboardingCanvas(
      animate: isActive,
      child: OnboardingMobileLayout(
        step: 1,
        primaryAction: OnboardingButton(
          label: 'Continuar',
          onPressed: onContinue,
        ),
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 18),
            _SafeIllustration(),
            SizedBox(height: 24),
            Text(
              'Crie seu cofre seguro',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 44,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: -1.4,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Guarde suas senhas com segurança no dispositivo. Sincronize quando quiser.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 20,
                height: 1.25,
                fontWeight: FontWeight.w400,
                color: Color(0xFF697386),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeIllustration extends StatelessWidget {
  const _SafeIllustration();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(320.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            height: width * 251 / 320,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 320,
                height: 251,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: SvgPicture.asset('cofre.svg', fit: BoxFit.fill),
                    ),
                    const Positioned.fill(child: _AnimatedSafeStars()),
                    const Positioned(
                      left: 99,
                      top: 152,
                      child: _SwingingLock(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedSafeStars extends StatefulWidget {
  const _AnimatedSafeStars();

  @override
  State<_AnimatedSafeStars> createState() => _AnimatedSafeStarsState();
}

class _AnimatedSafeStarsState extends State<_AnimatedSafeStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _buildStar(
              progress: _progress(0),
              left: 227,
              top: 199,
              size: 40,
              rise: 22,
              color: const Color(0xFFE1ED32),
            ),
            _buildStar(
              progress: _progress(0.34),
              left: 270,
              top: 45,
              size: 18,
              rise: 18,
              color: const Color(0xFF4862E0),
            ),
            _buildStar(
              progress: _progress(0.67),
              left: 3,
              top: 161,
              size: 44,
              rise: 24,
              color: const Color(0xFF4862E0),
            ),
          ],
        );
      },
    );
  }

  double _progress(double phase) {
    return (_controller.value + phase) % 1;
  }

  Widget _buildStar({
    required double progress,
    required double left,
    required double top,
    required double size,
    required double rise,
    required Color color,
  }) {
    final easedProgress = Curves.easeOut.transform(progress);
    final growth = Curves.easeOut.transform(_clamp01(progress / 0.18));
    final fade = progress < 0.68
        ? 1.0
        : Curves.easeIn.transform(_clamp01((1 - progress) / 0.32));

    return Positioned(
      left: left,
      top: top - rise * easedProgress,
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: growth,
          alignment: Alignment.center,
          child: CustomPaint(
            size: Size.square(size),
            painter: _SafeStarPainter(color),
          ),
        ),
      ),
    );
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}

class _SafeStarPainter extends CustomPainter {
  const _SafeStarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide / 2;
    final innerRadius = outerRadius * 0.24;
    final path = Path();

    for (var index = 0; index < 8; index++) {
      final radius = index.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + index * math.pi / 4;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SafeStarPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SwingingLock extends StatefulWidget {
  const _SwingingLock();

  @override
  State<_SwingingLock> createState() => _SwingingLockState();
}

class _SwingingLockState extends State<_SwingingLock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _rotation = Tween<double>(
      begin: -0.045,
      end: 0.045,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotation.value,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
      child: SizedBox(
        width: 50,
        height: 76,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: SvgPicture.asset(
                'cadeado.svg',
                width: 50,
                height: 70,
                fit: BoxFit.fill,
              ),
            ),
            Positioned(
              left: 22,
              top: -6,
              child: SvgPicture.asset(
                'prendedocadeado.svg',
                width: 7,
                height: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
