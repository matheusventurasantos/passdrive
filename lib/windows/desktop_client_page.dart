import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../generator/password_generator_page.dart';
import '../health/password_health_page.dart';
import '../passwords/passwords_page.dart';
import '../sync/desktop_sync.dart';
import '../sync/sync_protocol.dart';
import '../sync/sync_status.dart';
import '../sync/sync_store.dart';
import '../theme/app_colors.dart';
import '../vault/secure_clipboard.dart';
import 'desktop_layout.dart';
import 'desktop_sidebar.dart';

class DesktopClientPage extends StatefulWidget {
  const DesktopClientPage({this.controller, super.key});
  final DesktopSync? controller;
  @override
  State<DesktopClientPage> createState() => _DesktopClientPageState();
}

class _DesktopClientPageState extends State<DesktopClientPage>
    with WidgetsBindingObserver {
  late DesktopSync sync;
  int index = 0;
  String? filter;
  bool _wasConnected = false;
  bool _lifecycleLocking = false;
  bool _clipboardGraceOnDisconnect = false;
  int? _viewIdentity;
  Timer? _syncPulse;
  Timer? _ticketExpiryTimer;
  DateTime? _ticketExpiryAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync = widget.controller ?? DesktopSync();
    _wasConnected = sync.connected;
    sync.addListener(_changed);
    _scheduleTicketExpiry();
    if (widget.controller == null) unawaited(sync.start());
  }

  void _changed() {
    if (!mounted) return;
    _scheduleTicketExpiry();
    desktopConnectionStatus.value = sync.status;
    desktopConnectionOnline.value = sync.connected;
    final viewIdentity = sync.snapshot == null
        ? null
        : identityHashCode(sync.snapshot);
    if (viewIdentity != _viewIdentity || sync.syncing) {
      _viewIdentity = viewIdentity;
      _syncPulse?.cancel();
      desktopConnectionBusy.value = sync.connected || sync.syncing;
      _syncPulse = Timer(const Duration(milliseconds: 450), () {
        desktopConnectionBusy.value = mounted && sync.syncing;
      });
    }
    if (_wasConnected && !sync.connected) {
      // Close secret details too, not just the underlying page.
      Navigator.of(context).popUntil((route) => route.isFirst);
      if (!_clipboardGraceOnDisconnect) {
        unawaited(SecureClipboard.clear());
      }
      _clipboardGraceOnDisconnect = false;
      index = 0;
      filter = null;
    }
    _wasConnected = sync.connected;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncPulse?.cancel();
    _ticketExpiryTimer?.cancel();
    sync.removeListener(_changed);
    if (widget.controller == null) sync.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleLocking = false;
      return;
    }
    if (!sync.connected || _lifecycleLocking) return;

    if (state == AppLifecycleState.inactive) {
      _lockForLifecycle();
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _lockForLifecycle();
    }
  }

  void _lockForLifecycle() {
    if (!mounted || _lifecycleLocking || !sync.connected) return;
    _lifecycleLocking = true;
    // Keep a just-copied value available long enough to paste after switching
    // to the target application. The value is still cleared automatically.
    _clipboardGraceOnDisconnect = true;
    SecureClipboard.scheduleClearAfterFocusLoss();
    unawaited(
      sync.disconnect(
        forget: true,
        message: 'Sessão encerrada. Sincronize novamente.',
      ),
    );
  }

  Future<void> _request(RemoteAction action) async {
    if (!sync.connected) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Continue pelo celular para autorizar e preencher os dados.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
    final result = await sync.request(action);
    if (mounted && sync.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  void _select(int value) {
    if (sync.connected) setState(() => index = value);
  }

  void _lock() {
    _lifecycleLocking = true;
    unawaited(
      sync.disconnect(
        forget: true,
        message: 'Cofre bloqueado. Sincronize novamente.',
      ),
    );
  }

  void _scheduleTicketExpiry() {
    final expiresAt = sync.ticket?.expiresAt;
    if (expiresAt == _ticketExpiryAt &&
        (_ticketExpiryTimer?.isActive ?? false)) {
      return;
    }
    _ticketExpiryTimer?.cancel();
    _ticketExpiryAt = expiresAt;
    if (expiresAt == null) {
      _ticketExpiryTimer = null;
      return;
    }
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _ticketExpiryTimer = null;
      _regenerateExpiredTicket();
      return;
    }
    _ticketExpiryTimer = Timer(remaining, _regenerateExpiredTicket);
  }

  void _regenerateExpiredTicket() {
    _ticketExpiryTimer = null;
    _ticketExpiryAt = null;
    if (!mounted || sync.grant != null || sync.ticket?.valid() == true) return;
    sync.newTicket();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          _select(0),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          _select(1),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
          _select(2),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
          sync.refresh(),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): _lock,
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: desktopBackground,
        body: sync.connected
            ? Row(
                children: [
                  DesktopSidebar(
                    viewer: true,
                    selectedIndex: index,
                    onSelected: _select,
                    onLock: _lock,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      children: [
                        TickerMode(
                          enabled: index == 0,
                          child: PasswordHealthPage(
                            showBottomNavigation: false,
                            remoteSnapshot: sync.snapshot,
                            onOpenPasswords: (value) => setState(() {
                              filter = value;
                              index = 1;
                            }),
                          ),
                        ),
                        TickerMode(
                          enabled: index == 1,
                          child: PasswordsPage(
                            showBottomNavigation: false,
                            remoteSnapshot: sync.snapshot,
                            healthFilter: filter,
                            onRemoteAction: _request,
                          ),
                        ),
                        TickerMode(
                          enabled: index == 2,
                          child: const PasswordGeneratorPage(
                            showBottomNavigation: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : _connection(context),
      ),
    ),
  );

  Widget _connection(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Conectar ao celular',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Abra Sincronização e dispositivos nos ajustes do PassDrive. Os dois aparelhos precisam estar na mesma rede.',
              style: TextStyle(fontSize: 16, color: desktopMuted),
            ),
            const SizedBox(height: 28),
            if (sync.grant != null) ...[
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.phonelink_rounded,
                      size: 40,
                      color: AppColors.blue,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      sync.grant!.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Desbloqueie o cofre no celular para retomar a conexão. Nenhuma senha fica salva neste computador.',
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: _lock,
                      child: const Text('Conectar outro dispositivo'),
                    ),
                  ],
                ),
              ),
            ] else
              _panel(
                LayoutBuilder(
                  builder: (context, constraints) {
                    final qr = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Escaneie o QR Code',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (sync.ticket?.valid() == true)
                          Semantics(
                            label: 'QR Code de pareamento temporário',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  QrImageView(
                                    data: sync.ticket!.qr(sync.preferences.id),
                                    size: 208,
                                    backgroundColor: Colors.white,
                                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Colors.black,
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Container(
                                    width: 42,
                                    height: 42,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/branding/logo.svg',
                                      colorFilter: const ColorFilter.mode(
                                        Colors.black,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            height: 208,
                            child: Center(child: Text('QR Code expirado')),
                          ),
                        const SizedBox(height: 12),
                        const Text(
                          'Use o app PassDrive no celular para ler o código.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        const _QrPairingSteps(),
                      ],
                    );
                    final detect =
                        sync.target.isNotEmpty && sync.ticket?.valid() == true
                        ? _manualCodeView(sync)
                        : _pairingInstructions(sync);
                    return constraints.maxWidth >= 680
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: qr),
                              const SizedBox(width: 24),
                              Expanded(child: detect),
                            ],
                          )
                        : Column(
                            children: [qr, const SizedBox(height: 20), detect],
                          );
                  },
                ),
              ),
            const SizedBox(height: 18),
            _waitingStatus(sync),
            const SizedBox(height: 10),
            const Text(
              'O celular autoriza o acesso. O computador apenas exibe o cofre durante a conexão.',
              style: TextStyle(fontSize: 14, color: desktopMuted),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: desktopLine),
    ),
    child: child,
  );

  Widget _pairingInstructions(DesktopSync sync) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: _searchingInstructions(sync),
    ),
  );

  Widget _searchingInstructions(DesktopSync sync) => Column(
    key: const ValueKey('pairing-searching'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _detectDeviceAction(sync),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: sync.phones.isNotEmpty
            ? Column(
                key: const ValueKey('searching-results'),
                children: [
                  for (final phone in sync.phones)
                    _DiscoveredDeviceTile(
                      key: ValueKey(phone.id),
                      phone: phone,
                      onTap: () => sync.selectPhone(phone),
                    ),
                ],
              )
            : sync.error != null
            ? const _DeviceSearchError(
                key: ValueKey('searching-error'),
                message: 'Confira a rede local e tente novamente.',
              )
            : sync.searching
            ? const _DeviceSearchPlaceholder(
                key: ValueKey('searching-placeholder'),
              )
            : const SizedBox.shrink(key: ValueKey('searching-idle')),
      ),
    ],
  );

  Widget _detectDeviceAction(DesktopSync sync) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Ou detectar automaticamente',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Encontre o celular na rede e confirme o código por lá.',
        style: TextStyle(color: desktopMuted),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: sync.searching ? null : sync.detect,
        icon: const Icon(Icons.radar_rounded),
        label: Text(
          sync.searching
              ? 'Procurando celular…'
              : sync.error != null
              ? 'Tentar novamente'
              : 'Procurar celular',
        ),
      ),
    ],
  );

  Widget _manualCodeView(DesktopSync sync) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Detectar dispositivo',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 16),
      const Text('Digite no celular o código abaixo:'),
      const SizedBox(height: 18),
      Center(
        child: SelectableText(
          sync.ticket!.code,
          style: const TextStyle(
            fontSize: 48,
            letterSpacing: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.blue,
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Expira em 2 minutos. Cada código aceita até 3 tentativas.'),
    ],
  );

  Widget _waitingStatus(DesktopSync sync) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: desktopLine),
    ),
    child: const Row(
      children: [
        SizedBox.square(
          dimension: 19,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.blue,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Aguardando sincronização',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.navy,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DeviceSearchError extends StatelessWidget {
  const _DeviceSearchError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _deviceSearchCardHeight(context),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5D0D0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE1E1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppColors.weak,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nenhum dispositivo encontrado',
                  style: TextStyle(
                    color: AppColors.weak,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, color: AppColors.weak),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _QrPairingSteps extends StatelessWidget {
  const _QrPairingSteps();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QrPairingStep(
          number: '1',
          text: 'Acesse a aba ajustes > Sincronização > Ler QR CODE',
        ),
        SizedBox(height: 8),
        _QrPairingStep(
          number: '2',
          text: 'Aponte a câmera para o QR CODE exibido',
        ),
        SizedBox(height: 8),
        _QrPairingStep(number: '3', text: 'Confirme e configure o dispositivo'),
      ],
    ),
  );
}

