import '../settings/app_strings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DesktopUpdateInfo {
  const DesktopUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
  });

  final String version;
  final Uri downloadUrl;
  final String sha256;
}

class DesktopUpdateChecker {
  const DesktopUpdateChecker({
    this.repository = 'matheusventurasantos/passdrive',
    this.currentVersion = '1.0.2',
  });

  static const _apiBase = 'https://api.github.com/repos';
  final String repository;
  final String currentVersion;

  bool get shouldSkip {
    return Platform.executableArguments.contains('--passdrive-skip-update');
  }

  Future<DesktopUpdateInfo?> findUpdate() async {
    if (!Platform.isWindows || shouldSkip) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse('$_apiBase/$repository/releases/latest'),
      );
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'PassDrive-Updater');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(response).join();
      final release = jsonDecode(body);
      if (release is! Map<String, dynamic>) return null;

      final version = _normalizeVersion(release['tag_name']?.toString() ?? '');
      if (version == null || !_isNewer(version, currentVersion)) return null;

      final assets = release['assets'];
      if (assets is! List) return null;
      for (final item in assets) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name']?.toString() ?? '';
        final url = Uri.tryParse(
          item['browser_download_url']?.toString() ?? '',
        );
        final digest = _normalizeDigest(item['digest']?.toString());
        if (url == null || digest == null || !_isInstaller(name, url)) continue;
        return DesktopUpdateInfo(
          version: version,
          downloadUrl: url,
          sha256: digest,
        );
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> downloadAndInstall(
    DesktopUpdateInfo update, {
    required void Function(double progress) onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final filename = 'PassDrive-update-${update.version}.exe';
    final installer = File(path.join(directory.path, filename));
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(update.downloadUrl);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream')
        ..set(HttpHeaders.userAgentHeader, 'PassDrive-Updater');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw DesktopUpdateException(
          tr('Não foi possível baixar a atualização.'),
        );
      }

      final total = response.contentLength;
      var received = 0;
      final output = installer.openWrite();
      final digestBytes = <int>[];
      try {
        await for (final chunk in response) {
          received += chunk.length;
          digestBytes.addAll(chunk);
          output.add(chunk);
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await output.close();
      }

      final digest = await Sha256().hash(Uint8List.fromList(digestBytes));
      final actual = _hex(digest.bytes);
      if (actual != update.sha256) {
        try {
          await installer.delete();
        } on Object {
          // A failed cleanup must not hide the validation failure.
        }
        throw DesktopUpdateException(
          tr('A atualização não passou na validação de segurança.'),
        );
      }

      await Process.start(installer.path, const [
        '/SILENT',
        '/CLOSEAPPLICATIONS',
      ], runInShell: false);
      return installer.path;
    } finally {
      client.close(force: true);
    }
  }

  bool _isInstaller(String name, Uri url) {
    final lower = name.toLowerCase();
    return url.scheme == 'https' &&
        lower.endsWith('.exe') &&
        lower.contains('passdrive') &&
        lower.contains('setup');
  }

  String? _normalizeDigest(String? value) {
    if (value == null) return null;
    final digest = value.toLowerCase().replaceFirst('sha256:', '').trim();
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ? digest : null;
  }

  String? _normalizeVersion(String value) {
    final version = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    return RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(version)
        ? version
        : null;
  }

  bool _isNewer(String candidate, String installed) {
    final left = _parts(candidate);
    final right = _parts(installed);
    for (var i = 0; i < 3; i++) {
      if (left[i] != right[i]) return left[i] > right[i];
    }
    return false;
  }

  List<int> _parts(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) return const [0, 0, 0];
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class DesktopUpdateException implements Exception {
  const DesktopUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
