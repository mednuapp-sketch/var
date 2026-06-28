import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../widgets/mpin_pad.dart';

class MPINScreen extends ConsumerStatefulWidget {
  // 'login'  = called after OTP for existing user
  // 'unlock' = called from splash when session is still active
  final String mode;
  final String phone;

  const MPINScreen({
    super.key,
    this.mode = 'unlock',
    this.phone = '',
  });

  @override
  ConsumerState<MPINScreen> createState() => _MPINScreenState();
}

class _MPINScreenState extends ConsumerState<MPINScreen>
    with SingleTickerProviderStateMixin {
  static const _pinLength = 4;

  String _entered = '';
  bool _isLoading = false;
  bool _isLocked = false;
  bool _awaitingAuth = false;
  String? _errorMsg;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );

    // Check if already locked
    final locked = ref.read(authProvider).lockedUntil;
    if (locked != null && DateTime.now().isBefore(locked)) {
      _isLocked = true;
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    if (_isLoading || _isLocked) return;
    HapticFeedback.lightImpact();

    if (key == '⌫') {
      if (_entered.isNotEmpty) {
        setState(() {
          _entered = _entered.substring(0, _entered.length - 1);
          _errorMsg = null;
        });
      }
    } else {
      if (_entered.length < _pinLength) {
        setState(() { _entered += key; _errorMsg = null; });
        if (_entered.length == _pinLength) {
          _verify();
        }
      }
    }
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final phone = widget.phone;

    // ── Case 1: Firebase Auth already active ─────────────────────────────────
    if (ref.read(authProvider).user != null) {
      final ok = await ref.read(authProvider.notifier).verifyMpin(_entered);
      if (!mounted) return;
      if (ok) { HapticFeedback.mediumImpact(); context.go(AppRoutes.home); }
      else     { _onWrongMpin(authState: ref.read(authProvider)); }
      return;
    }

    // ── Case 2: MPIN-first flow — no Firebase session yet ────────────────────

    // Same-device fast path: verify locally (instant, no network)
    final sameDevice =
        await ref.read(authProvider.notifier).hasLocalMpin(phone);
    if (sameDevice) {
      final localOk =
          await ref.read(authProvider.notifier).verifyMpinLocal(_entered, phone);
      if (!mounted) return;
      if (!localOk) {
        _onWrongMpin(localMessage: 'Incorrect MPIN.');
        return;
      }
      // MPIN correct — get Firebase auth from auto-OTP
      setState(() { _awaitingAuth = true; _isLoading = false; });
      final signedIn = await _waitForFirebaseAuth();
      if (!mounted) return;
      setState(() { _awaitingAuth = false; });
      if (signedIn) {
        HapticFeedback.mediumImpact();
        context.go(AppRoutes.home);
      } else {
        context.push(AppRoutes.otp,
            extra: {'phone': phone, 'mode': 'completeLogin'});
      }
      return;
    }

    // Different device — wait for Firebase auto-OTP first, then verify server
    setState(() { _awaitingAuth = true; _isLoading = false; });
    final signedIn = await _waitForFirebaseAuth();
    if (!mounted) return;
    setState(() { _awaitingAuth = false; });

    if (!signedIn) {
      context.push(AppRoutes.otp,
          extra: {'phone': phone, 'mode': 'completeLogin'});
      return;
    }

    // Firebase auth obtained — server-side MPIN verify (with lockout tracking)
    setState(() => _isLoading = true);
    final ok = await ref.read(authProvider.notifier).verifyMpin(_entered);
    if (!mounted) return;
    if (ok) { HapticFeedback.mediumImpact(); context.go(AppRoutes.home); }
    else     { _onWrongMpin(authState: ref.read(authProvider)); }
  }

  Future<bool> _waitForFirebaseAuth() async {
    bool signedIn =
        await ref.read(authProvider.notifier).signInSilentlyIfPossible();
    if (signedIn) return true;

    final completer = Completer<bool>();
    StreamSubscription<User?>? sub;
    try {
      sub = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null && !completer.isCompleted) completer.complete(true);
      });
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted || completer.isCompleted) return;
        final ok =
            await ref.read(authProvider.notifier).signInSilentlyIfPossible();
        if (ok && !completer.isCompleted) completer.complete(true);
      });
      Future.delayed(const Duration(seconds: 8),
          () { if (!completer.isCompleted) completer.complete(false); });
      return await completer.future;
    } finally {
      await sub?.cancel();
    }
  }

  void _onWrongMpin({AuthState? authState, String? localMessage}) {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    setState(() {
      _entered = '';
      _isLoading = false;
      _awaitingAuth = false;
      _errorMsg = localMessage ?? authState?.error;
      _isLocked = authState?.lockedUntil != null &&
          DateTime.now().isBefore(authState!.lockedUntil!);
    });
  }

  Future<void> _forgotMpin() async {
    final phone = widget.phone.isNotEmpty
        ? widget.phone
        : ref.read(authProvider).user?.phoneNumber ?? '';
    if (phone.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).sendOtp(phone);
      if (!mounted) return;
      context.push(AppRoutes.otp, extra: {
        'phone': phone,
        'isExistingUser': true,
        'mode': 'resetMpin',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.toString().replaceFirst('Exception: ', ''),
          style: const TextStyle(color: Colors.white, fontFamily: 'Poppins'),
        ),
        backgroundColor: const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final authState = ref.watch(authProvider);
    final userName = authState.user?.displayName ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0520),
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0A2E), Color(0xFF5E1A4A)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Top bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      if (widget.mode == 'login')
                        GestureDetector(
                          onTap: () => context.canPop() ? context.pop() : context.go(AppRoutes.login),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          final router = GoRouter.of(context);
                          await ref.read(authProvider.notifier).signOut();
                          if (!mounted) return;
                          router.go(AppRoutes.login);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Sign out',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontFamily: 'Poppins',
                              )),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: size.height * 0.06),

                // ── Greeting ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Text('Enter MPIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                            letterSpacing: -0.3,
                          )),
                      const SizedBox(height: 6),
                      Text(
                        userName.isNotEmpty
                            ? 'Welcome back, ${userName.split(' ').first}'
                            : 'Quick and secure access',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 14,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: size.height * 0.05),

                // ── PIN dots with shake animation ──────────────────────────
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) {
                    final offset = _shakeCtrl.isAnimating
                        ? 10 *
                            (0.5 -
                                (_shakeAnim.value - _shakeAnim.value.floor())
                                    .abs())
                        : 0.0;
                    return Transform.translate(
                        offset: Offset(offset, 0), child: child);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pinLength, (i) {
                      final filled = i < _entered.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? const Color(0xFFF2A8D8)
                              : Colors.transparent,
                          border: Border.all(
                            color: filled
                                ? const Color(0xFFF2A8D8)
                                : Colors.white.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Status / error message ────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _awaitingAuth
                      ? Row(
                          key: const ValueKey('awaiting'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 13, height: 13,
                              child: CircularProgressIndicator(
                                color: const Color(0xFFF2A8D8)
                                    .withValues(alpha: 0.8),
                                strokeWidth: 1.8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Completing sign-in…',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ],
                        )
                      : AnimatedOpacity(
                          key: const ValueKey('error'),
                          opacity: _errorMsg != null ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _errorMsg ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFF6B6B),
                                fontSize: 13,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                        ),
                ),

                const Spacer(),

                // ── Number pad ────────────────────────────────────────────
                MpinPad(onKey: _onKey, isLoading: _isLoading),

                const SizedBox(height: 20),

                // ── Forgot MPIN ────────────────────────────────────────────
                TextButton(
                  onPressed: _isLoading ? null : _forgotMpin,
                  child: Text('Forgot MPIN?',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                        fontFamily: 'Poppins',
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white38,
                      )),
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),

          // ── Loading overlay ────────────────────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
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

