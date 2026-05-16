import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';

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
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        dueDate TEXT,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'task',
        language TEXT NOT NULL DEFAULT 'fr'
      )
    ''');
  }

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

  Future<List<Task>> getTasksForToday() async {
    final db = await instance.database;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).toIso8601String();
    final end = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'tasks',
      where: 'dueDate BETWEEN ? AND ?',
      whereArgs: [start, end],
    );
    return result.map((map) => Task.fromMap(map)).toList();
  }

  Future<List<Task>> getTasksForTomorrow() async {
    final db = await instance.database;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day).toIso8601String();
    final end = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'tasks',
      where: 'dueDate BETWEEN ? AND ?',
      whereArgs: [start, end],
    );
    return result.map((map) => Task.fromMap(map)).toList();
  }

  Future<int> updateTask(Task task) async {
    final db = await instance.database;
    return db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await instance.database;
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
