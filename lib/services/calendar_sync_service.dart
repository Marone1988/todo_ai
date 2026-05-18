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
    var result = await _plugin.requestPermissions();
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
  /// Returns number of tasks created.
  Future<int> importFromCalendar(String calendarId, {int days = 7}) async {
    final now = DateTime.now();
    final end = now.add(Duration(days: days));
    final result = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: now, endDate: end),
    );
    final events = result.data ?? [];
    int count = 0;
    for (final event in events) {
      if (event.title == null || event.title!.trim().isEmpty) continue;
      final task = Task(
        title: event.title!.trim(),
        dueDate: event.start?.toLocal(),
        type: 'event',
        category: 'other',
        language: 'fr',
      );
      await DatabaseService.instance.createTask(task);
      count++;
    }
    return count;
  }

  /// Import events between [from] and [to].
  Future<int> importRangeFromCalendar(
      String calendarId, {required DateTime from, required DateTime to}) async {
    final result = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: from, endDate: to),
    );
    final events = result.data ?? [];
    int count = 0;
    for (final event in events) {
      if (event.title == null || event.title!.trim().isEmpty) continue;
      final task = Task(
        title: event.title!.trim(),
        dueDate: event.start?.toLocal(),
        type: 'event',
        category: 'other',
        language: 'fr',
      );
      await DatabaseService.instance.createTask(task);
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
