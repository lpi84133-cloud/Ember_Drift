/// The role a single grid cell plays within a level.
enum CellType {
  /// Solid volcanic rock, never walkable.
  obstacle,

  /// A cracked tile that can be stepped on.
  platform,
}

/// A single coordinate on the square board.
class GridPos {
  const GridPos(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is GridPos && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  List<GridPos> neighbors() => [
        GridPos(row - 1, col),
        GridPos(row + 1, col),
        GridPos(row, col - 1),
        GridPos(row, col + 1),
      ];

  @override
  String toString() => '($row,$col)';
}

/// Immutable description of a generated level layout. The [GameController]
/// consumes this to run the actual playthrough state machine.
class LevelData {
  LevelData({
    required this.level,
    required this.gridSize,
    required this.cellTypes,
    required this.start,
    required this.finish,
    required this.crystals,
  });

  final int level;
  final int gridSize;

  /// `cellTypes[row][col]` -> [CellType].
  final List<List<CellType>> cellTypes;
  final GridPos start;
  final GridPos finish;
  final Set<GridPos> crystals;

  bool inBounds(GridPos p) => p.row >= 0 && p.row < gridSize && p.col >= 0 && p.col < gridSize;

  CellType typeAt(GridPos p) => cellTypes[p.row][p.col];

  /// The minimal number of moves required to solve this level (length of the
  /// generator's guaranteed solution path). Used to compute "no mistakes"
  /// scoring bonuses.
  int idealMoves = 0;
}
