import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../vault/vault_models.dart';
import 'sync_protocol.dart';
import 'sync_store.dart';

/// Never opens VaultDatabase or persists a snapshot. The only saved material
/// is the protected authorization credential needed for reconnecting.
class DesktopSync extends ChangeNotifier {
  DesktopSync({SyncStore? store})
    : preferences = SyncPreferences(
        store ?? const ProtectedSyncStore('desktop'),
      );
  final SyncPreferences preferences;
  HttpServer? _server;
  LanDiscovery? discovery;
  PairingTicket? ticket;
  SyncLink? _link;
  VaultSnapshot? snapshot;
  DeviceGrant? get grant => preferences.devices.values.firstOrNull;
  String name = Platform.localHostname;
  String target = '';
  String status = 'Nenhum dispositivo conectado';
  String? error;
  bool searching = false, syncing = false, _disposed = false;
  int _handshakes = 0;
  static const _maxConcurrentHandshakes = 2;
  static const _handshakeWindow = Duration(seconds: 30);
  static const _maxHandshakesPerAddress = 6;
  int _generation = 0;
  Timer? _timer;
  Timer? _searchTimeout;
  final Map<String, Completer<String>> _requests = {};
  final Map<String, List<DateTime>> _handshakeAttempts = {};
  bool get connected => _link != null && snapshot != null;
  int get port => _server?.port ?? 0;
  List<LanPeer> get phones => searching
      ? discovery?.peers.values.where((p) => p.role == 'phone').toList() ?? []
      : [];

  Future<void> start({bool discover = true}) async {
    try {
      await preferences.load();
      if (_disposed) return;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      if (_disposed) {
        await _server!.close(force: true);
        return;
      }
      _server!.listen(_accept);
      ticket = PairingTicket();
      discovery = LanDiscovery(
        advertisement: () => {
          'id': preferences.id,
          'name': name.length > 80 ? name.substring(0, 80) : name,
          'role': 'desktop',
          'port': _server!.port,
          'ticket': grant == null && ticket?.valid() == true ? ticket!.id : '',
          'target': target,
          'resume': grant?.id ?? '',
        },
        onChanged: _changed,
      );
      if (discover) await discovery!.start();
      if (_disposed) {
        discovery?.close();
        return;
      }
      status = grant == null
          ? 'Nenhum dispositivo conectado'
          : 'Aguardando o celular autorizado na rede';
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
      if (grant == null) {
        detect();
      } else {
        _changed();
      }
    } on Object {
      error =
          'Não foi possível preparar a conexão local. Confira a rede e tente novamente.';
      status = 'Erro de conexão';
      _changed();
    }
  }

  void detect() {
    _searchTimeout?.cancel();
    _searchTimeout = null;
    error = null;
    searching = true;
    discovery?.announce();
    _searchTimeout = Timer(const Duration(seconds: 8), () {
      if (_disposed || !searching) return;
      if (phones.isNotEmpty) {
        _searchTimeout = null;
        return;
      }
      searching = false;
      error = 'Nenhum dispositivo encontrado. Verifique a rede local.';
      status = 'Nenhum dispositivo conectado';
      _searchTimeout = null;
      _changed();
    });
    _changed();
  }

  void selectPhone(LanPeer phone) {
    _searchTimeout?.cancel();
    _searchTimeout = null;
    searching = false;
    newTicket();
    target = phone.id;
    status = 'Digite este código no celular';
    discovery?.announce();
    _changed();
  }

  void newTicket() {
    if (grant != null || _link != null) return;
    _searchTimeout?.cancel();
    _searchTimeout = null;
    ticket?.cancel();
    ticket = PairingTicket();
    target = '';
    error = null;
    _generation++;
    status = 'Nenhum dispositivo conectado';
    discovery?.announce();
    _changed();
  }

