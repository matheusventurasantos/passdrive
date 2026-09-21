import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'appearance_sheet.dart';
import 'package:flutter/material.dart' hide showModalBottomSheet;
import '../windows/adaptive_sheet.dart';
import '../windows/desktop_layout.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../vault/secure_clipboard.dart';
import '../vault/vault_access.dart';
import '../vault/vault_models.dart';
import '../vault/vault_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    this.vault,
    this.onAccess,
    this.onSync,
    this.onVaultChanged,
    this.onExportBackup,
    this.onRestoreBackup,
    super.key,
  });
  final VaultRepository? vault;
  final VoidCallback? onAccess;
  final VoidCallback? onSync;
  final VoidCallback? onVaultChanged;
  final Future<String?> Function()? onExportBackup;
  final Future<String?> Function()? onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return DesktopPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopHeading(tr('Ajustes')),
            _SettingsList(
              vault: vault,
              onAccess: onAccess,
              onSync: onSync,
              onVaultChanged: onVaultChanged,
              onExportBackup: onExportBackup,
              onRestoreBackup: onRestoreBackup,
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _SettingsHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                child: _SettingsList(
                  vault: vault,
                  onAccess: onAccess,
                  onSync: onSync,
                  onVaultChanged: onVaultChanged,
                  onExportBackup: onExportBackup,
                  onRestoreBackup: onRestoreBackup,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Center(
          child: Text(tr('Ajustes'), style: AppTypography.appPageTitle),
        ),
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    this.vault,
    this.onAccess,
    this.onSync,
    this.onVaultChanged,
    this.onExportBackup,
    this.onRestoreBackup,
  });
  final VaultRepository? vault;
  final VoidCallback? onAccess;
  final VoidCallback? onSync;
  final VoidCallback? onVaultChanged;
  final Future<String?> Function()? onExportBackup;
  final Future<String?> Function()? onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final items = <Widget>[
      _SettingsItem(
        icon: Icons.palette_outlined,
        title: tr('Aparência e idioma'),
        description: tr('Tema, tamanho da fonte e idioma'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const AppearanceSheet(),
        ),
      ),
      _SettingsItem(
        onTap: onAccess,
        icon: Icons.security_outlined,
        title: tr('Segurança'),
        description: tr('Senha do app, biometria e bloqueio automático'),
      ),
      _SettingsItem(
        icon: Icons.devices_outlined,
        title: tr('Sincronização e dispositivos'),
        description: tr('Gerencie conexões e aparelhos vinculados'),
        onTap: onSync,
      ),
      _SettingsItem(
        onTap: (onExportBackup == null || onRestoreBackup == null)
            ? onAccess
            : () => _showBackup(context, onExportBackup!, onRestoreBackup!),
        icon: Icons.backup_outlined,
        title: tr('Backup e recuperação'),
        description: tr('Importe, exporte e recupere seu cofre'),
      ),
      _SettingsItem(
        icon: Icons.visibility_outlined,
        title: tr('Privacidade'),
        description: tr('Controle o que pode ser visto e compartilhado'),
        onTap: vault == null
            ? () => _showInfo(
                context,
                title: tr('Privacidade'),
                message: tr(
                  'Seu cofre fica neste aparelho e é criptografado. A avaliação de força é local e não envia senhas para a internet. Senhas copiadas são limpas da área de transferência após 1 minuto.',
                ),
              )
            : () => _showPrivacy(context, vault!, onVaultChanged),
      ),
      _SettingsItem(
        icon: Icons.info_outline,
        title: tr('Sobre'),
        description: tr('Versão, política e informações do app'),
        onTap: () => _showAbout(context),
      ),
    ];
    if (isWindowsDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 16),
            items[index],
          ],
        ],
      );
    }
    return Column(children: items);
  }
}

