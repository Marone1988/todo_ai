import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart' as intl;
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../services/badge_service.dart';
import '../widgets/task_card.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'alerts_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiService _aiService = AiService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  List<Task> _allTasks = [];
  bool _isListening = false;
  bool _isProcessing = false;
  String _statusText = '';
  int _currentIndex = 0;
  String _userName = 'Alex';
  String? _avatarPath;
  String? _categoryFilter;

  // ── Langue de la reconnaissance vocale (indépendante de l'UI) ──
  // Mapping appLang → locale STT Android
  static const _langToLocale = {
    'fr': 'fr-FR',
    'en': 'en-US',
    'ar': 'ar-SA',
  };
  static const _voiceLangs = [
    {'code': 'fr', 'locale': 'fr-FR', 'flag': '🇫🇷', 'label': 'FR'},
    {'code': 'en', 'locale': 'en-US', 'flag': '🇬🇧', 'label': 'EN'},
    {'code': 'ar', 'locale': 'ar-SA', 'flag': '🇲🇦', 'label': 'AR'},
  ];
  // Par défaut = langue de l'interface
  String _voiceLangCode = 'fr';
  String get _activeSttLocale => _langToLocale[_voiceLangCode] ?? 'fr-FR';

  // Recherche
  bool _showSearch = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  // Undo delete
  final Set<int> _pendingDeletes = {};

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadTasks();
    _loadUserPrefs();
    _initTts();
    // Sync langue vocale avec la langue de l'interface au démarrage
    _voiceLangCode = appLang.value;
    appLang.addListener(_syncVoiceLang);
    appThemeMode.addListener(_onLangChange);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onLangChange() => setState(() {});

  /// Synchronise la langue vocale quand l'utilisateur change la langue de l'UI
  void _syncVoiceLang() {
    final newLang = appLang.value;
    // Seulement si l'utilisateur n'a pas manuellement choisi une autre langue
    if (_langToLocale.containsKey(newLang)) {
      setState(() => _voiceLangCode = newLang);
    }
    _onLangChange();
  }

  Future<void> _loadUserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName   = prefs.getString('user_name')  ?? 'Alex';
      _avatarPath = prefs.getString('user_avatar');
    });
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _initTts() async {
    await _tts.setSpeechRate(0.5);
  }

  /// Langue TTS selon la langue détectée dans la tâche
  Future<void> _setTtsLanguage(String lang) async {
    switch (lang) {
      case 'ar': await _tts.setLanguage('ar-SA'); break;
      case 'en': await _tts.setLanguage('en-US'); break;
      default:   await _tts.setLanguage('fr-FR'); break;
    }
  }

  Future<void> _loadTasks() async {
    final tasks = await DatabaseService.instance.getAllTasks();
    if (mounted) setState(() => _allTasks = tasks);
    WidgetService.update(tasks);
    BadgeService.instance.update(tasks);
    taskVersion.value++; // signal AlertsScreen de se rafraîchir
  }

  // ── Getters tâches filtrées ─────────────────────────────────

  List<Task> get _todayTasks {
    final today = DateTime.now();
    final q = _searchQuery.toLowerCase();
    return _allTasks.where((t) {
      if (q.isNotEmpty && !t.title.toLowerCase().contains(q)) return false;
      if (_categoryFilter != null && t.category != _categoryFilter) return false;
      if (t.dueDate == null) return !t.isCompleted;
      return t.dueDate!.year == today.year &&
          t.dueDate!.month == today.month &&
          t.dueDate!.day == today.day;
    }).toList()
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
  }

  int get _todayPendingCount =>
      _todayTasks.where((t) => !t.isCompleted).length;

  List<Task> get _upcomingTasks {
    final today = DateTime.now();
    final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
    return _allTasks.where((t) {
      if (t.isCompleted) return false;
      if (t.dueDate == null) return false;
      return t.dueDate!.isAfter(todayEnd);
    }).toList();
  }

  List<Task> get _doneTasks => _allTasks.where((t) => t.isCompleted).toList();

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return t('good_morning');
    if (hour < 17) return t('good_afternoon');
    return t('good_evening');
  }

  // ── Reconnaissance vocale ────────────────────────────────────

  Future<void> _startListening() async {
    if (_isProcessing) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _statusText = '❌ Permission microphone refusée');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _statusText = '');
      });
      return;
    }

    final available = await _speech.initialize(
      onError: (error) {
        if (error.errorMsg == 'error_speech_timeout') return; // silence timeout
        setState(() {
          _isListening = false;
          _statusText = 'Erreur: ${error.errorMsg}';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _statusText = '');
        });
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );

    if (!available) {
      setState(() => _statusText = '❌ Reconnaissance vocale indisponible');
      return;
    }

    setState(() {
      _isListening = true;
      _statusText = t('listening');
    });

    final listenOptions = SpeechListenOptions(
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );

    await _speech.listen(
      onResult: (result) async {
        if (result.recognizedWords.isNotEmpty) {
          setState(() => _statusText = '💬 "${result.recognizedWords}"');
        }
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          await _processVoiceInput(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: _activeSttLocale,
      listenOptions: listenOptions,
    );

    Future.delayed(const Duration(seconds: 32), () {
      if (_isListening && mounted) {
        _speech.stop();
        setState(() { _isListening = false; _statusText = ''; });
      }
    });
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() { _isListening = false; if (_statusText.startsWith('🎤')) _statusText = ''; });
  }

  Future<void> _processVoiceInput(String text) async {
    await _stopListening();
    setState(() { _isProcessing = true; _statusText = ''; });

    if (_isAgendaQuery(text)) {
      final answer = await _aiService.answerAgendaQuery(text, _allTasks);
      setState(() { _isProcessing = false; _statusText = answer; });
      // Adapter la langue TTS à la question posée
      final lang = _detectLang(text);
      await _setTtsLanguage(lang);
      await _tts.speak(answer);
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _statusText = '');
      });
    } else {
      final aiTask = await _aiService.extractTaskFromText(text);
      setState(() => _isProcessing = false);
      if (aiTask != null && mounted) {
        // Ouvrir la feuille d'édition complète — l'utilisateur peut tout modifier
        final taskToSave = await _showVoiceTaskEditor(text, aiTask);
        if (taskToSave != null) {
          final saved = await DatabaseService.instance.createTask(taskToSave);
          await NotificationService.instance.scheduleTaskNotification(saved);
          await _loadTasks();
          _showSaveSuccess();
          await _setTtsLanguage(taskToSave.language);
          await _tts.speak('${t('task_added')}${taskToSave.title}');
        } else {
          setState(() => _statusText = '');
        }
      }
    }
  }

  /// Affiche un grand ✓ vert animé au centre de l'écran, puis disparaît.
  void _showSaveSuccess() {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _SaveSuccessOverlay(onDone: () {
        if (entry.mounted) entry.remove();
      }),
    );
    overlay.insert(entry);
  }

  /// Détecte la langue d'un texte basiquement (pour le TTS)
  String _detectLang(String text) {
    if (RegExp(r'[؀-ۿ]').hasMatch(text)) return 'ar';
    final lower = text.toLowerCase();
    final frWords = ["aujourd", 'demain', 'bonjour', 'ajoute', "qu'est", 'tâche', 'réunion'];
    if (frWords.any((w) => lower.contains(w))) return 'fr';
    return 'en';
  }

  bool _isAgendaQuery(String text) {
    final lower = text.toLowerCase();
    final questionWords = [
      'quoi', "qu'est", 'quel', 'what', 'show me', 'dis-moi', 'montre',
      'combien', 'how many', 'liste', 'list', 'يستعرض', 'كم', 'ماذا', 'أخبرني', 'أرني'
    ];
    final domainWords = [
      "aujourd'hui", 'demain', 'today', 'tomorrow', 'agenda', 'planning',
      'semaine', 'week', 'urgent', 'urgente', 'priorité', 'haute priorité',
      'réunion', 'meeting', 'اليوم', 'غدا', 'أسبوع', 'عاجل', 'اجتماع'
    ];
    return questionWords.any((q) => lower.contains(q)) &&
        domainWords.any((w) => lower.contains(w));
  }

  // ── Actions tâches ───────────────────────────────────────────

  Future<void> _toggleTask(Task task) async {
    final isNowCompleted = !task.isCompleted;
    final updated = task.copyWith(
      isCompleted: isNowCompleted,
      completedAt: isNowCompleted ? DateTime.now() : null,
      clearCompletedAt: !isNowCompleted,
    );
    await DatabaseService.instance.updateTask(updated);

    // Récurrence
    if (updated.isCompleted &&
        updated.recurrence != 'none' &&
        updated.dueDate != null) {
      final nextDate = _nextDate(updated.dueDate!, updated.recurrence);
      final nextTask = updated.copyWith(
        id: null,
        isCompleted: false,
        clearCompletedAt: true,
        dueDate: nextDate,
      );
      final saved = await DatabaseService.instance.createTask(nextTask);
      await NotificationService.instance.scheduleTaskNotification(saved);
    }
    await _loadTasks();
  }

  DateTime _nextDate(DateTime base, String recurrence) {
    switch (recurrence) {
      case 'daily':   return base.add(const Duration(days: 1));
      case 'weekly':  return base.add(const Duration(days: 7));
      case 'monthly': return DateTime(base.year, base.month + 1, base.day, base.hour, base.minute);
      default:        return base;
    }
  }

  void _deleteTask(Task task) {
    if (task.id == null) return;
    setState(() {
      _allTasks.removeWhere((t) => t.id == task.id);
      _pendingDeletes.add(task.id!);
    });
    BadgeService.instance.update(_allTasks);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: Text(t('task_deleted')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1F2937),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          showCloseIcon: true,
          closeIconColor: Colors.white54,
          action: SnackBarAction(
            label: t('undo'),
            textColor: const Color(0xFF818CF8),
            onPressed: () {
              _pendingDeletes.remove(task.id!);
              _loadTasks();
            },
          ),
          duration: const Duration(seconds: 3),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action &&
          _pendingDeletes.contains(task.id!)) {
        DatabaseService.instance.deleteTask(task.id!);
        NotificationService.instance.cancelNotification(task.id!);
        _pendingDeletes.remove(task.id!);
        WidgetService.update(_allTasks);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      // IndexedStack keeps all screens alive — no reload on tab switch,
      // and AlertsScreen/SettingsScreen won't flash empty while loading.
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeBody(),
          const AlertsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Home body ────────────────────────────────────────────────

  Widget _buildHomeBody() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildHeader(),
                  ),
                  const SizedBox(height: 16),
                  _buildCategoryFilter(),
                  const SizedBox(height: 16),
                  if (_todayTasks.isNotEmpty) ...[
                    ..._todayTasks.map((task) => TaskCard(
                          task: task,
                          onToggle: () => _toggleTask(task),
                          onDelete: () => _deleteTask(task),
                          onRefresh: _loadTasks,
                        )),
                    const SizedBox(height: 8),
                  ],
                  if (_todayTasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildEmptyState(),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          if (_statusText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: context.bgColor,
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _isListening
                      ? context.primaryLight
                      : context.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final cats = [
      {'key': '', 'label': t('cat_all')},
      {'key': 'work',     'label': t('cat_work')},
      {'key': 'personal', 'label': t('cat_personal')},
      {'key': 'other',    'label': t('cat_other')},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: cats.map((cat) {
              final catKey = cat['key']!.isEmpty ? null : cat['key'];
              final isSelected = _categoryFilter == catKey;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () { haptic(); setState(() => _categoryFilter = catKey); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(cat['label']!,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    )),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final now     = DateTime.now();
    final dayName = intl.DateFormat('EEEE').format(now);  // "lundi"
    final dateTop = intl.DateFormat('d MMM').format(now).toUpperCase(); // "18 MAI"

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ligne date + recherche ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(dateTop,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: context.textMuted, letterSpacing: 1.0)),
            ),
            // Loupe en premier
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) { _searchQuery = ''; _searchCtrl.clear(); }
              }),
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _showSearch
                      ? context.primaryLight.withOpacity(0.12)
                      : context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                  color: _showSearch ? context.primaryLight : context.textMuted,
                  size: 20,
                ),
              ),
            ),
            // Avatar à droite
            GestureDetector(
              onTap: () { haptic(); setState(() => _currentIndex = 2); },
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.cardColor,
                  image: _avatarPath != null
                      ? DecorationImage(image: FileImage(File(_avatarPath!)), fit: BoxFit.cover)
                      : null,
                ),
                child: _avatarPath == null
                    ? Center(child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
                        style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                      ))
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ── Nom du jour (très grand, style screenshot) ──────────
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _showSearch
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: TextStyle(color: context.textPrimary),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: t('search_hint'),
                      hintStyle: TextStyle(color: context.textMuted),
                      prefixIcon: Icon(Icons.search, color: context.primaryLight, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () => setState(() {
                                _searchQuery = '';
                                _searchCtrl.clear();
                              }),
                              child: Icon(Icons.close, size: 18, color: context.textMuted),
                            )
                          : null,
                      filled: true,
                      fillColor: context.cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.primaryLight, width: 1.5)),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayName[0].toUpperCase() + dayName.substring(1),
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                          height: 1.1,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t('hello')}, $_userName',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: context.textSecondary),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(child: _statsCard('$_todayPendingCount', t('stat_today'),
            const Color(0xFF6366F1),
            context.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF0FF))),
        const SizedBox(width: 12),
        Expanded(child: _statsCard('${_upcomingTasks.length}', t('stat_upcoming'),
            const Color(0xFFF59E0B),
            context.isDark ? const Color(0xFF2C1A00) : const Color(0xFFFFF8ED))),
        const SizedBox(width: 12),
        Expanded(child: _statsCard('${_doneTasks.length}', t('stat_done'),
            const Color(0xFF10B981),
            context.isDark ? const Color(0xFF022C22) : const Color(0xFFEDFAF5))),
      ],
    );
  }

  Widget _statsCard(String count, String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text(count, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 13, color: context.textSecondary, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textMuted,
                letterSpacing: 1.2)),
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            color: context.primaryLight.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$count', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: context.primaryLight)),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: context.primaryLight.withOpacity(0.1),
              shape: BoxShape.circle),
            child: Icon(Icons.mic_none_rounded, color: context.primaryLight, size: 32),
          ),
          const SizedBox(height: 16),
          Text(t('empty_title'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                  color: context.textPrimary)),
          const SizedBox(height: 6),
          Text(t('empty_sub'),
              style: TextStyle(fontSize: 14, color: context.textMuted)),
        ]),
      ),
    );
  }

  // ── Bottom Navigation ────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // ── Gauche : Today + Agenda ──────────────────────────
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _navItem(Icons.home_rounded, Icons.home_rounded, t('nav_today'), 0),
                _navItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, t('nav_agenda'), 1),
              ],
            ),
          ),
          // ── Centre : bouton micro ────────────────────────────
          _voiceNavButton(),
          // ── Droite : Settings seul ───────────────────────────
          Expanded(
            child: Center(
              child: _navItem(Icons.settings_outlined, Icons.settings_rounded, t('nav_settings'), 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData iconInactive, IconData iconActive, String label, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        haptic();
        setState(() => _currentIndex = index);
      },
      child: SizedBox(
        width: 68,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActive ? iconActive : iconInactive,
                  color: isActive ? Colors.white : const Color(0xFF636366),
                  size: 26,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? Colors.white : const Color(0xFF636366),
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceNavButton() {
    // Langue vocale active (flag + code)
    final currentLang = _voiceLangs.firstWhere(
      (l) => l['code'] == _voiceLangCode,
      orElse: () => _voiceLangs.first,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(alignment: Alignment.center, children: [
          // Bouton micro principal
          // • Tap court  → toggle écoute / arrêt
          // • Maintien   → écoute pendant l'appui, traitement au relâchement
          GestureDetector(
            onTap: () {
              haptic();
              _isListening ? _stopListening() : _startListening();
            },
            onLongPressStart: (_) {
              if (!_isListening && !_isProcessing) {
                haptic();
                _startListening();
              }
            },
            onLongPressEnd: (_) { if (_isListening) _stopListening(); },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                final color = _isListening
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF6366F1);
                final scale = _pulseAnimation.value;
                return Stack(alignment: Alignment.center, children: [
                  Transform.scale(scale: scale, child: Container(width: 100, height: 100,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: color.withOpacity(_isListening ? 0.22 : 0.12)))),
                  Transform.scale(scale: scale * 0.86, child: Container(width: 100, height: 100,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: color.withOpacity(_isListening ? 0.18 : 0.08)))),
                  Container(
                    width: _isListening ? 82 : 78,
                    height: _isListening ? 82 : 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: color,
                      boxShadow: [BoxShadow(color: color.withOpacity(scale * 0.45),
                          blurRadius: _isListening ? 32 : 24,
                          spreadRadius: _isListening ? 6 : 3)],
                    ),
                    child: _isProcessing
                        ? const Padding(padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Icon(_isListening
                                ? Icons.stop_rounded : Icons.mic_none_rounded,
                            color: Colors.white, size: 36),
                  ),
                ]);
              },
            ),
          ),
          // Badge langue vocale — appuyer pour cycler FR → EN → AR → FR
          if (!_isListening)
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: () {
                  final idx = _voiceLangs.indexWhere(
                      (l) => l['code'] == _voiceLangCode);
                  final next = _voiceLangs[(idx + 1) % _voiceLangs.length];
                  setState(() => _voiceLangCode = next['code']!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.cardColor, width: 1.5),
                  ),
                  child: Text(
                    currentLang['flag']!,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  // ── Feuille vocale éditable ──────────────────────────────────

  /// Ouvre un bottom sheet complet après la reconnaissance vocale.
  /// L'utilisateur peut modifier tous les champs avant de sauvegarder.
  /// Retourne la [Task] à sauvegarder, ou null si annulé.
  Future<Task?> _showVoiceTaskEditor(String rawText, Task aiTask) {
    final titleCtrl = TextEditingController(text: aiTask.title);
    String selCat      = aiTask.category;
    DateTime? selDate  = aiTask.dueDate;
    String selPriority = aiTask.priority;
    String selRec      = aiTask.recurrence;
    int selReminder    = aiTask.reminderMinutes;

    return showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: context.dividerColor,
                        borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),

                  // Bandeau "IA a compris" avec le texte brut
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.primaryLight.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: context.primaryLight.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Text('🤖', style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('ai_understood'),
                              style: TextStyle(fontSize: 11,
                                  color: context.primaryLight,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3)),
                          const SizedBox(height: 2),
                          Text('"$rawText"',
                              style: TextStyle(fontSize: 12,
                                  color: context.textSecondary,
                                  fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Titre
                  Text(t('field_title'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    autofocus: false,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600,
                        color: context.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.inputFill,
                      hintText: t('field_title'),
                      hintStyle: TextStyle(color: context.textMuted),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: context.primaryLight, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Catégorie
                  Text(t('field_category'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  _editorDropdown<String>(
                    value: selCat,
                    items: const [
                      DropdownMenuItem(value: 'work',     child: Text('Travail')),
                      DropdownMenuItem(value: 'personal', child: Text('Personnel')),
                      DropdownMenuItem(value: 'other',    child: Text('Autre')),
                    ],
                    onChanged: (v) { if (v != null) setModal(() => selCat = v); },
                    ctx: ctx,
                  ),
                  const SizedBox(height: 16),

                  // Priorité
                  Text(t('priority'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  _editorDropdown<String>(
                    value: selPriority,
                    items: [
                      DropdownMenuItem(value: 'high',   child: Row(children: [Container(width:10,height:10,decoration:const BoxDecoration(color:Color(0xFFEF4444),shape:BoxShape.circle)),const SizedBox(width:8),const Text('Haute')])),
                      DropdownMenuItem(value: 'normal', child: Row(children: [Container(width:10,height:10,decoration:const BoxDecoration(color:Color(0xFFF59E0B),shape:BoxShape.circle)),const SizedBox(width:8),const Text('Normale')])),
                      DropdownMenuItem(value: 'low',    child: Row(children: [Container(width:10,height:10,decoration:const BoxDecoration(color:Color(0xFF9CA3AF),shape:BoxShape.circle)),const SizedBox(width:8),const Text('Basse')])),
                    ],
                    onChanged: (v) { if (v != null) setModal(() => selPriority = v); },
                    ctx: ctx,
                  ),
                  const SizedBox(height: 16),

                  // Date & heure
                  Text(t('add_date'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: selDate ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(
                              colorScheme: const ColorScheme.light(
                                  primary: Color(0xFF6366F1))),
                          child: child!),
                      );
                      if (date != null && ctx.mounted) {
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(
                              selDate ?? DateTime.now()),
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                                colorScheme: const ColorScheme.light(
                                    primary: Color(0xFF6366F1))),
                            child: child!),
                        );
                        if (time != null) {
                          setModal(() => selDate = DateTime(
                              date.year, date.month, date.day,
                              time.hour, time.minute));
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.inputFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selDate != null
                              ? context.primaryLight.withOpacity(0.4)
                              : Colors.transparent),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 18,
                            color: selDate != null
                                ? context.primaryLight : context.textMuted),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          selDate != null
                              ? intl.DateFormat('EEE d MMM • HH:mm').format(selDate!)
                              : t('add_date'),
                          style: TextStyle(
                              fontSize: 14,
                              color: selDate != null
                                  ? context.primaryLight : context.textMuted,
                              fontWeight: selDate != null
                                  ? FontWeight.w600 : FontWeight.normal),
                        )),
                        if (selDate != null)
                          GestureDetector(
                            onTap: () => setModal(() => selDate = null),
                            child: Icon(Icons.close, size: 16,
                                color: context.textMuted),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Rappel
                  Text(t('reminder'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  _editorDropdown<int>(
                    value: selReminder,
                    items: const [
                      DropdownMenuItem(value: 0,    child: Text("À l'heure")),
                      DropdownMenuItem(value: 15,   child: Text('15 min avant')),
                      DropdownMenuItem(value: 60,   child: Text('1 heure avant')),
                      DropdownMenuItem(value: 1440, child: Text('1 jour avant')),
                    ],
                    onChanged: (v) { if (v != null) setModal(() => selReminder = v); },
                    ctx: ctx,
                  ),
                  const SizedBox(height: 16),

                  // Récurrence
                  Text(t('recurrence'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: context.textSecondary)),
                  const SizedBox(height: 8),
                  _editorDropdown<String>(
                    value: selRec,
                    items: const [
                      DropdownMenuItem(value: 'none',    child: Text('Jamais')),
                      DropdownMenuItem(value: 'daily',   child: Text('Chaque jour')),
                      DropdownMenuItem(value: 'weekly',  child: Text('Chaque semaine')),
                      DropdownMenuItem(value: 'monthly', child: Text('Chaque mois')),
                    ],
                    onChanged: (v) { if (v != null) setModal(() => selRec = v); },
                    ctx: ctx,
                  ),
                  const SizedBox(height: 28),

                  // Boutons
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                              color: context.cardColor2,
                              borderRadius: BorderRadius.circular(14)),
                          child: Center(child: Text(t('cancel'),
                              style: TextStyle(fontWeight: FontWeight.w600,
                                  color: context.textSecondary, fontSize: 15))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) return;
                          Navigator.pop(ctx, aiTask.copyWith(
                            title: title,
                            category: selCat,
                            priority: selPriority,
                            recurrence: selRec,
                            reminderMinutes: selReminder,
                            dueDate: selDate,
                            clearDueDate: selDate == null,
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [context.primaryLight,
                                context.primaryLight.withBlue(220)]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(
                                color: context.primaryLight.withOpacity(0.35),
                                blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Center(child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text(t('save_task'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white, fontSize: 15)),
                            ],
                          )),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required BuildContext ctx,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: context.cardColor,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textMuted, size: 20),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.textPrimary),
        ),
      ),
    );
  }

  Widget _editorChip(String emoji, String label, String value, String selected,
      Function(String) onTap, BuildContext ctx, {Color? activeColor}) {
    final isSel = selected == value;
    final color = activeColor ?? context.primaryLight;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
            color: isSel ? color : context.inputFill,
            borderRadius: BorderRadius.circular(10)),
        child: Text(
          emoji.isEmpty ? label : '$emoji $label',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: isSel ? Colors.white : context.textSecondary),
        ),
      ),
    );
  }

  Widget _editorRemChip(String label, int value, int selected,
      Function(int) onTap, BuildContext ctx) {
    final isSel = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
            color: isSel ? context.primaryLight : context.inputFill,
            borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: isSel ? Colors.white : context.textSecondary)),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _pulseController.dispose();
    appLang.removeListener(_syncVoiceLang);
    appThemeMode.removeListener(_onLangChange);
    super.dispose();
  }
}

// ── Overlay animé ✓ vert au centre ──────────────────────────────
class _SaveSuccessOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const _SaveSuccessOverlay({required this.onDone});
  @override
  State<_SaveSuccessOverlay> createState() => _SaveSuccessOverlayState();
}

class _SaveSuccessOverlayState extends State<_SaveSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _scale   = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.35)));
    _ctrl.forward();
    // Auto-dismiss après 1,3s
    Future.delayed(const Duration(milliseconds: 1300), () async {
      if (!mounted) return;
      await _ctrl.reverse(from: 1.0);
      widget.onDone();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _opacity.value,
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.5),
                      blurRadius: 50, spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 68),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
