import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart' hide showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../windows/adaptive_sheet.dart';
import '../theme/app_colors.dart';
import 'mobile_sync.dart';
import 'sync_protocol.dart';
import 'sync_store.dart';

const _syncFieldBorder = Color(0xFFE9EDF5);

Future<T?> syncSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              textStyle: const TextStyle(
                fontFamily: 'Kumbh Sans',
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        child: child,
      ),
    );
typedef SyncNext = Future<void> Function(BuildContext);
Future<void> _runPanel(BuildContext context, Widget panel) async {
  final next = await syncSheet<SyncNext>(context, panel);
  if (next == null) return;
  await Future<void>.delayed(const Duration(milliseconds: 220));
  if (context.mounted) await next(context);
}

Future<void> openSyncDevices(BuildContext context, MobileSync sync) async {
  while (sync.ready) {
    if (!context.mounted) return;
    final next = await syncSheet<SyncNext>(
      context,
      SyncDevicesSheet(sync: sync),
    );
    if (next == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!context.mounted || !sync.ready) return;
    await next(context);
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }
}

class SyncPanel extends StatelessWidget {
  const SyncPanel({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppPalette.watch(
    context,
    () => AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .84,
        ),
        child: Material(
          color: AppPalette.resolve(Colors.white),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.resolve(const Color(0xFFE0E5EF)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Fechar'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool> syncConfirm(
  BuildContext context,
  String title,
  String message, {
  String confirm = 'Confirmar',
}) async =>
    await syncSheet<bool>(
      context,
      Builder(
        builder: (context) => SyncPanel(
          title: title,
          children: [
            Text(message, style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirm),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancelar')),
            ),
          ],
        ),
      ),
    ) ??
    false;

class SyncDevicesSheet extends StatefulWidget {
  const SyncDevicesSheet({required this.sync, super.key});
  final MobileSync sync;
  @override
  State<SyncDevicesSheet> createState() => _SyncDevicesSheetState();
}

class _SyncDevicesSheetState extends State<SyncDevicesSheet> {
  String? error;
  bool busy = false;
  bool _handingOver = false;
  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_incoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _incoming());
  }

  @override
  void dispose() {
    widget.sync.removeListener(_incoming);
    super.dispose();
  }

  void _incoming() {
    if (!mounted ||
        _handingOver ||
        widget.sync.incomingPairing == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _handingOver = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = widget.sync, peer = widget.sync.incomingPairing;
      if (peer == null) {
        _handingOver = false;
        return;
      }
      sync.incomingPairing = null;
      _next(() => PairingApprovalSheet(sync: sync, peer: peer));
    });
  }

  Future<void> _save(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() => error = tr('Não foi possível salvar esta opção.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _next(Widget Function() next) {
    Navigator.pop<SyncNext>(context, (parent) => _runPanel(parent, next()));
  }

  @override
  Widget build(BuildContext context) => AppPalette.watch(
    context,
    () => AnimatedBuilder(
      animation: widget.sync,
      builder: (context, _) {
        final sync = widget.sync;
        return SyncPanel(
          title: tr('Sincronização e dispositivos'),
          children: [
            if (!sync.ready)
              Text(sync.error ?? tr('Preparando conexão local…')),
            FilledButton.icon(
              onPressed: sync.ready && !busy
                  ? () => _next(() => ScanPairingSheet(sync: sync))
                  : null,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(tr('Ler QR Code do computador')),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Autorizar ao ler QR Code')),
              subtitle: Text(
                tr('A leitura pelo app autoriza o computador por 1 hora.'),
              ),
              value: sync.preferences.autoQr,
              onChanged: busy || !sync.ready
                  ? null
                  : (v) => _save(() => sync.setAutoQr(v)),
            ),
            Divider(color: AppPalette.resolve(_syncFieldBorder)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Receber pedidos em segundo plano')),
              subtitle: Text(
                tr(
                  'Mantém uma notificação ativa. Não funciona se o Android forçar a parada do app.',
                ),
              ),
              value: sync.background,
              onChanged: busy || !sync.ready
                  ? null
                  : (v) => _save(() => sync.setBackground(v)),
            ),
            const SizedBox(height: 20),
            Text(
              tr('Dispositivos'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            if (sync.preferences.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('Nenhum computador autorizado.')),
              ),
            for (final g in sync.preferences.devices.values) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.computer_rounded,
                  color: AppColors.blue,
                ),
                title: Text(g.name),
                subtitle: Text(
                  '${sync.links.containsKey(g.id) ? tr('Conectado') : tr('Desconectado')} • Windows\n${g.expiresAt == null ? tr('Sem prazo de expiração') : 'Até ${_date(g.expiresAt!)}'}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    _next(() => DeviceOptionsSheet(sync: sync, id: g.id)),
              ),
              Divider(color: AppPalette.resolve(_syncFieldBorder)),
            ],
            const SizedBox(height: 12),
            Text(
              tr(
                'Bloquear o cofre encerra as autorizações. “Para sempre” não impede bloqueio ou revogação.',
              ),
              style: TextStyle(color: AppColors.bodyText, fontSize: 14),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: AppPalette.resolve(Colors.red)),
                ),
              ),
          ],
        );
      },
    ),
  );
}

