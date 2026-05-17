import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/notification_service.dart';
import '../widgets/task_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiService _aiService = AiService();

  List<Task> _allTasks = [];
  bool _isListening = false;
  bool _isProcessing = false;
  String _statusText = '';
  int _currentIndex = 0;
  String _userName = 'Alex';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadTasks();
    _initTts();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _loadTasks() async {
    final tasks = await DatabaseService.instance.getAllTasks();
    setState(() => _allTasks = tasks);
  }

  List<Task> get _todayTasks {
    final today = DateTime.now();
    return _allTasks.where((t) {
      if (t.isCompleted) return false;
      if (t.dueDate == null) return true;
      return t.dueDate!.year == today.year &&
          t.dueDate!.month == today.month &&
          t.dueDate!.day == today.day;
    }).toList();
  }

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
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Future<void> _startListening() async {
    if (_isProcessing) return;
    final available = await _speech.initialize();
    if (!available) return;

    setState(() {
      _isListening = true;
      _statusText = 'Listening...';
    });

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          await _processVoiceInput(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _processVoiceInput(String text) async {
    await _stopListening();
    setState(() {
      _isProcessing = true;
      _statusText = 'Processing...';
    });

    final isQuery = _isAgendaQuery(text);

    if (isQuery) {
      final answer = await _aiService.answerAgendaQuery(text, _allTasks);
      setState(() => _statusText = answer);
      await _tts.speak(answer);
    } else {
      final task = await _aiService.extractTaskFromText(text);
      if (task != null) {
        final saved = await DatabaseService.instance.createTask(task);
        await NotificationService.instance.scheduleTaskNotification(saved);
        await _loadTasks();
        setState(() => _statusText = '✓ Added: ${task.title}');
        await _tts.speak('Task added: ${task.title}');
      }
    }

    setState(() => _isProcessing = false);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusText = '');
    });
  }

  bool _isAgendaQuery(String text) {
    final keywords = [
      'quoi', 'agenda', 'aujourd\'hui', 'demain',
      'what', 'today', 'tomorrow', 'schedule', 'do i have',
      'ماذا', 'اليوم', 'غدا'
    ];
    return keywords.any((k) => text.toLowerCase().contains(k));
  }

  Future<void> _toggleTask(Task task) async {
    await DatabaseService.instance.updateTask(
      task.copyWith(isCompleted: !task.isCompleted),
    );
    await _loadTasks();
  }

  Future<void> _deleteTask(Task task) async {
    if (task.id != null) {
      await DatabaseService.instance.deleteTask(task.id!);
      await NotificationService.instance.cancelNotification(task.id!);
      await _loadTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStatsCards(),
                    const SizedBox(height: 28),
                    if (_todayTasks.isNotEmpty) ...[
                      _buildSectionHeader('TODAY', _todayTasks.length),
                      const SizedBox(height: 12),
                      ..._todayTasks.map((t) => TaskCard(
                            task: t,
                            onToggle: () => _toggleTask(t),
                            onDelete: () => _deleteTask(t),
                          )),
                      const SizedBox(height: 8),
                    ],
                    if (_upcomingTasks.isNotEmpty) ...[
                      _buildSectionHeader('UPCOMING', _upcomingTasks.length),
                      const SizedBox(height: 12),
                      ..._upcomingTasks.map((t) => TaskCard(
                            task: t,
                            onToggle: () => _toggleTask(t),
                            onDelete: () => _deleteTask(t),
                          )),
                      const SizedBox(height: 8),
                    ],
                    if (_todayTasks.isEmpty && _upcomingTasks.isEmpty)
                      _buildEmptyState(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),

            // Status text
            if (_statusText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: const Color(0xFFF2F2F7),
                child: Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isListening
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final dateStr =
        DateFormat('EEEE, MMM d').format(now).toUpperCase();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✦ ', style: TextStyle(color: Color(0xFF6366F1))),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6366F1),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_greeting',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                height: 1.2,
              ),
            ),
            Text(
              '$_userName ✨',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                height: 1.2,
              ),
            ),
          ],
        ),
        // Avatar
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF6366F1),
          ),
          child: Center(
            child: Text(
              _userName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _statsCard(
            '${_todayTasks.length}',
            'Today',
            const Color(0xFF6366F1),
            const Color(0xFFEEF0FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statsCard(
            '${_upcomingTasks.length}',
            'Upcoming',
            const Color(0xFFF59E0B),
            const Color(0xFFFFF8ED),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statsCard(
            '${_doneTasks.length}',
            'Done',
            const Color(0xFF10B981),
            const Color(0xFFEDFAF5),
          ),
        ),
      ],
    );
  }

  Widget _statsCard(String count, String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9CA3AF),
            letterSpacing: 1,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6366F1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                color: Color(0xFF6366F1),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No tasks yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the mic button to add a task',
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home_rounded, 'Home', 0),
              _navItem(Icons.notifications_outlined, 'Alerts', 1),
              _voiceNavButton(),
              _navItem(Icons.settings_outlined, 'Settings', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive
                ? const Color(0xFF6366F1)
                : const Color(0xFF9CA3AF),
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isActive
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF9CA3AF),
              fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceNavButton() {
    return GestureDetector(
      onTapDown: (_) => _startListening(),
      onTapUp: (_) => _stopListening(),
      onTapCancel: _stopListening,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isListening ? 60 : 52,
            height: _isListening ? 60 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6366F1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1)
                      .withOpacity(_isListening ? 0.5 : 0.3),
                  blurRadius: _isListening ? 20 : 10,
                  spreadRadius: _isListening ? 4 : 0,
                ),
              ],
            ),
            child: _isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            'Voice',
            style: TextStyle(
              fontSize: 11,
              color: _isListening
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF9CA3AF),
              fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
