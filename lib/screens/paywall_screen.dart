import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

// ── Clés SharedPreferences ───────────────────────────────────────
const _kTrialStart   = 'trial_start_ms';
const _kSubscribed   = 'is_subscribed';
const _kPlanSelected = 'selected_plan'; // 'monthly' | 'annual'

/// Vérifie si l'utilisateur a accès (essai en cours ou abonné).
Future<bool> hasAccess() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kSubscribed) == true) return true;
  final start = prefs.getInt(_kTrialStart);
  if (start == null) return false;
  final elapsed = DateTime.now().millisecondsSinceEpoch - start;
  return elapsed < const Duration(days: 3).inMilliseconds;
}

/// Démarre l'essai gratuit (appel unique à la première souscription).
Future<void> startTrial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getInt(_kTrialStart) == null) {
    await prefs.setInt(_kTrialStart, DateTime.now().millisecondsSinceEpoch);
  }
}

/// Retourne les jours restants d'essai (0 si expiré ou non démarré).
Future<int> trialDaysLeft() async {
  final prefs = await SharedPreferences.getInstance();
  final start = prefs.getInt(_kTrialStart);
  if (start == null) return 3; // pas encore démarré
  final elapsed = DateTime.now().millisecondsSinceEpoch - start;
  final remaining = const Duration(days: 3).inMilliseconds - elapsed;
  return (remaining / Duration.millisecondsPerDay).ceil().clamp(0, 3);
}

