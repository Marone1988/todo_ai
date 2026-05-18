import 'dart:collection';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/task.dart';
import 'database_service.dart';

class CalendarSyncService {
  CalendarSyncService._();
  static final CalendarSyncService instance = CalendarSyncService._();

  final _plugin = DeviceCalendarPlugin();

  // ── Permissions ──────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    // Demande via le plugin device_calendar (gère READ + WRITE)
    final result = await _plugin.requestPermissions();
    return result.data == true;
  }

  Future<bool> hasPermissions() async {
    final result = await _plugin.hasPermissions();
    return result.data == true;
  }

  // ── Calendars list ───────────────────────────────────────────

  Future<List<Calendar>> getCalendars() async {
    final result = await _plugin.retrieveCalendars();
    return (result.data ?? []).cast<Calendar>();
  }

  // ── Import: Calendar events → Tasks ─────────────────────────

  /// Import events from the given calendar for the next [days] days.
  /// Returns number of tasks created (skips duplicates).
  Future<int> importFromCalendar(String calendarId, {int days = 30}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1); // début du mois courant
    final end = now.add(Duration(days: days));
    return _importEvents(calendarId, from: start, to: end);
  }

  /// Import events between [from] and [to] (skips duplicates).
  Future<int> importRangeFromCalendar(
      String calendarId, {required DateTime from, required DateTime to}) async {
    return _importEvents(calendarId, from: from, to: to);
  }

  /// Internal import: retrieves events and skips already-imported ones.
  Future<int> _importEvents(String calendarId,
      {required DateTime from, required DateTime to}) async {
    // Ensure permissions
    final hasPerm = await hasPermissions();
    if (!hasPerm) {
      final granted = await requestPermissions();
      if (!granted) return -1; // -1 = permission refusée
    }

    Result<UnmodifiableListView<Event>?>? result;
    try {
      result = await _plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: from, endDate: to),
      );
    } catch (_) {
      return -2; // -2 = erreur réseau/plugin
    }

    if (result == null || !result.isSuccess || result.data == null) return 0;

    // Load existing tasks once to check duplicates
    final existing = await DatabaseService.instance.getAllTasks();

    int count = 0;
    for (final event in result.data!) {
      final title = event.title?.trim();
      if (title == null || title.isEmpty) continue;

      final eventDate = event.start?.toLocal();

      // Skip duplicate: same title AND same day already imported
      final isDup = existing.any((t) =>
          t.title == title &&
          t.dueDate != null &&
          eventDate != null &&
          t.dueDate!.year  == eventDate.year &&
          t.dueDate!.month == eventDate.month &&
          t.dueDate!.day   == eventDate.day);
      if (isDup) continue;

      final task = Task(
        title: title,
        dueDate: eventDate,
        type: 'event',
        category: 'other',
        language: 'fr',
      );
      final saved = await DatabaseService.instance.createTask(task);
      existing.add(saved); // prevent dupes within the same batch
      count++;
    }
    return count;
  }

  // ── Export: Task → Calendar event ───────────────────────────

  Future<bool> exportTaskToCalendar(Task task, String calendarId) async {
    if (task.dueDate == null) return false;
    final event = Event(
      calendarId,
      title: task.title,
      description: task.description ?? '',
      start: TZDateTime.from(task.dueDate!, tz.local),
      end: TZDateTime.from(
          task.dueDate!.add(const Duration(hours: 1)), tz.local),
    );
    final result = await _plugin.createOrUpdateEvent(event);
    return result?.data != null;
  }

  /// Export all incomplete tasks that have a dueDate
  Future<int> exportAllToCalendar(String calendarId) async {
    final tasks = await DatabaseService.instance.getAllTasks();
    int count = 0;
    for (final task in tasks) {
      if (task.isCompleted || task.dueDate == null) continue;
      final ok = await exportTaskToCalendar(task, calendarId);
      if (ok) count++;
    }
    return count;
  }
}
