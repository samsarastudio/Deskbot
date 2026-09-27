import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nova_theme.dart';

class NovaMascot extends StatefulWidget {
  const NovaMascot({
    super.key,
    this.mood = NovaMood.happy,
    this.size = 180,
    this.pulse = false,
  });

  final NovaMood mood;
  final double size;
  final bool pulse;

  @override
  State<NovaMascot> createState() => _NovaMascotState();
}

class _NovaMascotState extends State<NovaMascot> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _sway;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _sway = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _sway]),
      builder: (context, _) {
        final breath = Curves.easeInOut.transform(_breath.value);
        final sway = (_sway.value - 0.5) * (widget.pulse ? 0.06 : 0.03);
        final lift = math.sin(breath * math.pi) * (widget.pulse ? 8 : 4);
        final scale = 1 + (widget.pulse ? breath * 0.03 : breath * 0.015);
        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform.rotate(
            angle: sway,
            child: Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _SmileyPainter(widget.mood, glow: 0.4 + breath * 0.35),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SmileyPainter extends CustomPainter {
  _SmileyPainter(this.mood, {required this.glow});
  final NovaMood mood;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;

    Color skin = NovaColors.gold;
    if (mood == NovaMood.love) skin = NovaColors.heart;
    if (mood == NovaMood.worried || mood == NovaMood.sleepy) skin = const Color(0xFFB8D4E6);

    final glowPaint = Paint()
      ..color = NovaColors.accent.withValues(alpha: 0.22 * glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 22 + glow * 8);
    canvas.drawCircle(Offset(cx, cy), r + 14, glowPaint);

    final shade = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(skin, Colors.white, 0.22)!,
          skin,
          Color.lerp(skin, const Color(0xFF2A1C14), 0.18)!,
        ],
        stops: const [0.15, 0.55, 1],
        center: const Alignment(-0.35, -0.4),
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, shade);

    final ink = Paint()
      ..color = const Color(0xFF2A1C14)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.045;

    final eyeY = cy - r * 0.18;
    final eyeDx = r * 0.32;
    if (mood == NovaMood.love) {
      _heart(canvas, Offset(cx - eyeDx, eyeY), r * 0.18, const Color(0xFFFFE6F0));
      _heart(canvas, Offset(cx + eyeDx, eyeY), r * 0.18, const Color(0xFFFFE6F0));
    } else if (mood == NovaMood.sleepy) {
      canvas.drawLine(Offset(cx - eyeDx - 8, eyeY), Offset(cx - eyeDx + 8, eyeY), ink..style = PaintingStyle.stroke);
      canvas.drawLine(Offset(cx + eyeDx - 8, eyeY), Offset(cx + eyeDx + 8, eyeY), ink);
    } else {
      final er = mood == NovaMood.surprised ? r * 0.12 : r * 0.09;
      canvas.drawCircle(Offset(cx - eyeDx, eyeY - (mood == NovaMood.curious ? 4 : 0)), er, ink..style = PaintingStyle.fill);
      canvas.drawCircle(
        Offset(cx + eyeDx + (mood == NovaMood.curious ? 2 : 0), eyeY - (mood == NovaMood.curious ? 8 : 0)),
        mood == NovaMood.curious ? er * 1.15 : er,
        ink,
      );
    }

    final mouth = Path();
    final my = cy + r * 0.28;
    if (mood == NovaMood.worried) {
      mouth.moveTo(cx - r * 0.28, my + 6);
      mouth.quadraticBezierTo(cx, my - 10, cx + r * 0.28, my + 6);
    } else if (mood == NovaMood.thinking || mood == NovaMood.focused) {
      canvas.drawLine(Offset(cx - r * 0.22, my), Offset(cx + r * 0.22, my), ink..style = PaintingStyle.stroke);
      return;
    } else if (mood == NovaMood.surprised) {
      canvas.drawCircle(Offset(cx, my), r * 0.12, ink..style = PaintingStyle.fill);
      return;
    } else {
      mouth.moveTo(cx - r * 0.32, my - 4);
      mouth.quadraticBezierTo(cx, my + 18, cx + r * 0.32, my - 4);
    }
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF2A1C14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round,
    );
  }

  void _heart(Canvas canvas, Offset c, double s, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s, c.dy - s * 0.2, c.dx - s * 0.85, c.dy - s, c.dx, c.dy - s * 0.45)
      ..cubicTo(c.dx + s * 0.85, c.dy - s, c.dx + s, c.dy - s * 0.2, c.dx, c.dy + s * 0.35);
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SmileyPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.glow != glow;
}
