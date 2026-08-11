// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../ticket/steps/step_assegnazione.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Admin schedule form — create or edit.
class AdminScheduleFormScreen extends ConsumerStatefulWidget {
  const AdminScheduleFormScreen({super.key, this.scheduleId});

  final String? scheduleId;

  @override
  ConsumerState<AdminScheduleFormScreen> createState() =>
      _AdminScheduleFormScreenState();
}

class _AdminScheduleFormScreenState
    extends ConsumerState<AdminScheduleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  String? _selectedUserId;
  String? _selectedLocationId;
  String? _selectedTicketId;
  bool _isSaving = false;

  bool get _isEditing => widget.scheduleId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final db = ref.read(appDatabaseProvider);
    final schedule = await (db.select(db.schedules)
          ..where((s) => s.id.equals(widget.scheduleId!)))
        .getSingleOrNull();
    if (schedule != null && mounted) {
      setState(() {
        _titleCtrl.text = schedule.title;
        _descriptionCtrl.text = schedule.description;
        _selectedDate = schedule.activityDate;
        _startTime = _minutesToTimeOfDay(schedule.timeStartMinutes);
        _endTime = _minutesToTimeOfDay(schedule.timeEndMinutes);
        _selectedUserId = schedule.userId;
        _selectedLocationId = schedule.locationId;
        _selectedTicketId = schedule.ticketId;
      });
    }
  }

  TimeOfDay _minutesToTimeOfDay(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un tecnico')),
      );
      return;
    }
    if (_selectedLocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona una sede')),
      );
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateSchedule(
          widget.scheduleId!,
          activityDate: _selectedDate,
          timeStartMinutes: _timeOfDayToMinutes(_startTime),
          timeEndMinutes: _timeOfDayToMinutes(_endTime),
          userId: _selectedUserId,
          locationId: _selectedLocationId,
          ticketId: _selectedTicketId,
          title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
        );
      } else {
        await api.createSchedule(
          activityDate: _selectedDate,
          timeStartMinutes: _timeOfDayToMinutes(_startTime),
          timeEndMinutes: _timeOfDayToMinutes(_endTime),
          userId: _selectedUserId!,
          locationId: _selectedLocationId!,
          ticketId: _selectedTicketId,
          statusId: 0,
          title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Pianificazione aggiornata' : 'Pianificazione creata',
            ),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final techniciansAsync = ref.watch(techniciansProvider);
    final technicians = techniciansAsync.valueOrNull ?? [];
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it')
        .format(_selectedDate);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Modifica pianificazione' : 'Nuova pianificazione',
        ),
        backgroundColor: context.colors.bg2,
        foregroundColor: context.colors.ink,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salva'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(19),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Date picker ──────────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data'),
              subtitle: Text(dateLabel),
              trailing: const Icon(LucideIcons.calendar),
              onTap: _pickDate,
            ),
            const Divider(),

            // ── Time pickers ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inizio'),
                    subtitle: Text(_startTime.format(context)),
                    trailing: const Icon(LucideIcons.clock),
                    onTap: _pickStartTime,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fine'),
                    subtitle: Text(_endTime.format(context)),
                    trailing: const Icon(LucideIcons.clock),
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // ── Technician selector ──────────────────────────────────────
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use — controlled field, needs value not initialValue
              value: _selectedUserId,
              decoration: const InputDecoration(
                labelText: 'Tecnico *',
                border: OutlineInputBorder(),
              ),
              items: [
                ...technicians.map((t) => DropdownMenuItem(
                      value: t['id'] as String,
                      child: Text(
                        t['displayName'] as String? ??
                            t['email'] as String? ??
                            '',
                      ),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedUserId = v),
              validator: (v) => v == null ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            // ── Location selector ────────────────────────────────────────
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use — controlled field, needs value not initialValue
              value: _selectedLocationId,
              decoration: const InputDecoration(
                labelText: 'Sede *',
                border: OutlineInputBorder(),
              ),
              items: locations
                  .map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedLocationId = v),
              validator: (v) => v == null ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
