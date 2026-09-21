import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'master_password_policy.dart';
import 'vault_crypto.dart';
import 'vault_repository.dart';

class MasterPasswordSheet extends StatefulWidget {
  const MasterPasswordSheet({required this.vault, super.key});

  final VaultRepository vault;

  @override
  State<MasterPasswordSheet> createState() => _MasterPasswordSheetState();
}

class _MasterPasswordSheetState extends State<MasterPasswordSheet> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _currentVisible = false;
  bool _newVisible = false;
  bool _confirmationVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final current = _currentController.text;
    final next = _newController.text;
    final confirmation = _confirmationController.text;
    if (current.isEmpty) {
      setState(() => _error = tr('Digite sua senha atual.'));
      return;
    }
    if (next != confirmation) {
      setState(() => _error = tr('A confirmação da nova senha não confere.'));
      return;
    }
    final policyError = MasterPasswordPolicy.errorFor(next);
    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.vault.changeMasterPassword(
        currentPassword: current,
        newPassword: next,
        confirmation: confirmation,
      );
      if (mounted) Navigator.of(context).pop();
    } on VaultUnlockException {
      if (mounted) setState(() => _error = tr('A senha atual está incorreta.'));
    } on MasterPasswordConfirmationException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } on MasterPasswordValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on VaultStorageException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = tr('Não foi possível salvar a nova senha.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Alterar senha mestra'), style: AppTypography.sectionTitle),
            const SizedBox(height: 8),
            Text(
              tr(
                'A chave do cofre será mantida. Apenas a proteção da senha será atualizada.',
              ),
              style: AppTypography.secondary,
            ),
            const SizedBox(height: 20),
            const _MasterPasswordWarning(),
            const SizedBox(height: 20),
            _passwordField(
              label: tr('Senha atual'),
              hint: tr('Digite a senha atual'),
              controller: _currentController,
              visible: _currentVisible,
              onToggle: () =>
                  setState(() => _currentVisible = !_currentVisible),
            ),
            const SizedBox(height: 14),
            _passwordField(
              label: tr('Nova senha'),
              hint: tr('Crie uma nova senha mestra'),
              controller: _newController,
              visible: _newVisible,
              onToggle: () => setState(() => _newVisible = !_newVisible),
            ),
            const SizedBox(height: 14),
            _passwordField(
              label: tr('Confirmar nova senha'),
              hint: tr('Repita a nova senha'),
              controller: _confirmationController,
              visible: _confirmationVisible,
              onToggle: () =>
                  setState(() => _confirmationVisible = !_confirmationVisible),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: AppTypography.secondary.copyWith(
                          color: AppPalette.resolve(const Color(0xFFE65353)),
                          height: 1.3,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: AppPalette.resolve(Colors.white),
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      tr('Salvar nova senha'),
                      style: AppTypography.buttonLabel,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(label, style: AppTypography.itemTitle),
        ),
        TextField(
          controller: controller,
          enabled: !_busy,
          obscureText: !visible,
          autocorrect: false,
          enableSuggestions: false,
          style: AppTypography.itemTitle,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.secondary,
            filled: true,
            fillColor: AppPalette.resolve(const Color(0xFFF7F9FC)),
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppPalette.resolve(const Color(0xFFE1E6F0)),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _MasterPasswordWarning extends StatelessWidget {
  const _MasterPasswordWarning();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.resolve(const Color(0xFFFFF8E8)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.resolve(const Color(0xFFF4DFAC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFC28A16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Se você perder a senha mestra e a chave-mestra, poderá perder o acesso ao cofre. Guarde as duas com segurança.',
              ),
              style: AppTypography.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