class _QrPairingStep extends StatelessWidget {
  const _QrPairingStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE8F0FF),
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.blue,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: AppColors.navy,
          ),
        ),
      ),
    ],
  );
}

double _deviceSearchCardHeight(BuildContext context) =>
    (72 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5)).toDouble();

class _DeviceSearchPlaceholder extends StatefulWidget {
  const _DeviceSearchPlaceholder({super.key});

  @override
  State<_DeviceSearchPlaceholder> createState() =>
      _DeviceSearchPlaceholderState();
}

class _DeviceSearchPlaceholderState extends State<_DeviceSearchPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Procurando dispositivos na rede local',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: _deviceSearchCardHeight(context),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F5FA),
                border: Border.all(color: desktopLine),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE4E8F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.smartphone_rounded,
                        color: desktopMuted,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Procurando dispositivo',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Verificando a rede local…',
                            style: TextStyle(fontSize: 13, color: desktopMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (context, child) => Align(
                  alignment: Alignment(-1 + (_shimmer.value * 2), 0),
                  child: FractionallySizedBox(
                    widthFactor: .3,
                    heightFactor: 1.6,
                    child: child,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: .7),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DiscoveredDeviceTile extends StatelessWidget {
  const _DiscoveredDeviceTile({
    required this.phone,
    required this.onTap,
    super.key,
  });

  final LanPeer phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: desktopLine),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: Color(0xFFE8F0FF),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.smartphone_rounded,
          color: AppColors.blue,
          size: 20,
        ),
      ),
      title: Text(
        phone.name,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'Dispositivo encontrado',
        style: TextStyle(fontSize: 13, color: desktopMuted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
      onTap: onTap,
    ),
  );
}
