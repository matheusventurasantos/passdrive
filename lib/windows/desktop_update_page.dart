import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'desktop_client_page.dart';
import 'desktop_update_checker.dart';

class DesktopUpdatePage extends StatefulWidget {
  const DesktopUpdatePage({super.key});

  @override
  State<DesktopUpdatePage> createState() => _DesktopUpdatePageState();
}

class _DesktopUpdatePageState extends State<DesktopUpdatePage> {
  final _checker = const DesktopUpdateChecker();
  double? _progress;
  String _message = 'Procurando atualizações...';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final update = await _checker.findUpdate();
    if (!mounted) return;
    if (update == null) {
      _continue();
      return;
    }

    setState(() {
      _message = 'Baixando a versão ${update.version}...';
      _progress = 0;
    });
    try {
      await _checker.downloadAndInstall(
        update,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _message = 'Atualização pronta. Reiniciando...';
        _progress = 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } on DesktopUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _progress = null;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      _continue();
    } on Object {
      if (mounted) _continue();
    }
  }

  void _continue() {
    if (!mounted || _finished) return;
    _finished = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DesktopClientPage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF3FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppColors.blue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'PassDrive',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF687899),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: const Color(0xFFE7ECF6),
                    color: AppColors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
