import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import '../windows/desktop_layout.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class RecoveryKeyConfirmationSheet extends StatelessWidget {
  const RecoveryKeyConfirmationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 38,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                tr('Salvar chave-mestra?'),
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Este arquivo abre seu cofre sem a senha. Guarde-o em um local seguro e não o compartilhe.',
                ),
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppPalette.resolve(const Color(0xFFD6DAE7)),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(tr('Agora não')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(tr('Baixar chave')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
