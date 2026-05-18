import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/task.dart';

class ExportService {
  static final ExportService instance = ExportService._();
  ExportService._();

  // ── Palette ──────────────────────────────────────────────────
  static const _bg     = PdfColor.fromInt(0xFF000000);
  static const _card   = PdfColor.fromInt(0xFF1C1C1E);
  static const _white  = PdfColor.fromInt(0xFFFFFFFF);
  static const _muted  = PdfColor.fromInt(0xFF8E8E93);
  static const _accent = PdfColor.fromInt(0xFF6366F1);
  static const _green  = PdfColor.fromInt(0xFF10B981);
  static const _red    = PdfColor.fromInt(0xFFEF4444);
  static const _amber  = PdfColor.fromInt(0xFFF59E0B);

  // Crée une couleur semi-transparente depuis une PdfColor 0-1 channels
  static PdfColor _fade(PdfColor c, double alpha) =>
      PdfColor(c.red, c.green, c.blue, alpha);

  /// Exporte les tâches en PDF et lance le partage
  Future<void> exportPdf(List<Task> tasks) async {
    final doc = pw.Document();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final pending   = tasks.where((t) => !t.isCompleted).toList();
    final completed = tasks.where((t) => t.isCompleted).toList();
    final sorted    = [...pending, ...completed];

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _bg),
          ),
        ),
        build: (ctx) => [
          // ── En-tête ─────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: _card,
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VOCAL TODO',
                        style: pw.TextStyle(
                            color: _accent, fontSize: 10,
                            fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                    pw.SizedBox(height: 4),
                    pw.Text('Mes tâches',
                        style: pw.TextStyle(
                            color: _white, fontSize: 24,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Exporté le $now',
                        style: pw.TextStyle(color: _muted, fontSize: 11)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _statBadge('${pending.length}', 'En cours', _accent),
                    pw.SizedBox(height: 8),
                    _statBadge('${completed.length}', 'Terminées', _green),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // ── Liste des tâches ─────────────────────────────────
          ...sorted.map((task) {
            final isDone = task.isCompleted;
            final priorityCol = task.priority == 'high'
                ? _red
                : task.priority == 'low'
                    ? _green
                    : _amber;
            final dateStr = task.dueDate != null ? fmt.format(task.dueDate!) : '—';

            // ── Task card: left bar via Row (borderRadius + non-uniform
            //    border is unsupported by the pdf package, so we use a
            //    colored sidebar as the first Row child instead) ──────
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(
                color: _card,
                borderRadius: pw.BorderRadius.circular(12),
                // No border here — left accent is a child Container
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Left priority accent bar
                  pw.Container(width: 3, color: priorityCol),
                  // Main content
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(14),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          // Cercle statut
                          pw.Container(
                            width: 18, height: 18,
                            margin: const pw.EdgeInsets.only(right: 12),
                            decoration: pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              color: isDone ? _green : _fade(_muted, 0.1),
                              border: pw.Border.all(
                                  color: isDone ? _green : _muted,
                                  width: 1.5),
                            ),
                            child: isDone
                                ? pw.Center(
                                    child: pw.Text('✓',
                                        style: pw.TextStyle(
                                            color: _white, fontSize: 10,
                                            fontWeight: pw.FontWeight.bold)))
                                : null,
                          ),
                          // Titre + meta
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  task.title,
                                  style: pw.TextStyle(
                                    color: isDone ? _muted : _white,
                                    fontSize: 13,
                                    fontWeight: pw.FontWeight.bold,
                                    decoration: isDone
                                        ? pw.TextDecoration.lineThrough
                                        : pw.TextDecoration.none,
                                  ),
                                ),
                                pw.SizedBox(height: 5),
                                pw.Row(children: [
                                  _chip(_catLabel(task.category), _muted),
                                  pw.SizedBox(width: 6),
                                  if (task.dueDate != null) ...[
                                    _chip(dateStr, _muted),
                                    pw.SizedBox(width: 6),
                                  ],
                                  _chip(isDone ? 'Terminé' : 'En cours',
                                      isDone ? _green : _accent),
                                ]),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          // Badge priorité
                          _chip(_priorityLabel(task.priority), priorityCol),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir   = await getTemporaryDirectory();
    final file  = File('${dir.path}/vocal_todo_export.pdf');
    await file.writeAsBytes(bytes);

    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: 'vocal_todo_export.pdf')],
        subject: 'Vocal Todo — ${tasks.length} tâche(s)',
      );
    } catch (_) {
      // Fallback: open with printing package
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  pw.Widget _statBadge(String count, String label, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _fade(color, 0.15),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(children: [
        pw.Text(count,
            style: pw.TextStyle(
                color: color, fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: pw.TextStyle(color: color, fontSize: 9)),
      ]),
    );
  }

  pw.Widget _chip(String label, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _fade(color, 0.15),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(label, style: pw.TextStyle(color: color, fontSize: 9)),
    );
  }

  String _catLabel(String cat) {
    switch (cat) {
      case 'work':     return 'Travail';
      case 'personal': return 'Personnel';
      default:         return 'Autre';
    }
  }

  String _priorityLabel(String p) {
    switch (p) {
      case 'high': return 'Urgent';
      case 'low':  return 'Bas';
      default:     return 'Normal';
    }
  }
}
