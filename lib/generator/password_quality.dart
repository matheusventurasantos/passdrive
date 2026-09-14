/// Local estimate; does not check breach databases or know personal dates.
int passwordLevel(String password) {
  if (password.isEmpty) return 0;
  final lower = password.toLowerCase();
  final normalized = lower
      .replaceAll('@', 'a')
      .replaceAll('0', 'o')
      .replaceAll('3', 'e')
      .replaceAll('1', 'i')
      .replaceAll(r'$', 's');
  final types = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp(r'[^a-zA-Z0-9\s]'),
  ].where((r) => r.hasMatch(password)).length;
  int level = password.length < 8
      ? 1
      : password.length < 12
      ? 2
      : password.length < 16
      ? 3
      : password.length < 20
      ? 4
      : 5;
  if (types >= 3 && password.length >= 12) level++;
  if (types == 1) level = level.clamp(1, 3);
  final unique = password.runes.toSet().length;
  if (unique <= 3 ||
      unique / password.runes.length < .35 ||
      RegExp(r'(.)\1{3,}|(.{2,4})\2{2,}').hasMatch(lower)) {
    return 1;
  }
  const common = [
    'password',
    'senha',
    'qwerty',
    'admin',
    'welcome',
    'letmein',
    'iloveyou',
    'abc123',
    'passw',
    'football',
    '123456',
  ];
  if (common.any((word) => lower.contains(word) || normalized.contains(word))) {
    level = level.clamp(1, 2);
  }
  for (final sequence in [
    '0123456789',
    '9876543210',
    'abcdefghijklmnopqrstuvwxyz',
    'zyxwvutsrqponmlkjihgfedcba',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
  ]) {
    for (var i = 0; i <= sequence.length - 4; i++) {
      if (lower.contains(sequence.substring(i, i + 4))) {
        level = level.clamp(1, 2);
      }
    }
  }
  // Common DDMMYYYY, YYYYMMDD and separated date formats.
  final dates = RegExp(
    r'(?:0[1-9]|[12][0-9]|3[01])[-/.]?(?:0[1-9]|1[0-2])[-/.]?(?:(?:19|20)[0-9]{2}|[0-9]{2})|(?:19|20)[0-9]{2}[-/.]?(?:0[1-9]|1[0-2])[-/.]?(?:0[1-9]|[12][0-9]|3[01])',
  );
  if (dates.hasMatch(password)) level = level.clamp(1, 2);
  final digits = password.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8 &&
      digits.length <= 15 &&
      digits.length / password.length >= .6) {
    level = level.clamp(1, 2);
  }
  if (RegExp(r'(.)\1{2}').hasMatch(password)) level = level.clamp(1, 3);
  return level.clamp(1, 5);
}
