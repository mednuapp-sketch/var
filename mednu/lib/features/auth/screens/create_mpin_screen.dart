import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../widgets/mpin_pad.dart';

enum _CreateStep { enter, confirm }

class CreateMPINScreen extends ConsumerStatefulWidget {
  final String mode;
  const CreateMPINScreen({super.key, this.mode = 'setup'});

  @override
  ConsumerState<CreateMPINScreen> createState() => _CreateMPINScreenState();
}

class _CreateMPINScreenState extends ConsumerState<CreateMPINScreen>
    with TickerProviderStateMixin {
  static const _pinLength = 4;

  _CreateStep _step = _CreateStep.enter;
  String _firstPin = '';
  String _entered  = '';
  String? _errorMsg;
  bool _isLoading  = false;

  // Shake on mismatch
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Entry animation
  late AnimationController _entryCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  // Shield pulse
  late AnimationController _pulseCtrl;

  // Step slide transition
  late AnimationController _stepCtrl;
  late Animation<Offset> _stepSlide;
  late Animation<double> _stepFade;

  // Success glow
  late AnimationController _successCtrl;
  late Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _fadeIn  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _stepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _stepSlide = Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOutCubic));
    _stepFade = CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOut);

    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _successScale =
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _stepCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    if (key == '⌫') {
      if (_entered.isNotEmpty) {
        setState(() {
          _entered  = _entered.substring(0, _entered.length - 1);
          _errorMsg = null;
        });
      }
    } else {
      if (_entered.length < _pinLength) {
        setState(() { _entered += key; _errorMsg = null; });
        if (_entered.length == _pinLength) _advance();
      }
    }
  }

  void _advance() {
    if (_step == _CreateStep.enter) {
      _stepCtrl.forward(from: 0);
      setState(() {
        _firstPin = _entered;
        _entered  = '';
        _step     = _CreateStep.confirm;
      });
    } else {
      _confirmPin();
    }
  }

  Future<void> _confirmPin() async {
    if (_entered != _firstPin) {
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      _stepCtrl.forward(from: 0);
      setState(() {
        _entered   = '';
        _errorMsg  = 'PINs don\'t match — try again.';
        _step      = _CreateStep.enter;
        _firstPin  = '';
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).createMpin(_entered);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _successCtrl.forward();
      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg  = e.toString().replaceFirst('Exception: ', '');
        _entered   = '';
        _step      = _CreateStep.enter;
        _firstPin  = '';
      });
    }
  }

  String get _heading => _step == _CreateStep.enter
      ? (widget.mode == 'reset' ? 'New Security PIN' : 'Create Security PIN')
      : 'Confirm Your PIN';

  String get _subheading => _step == _CreateStep.enter
      ? 'Choose a 4-digit PIN to protect your account'
      : 'Enter the same PIN again to confirm';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0520),
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D0520),
                    Color(0xFF2A0A3E),
                    Color(0xFF5E1A4A),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // ── Ambient blobs ────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Stack(children: [
              Positioned(
                top: -size.width * 0.25,
                right: -size.width * 0.15,
                child: Container(
                  width: size.width * 0.75,
                  height: size.width * 0.75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF9C27B0).withValues(
                          alpha: 0.10 + _pulseCtrl.value * 0.06),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: size.height * 0.08,
                left: -size.width * 0.2,
                child: Container(
                  width: size.width * 0.6,
                  height: size.width * 0.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF7b2d6e).withValues(
                          alpha: 0.08 + _pulseCtrl.value * 0.05),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ]),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Column(
                  children: [
                    // ── Back button (confirm step only) ──────────────────────
                    SizedBox(
                      height: 56,
                      child: _step == _CreateStep.confirm
                          ? Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: () {
                                    _stepCtrl.reverse();
                                    setState(() {
                                      _step     = _CreateStep.enter;
                                      _entered  = '';
                                      _firstPin = '';
                                      _errorMsg = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.12)),
                                    ),
                                    child: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: Colors.white,
                                        size: 16),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    SizedBox(height: size.height * 0.03),

                    // ── Shield icon with glow ────────────────────────────────
                    ScaleTransition(
                      scale: _isLoading ? _successScale : const AlwaysStoppedAnimation(1.0),
                      child: AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, child) => Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow ring
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  const Color(0xFF9C27B0).withValues(
                                      alpha:
                                          0.18 + _pulseCtrl.value * 0.10),
                                  Colors.transparent,
                                ]),
                              ),
                            ),
                            // Inner circle
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF9C27B0),
                                    Color(0xFF7b2d6e),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9C27B0)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.03),

                    // ── Step pills ───────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepPill(
                          label: 'Create',
                          active: true,
                          done: _step == _CreateStep.confirm,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            width: 28,
                            height: 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(1),
                              color: _step == _CreateStep.confirm
                                  ? const Color(0xFFF2A8D8)
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        _StepPill(
                          label: 'Confirm',
                          active: _step == _CreateStep.confirm,
                          done: false,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Heading ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0.05, 0),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(_step),
                          children: [
                            Text(
                              _heading,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Poppins',
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _subheading,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.045),

                    // ── PIN dots ─────────────────────────────────────────────
                    AnimatedBuilder(
                      animation: _shakeAnim,
                      builder: (_, child) {
                        final dx = _shakeCtrl.isAnimating
                            ? 12 *
                                sin(_shakeAnim.value * pi * 4) *
                                (1 - _shakeAnim.value)
                            : 0.0;
                        return Transform.translate(
                            offset: Offset(dx, 0), child: child);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (i) {
                          final filled = i < _entered.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutBack,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            width: filled ? 22 : 18,
                            height: filled ? 22 : 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? const Color(0xFFF2A8D8)
                                  : Colors.transparent,
                              border: Border.all(
                                color: filled
                                    ? const Color(0xFFF2A8D8)
                                    : Colors.white.withValues(alpha: 0.30),
                                width: 2,
                              ),
                              boxShadow: filled
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFF2A8D8)
                                            .withValues(alpha: 0.55),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Error message ────────────────────────────────────────
                    AnimatedOpacity(
                      opacity: _errorMsg != null ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFFF6B6B)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Color(0xFFFF6B6B), size: 15),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _errorMsg ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontSize: 12,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // ── Keypad ───────────────────────────────────────────────
                    MpinPad(onKey: _onKey, isLoading: _isLoading),

                    const SizedBox(height: 16),

                    // ── Security badge ───────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.of(context).padding.bottom + 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                size: 12,
                                color:
                                    Colors.white.withValues(alpha: 0.45)),
                            const SizedBox(width: 6),
                            Text(
                              'End-to-end encrypted  ·  Never stored in plain text',
                              style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontFamily: 'Poppins',
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Full-screen loading overlay ──────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.2),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFF2A8D8), strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Step pill indicator ──────────────────────────────────────────────────────
class _StepPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _StepPill(
      {required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: active || done
            ? const Color(0xFF7b2d6e).withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: active || done
              ? const Color(0xFFF2A8D8).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            const Icon(Icons.check_rounded,
                size: 12, color: Color(0xFFF2A8D8)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: active || done
                  ? const Color(0xFFF2A8D8)
                  : Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
