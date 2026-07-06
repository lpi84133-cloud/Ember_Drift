import 'package:flutter/foundation.dart';

import 'level_generator.dart';
import 'level_model.dart';

enum GameStatus { playing, won, lost }

/// Runtime state machine for a single level playthrough.
///
/// Rules implemented straight from the design doc:
/// - the coal only moves to an orthogonally adjacent, unbroken platform;
/// - the tile it leaves instantly cracks and can never be used again;
/// - all crystals must be collected before the finish tile counts as a win;
/// - if there is no legal move left the level is failed and must restart.
class GameController extends ChangeNotifier {
  GameController({required int level, int? seed}) {
    _level = level;
    _seed = seed;
    _startLevel();
  }

  late int _level;
  int? _seed;
  late LevelData _data;
  late Set<GridPos> _broken;
  late GridPos _current;
  late Set<GridPos> _remainingCrystals;

  int moves = 0;
  GameStatus status = GameStatus.playing;
  final Stopwatch _stopwatch = Stopwatch();

  int get level => _level;
  LevelData get data => _data;
  GridPos get current => _current;
  Set<GridPos> get broken => _broken;
  int get crystalsTotal => _data.crystals.length;
  int get crystalsCollected => crystalsTotal - _remainingCrystals.length;
  int get idealMoves => _data.idealMoves;
  Duration get elapsed => _stopwatch.elapsed;

  void _startLevel() {
    _data = LevelGenerator.generate(_level, seed: _seed);
    _broken = <GridPos>{};
    _current = _data.start;
    _remainingCrystals = Set<GridPos>.from(_data.crystals);
    moves = 0;
    status = GameStatus.playing;
    _stopwatch
      ..reset()
      ..start();
  }

  void restart() {
    _startLevel();
    notifyListeners();
  }

  /// Regenerates the very same level (used when the player wants a fresh
  /// layout without bumping the level counter after failing).
  void retrySameLevel() => restart();

  bool isBroken(GridPos p) => _broken.contains(p);

  bool get isFinishTile => _current == _data.finish;

  List<GridPos> get validMoves {
    if (status != GameStatus.playing) return const [];
    return _current
        .neighbors()
        .where((n) => _data.inBounds(n))
        .where((n) => _data.typeAt(n) == CellType.platform)
        .where((n) => !_broken.contains(n))
        .toList();
  }

  bool canMoveTo(GridPos p) => validMoves.any((v) => v == p);

  void moveTo(GridPos target) {
    if (status != GameStatus.playing) return;
    if (!canMoveTo(target)) return;

    _broken.add(_current);
    _current = target;
    moves++;

    if (_remainingCrystals.contains(target)) {
      _remainingCrystals.remove(target);
    }

    if (_current == _data.finish && _remainingCrystals.isEmpty) {
      status = GameStatus.won;
      _stopwatch.stop();
    } else if (validMoves.isEmpty) {
      status = GameStatus.lost;
      _stopwatch.stop();
    }

    notifyListeners();
  }

  /// Score awarded for a completed level. Rewards efficiency, speed,
  /// full crystal collection and mistake-free routing.
  int computeScore() {
    const base = 100;
    final crystalBonus = crystalsCollected * 15;
    final extraMoves = moves > idealMoves ? moves - idealMoves : 0;
    final efficiencyBonus = extraMoves == 0 ? idealMoves * 4 : _max(0, (idealMoves - extraMoves) * 2);
    final noMistakesBonus = wasFlawless ? 60 : 0;
    final seconds = elapsed.inMilliseconds / 1000.0;
    final speedBonus = seconds <= 10
        ? 50
        : seconds <= 20
            ? 25
            : 0;
    return base + crystalBonus + efficiencyBonus + noMistakesBonus + speedBonus;
  }

  bool get wasFlawless => moves == idealMoves;

  int _max(int a, int b) => a > b ? a : b;
}
