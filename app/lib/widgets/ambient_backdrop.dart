import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/nova_theme.dart';

class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> with TickerProviderStateMixin {
  late final AnimationController _drift;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _drift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF121F2E),
            NovaColors.bg,
            Color(0xFF080D14),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_drift, _pulse]),
        builder: (context, _) {
          final t = _drift.value * math.pi * 2;
          final p = Curves.easeInOut.transform(_pulse.value);
          return Stack(
            children: [
              Positioned(
                top: -90 + math.sin(t) * 18,
                right: -50 + math.cos(t * 0.7) * 22,
                child: _Blob(
                  color: NovaColors.accent.withValues(alpha: 0.14 + p * 0.05),
                  size: 270 + p * 18,
                ),
              ),
              Positioned(
                bottom: 30 + math.cos(t * 0.9) * 16,
                left: -80 + math.sin(t * 0.6) * 20,
                child: _Blob(
                  color: NovaColors.gold.withValues(alpha: 0.09 + p * 0.03),
                  size: 300,
                ),
              ),
              Positioned(
                top: 200 + math.sin(t * 1.2) * 24,
                left: 30 + math.cos(t) * 14,
                child: _Blob(
                  color: NovaColors.heart.withValues(alpha: 0.05 + p * 0.02),
                  size: 150,
                ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color, blurRadius: 72, offset: Offset.zero)],
        ),
      ),
    );
  }
}

/// Soft entrance for screen content.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offset / 200),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.07),
                NovaColors.panel.withValues(alpha: 0.72),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class SoftStatusChip extends StatelessWidget {
  const SoftStatusChip({super.key, required this.label, this.good = true});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? NovaColors.accent : NovaColors.muted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: NovaColors.panelSolid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          if (good)
            BoxShadow(color: NovaColors.accent.withValues(alpha: 0.12), blurRadius: 16),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.25,
                ),
          ),
        ],
      ),
    );
  }
}

class NovaPrimaryButton extends StatefulWidget {
  const NovaPrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<NovaPrimaryButton> createState() => _NovaPrimaryButtonState();
}

class _NovaPrimaryButtonState extends State<NovaPrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF9AF4FF), NovaColors.accent, Color(0xFF3FC4DE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: NovaColors.accent.withValues(alpha: enabled ? 0.38 : 0.12),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: NovaColors.bg,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
