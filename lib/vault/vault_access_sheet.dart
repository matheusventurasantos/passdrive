import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'vault_access.dart';
import 'vault_models.dart';
import 'vault_repository.dart';
import '../autofill/autofill_bridge.dart';

class VaultAccessSheet extends StatefulWidget {
  const VaultAccessSheet({
    required this.vault,
    required this.onLock,
    required this.onDownloadRecoveryKey,
    this.onAutoLockChanged,
    this.onChangeMasterPassword,
    super.key,
  });
  final VaultRepository vault;
  final VoidCallback onLock;
  final Future<void> Function() onDownloadRecoveryKey;
  final ValueChanged<VaultAutoLock>? onAutoLockChanged;
  final VoidCallback? onChangeMasterPassword;
  @override
  State<VaultAccessSheet> createState() => _VaultAccessSheetState();
}

class _VaultAccessSheetState extends State<VaultAccessSheet>
    with WidgetsBindingObserver {
  bool _enabled = false;
  bool _autofillEnabled = false;
  bool _busy = true;
  String? _message;
  late VaultAutoLock _autoLock;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoLock = widget.vault.autoLock;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAutofill();
  }

  Future<void> _refreshAutofill() async {
    final enabled = await AutofillBridge.enabled();
    if (mounted) setState(() => _autofillEnabled = enabled);
  }

  Future<void> _load() async {
    try {
      final enabled = await VaultAccess.enabled();
      final autofillEnabled = await AutofillBridge.enabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _autofillEnabled = autofillEnabled;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _message = tr('Biometria indisponível neste aparelho.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _message = e.code == 'cancelled'
              ? tr('Operação cancelada. Sua senha continua funcionando.')
              : tr(
                  'Não foi possível concluir. Confira a biometria do aparelho ou tente novamente.',
                ),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = tr('Não foi possível concluir. Tente novamente.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24, 12, 24, 28 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(tr('Acesso ao cofre'), style: AppTypography.sectionTitle),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('Entrar com biometria'),
                  style: AppTypography.itemTitle,
                ),
                subtitle: Text(
                  tr('Sua senha e chave-mestra continuam disponíveis.'),
                  style: AppTypography.secondary,
                ),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (value) => _run(() async {
                        if (value) {
                          final enabled = await widget.vault.enableBiometrics();
                          if (mounted) setState(() => _enabled = enabled);
                        } else {
                          await VaultAccess.disable();
                          if (mounted) setState(() => _enabled = false);
                        }
                      }),
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('Preenchimento automático'),
                  style: AppTypography.itemTitle,
                ),
                subtitle: Text(
                  tr(
                    'Use as credenciais do PassDrive em sites e aplicativos. No Chrome, selecione “Autofill usando outro serviço”.',
                  ),
                  style: AppTypography.secondary,
                ),
                value: _autofillEnabled,
                onChanged: _busy
                    ? null
                    : (value) async {
                        await _run(() async {
                          if (value) {
                            await AutofillBridge.openSettings();
                          } else {
                            await AutofillBridge.disable();
                            if (mounted) {
                              setState(() => _autofillEnabled = false);
                            }
                          }
                        });
                      },
              ),
              const SizedBox(height: 20),
              Text(tr('Bloqueio automático'), style: AppTypography.itemTitle),
              const SizedBox(height: 10),
              VaultAutoLockPicker(
                value: _autoLock,
                onChanged: _busy
                    ? null
                    : (value) {
                        _run(() async {
                          await widget.vault.setAutoLock(value);
                          if (!mounted) return;
                          setState(() => _autoLock = value);
                          widget.onAutoLockChanged?.call(value);
                        });
                      },
              ),
              const SizedBox(height: 8),
              Text(
                tr('O cofre será bloqueado depois que o app ficar inativo.'),
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 20),
              Text('Chave-mestra', style: AppTypography.itemTitle),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Este arquivo abre seu cofre sem a senha. Guarde-o em um local seguro e não compartilhe. Ele não contém um backup das suas senhas.',
                ),
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : widget.onChangeMasterPassword,
                icon: const Icon(Icons.password_outlined),
                label: Text(tr('Alterar senha mestra')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: AppPalette.resolve(const Color(0xFFD6DAE7)),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : widget.onDownloadRecoveryKey,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.download_rounded),
                label: Text(tr('Baixar chave-mestra')),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_message!, style: AppTypography.secondary),
                  ),
                ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : widget.onLock,
                icon: const Icon(Icons.lock_outline),
                label: Text(tr('Bloquear cofre')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VaultAutoLockPicker extends StatelessWidget {
  const VaultAutoLockPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final VaultAutoLock value;
  final ValueChanged<VaultAutoLock>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Semantics(
      label: tr('Tempo do bloqueio automático'),
      value: tr(value.label),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.resolve(const Color(0xFFF7F9FC)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppPalette.resolve(const Color(0xFFE1E6F0)),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<VaultAutoLock>(
            value: value,
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            borderRadius: BorderRadius.circular(14),
            style: AppTypography.itemTitle,
            items: [
              for (final option in VaultAutoLock.values)
                DropdownMenuItem(value: option, child: Text(tr(option.label))),
            ],
            onChanged: (next) {
              if (next != null) onChanged?.call(next);
            },
          ),
        ),
      ),
    );
  }
}
