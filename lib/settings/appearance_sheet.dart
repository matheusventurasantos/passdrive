import 'package:flutter/material.dart';
import 'appearance_preferences.dart';

class AppearanceSheet extends StatefulWidget {
  const AppearanceSheet({super.key});
  @override
  State<AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<AppearanceSheet> {
  final preferences = AppearancePreferences.instance;
  String? error;
  double? draftScale;
  String text(String pt, String en) => preferences.language == 'en' ? en : pt;
  Future<void> save({
    ThemeMode? mode,
    double? scale,
    String? language,
    bool? share,
  }) async {
    setState(() => error = null);
    try {
      await preferences.update(
        mode: mode,
        fontScale: scale,
        language: language,
        shareTheme: share,
      );
    } on Object {
      if (mounted) {
        setState(
          () => error = text(
            'Não foi possível salvar esta preferência.',
            'Could not save this preference.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => draftScale = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text('Aparência e idioma', 'Appearance and language'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<ThemeMode>(
              initialValue: preferences.mode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: text('Tema', 'Theme'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(text('Usar tema do sistema', 'Use system theme')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(text('Claro', 'Light')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(text('Escuro', 'Dark')),
                ),
              ],
              onChanged: preferences.saving
                  ? null
                  : (value) => save(mode: value),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                text(
                  'Aplicar no dispositivo conectado',
                  'Apply to the connected device',
                ),
              ),
              subtitle: Text(
                text(
                  'O desktop usa este tema durante a conexão.',
                  'The desktop uses this theme while connected.',
                ),
              ),
              value: preferences.shareTheme,
              onChanged: preferences.saving
                  ? null
                  : (value) => save(share: value),
            ),
            const SizedBox(height: 20),
            Text(
              text('Tamanho da fonte', 'Font size'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: draftScale ?? preferences.fontScale,
              min: .85,
              max: 1.3,
              divisions: 9,
              label:
                  '${((draftScale ?? preferences.fontScale) * 100).round()}%',
              onChanged: preferences.saving
                  ? null
                  : (value) => setState(() => draftScale = value),
              onChangeEnd: (value) => save(scale: value),
            ),
            Text(
              text(
                'A escala de acessibilidade do sistema também é respeitada.',
                'The system accessibility text scale is also respected.',
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: preferences.language,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: text('Idioma', 'Language'),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'pt',
                  child: Text('Português (Brasil)'),
                ),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: preferences.saving
                  ? null
                  : (value) => save(language: value),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
