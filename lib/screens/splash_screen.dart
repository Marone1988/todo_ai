import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Logo : apparition + scale
  late final AnimationController _logoCtrl;
  late final Animation<double>   _logoScale;
  late final Animation<double>   _logoOpacity;

  // Texte : fade + slide
  late final AnimationController _textCtrl;
  late final Animation<double>   _textOpacity;
  late final Animation<Offset>   _textSlide;

  // Barre de progression
  late final AnimationController _progressCtrl;

  // Sortie
  late final AnimationController _exitCtrl;
  late final Animation<double>   _exitOpacity;

  @override
  void initState() {
    super.initState();

    // Logo
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn));

    // Texte
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn));
    _textSlide = Tween<Offset>(
            begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _textCtrl, curve: Curves.easeOutCubic));

    // Barre de chargement — dure toute la durée de la splash
    _progressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3800));

    // Sortie
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));

    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoCtrl.forward();
    _progressCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 3000));

    // Fetch onboarding + abonnement state
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final access = await hasAccess();

    _exitCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 420));
    if (mounted) {
      Widget dest;
      if (!onboardingDone) {
        dest = const OnboardingScreen();      // 1ère fois → onboarding
      } else if (!access) {
        dest = const PaywallScreen();         // essai expiré → paywall
      } else {
        dest = const HomeScreen();            // accès OK → app
      }
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => dest,
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _progressCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [_logoCtrl, _textCtrl, _progressCtrl, _exitCtrl]),
        builder: (context, _) {
          return FadeTransition(
            opacity: _exitOpacity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Contenu central ─────────────────────────────
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo blanc
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 96, height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.15),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Colors.black,
                            size: 46,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Texte
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: const Column(children: [
                          Text(
                            'Vocal Todo',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Your AI voice assistant',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF636366),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),

                // ── Barre de progression en bas ──────────────────
                Positioned(
                  bottom: 52,
                  left: 40,
                  right: 40,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        // Track de la barre
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 2,
                            width: sw - 80,
                            child: Stack(children: [
                              // Fond sombre
                              Container(
                                color: Colors.white.withOpacity(0.1),
                              ),
                              // Progression blanche
                              FractionallySizedBox(
                                widthFactor: _progressCtrl.value,
                                child: Container(color: Colors.white),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Chargement...',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.3),
                            letterSpacing: 0.5,
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
    );
  }
}
