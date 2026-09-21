import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/sync/sync_protocol.dart';
import 'package:passdrive/sync/sync_store.dart';
import 'package:passdrive/sync/desktop_sync.dart';
import 'package:passdrive/sync/mobile_sync.dart';
import 'package:passdrive/vault/vault_models.dart';

class MemorySyncStore implements SyncStore {
  String? value;
  bool fail = false;
  Future<void>? hold;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    await hold;
    if (fail) throw const FileSystemException('Test failure');
    value = data;
  }
}

Future<void> eventually(bool Function() condition) async {
  final until = DateTime.now().add(const Duration(seconds: 8));
  while (!condition() && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

VaultSnapshot fixture([String password = 'secret-only-in-encrypted-wire']) {
  final now = DateTime.utc(2026, 1, 1);
  return VaultSnapshot(
    accounts: [
      VaultAccount(
        id: 'account-1',
        email: 'test@example.com',
        provider: 'Email',
        favorite: false,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    services: [
      VaultService(
        id: 'service-1',
        name: 'Test site',
        email: 'test@example.com',
        url: 'example.com',
        username: 'test',
        password: password,
        favorite: false,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'código tem 3 caracteres; prazo, limite e cancelamento invalidam convite',
    () {
      final now = DateTime.now();
      final t = PairingTicket(now: now);
      expect(t.code, matches(RegExp(r'^[A-Z2-9]{3}$')));
      expect(t.valid(now), true);
      expect(t.valid(now.add(const Duration(minutes: 2))), false);
      for (var i = 0; i < 3; i++) {
        t.claimAttempt();
      }
      expect(t.claimAttempt, throwsFormatException);
      final canceled = PairingTicket()..cancel();
      expect(canceled.valid(), false);
    },
  );
  test(
    'QR usa segredo aleatório, sem credenciais, endereço ou senha mestra',
    () {
      final ticket = PairingTicket(), id = randomToken(16);
      final qr = QrInvitation.parse(ticket.qr(id));
      expect(qr.desktopId, id);
      expect(qr.ticketId, ticket.id);
      expect(qr.secret, ticket.qrSecret);
      expect(
        () => QrInvitation.parse('https://example.com'),
        throwsFormatException,
      );
      expect(
        () => QrInvitation.parse('${ticket.qr(id)}:extra'),
        throwsFormatException,
      );
    },
  );
  test('SRP autentica código válido e rejeita código incorreto', () {
    final host = SrpHost('test', 'ABC'), phone = SrpPhone();
    final proof = phone.proof('test', 'ABC', host.challenge);
    final reply = host.verify(proof);
    expect(phone.verify(reply), host.key);
    expect(jsonEncode([host.challenge, proof, reply]), isNot(contains('ABC')));
    final wrong = SrpHost('test', 'ABC'), attacker = SrpPhone();
    expect(
      () => wrong.verify(attacker.proof('test', 'XYZ', wrong.challenge)),
      throwsFormatException,
    );
    expect(
      () => SrpHost('test', 'ABC').verify({'A': '0', 'M1': '1'}),
      throwsFormatException,
    );
  });
  test(
    'canal cifra conteúdo, autentica direção, rejeita replay e adulteração',
    () async {
      final host = await SyncCipher.create('key', 'context', host: true);
      final phone = await SyncCipher.create('key', 'context', host: false);
      final message = await phone.encrypt({'password': 'plaintext-test'});
      expect(jsonEncode(message), isNot(contains('plaintext-test')));
      expect(await host.decrypt(message), {'password': 'plaintext-test'});
      await expectLater(host.decrypt(message), throwsFormatException);
      final other = await SyncCipher.create('key', 'context', host: true);
      final tampered = Map<String, dynamic>.of(message)
        ..['body'] = base64Encode(List.filled(32, 0));
      await expectLater(other.decrypt(tampered), throwsA(isA<Exception>()));
      await expectLater(phone.decrypt(message), throwsA(isA<Exception>()));
      host.destroy();
      await expectLater(host.encrypt({}), throwsStateError);
      other.destroy();
      phone.destroy();
    },
  );
  test('canal encerra o orçamento agregado de mensagens recebidas', () async {
    final host = await SyncCipher.create('key', 'budget-context', host: true);
    final phone = await SyncCipher.create('key', 'budget-context', host: false);
    for (var index = 0; index < maxSyncMessagesPerWindow; index++) {
      final message = await phone.encrypt({'index': index});
      await host.decrypt(message);
    }
    final overBudget = await phone.encrypt({'index': maxSyncMessagesPerWindow});
    await expectLater(host.decrypt(overBudget), throwsFormatException);
    host.destroy();
    phone.destroy();
  });
  test('descoberta só aceita endereços locais', () {
    expect(isLocalAddress(InternetAddress('192.168.1.2')), true);
    expect(isLocalAddress(InternetAddress('10.0.0.4')), true);
    expect(isLocalAddress(InternetAddress('8.8.8.8')), false);
    expect(isLocalAddress(InternetAddress('172.32.0.1')), false);
  });
  test(
    'preferências protegidas persistem duração e QR desativado por padrão',
    () async {
      final store = MemorySyncStore(), now = DateTime.now();
      final prefs = SyncPreferences(store);
      await prefs.load();
      expect(prefs.autoQr, false);
      prefs.autoQr = true;
      prefs.devices['device'] = DeviceGrant(
        id: 'device',
        name: 'PC',
        secret: randomToken(),
        createdAt: now,
        lastSeen: now,
        expiresAt: ConnectionDuration.forever.expiry(now),
      );
      await prefs.save();
      final restored = SyncPreferences(store);
      await restored.load();
      expect(restored.autoQr, true);
      expect(restored.devices['device']!.expiresAt, null);
      expect(
        restored.devices['device']!.valid(now.add(const Duration(days: 3650))),
        true,
      );
      expect(
        restored.devices['device']!
            .update(duration: ConnectionDuration.minutes15)
            .expiresAt,
        isNotNull,
      );
    },
  );

  group('integração real WebSocket em loopback', () {
    late DesktopSync desktop;
    late MobileSync phone;
    late MemorySyncStore desktopStore, phoneStore;
    late VaultSnapshot snapshot;
    final actions = <RemoteAction>[];
    Future<bool> Function(RemoteAction)? handler;
    LanPeer desktopPeer() => LanPeer(
      desktop.preferences.id,
      'Windows test',
      'desktop',
      InternetAddress.loopbackIPv4,
      desktop.port,
      desktop.ticket!.id,
      phone.preferences.id,
      '',
      DateTime.now(),
    );
    LanPeer phonePeer() => LanPeer(
      phone.preferences.id,
      'Phone test',
      'phone',
      InternetAddress.loopbackIPv4,
      0,
      '',
      '',
      '',
      DateTime.now(),
    );
    Future<void> pair({bool qr = false}) async {
      desktop.selectPhone(phonePeer());
      await phone.pair(
        desktopPeer(),
        secret: qr ? desktop.ticket!.qrSecret : desktop.ticket!.code,
        mode: qr ? 'qr' : 'code',
      );
      await eventually(() => desktop.connected);
    }

    setUp(() async {
      desktopStore = MemorySyncStore();
      phoneStore = MemorySyncStore();
      snapshot = fixture();
      actions.clear();
      handler = null;
      desktop = DesktopSync(store: desktopStore);
      await desktop.start(discover: false);
      phone = MobileSync(
        store: phoneStore,
        readSnapshot: () => snapshot,
        onPairing: (_) {},
        onAction: (a, _) async {
          actions.add(a);
          return await handler?.call(a) ?? false;
        },
      );
      await phone.start(discover: false, useNative: false);
    });
    tearDown(() async {
      await phone.lock();
      phone.dispose();
      desktop.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    test(
      'código pareia, transmite snapshot e nunca persiste senhas no desktop',
      () async {
        await pair();
        expect(
          desktop.snapshot!.services.single.password,
          snapshot.services.single.password,
        );
        expect(phone.preferences.devices.length, 1);
        expect(
          desktopStore.value,
          isNot(contains(snapshot.services.single.password)),
        );
        expect(
          phoneStore.value,
          isNot(contains(snapshot.services.single.password)),
        );
        expect(desktopStore.value, isNot(contains('test@example.com')));
      },
    );
    test('QR válido conecta e QR expirado não autoriza', () async {
      await pair(qr: true);
      expect(desktop.connected, true);
      await desktop.disconnect(forget: true);
      await eventually(() => phone.links.isEmpty);
      desktop.ticket = PairingTicket(
        now: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      await expectLater(
        phone.pair(desktopPeer(), secret: desktop.ticket!.qrSecret, mode: 'qr'),
        throwsA(isA<Exception>()),
      );
      expect(desktop.snapshot, null);
    });
    test('código incorreto e convite cancelado não liberam snapshot', () async {
      desktop.selectPhone(phonePeer());
      await expectLater(
        phone.pair(desktopPeer(), secret: '000'),
        throwsA(isA<Exception>()),
      );
      expect(desktop.snapshot, null);
      expect(desktop.grant, null);
      desktop.ticket!.cancel();
      await expectLater(
        phone.pair(desktopPeer(), secret: desktop.ticket!.code),
        throwsA(isA<Exception>()),
      );
      expect(phone.preferences.devices, isEmpty);
    });
    test('desktop limita handshakes simultâneos por conexão', () async {
      final sockets = <WebSocket>[];
      try {
        sockets.add(
          await WebSocket.connect('ws://127.0.0.1:${desktop.port}/passdrive'),
        );
        sockets.add(
          await WebSocket.connect('ws://127.0.0.1:${desktop.port}/passdrive'),
        );
        await expectLater(
          WebSocket.connect('ws://127.0.0.1:${desktop.port}/passdrive'),
          throwsA(isA<WebSocketException>()),
        );
      } finally {
        for (final socket in sockets) {
          await socket.close();
        }
      }
    });
    test(
      'computador confiável reconecta ao reabrir sem QR Code ou código',
      () async {
        await pair();
        await phone.setTrusted(desktop.preferences.id, true);
        await eventually(() => desktop.trusted);
        final phoneGrant = phone.preferences.devices.values.single;
        desktop.dispose();
        await eventually(() => phone.links.isEmpty);
        desktop = DesktopSync(store: desktopStore);
        await desktop.start(discover: false);
        expect(desktop.snapshot, null);
        await phone.pair(
          desktopPeer(),
          secret: phoneGrant.secret,
          mode: 'resume',
        );
        await eventually(() => desktop.connected);
      },
    );
    test(
      'as preferências de confiança e foco são individuais e persistem',
      () async {
        await pair();
        final id = desktop.preferences.id;
        expect(phone.preferences.devices[id]!.trusted, isFalse);
        expect(phone.preferences.devices[id]!.lockOnFocusLoss, isTrue);
        await phone.setTrusted(id, true);
        await phone.setLockOnFocusLoss(id, false);
        await eventually(() => desktop.trusted && !desktop.lockOnFocusLoss);
        final restored = SyncPreferences(phoneStore);
        await restored.load();
        expect(restored.devices[id]!.trusted, isTrue);
        expect(restored.devices[id]!.lockOnFocusLoss, isFalse);
      },
    );
    test('perda de rede limpa visualização mas permite reconectar', () async {
      await pair();
      final grant = phone.preferences.devices.values.single;
      await desktop.disconnect();
      expect(desktop.snapshot, null);
      expect(desktop.grant, isNotNull);
      await eventually(() => phone.links.isEmpty);
      await phone.pair(desktopPeer(), secret: grant.secret, mode: 'resume');
      await eventually(() => desktop.connected);
    });
    test(
      'bloqueio desktop revoga autorização e bloqueio celular limpa memória',
      () async {
        await pair();
        await desktop.disconnect(forget: true);
        await eventually(() => phone.preferences.devices.isEmpty);
        expect(desktop.grant, null);
        expect(desktop.snapshot, null);
        await pair();
        await phone.lock();
        await eventually(() => desktop.grant == null);
        expect(desktop.snapshot, null);
      },
    );
    test(
      'revogação pelo celular e expiração de grant impedem acesso',
      () async {
        await pair();
        await phone.revoke(desktop.preferences.id);
        await eventually(() => desktop.grant == null);
        expect(desktop.snapshot, null);
        await pair();
        final g = phone.preferences.devices.values.single;
        phone.preferences.devices[g.id] = DeviceGrant(
          id: g.id,
          name: g.name,
          secret: g.secret,
          createdAt: g.createdAt,
          lastSeen: g.lastSeen,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        );
        await desktop.disconnect();
        await eventually(() => phone.links.isEmpty);
        await expectLater(
          phone.pair(desktopPeer(), secret: g.secret, mode: 'resume'),
          throwsFormatException,
        );
        expect(desktop.snapshot, null);
      },
    );
    test(
      'pedido de criar/editar/excluir não altera dados sem aprovação mobile',
      () async {
        await pair();
        for (final kind in [
          RemoteActionKind.addService,
          RemoteActionKind.editService,
          RemoteActionKind.deleteService,
          RemoteActionKind.favoriteAccount,
        ]) {
          final response = await desktop.request(
            RemoteAction(kind, itemId: 'service-1'),
          );
          expect(response, contains('cancelada'));
          expect(desktop.snapshot!.services.length, 1);
        }
        expect(actions.length, 4);
        handler = (_) async {
          snapshot = fixture('changed-only-by-phone');
          return true;
        };
        expect(
          await desktop.request(
            RemoteAction(RemoteActionKind.editService, itemId: 'service-1'),
          ),
          contains('concluída'),
        );
        expect(
          desktop.snapshot!.services.single.password,
          'changed-only-by-phone',
        );
      },
    );
    test('publicação após salvar atualiza serviços e favoritos', () async {
      await pair();
      snapshot = snapshot.copyWith(
        services: [snapshot.services.single.copyWith(favorite: true)],
      );
      phone.publish();
      await eventually(() => desktop.snapshot!.services.single.favorite);
      snapshot = snapshot.copyWith(services: []);
      phone.publish();
      await eventually(() => desktop.snapshot!.services.isEmpty);
    });
    test('cancelar autorização enquanto salva não libera o desktop', () async {
      final hold = Completer<void>();
      phoneStore.hold = hold.future;
      final attempt = PairingAttempt();
      desktop.selectPhone(phonePeer());
      final operation = phone.pair(
        desktopPeer(),
        secret: desktop.ticket!.code,
        attempt: attempt,
      );
      final rejected = expectLater(operation, throwsStateError);
      await eventually(() => phone.preferences.devices.isNotEmpty);
      attempt.cancel();
      hold.complete();
      await rejected;
      expect(desktop.snapshot, null);
      expect(phone.preferences.devices, isEmpty);
    });
    test('falha ao persistir autorização não libera o cofre', () async {
      phoneStore.fail = true;
      desktop.selectPhone(phonePeer());
      await expectLater(
        phone.pair(desktopPeer(), secret: desktop.ticket!.code),
        throwsA(isA<FileSystemException>()),
      );
      expect(desktop.snapshot, null);
      phoneStore.fail = false;
    });
    test(
      'falha no armazenamento Windows exige confirmação e desfaz pareamento',
      () async {
        desktopStore.fail = true;
        desktop.selectPhone(phonePeer());
        await expectLater(
          phone.pair(desktopPeer(), secret: desktop.ticket!.code),
          throwsA(isA<Exception>()),
        );
        expect(desktop.snapshot, null);
        expect(desktop.grant, null);
        expect(phone.preferences.devices, isEmpty);
        desktopStore.fail = false;
      },
    );
    test('mesma solicitação não pode ser executada duas vezes', () async {
      await pair();
      final action = RemoteAction(RemoteActionKind.addAccount);
      await desktop.request(action);
      await desktop.request(action);
      await eventually(() => !desktop.connected);
      expect(actions.length, 1);
    });
  });
  test(
    'descoberta UDP recebe telefone local e ignora versões ou dados inválidos',
    () async {
      final discovery = LanDiscovery(
        bindPort: 0,
        advertisement: () => {
          'id': 'test-desktop',
          'name': 'Desktop',
          'role': 'desktop',
          'port': 0,
        },
        onChanged: () {},
      );
      await discovery.start();
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      try {
        void send(Map<String, dynamic> packet) {
          final bytes = utf8.encode(jsonEncode(packet));
          socket.send(bytes, InternetAddress.loopbackIPv4, discovery.port);
        }

        send({
          'app': 'passdrive-lan',
          'v': 1,
          'id': 'test-phone',
          'name': 'Galaxy',
          'role': 'phone',
          'port': 0,
        });
        await eventually(() => discovery.peers.containsKey('test-phone'));
        expect(discovery.peers['test-phone']!.name, 'Galaxy');
        send({
          'app': 'passdrive-lan',
          'v': 999,
          'id': 'bad',
          'name': 'Invalid',
          'role': 'phone',
          'port': 0,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(discovery.peers.containsKey('bad'), false);
      } finally {
        socket.close();
        discovery.close();
      }
    },
  );
}
