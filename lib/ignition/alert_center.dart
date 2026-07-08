import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'agent_mask.dart';
import 'stash_hold.dart';

// ============================================================
// AlertCenter — Firebase Messaging + local notification display
// ============================================================
// Cold-start push taps (app was killed) stash the URL so the boot
// pipeline can pick it up on the next launch. Warm taps
// (background / foreground) deliver the URL live via [onOpenUrl]
// without persisting it — per contract, push URLs are one-time and
// must not survive across sessions.
//
// The channel id MUST match the AndroidManifest meta-data value
// `com.google.firebase.messaging.default_notification_channel_id`.
// The small icon references a monochrome flame drawable in res/drawable/.
// ============================================================

// Channel id matches AndroidManifest meta-data value exactly.
const String kEmberChannelId = 'emberdrift_ember_channel';
const String kEmberChannelName = 'Ember Alerts';
const String _kSmallFlame = '@drawable/ic_notification';

@pragma('vm:entry-point')
Future<void> _quietBackgroundReceiver(RemoteMessage message) async {
  // OS displays background pushes on its own; the tap event is picked up
  // on resume (warm) or boot (cold), so nothing to do here.
}

class AlertCenter {
  AlertCenter(this._stash);

  final StashHold _stash;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fm;
  String? _token;
  bool _wired = false;

  /// Delivered when a live push tap should be loaded in the WebView.
  void Function(String url)? onOpenUrl;

  /// Fired when FCM rotates the token → re-post the config request.
  void Function(String token)? onTokenRoll;

  String? get token => _token;

  Future<void> wire() async {
    if (_wired) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _fm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_quietBackgroundReceiver);

      await _setupLocal();

      _token = await _fm!.getToken();
      _fm!.onTokenRefresh.listen((String rolled) {
        _token = rolled;
        onTokenRoll?.call(rolled);
      });

      FirebaseMessaging.onMessage.listen(_onLive);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final RemoteMessage? cold = await _fm!.getInitialMessage();
      if (cold != null) _onColdTap(cold);

      _wired = true;
    } catch (_) {
      // Firebase not configured yet — push stays dormant.
    }
  }

  Future<void> _setupLocal() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings(_kSmallFlame);
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(payload) as Map<String, dynamic>;
          final String? url = data['url'] as String?;
          if (url != null && url.isNotEmpty) onOpenUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          kEmberChannelId,
          kEmberChannelName,
          description: 'Ember Drift updates and offers',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Requests the Android 13+ notification permission and records the
  /// OS-denied flag so the invite screen never loops.
  Future<bool> requestPermission() async {
    if (_fm == null) return false;
    final NotificationSettings s = await _fm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final AuthorizationStatus status = s.authorizationStatus;
    final bool granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    await _stash.recordInviteAccepted(granted);
    if (status == AuthorizationStatus.denied) {
      await _stash.recordInviteOsRefused();
    }
    return granted;
  }

  Future<void> _onLive(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    if (n == null || !Platform.isAndroid) return;

    AndroidNotificationDetails? details;
    final String? imageUrl = n.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final Uint8List? bytes = await _fetchImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          kEmberChannelId,
          kEmberChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _kSmallFlame,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      kEmberChannelId,
      kEmberChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: _kSmallFlame,
    );

    await _plugin.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(android: details),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  void _onColdTap(RemoteMessage message) {
    final String? url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _stash.parkPushUrl(url);
    }
  }

  void _onWarmTap(RemoteMessage message) {
    final String? url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onOpenUrl?.call(url);
    }
  }

  Future<Uint8List?> _fetchImage(String url) async {
    try {
      final dynamic res = await maskedClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes as Uint8List;
    } catch (_) {}
    return null;
  }
}
