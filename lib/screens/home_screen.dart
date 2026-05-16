import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/notification_service.dart';
import '../widgets/task_card.dart';
import '../widgets/voice_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiService _aiService = AiService();

  List<Task> _tasks = [];
  bool _isListening = false;
  bool _isProcessing = false;
  String _statusText = 'Appuyez pour parler';
  String _selectedFilter = 'today';

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
    await _tts.setVolume(1.0);
  }

  Future<void> _loadTasks() async {
    List<Task> tasks;
    if (_selectedFilter == 'today') {
      tasks = await DatabaseService.instance.getTasksForToday();
    } else if (_selectedFilter == 'tomorrow') {
      tasks = await DatabaseService.instance.getTasksForTomorrow();
    } else {
      tasks = await DatabaseService.instance.getAllTasks();
    }
    setState(() => _tasks = tasks);
  }

  Future<void> _startListening() async {
    if (_isProcessing) return;

    final available = await _speech.initialize();
    if (!available) {
      setState(() => _statusText = 'Microphone non disponible');
      return;
    }

    setState(() {
      _isListening = true;
      _statusText = 'Je vous écoute...';
    });

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            await _processVoiceInput(text);
          }
        }
      },
      localeId: 'fr_FR',
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
      _statusText = 'Traitement en cours...';
    });

    // Détecter si c'est une question sur l'agenda
    final isQuery = _isAgendaQuery(text);

    if (isQuery) {
      // Répondre à une requête d'agenda
      final allTasks = await DatabaseService.instance.getAllTasks();
      final answer = await _aiService.answerAgendaQuery(text, allTasks);
      setState(() => _statusText = answer);
      await _tts.speak(answer);
    } else {
      // Créer une nouvelle tâche
      final task = await _aiService.extractTaskFromText(text);
      if (task != null) {
        final savedTask = await DatabaseService.instance.createTask(task);
        await NotificationService.instance.scheduleTaskNotification(savedTask);
        await _loadTasks();
        setState(() => _statusText = '✅ Tâche ajoutée : ${task.title}');
        await _tts.speak('Tâche ajoutée : ${task.title}');
      }
    }

    setState(() => _isProcessing = false);

    // Réinitialiser le message après 3 secondes
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusText = 'Appuyez pour parler');
    });
  }

  bool _isAgendaQuery(String text) {
    final keywords = [
      'quoi', 'qu\'est-ce', 'agenda', 'aujourd\'hui', 'demain',
      'what', 'today', 'tomorrow', 'schedule',
      'ماذا', 'اليوم', 'غدا', 'جدول'
    ];
    return keywords.any((k) => text.toLowerCase().contains(k));
  }

  Future<void> _toggleTaskComplete(Task task) async {
    final updated = task.copyWith(isCompleted: !task.isCompleted);
    await DatabaseService.instance.updateTask(updated);
    if (updated.isCompleted && task.id != null) {
      await NotificationService.instance.cancelNotification(task.id!);
    }
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
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE d MMMM', 'fr_FR').format(now);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vocal Todo',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Filtres
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _filterChip('Aujourd\'hui', 'today'),
                  const SizedBox(width: 8),
                  _filterChip('Demain', 'tomorrow'),
                  const SizedBox(width: 8),
                  _filterChip('Tout', 'all'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Liste des tâches
            Expanded(
              child: _tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🎤', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          Text(
                            'Aucune tâche\nAppuyez pour en ajouter',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        return TaskCard(
                          task: _tasks[index],
                          onToggle: () => _toggleTaskComplete(_tasks[index]),
                          onDelete: () => _deleteTask(_tasks[index]),
                        );
                      },
                    ),
            ),

            // Status text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _statusText,
                  key: ValueKey(_statusText),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isListening
                        ? const Color(0xFF6C63FF)
                        : Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            // Bouton vocal
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: VoiceButton(
                isListening: _isListening,
                isProcessing: _isProcessing,
                onTapDown: _startListening,
                onTapUp: _stopListening,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = value);
        _loadTasks();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white38,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
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
