import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Full-bleed backdrop used across menu screens: a background asset image
/// covered by a dark gradient so foreground UI stays legible.
class VolcanicBackground extends StatelessWidget {
  const VolcanicBackground({
    super.key,
    required this.assetPath,
    required this.child,
  });

  final String assetPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.obsidianDark),
        Image.asset(assetPath, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.obsidianDark.withValues(alpha: 0.55),
                AppColors.obsidianDark.withValues(alpha: 0.75),
                AppColors.obsidianDark.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
