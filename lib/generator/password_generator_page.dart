import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'dart:math';
import '../windows/desktop_layout.dart';
import 'password_quality.dart';
import '../widgets/animated_password_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../passwords/passwords_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../vault/secure_clipboard.dart';

String createStrongPassword({
  int length = 18,
  bool uppercase = true,
  bool lowercase = true,
  bool numbers = true,
  bool symbols = true,
  bool avoidSimilar = true,
}) {
  const allUppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const allLowercase = 'abcdefghijklmnopqrstuvwxyz';
  const allNumbers = '0123456789';
  final selectedUppercase = avoidSimilar
      ? 'ABCDEFGHJKLMNPQRSTUVWXYZ'
      : allUppercase;
  final selectedLowercase = avoidSimilar
      ? 'abcdefghijkmnopqrstuvwxyz'
      : allLowercase;
  final selectedNumbers = avoidSimilar ? '23456789' : allNumbers;
  const symbolsPool = '!@#\$%&*';
  final pools = <String>[];
  if (uppercase) pools.add(selectedUppercase);
  if (lowercase) pools.add(selectedLowercase);
  if (numbers) pools.add(selectedNumbers);
  if (symbols) pools.add(symbolsPool);
  if (pools.isEmpty || length <= 0) return '';

  final random = Random.secure();
  final characters = pools.join();
  final result = List.generate(
    length,
    (_) => characters[random.nextInt(characters.length)],
  );
  for (var index = 0; index < pools.length && index < result.length; index++) {
    final pool = pools[index];
    result[index] = pool[random.nextInt(pool.length)];
  }
  result.shuffle(random);
  return result.join();
}

String resizeExistingPassword(
  String password, {
  required int length,
  required bool uppercase,
  required bool lowercase,
  required bool numbers,
  required bool symbols,
  required bool avoidSimilar,
}) {
  if (length <= password.length) return password.substring(0, length);

  final pools = <String>[
    if (uppercase)
      avoidSimilar ? 'ABCDEFGHJKLMNPQRSTUVWXYZ' : 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    if (lowercase)
      avoidSimilar ? 'abcdefghijkmnopqrstuvwxyz' : 'abcdefghijklmnopqrstuvwxyz',
    if (numbers) avoidSimilar ? '23456789' : '0123456789',
    if (symbols) '!@#\$%&*',
  ];
  if (pools.isEmpty) return password;

  final pool = pools.join();
  final random = Random.secure();
  final suffix = List.generate(
    length - password.length,
    (_) => pool[random.nextInt(pool.length)],
  ).join();
  return password + suffix;
}

String removeDisabledPasswordCharacters(
  String password, {
  required bool uppercase,
  required bool lowercase,
  required bool numbers,
  required bool symbols,
  required bool avoidSimilar,
}) {
  const similar = 'Il1O0o';
  return password.split('').where((character) {
    final code = character.codeUnitAt(0);
    if (!uppercase && code >= 65 && code <= 90) return false;
    if (!lowercase && code >= 97 && code <= 122) return false;
    if (!numbers && code >= 48 && code <= 57) return false;
    final isLetterOrNumber =
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57);
    if (!symbols && !isLetterOrNumber) return false;
    if (avoidSimilar && similar.contains(character)) return false;
    return true;
  }).join();
}

class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({this.showBottomNavigation = true, super.key});

  final bool showBottomNavigation;

  @override
  State<PasswordGeneratorPage> createState() => _PasswordGeneratorPageState();
}

class _PasswordGeneratorPageState extends State<PasswordGeneratorPage> {
  final Random _random = Random.secure();
  int _length = 16;
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _avoidSimilar = true;
  bool _customizeExpanded = false;
  late String _password;

  @override
  void initState() {
    super.initState();
    _customizeExpanded = isWindowsDesktop;
    _password = _createPassword();
  }

  String _createPassword() {
    const allUppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const allLowercase = 'abcdefghijklmnopqrstuvwxyz';
    const allNumbers = '0123456789';
    final uppercase = _avoidSimilar ? 'ABCDEFGHJKLMNPQRSTUVWXYZ' : allUppercase;
    final lowercase = _avoidSimilar
        ? 'abcdefghijkmnopqrstuvwxyz'
        : allLowercase;
    final numbers = _avoidSimilar ? '23456789' : allNumbers;
    const symbols = '!@#\$%&*';
    final pools = <String>[];

    if (_uppercase) pools.add(uppercase);
    if (_lowercase) pools.add(lowercase);
    if (_numbers) pools.add(numbers);
    if (_symbols) pools.add(symbols);
    if (pools.isEmpty) return '';

    final characters = pools.join();
    final result = List.generate(
      _length,
      (_) => characters[_random.nextInt(characters.length)],
    );

    for (
      var index = 0;
      index < pools.length && index < result.length;
      index++
    ) {
      final pool = pools[index];
      result[index] = pool[_random.nextInt(pool.length)];
    }

    result.shuffle(_random);
    return result.join();
  }

