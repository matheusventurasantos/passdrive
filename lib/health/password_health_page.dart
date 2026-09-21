import '../settings/app_strings.dart';
import '../settings/appearance_preferences.dart';
import '../theme/app_palette.dart';
import 'dart:math' as math;
import '../windows/desktop_layout.dart';

import 'package:flutter/material.dart';

import '../generator/password_generator_page.dart';
import '../generator/password_quality.dart';
import 'breach_check.dart';
import '../passwords/passwords_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../vault/vault_models.dart';
import '../vault/vault_repository.dart';

class PasswordHealthPage extends StatelessWidget {
  const PasswordHealthPage({
    this.showBottomNavigation = true,
    this.vault,
    this.onOpenPasswords,
    this.breachCheck,
    this.remoteSnapshot,
    super.key,
  });

  final bool showBottomNavigation;
  final VaultRepository? vault;
  final ValueChanged<String?>? onOpenPasswords;
  final BreachCheckController? breachCheck;
  final VaultSnapshot? remoteSnapshot;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return AnimatedBuilder(
      animation: breachCheck ?? Listenable.merge([]),
      builder: (context, _) {
        final summary = remoteSnapshot != null
            ? _HealthSummary.fromSnapshot(remoteSnapshot!, null)
            : vault == null
            ? const _HealthSummary.demo()
            : _HealthSummary.fromVault(vault!, breachCheck);
        if (isWindowsDesktop) return _desktopHome(context, summary);
        return Scaffold(
          backgroundColor: AppPalette.canvas,
          body: SafeArea(
            bottom: showBottomNavigation,
            child: Column(
              children: [
                const _HealthHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
                    child: Column(
                      children: [
                        ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                summary.statusText,
                                style: TextStyle(
                                  fontFamily: 'Kumbh Sans',
                                  fontSize: 13,
                                  height: 1,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.bodyText,
                                ),
                              ),
                              if (breachCheck?.isChecking == true) ...[
                                const SizedBox(width: 7),
                                SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: AppColors.bodyText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: _scoreAreaHeight(context),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final size = math.min(
                                  constraints.maxWidth,
                                  math.min(230.0, constraints.maxHeight),
                                );
                                return Center(
                                  child: SizedBox.square(
                                    dimension: size,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        const Positioned.fill(
                                          child: _ScoreBubbles(),
                                        ),
                                        _ScoreRing(summary: summary),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          _HealthGrid(
                            summary: summary,
                            onSelect: onOpenPasswords,
                          ),
                        ],
                        const SizedBox(height: 24),
                        _AccountsSection(
                          accounts: remoteSnapshot?.accounts ?? vault?.accounts,
                          services: remoteSnapshot?.services ?? vault?.services,
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                if (showBottomNavigation) const _HealthBottomNavigation(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _desktopHome(BuildContext context, _HealthSummary summary) {
    final entries = [
      (
        Icons.gpp_bad_outlined,
        tr('Comprometidas'),
        summary.compromised?.toString() ?? '—',
        AppPalette.resolve(const Color(0xFFE65353)),
        'compromised',
      ),
      (
        Icons.lock_open_rounded,
        tr('Fracas'),
        '${summary.weak}',
        AppPalette.resolve(const Color(0xFFDF820F)),
        'weak',
      ),
      (
        Icons.sync_rounded,
        tr('Reutilizadas'),
        '${summary.reused}',
        AppColors.blue,
        'reused',
      ),
      (
        Icons.verified_user_outlined,
        tr('Seguras'),
        '${summary.secure}',
        AppPalette.resolve(const Color(0xFF32AD72)),
        'secure',
      ),
    ];
    return DesktopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopHeading(
            tr('Saúde das senhas'),
            trailing: TextButton.icon(
              onPressed: () => onOpenPasswords?.call(null),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(tr('Ver senhas')),
            ),
          ),
          DesktopColumns(
            breakpoint: 720,
            leadingFlex: 5,
            trailingFlex: 6,
            equalHeight: true,
            leading: DesktopSurface(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('Visão geral'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox.square(
                    dimension: math.max(260, _scoreAreaHeight(context)),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: _ScoreBubbles()),
                        _ScoreRing(summary: summary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (breachCheck?.isChecking == true) ...[
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: desktopMuted,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          summary.statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: desktopMuted,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            trailing: DesktopSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('Resumo das senhas'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: desktopLine),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onOpenPasswords?.call(entries[i].$5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: entries[i].$4.withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                entries[i].$1,
                                color: entries[i].$4,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                entries[i].$2,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              entries[i].$3,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: desktopMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (vault == null || vault!.accounts.isNotEmpty) ...[
            const SizedBox(height: 28),
            DesktopSurface(
              child: _AccountsSection(
                accounts: remoteSnapshot?.accounts ?? vault?.accounts,
                services: remoteSnapshot?.services ?? vault?.services,
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _scoreAreaHeight(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (textScale >= 1.8) return 290;
    if (textScale >= 1.4) return 260;
    return 230;
  }
}

class _HealthHeader extends StatelessWidget {
  const _HealthHeader();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            const SizedBox(width: 30),
            Expanded(
              child: Center(
                child: Text(
                  tr('Saúde das senhas'),
                  style: AppTypography.appPageTitle,
                ),
              ),
            ),
            const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}

class _ScoreBubbles extends StatefulWidget {
  const _ScoreBubbles();

  @override
  State<_ScoreBubbles> createState() => _ScoreBubblesState();
}

class _ScoreBubblesState extends State<_ScoreBubbles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2800),
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
    Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _buildBubble(
              progress: _progress(0),
              left: 23,
              top: 151,
              size: 9,
              rise: 34,
              color: AppPalette.scoreBubble(const Color(0xFFB9D2FF)),
            ),
            _buildBubble(
              progress: _progress(0.26),
              left: 43,
              top: 87,
              size: 6,
              rise: 28,
              color: AppPalette.scoreBubble(const Color(0xFFD7E5FF)),
            ),
            _buildBubble(
              progress: _progress(0.51),
              left: 179,
              top: 71,
              size: 8,
              rise: 36,
              color: AppPalette.scoreBubble(const Color(0xFFAFCBFF)),
            ),
            _buildBubble(
              progress: _progress(0.76),
              left: 194,
              top: 155,
              size: 5,
              rise: 25,
              color: AppPalette.scoreBubble(const Color(0xFFD7E5FF)),
            ),
          ],
        );
      },
    );
  }

  double _progress(double phase) {
    return (_controller.value + phase) % 1;
  }

  Widget _buildBubble({
    required double progress,
    required double left,
    required double top,
    required double size,
    required double rise,
    required Color color,
  }) {
    final appearance = Curves.easeOut.transform(_clamp01(progress / 0.2));
    final fade = progress < 0.68
        ? 1.0
        : Curves.easeIn.transform(_clamp01((1 - progress) / 0.32));
    final verticalProgress = Curves.easeOut.transform(progress);

    return Positioned(
      left: left,
      top: top - rise * verticalProgress,
      child: Opacity(
        opacity: fade * appearance,
        child: Transform.scale(
          scale: appearance,
          alignment: Alignment.center,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: SizedBox.square(dimension: size),
          ),
        ),
      ),
    );
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.summary});

  final _HealthSummary summary;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: summary.score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) {
        return CustomPaint(
          painter: _ScoreRingPainter(
            progress,
            AppearancePreferences.instance.dark,
          ),
          child: child,
        );
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${summary.score}',
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 56,
                height: 0.95,
                fontWeight: FontWeight.w700,
                color: AppPalette.scoreRingBlue,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Pontuação'),
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w400,
                color: AppColors.bodyText,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: summary.color,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 7, height: 7),
                ),
                const SizedBox(width: 8),
                Text(
                  summary.label,
                  style: TextStyle(
                    fontFamily: 'Kumbh Sans',
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: summary.color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter(this.progress, this.darkMode);

  final double progress;
  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final circle = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius + 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppPalette.scoreRingOuter,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = AppPalette.scoreRingTrack,
    );

    final sweep = math.pi * 2 * progress;
    final bluePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppPalette.scoreRingBlue;
    canvas.drawArc(circle, -math.pi / 2, sweep, false, bluePaint);

    final endAngle = -math.pi / 2 + sweep;
    final end = Offset(
      center.dx + math.cos(endAngle) * radius,
      center.dy + math.sin(endAngle) * radius,
    );
    canvas.drawCircle(end, 4, Paint()..color = AppPalette.scoreRingBlue);
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.darkMode != darkMode;
  }
}

class _HealthGrid extends StatelessWidget {
  const _HealthGrid({required this.summary, required this.onSelect});

  final _HealthSummary summary;
  final ValueChanged<String?>? onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: textScale >= 1.8
          ? .72
          : textScale >= 1.4
          ? .86
          : 1.04,
      children: [
        _HealthCard(
          icon: Icons.shield_outlined,
          count: summary.compromised == null ? '—' : '${summary.compromised}',
          label: tr('Comprometidas'),
          color: AppPalette.resolve(const Color(0xFFFF5F59)),
          onTap: summary.compromised == null || onSelect == null
              ? null
              : () => onSelect!('compromised'),
        ),
        _HealthCard(
          icon: Icons.lock_outline,
          count: '${summary.weak}',
          label: tr('Fracas'),
          color: AppPalette.resolve(const Color(0xFFFF8A00)),
          onTap: onSelect == null ? null : () => onSelect!('weak'),
        ),
        _HealthCard(
          icon: Icons.sync,
          count: '${summary.reused}',
          label: tr('Reutilizadas'),
          color: AppPalette.resolve(const Color(0xFF347BFF)),
          onTap: onSelect == null ? null : () => onSelect!('reused'),
        ),
        _HealthCard(
          icon: Icons.verified_user_outlined,
          count: '${summary.secure}',
          label: tr('Seguras'),
          color: AppPalette.resolve(const Color(0xFF40C27B)),
          onTap: onSelect == null ? null : () => onSelect!('secure'),
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String count;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? '$count $label'
          : tx('$count $label. Abrir lista.', '$count $label. Open list.'),
      child: Material(
        color: AppPalette.resolve(Colors.white),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppPalette.resolve(const Color(0xFFE5EAF3))),
          borderRadius: BorderRadius.circular(19),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 12, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 32),
                const Spacer(),
                Text(
                  count,
                  style: TextStyle(
                    fontFamily: 'Kumbh Sans',
                    fontSize: 29,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Kumbh Sans',
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountsSection extends StatelessWidget {
  const _AccountsSection({required this.accounts, required this.services});

  final List<VaultAccount>? accounts;
  final List<VaultService>? services;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (accounts == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Contas'),
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          _AccountRow(
            email: 'joao@gmail.com',
            detail: tr('12 serviços'),
            showDivider: true,
          ),
          _AccountRow(
            email: 'joao@outlook.com',
            detail: tr('8 serviços'),
            showDivider: true,
          ),
          _AccountRow(email: 'contato@empresa.com', detail: tr('3 serviços')),
        ],
      );
    }
    if (accounts!.isEmpty) {
      return const SizedBox.shrink();
    }
    final visibleAccounts = accounts!.take(3).toList(growable: false);
    final linkedServices = services ?? <VaultService>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Contas'),
          style: TextStyle(
            fontFamily: 'Kumbh Sans',
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < visibleAccounts.length; index++)
          _AccountRow(
            email: visibleAccounts[index].email,
            detail: tx(
              '${linkedServices.where((service) => service.email.toLowerCase() == visibleAccounts[index].email.toLowerCase()).length} serviços',
              '${linkedServices.where((service) => service.email.toLowerCase() == visibleAccounts[index].email.toLowerCase()).length} services',
            ),
            showDivider: index < visibleAccounts.length - 1,
          ),
      ],
    );
  }
}

class _HealthSummary {
  const _HealthSummary({
    required this.score,
    required this.label,
    required this.color,
    required this.compromised,
    required this.weak,
    required this.reused,
    required this.secure,
    required this.statusText,
  });

  const _HealthSummary.demo()
    : score = 82,
      label = 'Boa',
      color = const Color(0xFF40B878),
      compromised = 22,
      weak = 89,
      reused = 114,
      secure = 219,
      statusText = 'Verificado há 2 min';

  final int score;
  final String label;
  final Color color;
  final int? compromised;
  final int weak;
  final int reused;
  final int secure;
  final String statusText;

  factory _HealthSummary.fromVault(
    VaultRepository vault,
    BreachCheckController? breachCheck,
  ) => _HealthSummary.fromSnapshot(vault.snapshot, breachCheck);

  factory _HealthSummary.fromSnapshot(
    VaultSnapshot snapshot,
    BreachCheckController? breachCheck,
  ) {
    final services = snapshot.services;
    if (services.isEmpty) {
      return _HealthSummary(
        score: 0,
        label: 'Sem dados',
        color: AppColors.bodyText,
        compromised: 0,
        weak: 0,
        reused: 0,
        secure: 0,
        statusText: 'Adicione senhas ao seu cofre',
      );
    }

    final byPassword = <String, int>{};
    for (final service in services) {
      if (service.password.isNotEmpty) {
        byPassword.update(
          service.password,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final weak = services
        .where((service) => passwordLevel(service.password) <= 2)
        .length;
    final secure = services
        .where((service) => passwordLevel(service.password) >= 4)
        .length;
    final reused = services
        .where(
          (service) =>
              service.password.isNotEmpty &&
              (byPassword[service.password] ?? 0) > 1,
        )
        .length;
    final compromised =
        breachCheck?.compromisedCount ??
        (services.every((s) => snapshot.breachChecks.containsKey(s.id))
            ? services
                  .where(
                    (s) => snapshot.breachChecks[s.id]?.compromised == true,
                  )
                  .length
            : null);
    final score =
        ((secure / services.length) * 100 -
                (weak / services.length) * 35 -
                (reused / services.length) * 20 -
                ((compromised ?? 0) / services.length) * 50)
            .round()
            .clamp(0, 100)
            .toInt();
    final label = score >= 80
        ? 'Boa'
        : score >= 50
        ? 'Atenção'
        : 'Fraca';
    final color = score >= 80
        ? AppPalette.resolve(const Color(0xFF40B878))
        : score >= 50
        ? AppPalette.resolve(const Color(0xFFFF8A00))
        : AppPalette.resolve(const Color(0xFFE65353));
    return _HealthSummary(
      score: score,
      label: label,
      color: color,
      compromised: compromised,
      weak: weak,
      reused: reused,
      secure: secure,
      statusText: breachCheck?.isChecking == true
          ? 'Verificando senhas comprometidas...'
          : breachCheck?.status == BreachVerificationStatus.unavailable
          ? 'Não foi possível verificar agora.'
          : breachCheck?.isAvailable == true
          ? 'Senhas comprometidas verificadas'
          : tx(
              'Análise local • ${services.length} serviços',
              'Local analysis • ${services.length} services',
            ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.email,
    required this.detail,
    this.showDivider = false,
  });

  final String email;
  final String detail;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.paleBlueStrong,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_circle_outlined,
                  color: AppColors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: TextStyle(
                        fontFamily: 'Kumbh Sans',
                        fontSize: 16,
                        height: 1.05,
                        fontWeight: FontWeight.w500,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        fontFamily: 'Kumbh Sans',
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w400,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFFB5BDCC),
                size: 22,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppPalette.resolve(const Color(0xFFF0F2F6)),
          ),
      ],
    );
  }
}

class _HealthBottomNavigation extends StatelessWidget {
  const _HealthBottomNavigation();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border(
          top: BorderSide(color: AppPalette.resolve(const Color(0xFFF1F3F8))),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _BottomNavigationItem(
              icon: Icons.home_outlined,
              label: tr('Início'),
              selected: true,
            ),
          ),
          Expanded(
            child: _BottomNavigationItem(
              icon: Icons.lock_outline,
              label: tr('Senhas'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PasswordsPage(),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _BottomNavigationItem(
              icon: Icons.key_outlined,
              label: tr('Gerador'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PasswordGeneratorPage(),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _BottomNavigationItem(
              icon: Icons.settings_outlined,
              label: tr('Ajustes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = selected
        ? AppPalette.resolve(const Color(0xFF347BFF))
        : AppPalette.resolve(const Color(0xFF9AA3B5));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 12,
              height: 1,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
