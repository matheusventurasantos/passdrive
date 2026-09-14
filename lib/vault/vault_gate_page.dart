import 'dart:async';

import 'package:flutter/material.dart';
import '../windows/desktop_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../navigation/passdrive_shell.dart';
import '../onboarding/onboarding_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'vault_crypto.dart';
import 'vault_repository.dart';
import 'vault_access.dart';
import '../autofill/autofill_bridge.dart';
import 'master_password_throttle.dart';

class VaultGatePage extends StatefulWidget {
  const VaultGatePage({super.key});

  @override
  State<VaultGatePage> createState() => _VaultGatePageState();
}

class _VaultGatePageState extends State<VaultGatePage> {
  final _passwordController = TextEditingController();
  bool? _hasVault;
  bool _loadFailed = false;
  bool _isSubmitting = false;
  bool _passwordVisible = false;
  bool _biometricEnabled = false;
  String? _errorText;
  final _passwordThrottle = MasterPasswordAttemptThrottle();

  @override
  void initState() {
    super.initState();
    _loadVaultState();
  }

  @override
  void dispose() {
    unawaited(AutofillBridge.cancel());
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadVaultState() async {
    try {
      final hasVault = await VaultRepository.isInitialized();
      bool enabled = false;
      if (hasVault) {
        await _passwordThrottle.load();
        try {
          enabled = await VaultAccess.enabled();
        } on Object {
          /* Password remains available. */
        }
      }
      if (mounted) {
        setState(() {
          _hasVault = hasVault;
          _biometricEnabled = enabled;
          _loadFailed = false;
        });
        if (enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _submit(method: 'biometric');
          });
        }
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _errorText = 'Não foi possível abrir o cofre local.';
        });
      }
    }
  }

  Future<void> _submit({String method = 'password'}) async {
    final hasVault = _hasVault;
    if (hasVault != true || _isSubmitting) return;

    final password = _passwordController.text;
    if (method == 'password' && password.length < 8) {
      setState(
        () => _errorText = password.isEmpty
            ? 'Digite sua senha para continuar.'
            : 'Sua senha precisa ter pelo menos 8 caracteres.',
      );
      return;
    }
    if (method == 'password') {
      if (!_passwordThrottle.loaded ||
          !_passwordThrottle.persistenceAvailable) {
        setState(
          () => _errorText =
              'Não foi possível validar as tentativas com segurança agora.',
        );
        return;
      }
      final remaining = _passwordThrottle.remaining;
      if (remaining > Duration.zero) {
        final seconds =
            remaining.inSeconds +
            (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
        setState(
          () => _errorText =
              'Aguarde $seconds segundo${seconds == 1 ? '' : 's'} antes de tentar novamente.',
        );
        return;
      }
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    try {
      final VaultRepository vault;
      if (method == 'file') {
        final bytes = await VaultAccess.pick();
        if (bytes == null) return;
        try {
          vault = await VaultRepository.openWithFile(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } else if (method == 'biometric') {
        vault = await VaultRepository.openWithBiometrics();
      } else {
        vault = await VaultRepository.open(masterPassword: password);
        await _passwordThrottle.reset();
      }
      if (!mounted) {
        await vault.close();
        return;
      }
      final isAutofillAuthentication = AutofillBridge.pending.value != null;
      if (isAutofillAuthentication) {
        // Firefox may issue a fresh fill request after the authentication
        // Activity closes instead of consuming its result. Keep a short,
        // in-memory fallback for that exact handoff; it is never persisted.
        await AutofillBridge.cacheSnapshot(vault.snapshot, transient: true);
      }
      final completedAuthentication = await AutofillBridge.fillFromSnapshot(
        vault.snapshot,
      );
      if (completedAuthentication) {
        await vault.close();
        return;
      }
      if (!mounted) {
        await vault.close();
        return;
      }
      final saveCandidate = await AutofillBridge.consumePendingSaveCandidate();
      if (!mounted) {
        await vault.close();
        return;
      }
      _passwordController.clear();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              PassDriveShell(vault: vault, pendingAutofillSave: saveCandidate),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        ),
      );
    } on FormatException {
      if (mounted) {
        setState(
          () => _errorText =
              'Este arquivo não é uma chave-mestra válida do PassDrive.',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _errorText = e.code == 'cancelled'
              ? null
              : method == 'biometric'
              ? 'Biometria indisponível agora. Use sua senha ou chave-mestra.'
              : 'Não conseguimos acessar o arquivo. Selecione-o novamente.',
        );
      }
    } on VaultUnlockException {
      if (method == 'password' && _passwordThrottle.loaded) {
        final remaining = await _passwordThrottle.registerFailure();
        if (mounted && remaining > Duration.zero) {
          final seconds =
              remaining.inSeconds +
              (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
          setState(
            () => _errorText =
                'A senha não desbloqueou seu cofre. Aguarde $seconds segundo${seconds == 1 ? '' : 's'} antes de tentar novamente.',
          );
          return;
        }
      }
      if (mounted) {
        setState(
          () => _errorText = method == 'file'
              ? 'Esta chave não abre seu cofre. Selecione o arquivo correspondente.'
              : method == 'biometric'
              ? 'Entre com senha ou arquivo e ative a biometria novamente nos Ajustes.'
              : 'A senha não desbloqueou seu cofre. Confira e tente novamente.',
        );
      }
    } on StateError {
      if (mounted) {
        setState(
          () => _errorText =
              'Não foi possível ler o cofre. Feche o app e tente novamente.',
        );
      }
    } on VaultStorageException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } on Object catch (error) {
      debugPrint('Falha no acesso ao cofre: ${error.runtimeType}');
      if (mounted) {
        setState(
          () => _errorText = method == 'file'
              ? 'Não foi possível concluir a leitura da chave-mestra.'
              : 'Não foi possível acessar o cofre.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVault = _hasVault;
    if (hasVault == false) return const OnboardingPage();
    if (isWindowsDesktop) {
      return Scaffold(
        body: DesktopAuthLayout(
          title: 'Abrir cofre',
          illustration: SvgPicture.asset(
            'assets/illustrations/cofre.svg',
            width: 320,
          ),
          child: hasVault == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadFailed) ...[
                      Text(
                        _errorText ?? 'Não foi possível abrir o cofre local.',
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: desktopMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.tonalIcon(
                        onPressed: _loadVaultState,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ] else
                      const Center(child: CircularProgressIndicator()),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _VaultFieldLabel('Senha do aplicativo'),
                    TextField(
                      controller: _passwordController,
                      enabled: !_isSubmitting,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: !_passwordVisible,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.navy,
                      ),
                      decoration: _decoration(
                        hintText: 'Digite sua senha',
                        suffix: IconButton(
                          tooltip: _passwordVisible
                              ? 'Ocultar senha'
                              : 'Mostrar senha',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Color(0xFFE65353),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Entrar',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (_biometricEnabled)
                      OutlinedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => _submit(method: 'biometric'),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Usar biometria'),
                      ),
                    TextButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _submit(method: 'file'),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text(
                        'Entrar com chave-mestra',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: hasVault == null
            ? _loadFailed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: FilledButton.tonalIcon(
                          onPressed: _loadVaultState,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ),
                    )
                  : const Center(
                      child: SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SvgPicture.asset(
                            'assets/branding/logo.svg',
                            width: 36,
                            height: 36,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Seu cofre,\nsempre com você',
                          textAlign: TextAlign.center,
                          style: AppTypography.appPageTitle.copyWith(
                            fontSize: 30,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _VaultMark(),
                        const SizedBox(height: 24),
                        const _VaultFieldLabel('Senha do aplicativo'),
                        TextField(
                          enabled: !_isSubmitting,
                          autocorrect: false,
                          enableSuggestions: false,
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          style: AppTypography.itemTitle,
                          decoration: _decoration(
                            hintText: 'Digite sua senha',
                            suffix: IconButton(
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          child: _errorText == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _errorText!,
                                      style: AppTypography.secondary.copyWith(
                                        color: const Color(0xFFE65353),
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF347BFF),
                              disabledBackgroundColor: const Color(0xFFB9CCF7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Entrar',
                                    style: AppTypography.buttonLabel,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_biometricEnabled)
                          OutlinedButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _submit(method: 'biometric'),
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Usar biometria'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              textStyle: AppTypography.itemTitle,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _submit(method: 'file'),
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Entrar com chave-mestra'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.blue,
                            textStyle: AppTypography.itemTitle,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  InputDecoration _decoration({required String hintText, Widget? suffix}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTypography.secondary,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E6F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
      ),
    );
  }
}

class _VaultMark extends StatelessWidget {
  const _VaultMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.asset(
        'assets/illustrations/cofre.svg',
        height: MediaQuery.sizeOf(context).height < 700 ? 100 : 150,
      ),
    );
  }
}

class _VaultFieldLabel extends StatelessWidget {
  const _VaultFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: AppTypography.itemTitle.copyWith(fontSize: 15)),
    );
  }
}
