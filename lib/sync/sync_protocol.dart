import '../settings/app_strings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/srp/srp6_client.dart';
import 'package:pointycastle/srp/srp6_server.dart';
import 'package:pointycastle/srp/srp6_standard_groups.dart';
import 'package:pointycastle/srp/srp6_verifier_generator.dart';

const syncVersion = 1;
const syncPort = 47777;
const syncGroup = '239.255.77.77';
const maxSyncBytes = 8 * 1024 * 1024;
const syncReceiveBudgetWindow = Duration(seconds: 10);
const maxSyncMessagesPerWindow = 120;
const maxSyncBytesPerWindow = 32 * 1024 * 1024;
final _random = Random.secure();
Uint8List randomBytes(int count) =>
    Uint8List.fromList(List.generate(count, (_) => _random.nextInt(256)));
String randomToken([int count = 32]) =>
    base64UrlEncode(randomBytes(count)).replaceAll('=', '');
String pairingCode() {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  return List.generate(
    3,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}

String safeString(Object? value, {int max = 160}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.contains(RegExp(r'[\x00-\x1f]'))) {
    throw FormatException(tr('Mensagem de conexão inválida.'));
  }
  return value;
}

Map<String, dynamic> jsonObject(Object? raw) {
  if (raw is! String || raw.length > maxSyncBytes) {
    throw FormatException(tr('Mensagem de conexão inválida.'));
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException(tr('Mensagem de conexão inválida.'));
  }
  return decoded;
}

bool isLocalAddress(InternetAddress address) {
  if (address.isLoopback) return true;
  final b = address.rawAddress;
  return b.length == 4 &&
      (b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254));
}

class PairingTicket {
  PairingTicket({DateTime? now})
    : id = randomToken(16),
      code = pairingCode(),
      qrSecret = randomToken(),
      expiresAt = (now ?? DateTime.now()).add(const Duration(minutes: 2));
  final String id;
  final String code;
  final String qrSecret;
  final DateTime expiresAt;
  int attempts = 0;
  bool consumed = false;
  bool valid([DateTime? now]) =>
      !consumed && attempts < 3 && (now ?? DateTime.now()).isBefore(expiresAt);
  void claimAttempt() {
    if (!valid()) {
      throw FormatException(
        tr('Código expirado. Gere uma nova conexão no computador.'),
      );
    }
    attempts++;
  }

  void cancel() => consumed = true;
  String qr(String desktopId) => 'passdrive:pair:$desktopId:$id:$qrSecret';
}

class QrInvitation {
  QrInvitation(this.desktopId, this.ticketId, this.secret);
  final String desktopId, ticketId, secret;
  factory QrInvitation.parse(String value) {
    final parts = value.split(':');
    if (parts.length != 5 ||
        parts[0] != 'passdrive' ||
        parts[1] != 'pair' ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(parts[2]) ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(parts[3]) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(parts[4])) {
      throw const FormatException('QR Code inválido para o PassDrive.');
    }
    return QrInvitation(parts[2], parts[3], parts[4]);
  }
}

/// SRP-6a authenticates the short code without sending it or a hash of it.
/// An observed handshake is insufficient for an offline dictionary attack.
pc.SecureRandom _srpRandom() =>
    pc.FortunaRandom()..seed(pc.KeyParameter(randomBytes(32)));
final _group = SRP6StandardGroups.rfc5054_3072;
BigInt _integer(Object? value) {
  final s = safeString(value, max: 768);
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(s)) throw const FormatException();
  final n = BigInt.parse(s, radix: 16);
  if (n <= BigInt.zero || n >= _group.N) throw const FormatException();
  return n;
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

class SrpHost {
  SrpHost(String identity, String password) {
    final verifier = SRP6VerifierGenerator(
      group: _group,
      digest: pc.SHA256Digest(),
    ).generateVerifier(salt, _bytes(identity), _bytes(password));
    server = SRP6Server(
      group: _group,
      v: verifier,
      digest: pc.SHA256Digest(),
      random: _srpRandom(),
    );
    challenge = {
      'salt': base64Encode(salt),
      'B': server.generateServerCredentials()!.toRadixString(16),
    };
  }
  final Uint8List salt = randomBytes(32);
  late final SRP6Server server;
  late final Map<String, dynamic> challenge;
  Map<String, dynamic> verify(Map<String, dynamic> proof) {
    server.calculateSecret(_integer(proof['A']));
    if (!server.verifyClientEvidenceMessage(_integer(proof['M1']))) {
      throw FormatException(tr('Código incorreto ou conexão não autorizada.'));
    }
    return {'M2': server.calculateServerEvidenceMessage()!.toRadixString(16)};
  }

  String get key => server.calculateSessionKey()!.toRadixString(16);
}

