import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passdrive/vault/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String clipboard = '';

  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String? ?? '';
              return null;
            case 'Clipboard.getData':
              return {'text': clipboard};
          }
          return null;
        });
  });

  tearDown(() {
    SecureClipboard.resetForTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('limpa um segredo após o intervalo configurado', () async {
    await SecureClipboard.copy(
      'segredo',
      clearAfter: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(clipboard, isEmpty);
  });

  test('não apaga texto copiado depois pelo usuário', () async {
    await SecureClipboard.copy(
      'segredo',
      clearAfter: const Duration(milliseconds: 1),
    );
    await Clipboard.setData(const ClipboardData(text: 'texto novo'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(clipboard, 'texto novo');
  });

  test(
    'mantém a cópia durante a janela de colagem após perder o foco',
    () async {
      await SecureClipboard.copy('segredo');
      SecureClipboard.scheduleClearAfterFocusLoss();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(clipboard, 'segredo');
    },
  );

  test(
    'mantém a cópia quando a limpeza automática estiver desativada',
    () async {
      SecureClipboard.configure(null);
      await SecureClipboard.copy('segredo');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(clipboard, 'segredo');
    },
  );
}
