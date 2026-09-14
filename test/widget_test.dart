// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:passdrive/generator/password_quality.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:passdrive/generator/password_generator_page.dart';
import 'package:passdrive/main.dart';
import 'package:passdrive/navigation/passdrive_shell.dart';
import 'package:passdrive/passwords/passwords_page.dart';
import 'package:passdrive/vault/vault_crypto.dart';

void main() {
  test('qualidade penaliza padrões previsíveis sem premiar só tamanho', () {
    for (final value in [
      'aaaaaaaaAAAAAAAA1111!!!!',
      'abcabcabcabcabcabc',
      'Senha123456!2025',
      'Maria01011990!',
      '11987654321',
      '01/01/1990',
      '12345678901234567890',
      'Qwerty1234!',
    ]) {
      expect(passwordLevel(value), lessThanOrEqualTo(2), reason: value);
    }
    expect(passwordLevel(''), 0);
    expect(passwordLevel('aB2!'), 1);
    expect(passwordLevel('vR9!mT4@xK7#pZ2&'), 5);
  });
  test('gerador respeita ausência de tipos e tipos selecionados', () {
    expect(
      createStrongPassword(
        uppercase: false,
        lowercase: false,
        numbers: false,
        symbols: false,
      ),
      isEmpty,
    );
    final digits = createStrongPassword(
      length: 24,
      uppercase: false,
      lowercase: false,
      symbols: false,
    );
    expect(digits, matches(RegExp(r'^[2-9]{24}$')));

    for (var index = 0; index < 12; index++) {
      final password = createStrongPassword(length: 16);
      expect(password, matches(RegExp(r'[A-Z]')));
      expect(password, matches(RegExp(r'[a-z]')));
      expect(password, matches(RegExp(r'[2-9]')));
      expect(password, matches(RegExp(r'[!@#\$%&*]')));
    }
  });
  test(
    'cofre deriva uma chave e rejeita senha ou payload adulterado',
    () async {
      final crypto = VaultCrypto();
      final created = await crypto.create('senha-mestra-segura');
      final metadata = VaultMetadata.fromJson(created.metadata.toJson());
      final unlocked = await crypto.unlock('senha-mestra-segura', metadata);
      final encrypted = await crypto.encryptSnapshot(
        '{"services":[{"password":"segredo"}]}',
        unlocked,
      );

      expect(
        await crypto.decryptSnapshot(encrypted, unlocked),
        '{"services":[{"password":"segredo"}]}',
      );
      await expectLater(
        crypto.unlock('senha-incorreta', metadata),
        throwsA(isA<VaultUnlockException>()),
      );

      final tamperedJson = encrypted.toJson();
      final cipherText = tamperedJson['cipherText']! as String;
      final replacement = cipherText[0] == 'A' ? 'B' : 'A';
      tamperedJson['cipherText'] = '$replacement${cipherText.substring(1)}';
      final tampered = EncryptedVaultPayload.fromJson(tamperedJson);
      await expectLater(
        crypto.decryptSnapshot(tampered, unlocked),
        throwsA(isA<VaultUnlockException>()),
      );
    },
  );
  test('personalização altera a senha atual sem recriar os caracteres', () {
    const original = 'A23Um34RN23';
    expect(
      removeDisabledPasswordCharacters(
        original,
        uppercase: true,
        lowercase: false,
        numbers: true,
        symbols: true,
        avoidSimilar: false,
      ),
      'A23U34RN23',
    );

    final extended = resizeExistingPassword(
      original,
      length: original.length + 1,
      uppercase: true,
      lowercase: true,
      numbers: true,
      symbols: true,
      avoidSimilar: false,
    );
    expect(extended.startsWith(original), isTrue);
    expect(extended.length, original.length + 1);
    expect(
      resizeExistingPassword(
        original,
        length: original.length - 1,
        uppercase: true,
        lowercase: true,
        numbers: true,
        symbols: true,
        avoidSimilar: false,
      ),
      original.substring(0, original.length - 1),
    );
  });
  testWidgets('cadastro acompanha teclado e anima troca do seletor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Adicionar serviço')).dy;
    await tester.tap(find.text('Adicionar serviço'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(
      tester.getTopLeft(find.text('Adicionar serviço')).dy,
      greaterThan(before),
    );
    await tester.pumpAndSettle();
    final password = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Digite uma senha forte',
    );
    await tester.tap(password);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    await tester.ensureVisible(password);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(password).dy, lessThanOrEqualTo(524));
    expect(
      tester.getBottomRight(find.text('Continuar')).dy,
      lessThanOrEqualTo(524),
    );
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('abre diretamente na home', (WidgetTester tester) async {
    await tester.pumpWidget(const PassDriveApp(home: PassDriveShell()));

    expect(find.text('Saúde das senhas'), findsOneWidget);
    expect(find.text('Verificado há 2 min'), findsOneWidget);
    expect(find.text('Sincronização'), findsNothing);
    expect(find.text('Contas'), findsOneWidget);
    expect(find.text('joao@gmail.com'), findsOneWidget);
    expect(find.text('joao@outlook.com'), findsOneWidget);
    expect(find.text('contato@empresa.com'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
  });

  testWidgets('a home permite rolagem vertical', (WidgetTester tester) async {
    await tester.pumpWidget(const PassDriveApp(home: PassDriveShell()));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Senhas separa contas, serviços e filtra a busca', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));

    expect(find.text('Minhas senhas'), findsOneWidget);
    expect(find.text('Contas'), findsOneWidget);
    expect(find.text('joao@gmail.com'), findsNWidgets(3));
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Senhas'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'PayPal');
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'PayPal',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Google',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'joao@gmail.com',
      ),
      findsNothing,
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('busca sem resultados pode ser limpa diretamente', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    await tester.enterText(find.byType(TextField), 'nao-existe');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum resultado encontrado'), findsWidgets);
    expect(find.text('Limpar busca'), findsWidgets);
    await tester.tap(find.text('Limpar busca').first);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum resultado encontrado'), findsNothing);
    expect(find.text('Google'), findsOneWidget);
  });

  testWidgets('organização da aba Senhas abre e aplica ordenação', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));

    final organizeButton = find.text('Organizar');
    await tester.ensureVisible(organizeButton);
    await tester.tap(organizeButton);
    await tester.pumpAndSettle();
    expect(find.text('Organizar senhas'), findsOneWidget);
    expect(find.text('Nome (A–Z)'), findsOneWidget);

    await tester.tap(find.text('Nome (A–Z)'));
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.text('Organizar'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
  });

  testWidgets('adiciona uma conta pelo seletor do botão mais', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar conta'), findsOneWidget);
    expect(find.text('Adicionar serviço'), findsOneWidget);

    await tester.tap(find.text('Adicionar conta'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar conta'), findsOneWidget);
    expect(find.text('Email principal'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'voce@exemplo.com',
      ),
      'pessoa@yahoo.com',
    );
    tester.testTextInput.closeConnection();
    await tester.pump();
    expect(find.text('Provedor identificado: Yahoo'), findsOneWidget);

    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();

    expect(find.text('pessoa@yahoo.com'), findsOneWidget);
  });

  testWidgets('adiciona um serviço e vincula uma conta existente', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar serviço'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Seu usuário no serviço',
      ),
      'pessoa',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Digite ou selecione um email',
      ),
      'joao@',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('joao@gmail.com').last);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(find.byIcon(Icons.alternate_email), findsNothing);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Digite uma senha forte',
      ),
      'SenhaForte#123',
    );
    tester.testTextInput.closeConnection();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'GitHub, Netflix ou PayPal',
      ),
      'GitLab',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'github.com',
      ),
      'gitlab.com',
    );

    await tester.tap(find.text('Salvar serviço'));
    await tester.pumpAndSettle();

    expect(find.text('GitLab'), findsOneWidget);
    expect(find.text('joao@gmail.com'), findsNWidgets(4));
  });

  testWidgets('menu da conta edita e impede excluir conta vinculada', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções').first);
    await tester.pumpAndSettle();
    expect(find.text('Editar conta'), findsOneWidget);
    expect(find.text('Excluir conta'), findsOneWidget);

    await tester.tap(find.text('Editar conta'));
    await tester.pumpAndSettle();
    expect(find.text('Editar conta'), findsOneWidget);
    expect(find.text('Salvar alterações'), findsOneWidget);
    expect(find.text('joao@gmail.com'), findsWidgets);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Pessoal, trabalho ou faculdade',
      ),
      'Conta pessoal',
    );
    tester.testTextInput.closeConnection();
    await tester.pump();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(find.text('Conta pessoal'), findsOneWidget);

    await tester.tap(find.byTooltip('Mais opções').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir conta?'), findsOneWidget);
    expect(
      find.text(
        'Esta conta possui serviços vinculados. Remova ou transfira esses serviços antes de excluir.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.text('joao@gmail.com'), findsWidgets);
  });

  testWidgets('exclusão de conta livre pode ser cancelada ou confirmada', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar conta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'voce@exemplo.com',
      ),
      'livre@example.com',
    );
    tester.testTextInput.closeConnection();
    await tester.pump();
    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções').at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();
    expect(find.text('Essa conta será removida do cofre.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('livre@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Mais opções').at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('livre@example.com'), findsNothing);
  });

  testWidgets('exclusão de serviço exige confirmação e pode ser cancelada', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir serviço?'), findsOneWidget);
    expect(
      find.text('Essa credencial será removida do cofre.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Google'), findsOneWidget);

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Google'), findsNothing);
  });

  testWidgets('menu do serviço reutiliza o formulário para edição', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar serviço'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Digite uma senha forte',
      ),
      'NovaSenha#2026',
    );
    tester.testTextInput.closeConnection();
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'GitHub, Netflix ou PayPal',
      ),
      'Google editado',
    );
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(find.text('Google editado'), findsOneWidget);
  });

  testWidgets('Início retorna da tela Senhas para a origem', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PasswordsPage(),
                  ),
                );
              },
              child: const Text('Abrir Senhas'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir Senhas'));
    await tester.pumpAndSettle();
    expect(find.text('Minhas senhas'), findsOneWidget);

    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir Senhas'), findsOneWidget);
  });

  testWidgets('Gerador exibe e permite ajustar a senha', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(720, 1280)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PasswordGeneratorPage()));

    expect(find.text('Gerador de senhas'), findsOneWidget);
    expect(find.text('Sua senha segura'), findsOneWidget);
    expect(find.text('Personalizar senha'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.text('Personalizar senha'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(5));
    expect(find.text('Dicas de segurança'), findsOneWidget);

    await tester.tap(find.text('Gerar outra senha'));
    await tester.tap(find.byIcon(Icons.copy_outlined));
    for (var index = 0; index < 4; index++) {
      final option = find.byType(Switch).at(index);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
    }
    await tester.pump();
    expect(
      find.text('Ative pelo menos um tipo de caractere para gerar.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Gerar outra senha'),
          )
          .onPressed,
      isNull,
    );
    await tester.drag(find.byType(Slider), const Offset(70, 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('troca páginas por arraste mantendo a navbar do shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PassDriveApp(home: PassDriveShell()));

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('Saúde das senhas'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Minhas senhas'), findsOneWidget);
    expect(find.text('Senhas'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Gerador de senhas'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await tester.pump();
    expect(find.text('Ajustes'), findsNWidgets(2));
    expect(find.text('Segurança'), findsOneWidget);
    expect(
      find.text('Senha do app, biometria e bloqueio automático'),
      findsOneWidget,
    );
    expect(find.text('Sincronização e dispositivos'), findsOneWidget);
    expect(find.text('Backup e recuperação'), findsOneWidget);
    expect(find.text('Privacidade'), findsOneWidget);
    expect(find.text('Sobre'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Saúde das senhas'), findsOneWidget);
  });

  testWidgets('aviso de segurança pode ser fechado durante a sessão', (
    WidgetTester tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurityAlert(
            title: 'Existem senhas fracas',
            message: 'Atualize suas senhas para proteger melhor suas contas.',
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('Existem senhas fracas'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar aviso'));
    expect(closed, isTrue);
  });

  testWidgets('favoritar serviço anima a mudança para o topo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordsPage()));
    final favorite = find.byTooltip('Adicionar aos favoritos').last;
    await tester.ensureVisible(favorite);
    await tester.tap(favorite);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
