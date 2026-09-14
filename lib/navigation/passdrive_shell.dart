import 'dart:async';

import 'package:flutter/material.dart' hide showModalBottomSheet;
import 'package:flutter/services.dart';
import '../windows/adaptive_sheet.dart';

import '../generator/password_generator_page.dart';
import '../health/password_health_page.dart';
import '../health/breach_check.dart';
import '../passwords/passwords_page.dart';
import '../settings/settings_page.dart';
import '../vault/vault_repository.dart';
import '../vault/vault_access.dart';
import '../vault/vault_lifecycle_lock.dart';
import '../vault/vault_access_sheet.dart';
import '../vault/vault_gate_page.dart';
import '../vault/master_password_sheet.dart';
import '../vault/recovery_key_confirmation_sheet.dart';
import '../vault/secure_clipboard.dart';
import '../windows/desktop_layout.dart';
import '../windows/desktop_sidebar.dart';
import '../sync/mobile_sync.dart';
import '../sync/sync_devices_sheet.dart';
import '../sync/sync_protocol.dart';
import '../sync/sync_store.dart';
import '../autofill/autofill_bridge.dart';

class PassDriveShell extends StatefulWidget {
  const PassDriveShell({this.vault, this.pendingAutofillSave, super.key});

  final VaultRepository? vault;
  final AutofillSaveCandidate? pendingAutofillSave;

  @override
  State<PassDriveShell> createState() => _PassDriveShellState();
}

