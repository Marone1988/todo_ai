import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/strings.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatefulWidget {
  final List<Task> tasks;
  const StatsScreen({super.key, required this.tasks});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, int> _completedPerDay = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    appLang.addListener(_onLangChange);
    _load();
  }

  @override
  void dispose() {
    appLang.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _load() async {
    final data = await DatabaseService.instance.completedPerDay(7);
    setState(() {
      _completedPerDay = data;
      _loading = false;
    });
  }

  // ── Calculs stats ──────────────────────────────────────────────

  int get _total => widget.tasks.length;
  int get _completed => widget.tasks.where((t) => t.isCompleted).length;
  int get _pending => _total - _completed;
  double get _rate => _total == 0 ? 0 : _completed / _total;

  int get _streak {
    int streak = 0;
    var day = DateTime.now();
    while (true) {
      final key = DateFormat('yyyy-MM-dd').format(day);
      if (_completedPerDay.containsKey(key)) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Données pour les 7 derniers jours (lun → aujourd'hui)
  List<_DayBar> get _weekBars {
    final bars = <_DayBar>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      final count = _completedPerDay[key] ?? 0;
      final label = DateFormat('E', dateLocale).format(d).substring(0, 1).toUpperCase();
      bars.add(_DayBar(label: label, count: count, isToday: i == 0));
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.bgColor,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildKpiRow()),
                  SliverToBoxAdapter(child: _buildWeeklyChart()),
                  SliverToBoxAdapter(child: _buildCategoryBreakdown()),
                  SliverToBoxAdapter(child: _buildPriorityBreakdown()),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('stats_title'),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary)),
                Text('${DateFormat('MMMM yyyy', dateLocale).format(DateTime.now())}',
                    style: TextStyle(fontSize: 14, color: context.textMuted)),
              ],
            ),
          ),
          // Streak badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Column(
                  children: [
                    Text('$_streak',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    Text(t('streak'),
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          _kpiCard(t('total_tasks'), '$_total', const Color(0xFF6366F1), Icons.task_alt),
          const SizedBox(width: 12),
          _kpiCard(t('completed_tasks'), '$_completed', const Color(0xFF10B981), Icons.check_circle_outline),
          const SizedBox(width: 12),
          _kpiCard(t('pending_tasks'), '$_pending', const Color(0xFFF59E0B), Icons.pending_outlined),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: context.textMuted,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final bars = _weekBars;
    final maxCount = bars.map((b) => b.count).fold(0, max);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre + taux
            Row(children: [
              Expanded(
                child: Text(t('weekly_chart'),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${(_rate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6366F1)),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(t('completion_rate'),
                style: TextStyle(fontSize: 12, color: context.textMuted)),
            const SizedBox(height: 20),
            // Barre de progression globale
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _rate,
                minHeight: 8,
                backgroundColor: context.dividerColor,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            const SizedBox(height: 24),
            // Graphique en barres 7 jours
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: bars.map((bar) {
                  final ratio = maxCount == 0 ? 0.0 : bar.count / maxCount;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (bar.count > 0)
                            Text('${bar.count}',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: bar.isToday
                                        ? const Color(0xFF6366F1)
                                        : context.textMuted)),
                          const SizedBox(height: 3),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutBack,
                            height: max(4.0, 80.0 * ratio),
                            decoration: BoxDecoration(
                              color: bar.isToday
                                  ? const Color(0xFF6366F1)
                                  : bar.count > 0
                                      ? const Color(0xFF6366F1).withOpacity(0.4)
                                      : context.dividerColor,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(bar.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: bar.isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: bar.isToday
                                      ? const Color(0xFF6366F1)
                                      : context.textMuted)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    final cats = {'work': 0, 'personal': 0, 'other': 0};
    for (final t in widget.tasks) {
      cats[t.category] = (cats[t.category] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('field_category'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary)),
            const SizedBox(height: 16),
            _catBar('💼', t('cat_work'), cats['work']!, _total, const Color(0xFF6366F1)),
            const SizedBox(height: 10),
            _catBar('👤', t('cat_personal'), cats['personal']!, _total, const Color(0xFFEF4444)),
            const SizedBox(height: 10),
            _catBar('🌿', t('cat_other'), cats['other']!, _total, const Color(0xFF10B981)),
          ],
        ),
      ),
    );
  }

  Widget _catBar(String emoji, String label, int count, int total, Color color) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary)),
            const Spacer(),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: context.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildPriorityBreakdown() {
    final high   = widget.tasks.where((t) => t.priority == 'high').length;
    final normal = widget.tasks.where((t) => t.priority == 'normal').length;
    final low    = widget.tasks.where((t) => t.priority == 'low').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('priority'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary)),
            const SizedBox(height: 16),
            Row(children: [
              _prioCircle(t('prio_high'), high, const Color(0xFFEF4444)),
              const SizedBox(width: 12),
              _prioCircle(t('prio_normal'), normal, const Color(0xFF6366F1)),
              const SizedBox(width: 12),
              _prioCircle(t('prio_low'), low, const Color(0xFF9CA3AF)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _prioCircle(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color)),
          const SizedBox(height: 4),
          Text(label.replaceAll(RegExp(r'[🔴⚪⬇️\s]+'), '').trim(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _DayBar {
  final String label;
  final int count;
  final bool isToday;
  const _DayBar({required this.label, required this.count, required this.isToday});
}