  bool _allowHandshake(InternetAddress address) {
    if (_handshakes >= _maxConcurrentHandshakes) return false;
    final now = DateTime.now();
    final attempts = _handshakeAttempts[address.address] ?? <DateTime>[];
    attempts.removeWhere(
      (attempt) => now.difference(attempt) >= _handshakeWindow,
    );
    if (attempts.length >= _maxHandshakesPerAddress) {
      _handshakeAttempts[address.address] = attempts;
      return false;
    }
    attempts.add(now);
    _handshakeAttempts[address.address] = attempts;
    return true;
  }

  Future<void> _accept(HttpRequest request) async {
    final address = request.connectionInfo?.remoteAddress;
    if (_disposed ||
        _link != null ||
        address == null ||
        !isLocalAddress(address) ||
        request.uri.path != '/passdrive' ||
        !WebSocketTransformer.isUpgradeRequest(request) ||
        !_allowHandshake(address)) {
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }
    _handshakes++;
    final generation = _generation;
    final previousGrant = grant;
    SyncWire? wire;
    try {
      wire = SyncWire(await WebSocketTransformer.upgrade(request));
      final hello = await wire.read(const Duration(seconds: 8));
      if (hello['v'] != syncVersion || hello['desktopId'] != preferences.id) {
        throw const FormatException('Dispositivo não autorizado.');
      }
      final phoneId = safeString(hello['phoneId']);
      final mode = safeString(hello['mode']);
      final resume = mode == 'resume';
      final currentTicket = ticket;
      String secret;
      if (resume) {
        final g = grant;
        if (g == null || g.id != phoneId || !g.valid()) {
          throw const FormatException('Autorização expirada ou revogada.');
        }
        secret = g.secret;
      } else {
        if (grant != null ||
            currentTicket == null ||
            hello['ticket'] != currentTicket.id ||
            !['code', 'qr'].contains(mode) ||
            (mode == 'code' && target != phoneId)) {
          throw const FormatException('Pareamento não autorizado.');
        }
        currentTicket.claimAttempt();
        secret = mode == 'qr' ? currentTicket.qrSecret : currentTicket.code;
      }
      final identity =
          'v1:${preferences.id}:$phoneId:$mode:${hello['ticket'] ?? ''}';
      final srp = SrpHost(identity, secret);
      wire.send(srp.challenge);
      final proof = await wire.read(const Duration(seconds: 8));
      final reply = srp.verify(proof);
      if (generation != _generation ||
          _disposed ||
          (!resume &&
              (currentTicket!.consumed ||
                  DateTime.now().isAfter(currentTicket.expiresAt)))) {
        throw const FormatException('Pareamento expirado.');
      }
      wire.send(reply);
      final link = SyncLink(
        wire,
        await SyncCipher.create(
          srp.key,
          '$identity:${srp.challenge['salt']}:${srp.challenge['B']}:${proof['A']}',
          host: true,
        ),
      );
      final first = await link.cipher.decrypt(
        await wire.read(const Duration(seconds: 8)),
      );
      if (first['type'] != 'grant') throw const FormatException();
      final received = DeviceGrant.fromJson(
        Map<String, dynamic>.from(first['grant'] as Map),
      );
      if (received.id != phoneId ||
          !received.valid() ||
          (resume && received.secret != grant?.secret)) {
        throw const FormatException();
      }
      if (generation != _generation || _disposed) {
        await link.close();
        return;
      }
      currentTicket?.cancel();
      preferences.devices
        ..clear()
        ..[received.id] = received;
      await preferences.save();
      if (generation != _generation || _disposed) {
        await link.close();
        return;
      }
      await link.send({'type': 'authorized'});
      _link = link;
      _handshakeAttempts.remove(address.address);
      error = null;
      syncing = true;
      status = 'Sincronizando com ${received.name}';
      _changed();
      unawaited(_listen(link));
    } on Object catch (e) {
      if (!_disposed && generation == _generation) {
        preferences.devices.clear();
        if (previousGrant != null) {
          preferences.devices[previousGrant.id] = previousGrant;
        }
      }
      error = e is FormatException
          ? e.message.toString()
          : 'Não foi possível autorizar esta conexão.';
      try {
        wire?.send({'error': error});
        await wire?.close();
      } on Object {
        /* Closed peer. */
      }
      _changed();
    } finally {
      _handshakes--;
    }
  }

