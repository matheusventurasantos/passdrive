import '../settings/app_strings.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../vault/vault_models.dart';
import '../settings/appearance_preferences.dart';
import 'sync_protocol.dart';
import 'sync_store.dart';

class PairingAttempt {
  bool canceled = false, completed = false;
  SyncWire? wire;
  void cancel() {
    if (completed) return;
    canceled = true;
    unawaited(wire?.close());
  }
}

/// Only this unlocked mobile owner can release a view or approve a mutation.
class MobileSync extends ChangeNotifier {
  MobileSync({
    required this.readSnapshot,
    required this.onAction,
    required this.onPairing,
    SyncStore? store,
  }) : preferences = SyncPreferences(
         store ?? const ProtectedSyncStore('phone'),
       );
  final VaultSnapshot Function() readSnapshot;
  final Future<bool> Function(RemoteAction, String) onAction;
  final void Function(LanPeer) onPairing;
  final SyncPreferences preferences;
  static const native = MethodChannel('passdrive/sync');
  LanDiscovery? discovery;
  final Map<String, SyncLink> links = {};
  final Set<String> _connecting = {}, _offered = {};
  final Map<SyncLink, Set<String>> _requests = {};
  final Set<PairingAttempt> _attempts = {};
  LanPeer? incomingPairing;
  final Map<String, DateTime> _retryAfter = {};
  Timer? _timer;
  bool _closed = false,
      _disposed = false,
      ready = false,
      background = false,
      _actionBusy = false;
  String name = tr('Celular'), pendingDevice = '';
  String? error;
  List<LanPeer> get computers =>
      discovery?.peers.values
          .where((p) => p.role == 'desktop' && p.port > 0)
          .toList() ??
      [];

  Future<void> start({bool discover = true, bool useNative = true}) async {
    AppearancePreferences.instance.addListener(publish);
    try {
      await preferences.load();
      if (_closed) return;
      // Grants are stored only in protected storage and are still revoked when
      // the vault is explicitly locked. Keeping them here enables the user's
      // per-device trust choice to survive a regular app or desktop restart.
      if (useNative) {
        try {
          final info = await native.invokeMapMethod<String, dynamic>('info');
          name = info?['name'] as String? ?? name;
          background = info?['enabled'] == true;
          if (background) {
            background =
                await native.invokeMethod<bool>('enableBackground', {
                  'id': preferences.id,
                  'name': name,
                }) ??
                false;
          }
          await native.invokeMethod<void>('acquireDiscovery');
          pendingDevice =
              await native.invokeMethod<String>('consumeRequest') ?? '';
          native.setMethodCallHandler((call) async {
            if (call.method == 'pendingPairing') {
              pendingDevice = call.arguments as String? ?? '';
              _peersChanged();
            }
          });
        } on MissingPluginException {
          /* Tests/non-Android owner. */
        }
      }
      if (_closed) return;
      if (discover) {
        discovery = LanDiscovery(
          advertisement: () => {
            'id': preferences.id,
            'name': name,
            'role': 'phone',
            'port': 0,
          },
          onChanged: _peersChanged,
        );
        await discovery!.start();
      }
      if (_closed) {
        discovery?.close();
        return;
      }
      ready = true;
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
      _changed();
    } on Object {
      error = tr('Não foi possível iniciar as conexões locais.');
      _changed();
    }
  }

  void _peersChanged() {
    if (_closed) return;
    for (final peer in computers) {
      final grant = preferences.devices[peer.id];
      if (grant != null &&
          grant.valid() &&
          grant.trusted &&
          peer.resume == preferences.id &&
          !links.containsKey(peer.id) &&
          !_connecting.contains(peer.id) &&
          !DateTime.now().isBefore(_retryAfter[peer.id] ?? DateTime(2000))) {
        _retryAfter[peer.id] = DateTime.now().add(const Duration(seconds: 15));
        unawaited(
          pair(
            peer,
            secret: grant.secret,
            mode: 'resume',
          ).catchError((Object _) {}),
        );
      }
      if (peer.ticket.isNotEmpty &&
          (peer.target == preferences.id || pendingDevice == peer.id) &&
          _offered.add('${peer.id}:${peer.ticket}')) {
        pendingDevice = '';
        incomingPairing = peer;
        onPairing(peer);
      }
    }
    _changed();
  }

