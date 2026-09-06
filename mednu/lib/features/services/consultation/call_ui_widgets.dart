import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared building blocks for the patient-side and guest-side call screens
/// (video_call_screen.dart / guest_video_call_screen.dart) — kept in one
/// place so both stay visually and behaviorally identical.

/// Scale + haptic feedback wrapper used on every tappable control in-call.
class AnimatedTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool heavy;
  const AnimatedTap(
      {super.key, required this.child, required this.onTap, this.heavy = false});

  @override
  State<AnimatedTap> createState() => _AnimatedTapState();
}

class _AnimatedTapState extends State<AnimatedTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 75),
      reverseDuration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.heavy ? 0.80 : 0.86)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    widget.heavy
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.lightImpact();
    _ctrl.forward();
  }

  void _up(TapUpDetails _) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _cancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _cancel,
        child: ScaleTransition(scale: _scale, child: widget.child),
      );
}

/// Small circular icon button used in the call screen's top bar.
class TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const TopButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

/// Labeled circular control used in the bottom control bar (mute, camera,
/// speaker, flip) and in the pre-join lobby's mic/camera toggles.
class CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const CallButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedTap(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}