// ────────────────────────────────────────────────────────────────
class PaywallScreen extends StatefulWidget {
  /// Si true, l'utilisateur vient de terminer l'onboarding
  final bool fromOnboarding;
  const PaywallScreen({super.key, this.fromOnboarding = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen>
    with TickerProviderStateMixin {
  String _plan = 'annual'; // plan sélectionné
  bool _loading = false;

  // Animations d'entrée
  late final AnimationController _enterCtrl;
  late final Animation<double>    _fadeIn;
  late final Animation<Offset>    _slideUp;

  // Animation du bouton CTA
  late final AnimationController _btnCtrl;
  late final Animation<double>    _btnScale;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));

    _btnCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _btnScale = Tween<double>(begin: 1.0, end: 1.03)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut));

    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────

  Future<void> _startTrial() async {
    HapticFeedback.heavyImpact();
    setState(() => _loading = true);

    // Simule un appel Play Store (sera remplacé par in_app_purchase)
    await Future.delayed(const Duration(milliseconds: 800));

    await startTrial();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlanSelected, _plan);

    if (!mounted) return;
    setState(() => _loading = false);
    _goHome();
  }

  Future<void> _restore() async {
    HapticFeedback.lightImpact();
    // TODO: restaurer l'achat via in_app_purchase
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Aucun abonnement actif trouvé.'),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const HomeScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideUp,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildContent()),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          _buildHero(),
          const SizedBox(height: 28),
          _buildFeatures(),
          const SizedBox(height: 28),
          _buildPlans(),
          const SizedBox(height: 28),
          _buildCTA(),
          const SizedBox(height: 16),
          _buildRestoreBtn(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Column(children: [
      // Icône avec halo violet
      Stack(alignment: Alignment.center, children: [
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6366F1).withOpacity(0.12),
          ),
        ),
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6366F1).withOpacity(0.18),
          ),
        ),
        Container(
          width: 68, height: 68,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF6366F1),
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 36),
        ),
        // Badge IA
        Positioned(
          right: 12, bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Text('AI', style: TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      // Titre
      const Text(
        'Passez à\nVocal Todo Premium',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800,
          color: Colors.white, height: 1.2,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 10),
      // Badge essai gratuit
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '🎁  3 jours gratuits, sans engagement',
          style: TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    ]);
  }

  // ── Features ─────────────────────────────────────────────────────

  Widget _buildFeatures() {
    final items = [
      (Icons.mic_rounded,        'Reconnaissance vocale illimitée',  'Créez des tâches à la voix en FR / EN / AR'),
      (Icons.psychology_rounded, 'IA Groq ultra-rapide',             'Extraction intelligente de titre, date, priorité'),
      (Icons.calendar_month_rounded, 'Agenda & rappels avancés',     'Vue semaine/mois, rappels GPS, récurrence'),
      (Icons.notifications_active_rounded, 'Notifications intelligentes', 'Alertes ponctuelles avec votre logo'),
      (Icons.sync_rounded,       'Sync Google Agenda',               'Import automatique de vos événements'),
      (Icons.cloud_done_rounded, 'Toutes les mises à jour futures',  'Nouvelles fonctionnalités incluses'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Column(children: [
            if (i > 0)
              const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
            _featureRow(item.$1, item.$2, item.$3),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF818CF8), size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(
                color: Color(0xFF8E8E93), fontSize: 12)),
          ],
        )),
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF10B981), size: 18),
      ]),
    );
  }

  // ── Plans ─────────────────────────────────────────────────────────

  Widget _buildPlans() {
    return Column(children: [
      Row(children: [
        Expanded(child: _planCard(
          id: 'monthly',
          label: 'Mensuel',
          price: '2,99€',
          period: '/mois',
          badge: null,
        )),
        const SizedBox(width: 12),
        Expanded(child: _planCard(
          id: 'annual',
          label: 'Annuel',
          price: '14,99€',
          period: '/an',
          badge: 'Économisez 58%',
        )),
      ]),
      const SizedBox(height: 10),
      // Équivalent par mois pour le plan annuel
      AnimatedOpacity(
        opacity: _plan == 'annual' ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: const Text(
          'Soit seulement 1,25€/mois avec le plan annuel',
          style: TextStyle(fontSize: 11, color: Color(0xFF636366)),
        ),
      ),
    ]);
  }

  Widget _planCard({
    required String id,
    required String label,
    required String price,
    required String period,
    required String? badge,
  }) {
    final isSelected = _plan == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _plan = id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withOpacity(0.15)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF2C2C2E),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              )
            else
              const SizedBox(height: 25),
            Text(label,
                style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF8E8E93),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(price,
                style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF636366),
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            Text(period,
                style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF636366),
                    fontSize: 12)),
            const SizedBox(height: 8),
            // Radio indicator
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 18, height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF48484A),
                    width: 2,
                  ),
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 11)
                    : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── CTA ───────────────────────────────────────────────────────────

  Widget _buildCTA() {
    return AnimatedBuilder(
      animation: _btnScale,
      builder: (_, __) => Transform.scale(
        scale: _btnScale.value,
        child: GestureDetector(
          onTap: _loading ? null : _startTrial,
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _plan == 'annual'
                            ? 'Essayer 3 jours gratuits — 14,99€/an ensuite'
                            : 'Essayer 3 jours gratuits — 2,99€/mois ensuite',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────

  Widget _buildRestoreBtn() {
    return GestureDetector(
      onTap: _restore,
      child: const Text(
        'Restaurer un achat',
        style: TextStyle(fontSize: 13, color: Color(0xFF636366)),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      child: Column(children: [
        const Divider(height: 1, thickness: 0.5, color: Color(0xFF1C1C1E)),
        const SizedBox(height: 10),
        const Text(
          'Abonnement reconduit automatiquement. Annulable à tout moment depuis '
          'les paramètres Google Play. Aucun débit pendant les 3 jours d\'essai.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Color(0xFF48484A), height: 1.5),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _footerLink('Conditions d\'utilisation'),
          const Text('  ·  ', style: TextStyle(color: Color(0xFF48484A), fontSize: 10)),
          _footerLink('Politique de confidentialité'),
        ]),
      ]),
    );
  }

  Widget _footerLink(String text) {
    return GestureDetector(
      onTap: () {/* TODO: ouvrir URL */},
      child: Text(text,
          style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF636366),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF636366))),
    );
  }
}
