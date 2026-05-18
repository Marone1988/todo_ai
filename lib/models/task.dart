class Task {
  final int? id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final String type;        // 'task', 'event', 'reminder'
  final String language;    // 'fr', 'en', 'ar'
  final String category;    // 'work', 'personal', 'other'
  final String recurrence;  // 'none', 'daily', 'weekly', 'monthly'
  final String priority;    // 'high', 'normal', 'low'
  final int reminderMinutes; // 0=at time, 15, 60, 1440
  final String? locationName;    // "Épicerie Carrefour"
  final double? locationLat;
  final double? locationLng;
  final double? locationRadius;  // meters, default 200
  final bool locationTriggered;  // prevents repeat notification

  Task({
    this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.isCompleted = false,
    this.completedAt,
    this.type = 'task',
    this.language = 'en',
    this.category = 'personal',
    this.recurrence = 'none',
    this.priority = 'normal',
    this.reminderMinutes = 0,
    this.locationName,
    this.locationLat,
    this.locationLng,
    this.locationRadius,
    this.locationTriggered = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dueDate': dueDate?.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'completedAt': completedAt?.toIso8601String(),
      'type': type,
      'language': language,
      'category': category,
      'recurrence': recurrence,
      'priority': priority,
      'reminderMinutes': reminderMinutes,
      'locationName': locationName,
      'locationLat': locationLat,
      'locationLng': locationLng,
      'locationRadius': locationRadius,
      'locationTriggered': locationTriggered ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      isCompleted: map['isCompleted'] == 1,
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'])
          : null,
      type: map['type'] ?? 'task',
      language: map['language'] ?? 'en',
      category: map['category'] ?? 'personal',
      recurrence: map['recurrence'] ?? 'none',
      priority: map['priority'] ?? 'normal',
      reminderMinutes: map['reminderMinutes'] ?? 0,
      locationName: map['locationName'],
      locationLat: map['locationLat'] != null ? (map['locationLat'] as num).toDouble() : null,
      locationLng: map['locationLng'] != null ? (map['locationLng'] as num).toDouble() : null,
      locationRadius: map['locationRadius'] != null ? (map['locationRadius'] as num).toDouble() : null,
      locationTriggered: map['locationTriggered'] == 1,
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dueDate,
    bool? isCompleted,
    DateTime? completedAt,
    String? type,
    String? language,
    String? category,
    String? recurrence,
    String? priority,
    int? reminderMinutes,
    bool clearDueDate = false,
    bool clearCompletedAt = false,
    String? locationName,
    double? locationLat,
    double? locationLng,
    double? locationRadius,
    bool? locationTriggered,
    bool clearLocation = false,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      type: type ?? this.type,
      language: language ?? this.language,
      category: category ?? this.category,
      recurrence: recurrence ?? this.recurrence,
      priority: priority ?? this.priority,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      locationName: clearLocation ? null : (locationName ?? this.locationName),
      locationLat: clearLocation ? null : (locationLat ?? this.locationLat),
      locationLng: clearLocation ? null : (locationLng ?? this.locationLng),
      locationRadius: clearLocation ? null : (locationRadius ?? this.locationRadius),
      locationTriggered: clearLocation ? false : (locationTriggered ?? this.locationTriggered),
    );
  }
}
