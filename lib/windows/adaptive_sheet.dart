import 'dart:math' as math;
import 'package:flutter/material.dart' hide showModalBottomSheet;
import 'package:flutter/material.dart' as material;
import 'desktop_layout.dart';

/// Keeps the existing mobile sheet flows and their results, with desktop dialogs.
Future<T?> showModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  if (!isWindowsDesktop) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return material.showModalBottomSheet<T>(
      context: context,
      builder: (sheetContext) =>
          _MobileSheetSurface(child: builder(sheetContext)),
      isScrollControlled: isScrollControlled,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      backgroundColor: backgroundColor,
      shape: shape,
      constraints: BoxConstraints(maxHeight: screenHeight * .84),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x6615224C),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .025), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
    pageBuilder: (context, animation, secondary) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(620, constraints.maxWidth - 48),
              maxHeight: math.max(100, constraints.maxHeight - 48),
            ),
            child: Material(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: IconButton(
                        tooltip: 'Fechar janela',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: desktopMuted,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  Flexible(child: builder(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Keeps the sheet affordance visible while the content below it scrolls.
///
/// The existing panels already draw their own handle as part of their content.
/// This fixed overlay covers that copy at the top and remains above the panel
/// when it is scrolled.  It is intentionally transparent to hit testing so
/// the modal route's native drag-to-dismiss gesture keeps working.
class _MobileSheetSurface extends StatelessWidget {
  const _MobileSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 38,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCE2EC),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
