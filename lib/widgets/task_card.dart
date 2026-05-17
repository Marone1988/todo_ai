import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  Color get _categoryColor {
    switch (task.category.toLowerCase()) {
      case 'work':
        return const Color(0xFF6366F1);
      case 'personal':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF10B981);
    }
  }

  Color get _categoryBg {
    switch (task.category.toLowerCase()) {
      case 'work':
        return const Color(0xFFEEF0FF);
      case 'personal':
        return const Color(0xFFFFE4E8);
      default:
        return const Color(0xFFE6FAF5);
    }
  }

  String get _categoryLabel {
    switch (task.category.toLowerCase()) {
      case 'work':
        return 'Work';
      case 'personal':
        return 'Personal';
      default:
        return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(task.id.toString()),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Checkbox circle
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: task.isCompleted
                        ? const Color(0xFF6366F1)
                        : Colors.transparent,
                    border: Border.all(
                      color: task.isCompleted
                          ? const Color(0xFF6366F1)
                          : _categoryColor,
                      width: 2,
                    ),
                  ),
                  child: task.isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ),

              const SizedBox(width: 14),

              // Contenu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: task.isCompleted
                            ? const Color(0xFFADB5BD)
                            : const Color(0xFF111827),
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    if (task.dueDate != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(task.dueDate!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.access_time_outlined,
                            size: 12,
                            color: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('h:mm a').format(task.dueDate!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Tag catégorie
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _categoryBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _categoryLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _categoryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final taskDay = DateTime(date.year, date.month, date.day);

    if (taskDay == today) return 'Today';
    if (taskDay == tomorrow) return 'Tomorrow';
    return DateFormat('MMM d').format(date);
  }
}
