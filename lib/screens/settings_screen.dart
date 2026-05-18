import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/calendar_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _soundEnabled         = true;
  String _userName           = 'Alex';
  String? _avatarPath;
  List<dynamic> _calendars = [];   // List<Calendar>
  String? _selectedCalendarId;
  bool _syncing = false;
  String _syncMsg = '';

  static const _prefKeyName      = 'user_name';
  static const _prefKeyAvatar    = 'user_avatar';
  static const _prefKeyHaptics   = 'haptics_enabled';
  static const _prefKeyNotifs    = 'notifs_enabled';
  static const _prefKeySound     = 'sound_enabled';

  // Données du dropdown langue
  static const _langs = [
    {'code': 'fr', 'flag': '🇫🇷', 'label': 'Français'},
    {'code': 'en', 'flag': '🇬🇧', 'label': 'English'},
    {'code': 'ar', 'flag': '🇲🇦', 'label': 'العربية'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    appLang.addListener(_onLangChange);
    appThemeMode.addListener(_onLangChange);
    hapticsEnabled.addListener(_onLangChange);
  }

  @override
  void dispose() {
    appLang.removeListener(_onLangChange);
    appThemeMode.removeListener(_onLangChange);
    hapticsEnabled.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName              = prefs.getString(_prefKeyName)  ?? 'Alex';
      _avatarPath            = prefs.getString(_prefKeyAvatar);
      hapticsEnabled.value   = prefs.getBool(_prefKeyHaptics) ?? true;
      _notificationsEnabled  = prefs.getBool(_prefKeyNotifs)  ?? true;
      _soundEnabled          = prefs.getBool(_prefKeySound)   ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyName, _userName);
    if (_avatarPath != null) await prefs.setString(_prefKeyAvatar, _avatarPath!);
    await prefs.setBool(_prefKeyHaptics, hapticsEnabled.value);
    await prefs.setBool(_prefKeyNotifs, _notificationsEnabled);
    await prefs.setBool(_prefKeySound, _soundEnabled);
  }

  // ── Photo de profil ──────────────────────────────────────────

  Future<void> _pickAvatar() async {
    haptic();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (picked != null) {
      setState(() => _avatarPath = picked.path);
      _savePrefs();
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Langue courante pour le dropdown
    final currentLang = _langs.firstWhere(
      (l) => l['code'] == appLang.value,
      orElse: () => _langs.first,
    );

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: const Text(
                'Paramètres',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [

                  // ── Profil ───────────────────────────────────────
                  _card(
                    onTap: _editName,
                    child: Row(children: [
                      GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2C2C2E),
                              image: _avatarPath != null
                                  ? DecorationImage(
                                      image: FileImage(File(_avatarPath!)),
                                      fit: BoxFit.cover)
                                  : null,
                            ),
                            child: _avatarPath == null
                                ? Center(child: Text(
                                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
                                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                  ))
                                : null,
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 20, height: 20,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.edit, size: 12, color: Colors.black),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_userName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(t('tap_edit'), style: const TextStyle(fontSize: 12, color: Color(0xFF636366))),
                        ],
                      )),
                      const Icon(Icons.chevron_right, color: Color(0xFF636366)),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // ── Langue (dropdown sans doublon) ───────────────
                  _card(
                    child: Row(children: [
                      const Icon(Icons.language, color: Color(0xFF8E8E93), size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButton<String>(
                          value: appLang.value,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF2C2C2E),
                          underline: const SizedBox(),
                          icon: const Icon(Icons.expand_more, color: Color(0xFF636366), size: 20),
                          borderRadius: BorderRadius.circular(14),
                          // selectedItemBuilder : affiche le texte dans la ligne
                          selectedItemBuilder: (ctx) => _langs.map((l) =>
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('${l['flag']}  ${l['label']}',
                                  style: const TextStyle(color: Colors.white, fontSize: 15)),
                            ),
                          ).toList(),
                          // items : affiché dans la liste déroulante
                          items: _langs.map((l) => DropdownMenuItem<String>(
                            value: l['code'],
                            child: Text('${l['flag']}  ${l['label']}',
                                style: const TextStyle(color: Colors.white, fontSize: 15)),
                          )).toList(),
                          onChanged: (v) {
                            haptic();
                            if (v != null) setState(() => appLang.value = v);
                          },
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // ── Mode sombre ──────────────────────────────────
                  _card(
                    child: _toggle(
                      t('dark_mode'), Icons.dark_mode_outlined,
                      appThemeMode.value == ThemeMode.dark,
                      (v) {
                        haptic();
                        appThemeMode.value = v ? ThemeMode.dark : ThemeMode.light;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Notifications + Son ──────────────────────────
                  _card(
                    child: Column(children: [
                      _toggle(t('notifications'), Icons.notifications_outlined,
                        _notificationsEnabled, (v) {
                          haptic();
                          setState(() => _notificationsEnabled = v);
                          _savePrefs();
                        },
                      ),
                      _divider(),
                      _toggle(t('sound'), Icons.volume_up_outlined,
                        _soundEnabled, (v) {
                          haptic();
                          setState(() => _soundEnabled = v);
                          _savePrefs();
                        },
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // ── Vibrations ───────────────────────────────────
                  _card(
                    child: _toggle(
                      'Retour haptique', Icons.vibration_outlined,
                      hapticsEnabled.value,
                      (v) {
                        hapticsEnabled.value = v;
                        if (v) haptic();
                        _savePrefs();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Google Agenda ─────────────────────────────────────────────
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Google Agenda', style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                              Text(_selectedCalendarId == null
                                  ? 'Sélectionner un calendrier'
                                  : 'Calendrier connecté',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF636366))),
                            ],
                          )),
                          GestureDetector(
                            onTap: () async {
                              haptic();
                              await _loadCalendars();
                              if (_calendars.isEmpty) return;
                              if (!mounted) return;
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: const Color(0xFF1C1C1E),
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (ctx) => Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 12),
                                    Container(width: 40, height: 4,
                                        decoration: BoxDecoration(color: const Color(0xFF48484A),
                                            borderRadius: BorderRadius.circular(2))),
                                    const SizedBox(height: 16),
                                    const Text('Choisir un calendrier',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                    const SizedBox(height: 12),
                                    ..._calendars.map((cal) {
                                      final c = cal as Calendar;
                                      return ListTile(
                                        title: Text(c.name ?? 'Sans nom',
                                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                                        subtitle: Text(c.accountName ?? '',
                                            style: const TextStyle(color: Color(0xFF636366), fontSize: 12)),
                                        trailing: _selectedCalendarId == c.id
                                            ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
                                            : null,
                                        onTap: () async {
                                          setState(() => _selectedCalendarId = c.id);
                                          // Save to SharedPreferences for background sync
                                          final prefs = await SharedPreferences.getInstance();
                                          await prefs.setString('selected_calendar_id', c.id ?? '');
                                          Navigator.pop(ctx);
                                          // Auto-import current month immediately
                                          if (mounted) _importCurrentMonth();
                                        },
                                      );
                                    }),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              );
                            },
                            child: const Icon(Icons.chevron_right, color: Color(0xFF636366)),
                          ),
                        ]),
                        if (_selectedCalendarId != null) ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1, thickness: 0.5, color: Color(0xFF2C2C2E)),
                          const SizedBox(height: 10),
                          // Synchro auto — un seul bouton Exporter, l'import est auto
                          GestureDetector(
                            onTap: _syncing ? null : () async {
                              haptic();
                              setState(() { _syncing = true; _syncMsg = ''; });
                              final count = await CalendarSyncService.instance
                                  .exportAllToCalendar(_selectedCalendarId!);
                              setState(() {
                                _syncing = false;
                                _syncMsg = count > 0
                                    ? '$count tâche(s) envoyée(s) vers le calendrier'
                                    : 'Aucune tâche à exporter';
                              });
                              Future.delayed(const Duration(seconds: 3),
                                  () { if (mounted) setState(() => _syncMsg = ''); });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Center(child: Text('↑ Exporter mes tâches',
                                  style: TextStyle(color: Color(0xFF818CF8),
                                      fontSize: 13, fontWeight: FontWeight.w600))),
                            ),
                          ),
                          if (_syncing)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Center(child: SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFF6366F1)))),
                            ),
                          if (_syncMsg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_syncMsg, textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF6366F1))),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── À propos ─────────────────────────────────────
                  _card(child: _infoRow(t('version'), '1.1.0')),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF636366),
                letterSpacing: 1.0)),
      );

  Widget _divider() => const Divider(
      height: 1, thickness: 0.5, color: Color(0xFF2C2C2E));

  Widget _card({required Widget child, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      );

  Widget _toggle(String label, IconData icon, bool value,
      Function(bool) onChanged) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF8E8E93), size: 22),
      const SizedBox(width: 14),
      Expanded(
        child: Text(label,
            style: const TextStyle(fontSize: 15, color: Colors.white)),
      ),
      Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: const Color(0xFF48484A),
        inactiveThumbColor: const Color(0xFF636366),
        inactiveTrackColor: const Color(0xFF2C2C2E),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    ]);
  }

  Widget _infoRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 15, color: Colors.white)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF636366))),
        ],
      );

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _loadCalendars() async {
    // Use permission_handler first for explicit runtime request
    final ok = await CalendarSyncService.instance.requestPermissions();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permission calendrier refusée. Activez-la dans les paramètres.'),
          backgroundColor: Color(0xFF1F2937),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ));
      }
      return;
    }
    final cals = await CalendarSyncService.instance.getCalendars();
    if (cals.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun calendrier trouvé sur cet appareil.'),
        backgroundColor: Color(0xFF1F2937),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _calendars = cals);
  }

  Future<void> _importCurrentMonth() async {
    if (_selectedCalendarId == null) return;
    setState(() { _syncing = true; _syncMsg = ''; });
    final now = DateTime.now();
    // Importer de -7j à +60j pour maximiser les chances de trouver des événements
    final start = now.subtract(const Duration(days: 7));
    final end   = now.add(const Duration(days: 60));
    final count = await CalendarSyncService.instance
        .importRangeFromCalendar(_selectedCalendarId!, from: start, to: end);
    if (mounted) {
      String msg;
      if (count == -1) {
        msg = '❌ Permission calendrier refusée';
      } else if (count == -2) {
        msg = '❌ Erreur lecture calendrier';
      } else if (count == 0) {
        msg = 'Aucun nouvel événement trouvé';
      } else {
        msg = '✅ $count événement(s) importé(s)';
        taskVersion.value++; // rafraîchit l'Agenda
      }
      setState(() { _syncing = false; _syncMsg = msg; });
      Future.delayed(const Duration(seconds: 4),
          () { if (mounted) setState(() => _syncMsg = ''); });
    }
  }

  Future<void> _exportPdf() async {
    haptic();
    try {
      final tasks = await DatabaseService.instance.getAllTasks();
      if (!mounted) return;
      if (tasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune tâche à exporter.'),
          backgroundColor: Color(0xFF1F2937),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      await ExportService.instance.exportPdf(tasks);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur export PDF: $e'),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  void _editName() {
    haptic();
    final controller = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Modifier le nom',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Votre prénom',
            hintStyle: TextStyle(color: Color(0xFF636366)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF48484A))),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF636366))),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _userName = name);
                _savePrefs();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Enregistrer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
