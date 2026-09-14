import 'package:flutter/material.dart' hide showModalBottomSheet;
import '../windows/adaptive_sheet.dart';
import 'package:cryptography/cryptography.dart';
import '../vault/vault_access.dart';
import '../vault/recovery_key_confirmation_sheet.dart';

import '../navigation/passdrive_shell.dart';
import '../vault/vault_repository.dart';
import 'onboarding_step_one.dart';
import 'onboarding_step_three.dart';
import 'onboarding_step_two.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final PageController _pageController;
  int _currentPage = 0;
  String _appPassword = '';
  bool _hasOpenedHealth = false;
  SecretKey? _preparedKey;
  VaultRepository? _vault;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _vault?.close();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _continue() {
    if (_currentPage == 1 && _appPassword.isEmpty) {
      return;
    }

    if (_currentPage < 2) {
      _goToPage(_currentPage + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) => setState(() => _currentPage = page),
              children: [
                OnboardingStepOne(
                  isActive: _currentPage == 0,
                  onContinue: _continue,
                ),
                OnboardingStepTwo(
                  initialPassword: _appPassword,
                  onBiometricsChanged: (value) async {
                    if (!value) {
                      await VaultAccess.disable();
                      return false;
                    }
                    _preparedKey ??= await AesGcm.with256bits().newSecretKey();
                    return VaultAccess.enable(_preparedKey!);
                  },
                  onPasswordChanged: (value) => _appPassword = value,
                  onContinue: _continue,
                  isActive: _currentPage == 1,
                ),
                OnboardingStepThree(
                  onDownload: _downloadMasterKey,
                  onSkip: _finishOnboarding,
                  isActive: _currentPage == 2,
                ),
              ],
            ),
            if (_hasOpenedHealth)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xCCFFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadMasterKey() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RecoveryKeyConfirmationSheet(),
    );
    if (confirmed != true || !mounted) return;
    _openPasswordHealth(download: true);
  }

  void _finishOnboarding() {
    _openPasswordHealth();
  }

  Future<void> _openPasswordHealth({bool download = false}) async {
    if (_hasOpenedHealth) return;
    setState(() => _hasOpenedHealth = true);
    final VaultRepository vault;
    try {
      _vault ??= await VaultRepository.create(
        masterPassword: _appPassword,
        vaultKey: _preparedKey,
      );
      vault = _vault!;
      if (download && !await vault.downloadRecoveryKey()) {
        if (mounted) setState(() => _hasOpenedHealth = false);
        return;
      }
    } on Object {
      if (!mounted) return;
      setState(() => _hasOpenedHealth = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não conseguimos concluir. Tente novamente; seu cofre não será apagado.',
          ),
        ),
      );
      return;
    }
    _appPassword = '';
    if (!mounted) {
      await vault.close();
      return;
    }
    _vault = null;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondaryAnimation) =>
            PassDriveShell(vault: vault),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
