import 'package:flutter/material.dart';

class MpinPad extends StatelessWidget {
  final void Function(String key) onKey;
  final bool isLoading;

  const MpinPad({super.key, required this.onKey, required this.isLoading});

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: _rows.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row
                .map((key) => _PadKey(
                      label: key,
                      onTap: key.isEmpty ? null : () => onKey(key),
                      isLoading: isLoading,
                    ))
                .toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _PadKey extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PadKey({required this.label, this.onTap, required this.isLoading});

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) {
      return const SizedBox(width: 76, height: 76);
    }

    final isBack = widget.label == '⌫';

    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => _pressCtrl.forward(),
      onTapUp: widget.isLoading
          ? null
          : (_) {
              _pressCtrl.reverse();
              widget.onTap?.call();
            },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 76,
          height: 76,
          margin: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isBack
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.06),
                    ],
                  ),
            color: isBack ? Colors.white.withValues(alpha: 0.06) : null,
            border: Border.all(
              color: Colors.white.withValues(alpha: isBack ? 0.08 : 0.16),
              width: 1.2,
            ),
            boxShadow: isBack
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF7b2d6e).withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: isBack
              ? Icon(
                  Icons.backspace_rounded,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 22,
                )
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
