import 'package:flutter/material.dart';

/// A soft, breathing pulse ring behind a solid dot — used for the on-duty
/// indicator on the Dashboard. Kept local to this module (a small,
/// self-contained widget) rather than importing the Ambulance module's
/// equivalent, since feature modules shouldn't depend on each other.
class DutyPulse extends StatefulWidget {
  final Color color;
  final double size;

  const DutyPulse({super.key, required this.color, this.size = 12});

  @override
  State<DutyPulse> createState() => _DutyPulseState();
}

class _DutyPulseState extends State<DutyPulse> with SingleTickerProviderStateMixin {
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
