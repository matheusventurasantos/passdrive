import '../settings/app_strings.dart';

class MasterPasswordValidationException implements Exception {
  const MasterPasswordValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MasterPasswordConfirmationException implements Exception {
  const MasterPasswordConfirmationException();

  @override
  String toString() => tr('A confirmação da nova senha não confere.');
}

abstract final class MasterPasswordPolicy {
  static const minimumLength = 12;
  static const _common = <String>{
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    'abcdefgh',
    'abcdefghi',
    'abcd1234',
    'qwertyui',
    'qwerty123',
    'password',
    'password1',
    'password123',
    'passw0rd',
    'passw0rd!',
    'qwerty',
    'senha123',
    'senha1234',
    'senha12345',
    'abc123',
    'iloveyou',
    'welcome',
    'welcome1',
    'admin',
    'admin123',
    'letmein',
    'letmein123',
    'football',
    'dragon',
    'monkey',
    '1q2w3e4r',
    'zaq12wsx',
    'asdfgh',
    'qazwsx',
    '11111111',
    '00000000',
    '987654321',
    '20200101',
  };

  static String? errorFor(String password) {
    final normalized = password.trim().toLowerCase();
    if (_common.contains(normalized)) {
      return tr('Escolha uma senha menos comum e previsível.');
    }
    if (password.length < minimumLength) {
      return tx(
        'A senha mestra precisa ter pelo menos $minimumLength caracteres.',
        'The master password must have at least $minimumLength characters.',
      );
    }

    if (normalized.runes.toSet().length == 1) {
      return tr('Evite repetir o mesmo caractere.');
    }

    if (_isOrdered(normalized) || _hasRepeatedBlock(normalized)) {
      return tr('Evite sequências previsíveis de caracteres.');
    }

    final numericRuns = RegExp(r'\d+').allMatches(normalized);
    if (numericRuns.any((match) => match.group(0)!.length >= 8) ||
        RegExp(r'(?:19|20)\d{6}').hasMatch(normalized)) {
      return tr('Evite datas, telefones e sequências numéricas previsíveis.');
    }

    return null;
  }

  static void validate(String password) {
    final message = errorFor(password);
    if (message != null) {
      throw MasterPasswordValidationException(message);
    }
  }

  static void validateChange({
    required String newPassword,
    required String confirmation,
  }) {
    if (newPassword != confirmation) {
      throw const MasterPasswordConfirmationException();
    }
    validate(newPassword);
  }

  static bool _isOrdered(String value) {
    if (value.length < 6) return false;
    final codes = value.codeUnits;
    final step = codes[1] - codes[0];
    if (step != 1 && step != -1) return false;
    for (var index = 2; index < codes.length; index++) {
      if (codes[index] - codes[index - 1] != step) return false;
    }
    return true;
  }

  static bool _hasRepeatedBlock(String value) {
    if (value.length < 6) return false;
    for (var size = 1; size <= 4; size++) {
      if (value.length % size != 0) continue;
      final block = value.substring(0, size);
      if (List.filled(value.length ~/ size, block).join() == value) {
        return true;
      }
    }
    return false;
  }
}
