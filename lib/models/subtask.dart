class SubTask {
  final int? id;
  final int taskId;
  final String title;
  final bool isCompleted;

  SubTask({
    this.id,
    required this.taskId,
    required this.title,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'title': title,
        'isCompleted': isCompleted ? 1 : 0,
      };

  factory SubTask.fromMap(Map<String, dynamic> map) => SubTask(
        id: map['id'],
        taskId: map['taskId'],
        title: map['title'],
        isCompleted: map['isCompleted'] == 1,
      );

  SubTask copyWith({int? id, int? taskId, String? title, bool? isCompleted}) =>
      SubTask(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
      );
}