class SrpPhone {
  final SRP6Client client = SRP6Client(
    group: _group,
    digest: pc.SHA256Digest(),
    random: _srpRandom(),
  );
  Map<String, dynamic> proof(
    String identity,
    String password,
    Map<String, dynamic> challenge,
  ) {
    final salt = base64Decode(safeString(challenge['salt'], max: 48));
    if (salt.length != 32) throw const FormatException();
    final a = client.generateClientCredentials(
      salt,
      _bytes(identity),
      _bytes(password),
    );
    client.calculateSecret(_integer(challenge['B']));
    return {
      'A': a!.toRadixString(16),
      'M1': client.calculateClientEvidenceMessage()!.toRadixString(16),
    };
  }

  String verify(Map<String, dynamic> reply) {
    if (!client.verifyServerEvidenceMessage(_integer(reply['M2']))) {
      throw FormatException(tr('O computador não pôde ser autenticado.'));
    }
    return client.calculateSessionKey()!.toRadixString(16);
  }
}

class SyncWire {
  SyncWire(this.socket) : incoming = StreamIterator(socket);
  final WebSocket socket;
  final StreamIterator<dynamic> incoming;
  Future<Map<String, dynamic>> read([
    Duration timeout = const Duration(seconds: 25),
  ]) async {
    if (!await incoming.moveNext().timeout(timeout)) {
      throw SocketException(tr('Dispositivo desconectado.'));
    }
    final data = jsonObject(incoming.current);
    if (data['error'] != null) throw FormatException(safeString(data['error']));
    return data;
  }

  void send(Map<String, dynamic> value) => socket.add(jsonEncode(value));
  Future<void> close() async {
    await socket.close().timeout(const Duration(seconds: 2), onTimeout: () {});
    await incoming.cancel();
  }
}

