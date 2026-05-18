import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../widgets/task_card.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Task> _allTasks = [];
  DateTime? _selectedDate;
  late DateTime _weekStart;
  late DateTime _focusedMonth;
  String _viewMode = 'week';
  final Set<int> _pendingDeletes = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    _weekStart = monday;
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = null; // par défaut : toutes les tâches
    _loadTasks();
    appLang.addListener(_onLangChange);
    appThemeMode.addListener(_onLangChange);
    taskVersion.addListener(_loadTasks); // rafraîchit quand HomeScreen ajoute/supprime
  }

  @override
  void dispose() {
    appLang.removeListener(_onLangChange);
    appThemeMode.removeListener(_onLangChange);
    taskVersion.removeListener(_loadTasks);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _loadTasks() async {
    final all = await DatabaseService.instance.getAllTasks();
    setState(() => _allTasks = all);
  }

  // ── Filtrage ────────────────────────────────────────────────

  List<Task> get _displayedTasks {
    if (_selectedDate != null) return _tasksForDay(_selectedDate!);
    if (_viewMode == 'week') return _tasksForWeek();
    return _tasksForMonth();
  }

  List<Task> _tasksForDay(DateTime day) {
    return _allTasks.where((t) {
      if (t.dueDate == null) {
        final today = DateTime.now();
        final todayNorm = DateTime(today.year, today.month, today.day);
        return day == todayNorm && !t.isCompleted;
      }
      return t.dueDate!.year == day.year &&
          t.dueDate!.month == day.month &&
          t.dueDate!.day == day.day;
    }).toList();
  }

  List<Task> _tasksForWeek() {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final endOfDay =
        DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59);
    return _allTasks.where((t) {
      if (t.dueDate == null) return !t.isCompleted;
      return !t.dueDate!.isBefore(_weekStart) &&
          !t.dueDate!.isAfter(endOfDay);
    }).toList();
  }

  List<Task> _tasksForMonth() {
    final lastDay = DateTime(
        _focusedMonth.year, _focusedMonth.month + 1, 0, 23, 59, 59);
    return _allTasks.where((t) {
      if (t.dueDate == null) return !t.isCompleted;
      return !t.dueDate!.isBefore(_focusedMonth) &&
          !t.dueDate!.isAfter(lastDay);
    }).toList();
  }

  bool _hasTasksOnDay(DateTime day) => _allTasks.any((t) {
        if (t.dueDate == null) return false;
        return t.dueDate!.year == day.year &&
            t.dueDate!.month == day.month &&
            t.dueDate!.day == day.day;
      });

  void _selectDay(DateTime day) {
    setState(() {
      if (_selectedDate == day) {
        _selectedDate = null; // déselectionner = tout afficher
      } else {
        _selectedDate = day;
      }
    });
  }

  // ── Actions ─────────────────────────────────────────────────

  Future<void> _toggleTask(Task task) async {
    final isNowCompleted = !task.isCompleted;
    final updated = task.copyWith(
      isCompleted: isNowCompleted,
      completedAt: isNowCompleted ? DateTime.now() : null,
      clearCompletedAt: !isNowCompleted,
    );
    await DatabaseService.instance.updateTask(updated);

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

  void _deleteTask(Task task) {
    if (task.id == null) return;

    setState(() {
      _allTasks.removeWhere((t) => t.id == task.id);
      _pendingDeletes.add(task.id!);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: Text(t('task_deleted')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1F2937),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
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

  DateTime _nextDate(DateTime base, String recurrence) {
    switch (recurrence) {
      case 'daily':
        return base.add(const Duration(days: 1));
      case 'weekly':
        return base.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(base.year, base.month + 1, base.day,
            base.hour, base.minute);
      default:
        return base;
    }
  }

  // ── Formatage ────────────────────────────────────────────────

  String _periodLabel() {
    if (_viewMode == 'week') {
      final weekEnd = _weekStart.add(const Duration(days: 6));
      return '${_weekStart.day} – ${weekEnd.day} ${monthNames[weekEnd.month - 1]}';
    } else {
      return '${monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}';
    }
  }

  String _dayHeader() {
    if (_selectedDate == null) return _periodLabel();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    if (_selectedDate == today) return t('lbl_today');
    if (_selectedDate == tomorrow) return t('lbl_tomorrow');
    return DateFormat('EEEE d MMMM', dateLocale).format(_selectedDate!);
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tasks = _displayedTasks;

    return Container(
      color: context.bgColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('nav_agenda'),
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          _dayHeader(),
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Toggle semaine/mois + bouton All
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _viewToggle(),
                  const Spacer(),
                  // Bouton "Tout" pour déselectionner
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedDate = null),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _selectedDate == null
                            ? const Color(0xFF6366F1)
                            : context.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 6)
                        ],
                      ),
                      child: Text(
                        t('all_btn'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _selectedDate == null
                              ? Colors.white
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Calendrier
            _viewMode == 'week' ? _buildWeekStrip() : _buildMonthGrid(),
            const SizedBox(height: 12),

            // Liste des tâches
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmpty()
                  : _buildTaskList(tasks),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _viewToggle() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06), blurRadius: 6)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(t('week_view'), 'week'),
          _toggleBtn(t('month_view'), 'month'),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, String mode) {
    final isActive = _viewMode == mode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _viewMode = mode;
        _selectedDate = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  // ── Vue semaine ──────────────────────────────────────────────

  Widget _buildWeekStrip() {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final labels = dayAbbr;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navArrow(Icons.chevron_left, () => setState(() {
                    _weekStart =
                        _weekStart.subtract(const Duration(days: 7));
                    _selectedDate = null;
                  })),
              Text(
                '${_weekStart.day} – ${_weekStart.add(const Duration(days: 6)).day} ${monthNames[_weekStart.add(const Duration(days: 3)).month - 1]} ${_weekStart.add(const Duration(days: 3)).year}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
              _navArrow(Icons.chevron_right, () => setState(() {
                    _weekStart =
                        _weekStart.add(const Duration(days: 7));
                    _selectedDate = null;
                  })),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (i) {
              final day = _weekStart.add(Duration(days: i));
              final isSelected = day == _selectedDate;
              final isToday = day == today;
              final hasTasks = _hasTasksOnDay(day);
              return _dayCell(
                  day, labels[i], isSelected, isToday, hasTasks);
            }),
          ),
        ],
      ),
    );
  }

  // ── Vue mois ─────────────────────────────────────────────────

  Widget _buildMonthGrid() {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final firstDay = _focusedMonth;
    final daysInMonth =
        DateTime(firstDay.year, firstDay.month + 1, 0).day;
    final startOffset = firstDay.weekday - 1; // 0=Mon
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final labels = dayAbbr;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // Navigation mois
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navArrow(Icons.chevron_left, () => setState(() {
                    _focusedMonth = DateTime(
                        _focusedMonth.year, _focusedMonth.month - 1, 1);
                    _selectedDate = null;
                  })),
              Text(
                '${monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
              _navArrow(Icons.chevron_right, () => setState(() {
                    _focusedMonth = DateTime(
                        _focusedMonth.year, _focusedMonth.month + 1, 1);
                    _selectedDate = null;
                  })),
            ],
          ),
          const SizedBox(height: 10),
          // En-têtes jours
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: labels
                .map((l) => SizedBox(
                      width: 36,
                      child: Center(
                        child: Text(l,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9CA3AF))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          // Grille jours
          ...List.generate(rows, (row) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (col) {
                final cellIdx = row * 7 + col;
                final dayNum = cellIdx - startOffset + 1;

                DateTime day;
                bool isCurrentMonth;

                if (dayNum < 1) {
                  day = DateTime(firstDay.year, firstDay.month, dayNum);
                  isCurrentMonth = false;
                } else if (dayNum > daysInMonth) {
                  day = DateTime(firstDay.year, firstDay.month + 1,
                      dayNum - daysInMonth);
                  isCurrentMonth = false;
                } else {
                  day = DateTime(firstDay.year, firstDay.month, dayNum);
                  isCurrentMonth = true;
                }

                final isSelected = day == _selectedDate;
                final isToday = day == today;
                final hasTasks = _hasTasksOnDay(day);

                return Opacity(
                  opacity: isCurrentMonth ? 1.0 : 0.3,
                  child: _dayCell(
                      day, '${day.day}', isSelected, isToday, hasTasks,
                      isNumber: true),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: const Color(0xFF6B7280)),
      ),
    );
  }

  Widget _dayCell(DateTime day, String label, bool isSelected,
      bool isToday, bool hasTasks,
      {bool isNumber = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectDay(day),
      child: SizedBox(
        width: 36,
        child: Column(
          children: [
            if (!isNumber)
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : context.textMuted)),
            if (!isNumber) const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !isSelected
                    ? Border.all(
                        color: const Color(0xFF6366F1), width: 1.5)
                    : null,
              ),
              child: Center(
                child: Text(
                  isNumber ? label : '${day.day}',
                  style: TextStyle(
                    fontSize: isNumber ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : isToday
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF374151),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasTasks
                    ? (isSelected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF6366F1).withOpacity(0.5))
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Liste des tâches ─────────────────────────────────────────

  Widget _buildTaskList(List<Task> tasks) {
    if (_selectedDate == null) {
      // Grouper par jour
      final Map<String, List<Task>> grouped = {};
      for (final task in tasks) {
        final key = task.dueDate == null
            ? 'no_date'
            : DateFormat('yyyy-MM-dd').format(task.dueDate!);
        grouped.putIfAbsent(key, () => []).add(task);
      }
      final sortedKeys = grouped.keys.toList()
        ..sort((a, b) {
          if (a == 'no_date') return 1;
          if (b == 'no_date') return -1;
          return a.compareTo(b);
        });

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: sortedKeys.length,
        itemBuilder: (ctx, i) {
          final key = sortedKeys[i];
          final dayTasks = grouped[key]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  _formatGroupHeader(key).toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.8),
                ),
              ),
              ...dayTasks.map((task) => TaskCard(
                    task: task,
                    onToggle: () => _toggleTask(task),
                    onDelete: () => _deleteTask(task),
                    onRefresh: _loadTasks,
                  )),
            ],
          );
        },
      );
    }

    // Jour spécifique sélectionné
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: tasks
          .map((t) => TaskCard(
                task: t,
                onToggle: () => _toggleTask(t),
                onDelete: () => _deleteTask(t),
                onRefresh: _loadTasks,
              ))
          .toList(),
    );
  }

  String _formatGroupHeader(String key) {
    if (key == 'no_date') return '—';
    final date = DateTime.parse(key);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return t('lbl_today');
    if (d == tomorrow) return t('lbl_tomorrow');
    return DateFormat('EEEE d MMMM', dateLocale).format(date);
  }

  Widget _buildEmpty() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _selectedDate == today;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_outlined,
                color: Color(0xFF6366F1), size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            isToday ? t('nothing_today') : t('no_tasks_day'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            isToday ? t('tap_mic_add') : t('free_day'),
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}
