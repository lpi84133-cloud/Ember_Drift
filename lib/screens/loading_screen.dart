import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/asset_paths.dart';
import '../core/storage_service.dart';

/// First screen shown on cold start.
///
/// Behaviour (tuned to match the exact spec requested):
/// - Works in both portrait AND landscape (the only screen allowed to
///   rotate freely); the rest of the app is locked to portrait once this
///   screen hands off.
/// - The bar starts completely empty and fills up in visible stages, always
///   perfectly in sync with the percentage readout underneath it.
/// - The bar only ever reaches 100% at the exact instant right before the
///   app hands off to the main menu - never stalls midway (fixes the old
///   "stuck at 97%" bug by always explicitly driving the last stage to a
///   real, awaited 100).
/// - The whole sequence is capped well under the 10 second requirement.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _stepController;
  double _progress = 0;
  int _dotCount = 1;
  Timer? _dotTimer;
  bool _handedOff = false;

  // Staged checkpoints - the bar visibly climbs in bursts ("поэтапно")
  // instead of one smooth linear sweep, but never overshoots and never
  // reaches 100 until the explicit final step.
  static const List<int> _stageTargets = [10, 24, 39, 55, 70, 83, 93, 98];

  @override
  void initState() {
    super.initState();
    // Allow free rotation only while this screen is on screen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _stepController = AnimationController(vsync: this);
    _dotTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

    _run();
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _stepController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final rng = Random();
    final initFuture = _performRealInit();

    for (final target in _stageTargets) {
      await _animateTo(target.toDouble(), Duration(milliseconds: 190 + rng.nextInt(160)));
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: 55 + rng.nextInt(110)));
      if (!mounted) return;
    }

    // Give real initialization work a bounded chance to finish, but never
    // let it hold the splash hostage past the 10s ceiling.
    await initFuture.timeout(const Duration(seconds: 4), onTimeout: () {});
    if (!mounted) return;

    // The bar is only ever allowed to hit 100 right here, immediately
    // before handing off to the game.
    await _animateTo(100, const Duration(milliseconds: 260));
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted || _handedOff) return;

    _handedOff = true;
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    widget.onComplete();
  }

  Future<void> _animateTo(double target, Duration duration) async {
    final start = _progress;
    late final Animation<double> anim;
    anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _stepController, curve: Curves.easeOutCubic),
    );
    void listener() {
      if (!mounted) return;
      setState(() => _progress = anim.value);
    }

    anim.addListener(listener);
    _stepController
      ..duration = duration
      ..value = 0;
    await _stepController.forward();
    anim.removeListener(listener);
    if (mounted) setState(() => _progress = target);
  }

  Future<void> _performRealInit() async {
    await StorageService.getInstance();
    if (!mounted) return;
    await _precacheGameArt();
  }

  Future<void> _precacheGameArt() async {
    const paths = [
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
    for (final path in paths) {
      if (!mounted) return;
      try {
        await precacheImage(AssetImage(path), context);
      } catch (_) {
        // Non-fatal: missing/undecoded art must never block app launch.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidianDark,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          final bgAsset = isLandscape
              ? AssetPaths.horizontalLoadingScreen
              : AssetPaths.verticalLoadingScreen;

          final loadingGroup = _LoadingGroup(
            progress: _progress,
            dotCount: _dotCount,
            landscape: isLandscape,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: AppColors.obsidianDark),
              Image.asset(bgAsset, fit: BoxFit.cover),
              SafeArea(
                child: Align(
                  alignment: Alignment(0, isLandscape ? 0.68 : 0.72),
                  child: loadingGroup,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingGroup extends StatelessWidget {
  const _LoadingGroup({
    required this.progress,
    required this.dotCount,
    required this.landscape,
  });

  final double progress;
  final int dotCount;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth * (landscape ? 0.62 : 0.86);
    final barHeight = landscape ? 24.0 : 26.0;
    final pct = progress.clamp(0, 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Loading${'.' * dotCount}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: landscape ? 28 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
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
            border: Border.all(color: AppColors.obsidianPanelLight, width: 1.5),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (progress / 100).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.emberOrange.withValues(alpha: 0.7),
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
            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
          ),
        ),
      ],
    );
  }
}