  Future<void> _listen(SyncLink link) async {
    try {
      await for (final message in link.messages) {
        if (_disposed || _link != link || grant?.valid() != true) break;
        switch (message['type']) {
          case 'snapshot':
            snapshot = VaultSnapshot.fromJson(
              Map<String, Object?>.from(message['snapshot'] as Map),
            );
            syncing = false;
            status = 'Sincronizado com ${grant!.name}';
            error = null;
            _changed();
          case 'grant':
            final updated = DeviceGrant.fromJson(
              Map<String, dynamic>.from(message['grant'] as Map),
            );
            if (updated.id != grant!.id || updated.secret != grant!.secret) {
              throw const FormatException();
            }
            preferences.devices[updated.id] = updated;
            await preferences.save();
            _changed();
          case 'result':
            _requests
                .remove(message['requestId'])
                ?.complete(safeString(message['message'], max: 300));
          case 'locked':
          case 'revoked':
            await disconnect(
              forget: true,
              message:
                  'A conexão foi encerrada pelo celular. Faça um novo pareamento.',
            );
            return;
          case 'ping':
            await link.send({'type': 'pong'});
          case 'pong':
            break;
          default:
            throw const FormatException('Mensagem de sincronização inválida.');
        }
      }
    } on Object {
      /* Loss of transport always removes the memory view. */
    }
    if (!_disposed && _link == link) {
      await disconnect(
        message: 'Celular desconectado. Aguardando reconexão na rede local.',
      );
    }
  }

  Future<void> refresh() async {
    if (_link == null) {
      discovery?.announce();
      return;
    }
    syncing = true;
    status = 'Sincronizando com ${grant?.name}';
    _changed();
    try {
      await _link!.send({'type': 'refresh'});
    } on Object {
      await disconnect();
    }
  }

  Future<String> request(RemoteAction action) async {
    if (!connected || _requests.isNotEmpty) {
      return 'Conclua a solicitação atual no celular.';
    }
    final result = Completer<String>();
    _requests[action.requestId] = result;
    try {
      await _link!.send({'type': 'action', 'action': action.toJson()});
      return await result.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () =>
            'A conclusão continua no celular. Você pode seguir usando o computador.',
      );
    } on Object {
      return 'O celular foi desconectado.';
    } finally {
      _requests.remove(action.requestId);
    }
  }

  Future<void> _tick() async {
    if (grant != null && !grant!.valid()) {
      await disconnect(
        forget: true,
        message: 'Sessão expirada. Conecte novamente.',
      );
      return;
    }
    if (_link != null) {
      if (DateTime.now().difference(_link!.lastSeen).inSeconds > 20) {
        await disconnect();
        return;
      }
      try {
        await _link!.send({'type': 'ping'});
      } on Object {
        await disconnect();
      }
    }
    _changed();
  }

  Future<void> disconnect({
    bool forget = false,
    String message = 'Celular desconectado. Aguardando reconexão.',
  }) async {
    _searchTimeout?.cancel();
    _searchTimeout = null;
    _generation++;
    final old = _link;
    _link = null;
    snapshot = null;
    syncing = false;
    status = message;
    for (final request in _requests.values) {
      if (!request.isCompleted) request.complete('A conexão foi encerrada.');
    }
    _requests.clear();
    _changed();
    try {
      if (forget) {
        try {
          await old?.send({'type': 'revoke'});
        } on Object {
          /* Offline revocation is also enforced locally. */
        }
        preferences.devices.clear();
        await preferences.save();
        ticket = PairingTicket();
        target = '';
      }
    } on Object {
      error =
          'A conexão foi bloqueada, mas não foi possível salvar a revogação local.';
    } finally {
      await old?.close();
      discovery?.announce();
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _searchTimeout?.cancel();
    discovery?.close();
    snapshot = null;
    final link = _link;
    _link = null;
    link?.close();
    for (final pending in _requests.values) {
      if (!pending.isCompleted) pending.complete('A conexão foi encerrada.');
    }
    _requests.clear();
    _server?.close(force: true);
    super.dispose();
  }
}
