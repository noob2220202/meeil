import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../map/goat_painter.dart';

/// 혼자 움직이는 염소 한 마리(상세 시트·목록용)
class GoatAvatar extends StatefulWidget {
  const GoatAvatar({
    super.key,
    required this.look,
    this.size = 120,
    this.pose = GoatPose.idle,
    this.faceLeft = false,
  });

  final GoatLook look;
  final double size;
  final GoatPose pose;
  final bool faceLeft;

  @override
  State<GoatAvatar> createState() => _GoatAvatarState();
}

class _GoatAvatarState extends State<GoatAvatar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _AvatarPainter(_t, widget.look, widget.pose, widget.faceLeft)),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.t, this.look, this.pose, this.faceLeft) : super(repaint: t);

  final ValueNotifier<double> t;
  final GoatLook look;
  final GoatPose pose;
  final bool faceLeft;

  @override
  void paint(Canvas canvas, Size size) {
    GoatPainterKit.paint(
      canvas,
      at: Offset(size.width / 2, size.height * 0.9),
      size: size.height * 0.85,
      look: look,
      t: t.value + 1,
      pose: pose,
      faceLeft: faceLeft,
    );
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.look != look || old.pose != pose || old.faceLeft != faceLeft;
}
