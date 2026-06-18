import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/router/app_router.dart';
import '../legal/screens/medical_disclaimer_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {

  // One-shot intro (2 s)
  late AnimationController _intro;
  // Infinite loop (3 s)
  late AnimationController _loop;

  static List<_Particle> _buildParticles() {
    final rng = Random(7);
    return List.generate(9, (_) => _Particle(
      xFrac:   0.18 + rng.nextDouble() * 0.64,
      size:    2.2  + rng.nextDouble() * 3.6,
      phase:   rng.nextDouble(),
      opacity: 0.22 + rng.nextDouble() * 0.44,
    ));
  }

  final List<_Particle> _particles = _buildParticles();

  // helpers ─────────────────────────────────────────────────────────────────
  double _iv(double t, double from, double to, Curve curve) {
    if (t <= from) return 0.0;
    if (t >= to) return 1.0;
    return curve.transform((t - from) / (to - from));
  }

  double _ivRaw(double t, double from, double to, Curve curve,
      double start, double end) {
    final p = _iv(t, from, to, curve);
    return start + (end - start) * p;
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..forward();

    _loop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();

    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final ok = await MedicalDisclaimerScreen.hasAccepted();
    if (!mounted) return;
    if (!ok) { _showDisclaimer(); return; }
    await _go();
  }

  void _showDisclaimer() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MedicalDisclaimerScreen(onAccepted: () async {
        if (mounted) Navigator.of(context).pop();
        await _go();
      }),
    ));
  }

  Future<void> _go() async {
    if (!mounted) return;
    final prefs     = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('onboarded') ?? false;

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser != null) {
      final uid = firebaseUser.uid;
      final db  = FirebaseFirestore.instance;

      // ── Step 1: Cache check (instant, offline) ───────────────────────────
      try {
        final cached = await db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        if (!mounted) return;
        if (cached.exists) {
          final data = cached.data() ?? {};
          if (data['mpinHash'] != null) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.createMpin, extra: {'mode': 'setup'});
          }
          return;
        }
      } on FirebaseException catch (_) {
        // Cache miss — continue to network check
      }

      // ── Step 2: Network check ────────────────────────────────────────────
      try {
        final doc = await db.collection('users').doc(uid).get();
        if (!mounted) return;
        if (doc.exists) {
          final data = doc.data() ?? {};
          if (data['mpinHash'] != null) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.createMpin, extra: {'mode': 'setup'});
          }
          return;
        }
        // Firebase session exists but no Firestore doc — sign out cleanly
        // so the user starts a fresh phone auth on the login screen.
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // Network failure — if cache was also empty, fall back to login
        if (!mounted) return;
        context.go(onboarded ? AppRoutes.login : AppRoutes.onboarding);
        return;
      }
    }

    if (!mounted) return;
    context.go(onboarded ? AppRoutes.login : AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF3a1732),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7b2d6e), Color(0xFF5e2750), Color(0xFF3a1732)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Ambient blooms (static)
            _Bloom(top: size.height * -0.15, left: size.width * -0.25,
                w: size.width * 1.1,  h: size.height * 0.55, opacity: 0.10),
            _Bloom(top: size.height * 0.73,  left: size.width * -0.20,
                w: size.width * 0.8,  h: size.height * 0.35, opacity: 0.06),

            // Floating sparkle particles
            AnimatedBuilder(
              animation: _loop,
              builder: (_, __) => Stack(
                children: _particles.map((p) {
                  final t = (_loop.value + p.phase) % 1.0;
                  final y = size.height * 0.75 - t * size.height * 0.50;
                  final alpha = t < 0.18
                      ? (t / 0.18) * p.opacity
                      : t > 0.78
                          ? ((1 - t) / 0.22) * p.opacity
                          : p.opacity;
                  return Positioned(
                    left: size.width * p.xFrac,
                    top:  y,
                    child: Opacity(
                      opacity: alpha.clamp(0.0, 1.0),
                      child: Container(
                        width: p.size, height: p.size,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFF2A8D8),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Main animated content — single AnimatedBuilder reads both clocks
            AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (_, __) {
                final t    = _intro.value;           // 0 → 1 over 2 s
                final loop = _loop.value;            // 0 → 1 repeating

                // ── Intro values (all computed from t) ────────────────────

                // M: scale 0→1 with bounce, fade 0→1
                final mFade  = _iv(t, 0.00, 0.40, Curves.easeOut);
                final mScale = _ivRaw(t, 0.00, 0.45, Curves.easeOutBack,
                    0.0, 1.0);

                // Shimmer: sweeps left to right across the M
                final shimmerX = _ivRaw(t, 0.38, 0.75, Curves.easeInOut,
                    -size.width * 0.5, size.width * 1.2);

                // Accent line: grows from 0 → full width
                final lineW = _iv(t, 0.44, 0.62, Curves.easeOut);

                // Wordmark
                final wordFade  = _iv(t, 0.52, 0.72, Curves.easeOut);
                final wordSlide = _ivRaw(t, 0.52, 0.72, Curves.easeOut,
                    26.0, 0.0);

                // Tagline
                final tagFade = _iv(t, 0.66, 0.84, Curves.easeOut);

                // Loader
                final loadFade = _iv(t, 0.80, 1.00, Curves.easeOut);

                // ── Loop values ───────────────────────────────────────────
                // Soft glow pulses 0→1→0 every 3 s
                final pulse = sin(loop * pi);

                return SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      SizedBox(height: size.height * 0.18),

                      // ── M ───────────────────────────────────────────────
                      Opacity(
                        opacity: mFade,
                        child: Transform.scale(
                          scale: mScale,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulsing radial glow
                              Opacity(
                                opacity: mFade * (0.12 + pulse * 0.14),
                                child: Container(
                                  width:  size.width * 0.84,
                                  height: size.width * 0.84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [
                                      const Color(0xFFF2A8D8).withValues(alpha:0.40),
                                      Colors.transparent,
                                    ]),
                                  ),
                                ),
                              ),

                              // The bold M
                              Text(
                                'M',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize:   size.width * 0.68,
                                  fontWeight: FontWeight.w900,
                                  color:      Colors.white,
                                  height:     0.88,
                                  letterSpacing: -4,
                                ),
                              ),

                              // Diagonal shimmer sweep
                              Positioned.fill(
                                child: ClipRect(
                                  child: OverflowBox(
                                    maxWidth: double.infinity,
                                    child: Transform.translate(
                                      offset: Offset(shimmerX, 0),
                                      child: Transform.rotate(
                                        angle: -pi / 5.5,
                                        child: Container(
                                          width: size.width * 0.30,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(colors: [
                                              Colors.white.withValues(alpha:0.00),
                                              Colors.white.withValues(alpha:0.26),
                                              Colors.white.withValues(alpha:0.00),
                                            ]),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: size.height * 0.006),

                      // ── Accent line grows from centre ────────────────────
                      SizedBox(
                        height: 5,
                        child: Center(
                          child: SizedBox(
                            width:  size.width * 0.44 * lineW,
                            height: 3.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Color(0xFFF2A8D8),
                                    Color(0xFFF2A8D8),
                                    Colors.transparent,
                                  ],
                                  stops: [0, 0.22, 0.78, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: size.height * 0.026),

                      // Thin divider
                      Opacity(
                        opacity: wordFade,
                        child: Container(
                          width: size.width * 0.72, height: 1,
                          color: Colors.white.withValues(alpha:0.10),
                        ),
                      ),

                      SizedBox(height: size.height * 0.020),

                      // ── med-NU wordmark ───────────────────────────────────
                      Opacity(
                        opacity: wordFade,
                        child: Transform.translate(
                          offset: Offset(0, wordSlide),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize:   size.width * 0.115,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                              children: const [
                                TextSpan(text: 'med',
                                    style: TextStyle(color: Colors.white)),
                                TextSpan(text: '-NU',
                                    style: TextStyle(color: Color(0xFFF2A8D8))),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: size.height * 0.010),

                      // ── Tagline ───────────────────────────────────────────
                      Opacity(
                        opacity: tagFade,
                        child: Text(
                          'ALWAYS WITH YOU',
                          style: TextStyle(
                            fontFamily:  'Poppins',
                            fontSize:    size.width * 0.033,
                            fontWeight:  FontWeight.w500,
                            color:       Colors.white.withValues(alpha:0.38),
                            letterSpacing: 5.0,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // ── Bottom loader ─────────────────────────────────────
                      Opacity(
                        opacity: loadFade,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: size.height * 0.055
                                + MediaQuery.of(context).padding.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 26, height: 26,
                                child: CircularProgressIndicator(
                                  color: Colors.white.withValues(alpha:0.50),
                                  strokeWidth: 2.0,
                                ),
                              ),
                              SizedBox(height: size.height * 0.016),
                              Text(
                                'MedNU Healthcare Services Pvt. Ltd.',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize:   size.width * 0.028,
                                  color:      Colors.white.withValues(alpha:0.28),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _Bloom extends StatelessWidget {
  const _Bloom({
    required this.top, required this.left,
    required this.w,   required this.h,
    required this.opacity,
  });
  final double top, left, w, h, opacity;

  @override
  Widget build(BuildContext context) => Positioned(
    top: top, left: left,
    child: Container(
      width: w, height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          const Color(0xFFF2A8D8).withValues(alpha:opacity),
          Colors.transparent,
        ]),
      ),
    ),
  );
}

class _Particle {
  final double xFrac, size, phase, opacity;
  const _Particle({
    required this.xFrac, required this.size,
    required this.phase, required this.opacity,
  });
}
