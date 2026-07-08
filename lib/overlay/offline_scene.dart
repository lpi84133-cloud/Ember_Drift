import 'package:flutter/material.dart';

import '../core/asset_paths.dart';
import 'molten_button.dart';

/// Full-screen "no wifi" scene. Uses the project's dedicated no-wifi
/// artwork (orientation-aware) with a Retry pill overlaid at the bottom.
/// Retry rebuilds whatever screen the caller supplies.
///
/// [FROM TZ] The Retry button must sit exactly on the horizontal center
/// in BOTH orientations, unaffected by safe zones / camera cutouts. That
/// is why we intentionally do NOT wrap the button in a `SafeArea` — the
/// artwork already accounts for cutout gutters and any inset shift
/// would drag the button off-center.
class OfflineScene extends StatefulWidget {
  const OfflineScene({super.key, required this.rebuilder});

  final WidgetBuilder rebuilder;

  @override
  State<OfflineScene> createState() => _OfflineSceneState();
}

class _OfflineSceneState extends State<OfflineScene> {
  bool _spinning = false;

  Future<void> _retry() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.rebuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? AssetPaths.horizontalNoWifi
        : AssetPaths.verticalNoWifi;

    return Scaffold(
      backgroundColor: const Color(0xFF140A08),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            bg,
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Color(0x99000000)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * (landscape ? 0.08 : 0.09),
            child: Center(
              child: _spinning
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFFF7A18)),
                      ),
                    )
                  : MoltenPill(
                      label: 'Retry',
                      width: landscape ? size.width * 0.32 : size.width * 0.6,
                      onPressed: _retry,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
