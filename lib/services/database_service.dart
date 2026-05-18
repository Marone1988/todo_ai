import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';
import '../models/subtask.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vocal_todo.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        dueDate TEXT,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        completedAt TEXT,
        type TEXT NOT NULL DEFAULT 'task',
        language TEXT NOT NULL DEFAULT 'en',
        category TEXT NOT NULL DEFAULT 'personal',
        recurrence TEXT NOT NULL DEFAULT 'none',
        priority TEXT NOT NULL DEFAULT 'normal',
        reminderMinutes INTEGER NOT NULL DEFAULT 0,
        locationName TEXT,
        locationLat REAL,
        locationLng REAL,
        locationRadius REAL,
        locationTriggered INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE subtasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taskId INTEGER NOT NULL,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (taskId) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none'");
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'");
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN reminderMinutes INTEGER NOT NULL DEFAULT 0");
    }
    if (oldVersion < 4) {
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN completedAt TEXT");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subtasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          taskId INTEGER NOT NULL,
          title TEXT NOT NULL,
          isCompleted INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (taskId) REFERENCES tasks (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN locationName TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationLat REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationLng REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationRadius REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationTriggered INTEGER NOT NULL DEFAULT 0');
    }
  }

  // ── Tasks CRUD ────────────────────────────────────────────────

  Future<Task> createTask(Task task) async {
    final db = await instance.database;
    final id = await db.insert('tasks', task.toMap());
    return task.copyWith(id: id);
  }

  Future<List<Task>> getAllTasks() async {
    final db = await instance.database;
    final result = await db.query('tasks', orderBy: 'dueDate ASC');
    return result.map((map) => Task.fromMap(map)).toList();
  }

  Future<int> updateTask(Task task) async {
    final db = await instance.database;
    return db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await instance.database;
    await db.delete('subtasks', where: 'taskId = ?', whereArgs: [id]);
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ── Subtasks CRUD ─────────────────────────────────────────────

  Future<SubTask> createSubTask(SubTask sub) async {
    final db = await instance.database;
    final id = await db.insert('subtasks', sub.toMap());
    return sub.copyWith(id: id);
  }

  Future<List<SubTask>> getSubTasks(int taskId) async {
    final db = await instance.database;
    final result = await db
        .query('subtasks', where: 'taskId = ?', whereArgs: [taskId]);
    return result.map((m) => SubTask.fromMap(m)).toList();
  }

  Future<int> updateSubTask(SubTask sub) async {
    final db = await instance.database;
    return db.update('subtasks', sub.toMap(),
        where: 'id = ?', whereArgs: [sub.id]);
  }

  Future<int> deleteSubTask(int id) async {
    final db = await instance.database;
    return db.delete('subtasks', where: 'id = ?', whereArgs: [id]);
  }

  // ── Stats ─────────────────────────────────────────────────────

  /// Nombre de tâches complétées par jour pour les 7 derniers jours
  /// Retourne une Map<String(date yyyy-MM-dd), int>
  Future<Map<String, int>> completedPerDay(int days) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT date(completedAt) as day, COUNT(*) as cnt
      FROM tasks
      WHERE isCompleted = 1
        AND completedAt IS NOT NULL
        AND completedAt >= date('now', '-$days days')
      GROUP BY day
      ORDER BY day ASC
    ''');
    final map = <String, int>{};
    for (final row in result) {
      map[row['day'] as String] = (row['cnt'] as int? ?? 0);
    }
    return map;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
