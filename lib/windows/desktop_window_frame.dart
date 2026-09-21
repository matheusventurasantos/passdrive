import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../sync/sync_status.dart';

import '../theme/app_colors.dart';

/// Desktop-only chrome for the Windows build.
///
/// Wraps the navigator so custom window controls remain on every route.
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppPalette.resolve(Colors.white),
      child: Column(
        children: [
          const _DesktopTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DesktopTitleBar extends StatefulWidget {
  const _DesktopTitleBar();

  @override
  State<_DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<_DesktopTitleBar>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('passdrive/window');

  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readMaximizedState();
  }

  @override
  void didChangeMetrics() => _readMaximizedState();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _readMaximizedState() async {
    try {
      final value = await _channel.invokeMethod<bool>('isMaximized');
      if (mounted) setState(() => _maximized = value ?? false);
    } on MissingPluginException {
      // The chrome is only mounted on Windows, but keeping this fallback
      // makes widget previews and tests harmless.
    }
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native window exists in a widget-test environment.
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 48,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () async {
                  await _invoke('toggleMaximize');
                  await _readMaximizedState();
                },
                onPanStart: (_) => _invoke('startDrag'),
                child: Row(
                  children: [
                    const SizedBox(width: 22),
                    const _ConnectionSignal(),
                    const SizedBox(width: 10),
                    Flexible(
                      child: ValueListenableBuilder<String>(
                        valueListenable: desktopConnectionStatus,
                        builder: (_, status, _) => Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _WindowButton(
              tooltip: tr('Minimizar'),
              icon: Icons.remove_rounded,
              onTap: () => _invoke('minimize'),
            ),
            _WindowButton(
              tooltip: _maximized ? tr('Restaurar') : tr('Maximizar'),
              icon: _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              onTap: () async {
                await _invoke('toggleMaximize');
                await _readMaximizedState();
              },
            ),
            _WindowButton(
              tooltip: tr('Fechar'),
              icon: Icons.close_rounded,
              isClose: true,
              onTap: () => _invoke('close'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ConnectionSignal extends StatefulWidget {
  const _ConnectionSignal();

  @override
  State<_ConnectionSignal> createState() => _ConnectionSignalState();
}

class _ConnectionSignalState extends State<_ConnectionSignal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: desktopConnectionOnline,
      builder: (context, online, _) {
        final color = online
            ? AppPalette.resolve(const Color(0xFF40B878))
            : AppPalette.resolve(const Color(0xFF8D99AE));
        return Semantics(
          label: online
              ? tr('Dispositivo conectado')
              : tr('Nenhum dispositivo conectado'),
          child: SizedBox.square(
            dimension: 16,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = Curves.easeOut.transform(_controller.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: (1 - progress) * .34,
                      child: Transform.scale(
                        scale: 1 + progress * 1.45,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 8),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 7),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: isClose
            ? AppPalette.resolve(const Color(0xFFFFE9EC))
            : AppPalette.resolve(const Color(0xFFF1F3F9)),
        child: SizedBox(
          width: 42,
          height: 38,
          child: Icon(
            icon,
            size: 17,
            color: isClose
                ? AppPalette.resolve(const Color(0xFFD94A5B))
                : AppColors.navy,
          ),
        ),
      ),
    );
  }
}
