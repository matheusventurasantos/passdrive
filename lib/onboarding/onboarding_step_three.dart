import 'dart:math' as math;
import '../windows/desktop_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../widgets/onboarding_button.dart';
import '../widgets/onboarding_canvas.dart';

class OnboardingStepThree extends StatelessWidget {
  const OnboardingStepThree({
    required this.onDownload,
    required this.onSkip,
    this.isActive = true,
    super.key,
  });

  final VoidCallback onDownload;
  final VoidCallback onSkip;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (isWindowsDesktop) {
      return DesktopAuthLayout(
        title: 'Baixe sua chave-mestra',
        step: 3,
        illustration: const _AnimatedKeyIllustration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DesktopSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.key_rounded, size: 32, color: AppColors.blue),
                  SizedBox(height: 20),
                  Text(
                    'Arquivo de desbloqueio',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Este arquivo abre seu cofre. Guarde em local seguro. Não é um backup das senhas.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: desktopMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            DesktopPrimaryButton(
              label: 'Baixar chave-mestra',
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 22),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: const Text(
                'Vou baixar depois',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }
    return OnboardingCanvas(
      animate: isActive,
      child: OnboardingMobileLayout(
        step: 3,
        primaryAction: OnboardingButton(
          label: 'Baixar chave-mestra',
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded, size: 22),
        ),
        secondaryAction: TextButton(
          onPressed: onSkip,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.blue,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: const Text(
            'Vou baixar depois',
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w500,
              color: AppColors.blue,
            ),
          ),
        ),
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 4),
            Text(
              'Baixe sua chave-mestra',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 42,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: -1.4,
              ),
            ),
            SizedBox(height: 16),
            _AnimatedKeyIllustration(),
            SizedBox(height: 16),
            _MasterKeyCard(),
          ],
        ),
      ),
    );
  }
}

class _MasterKeyCard extends StatelessWidget {
  const _MasterKeyCard();

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 70,
      height: 70,
      decoration: const BoxDecoration(
        color: AppColors.paleBlueStrong,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.key_rounded, color: AppColors.blue, size: 36),
    );
    const details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Arquivo de desbloqueio',
          style: TextStyle(
            fontFamily: 'Kumbh Sans',
            fontSize: 20,
            height: 1.12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4D4D4D),
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Este arquivo abre seu cofre. Guarde em local seguro. Não é um backup das senhas.',
          style: TextStyle(
            fontFamily: 'Kumbh Sans',
            fontSize: 19,
            height: 1.18,
            fontWeight: FontWeight.w400,
            color: AppColors.bodyText,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(16) > 20.8;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(24),
          ),
          child: useVerticalLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [icon, const SizedBox(height: 14), details],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 16),
                    const Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }
}

class _AnimatedKeyIllustration extends StatefulWidget {
  const _AnimatedKeyIllustration();

  @override
  State<_AnimatedKeyIllustration> createState() =>
      _AnimatedKeyIllustrationState();
}

class _AnimatedKeyIllustrationState extends State<_AnimatedKeyIllustration>
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(320.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            height: width * 321 / 320,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 320,
                height: 321,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: SvgPicture.asset(
                        'etapa3criptografia.svg',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final cloudDrift =
                              math.sin(_controller.value * math.pi * 2) * 2.2;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: 2 + cloudDrift,
                                top: 40,
                                child: const _KeyCloud(width: 137, height: 70),
                              ),
                              Positioned(
                                left: 176 - cloudDrift * 0.7,
                                top: 192,
                                child: const _KeyCloud(width: 135, height: 70),
                              ),
                              _buildStar(
                                progress: _progress(0),
                                left: 286,
                                top: 152,
                                size: 33,
                                rise: 18,
                                color: AppColors.blue,
                              ),
                              _buildStar(
                                progress: _progress(0.34),
                                left: 27,
                                top: 258,
                                size: 38,
                                rise: 20,
                                color: const Color(0xFFE1ED32),
                              ),
                              _buildStar(
                                progress: _progress(0.67),
                                left: 104,
                                top: 0,
                                size: 38,
                                rise: 18,
                                color: AppColors.paleBlue,
                              ),
                            ],
                          );
                        },
                      ),
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
            painter: _KeyStarPainter(color),
          ),
        ),
      ),
    );
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}

class _KeyCloud extends StatelessWidget {
  const _KeyCloud({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: const _KeyCloudPainter(),
    );
  }
}

class _KeyCloudPainter extends CustomPainter {
  const _KeyCloudPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD9D9D9);
    final scaleX = size.width / 137;
    final scaleY = size.height / 70;

    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawCircle(const Offset(24.35, 48.12), 21.85, paint);
    canvas.drawCircle(const Offset(70.84, 35), 35, paint);
    canvas.drawCircle(const Offset(118.23, 51.63), 18.38, paint);
    canvas.drawRect(const Rect.fromLTWH(26.14, 52.5, 89.4, 17.5), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KeyCloudPainter oldDelegate) => false;
}

class _KeyStarPainter extends CustomPainter {
  const _KeyStarPainter(this.color);

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
  bool shouldRepaint(_KeyStarPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
