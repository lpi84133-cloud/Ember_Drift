import 'dart:math';

import 'level_model.dart';

/// Procedurally builds solvable [LevelData] boards.
///
/// The generator always guarantees at least one valid solution by first
/// carving a random self-avoiding "safe route" (via backtracking DFS) from
/// the start tile to the finish tile. Every crystal is placed on that route,
/// so following it in order always clears the level. Extra platform tiles
/// ("decoys") are then grafted onto the route as single-tile dead ends: they
/// are perfectly safe to look at, but stepping onto one destroys the only
/// tile connecting back, trapping the player - which is exactly the
/// "plan or perish" risk described by the game design.
class LevelGenerator {
  static LevelData generate(int level, {int? seed}) {
    final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch ^ level);
    final gridSize = _gridSizeForLevel(level);
    final totalCells = gridSize * gridSize;

    final targetLenFraction = 0.55 + rng.nextDouble() * 0.2; // 55%-75%
    final targetLen = max(gridSize + 3, (totalCells * targetLenFraction).round());

    final path = _dfsLongestPath(gridSize, rng, targetLen, maxSteps: 60000);

    final cellTypes = List.generate(
      gridSize,
      (_) => List.generate(gridSize, (_) => CellType.obstacle),
    );
    for (final p in path) {
      cellTypes[p.row][p.col] = CellType.platform;
    }

    // Grant decoy dead-ends: non-path cells touching exactly one path cell.
    final decoyBudget = min(3 + level ~/ 2, max(0, totalCells - path.length));
    final pathSet = path.toSet();
    final candidates = <GridPos>[];
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
        final p = GridPos(r, c);
        if (pathSet.contains(p)) continue;
        final touchingPath = p
            .neighbors()
            .where((n) => n.row >= 0 && n.row < gridSize && n.col >= 0 && n.col < gridSize)
            .where(pathSet.contains)
            .length;
        if (touchingPath == 1) candidates.add(p);
      }
    }
    candidates.shuffle(rng);
    for (final decoy in candidates.take(decoyBudget)) {
      cellTypes[decoy.row][decoy.col] = CellType.platform;
    }

    final start = path.first;
    final finish = path.last;

    final crystalCount = min(2 + (level - 1) ~/ 3, min(path.length - 2, 10)).clamp(1, path.length - 2);
    final interior = path.sublist(1, path.length - 1)..shuffle(rng);
    final crystals = interior.take(crystalCount).toSet();

    final data = LevelData(
      level: level,
      gridSize: gridSize,
      cellTypes: cellTypes,
      start: start,
      finish: finish,
      crystals: crystals,
    );
    data.idealMoves = path.length - 1;
    return data;
  }

  static int _gridSizeForLevel(int level) {
    final step = ((level - 1) ~/ 4).clamp(0, 4);
    return 4 + step; // caps at 8x8
  }

  /// Randomized backtracking DFS that tries to reach [targetLen] visited
  /// cells, remembering the longest path found in case the target proves
  /// unreachable within [maxSteps] iterations.
  static List<GridPos> _dfsLongestPath(
    int size,
    Random rng,
    int targetLen, {
    required int maxSteps,
  }) {
    final start = GridPos(rng.nextInt(size), rng.nextInt(size));
    final path = <GridPos>[start];
    final visited = <GridPos>{start};
    final candidateStack = <List<GridPos>>[_shuffledNeighbors(start, size, rng)];
    var best = List<GridPos>.from(path);

    var steps = 0;
    while (path.isNotEmpty && path.length < targetLen && steps < maxSteps) {
      steps++;
      final candidates = candidateStack.last;
      while (candidates.isNotEmpty && visited.contains(candidates.last)) {
        candidates.removeLast();
      }
      if (candidates.isEmpty) {
        candidateStack.removeLast();
        final removed = path.removeLast();
        visited.remove(removed);
        continue;
      }
      final next = candidates.removeLast();
      path.add(next);
      visited.add(next);
      if (path.length > best.length) best = List<GridPos>.from(path);
      candidateStack.add(_shuffledNeighbors(next, size, rng));
    }
    return path.length > best.length ? path : best;
  }

  static List<GridPos> _shuffledNeighbors(GridPos p, int size, Random rng) {
    final list = p
        .neighbors()
        .where((n) => n.row >= 0 && n.row < size && n.col >= 0 && n.col < size)
        .toList();
    list.shuffle(rng);
    return list;
  }
}