  Future<void> pair(
    LanPeer peer, {
    required String secret,
    String mode = 'code',
    ConnectionDuration duration = ConnectionDuration.hour,
    PairingAttempt? attempt,
  }) async {
    if (_closed ||
        !ready ||
        !isLocalAddress(peer.address) ||
        !_connecting.add(peer.id) ||
        links.containsKey(peer.id)) {
      throw StateError(tr('Conexão indisponível.'));
    }
    SyncWire? wire;
    SyncLink? link;
    final operation = attempt ?? PairingAttempt();
    _attempts.add(operation);
    final previous = preferences.devices[peer.id];
    bool saved = false;
    try {
      if (operation.canceled) throw StateError(tr('Pareamento cancelado.'));
      if (mode == 'resume' && (previous == null || !previous.valid())) {
        throw FormatException(tr('Autorização expirada.'));
      }
      wire = SyncWire(
        await WebSocket.connect(
          'ws://${peer.address.address}:${peer.port}/passdrive',
        ).timeout(const Duration(seconds: 10)),
      );
      operation.wire = wire;
      if (_closed || operation.canceled) {
        throw StateError(tr('Pareamento cancelado.'));
      }
      final ticket = mode == 'resume' ? '' : peer.ticket;
      final identity = 'v1:${peer.id}:${preferences.id}:$mode:$ticket';
      wire.send({
        'v': syncVersion,
        'desktopId': peer.id,
        'phoneId': preferences.id,
        'mode': mode,
        'ticket': ticket,
      });
      final challenge = await wire.read();
      final srp = SrpPhone();
      final proof = srp.proof(identity, secret, challenge);
      wire.send(proof);
      final key = srp.verify(await wire.read());
      if (_closed || operation.canceled) {
        throw StateError(tr('Pareamento cancelado.'));
      }
      link = SyncLink(
        wire,
        await SyncCipher.create(
          key,
          '$identity:${challenge['salt']}:${challenge['B']}:${proof['A']}',
          host: false,
        ),
      );
      final now = DateTime.now();
      final grant = mode == 'resume'
          ? previous!.update(seen: now)
          : DeviceGrant(
              id: peer.id,
              name: peer.name,
              secret: randomToken(32),
              createdAt: now,
              lastSeen: now,
              expiresAt: duration.expiry(now),
            );
      preferences.devices[peer.id] = grant;
      await preferences.save();
      saved = true;
      if (_closed || operation.canceled) {
        throw StateError(tr('Pareamento cancelado.'));
      }
      await link.send({'type': 'grant', 'grant': _mirror(grant).toJson()});
      final acknowledged = await link.cipher.decrypt(await wire.read());
      if (_closed ||
          operation.canceled ||
          acknowledged['type'] != 'authorized') {
        throw StateError(tr('Conexão não autorizada.'));
      }
      links[peer.id] = link;
      await _sendSnapshot(link);
      operation.completed = true;
      unawaited(_listen(peer.id, link));
      error = null;
      _changed();
    } on Object {
      if (previous == null || _closed) {
        preferences.devices.remove(peer.id);
      } else {
        preferences.devices[peer.id] = previous;
      }
      try {
        if (saved) await preferences.save();
      } finally {
        links.remove(peer.id);
        await link?.close();
        if (link == null) await wire?.close();
      }
      rethrow;
    } finally {
      _attempts.remove(operation);
      operation.wire = null;
      _connecting.remove(peer.id);
      _changed();
    }
  }

  DeviceGrant _mirror(DeviceGrant g) => DeviceGrant(
    id: preferences.id,
    name: name,
    secret: g.secret,
    createdAt: g.createdAt,
    lastSeen: g.lastSeen,
    expiresAt: g.expiresAt,
    trusted: g.trusted,
    lockOnFocusLoss: g.lockOnFocusLoss,
  );
  Future<void> _sendSnapshot(SyncLink link) async {
    if (_closed) return;
    final source = readSnapshot();
    // Deliberately excludes access metadata, recovery keys and owner preferences.
    final view = VaultSnapshot(
      accounts: source.accounts,
      services: source.services,
      breachChecks: source.breachChecks,
    );
    await link.send({
      'type': 'snapshot',
      'snapshot': view.toJson(),
      'theme': AppearancePreferences.instance.sharedTheme,
    });
  }

  void publish() {
    for (final entry in links.entries.toList()) {
      unawaited(
        _sendSnapshot(
          entry.value,
        ).catchError((Object _) => _drop(entry.key, entry.value)),
      );
    }
  }

  Future<void> _listen(String id, SyncLink link) async {
    try {
      await for (final message in link.messages) {
        if (_closed || !identical(links[id], link)) break;
        switch (message['type']) {
          case 'refresh':
            await _sendSnapshot(link);
          case 'ping':
            await link.send({'type': 'pong'});
          case 'pong':
            break;
          case 'revoke':
            await revoke(id);
            return;
          case 'action':
            final action = RemoteAction.fromJson(
              Map<String, dynamic>.from(message['action'] as Map),
            );
            final handled = _requests.putIfAbsent(link, () => <String>{});
            if (handled.contains(action.requestId)) {
              throw FormatException(tr('Solicitação repetida.'));
            }
            if (handled.length >= 256) {
              throw FormatException(tr('Limite de solicitações atingido.'));
            }
            handled.add(action.requestId);
            // Do not stop processing heartbeats while the owner fills a form.
            unawaited(_perform(id, link, action));
          default:
            throw FormatException(tr('Mensagem inválida.'));
        }
      }
    } on Object {
      /* Connection loss never transfers authority. */
    } finally {
      await _drop(id, link);
    }
  }

