import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'calendar_sync_service.dart';

const _kGeofenceTask = 'geofence_check';

/// Top-level callback required by workmanager (must be @pragma annotated)
@pragma('vm:entry-point')
void workmanagerDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName == _kGeofenceTask) {
      WidgetsFlutterBinding.ensureInitialized();
      await LocationService.checkAllGeofences();
    } else if (taskName == 'monthly_calendar_sync') {
      WidgetsFlutterBinding.ensureInitialized();
      await LocationService.doMonthlyCalendarSync();
    }
    return true;
  });
}

class LocationService {
  LocationService._();

  // ── Initialisation ────────────────────────────────────────────

  static Future<void> initialize() async {
    await Workmanager().initialize(workmanagerDispatcher, isInDebugMode: false);
  }

  static Future<void> startMonitoring() async {
    await Workmanager().registerPeriodicTask(
      _kGeofenceTask,
      _kGeofenceTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.not_required),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  static Future<void> stopMonitoring() async {
    await Workmanager().cancelByUniqueName(_kGeofenceTask);
  }

  static const _kCalendarSyncTask = 'monthly_calendar_sync';

  /// Register daily task that checks if it's the 1st of the month.
  static Future<void> registerMonthlyCalendarSync() async {
    await Workmanager().registerPeriodicTask(
      _kCalendarSyncTask,
      _kCalendarSyncTask,
      frequency: const Duration(hours: 24),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }

  static Future<void> doMonthlyCalendarSync() async {
    final now = DateTime.now();
    if (now.day != 1) return; // Only run on 1st of month

    final prefs = await SharedPreferences.getInstance();
    final calId = prefs.getString('selected_calendar_id');
    if (calId == null || calId.isEmpty) return;

    final start = DateTime(now.year, now.month, 1);
    final end   = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    await CalendarSyncService.instance.importRangeFromCalendar(calId, from: start, to: end);
  }

  // ── Permission & position ─────────────────────────────────────

  static Future<bool> requestPermission() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  static Future<Position?> currentPosition() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Geocoding via OpenStreetMap Nominatim (no API key) ────────

  /// Address string → (lat, lng, displayName)
  static Future<({double lat, double lng, String name})?> geocodeAddress(
      String address) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(address)}&format=json&limit=1');
      final res = await http.get(uri,
          headers: {'User-Agent': 'VocalTodoApp/1.0'});
      if (res.statusCode != 200) return null;
      final list = json.decode(res.body) as List;
      if (list.isEmpty) return null;
      final item = list.first as Map<String, dynamic>;
      return (
        lat: double.parse(item['lat'] as String),
        lng: double.parse(item['lon'] as String),
        name: (item['display_name'] as String).split(',').first.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Coordinates → readable place name (city + road when available)
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=$lat&lon=$lng&format=json&addressdetails=1&zoom=16');
      final res = await http.get(uri,
          headers: {'User-Agent': 'VocalTodoApp/1.0'});
      if (res.statusCode != 200) return null;
      final map = json.decode(res.body) as Map<String, dynamic>;
      final addr = map['address'] as Map<String, dynamic>?;
      if (addr == null) return (map['display_name'] as String?)?.split(',').first;

      // Construire un nom lisible : rue + ville
      final road   = addr['road'] as String?;
      final city   = addr['city'] as String?
                  ?? addr['town'] as String?
                  ?? addr['village'] as String?
                  ?? addr['county'] as String?
                  ?? addr['state'] as String?;

      if (road != null && city != null) return '$road, $city';
      if (city != null) return city;
      if (road != null) return road;
      // dernier recours : premier segment du display_name
      return (map['display_name'] as String?)?.split(',').first;
    } catch (_) {
      return null;
    }
  }

  // ── Geofence check (called by workmanager) ────────────────────

  static Future<void> checkAllGeofences() async {
    final pos = await currentPosition();
    if (pos == null) return;

    final tasks = await DatabaseService.instance.getAllTasks();
    final targets = tasks.where((t) =>
        !t.isCompleted &&
        !t.locationTriggered &&
        t.locationLat != null &&
        t.locationLng != null);

    final flnp = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await flnp.initialize(initSettings);

    for (final task in targets) {
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        task.locationLat!, task.locationLng!,
      );
      final radius = task.locationRadius ?? 200.0;
      if (dist <= radius) {
        await flnp.show(
          (task.id! + 20000) % 2147483647,
          '📍 ${task.locationName ?? 'Rappel de lieu'}',
          task.title,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'location_reminders',
              'Rappels de lieu',
              channelDescription: 'Notifications déclenchées par votre position',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
        await DatabaseService.instance
            .updateTask(task.copyWith(locationTriggered: true));
      }
    }
  }
}
