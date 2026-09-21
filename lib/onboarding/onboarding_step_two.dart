import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import '../windows/desktop_layout.dart';
import '../generator/password_generator_page.dart' show PasswordStrengthBar;

import '../theme/app_colors.dart';
import '../vault/master_password_policy.dart';
import '../widgets/onboarding_button.dart';
import '../widgets/onboarding_canvas.dart';

class OnboardingStepTwo extends StatefulWidget {
  const OnboardingStepTwo({
    required this.initialPassword,
    required this.onPasswordChanged,
    required this.onContinue,
    this.isActive = true,
    this.onBiometricsChanged,
    super.key,
  });

  final String initialPassword;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onContinue;
  final bool isActive;
  final Future<bool> Function(bool)? onBiometricsChanged;

  @override
  State<OnboardingStepTwo> createState() => _OnboardingStepTwoState();
}

class _OnboardingStepTwoState extends State<OnboardingStepTwo> {
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmationController;
  bool _showPassword = false;
  bool _showConfirmation = false;
  bool _biometricsEnabled = false;
  bool _biometricsBusy = false;
  bool _hasAttemptedContinue = false;
  String? _passwordError;
  String? _confirmationError;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController(text: widget.initialPassword);
    _confirmationController = TextEditingController();
    _passwordController.addListener(_notifyPasswordChanged);
    _confirmationController.addListener(_refresh);
  }

  @override
  void dispose() {
    _passwordController
      ..removeListener(_notifyPasswordChanged)
      ..dispose();
    _confirmationController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _notifyPasswordChanged() {
    widget.onPasswordChanged(_passwordController.text);
    _refresh();
  }

  void _refresh() {
    setState(() {
      if (_hasAttemptedContinue) {
        _updateValidationErrors();
      }
    });
  }

  void _updateValidationErrors() {
    final password = _passwordController.text;
    final confirmation = _confirmationController.text;

    _passwordError = password.isEmpty
        ? tr('Digite a senha do aplicativo.')
        : password.length < MasterPasswordPolicy.minimumLength
        ? tx(
            'Use pelo menos ${MasterPasswordPolicy.minimumLength} caracteres.',
            'Use at least ${MasterPasswordPolicy.minimumLength} characters.',
          )
        : MasterPasswordPolicy.errorFor(password);
    _confirmationError = confirmation.isEmpty
        ? tr('Confirme a senha do aplicativo.')
        : password.isEmpty
        ? null
        : password != confirmation
        ? tr('As senhas são diferentes.')
        : null;

    if (password.isEmpty && confirmation.isEmpty) {
      _confirmationError = null;
    }
  }

  void _handleContinue() {
    final password = _passwordController.text;
    final confirmation = _confirmationController.text;
    final isValid =
        password.length >= 8 &&
        confirmation.isNotEmpty &&
        password == confirmation &&
        MasterPasswordPolicy.errorFor(password) == null;

    setState(() {
      _hasAttemptedContinue = true;
      _updateValidationErrors();
    });

    if (isValid) {
      widget.onContinue();
    }
  }

  Future<void> _changeBiometrics(bool value) async {
    setState(() => _biometricsBusy = true);
    try {
      final enabled = await widget.onBiometricsChanged?.call(value) ?? false;
      if (mounted) setState(() => _biometricsEnabled = enabled);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Biometria não ativada. Você pode continuar com sua senha e tentar novamente.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _biometricsBusy = false);
    }
  }

  Widget _desktopPasswordField(
    String label,
    TextEditingController controller,
    bool visible,
    VoidCallback onToggle,
    String? error,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        obscureText: !visible,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => _handleContinue(),
        style: TextStyle(fontSize: 17, color: AppColors.navy),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppPalette.resolve(const Color(0xFFF8FAFE)),
          contentPadding: const EdgeInsets.all(18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: desktopLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: desktopLine),
          ),
          suffixIcon: IconButton(
            tooltip: visible ? tr('Ocultar senha') : tr('Mostrar senha'),
            onPressed: onToggle,
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFE65353),
              height: 1.4,
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return DesktopAuthLayout(
        title: tr('Proteja suas senhas'),
        step: 2,
        illustration: const Icon(
          Icons.lock_person_outlined,
          size: 180,
          color: AppColors.blue,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _desktopPasswordField(
              tr('Senha do aplicativo'),
              _passwordController,
              _showPassword,
              () => setState(() => _showPassword = !_showPassword),
              _passwordError,
            ),
            const SizedBox(height: 12),
            PasswordStrengthBar(password: _passwordController.text),
            const SizedBox(height: 24),
            _desktopPasswordField(
              tr('Confirmar senha'),
              _confirmationController,
              _showConfirmation,
              () => setState(() => _showConfirmation = !_showConfirmation),
              _confirmationError,
            ),
            const SizedBox(height: 24),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                tr('Desbloquear com biometria'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              value: _biometricsEnabled,
              onChanged: _biometricsBusy ? null : _changeBiometrics,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  !_biometricsBusy &&
                      (_passwordController.text.isNotEmpty ||
                          _confirmationController.text.isNotEmpty)
                  ? _handleContinue
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                tr('Continuar'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return OnboardingCanvas(
      animate: widget.isActive,
      child: OnboardingMobileLayout(
        step: 2,
        primaryAction: OnboardingButton(
          label: tr('Continuar'),
          onPressed: _handleContinue,
          enabled:
              !_biometricsBusy &&
              (_passwordController.text.isNotEmpty ||
                  _confirmationController.text.isNotEmpty),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Proteja suas senhas'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: AppPalette.resolve(Colors.black),
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'Crie uma senha forte e ative a biometria para mais segurança.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w400,
                color: AppColors.bodyText,
              ),
            ),
            const SizedBox(height: 20),
            _PasswordCard(
              passwordController: _passwordController,
              confirmationController: _confirmationController,
              showPassword: _showPassword,
              showConfirmation: _showConfirmation,
              passwordError: _passwordError,
              confirmationError: _confirmationError,
              onTogglePassword: () =>
                  setState(() => _showPassword = !_showPassword),
              onToggleConfirmation: () =>
                  setState(() => _showConfirmation = !_showConfirmation),
            ),
            const SizedBox(height: 16),
            _BiometricsCard(
              enabled: _biometricsEnabled,
              onChanged: _biometricsBusy ? null : _changeBiometrics,
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({
    required this.passwordController,
    required this.confirmationController,
    required this.showPassword,
    required this.showConfirmation,
    required this.passwordError,
    required this.confirmationError,
    required this.onTogglePassword,
    required this.onToggleConfirmation,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmationController;
  final bool showPassword;
  final bool showConfirmation;
  final String? passwordError;
  final String? confirmationError;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmation;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final password = passwordController.text;
    final confirmation = confirmationController.text;
    final matches = password.isNotEmpty && password == confirmation;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label: tr('Senha do aplicativo')),
          const SizedBox(height: 12),
          _PasswordInput(
            controller: passwordController,
            obscureText: !showPassword,
            onToggleVisibility: onTogglePassword,
          ),
          _ValidationMessage(message: passwordError),
          const SizedBox(height: 4),
          _PasswordStrength(password: password),
          const SizedBox(height: 4),
          _FieldLabel(label: tr('Confirmar senha')),
          const SizedBox(height: 12),
          _PasswordInput(
            controller: confirmationController,
            obscureText: !showConfirmation,
            onToggleVisibility: onToggleConfirmation,
            isValid: matches,
          ),
          _ValidationMessage(message: confirmationError),
        ],
      ),
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppPalette.resolve(const Color(0xFFFFE9E9)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.weak,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message!,
                      style: const TextStyle(
                        fontFamily: 'Kumbh Sans',
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: AppColors.weak,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Kumbh Sans',
        fontSize: 16,
        height: 1.15,
        fontWeight: FontWeight.w500,
        color: AppPalette.resolve(Colors.black),
        letterSpacing: -0.7,
      ),
    );
  }
}

class _PasswordInput extends StatelessWidget {
  const _PasswordInput({
    required this.controller,
    required this.obscureText,
    required this.onToggleVisibility,
    this.isValid = false,
  });

  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        fontFamily: 'Kumbh Sans',
        fontSize: 16,
        color: AppPalette.resolve(Colors.black),
      ),
      decoration: InputDecoration(
        constraints: const BoxConstraints(minHeight: 52),
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isValid)
              const Icon(Icons.check, color: AppColors.success, size: 23),
            IconButton(
              tooltip: obscureText ? tr('Mostrar senha') : tr('Ocultar senha'),
              onPressed: onToggleVisibility,
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.navy,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final strength = _strengthFor(password);

    return SizedBox(
      height: 6,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: strength.toDouble()),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, level, child) {
          final color = _colorForLevel(level);
          final progress = (level / 5).clamp(0.0, 1.0);

          return LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    width: constraints.maxWidth * progress,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _colorForLevel(double level) {
    if (level <= 1) return AppColors.weak;
    if (level <= 3) {
      return Color.lerp(AppColors.weak, AppColors.warning, (level - 1) / 2)!;
    }
    return Color.lerp(AppColors.warning, AppColors.success, (level - 3) / 2)!;
  }

  int _strengthFor(String value) {
    if (value.isEmpty) return 0;
    if (value.length < 6) return 1;
    if (value.length < 8) return 3;
    return 5;
  }
}

class _BiometricsCard extends StatelessWidget {
  const _BiometricsCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(16) > 20.8;
        final icon = Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.paleBlueStrong,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.fingerprint, color: AppColors.blue, size: 32),
        );
        final toggle = Switch.adaptive(
          value: enabled,
          onChanged: onChanged,
          activeTrackColor: AppColors.blue,
          activeThumbColor: AppPalette.resolve(Colors.white),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Desbloquear com biometria'),
              style: const TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4D4D4D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Use sua digital para abrir o app.'),
              style: TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w400,
                color: AppColors.bodyText,
              ),
            ),
          ],
        );
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
          decoration: BoxDecoration(
            color: AppPalette.resolve(Colors.white),
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [icon, const Spacer(), toggle]),
                    const SizedBox(height: 12),
                    details,
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                    toggle,
                  ],
                ),
        );
      },
    );
  }
}