  Future<void> _perform(String id, SyncLink link, RemoteAction action) async {
    if (_actionBusy) {
      await link
          .send({
            'type': 'result',
            'requestId': action.requestId,
            'message': tr('O celular já está atendendo outra solicitação.'),
          })
          .catchError((Object _) {});
      return;
    }
    _actionBusy = true;
    try {
      final accepted = await onAction(
        action,
        preferences.devices[id]?.name ?? tr('Computador'),
      );
      if (_closed || !identical(links[id], link)) return;
      await _sendSnapshot(link);
      await link.send({
        'type': 'result',
        'requestId': action.requestId,
        'message': accepted
            ? tr('Solicitação concluída no celular.')
            : tr('Solicitação cancelada no celular.'),
      });
    } on Object {
      await link
          .send({
            'type': 'result',
            'requestId': action.requestId,
            'message': tr('Não foi possível concluir no celular.'),
          })
          .catchError((Object _) {});
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _drop(String id, SyncLink link) async {
    _requests.remove(link);
    if (identical(links[id], link)) links.remove(id);
    await link.close();
    _changed();
  }

  Future<void> revoke(String id) async {
    final link = links.remove(id);
    preferences.devices.remove(id);
    try {
      await preferences.save();
    } finally {
      await link?.send({'type': 'revoked'}).catchError((Object _) {});
      await link?.close();
      _changed();
    }
  }

  Future<void> setDuration(String id, ConnectionDuration duration) async {
    final old = preferences.devices[id];
    if (old == null) return;
    final grant = old.update(duration: duration);
    preferences.devices[id] = grant;
    try {
      await preferences.save();
    } on Object {
      preferences.devices[id] = old;
      rethrow;
    }
    await links[id]?.send({'type': 'grant', 'grant': _mirror(grant).toJson()});
    _changed();
  }

  Future<void> setTrusted(String id, bool value) =>
      _setDeviceOption(id, trusted: value);

  Future<void> setLockOnFocusLoss(String id, bool value) =>
      _setDeviceOption(id, lockOnFocusLoss: value);

  Future<void> _setDeviceOption(
    String id, {
    bool? trusted,
    bool? lockOnFocusLoss,
  }) async {
    final old = preferences.devices[id];
    if (old == null) return;
    final grant = old.update(
      trusted: trusted,
      lockOnFocusLoss: lockOnFocusLoss,
    );
    preferences.devices[id] = grant;
    try {
      await preferences.save();
    } on Object {
      preferences.devices[id] = old;
      rethrow;
    }
    await links[id]?.send({'type': 'grant', 'grant': _mirror(grant).toJson()});
    _changed();
  }

  Future<void> setAutoQr(bool value) async {
    final old = preferences.autoQr;
    preferences.autoQr = value;
    try {
      await preferences.save();
    } on Object {
      preferences.autoQr = old;
      rethrow;
    }
    _changed();
  }

  Future<void> setBackground(bool value) async {
    background =
        await native.invokeMethod<bool>(
          value ? 'enableBackground' : 'disableBackground',
          {'id': preferences.id, 'name': name},
        ) ??
        false;
    _changed();
  }

  Future<void> _tick() async {
    if (_closed) return;
    for (final g in preferences.devices.values.toList()) {
      if (!g.valid()) {
        await revoke(g.id);
        continue;
      }
      final link = links[g.id];
      if (link == null) continue;
      if (DateTime.now().difference(link.lastSeen).inSeconds > 20) {
        await _drop(g.id, link);
      } else {
        await link
            .send({'type': 'ping'})
            .catchError((Object _) => _drop(g.id, link));
      }
    }
  }

  Future<void> lock() async {
    if (_closed) return;
    _closed = true;
    AppearancePreferences.instance.removeListener(publish);
    incomingPairing = null;
    for (final attempt in _attempts) {
      attempt.cancel();
    }
    ready = false;
    _timer?.cancel();
    discovery?.close();
    native.setMethodCallHandler(null);
    unawaited(
      native.invokeMethod<void>('releaseDiscovery').catchError((Object _) {}),
    );
    final active = links.values.toList();
    links.clear();
    preferences.devices.clear();
    // Revoke durable resume credentials too. A future unlock requires pairing.
    try {
      await preferences.save();
    } on Object {
      error = tr('Conexões encerradas. Não foi possível salvar a revogação.');
    } finally {
      await Future.wait(
        active.map((link) async {
          await link.send({'type': 'locked'}).catchError((Object _) {});
          await link.close();
        }),
      );
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(lock());
    super.dispose();
  }
}
