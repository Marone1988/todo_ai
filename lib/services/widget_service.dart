import 'package:home_widget/home_widget.dart';
import '../models/task.dart';

class WidgetService {
  static const String _appGroupId = 'com.example.todo_ai';
  static const String _widgetName = 'TodoWidgetProvider';

  /// Met à jour le widget écran d'accueil avec les tâches du jour
  static Future<void> update(List<Task> allTasks) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Tâches du jour (non complétées)
      final todayPending = allTasks.where((t) {
        if (t.isCompleted) return false;
        if (t.dueDate == null) return true;
        return t.dueDate!.year == today.year &&
            t.dueDate!.month == today.month &&
            t.dueDate!.day == today.day;
      }).toList();

      // Envoyer le nombre de tâches
      await HomeWidget.saveWidgetData<String>(
          'task_count', '${todayPending.length}');

      // Envoyer les 4 premières tâches
      for (int i = 0; i < 4; i++) {
        final title =
            i < todayPending.length ? todayPending[i].title : '';
        final priority =
            i < todayPending.length ? todayPending[i].priority : 'normal';
        await HomeWidget.saveWidgetData<String>('task_$i', title);
        await HomeWidget.saveWidgetData<String>('priority_$i', priority);
      }

      // Déclencher la mise à jour du widget
      await HomeWidget.updateWidget(
        androidName: _widgetName,
        qualifiedAndroidName: '$_appGroupId.$_widgetName',
      );
    } catch (_) {
      // Le widget peut ne pas être installé — ignorer silencieusement
    }
  }
}
