import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/asset_paths.dart';
import '../game/game_controller.dart';
import '../game/level_model.dart';

/// Renders the volcanic tile grid and lets the player tap an adjacent,
/// unbroken platform to move the ember there.
class GridBoard extends StatelessWidget {
  const GridBoard({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.data;
    final size = data.gridSize;
    final validMoves = controller.validMoves.toSet();

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = constraints.maxWidth / size;
          return Stack(
            children: [
              for (var r = 0; r < size; r++)
                for (var c = 0; c < size; c++)
                  Positioned(
                    left: c * cell,
                    top: r * cell,
                    width: cell,
                    height: cell,
                    child: _TileCell(
                      pos: GridPos(r, c),
                      controller: controller,
                      isReachable: validMoves.contains(GridPos(r, c)),
                      padding: cell * 0.045,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _TileCell extends StatelessWidget {
  const _TileCell({
    required this.pos,
    required this.controller,
    required this.isReachable,
    required this.padding,
  });

  final GridPos pos;
  final GameController controller;
  final bool isReachable;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final data = controller.data;
    final type = data.typeAt(pos);
    final isBroken = controller.isBroken(pos);
    final isCurrent = controller.current == pos;
    final isFinish = data.finish == pos;
    final hasCrystal = data.crystals.contains(pos) && !isCurrent && !isBroken;

    Widget base;
    if (type == CellType.obstacle) {
      base = Image.asset(AssetPaths.obsidianStoneBlock, fit: BoxFit.cover);
    } else if (isBroken) {
      base = Image.asset(AssetPaths.inactivePlatform, fit: BoxFit.cover);
    } else {
      base = Image.asset(AssetPaths.activePlatform, fit: BoxFit.cover);
    }

    return Padding(
      padding: EdgeInsets.all(padding),
      child: GestureDetector(
        onTap: isReachable ? () => controller.moveTo(pos) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: isReachable
                ? [
                    BoxShadow(
                      color: AppColors.emberOrange.withValues(alpha: 0.75),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
            border: isFinish
                ? Border.all(color: AppColors.emberYellow, width: 2.5)
                : isReachable
                    ? Border.all(color: AppColors.emberOrange, width: 2)
                    : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                base,
                if (isFinish)
                  Container(
                    color: AppColors.emberYellow.withValues(alpha: 0.16),
                    child: const Center(
                      child: Icon(Icons.flag_rounded, color: AppColors.emberYellow, size: 18),
                    ),
                  ),
                if (hasCrystal)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(AssetPaths.fireCrystal, fit: BoxFit.contain),
                  ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: _PulsingEmber(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _PulsingEmber extends StatefulWidget {
  @override
  State<_PulsingEmber> createState() => _PulsingEmberState();
}

class _PulsingEmberState extends State<_PulsingEmber> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.9 + _controller.value * 0.15;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.emberOrange.withValues(alpha: 0.8 * _controller.value + 0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Image.asset(AssetPaths.moltenEmber, fit: BoxFit.contain),
    );
  }
}