  void _regenerate() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_length == 0) _length = 8;
      _password = _createPassword();
    });
  }

  void _updateOption(bool value, void Function(bool) update) {
    HapticFeedback.selectionClick();
    setState(() {
      update(value);
      _password = removeDisabledPasswordCharacters(
        _password,
        uppercase: _uppercase,
        lowercase: _lowercase,
        numbers: _numbers,
        symbols: _symbols,
        avoidSimilar: _avoidSimilar,
      );
      _length = _password.length;
    });
  }

  void _updateLength(double value) {
    final nextLength = value.round();
    if (nextLength == _length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _length = nextLength;
      _password = resizeExistingPassword(
        _password,
        length: nextLength,
        uppercase: _uppercase,
        lowercase: _lowercase,
        numbers: _numbers,
        symbols: _symbols,
        avoidSimilar: _avoidSimilar,
      );
      _length = _password.length;
    });
  }

  Future<void> _copyPassword() async {
    if (_password.isEmpty) return;
    await SecureClipboard.copy(_password);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tx(
            'Senha copiada. ${SecureClipboard.clearAfterMessage}',
            'Password copied. ${SecureClipboard.clearAfterMessage}',
          ),
          style: const TextStyle(fontFamily: 'Kumbh Sans'),
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return DesktopPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopHeading(tr('Gerador de senhas')),
            DesktopColumns(
              breakpoint: 760,
              leadingFlex: 6,
              trailingFlex: 5,
              leading: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopSurface(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(
                            Icons.key_rounded,
                            size: 40,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _PasswordPreview(
                          password: _password,
                          onCopy: _copyPassword,
                        ),
                        const SizedBox(height: 24),
                        _GenerateButton(
                          onPressed:
                              _uppercase || _lowercase || _numbers || _symbols
                              ? _regenerate
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: _CustomizeCard(
                expanded: _customizeExpanded,
                onToggle: () =>
                    setState(() => _customizeExpanded = !_customizeExpanded),
                length: _length,
                uppercase: _uppercase,
                lowercase: _lowercase,
                numbers: _numbers,
                symbols: _symbols,
                avoidSimilar: _avoidSimilar,
                onLengthChanged: _updateLength,
                onUppercaseChanged: (v) =>
                    _updateOption(v, (n) => _uppercase = n),
                onLowercaseChanged: (v) =>
                    _updateOption(v, (n) => _lowercase = n),
                onNumbersChanged: (v) => _updateOption(v, (n) => _numbers = n),
                onSymbolsChanged: (v) => _updateOption(v, (n) => _symbols = n),
                onAvoidSimilarChanged: (v) =>
                    _updateOption(v, (n) => _avoidSimilar = n),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      bottomNavigationBar: widget.showBottomNavigation
          ? const SafeArea(top: false, child: _GeneratorBottomNavigation())
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _GeneratorHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _PasswordPreview(
                      password: _password,
                      onCopy: _copyPassword,
                    ),
                    const SizedBox(height: 18),
                    _GenerateButton(
                      onPressed:
                          _uppercase || _lowercase || _numbers || _symbols
                          ? _regenerate
                          : null,
                    ),
                    const SizedBox(height: 22),
                    _CustomizeCard(
                      expanded: _customizeExpanded,
                      onToggle: () => setState(
                        () => _customizeExpanded = !_customizeExpanded,
                      ),
                      length: _length,
                      uppercase: _uppercase,
                      lowercase: _lowercase,
                      numbers: _numbers,
                      symbols: _symbols,
                      avoidSimilar: _avoidSimilar,
                      onLengthChanged: _updateLength,
                      onUppercaseChanged: (value) =>
                          _updateOption(value, (next) => _uppercase = next),
                      onLowercaseChanged: (value) =>
                          _updateOption(value, (next) => _lowercase = next),
                      onNumbersChanged: (value) =>
                          _updateOption(value, (next) => _numbers = next),
                      onSymbolsChanged: (value) =>
                          _updateOption(value, (next) => _symbols = next),
                      onAvoidSimilarChanged: (value) =>
                          _updateOption(value, (next) => _avoidSimilar = next),
                    ),
                    const SizedBox(height: 14),
                    const _SecurityTipsCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratorHeader extends StatelessWidget {
  const _GeneratorHeader();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(tr('Gerador de senhas'), style: AppTypography.appPageTitle),
            const Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.info_outline,
                color: Color(0xFF8993A8),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordPreview extends StatefulWidget {
  const _PasswordPreview({required this.password, required this.onCopy});

  final String password;
  final VoidCallback onCopy;

  @override
  State<_PasswordPreview> createState() => _PasswordPreviewState();
}

class _PasswordPreviewState extends State<_PasswordPreview> {
  // A generated secret is sensitive too. It starts masked and can only be
  // revealed explicitly with the eye button.
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final password = widget.password;
    final onCopy = widget.onCopy;
    return Container(
      width: double.infinity,
      padding: isWindowsDesktop
          ? const EdgeInsets.symmetric(vertical: 18)
          : const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: isWindowsDesktop
            ? null
            : Border.all(color: AppPalette.resolve(const Color(0xFFE1E6F0))),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            tr('Sua senha segura'),
            style: isWindowsDesktop
                ? TextStyle(fontSize: 16, color: desktopMuted)
                : AppTypography.secondary,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: password.isEmpty
                    ? Text(
                        tr('Ative pelo menos um tipo de caractere para gerar.'),
                        style: AppTypography.secondary,
                      )
                    : AnimatedPasswordText(
                        password: password,
                        obscured: _obscured,
                      ),
              ),
              IconButton(
                tooltip: _obscured ? tr('Mostrar senha') : tr('Ocultar senha'),
                onPressed: password.isEmpty
                    ? null
                    : () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppPalette.resolve(const Color(0xFF73819D)),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onCopy,
                tooltip: tr('Copiar senha'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                icon: const Icon(
                  Icons.copy_outlined,
                  color: Color(0xFF73819D),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PasswordStrengthBar(password: password),
        ],
      ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final strength = _strengthFor(password);

    return SizedBox(
      height: 6,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: strength.toDouble()),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, level, child) {
          final color = _colorForLevel(level);
          final progress = (level / 5).clamp(0.0, 1.0);

          return LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    width: constraints.maxWidth * progress,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _colorForLevel(double level) {
    if (level <= 1) return AppColors.weak;
    if (level <= 3) {
      return Color.lerp(AppColors.weak, AppColors.warning, (level - 1) / 2)!;
    }
    return Color.lerp(AppColors.warning, AppColors.success, (level - 3) / 2)!;
  }

  int _strengthFor(String value) => passwordLevel(value);
}

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.sync, size: 23),
        label: Text(tr('Gerar outra senha')),
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.resolve(const Color(0xFF347BFF)),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: AppTypography.buttonLabel,
        ),
      ),
    );
  }
}

class _CustomizeCard extends StatelessWidget {
  const _CustomizeCard({
    required this.expanded,
    required this.onToggle,
    required this.length,
    required this.uppercase,
    required this.lowercase,
    required this.numbers,
    required this.symbols,
    required this.avoidSimilar,
    required this.onLengthChanged,
    required this.onUppercaseChanged,
    required this.onLowercaseChanged,
    required this.onNumbersChanged,
    required this.onSymbolsChanged,
    required this.onAvoidSimilarChanged,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool numbers;
  final bool symbols;
  final bool avoidSimilar;
  final ValueChanged<double> onLengthChanged;
  final ValueChanged<bool> onUppercaseChanged;
  final ValueChanged<bool> onLowercaseChanged;
  final ValueChanged<bool> onNumbersChanged;
  final ValueChanged<bool> onSymbolsChanged;
  final ValueChanged<bool> onAvoidSimilarChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      width: double.infinity,
      padding: isWindowsDesktop
          ? const EdgeInsets.all(24)
          : const EdgeInsets.fromLTRB(16, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border.all(color: AppPalette.resolve(const Color(0xFFE1E6F0))),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Personalizar senha'),
                      maxLines: isWindowsDesktop ? null : 1,
                      overflow: isWindowsDesktop
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: isWindowsDesktop
                          ? TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            )
                          : AppTypography.itemTitle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    color: AppColors.navy,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(tr('Tamanho'), style: AppTypography.secondary),
                            Text(
                              tx('$length caracteres', '$length characters'),
                              style: AppTypography.secondary.copyWith(
                                color: AppPalette.resolve(
                                  const Color(0xFF347BFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              activeTrackColor: AppPalette.resolve(
                                const Color(0xFF347BFF),
                              ),
                              inactiveTrackColor: AppPalette.resolve(
                                const Color(0xFFE8ECF3),
                              ),
                              thumbColor: AppPalette.resolve(
                                const Color(0xFF347BFF),
                              ),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10,
                              ),
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: length.toDouble(),
                              min: 0,
                              max: 32,
                              onChanged: onLengthChanged,
                            ),
                          ),
                        ),
                        _OptionRow(
                          marker: 'Aa',
                          label: tr('Letras maiúsculas (A–Z)'),
                          value: uppercase,
                          onChanged: onUppercaseChanged,
                        ),
                        _OptionRow(
                          marker: 'aa',
                          label: tr('Letras minúsculas (a–z)'),
                          value: lowercase,
                          onChanged: onLowercaseChanged,
                        ),
                        _OptionRow(
                          marker: '123',
                          label: tr('Números (0–9)'),
                          value: numbers,
                          onChanged: onNumbersChanged,
                        ),
                        _OptionRow(
                          marker: '#%',
                          label: tr('Símbolos (!@#\$%)'),
                          value: symbols,
                          onChanged: onSymbolsChanged,
                        ),
                        _OptionRow(
                          marker: '',
                          label: tr('Evitar caracteres semelhantes'),
                          value: avoidSimilar,
                          onChanged: onAvoidSimilarChanged,
                          showInfo: true,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.marker,
    required this.label,
    required this.value,
    required this.onChanged,
    this.showInfo = false,
  });

  final String marker;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: isWindowsDesktop ? 58 : 45),
      padding: isWindowsDesktop
          ? const EdgeInsets.symmetric(vertical: 6)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppPalette.resolve(const Color(0xFFF0F2F6)),
            width: .8,
          ),
        ),
      ),
      child: Row(
        children: [
          if (marker.isNotEmpty)
            Container(
              width: isWindowsDesktop ? null : 28,
              height: isWindowsDesktop ? null : 28,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: isWindowsDesktop
                  ? const EdgeInsets.all(4)
                  : EdgeInsets.zero,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.resolve(const Color(0xFFF3F5F9)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                marker,
                style: TextStyle(
                  fontFamily: 'Kumbh Sans',
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
          if (marker.isNotEmpty) const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: isWindowsDesktop ? null : 1,
                    overflow: isWindowsDesktop
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Kumbh Sans',
                      fontSize: isWindowsDesktop ? 15 : 14,
                      height: isWindowsDesktop ? 1.4 : 1,
                      fontWeight: FontWeight.w400,
                      color: isWindowsDesktop
                          ? desktopMuted
                          : AppColors.bodyText,
                    ),
                  ),
                ),
                if (showInfo) ...[
                  const SizedBox(width: 9),
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF8993A8),
                    size: 17,
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppPalette.resolve(Colors.white),
            activeTrackColor: AppPalette.resolve(const Color(0xFF347BFF)),
            inactiveThumbColor: AppPalette.resolve(Colors.white),
            inactiveTrackColor: AppPalette.resolve(const Color(0xFFD9DEE8)),
          ),
        ],
      ),
    );
  }
}

