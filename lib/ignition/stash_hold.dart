import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contract/path_choice.dart';

// ============================================================
// StashHold — persistence layer for the shell
// ============================================================
// Plain flags live in SharedPreferences; user-visible URLs and one-time
// push payloads live in encrypted secure storage. Every key is
// deliberately terse and unrelated to the intent it stores, so a prefs
// dump on-device does not reveal the flow.
// ============================================================

class StashHold {
  StashHold({FlutterSecureStorage? secure})
      : _sealed = secure ?? const FlutterSecureStorage();

  // Terse keys — no words like "webview" or "gray".
  static const String _kPath = 'ed_route_v1';
  static const String _kStreamUrl = 'ed_st_blob';
  static const String _kStreamTtl = 'ed_st_ttl';
  static const String _kInviteMuteUntil = 'ed_mute_until';
  static const String _kInviteGranted = 'ed_inv_ok';
  static const String _kInviteOsRefused = 'ed_inv_no';
  static const String _kPushUrlBlob = 'ed_pu_blob';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _sealed;

  Future<void> hydrate() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Path choice ──
  PathChoice fetchPath() => PathChoice.restore(_prefs.getString(_kPath));

  Future<void> commitPath(PathChoice choice) =>
      _prefs.setString(_kPath, choice.tag());

  // ── Cached stream destination (secure) ──
  Future<String?> readStreamUrl() => _sealed.read(key: _kStreamUrl);

  Future<void> writeStreamUrl(String url) =>
      _sealed.write(key: _kStreamUrl, value: url);

  // ── Stream expiry ──
  int? readStreamTtl() => _prefs.getInt(_kStreamTtl);

  Future<void> writeStreamTtl(int unixSeconds) =>
      _prefs.setInt(_kStreamTtl, unixSeconds);

  bool isStreamExpired() {
    final int? ttl = readStreamTtl();
    if (ttl == null) return true;
    return _clock() >= ttl;
  }

  // ── Invite state (notification permission) ──
  bool isInviteAccepted() => _prefs.getBool(_kInviteGranted) ?? false;

  Future<void> recordInviteAccepted(bool value) =>
      _prefs.setBool(_kInviteGranted, value);

  /// True once the OS dialog was denied — the OS refuses to show the
  /// prompt again, so re-offering the invite is pointless.
  bool isInviteOsRefused() => _prefs.getBool(_kInviteOsRefused) ?? false;

  Future<void> recordInviteOsRefused() =>
      _prefs.setBool(_kInviteOsRefused, true);

  int? readInviteMuteUntil() => _prefs.getInt(_kInviteMuteUntil);

  Future<void> writeInviteMuteUntil(int unixSeconds) =>
      _prefs.setInt(_kInviteMuteUntil, unixSeconds);

  bool shouldSurfaceInvite() {
    if (isInviteAccepted()) return false;
    if (isInviteOsRefused()) return false;
    final int? until = readInviteMuteUntil();
    if (until == null) return true;
    return _clock() >= until;
  }

  // ── One-off push destination ──
  Future<void> parkPushUrl(String? url) async {
    if (url == null) {
      await _sealed.delete(key: _kPushUrlBlob);
    } else {
      await _sealed.write(key: _kPushUrlBlob, value: url);
    }
  }

  Future<String?> claimPushUrl() async {
    final String? url = await _sealed.read(key: _kPushUrlBlob);
    if (url != null) await _sealed.delete(key: _kPushUrlBlob);
    return url;
  }

  static int _clock() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
