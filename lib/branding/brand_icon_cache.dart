import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Keeps only public brand icon bytes, keyed by a normalized host name.
///
/// No credential, account identifier or complete URL is ever written here.
abstract final class BrandIconCache {
  static const int _maxIconBytes = 512 * 1024;
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  static final Map<String, Uint8List> _memory = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  static final Set<String> _failedThisSession = <String>{};

  static Future<Uint8List?> load(String host) {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost == null) return Future<Uint8List?>.value(null);

    final memoryValue = _memory[normalizedHost];
    if (memoryValue != null) return Future<Uint8List?>.value(memoryValue);
    if (_isFlutterTest ||
        Platform.environment['FLUTTER_TEST'] == 'true' ||
        _failedThisSession.contains(normalizedHost)) {
      return Future<Uint8List?>.value(null);
    }

    return _inFlight.putIfAbsent(normalizedHost, () async {
      try {
        final cached = await _read(normalizedHost);
        if (cached != null) {
          _memory[normalizedHost] = cached;
          return cached;
        }

        final downloaded = await _download(normalizedHost);
        if (downloaded == null) {
          _failedThisSession.add(normalizedHost);
          return null;
        }

        _memory[normalizedHost] = downloaded;
        await _write(normalizedHost, downloaded);
        return downloaded;
      } catch (_) {
        _failedThisSession.add(normalizedHost);
        return null;
      } finally {
        _inFlight.remove(normalizedHost);
      }
    });
  }

  static String? _normalizeHost(String value) {
    final host = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.isEmpty || host.length > 253) return null;
    if (host.contains('..') || host.contains('/') || host.contains('\\')) {
      return null;
    }
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(host)) {
      return null;
    }
    return host;
  }

  static Future<Directory?> _cacheDirectory() async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(path.join(root.path, 'brand-icons'));
      await directory.create(recursive: true);
      return directory;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _read(String host) async {
    final directory = await _cacheDirectory();
    if (directory == null) return null;

    final file = File(
      path.join(directory.path, 'icon-v1-${Uri.encodeComponent(host)}.bin'),
    );
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > _maxIconBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String host, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxIconBytes) return;
    final directory = await _cacheDirectory();
    if (directory == null) return;

    final file = File(
      path.join(directory.path, 'icon-v1-${Uri.encodeComponent(host)}.bin'),
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // A cache failure must never make a credential screen fail.
    }
  }

  static Future<Uint8List?> _download(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 8);

    try {
      final request = await client
          .getUrl(
            Uri.https('www.google.com', '/s2/favicons', <String, String>{
              'domain': host,
              'sz': '64',
            }),
          )
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;

      final contentType = response.headers.contentType?.mimeType;
      if (contentType != null && !contentType.startsWith('image/')) return null;

      final builder = BytesBuilder(copy: true);
      var totalBytes = 0;
      await for (final chunk in response) {
        totalBytes += chunk.length;
        if (totalBytes > _maxIconBytes) return null;
        builder.add(chunk);
      }

      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void clearMemoryForTests() {
    _memory.clear();
    _inFlight.clear();
    _failedThisSession.clear();
  }
}
