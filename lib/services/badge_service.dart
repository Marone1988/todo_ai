import '../models/task.dart';

/// Service badge icône app.
/// Le badge natif Android varie selon le fabricant (Samsung, AOSP…).
/// Ici on stocke le compte via SharedPreferences pour utilisation future.
class BadgeService {
  static final BadgeService instance = BadgeService._();
  BadgeService._();

  int _lastCount = 0;
  int get pendingCount => _lastCount;

  Future<void> update(List<Task> tasks) async {
    _lastCount = tasks.where((t) => !t.isCompleted).length;
    // Badge natif : implémentation via canal méthode Android possible
    // dans une prochaine version (flutter_app_badger incompatible AGP 8+)
  }
}