String _date(DateTime value) {
  final d = value.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class DeviceOptionsSheet extends StatefulWidget {
  const DeviceOptionsSheet({required this.sync, required this.id, super.key});
  final MobileSync sync;
  final String id;
  @override
  State<DeviceOptionsSheet> createState() => _DeviceOptionsSheetState();
}

class _DeviceOptionsSheetState extends State<DeviceOptionsSheet> {
  String? error;
  bool busy = false;

  Future<void> _saveOption(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() => error = tr('Não foi possível salvar esta opção.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _change({
    ConnectionDuration? duration,
    bool revoke = false,
  }) async {
    if (busy) return;
    final sync = widget.sync, id = widget.id;
    Navigator.pop<SyncNext>(context, (parent) async {
      if (!sync.ready) return;
      final confirmed =
          (!revoke && duration != ConnectionDuration.forever) ||
          await syncConfirm(
            parent,
            revoke
                ? tr('Desconectar dispositivo?')
                : tr('Autorizar sem prazo?'),
            revoke
                ? tr('Será necessário parear novamente para acessar o cofre.')
                : tr(
                    'Este computador poderá reconectar até você bloquear o cofre ou revogar o acesso.',
                  ),
          );
      if (!confirmed || !sync.ready) return;
      try {
        if (revoke) {
          await sync.revoke(id);
        } else {
          await sync.setDuration(id, duration!);
        }
      } on Object {
        if (parent.mounted) {
          await syncSheet<void>(
            parent,
            SyncPanel(
              title: tr('Não foi possível salvar'),
              children: [Text(tr('Confira a conexão e tente novamente.'))],
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final g = widget.sync.preferences.devices[widget.id];
    return SyncPanel(
      title: g?.name ?? tr('Dispositivo'),
      children: [
        if (g != null) ...[
          Text(
            'Windows • Vinculado em ${_date(g.createdAt)}\nÚltima conexão: ${_date(g.lastSeen)}',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.bodyText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Confiar neste computador')),
            subtitle: Text(
              tr(
                'Reconecta automaticamente ao abrir o PassDrive no Windows, sem QR Code ou código.',
              ),
            ),
            value: g.trusted,
            onChanged: busy
                ? null
                : (value) => _saveOption(
                    () => widget.sync.setTrusted(widget.id, value),
                  ),
          ),
          Divider(color: AppPalette.resolve(_syncFieldBorder)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bloquear ao perder o foco')),
            subtitle: Text(
              tr(
                'Encerra a sessão deste computador ao trocar para outro app ou janela.',
              ),
            ),
            value: g.lockOnFocusLoss,
            onChanged: busy
                ? null
                : (value) => _saveOption(
                    () => widget.sync.setLockOnFocusLoss(widget.id, value),
                  ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ConnectionDuration>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Permitir reconexão por'),
            ),
            hint: Text(
              g.expiresAt == null ? tr('Para sempre') : tr('Escolher duração'),
            ),
            items: ConnectionDuration.values
                .map(
                  (v) => DropdownMenuItem(value: v, child: Text(tr(v.label))),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _change(duration: v);
            },
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => _change(revoke: true),
            icon: const Icon(Icons.link_off_rounded),
            label: Text(tr('Revogar acesso')),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: AppPalette.resolve(Colors.red)),
            ),
          ],
        ],
      ],
    );
  }
}

class PairingApprovalSheet extends StatefulWidget {
  const PairingApprovalSheet({
    required this.sync,
    required this.peer,
    this.qrSecret,
    super.key,
  });
  final MobileSync sync;
  final LanPeer peer;
  final String? qrSecret;
  @override
  State<PairingApprovalSheet> createState() => _PairingApprovalSheetState();
}

class _PairingApprovalSheetState extends State<PairingApprovalSheet> {
  PairingAttempt? _attempt;
  final code = List.generate(3, (_) => TextEditingController());
  final codeFocus = List.generate(3, (_) => FocusNode());
  ConnectionDuration duration = ConnectionDuration.hour;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    _attempt?.cancel();
    for (final controller in code) {
      controller.dispose();
    }
    for (final focusNode in codeFocus) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _enteredCode => code.map((field) => field.text).join();

  void _onCodeChanged(int index, String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (normalized.length > 1) {
      final available = normalized.length.clamp(0, code.length - index);
      for (var offset = 0; offset < available; offset++) {
        code[index + offset].value = TextEditingValue(
          text: normalized[offset],
          selection: const TextSelection.collapsed(offset: 1),
        );
      }
      final nextIndex = (index + available).clamp(0, code.length - 1);
      codeFocus[nextIndex].requestFocus();
      if (error != null) setState(() => error = null);
      return;
    }
    if (value != normalized) {
      code[index].value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    if (normalized.isNotEmpty && index < code.length - 1) {
      codeFocus[index + 1].requestFocus();
    }
    if (error != null) setState(() => error = null);
  }

  Future<void> _approve() async {
    if (busy) return;
    if (widget.qrSecret == null && _enteredCode.length != 3) {
      setState(
        () => error = tr('Digite os 3 caracteres exibidos no computador.'),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.sync.pair(
        widget.peer,
        attempt: _attempt = PairingAttempt(),
        secret: widget.qrSecret ?? _enteredCode,
        mode: widget.qrSecret == null ? 'code' : 'qr',
        duration: duration,
      );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() {
          busy = false;
          error = tr(
            'Não foi possível autorizar. Confira o código, a rede e o prazo de 2 minutos. Após 3 tentativas, gere outro código no computador.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppPalette.watch(
    context,
    () => SyncPanel(
      title: tr('Autorizar computador'),
      children: [
        Text(
          widget.peer.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Este dispositivo poderá exibir e copiar as senhas enquanto o celular estiver conectado e desbloqueado.',
          ),
        ),
        const SizedBox(height: 20),
        if (widget.qrSecret == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Código do computador'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Use os caracteres exibidos no computador.'),
                style: TextStyle(fontSize: 14, color: AppColors.bodyText),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < code.length; index++) ...[
                    if (index > 0) const SizedBox(width: 12),
                    Semantics(
                      label: tx(
                        'Caractere ${index + 1} de 3',
                        'Character ${index + 1} of 3',
                      ),
                      child: SizedBox(
                        width: 58,
                        height: 62,
                        child: TextField(
                          controller: code[index],
                          focusNode: codeFocus[index],
                          enabled: !busy,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: index == code.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[a-zA-Z0-9]'),
                            ),
                          ],
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: AppPalette.resolve(
                              const Color(0xFFF7F9FD),
                            ),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: _syncFieldBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: _syncFieldBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: AppColors.blue,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (value) => _onCodeChanged(index, value),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ConnectionDuration>(
          initialValue: duration,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          dropdownColor: AppPalette.resolve(Colors.white),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.navy,
          ),
          decoration: InputDecoration(
            labelText: tr('Permitir reconexão por'),
            prefixIcon: const Icon(Icons.schedule_rounded),
            filled: true,
            fillColor: AppPalette.resolve(const Color(0xFFF7F9FD)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _syncFieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _syncFieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
            ),
          ),
          items: ConnectionDuration.values
              .where((v) => v != ConnectionDuration.forever)
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(tr(v.label), overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: busy ? null : (v) => setState(() => duration = v!),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Você pode autorizar sem prazo depois, nas opções do dispositivo.',
          ),
          style: TextStyle(fontSize: 14, color: AppColors.bodyText),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: TextStyle(color: AppPalette.resolve(Colors.red)),
            ),
          ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: busy ? null : _approve,
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('Autorizar conexão')),
        ),
      ],
    ),
  );
}

class ScanPairingSheet extends StatefulWidget {
  const ScanPairingSheet({required this.sync, super.key});
  final MobileSync sync;
  @override
  State<ScanPairingSheet> createState() => _ScanPairingSheetState();
}

class _ScanPairingSheetState extends State<ScanPairingSheet> {
  PairingAttempt? _attempt;
  final scanner = MobileScannerController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    _attempt?.cancel();
    scanner.dispose();
    super.dispose();
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final invite = QrInvitation.parse(raw);
      final peer = widget.sync.computers
          .where((p) => p.id == invite.desktopId && p.ticket == invite.ticketId)
          .firstOrNull;
      if (peer == null) throw const FormatException();
      await scanner.stop();
      if (!mounted) return;
      if (widget.sync.preferences.autoQr) {
        await widget.sync.pair(
          peer,
          secret: invite.secret,
          mode: 'qr',
          attempt: _attempt = PairingAttempt(),
        );
        if (mounted) Navigator.pop(context);
      } else {
        final sync = widget.sync;
        Navigator.pop<SyncNext>(context, (parent) async {
          if (sync.ready) {
            await syncSheet<void>(
              parent,
              PairingApprovalSheet(
                sync: sync,
                peer: peer,
                qrSecret: invite.secret,
              ),
            );
          }
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          error = tr(
            'QR Code inválido, expirado ou computador fora da rede. Confira e tente novamente.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppPalette.watch(
    context,
    () => SyncPanel(
      title: tr('Ler QR Code'),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: MobileScanner(
              controller: scanner,
              onDetect: _scan,
              errorBuilder: (_, _) => Center(
                child: Text(
                  tr('Permita o acesso à câmera para ler o QR Code.'),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(tr('Aponte para o QR Code exibido pelo PassDrive no computador.')),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: AppPalette.resolve(Colors.red))),
          TextButton(
            onPressed: () {
              setState(() {
                busy = false;
                error = null;
              });
              scanner.start();
            },
            child: Text(tr('Tentar novamente')),
          ),
        ],
      ],
    ),
  );
}
