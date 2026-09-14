import 'package:flutter/material.dart';

import 'windows/desktop_window_frame.dart';
import 'windows/desktop_layout.dart';
import 'vault/vault_gate_page.dart';
import 'windows/desktop_client_page.dart';
import 'autofill/autofill_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AutofillBridge.initialize();
  runApp(const PassDriveApp());
}

class PassDriveApp extends StatelessWidget {
  const PassDriveApp({this.home, super.key});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final content =
        home ??
        (isWindowsDesktop ? const DesktopClientPage() : const VaultGatePage());
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PassDrive',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Kumbh Sans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4862E0),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      builder: (context, child) => isWindowsDesktop
          ? Overlay.wrap(
              child: DesktopWindowFrame(
                child: child ?? const SizedBox.shrink(),
              ),
            )
          : child ?? const SizedBox.shrink(),
      home: content,
    );
  }
}
