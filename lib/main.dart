import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_colors.dart';
import 'ignition/agent_mask.dart';
import 'ignition/alert_center.dart';
import 'ignition/boot_pipeline.dart';
import 'ignition/remote_valve.dart';
import 'ignition/stash_hold.dart';
import 'ignition/track_beacon.dart';
import 'ignition/wire_watch.dart';
import 'setup/mission_facade.dart';

// ============================================================
// Ember Drift — application entry point
// ============================================================
// Bootstrap order (do NOT change without reading the gray-flow guide):
//   1. WidgetsFlutterBinding — required before any plugin call.
//   2. Firebase + AppCheck   — wrapped in try/catch because we ship
//      without google-services.json until credentials land. Failure
//      here must never block startup: the shell falls back to the
//      native game path.
//   3. Orientation whitelist — all four are enabled so the loading
//      screen and WebView can rotate freely. BootPipeline locks the
//      game back to portrait when it hands off to HomeScreen.
//   4. Transparent status bar with light icons for the loading
//      artwork.
//   5. maskedClient.assemble() — builds the forged device UA used by
//      BOTH the config HTTP call and the WebView. Must run before any
//      ignition-layer bridge is constructed.
//   6. stash.hydrate() — loads SharedPreferences so the very first
//      frame of BootPipeline can read the persisted PathChoice
//      synchronously.
//   7. Bridges are constructed but never `wire()`d here — AlertCenter
//      and TrackBeacon run their side effects inside BootPipeline
//      once the UI is up.
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + AppCheck are optional until credentials land. Any failure
  // must be swallowed so the native game path still boots.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await maskedClient.assemble();

  final StashHold stash = StashHold();
  await stash.hydrate();

  final WireWatch wireWatch = WireWatch();
  final TrackBeacon beacon = TrackBeacon();
  final RemoteValve remoteValve = RemoteValve(stash);
  final AlertCenter alertCenter = AlertCenter(stash);

  runApp(EmberDriftShell(
    stash: stash,
    wireWatch: wireWatch,
    beacon: beacon,
    remoteValve: remoteValve,
    alertCenter: alertCenter,
  ));
}

class EmberDriftShell extends StatelessWidget {
  const EmberDriftShell({
    super.key,
    required this.stash,
    required this.wireWatch,
    required this.beacon,
    required this.remoteValve,
    required this.alertCenter,
  });

  final StashHold stash;
  final WireWatch wireWatch;
  final TrackBeacon beacon;
  final RemoteValve remoteValve;
  final AlertCenter alertCenter;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: MissionFacade.displayTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.obsidianDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.emberOrange,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: BootPipeline(
        stash: stash,
        wireWatch: wireWatch,
        beacon: beacon,
        remoteValve: remoteValve,
        alertCenter: alertCenter,
      ),
    );
  }
}
