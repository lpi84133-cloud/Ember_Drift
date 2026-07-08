import 'package:flutter/material.dart';

// ============================================================
// MoltenButton — shared button styling for the gray shell screens
// ============================================================
// Deliberately different look-and-feel from the native game's ember
// gradient primary button so the two flows read as distinct products.
// Uses a smoked-obsidian pill with an inner amber glow and a firm
// press-scale reaction. Skip variant is a bordered ghost pill (NOT a
// pale text-link — see pitfalls guide §12).
// ============================================================

class MoltenPill extends StatefulWidget {
  const MoltenPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.width,
    this.tone = MoltenTone.blaze,
  });

  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final double? width;
  final MoltenTone tone;

  @override
  State<MoltenPill> createState() => _MoltenPillState();
}

enum MoltenTone { blaze, ash }

class _MoltenPillState extends State<MoltenPill> {
  double _pressScale = 1.0;

  bool get _isAsh => widget.tone == MoltenTone.ash;

  @override
  Widget build(BuildContext context) {
    final List<Color> gradient = _isAsh
        ? const <Color>[Color(0xFF3A2822), Color(0xFF1E100C)]
        : const <Color>[Color(0xFFFF7A18), Color(0xFFB33200)];
    final Color glow = _isAsh
        ? const Color(0xFF6E3A21).withValues(alpha: 0.35)
        : const Color(0xFFFF7A18).withValues(alpha: 0.55);
    final Color rim = _isAsh
        ? const Color(0xFFB56A3E).withValues(alpha: 0.6)
        : const Color(0xFFFFDBA1).withValues(alpha: 0.8);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressScale = 0.94),
      onTapCancel: () => setState(() => _pressScale = 1.0),
      onTapUp: (_) {
        setState(() => _pressScale = 1.0);
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressScale,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.width,
          padding: EdgeInsets.symmetric(
            horizontal: 26,
            vertical: widget.compact ? 12 : 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: rim, width: 1.6),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: glow,
                blurRadius: 14,
                spreadRadius: 0.6,
                offset: const Offset(0, 3),
              ),
              const BoxShadow(
                color: Colors.black45,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.compact ? 15 : 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1.0,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black87, offset: Offset(0, 2), blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