class _SecurityTipsCard extends StatelessWidget {
  const _SecurityTipsCard();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 14, 12, 13),
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border.all(color: AppPalette.resolve(const Color(0xFFE1E6F0))),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppPalette.resolve(const Color(0xFFEAF0FF)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF347BFF),
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Dicas de segurança'),
                  style: TextStyle(
                    fontFamily: 'Kumbh Sans',
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Use senhas únicas para cada conta e guarde-as com segurança.',
                  ),
                  style: AppTypography.secondary,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF8993A8), size: 23),
        ],
      ),
    );
  }
}

class _GeneratorBottomNavigation extends StatelessWidget {
  const _GeneratorBottomNavigation();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border(
          top: BorderSide(color: AppPalette.resolve(const Color(0xFFF1F3F8))),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _GeneratorNavigationItem(
              icon: Icons.home_outlined,
              label: tr('Início'),
              onTap: () => _goHome(context),
            ),
          ),
          Expanded(
            child: _GeneratorNavigationItem(
              icon: Icons.lock_outline,
              label: tr('Senhas'),
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const PasswordsPage()),
              ),
            ),
          ),
          Expanded(
            child: _GeneratorNavigationItem(
              icon: Icons.key_outlined,
              label: tr('Gerador'),
              selected: true,
            ),
          ),
          Expanded(
            child: _GeneratorNavigationItem(
              icon: Icons.settings_outlined,
              label: tr('Ajustes'),
            ),
          ),
        ],
      ),
    );
  }
}

void _goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class _GeneratorNavigationItem extends StatelessWidget {
  const _GeneratorNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = selected
        ? AppPalette.resolve(const Color(0xFF347BFF))
        : AppPalette.resolve(const Color(0xFF9AA3B5));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 12,
              height: 1,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
