import 'package:flutter/material.dart';

/// A soft, breathing pulse ring behind a solid dot — used for "online" /
/// "live" indicators across the Ambulance module so it reads as active
/// rather than a static badge.
class StatusPulse extends StatefulWidget {
  final Color color;
  final double size;

  const StatusPulse({super.key, required this.color, this.size = 12});

  @override
  State<StatusPulse> createState() => _StatusPulseState();
}

class _StatusPulseState extends State<StatusPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3,
      height: widget.size * 3,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t).clamp(0, 1),
                child: Container(
                  width: widget.size + (widget.size * 2 * t),
                  height: widget.size + (widget.size * 2 * t),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
