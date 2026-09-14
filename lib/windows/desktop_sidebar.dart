import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import 'desktop_layout.dart';

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onLock,
    this.viewer = false,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onLock;
  final bool viewer;
  @override
  Widget build(BuildContext context) => Container(
    width:
        224 + (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1) * 100,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: desktopLine)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          child: Row(
            children: [
              SvgPicture.asset('logo.svg', width: 38, height: 38),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'PassDrive',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: -.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'MEU COFRE',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: desktopMuted,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (var index = 0; index < (viewer ? 3 : 4); index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: selectedIndex == index
                        ? const Color(0xFFEDF1FF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selectedIndex == index,
                      selectedColor: AppColors.blue,
                      textColor: desktopMuted,
                      iconColor: desktopMuted,
                      leading: Icon(
                        [
                          Icons.space_dashboard_outlined,
                          Icons.lock_outline_rounded,
                          Icons.key_rounded,
                          Icons.tune_rounded,
                        ][index],
                        size: 23,
                      ),
                      title: Text(
                        ['Início', 'Senhas', 'Gerador', 'Ajustes'][index],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: selectedIndex == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () => onSelected(index),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: desktopLine),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: onLock,
                icon: const Icon(Icons.lock_clock_outlined, size: 18),
                label: const Text('Bloquear cofre'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: desktopLine),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                viewer
                    ? 'Conexão local criptografada'
                    : 'Armazenado neste computador',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: desktopMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
