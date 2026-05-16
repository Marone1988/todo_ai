class Task {
  final int? id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final bool isCompleted;
  final String type; // 'task', 'event', 'reminder'
  final String language; // 'fr', 'en', 'ar'

  Task({
    this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.isCompleted = false,
    this.type = 'task',
    this.language = 'fr',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dueDate': dueDate?.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'type': type,
      'language': language,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      isCompleted: map['isCompleted'] == 1,
      type: map['type'] ?? 'task',
      language: map['language'] ?? 'fr',
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dueDate,
    bool? isCompleted,
    String? type,
    String? language,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      type: type ?? this.type,
      language: language ?? this.language,
    );
  }
}
