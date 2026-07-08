import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

// ============================================================
// WireWatch — connectivity probe + change stream
// ============================================================
// Adapter state alone is not enough: captive portals, throttled cell
// data and VPN-tunnel warmup all show as "wifi" but fail HTTP. So we
// pair the adapter check with a fast DNS probe with a generous 7-second
// timeout. Real outages throw immediately, so the extra headroom costs
// nothing.
// ============================================================

/// Every ConnectivityResult that counts as a real interface. VPN and
/// bluetooth are included so tunnel-only setups don't flash offline
/// (see pitfalls guide §3).
const Set<ConnectivityResult> _liveInterfaces = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

class WireWatch {
  WireWatch({Connectivity? impl}) : _impl = impl ?? Connectivity();

  final Connectivity _impl;

  Future<bool> canReach() async {
    final List<ConnectivityResult> states = await _impl.checkConnectivity();
    if (!states.any(_liveInterfaces.contains)) return false;

    try {
      final List<InternetAddress> probe = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 7));
      return probe.isNotEmpty && probe.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Stream<List<ConnectivityResult>> get pulses => _impl.onConnectivityChanged;
}