/// Independent keys, ordered counters and authenticated direction prevent
/// replay/reflection. Keys are fresh for every SRP exchange, including resume.
class SyncCipher {
  SyncCipher._(
    this._sendKey,
    this._receiveKey,
    this._sendDirection,
    this._receiveDirection,
  );
  SecretKey? _sendKey, _receiveKey;
  final String _sendDirection, _receiveDirection;
  int _sent = 0, _received = 0;
  DateTime _receiveWindowStarted = DateTime.now();
  int _receivedMessagesInWindow = 0;
  int _receivedBytesInWindow = 0;
  final _aes = AesGcm.with256bits();
  static Future<SyncCipher> create(
    String sessionKey,
    String context, {
    required bool host,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    Future<SecretKey> derive(String direction) => hkdf.deriveKey(
      secretKey: SecretKey(_bytes(sessionKey)),
      nonce: _bytes(context),
      info: _bytes('PassDrive LAN v1 $direction'),
    );
    final up = await derive('phone-to-desktop');
    final down = await derive('desktop-to-phone');
    return SyncCipher._(
      host ? down : up,
      host ? up : down,
      host ? 'd' : 'p',
      host ? 'p' : 'd',
    );
  }

  List<int> _nonce(int counter) =>
      (ByteData(12)..setUint64(4, counter)).buffer.asUint8List();
  Future<Map<String, dynamic>> encrypt(Map<String, dynamic> message) async {
    final key = _sendKey;
    if (key == null) throw StateError(tr('Conexão encerrada.'));
    final sequence = _sent++;
    final box = await _aes.encrypt(
      _bytes(jsonEncode(message)),
      secretKey: key,
      nonce: _nonce(sequence),
      aad: _bytes('$_sendDirection:$sequence'),
    );
    return {
      'sequence': sequence,
      'body': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Map<String, dynamic>> decrypt(Map<String, dynamic> message) async {
    final key = _receiveKey;
    if (key == null || message['sequence'] != _received) {
      throw FormatException(tr('Mensagem repetida ou fora de ordem.'));
    }
    final body = base64Decode(safeString(message['body'], max: maxSyncBytes));
    if (body.length < 16) throw const FormatException();
    _consumeReceiveBudget(body.length);
    final plain = await _aes.decrypt(
      SecretBox(
        body.sublist(0, body.length - 16),
        nonce: _nonce(_received),
        mac: Mac(body.sublist(body.length - 16)),
      ),
      secretKey: key,
      aad: _bytes('$_receiveDirection:$_received'),
    );
    _received++;
    try {
      return jsonObject(utf8.decode(plain));
    } finally {
      if (plain is Uint8List) plain.fillRange(0, plain.length, 0);
    }
  }

  void _consumeReceiveBudget(int bytes) {
    final now = DateTime.now();
    if (now.difference(_receiveWindowStarted) >= syncReceiveBudgetWindow) {
      _receiveWindowStarted = now;
      _receivedMessagesInWindow = 0;
      _receivedBytesInWindow = 0;
    }
    if (_receivedMessagesInWindow >= maxSyncMessagesPerWindow ||
        bytes > maxSyncBytesPerWindow - _receivedBytesInWindow) {
      throw FormatException(
        tr('Limite de mensagens de sincronização excedido.'),
      );
    }
    _receivedMessagesInWindow++;
    _receivedBytesInWindow += bytes;
  }

  void destroy() {
    _sendKey = null;
    _receiveKey = null;
  }
}

class SyncLink {
  SyncLink(this.wire, this.cipher);
  final SyncWire wire;
  final SyncCipher cipher;
  Future<void> _outgoing = Future.value();
  bool closed = false;
  DateTime lastSeen = DateTime.now();
  Future<void> send(Map<String, dynamic> message) {
    final next = _outgoing.then((_) async {
      if (closed) throw StateError(tr('Conexão encerrada.'));
      wire.send(await cipher.encrypt(message));
    });
    _outgoing = next.catchError((_) {});
    return next;
  }

  Stream<Map<String, dynamic>> get messages async* {
    while (!closed) {
      final data = await cipher.decrypt(await wire.read());
      lastSeen = DateTime.now();
      yield data;
    }
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    cipher.destroy();
    await wire.close();
  }
}

class LanPeer {
  LanPeer(
    this.id,
    this.name,
    this.role,
    this.address,
    this.port,
    this.ticket,
    this.target,
    this.resume,
    this.seen,
  );
  final String id, name, role, ticket, target, resume;
  final InternetAddress address;
  final int port;
  final DateTime seen;
}

class LanDiscovery {
  static const _packetWindow = Duration(seconds: 10);
  static const _maxPacketsPerAddress = 120;
  final int bindPort;
  int get port => _socket?.port ?? bindPort;
  RawDatagramSocket? _socket;
  Timer? _timer;
  List<NetworkInterface> _interfaces = [];
  final Map<String, LanPeer> peers = {};
  final void Function() onChanged;
  final Map<String, dynamic> Function() advertisement;
  final Map<String, List<DateTime>> _packetTimes = {};
  LanDiscovery({
    required this.advertisement,
    required this.onChanged,
    this.bindPort = syncPort,
  });
  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      bindPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.multicastHops = 1;
    _interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    if (_socket == null) return;
    for (final interface in _interfaces) {
      try {
        _socket!.joinMulticast(InternetAddress(syncGroup), interface);
      } on SocketException {
        /* An interface can be unavailable. */
      }
    }
    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = _socket?.receive();
      if (packet == null ||
          packet.data.length > 2048 ||
          !isLocalAddress(packet.address)) {
        return;
      }
      if (!_allowPacket(packet.address)) return;
      try {
        final data = jsonObject(utf8.decode(packet.data));
        if (data['app'] != 'passdrive-lan' ||
            data['v'] != syncVersion ||
            data['id'] == advertisement()['id']) {
          return;
        }
        final role = safeString(data['role']);
        if (role != 'desktop' && role != 'phone') return;
        final port = data['port'];
        if (port is! int || port < 0 || port > 65535) return;
        final id = safeString(data['id']);
        if (peers.length >= 64 && !peers.containsKey(id)) return;
        peers[id] = LanPeer(
          id,
          safeString(data['name'], max: 80),
          role,
          packet.address,
          port,
          data['ticket'] is String ? data['ticket'] : '',
          data['target'] is String ? data['target'] : '',
          data['resume'] is String ? data['resume'] : '',
          DateTime.now(),
        );
        onChanged();
      } on Object {
        /* Untrusted discovery messages never authorize access. */
      }
    });
    announce();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      peers.removeWhere(
        (_, peer) => DateTime.now().difference(peer.seen).inSeconds > 8,
      );
      announce();
      onChanged();
    });
  }

  bool _allowPacket(InternetAddress address) {
    final now = DateTime.now();
    final times = _packetTimes[address.address] ?? <DateTime>[];
    times.removeWhere((time) => now.difference(time) >= _packetWindow);
    if (times.length >= _maxPacketsPerAddress) {
      _packetTimes[address.address] = times;
      return false;
    }
    times.add(now);
    _packetTimes[address.address] = times;
    return true;
  }

  void announce() {
    if (_socket == null) return;
    final data = _bytes(
      jsonEncode({
        'app': 'passdrive-lan',
        'v': syncVersion,
        ...advertisement(),
      }),
    );
    for (final interface in _interfaces) {
      try {
        final address = interface.addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .firstOrNull;
        if (address == null) continue;
        _socket!.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            Platform.isWindows ? 9 : 32,
            address.rawAddress,
          ),
        );
        _socket!.send(data, InternetAddress(syncGroup), port);
      } on SocketException {
        /* Try the next local interface. */
      }
    }
    for (final host in [syncGroup, '255.255.255.255']) {
      try {
        _socket?.send(data, InternetAddress(host), port);
      } on SocketException {
        /* Other interfaces may still work. */
      }
    }
  }

  void close() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
    peers.clear();
    _packetTimes.clear();
    _interfaces = [];
  }
}
