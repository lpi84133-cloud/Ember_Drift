import 'package:flutter/material.dart';

import '../bridge/insight.dart';
import '../core/asset_paths.dart';
import '../ignition/alert_center.dart';
import '../ignition/stash_hold.dart';
import '../ignition/wire_watch.dart';
import '../setup/mission_facade.dart';
import 'molten_button.dart';
import 'stream_scene.dart';

/// Push opt-in promo shown once before the WebView. Two buttons:
///   • Accept — triggers the OS permission dialog
///   • Skip   — arms the 3-day cooldown
///
/// [FROM TZ] The two buttons must sit on the exact horizontal center
/// of the screen in BOTH orientations, even on devices with a punch-hole
/// camera on the long edge. We therefore intentionally SKIP `SafeArea`
/// on the button column — the background artwork already handles cutout
/// gutters, and adding an inset would shift the buttons off-center.
class AlertPrompt extends StatefulWidget {
  const AlertPrompt({
    super.key,
    required this.stash,
    required this.alertCenter,
    required this.wireWatch,
    required this.streamUrl,
  });

  final StashHold stash;
  final AlertCenter alertCenter;
  final WireWatch wireWatch;
  final String streamUrl;

  @override
  State<AlertPrompt> createState() => _AlertPromptState();
}

class _AlertPromptState extends State<AlertPrompt> {
  @override
  void initState() {
    super.initState();
    Insight.screen('push_invite');
  }

  Future<void> _accept() async {
    Insight.event('push_invite_accept');
    final bool granted = await widget.alertCenter.requestPermission();
    Insight.tag('notif_permission', granted ? 'granted' : 'denied');
    Insight.event(granted ? 'push_granted' : 'push_denied');
    if (!granted) {
      await widget.stash.writeInviteMuteUntil(_muteTarget());
    }
    if (mounted) _proceed();
  }

  Future<void> _skip() async {
    Insight.event('push_invite_skip');
    Insight.tag('notif_permission', 'skipped');
    await widget.stash.writeInviteMuteUntil(_muteTarget());
    if (mounted) _proceed();
  }

  int _muteTarget() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 +
      MissionFacade.inviteQuietWindow;

  void _proceed() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => StreamScene(
          streamUrl: widget.streamUrl,
          stash: widget.stash,
          alertCenter: widget.alertCenter,
          wireWatch: widget.wireWatch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final String bg = landscape
        ? AssetPaths.horizontalNotifications
        : AssetPaths.verticalNotifications;

    final Widget actions = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MoltenPill(
          label: 'Accept',
          compact: landscape,
          width: landscape ? size.width * 0.34 : size.width * 0.66,
          onPressed: _accept,
        ),
        SizedBox(height: landscape ? 10 : 14),
        MoltenPill(
          label: 'Skip',
          compact: landscape,
          tone: MoltenTone.ash,
          width: landscape ? size.width * 0.24 : size.width * 0.4,
          onPressed: _skip,
        ),
      ],
    );

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
                colors: <Color>[Colors.transparent, Color(0x88000000)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * (landscape ? 0.06 : 0.08),
            child: Center(child: actions),
          ),
        ],
      ),
    );
  }
}