void _showAbout(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AboutSheet(),
  );
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Não foi possível abrir este endereço.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 38,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(tr('Sobre o PassDrive'), style: AppTypography.sectionTitle),
              const SizedBox(height: 8),
              Text(
                tr('Versão 1.0.2'),
                style: AppTypography.secondary.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Um cofre local criptografado para organizar e proteger suas credenciais.',
                ),
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 18),
              _AboutLink(
                icon: Icons.mail_outline_rounded,
                title: tr('Contato'),
                detail: 'contato@passdrive.online',
                onTap: () => _open(
                  context,
                  Uri(scheme: 'mailto', path: 'contato@passdrive.online'),
                ),
              ),
              _AboutLink(
                icon: Icons.language_rounded,
                title: tr('Site'),
                detail: 'passdrive.online',
                onTap: () =>
                    _open(context, Uri.parse('https://passdrive.online')),
              ),
              _AboutLink(
                icon: Icons.privacy_tip_outlined,
                title: tr('Política de privacidade'),
                onTap: () => _open(
                  context,
                  Uri.parse('https://passdrive.online/privacy.html'),
                ),
              ),
              _AboutLink(
                icon: Icons.description_outlined,
                title: tr('Termos de uso'),
                onTap: () => _open(
                  context,
                  Uri.parse('https://passdrive.online/terms.html'),
                ),
              ),
              _AboutLink(
                icon: Icons.code_rounded,
                title: tr('Código-fonte'),
                detail: 'GitHub',
                onTap: () => _open(
                  context,
                  Uri.parse(
                    'https://github.com/matheusventurasantos/passdrive',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: AppPalette.resolve(const Color(0xFFD6E0F2)),
                  ),
                ),
                child: Text(tr('Fechar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.title,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.paleBlueStrong,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: AppColors.blue, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.itemTitle),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(detail!, style: AppTypography.secondary),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              color: Color(0xFF8993A8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

void _showBackup(
  BuildContext context,
  Future<String?> Function() onExport,
  Future<String?> Function() onRestore,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BackupSheet(onExport: onExport, onRestore: onRestore),
  );
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({required this.onExport, required this.onRestore});
  final Future<String?> Function() onExport;
  final Future<String?> Function() onRestore;
  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  bool _busy = false;
  bool _confirmRestore = false;
  bool _restoreCompleted = false;
  String? _message;

  Future<void> _run(
    Future<String?> Function() action, {
    bool completesRestore = false,
  }) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted && message != null) {
        setState(() {
          _message = message;
          if (completesRestore) {
            _restoreCompleted = true;
            _confirmRestore = false;
          }
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = tr('Não foi possível concluir esta operação.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppPalette.watch(
    context,
    () => SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 38,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_restoreCompleted)
                const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF36BD78),
                    size: 52,
                  ),
                ),
              if (_restoreCompleted) const SizedBox(height: 14),
              Text(
                _restoreCompleted
                    ? tr('Backup restaurado')
                    : _confirmRestore
                    ? tr('Restaurar backup?')
                    : tr('Backup e recuperação'),
                textAlign: _restoreCompleted
                    ? TextAlign.center
                    : TextAlign.start,
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: 10),
              Text(
                _restoreCompleted
                    ? tr(
                        'O conteúdo do cofre foi substituído pelo backup selecionado.',
                      )
                    : _confirmRestore
                    ? tr(
                        'O conteúdo atual do cofre será substituído pelo backup selecionado.',
                      )
                    : tr(
                        'O backup permanece criptografado e só pode ser restaurado neste mesmo cofre.',
                      ),
                textAlign: _restoreCompleted
                    ? TextAlign.center
                    : TextAlign.start,
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 22),
              if (_restoreCompleted) ...[
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(tr('Concluído')),
                ),
              ] else if (_confirmRestore) ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(widget.onRestore, completesRestore: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.resolve(
                      const Color(0xFFE65353),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(
                    _busy ? 'Restaurando...' : tr('Selecionar e restaurar'),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _confirmRestore = false),
                  child: Text(tr('Cancelar')),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onExport),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_busy ? 'Exportando...' : tr('Exportar backup')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _confirmRestore = true),
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(tr('Restaurar backup')),
                ),
              ],
              if (_message != null && !_restoreCompleted)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!, style: AppTypography.secondary),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showPrivacy(
  BuildContext context,
  VaultRepository vault,
  VoidCallback? onVaultChanged,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _PrivacySettingsSheet(vault: vault, onVaultChanged: onVaultChanged),
  );
}

void _showInfo(
  BuildContext context, {
  required String title,
  required String message,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SettingsInfoSheet(title: title, message: message),
  );
}

