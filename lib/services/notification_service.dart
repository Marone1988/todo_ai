import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/task.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  NotificationService._init();

  // ── Canal Android ─────────────────────────────────────────────
  static const _channelId   = 'vocal_todo_channel';
  static const _channelName = 'Vocal Todo — Rappels';
  static const _channelDesc = 'Rappels de tâches programmés';

  // ── Initialisation ────────────────────────────────────────────

  Future<void> initialize() async {
    // 1. Charger les données timezone et positionner sur la timezone locale
    tz.initializeTimeZones();
    final String localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));

    // 2. Paramètres d'init Android/iOS
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (_) {},
    );

    // 3. Demander les permissions (Android 13+ = POST_NOTIFICATIONS)
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // POST_NOTIFICATIONS (API 33+)
      await android.requestNotificationsPermission();
      // SCHEDULE_EXACT_ALARM (API 31+)
      await android.requestExactAlarmsPermission();
    }
  }

  // ── Planification ─────────────────────────────────────────────

  Future<void> scheduleTaskNotification(Task task) async {
    if (task.dueDate == null || task.id == null) return;

    // Calculer l'heure de la notification (reminderMinutes avant l'échéance)
    final notifTime = task.dueDate!.subtract(
      Duration(minutes: task.reminderMinutes),
    );

    // Convertir en TZDateTime local (timezone du téléphone)
    final scheduled = tz.TZDateTime.from(notifTime, tz.local);

    // Ne pas planifier dans le passé
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    // Titre
    final priorityIcon =
        task.priority == 'high' ? '🔴 ' : task.priority == 'low' ? '⬇️ ' : '';
    final recIcon = task.recurrence != 'none' ? ' 🔁' : '';
    final title   = '$priorityIcon${task.title}$recIcon';

    // Corps du message selon le délai
    final body = _buildBody(task.reminderMinutes);

    await _plugin.zonedSchedule(
      task.id!,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          // Afficher même si l'app est en premier plan
          fullScreenIntent: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  String _buildBody(int minutes) {
    if (minutes == 0)    return "C'est l'heure !";
    if (minutes < 60)    return 'Dans $minutes minutes';
    if (minutes < 1440)  return 'Dans ${minutes ~/ 60}h';
    if (minutes < 2880)  return 'Demain';
    return 'Dans ${minutes ~/ 1440} jours';
  }

  // ── Annulation ────────────────────────────────────────────────

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  // ── Debug : liste des notifs planifiées ──────────────────────

  Future<List<PendingNotificationRequest>> pendingNotifications() async {
    return _plugin.pendingNotificationRequests();
  }
}