class _PassDriveShellState extends State<PassDriveShell>
    with WidgetsBindingObserver {
  static const _immediateLockGrace = Duration(milliseconds: 700);
  bool _needsLock = false;
  bool _locking = false;
  DateTime? _inactiveSince;
  final _lifecycleLock = VaultLifecycleLockTracker();
  DateTime? _metricsChangedAt;
  bool? _isLandscape;
  Timer? _lockTimer;
  late final BreachCheckController _breachCheck;
  MobileSync? _sync;
  final _passwordsKey = GlobalKey<PasswordsPageState>();
  bool _syncMenuOpen = false;
  AutofillSaveCandidate? _pendingAutofillSave;

  void _openSync() async {
    final sync = _sync;
    if (sync == null || _syncMenuOpen || _locking) return;
    _syncMenuOpen = true;
    try {
      await openSyncDevices(context, sync);
    } finally {
      _syncMenuOpen = false;
      _showPendingPairing();
    }
  }

  void _offerPairing(LanPeer peer) {
    _showPendingPairing();
  }

  Future<void> _showPendingPairing() async {
    final sync = _sync;
    final peer = sync?.incomingPairing;
    if (peer == null ||
        sync == null ||
        !mounted ||
        _locking ||
        _syncMenuOpen ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    sync.incomingPairing = null;
    _syncMenuOpen = true;
    try {
      await syncSheet<void>(
        context,
        PairingApprovalSheet(sync: sync, peer: peer),
      );
    } finally {
      _syncMenuOpen = false;
    }
  }

  Future<bool> _remoteAction(RemoteAction action, String computer) async {
    if (!mounted ||
        _locking ||
        _syncMenuOpen ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    _syncMenuOpen = true;
    try {
      final label = switch (action.kind) {
        RemoteActionKind.addAccount => 'Adicionar conta',
        RemoteActionKind.addService => 'Adicionar serviço',
        RemoteActionKind.editAccount => 'Editar conta',
        RemoteActionKind.editService => 'Editar serviço',
        RemoteActionKind.deleteAccount => 'Excluir conta',
        RemoteActionKind.deleteService => 'Excluir serviço',
        RemoteActionKind.favoriteAccount => 'Alterar favorito da conta',
        RemoteActionKind.favoriteService => 'Alterar favorito do serviço',
      };
      if (!await syncConfirm(
        context,
        label,
        '$computer solicitou esta ação. Continue aqui no celular para autorizar.',
        confirm: 'Continuar no celular',
      )) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || _locking) return false;
      _selectPage(1);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _locking) return false;
      return await _passwordsKey.currentState?.handleRemoteAction(action) ??
          false;
    } finally {
      _syncMenuOpen = false;
    }
  }

  @override
  void didChangeMetrics() {
    // Android may briefly pause the activity while applying a rotation. This
    // is not the user leaving the app, so it must not trigger auto-lock.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final isLandscape = view.physicalSize.width > view.physicalSize.height;
    if (_isLandscape != isLandscape) {
      _isLandscape = isLandscape;
      _metricsChangedAt = DateTime.now();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final transition = _lifecycleLock.update(state, DateTime.now());
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showPendingPairing(),
      );
    }
    if (widget.vault == null) return;
    // `inactive` is recorded but is treated as a confirmed overlay only when
    // capture is disabled. It also occurs during short system interactions
    // while the activity is still visible, including the Android screenshot
    // flow. `hidden`/`paused` confirm that the surface left the foreground.
    // When capture is disabled there is no screenshot exception to preserve,
    // so a sustained inactive overlay also starts the configured lock.
    if (state == AppLifecycleState.inactive &&
        widget.vault?.allowScreenCapture != true &&
        !VaultAccess.busy &&
        !_isRecentMetricsChange) {
      _scheduleLock(startedAt: transition.awaySince);
    }
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        !VaultAccess.busy &&
        !_isRecentMetricsChange) {
      _scheduleLock(startedAt: transition.awaySince);
    }
    if (state == AppLifecycleState.detached && !VaultAccess.busy) {
      // The process is being detached; there is no safe reason to keep an
      // unlocked repository alive even if the configured timeout is longer.
      unawaited(_lock(fromLifecycle: true));
    }
    if (state == AppLifecycleState.resumed && _needsLock) {
      final seconds = widget.vault?.autoLock.seconds;
      final elapsed = transition.confirmedBackground && _inactiveSince != null
          ? DateTime.now().difference(_inactiveSince!)
          : Duration.zero;
      final timeout = seconds == 0
          ? _immediateLockGrace
          : seconds == null
          ? null
          : Duration(seconds: seconds);
      if (transition.confirmedBackground &&
          timeout != null &&
          elapsed >= timeout) {
        unawaited(_lock(fromLifecycle: true));
      } else {
        _cancelScheduledLock();
      }
    } else if (state == AppLifecycleState.resumed && !VaultAccess.busy) {
      _beginBreachSession();
    }
  }

  bool get _isRecentMetricsChange =>
      _metricsChangedAt != null &&
      DateTime.now().difference(_metricsChangedAt!) <
          const Duration(milliseconds: 900);

  void _scheduleLock({DateTime? startedAt}) {
    final seconds = widget.vault?.autoLock.seconds;
    _lockTimer?.cancel();
    if (seconds == null) {
      _needsLock = false;
      _inactiveSince = null;
      return;
    }
    _needsLock = true;
    _inactiveSince ??= startedAt ?? DateTime.now();
    final timeout = seconds == 0
        ? _immediateLockGrace
        : Duration(seconds: seconds);
    final elapsed = DateTime.now().difference(_inactiveSince!);
    final remaining = timeout > elapsed ? timeout - elapsed : Duration.zero;
    _lockTimer = Timer(remaining, () => _lock(fromLifecycle: true));
  }

  void _cancelScheduledLock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _needsLock = false;
    _inactiveSince = null;
  }

  void _beginBreachSession() {
    final vault = widget.vault;
    if (vault == null) return;
    _breachCheck.beginSession(vault.services, cachedChecks: vault.breachChecks);
  }

  Future<void> _lock({bool fromLifecycle = false}) async {
    if (!mounted || _locking) return;
    setState(() => _locking = true);
    _cancelScheduledLock();
    if (fromLifecycle) {
      SecureClipboard.scheduleClearAfterFocusLoss();
    } else {
      await SecureClipboard.clear();
    }
    try {
      await AutofillBridge.cancel();
    } on Object {
      // A stale Autofill request must not prevent the lock.
    }
    try {
      await AutofillBridge.clearCache();
    } on Object {
      // The repository still closes below; the native cache is best-effort.
    }
    try {
      await widget.vault?.close();
    } catch (_) {
      // Closing is fail-closed: the repository clears its snapshot even if a
      // secondary sync callback fails, so the UI must still reach the gate.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const VaultGatePage()),
      (_) => false,
    );
  }

  void _openAccess() {
    final vault = widget.vault;
    if (vault == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VaultAccessSheet(
        vault: vault,
        onLock: _lock,
        onDownloadRecoveryKey: _downloadRecoveryKeyFromAccess,
        onAutoLockChanged: (_) => _cancelScheduledLock(),
        onChangeMasterPassword: _changeMasterPasswordFromAccess,
      ),
    );
  }

  void _changeMasterPasswordFromAccess() {
    if (!mounted) return;
    Navigator.of(context).pop();
    Future<void>.delayed(
      const Duration(milliseconds: 220),
      _openMasterPassword,
    );
  }

  Future<void> _openMasterPassword() async {
    final vault = widget.vault;
    if (vault == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MasterPasswordSheet(vault: vault),
    );
    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) _openAccess();
    }
  }

  Future<void> _downloadRecoveryKeyFromAccess() async {
    final vault = widget.vault;
    if (vault == null || !mounted) return;

    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RecoveryKeyConfirmationSheet(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    if (confirmed == true) {
      final saved = await vault.downloadRecoveryKey();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Chave-mestra salva no local escolhido.'
                  : 'Download cancelado. Você pode tentar novamente.',
              style: const TextStyle(fontFamily: 'Kumbh Sans'),
            ),
            duration: const Duration(milliseconds: 1800),
          ),
        );
      }
    }

    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) _openAccess();
    }
  }

  Future<String?> _exportBackup() async {
    final vault = widget.vault;
    if (vault == null) return null;
    final saved = await vault.exportBackup();
    return saved ? 'Backup criptografado salvo no local escolhido.' : null;
  }

  Future<String?> _restoreBackup() async {
    final vault = widget.vault;
    if (vault == null) return null;
    final bytes = await VaultAccess.pick(maxBytes: VaultBackupFile.maxBytes);
    if (bytes == null) return null;
    await vault.restoreBackup(bytes);
    if (mounted) setState(() {});
    return 'Backup restaurado com sucesso.';
  }

  late final PageController _pageController;
  int _currentIndex = 0;
  String? _healthFilter;

  @override
  void initState() {
    super.initState();
    AutofillBridge.pending.addListener(_fillPendingAutofill);
    AutofillBridge.pendingSaveCaptureId.addListener(_receiveAutofillSave);
    _pendingAutofillSave = widget.pendingAutofillSave;
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _breachCheck = BreachCheckController(
      onPersist: (checks) async {
        final vault = widget.vault;
        if (vault == null) return;
        try {
          await vault.setBreachChecks(checks);
        } on Object {
          // A lock can close the database while the network check finishes.
        }
      },
    );
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    _isLandscape = view.physicalSize.width > view.physicalSize.height;
    final vault = widget.vault;
    if (vault != null && !isWindowsDesktop) {
      final sync = MobileSync(
        readSnapshot: () => vault.snapshot,
        onAction: _remoteAction,
        onPairing: _offerPairing,
      );
      _sync = sync;
      sync.addListener(_showPendingPairing);
      vault.changes.addListener(sync.publish);
      vault.beforeClose = sync.lock;
      unawaited(sync.start());
    }
    if (vault != null) {
      vault.changes.addListener(_cacheAutofillSnapshot);
      unawaited(AutofillBridge.cacheSnapshot(vault.snapshot));
    }
    SecureClipboard.configure(widget.vault?.clipboardClear.duration);
    if (widget.vault != null) _beginBreachSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vault = widget.vault;
      if (vault != null) {
        VaultAccess.setScreenCaptureAllowed(
          vault.allowScreenCapture,
        ).catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    AutofillBridge.pending.removeListener(_fillPendingAutofill);
    AutofillBridge.pendingSaveCaptureId.removeListener(_receiveAutofillSave);
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    _pageController.dispose();
    _breachCheck.dispose();
    final sync = _sync;
    if (sync != null) {
      sync.removeListener(_showPendingPairing);
      widget.vault?.changes.removeListener(sync.publish);
      sync.dispose();
    }
    widget.vault?.changes.removeListener(_cacheAutofillSnapshot);
    unawaited(AutofillBridge.clearCache());
    if (!_locking) widget.vault?.close();
    super.dispose();
  }

  void _fillPendingAutofill() {
    final vault = widget.vault;
    if (vault == null || AutofillBridge.pending.value == null) return;
    unawaited(AutofillBridge.fillFromSnapshot(vault.snapshot));
  }

  void _receiveAutofillSave() {
    final vault = widget.vault;
    if (vault == null || _locking) return;
    unawaited(_consumeAutofillSave());
  }

  Future<void> _consumeAutofillSave() async {
    final candidate = await AutofillBridge.consumePendingSaveCandidate();
    if (!mounted || candidate == null) return;
    setState(() => _pendingAutofillSave = candidate);
  }

  void _clearAutofillSave() {
    if (mounted) setState(() => _pendingAutofillSave = null);
  }

  void _cacheAutofillSnapshot() {
    final vault = widget.vault;
    if (vault != null) {
      unawaited(AutofillBridge.cacheSnapshot(vault.snapshot));
    }
  }

  void _selectPage(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
    _pageController.jumpToPage(index);
  }

  void _openHealthFilter(String? filter) {
    if (!mounted) return;
    setState(() => _healthFilter = filter);
    _selectPage(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_locking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Icon(Icons.lock_outline, color: Color(0xFF4862E0), size: 34),
        ),
      );
    }
    final pages = PageView(
      controller: _pageController,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      physics: isWindowsDesktop
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      children: [
        PasswordHealthPage(
          showBottomNavigation: false,
          vault: widget.vault,
          onOpenPasswords: _openHealthFilter,
          breachCheck: _breachCheck,
        ),
        PasswordsPage(
          key: _passwordsKey,
          showBottomNavigation: false,
          vault: widget.vault,
          healthFilter: _healthFilter,
          breachCheck: _breachCheck,
          pendingAutofillSave: _pendingAutofillSave,
          onAutofillSaveHandled: _clearAutofillSave,
          onVaultChanged: () {
            final vault = widget.vault;
            if (vault != null) _breachCheck.refresh(vault.services);
            if (mounted) setState(() {});
          },
        ),
        const PasswordGeneratorPage(showBottomNavigation: false),
        SettingsPage(
          onSync: _openSync,
          vault: widget.vault,
          onAccess: _openAccess,
          onVaultChanged: () {
            final vault = widget.vault;
            SecureClipboard.configure(vault?.clipboardClear.duration);
            if (vault != null) {
              VaultAccess.setScreenCaptureAllowed(
                vault.allowScreenCapture,
              ).catchError((_) {});
            }
            if (mounted) setState(() {});
          },
          onExportBackup: _exportBackup,
          onRestoreBackup: _restoreBackup,
        ),
      ],
    );
    if (isWindowsDesktop) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
              _selectPage(0),
          const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
              _selectPage(1),
          const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
              _selectPage(2),
          const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
              _selectPage(3),
          if (widget.vault != null)
            const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                _lock,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                DesktopSidebar(
                  selectedIndex: _currentIndex,
                  onSelected: _selectPage,
                  onLock: widget.vault == null ? null : _lock,
                ),
                Expanded(child: pages),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: pages,
      bottomNavigationBar: SafeArea(
        top: false,
        child: _ShellBottomNavigation(
          selectedIndex: _currentIndex,
          onSelected: _selectPage,
        ),
      ),
    );
  }
}

class _ShellBottomNavigation extends StatelessWidget {
  const _ShellBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F3F8))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ShellNavigationItem(
              icon: Icons.home_outlined,
              label: 'Início',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
          ),
          Expanded(
            child: _ShellNavigationItem(
              icon: Icons.lock_outline,
              label: 'Senhas',
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
          ),
          Expanded(
            child: _ShellNavigationItem(
              icon: Icons.key_outlined,
              label: 'Gerador',
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
          ),
          Expanded(
            child: _ShellNavigationItem(
              icon: Icons.settings_outlined,
              label: 'Ajustes',
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellNavigationItem extends StatelessWidget {
  const _ShellNavigationItem({
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
    final color = selected ? const Color(0xFF347BFF) : const Color(0xFF9AA3B5);

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
