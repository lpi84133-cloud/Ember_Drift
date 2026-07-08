import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../setup/veiled_bytes.dart';

// ============================================================
// AgentMask — HTTP client wearing a real device User-Agent
// ============================================================
// Outbound requests (config POST, GCD retry, push image fetch) and the
// WebView share the same forged User-Agent. Two fingerprint principles:
//   • Never leak "Dart", "Flutter", "wv" or the app package name in the
//     UA — those substrings are trivial pattern matches.
//   • Reflect the real device model / build id (via device_info_plus)
//     so two installs on different phones produce different UAs.
// ============================================================

class MaskedClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  String _agent = 'Mozilla/5.0';

  /// The active user agent string.
  String get agent => _agent;

  /// Reads device info and builds the UA. Call once during boot before
  /// any network call, so the very first request already has a real UA.
  Future<void> assemble() async {
    final String chrome = _fallback(peekChromeMajor(), '149.0.7636.72');
    final String webkit = _fallback(peekWebkitMajor(), '537.36');

    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo a = await info.androidInfo;
        final String buildTag =
            a.display.isNotEmpty ? a.display : a.id;
        _agent = 'Mozilla/5.0 (Linux; Android ${a.version.release}; '
            '${a.brand} ${a.model} Build/$buildTag) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit';
      } else if (Platform.isIOS) {
        final IosDeviceInfo i = await info.iosInfo;
        final String iosVer = i.systemVersion.replaceAll('.', '_');
        _agent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $iosVer like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      _agent = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/$webkit';
    }
  }

  static String _fallback(String value, String backup) =>
      value.isNotEmpty ? value : backup;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _agent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Process-wide shared client. Every ignition-layer bridge and the
/// WebView setUserAgent call must go through this instance.
final MaskedClient maskedClient = MaskedClient();
