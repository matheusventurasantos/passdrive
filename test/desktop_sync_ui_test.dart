import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/main.dart';
import 'package:passdrive/windows/desktop_client_page.dart';
import 'package:passdrive/windows/desktop_sidebar.dart';
import 'package:passdrive/sync/desktop_sync.dart';
import 'package:passdrive/sync/mobile_sync.dart';
import 'package:passdrive/sync/sync_devices_sheet.dart';
import 'package:passdrive/sync/sync_protocol.dart';
import 'package:passdrive/sync/sync_store.dart';
import 'package:passdrive/vault/vault_database.dart';
import 'package:passdrive/vault/vault_models.dart';
import 'lan_sync_test.dart' show MemorySyncStore, fixture;

class PreviewSync extends DesktopSync {
  PreviewSync() : super(store: MemorySyncStore()) {
    ticket = PairingTicket();
    status = 'Aguardando sincronização';
    searching = true;
  }
  final actions = <RemoteAction>[];
  @override
  bool get connected => snapshot != null;
  void display(VaultSnapshot? value) {
    snapshot = value;
    notifyListeners();
  }

  @override
  Future<String> request(RemoteAction action) async {
    actions.add(action);
    return 'Continue no celular.';
  }
}

class PhonePreview extends MobileSync {
  PhonePreview()
    : super(
        readSnapshot: fixture,
        onAction: (_, _) async => false,
        onPairing: (_) {},
        store: MemorySyncStore(),
      ) {
    ready = true;
  }
  void offer(LanPeer peer) {
    incomingPairing = peer;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Kumbh Sans');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/KumbhSans-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> mount(
    WidgetTester tester,
    PreviewSync sync, {
    double scale = 1,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      PassDriveApp(home: DesktopClientPage(controller: sync)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text(label),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Windows abre conexão sem login, banco ou cadastro', (
    tester,
  ) async {
    final sync = PreviewSync();
    addTearDown(sync.dispose);
    await mount(tester, sync);
    expect(find.text('Conectar ao celular'), findsOneWidget);
    expect(find.text('Escaneie o QR Code'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ajustes'), findsNothing);
    await expectLater(VaultDatabase.open(), throwsUnsupportedError);
    if (const bool.fromEnvironment('DESKTOP_PREVIEWS')) {
      await expectLater(
        find.byType(PassDriveApp),
        matchesGoldenFile('../.dart_tool/desktop-previews/conexao-lan.png'),
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('Windows limpa o snapshot ao perder visibilidade', (
    tester,
  ) async {
    final sync = PreviewSync()..snapshot = fixture();
    addTearDown(sync.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await mount(tester, sync);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(sync.snapshot, isNull);
    expect(find.text('Conectar ao celular'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('três abas fixas e + solicita ao celular sem abrir formulário', (
    tester,
  ) async {
    final sync = PreviewSync()..snapshot = fixture();
    addTearDown(sync.dispose);
    await mount(tester, sync);
    final sidebar = tester.getRect(find.byType(DesktopSidebar));
    expect(find.text('Ajustes'), findsNothing);
    await select(tester, 'Senhas');
    expect(tester.getRect(find.byType(DesktopSidebar)), sidebar);
    await tester.tap(find.text('Adicionar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Adicionar serviço'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sync.actions.single.kind, RemoteActionKind.addService);
    expect(find.text('Nome do serviço'), findsNothing);
    expect(sync.snapshot!.services.length, 1);
    await select(tester, 'Gerador');
    expect(tester.getRect(find.byType(DesktopSidebar)), sidebar);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets(
    'busca permanece após snapshot novo e desconectar remove detalhes',
    (tester) async {
      final sync = PreviewSync()..snapshot = fixture();
      addTearDown(sync.dispose);
      await mount(tester, sync);
      await select(tester, 'Senhas');
      await tester.enterText(find.byType(TextField).first, 'Test site');
      sync.display(fixture('other-secret'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Test site',
      );
      await tester.tap(find.text('Test site').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Editar'), findsWidgets);
      expect(find.text('other-secret'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data ?? '').contains('••'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Mostrar Senha'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar Senha'));
      await tester.pump();
      expect(find.text('other-secret'), findsOneWidget);
      expect(find.byTooltip('Ocultar Senha'), findsOneWidget);
      sync.display(null);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Conectar ao celular'), findsOneWidget);
      expect(find.text('Test site'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets('conexão e páginas suportam janela mínima com texto 2x', (
    tester,
  ) async {
    final sync = PreviewSync();
    addTearDown(sync.dispose);
    await mount(tester, sync, size: const Size(960, 640), scale: 2);
    expect(tester.takeException(), isNull);
    sync.display(fixture());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final label in ['Senhas', 'Gerador', 'Início']) {
      await select(tester, label);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('autorização mobile tem validação de código e cabe com teclado', (
    tester,
  ) async {
    final phone = MobileSync(
      readSnapshot: fixture,
      onAction: (_, _) async => false,
      onPairing: (_) {},
      store: MemorySyncStore(),
    );
    addTearDown(phone.dispose);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      PassDriveApp(
        home: Scaffold(
          body: PairingApprovalSheet(
            sync: phone,
            peer: LanPeer(
              randomToken(16),
              'Meu computador Windows',
              'desktop',
              InternetAddress.loopbackIPv4,
              1234,
              randomToken(16),
              '',
              '',
              DateTime.now(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Autorizar conexão'));
    await tester.tap(find.text('Autorizar conexão'));
    await tester.pumpAndSettle();
    expect(
      find.text('Digite os 3 caracteres exibidos no computador.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('pedido recebido troca o menu aberto e retorna após cancelar', (
    tester,
  ) async {
    final phone = PhonePreview();
    addTearDown(phone.dispose);
    await tester.pumpWidget(
      PassDriveApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSyncDevices(context, phone),
              child: const Text('Abrir dispositivos'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir dispositivos'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronização e dispositivos'), findsOneWidget);
    phone.offer(
      LanPeer(
        randomToken(16),
        'Windows',
        'desktop',
        InternetAddress.loopbackIPv4,
        1234,
        randomToken(16),
        '',
        '',
        DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Autorizar computador'), findsOneWidget);
    expect(find.text('Sincronização e dispositivos'), findsNothing);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Sincronização e dispositivos'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
