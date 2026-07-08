import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/mission_facade.dart';
import '../setup/veiled_bytes.dart';
import 'agent_mask.dart';

// ============================================================
// TrackBeacon — AppsFlyer attribution capture
// ============================================================
// Collects three sources of attribution and folds them into the config
// request body: onInstallConversionData, onDeepLinking, and
// onAppOpenAttribution. The install data can lie ("Organic") on the
// first callback for genuinely paid installs, so we wait a short pause
// and re-query the GCD endpoint for the real answer.
//
// When no AppsFlyer key is packed yet (fresh template), the beacon
// short-circuits: awaiters immediately resolve with empty data so the
// shell never stalls before falling back to the game.
// ============================================================

class TrackBeacon {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _resumePayload;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();

  bool _armed = false;

  /// Boots the SDK and wires callbacks. Idempotent.
  Future<void> arm() async {
    if (_armed) return;
    _armed = true;

    final String key = MissionFacade.appsflyerKey;
    if (key.isEmpty) {
      _resolveInstall(<String, dynamic>{});
      _resolveDeepLink();
      return;
    }

    final AppsFlyerOptions opts = AppsFlyerOptions(
      afDevKey: key,
      appId: MissionFacade.appleStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 8,
    );

    final AppsflyerSdk sdk = AppsflyerSdk(opts);
    _sdk = sdk;

    sdk.onInstallConversionData((dynamic raw) async {
      final Map<String, dynamic> payload = _flatten(raw);
      final String? status = payload['af_status']?.toString();
      if (status == 'Organic') {
        await Future<void>.delayed(
          Duration(seconds: MissionFacade.organicRetryPause),
        );
        final Map<String, dynamic>? refreshed = await _gcdRefresh();
        _installPayload = refreshed ?? payload;
      } else {
        _installPayload = payload;
      }
      _resolveInstall(_installPayload ?? <String, dynamic>{});
    });

    sdk.onAppOpenAttribution((dynamic raw) {
      _resumePayload = _flatten(raw);
    });

    sdk.onDeepLinking((DeepLinkResult res) {
      final Map<String, dynamic>? evt = res.deepLink?.clickEvent;
      if (evt != null) {
        _deepLinkPayload = Map<String, dynamic>.from(evt);
      }
      _resolveDeepLink();
    });

    try {
      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _resolveInstall(<String, dynamic>{});
      _resolveDeepLink();
    }
  }

  /// Waits up to [seconds] for install conversion data.
  Future<Map<String, dynamic>> attendInstall({int seconds = 30}) {
    return _installReady.future.timeout(
      Duration(seconds: seconds),
      onTimeout: () => <String, dynamic>{},
    );
  }

  /// Waits up to 5s for the deep-link callback.
  Future<void> attendDeepLink() {
    return _deepLinkReady.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  Future<String?> deviceUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Composes the merged body posted to the config gate.
  Future<Map<String, dynamic>> composeGateBody({
    required String localeTag,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};

    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));
    _resumePayload?.forEach((String k, dynamic v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await deviceUid() ?? '';
    body['bundle_id'] = MissionFacade.packageId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = MissionFacade.marketId;
    body['locale'] = localeTag;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final String project = MissionFacade.firebaseProject;
    if (project.isNotEmpty) {
      body['firebase_project_id'] = project;
    }

    if (kDebugMode) {
      debugPrint('[TrackBeacon] gate body: ${jsonEncode(body)}');
    }
    return body;
  }

  Future<Map<String, dynamic>?> _gcdRefresh() async {
    try {
      final String? uid = await deviceUid();
      if (uid == null) return null;
      final String appId = Platform.isIOS
          ? MissionFacade.appleStoreId
          : MissionFacade.packageId;
      final String url = peekGcdUrl(appId, uid);
      if (url.isEmpty) return null;

      final dynamic res = await maskedClient
          .get(
            Uri.parse(url),
            headers: <String, String>{
              'authorization': 'Bearer ${MissionFacade.appsflyerKey}',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _resolveInstall(Map<String, dynamic> data) {
    if (!_installReady.isCompleted) _installReady.complete(data);
  }

  void _resolveDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }

  static Map<String, dynamic> _flatten(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final dynamic inner = raw['payload'] ?? raw['data'] ?? raw;
    if (inner is Map) {
      return inner.map<String, dynamic>((dynamic k, dynamic v) =>
          MapEntry<String, dynamic>(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}
