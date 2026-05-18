import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/subtask.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../screens/map_picker_screen.dart';

class TaskCard extends StatefulWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onRefresh;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDelete,
    this.onRefresh,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _expanded = false;
  List<SubTask> _subtasks = [];

  @override
  void initState() {
    super.initState();
    _loadSubtasks();
  }

  @override
  void didUpdateWidget(TaskCard old) {
    super.didUpdateWidget(old);
    if (old.task.id != widget.task.id) _loadSubtasks();
  }

  Future<void> _loadSubtasks() async {
    if (widget.task.id == null) return;
    final list = await DatabaseService.instance.getSubTasks(widget.task.id!);
    if (mounted) setState(() => _subtasks = list);
  }

  Future<void> _toggleSubtask(SubTask sub) async {
    haptic();
    final updated = sub.copyWith(isCompleted: !sub.isCompleted);
    await DatabaseService.instance.updateSubTask(updated);
    final idx = _subtasks.indexWhere((s) => s.id == sub.id);
    if (idx != -1) {
      setState(() => _subtasks[idx] = updated);
    }
    // Auto-complete parent when all subtasks are done
    if (!widget.task.isCompleted && _subtasks.every((s) => s.isCompleted)) {
      widget.onToggle();
    }
  }

  void _onCardTap() {
    if (_subtasks.isNotEmpty) {
      haptic();
      setState(() => _expanded = !_expanded);
    } else {
      widget.onToggle();
    }
  }

  // ── Priority color ─────────────────────────────────────────────
  Color get _priorityColor {
    switch (widget.task.priority) {
      case 'high': return const Color(0xFFEF4444);
      case 'low':  return const Color(0xFFD1D5DB);
      default:     return Colors.transparent;
    }
  }

  Widget _countdownWidget(BuildContext context) {
    if (widget.task.dueDate == null) return const SizedBox.shrink();
    final diff = widget.task.dueDate!.difference(DateTime.now());
    Color color;
    Color bg;
    String label;
    if (diff.isNegative) {
      label = t('lbl_late');
      color = const Color(0xFFEF4444);
      bg = const Color(0xFFEF4444).withOpacity(0.15);
    } else if (diff.inMinutes < 60) {
      label = '${diff.inMinutes}m';
      color = const Color(0xFFF59E0B);
      bg = const Color(0xFFF59E0B).withOpacity(0.15);
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      label = '${h}h${m > 0 ? '${m}m' : ''}';
      color = context.textMuted;
      bg = context.cardColor2;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  String _catLabel(BuildContext context) {
    switch (widget.task.category) {
      case 'work':     return t('cat_work');
      case 'personal': return t('cat_personal');
      default:         return t('cat_other');
    }
  }

  // ── Edit sheet ──────────────────────────────────────────────────
  void _showEditSheet(BuildContext context) {
    final titleCtrl = TextEditingController(text: widget.task.title);
    String selCat      = widget.task.category;
    DateTime? selDate  = widget.task.dueDate;
    String selRec      = widget.task.recurrence;
    String selPriority = widget.task.priority;
    int selReminder    = widget.task.reminderMinutes;
    List<SubTask> subtasks = List.from(_subtasks);
    final subCtrl = TextEditingController();
    String? selLocationName = widget.task.locationName;
    double? selLocationLat  = widget.task.locationLat;
    double? selLocationLng  = widget.task.locationLng;
    final locationCtrl = TextEditingController(text: widget.task.locationName ?? '');
    bool _geocoding = false;
    bool _pastDateError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: context.dividerColor,
                          borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Text(t('edit_task'), style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        color: context.textPrimary)),
                    const SizedBox(height: 20),

                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        labelText: t('field_title'),
                        labelStyle: TextStyle(color: context.textMuted),
                        filled: true,
                        fillColor: context.inputFill,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF6366F1), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _label(t('field_category'), context),
                    const SizedBox(height: 8),
                    _dropdownField<String>(
                      value: selCat,
                      items: const [
                        DropdownMenuItem(value: 'work',     child: Text('Travail')),
                        DropdownMenuItem(value: 'personal', child: Text('Personnel')),
                        DropdownMenuItem(value: 'other',    child: Text('Autre')),
                      ],
                      onChanged: (v) { if (v != null) setModal(() => selCat = v); },
                      context: context,
                    ),
                    const SizedBox(height: 16),

                    _label(t('priority'), context),
                    const SizedBox(height: 8),
                    _dropdownField<String>(
                      value: selPriority,
                      items: [
                        DropdownMenuItem(
                          value: 'high',
                          child: Row(children: [
                            Container(width: 10, height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            const Text('Haute'),
                          ]),
                        ),
                        DropdownMenuItem(
                          value: 'normal',
                          child: Row(children: [
                            Container(width: 10, height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            const Text('Normale'),
                          ]),
                        ),
                        DropdownMenuItem(
                          value: 'low',
                          child: Row(children: [
                            Container(width: 10, height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFF9CA3AF), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            const Text('Basse'),
                          ]),
                        ),
                      ],
                      onChanged: (v) { if (v != null) setModal(() => selPriority = v); },
                      context: context,
                    ),
                    const SizedBox(height: 16),

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
                            child: child!,
                          ),
                        );
                        if (date != null && ctx.mounted) {
                          final time = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(selDate ?? DateTime.now()),
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: Color(0xFF6366F1))),
                              child: child!,
                            ),
                          );
                          if (time != null) {
                            setModal(() => selDate = DateTime(
                                date.year, date.month, date.day, time.hour, time.minute));
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
                                ? const Color(0xFF6366F1).withOpacity(0.3)
                                : Colors.transparent),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today_outlined, size: 18,
                              color: selDate != null
                                  ? const Color(0xFF6366F1) : context.textMuted),
                          const SizedBox(width: 10),
                          Text(
                            selDate != null
                                ? DateFormat('EEE d MMM • HH:mm').format(selDate!)
                                : t('add_date'),
                            style: TextStyle(fontSize: 14,
                                color: selDate != null
                                    ? const Color(0xFF6366F1) : context.textMuted,
                                fontWeight: selDate != null
                                    ? FontWeight.w600 : FontWeight.normal),
                          ),
                          const Spacer(),
                          if (selDate != null)
                            GestureDetector(
                              onTap: () => setModal(() => selDate = null),
                              child: Icon(Icons.close, size: 16, color: context.textMuted),
                            ),
                        ]),
                      ),
                    ),
                    // Erreur date passée
                    if (_pastDateError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: const [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444), size: 14),
                          SizedBox(width: 6),
                          Text('Date déjà passée — choisissez une date future',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFFEF4444))),
                        ]),
                      ),
                    const SizedBox(height: 16),

                    _label(t('reminder'), context),
                    const SizedBox(height: 8),
                    _dropdownField<int>(
                      value: selReminder,
                      items: const [
                        DropdownMenuItem(value: 0,    child: Text('À l\'heure')),
                        DropdownMenuItem(value: 15,   child: Text('15 min avant')),
                        DropdownMenuItem(value: 60,   child: Text('1 heure avant')),
                        DropdownMenuItem(value: 1440, child: Text('1 jour avant')),
                      ],
                      onChanged: (v) { if (v != null) setModal(() => selReminder = v); },
                      context: context,
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 16),
                    _label('📍 Rappel de lieu', context),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: locationCtrl,
                          style: TextStyle(color: context.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Adresse ou lieu…',
                            hintStyle: TextStyle(color: context.textMuted, fontSize: 13),
                            filled: true,
                            fillColor: context.inputFill,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            prefixIcon: Icon(Icons.location_on_outlined, size: 16, color: context.textMuted),
                            suffixIcon: selLocationLat != null
                                ? GestureDetector(
                                    onTap: () => setModal(() {
                                      selLocationName = null; selLocationLat = null;
                                      selLocationLng = null; locationCtrl.clear();
                                    }),
                                    child: Icon(Icons.close, size: 14, color: context.textMuted))
                                : null,
                          ),
                          onSubmitted: (v) async {
                            if (v.trim().isEmpty) return;
                            setModal(() => _geocoding = true);
                            final result = await LocationService.geocodeAddress(v.trim());
                            setModal(() {
                              _geocoding = false;
                              if (result != null) {
                                selLocationName = result.name;
                                selLocationLat = result.lat;
                                selLocationLng = result.lng;
                                locationCtrl.text = result.name;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          setModal(() => _geocoding = true);
                          final granted = await LocationService.requestPermission();
                          if (!granted) { setModal(() => _geocoding = false); return; }
                          final pos = await LocationService.currentPosition();
                          if (pos == null) { setModal(() => _geocoding = false); return; }
                          final name = await LocationService.reverseGeocode(pos.latitude, pos.longitude);
                          setModal(() {
                            _geocoding = false;
                            selLocationLat = pos.latitude;
                            selLocationLng = pos.longitude;
                            selLocationName = name ?? 'Ma position';
                            locationCtrl.text = selLocationName!;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: _geocoding
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
                              : const Icon(Icons.my_location, color: Color(0xFF6366F1), size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.of(context).push<dynamic>(
                            MaterialPageRoute(
                              builder: (_) => MapPickerScreen(
                                initialLat: selLocationLat,
                                initialLng: selLocationLng,
                              ),
                            ),
                          );
                          if (result != null) {
                            setModal(() {
                              selLocationLat  = result.lat as double;
                              selLocationLng  = result.lng as double;
                              selLocationName = result.name as String;
                              locationCtrl.text = selLocationName!;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2E),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.map_outlined,
                              color: Colors.white70, size: 18),
                        ),
                      ),
                    ]),
                    if (selLocationLat != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.check_circle, size: 13, color: Color(0xFF6366F1)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Rayon 200m · $selLocationName',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                          ),
                        ),
                      ]),
                    ],

                    _label(t('recurrence'), context),
                    const SizedBox(height: 8),
                    _dropdownField<String>(
                      value: selRec,
                      items: const [
                        DropdownMenuItem(value: 'none',    child: Text('Jamais')),
                        DropdownMenuItem(value: 'daily',   child: Text('Chaque jour')),
                        DropdownMenuItem(value: 'weekly',  child: Text('Chaque semaine')),
                        DropdownMenuItem(value: 'monthly', child: Text('Chaque mois')),
                      ],
                      onChanged: (v) { if (v != null) setModal(() => selRec = v); },
                      context: context,
                    ),
                    const SizedBox(height: 16),

                    _label(t('subtasks'), context),
                    const SizedBox(height: 8),
                    ...subtasks.map((sub) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        GestureDetector(
                          onTap: () async {
                            final updated = sub.copyWith(isCompleted: !sub.isCompleted);
                            await DatabaseService.instance.updateSubTask(updated);
                            final idx = subtasks.indexWhere((s) => s.id == sub.id);
                            if (idx != -1) setModal(() => subtasks[idx] = updated);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sub.isCompleted
                                  ? const Color(0xFF6366F1) : Colors.transparent,
                              border: Border.all(
                                color: sub.isCompleted
                                    ? const Color(0xFF6366F1) : context.textMuted,
                                width: 1.5)),
                            child: sub.isCompleted
                                ? const Icon(Icons.check, size: 11, color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(sub.title,
                            style: TextStyle(
                                fontSize: 13,
                                color: sub.isCompleted
                                    ? context.textMuted : context.textPrimary,
                                decoration: sub.isCompleted
                                    ? TextDecoration.lineThrough : null))),
                        GestureDetector(
                          onTap: () async {
                            if (sub.id != null) {
                              await DatabaseService.instance.deleteSubTask(sub.id!);
                              setModal(() => subtasks.removeWhere((s) => s.id == sub.id));
                            }
                          },
                          child: Icon(Icons.close, size: 14, color: context.textMuted),
                        ),
                      ]),
                    )),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: subCtrl,
                          style: TextStyle(fontSize: 13, color: context.textPrimary),
                          decoration: InputDecoration(
                            hintText: t('add_subtask'),
                            hintStyle: TextStyle(fontSize: 13, color: context.textMuted),
                            filled: true,
                            fillColor: context.inputFill,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none),
                          ),
                          onSubmitted: (v) async {
                            if (v.trim().isEmpty) return;
                            final sub = SubTask(taskId: widget.task.id ?? 0, title: v.trim());
                            final saved = await DatabaseService.instance.createSubTask(sub);
                            setModal(() { subtasks.add(saved); subCtrl.clear(); });
                            _loadSubtasks();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          final v = subCtrl.text.trim();
                          if (v.isEmpty) return;
                          final sub = SubTask(taskId: widget.task.id ?? 0, title: v);
                          final saved = await DatabaseService.instance.createSubTask(sub);
                          setModal(() { subtasks.add(saved); subCtrl.clear(); });
                          _loadSubtasks();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.add, color: Colors.white, size: 18),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),

                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                                color: context.cardColor2,
                                borderRadius: BorderRadius.circular(14)),
                            child: Center(child: Text(t('cancel'),
                                style: TextStyle(fontWeight: FontWeight.w600,
                                    color: context.textSecondary))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(flex: 2,
                        child: GestureDetector(
                          onTap: () async {
                            // Vérifier que la date n'est pas dans le passé
                            if (selDate != null &&
                                selDate!.isBefore(DateTime.now())) {
                              setModal(() => _pastDateError = true);
                              return;
                            }
                            setModal(() => _pastDateError = false);
                            final updated = widget.task.copyWith(
                              title: titleCtrl.text.trim(),
                              category: selCat,
                              dueDate: selDate,
                              recurrence: selRec,
                              priority: selPriority,
                              reminderMinutes: selReminder,
                              clearDueDate: selDate == null,
                              locationName: selLocationName,
                              locationLat: selLocationLat,
                              locationLng: selLocationLng,
                              locationRadius: 200.0,
                              locationTriggered: selLocationLat == null,
                            );
                            await DatabaseService.instance.updateTask(updated);
                            if (updated.id != null) {
                              await NotificationService.instance
                                  .cancelNotification(updated.id!);
                              await NotificationService.instance
                                  .scheduleTaskNotification(updated);
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              widget.onRefresh?.call();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                                color: const Color(0xFF6366F1),
                                borderRadius: BorderRadius.circular(14)),
                            child: Center(child: Text(t('save'),
                                style: const TextStyle(fontWeight: FontWeight.w700,
                                    color: Colors.white, fontSize: 15))),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _label(String text, BuildContext ctx) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: ctx.textSecondary));

  /// Styled dropdown — matches the filled input look of the edit sheet.
  Widget _dropdownField<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required BuildContext context,
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
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: context.textMuted, size: 20),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }

  // ── Main build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doneCount = _subtasks.where((s) => s.isCompleted).length;
    final hasSubtasks = _subtasks.isNotEmpty;

    return Dismissible(
      key: Key('task_${widget.task.id}'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.endToStart) return true;
        _showEditSheet(context);
        return false;
      },
      onDismissed: (dir) {
        if (dir == DismissDirection.endToStart) widget.onDelete();
      },
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.edit_outlined, color: Color(0xFF6366F1)),
      ),
      child: GestureDetector(
        onTap: _onCardTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: context.cardColor,
              ),
              child: IntrinsicHeight(
                child: Row(children: [
                  // Priority bar — no borderRadius needed, ClipRRect clips it
                  Container(
                    width: 4,
                    color: _priorityColor,
                  ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main row: checkbox + title + badge
                      Row(children: [
                        // Checkbox — direct toggle even with subtasks
                        GestureDetector(
                          onTap: widget.onToggle,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.task.isCompleted
                                  ? const Color(0xFF6366F1) : Colors.transparent,
                              border: Border.all(
                                color: widget.task.isCompleted
                                    ? const Color(0xFF6366F1)
                                    : Colors.white,
                                width: 1.5)),
                            child: widget.task.isCompleted
                                ? const Icon(Icons.check, color: Colors.white, size: 13)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Title + meta
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(widget.task.title,
                                    style: TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.w600,
                                        color: widget.task.isCompleted
                                            ? context.textMuted : context.textPrimary,
                                        decoration: widget.task.isCompleted
                                            ? TextDecoration.lineThrough : null,
                                        decorationColor: context.textMuted))),
                                if (widget.task.recurrence != 'none')
                                  Padding(padding: const EdgeInsets.only(left: 4),
                                      child: Icon(Icons.repeat, size: 13,
                                          color: context.primaryLight)),
                              ]),
                              if (widget.task.dueDate != null) ...[
                                const SizedBox(height: 4),
                                Builder(builder: (context) {
                                  final dateLabel = _formatDate(widget.task.dueDate!);
                                  return Row(children: [
                                    Icon(Icons.access_time_outlined,
                                        size: 11, color: context.textMuted),
                                    const SizedBox(width: 4),
                                    if (dateLabel.isNotEmpty) ...[
                                      Text(dateLabel,
                                          style: TextStyle(fontSize: 11, color: context.textMuted)),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(DateFormat('HH:mm').format(widget.task.dueDate!),
                                        style: TextStyle(fontSize: 11, color: context.textMuted)),
                                    if (widget.task.reminderMinutes > 0) ...[
                                      const SizedBox(width: 6),
                                      Icon(Icons.notifications_outlined,
                                          size: 11,
                                          color: context.primaryLight.withOpacity(0.7)),
                                    ],
                                  ]);
                                }),
                              ],
                              // Subtask progress bar
                              if (hasSubtasks) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: doneCount / _subtasks.length,
                                        minHeight: 4,
                                        backgroundColor: context.dividerColor,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            context.primaryLight.withOpacity(0.7)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('$doneCount/${_subtasks.length}',
                                      style: TextStyle(fontSize: 10,
                                          color: context.textMuted,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    size: 14, color: context.textMuted,
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _countdownWidget(context),
                        const SizedBox(width: 4),
                        if (widget.task.locationLat != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.location_on, size: 11, color: Color(0xFF6366F1)),
                          ),
                          const SizedBox(width: 4),
                        ],
                        // Category badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.catBg(widget.task.category),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(_catLabel(context),
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.catColor(widget.task.category))),
                        ),
                      ]),

                      // ── Expanded subtask list ──────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        child: _expanded && hasSubtasks
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  Divider(height: 1, thickness: 0.5, color: context.dividerColor),
                                  const SizedBox(height: 10),
                                  ..._subtasks.map((sub) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: GestureDetector(
                                      onTap: () => _toggleSubtask(sub),
                                      child: Row(children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          width: 20, height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: sub.isCompleted
                                                ? const Color(0xFF48484A) : Colors.transparent,
                                            border: Border.all(
                                              color: sub.isCompleted
                                                  ? const Color(0xFF48484A) : Colors.white,
                                              width: 1.5)),
                                          child: sub.isCompleted
                                              ? const Icon(Icons.check, size: 10, color: Colors.white)
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(sub.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: sub.isCompleted
                                                ? context.textMuted : context.textPrimary,
                                            decoration: sub.isCompleted
                                                ? TextDecoration.lineThrough : null,
                                            decorationColor: context.textMuted,
                                          ),
                                        )),
                                      ]),
                                    ),
                                  )),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '';
    if (d == tomorrow) return t('lbl_tomorrow');
    return DateFormat('MMM d').format(date);
  }
}
