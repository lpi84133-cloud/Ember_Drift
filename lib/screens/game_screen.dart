import 'package:flutter/material.dart';

import '../bridge/insight.dart';
import '../core/app_colors.dart';
import '../core/asset_paths.dart';
import '../core/daily_tasks.dart';
import '../core/storage_service.dart';
import '../game/game_controller.dart';
import '../widgets/grid_board.dart';
import '../widgets/stat_chip.dart';
import '../widgets/volcanic_background.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level});

  final int level;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController _controller;
  StorageService? _storage;
  bool _rewardApplied = false;
  int? _lastScore;

  @override
  void initState() {
    super.initState();
    _controller = GameController(level: widget.level);
    _controller.addListener(_onControllerChanged);
    _initStorage();
    Insight.screen('game');
    Insight.tag('level', '${widget.level}');
  }

  Future<void> _initStorage() async {
    final storage = await StorageService.getInstance();
    if (!mounted) return;
    setState(() => _storage = storage);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (_controller.status == GameStatus.won && !_rewardApplied) {
      _rewardApplied = true;
      _lastScore = _controller.computeScore();
      _applyWinRewards(_lastScore!);
      Insight.event('game_win');
      Insight.tag('level_cleared', '${widget.level}');
    } else if (_controller.status == GameStatus.lost) {
      Insight.event('game_lose');
      Insight.tag('level_lost', '${widget.level}');
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyWinRewards(int score) async {
    final storage = _storage ?? await StorageService.getInstance();
    await storage.addCrystals(_controller.crystalsCollected);
    await storage.addMoves(_controller.moves);
    await storage.incrementLevelsCompleted();
    await storage.maybeUpdateBestScore(_controller.level, score);
    if (storage.unlockedLevel <= _controller.level) {
      await storage.setUnlockedLevel(_controller.level + 1);
    }
    await storage.setPerfectStreak(_controller.wasFlawless ? storage.perfectStreak + 1 : 0);

    final manager = DailyTasksManager(storage);
    final tasks = manager.loadOrGenerate();
    for (final task in tasks) {
      switch (task.kind) {
        case DailyTaskKind.completeLevels:
          await manager.incrementProgress(task, 1);
        case DailyTaskKind.collectCrystals:
          await manager.incrementProgress(task, _controller.crystalsCollected);
        case DailyTaskKind.flawlessLevel:
          if (_controller.wasFlawless) await manager.incrementProgress(task, 1);
        case DailyTaskKind.makeMoves:
          await manager.incrementProgress(task, _controller.moves);
      }
    }
    if (mounted) setState(() {});
  }

  void _restartSameLevel() {
    setState(() {
      _rewardApplied = false;
      _lastScore = null;
      _controller.retrySameLevel();
    });
  }

  void _goToNextLevel() {
    final nextLevel = _controller.level + 1;
    setState(() {
      _rewardApplied = false;
      _lastScore = null;
      _controller.removeListener(_onControllerChanged);
      _controller = GameController(level: nextLevel)..addListener(_onControllerChanged);
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = _storage;
    return PopScope(
      canPop: true,
      child: Scaffold(
        body: VolcanicBackground(
          assetPath: AssetPaths.bg2,
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(storage),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: GridBoard(controller: _controller),
                      ),
                      if (_controller.status == GameStatus.won)
                        _ResultOverlay(
                          success: true,
                          controller: _controller,
                          score: _lastScore ?? _controller.computeScore(),
                          onPrimary: _goToNextLevel,
                          onSecondary: () => Navigator.of(context).pop(),
                        ),
                      if (_controller.status == GameStatus.lost)
                        _ResultOverlay(
                          success: false,
                          controller: _controller,
                          score: 0,
                          onPrimary: _restartSameLevel,
                          onSecondary: () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(StorageService? storage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                StatChip(icon: Icons.flag_rounded, label: 'Lvl ${_controller.level}'),
                StatChip(icon: Icons.touch_app, label: '${_controller.moves} moves'),
                StatChip(
                  icon: Icons.diamond,
                  label: '${_controller.crystalsCollected}/${_controller.crystalsTotal}',
                  iconColor: AppColors.emberYellow,
                ),
                if (storage != null)
                  StatChip(
                    icon: Icons.emoji_events,
                    label: 'Best ${storage.bestScoreForLevel(_controller.level)}',
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _restartSameLevel,
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.success,
    required this.controller,
    required this.score,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool success;
  final GameController controller;
  final int score;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.obsidianDark.withValues(alpha: 0.82),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.obsidianPanel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: success ? AppColors.emberYellow : AppColors.ashGrey,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.emoji_events : Icons.whatshot,
                color: success ? AppColors.emberYellow : AppColors.lavaRed,
                size: 44,
              ),
              const SizedBox(height: 10),
              Text(
                success ? 'Level Complete!' : 'The Ember Fizzled Out',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                success
                    ? 'All crystals collected. The path ahead cools and opens.'
                    : "You're trapped with nowhere left to go. Plan a better route!",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (success) ...[
                const SizedBox(height: 16),
                _statRow('Moves', '${controller.moves} (ideal ${controller.idealMoves})'),
                _statRow('Crystals', '${controller.crystalsCollected}/${controller.crystalsTotal}'),
                _statRow('Score', '$score'),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.obsidianPanelLight),
                    ),
                    child: const Text('Menu'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: success ? AppColors.emberOrange : AppColors.lavaRed,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(success ? 'Next Level' : 'Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