class _SettingsInfoSheet extends StatelessWidget {
  const _SettingsInfoSheet({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 38,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: AppTypography.sectionTitle),
              const SizedBox(height: 12),
              Text(message, style: AppTypography.secondary),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(tr('Entendi')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacySettingsSheet extends StatefulWidget {
  const _PrivacySettingsSheet({required this.vault, this.onVaultChanged});

  final VaultRepository vault;
  final VoidCallback? onVaultChanged;

  @override
  State<_PrivacySettingsSheet> createState() => _PrivacySettingsSheetState();
}

class _PrivacySettingsSheetState extends State<_PrivacySettingsSheet> {
  late VaultClipboardClear _selected;
  late bool _allowScreenCapture;
  bool _clipboardExpanded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.vault.clipboardClear;
    _allowScreenCapture = widget.vault.allowScreenCapture;
  }

  Future<void> _select(VaultClipboardClear value) async {
    if (_saving || value == _selected) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.vault.setClipboardClear(value);
      SecureClipboard.configure(value.duration);
      if (!mounted) return;
      setState(() {
        _selected = value;
        _clipboardExpanded = false;
      });
      widget.onVaultChanged?.call();
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr('Não foi possível salvar esta preferência.'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setScreenCaptureAllowed(bool value) async {
    if (_saving || value == _allowScreenCapture) return;
    if (!value && !await _authorizeScreenCaptureDisable()) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VaultAccess.setScreenCaptureAllowed(value);
      await widget.vault.setAllowScreenCapture(value);
      if (!mounted) return;
      setState(() => _allowScreenCapture = value);
      widget.onVaultChanged?.call();
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _error = tr(
            'Reinicie o app para concluir a alteração de captura de tela.',
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'cancelled'
              ? tr('A alteração foi cancelada.')
              : tr('Não foi possível atualizar a proteção de captura de tela.'),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr('Não foi possível salvar esta preferência.'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _authorizeScreenCaptureDisable() async {
    try {
      if (await VaultAccess.enabled()) {
        final authorized = await widget.vault.verifyBiometrics();
        if (!authorized && mounted) {
          setState(
            () => _error = tr('Não foi possível confirmar sua biometria.'),
          );
        }
        return authorized;
      }
    } on PlatformException catch (error) {
      if (mounted && error.code != 'cancelled') {
        setState(
          () => _error = tr('Não foi possível confirmar sua biometria.'),
        );
      }
      return false;
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr('Não foi possível confirmar sua biometria.'),
        );
      }
      return false;
    }
    if (!mounted) return false;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _PrivacyAuthorizationSheet(vault: widget.vault),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: isWindowsDesktop ? 0 : 38,
                    height: isWindowsDesktop ? 0 : 4,
                    decoration: BoxDecoration(
                      color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(tr('Privacidade'), style: AppTypography.sectionTitle),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'O cofre e a avaliação de senhas funcionam somente neste aparelho.',
                  ),
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: 24),
                InkWell(
                  onTap: _saving
                      ? null
                      : () => setState(
                          () => _clipboardExpanded = !_clipboardExpanded,
                        ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Limpar área de transferência'),
                                style: AppTypography.itemTitle,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr('Remove senhas copiadas automaticamente.'),
                                style: AppTypography.secondary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          tr(_selected.label),
                          style: AppTypography.secondary,
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _clipboardExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: !_clipboardExpanded
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            children: VaultClipboardClear.values.map((value) {
                              final selected = value == _selected;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                dense: true,
                                title: Text(
                                  tr(value.label),
                                  style: AppTypography.itemTitle,
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: AppColors.blue,
                                      )
                                    : null,
                                onTap: _saving ? null : () => _select(value),
                              );
                            }).toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('Permitir captura de tela'),
                    style: AppTypography.itemTitle,
                  ),
                  subtitle: Text(
                    tr(
                      'Desative para impedir capturas e visualização recente.',
                    ),
                    style: AppTypography.secondary,
                  ),
                  value: _allowScreenCapture,
                  onChanged: _saving ? null : _setScreenCaptureAllowed,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: AppTypography.secondary.copyWith(
                      color: AppPalette.resolve(const Color(0xFFD84A4A)),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(_saving ? 'Salvando...' : tr('Concluído')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyAuthorizationSheet extends StatefulWidget {
  const _PrivacyAuthorizationSheet({required this.vault});

  final VaultRepository vault;

  @override
  State<_PrivacyAuthorizationSheet> createState() =>
      _PrivacyAuthorizationSheetState();
}

class _PrivacyAuthorizationSheetState
    extends State<_PrivacyAuthorizationSheet> {
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirmPassword() async {
    if (_busy) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = tr('Digite sua senha mestra para continuar.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final valid = await widget.vault.verifyMasterPassword(password);
    _passwordController.clear();
    if (!mounted) return;
    if (valid) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = tr('A senha mestra está incorreta.');
      });
    }
  }

  Future<void> _confirmRecoveryKey() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await VaultAccess.pick();
      if (bytes == null) return;
      final valid = await widget.vault.verifyRecoveryKey(bytes);
      if (!mounted) return;
      if (valid) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = tr('Esta chave não pertence a este cofre.'));
      }
    } on Object {
      if (mounted) {
        setState(() => _error = tr('Não foi possível ler a chave-mestra.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: isWindowsDesktop ? 0 : 38,
                    height: isWindowsDesktop ? 0 : 4,
                    decoration: BoxDecoration(
                      color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('Confirmar identidade'),
                  style: AppTypography.sectionTitle,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Confirme sua senha ou chave-mestra para bloquear capturas de tela.',
                  ),
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: tr('Senha mestra'),
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible
                          ? tr('Ocultar senha')
                          : tr('Exibir senha'),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _confirmPassword(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTypography.secondary.copyWith(
                      color: AppPalette.resolve(const Color(0xFFD84A4A)),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _confirmPassword,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(_busy ? 'Confirmando...' : tr('Confirmar')),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _confirmRecoveryKey,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(tr('Usar chave-mestra')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return Material(
        color: AppPalette.resolve(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: desktopLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.paleBlueStrong,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.blue, size: 27),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: desktopMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: desktopMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppPalette.resolve(const Color(0xFFF0F2F6)),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.paleBlueStrong,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: AppColors.blue, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: AppTypography.itemTitle),
                    const SizedBox(height: 5),
                    Text(description, style: AppTypography.secondary),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF8993A8),
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
