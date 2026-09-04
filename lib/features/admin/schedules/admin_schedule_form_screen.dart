// dart format width=100
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../ticket/steps/step_assegnazione.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import '../squadre/admin_squadra_list_screen.dart' show adminSquadreProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

/// Who a schedule is assigned to — the three assignment kinds this form offers, matching the
/// backend's own model (ADR-0009: `Direct`, `TeamLead`(+legacy `StaffIds`), `Squadra`). Legacy
/// staff-only assignment (no lead) is deliberately not a fourth tab: `ScheduleAssignmentDerivation`
/// treats a lead as the natural anchor for a staff list, and offering a leaderless staff group as
/// its own primary choice would just be a worse version of [capoSquadra].
enum AssignmentType { tecnico, capoSquadra, squadra }

/// Admin schedule form — create or edit, with a real assignment picker (individual technician,
/// team lead + staff, or squadra) and a pre-save conflict check.
class AdminScheduleFormScreen extends ConsumerStatefulWidget {
  const AdminScheduleFormScreen({super.key, this.scheduleId});

  final String? scheduleId;

  @override
  ConsumerState<AdminScheduleFormScreen> createState() => _AdminScheduleFormScreenState();
}

class _AdminScheduleFormScreenState extends ConsumerState<AdminScheduleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  String? _selectedLocationId;
  String? _selectedTicketId;
  bool _isSaving = false;
  bool _isLoadingAssignment = false;

  // ── Assignment ────────────────────────────────────────────────────────────
  AssignmentType _assignmentType = AssignmentType.tecnico;
  String? _selectedUserId;
  String? _selectedTeamLeadId;
  final Set<String> _selectedStaffIds = {};
  String? _selectedSquadraId;

  /// Set once an edit-mode load has resolved live assignment via
  /// [AdminApiClient.fetchScheduleDetail]. When it stays false (offline, or the call failed) the
  /// squadra tab is disabled rather than let the admin "confirm" a squadra assignment this device
  /// cannot actually name.
  bool _assignmentLoadedLive = false;

  bool get _isEditing => widget.scheduleId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final db = ref.read(appDatabaseProvider);
    final schedule = await (db.select(
      db.schedules,
    )..where((s) => s.id.equals(widget.scheduleId!))).getSingleOrNull();
    if (schedule != null && mounted) {
      setState(() {
        _titleCtrl.text = schedule.title;
        _descriptionCtrl.text = schedule.description;
        _selectedDate = schedule.activityDate;
        _startTime = _minutesToTimeOfDay(schedule.timeStartMinutes);
        _endTime = _minutesToTimeOfDay(schedule.timeEndMinutes);
        _selectedLocationId = schedule.locationId;
        _selectedTicketId = schedule.ticketId;
      });
    }

    await _loadAssignment();
  }

  /// Resolves the current assignment for edit mode.
  ///
  /// Tries the live detail endpoint first — it is the only source that carries `teamLeadId` and
  /// `squadraId` (see [AdminApiClient.fetchScheduleDetail]'s doc comment). Offline, or on any
  /// failure, falls back to the local `ScheduleAssignees` mirror: it can still say "direct" vs
  /// "team", just not which squadra, so the squadra tab stays disabled in that case rather than
  /// preselect a team the admin cannot see the name of.
  Future<void> _loadAssignment() async {
    setState(() => _isLoadingAssignment = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final detail = await api.fetchScheduleDetail(widget.scheduleId!);
      if (detail == null || !mounted) return;

      final userId = detail['userId'] as String?;
      final teamLeadId = detail['teamLeadId'] as String?;
      final squadraId = detail['squadraId'] as String?;
      final assignees = (detail['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final legacyStaff = assignees
          .where((a) => a['isLegacyStaff'] == true)
          .map((a) => a['userId'] as String)
          .toSet();

      setState(() {
        _assignmentLoadedLive = true;
        if (squadraId != null) {
          _assignmentType = AssignmentType.squadra;
          _selectedSquadraId = squadraId;
        } else if (teamLeadId != null) {
          _assignmentType = AssignmentType.capoSquadra;
          _selectedTeamLeadId = teamLeadId;
          _selectedStaffIds
            ..clear()
            ..addAll(legacyStaff);
        } else if (userId != null) {
          _assignmentType = AssignmentType.tecnico;
          _selectedUserId = userId;
        }
      });
    } catch (_) {
      // Offline or the call failed — fall back to what the local mirror knows.
      if (!mounted) return;
      final db = ref.read(appDatabaseProvider);
      final assignees = await (db.select(
        db.scheduleAssignees,
      )..where((a) => a.scheduleId.equals(widget.scheduleId!))).get();
      if (!mounted) return;
      final direct = assignees.where((a) => a.isDirect).firstOrNull;
      final isTeam = assignees.any((a) => a.isTeam);
      setState(() {
        if (isTeam) {
          _assignmentType = AssignmentType.squadra; // id unknown — tab stays disabled below
        } else if (direct != null) {
          _assignmentType = AssignmentType.tecnico;
          _selectedUserId = direct.userId;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoadingAssignment = false);
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
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  /// Whether the currently selected assignment tab has what it needs to save.
  bool get _assignmentIsValid => switch (_assignmentType) {
    AssignmentType.tecnico => _selectedUserId != null,
    AssignmentType.capoSquadra => _selectedTeamLeadId != null,
    AssignmentType.squadra => _selectedSquadraId != null,
  };

  String get _assignmentErrorMessage => switch (_assignmentType) {
    AssignmentType.tecnico => 'Seleziona un tecnico',
    AssignmentType.capoSquadra => 'Seleziona un capo squadra',
    AssignmentType.squadra => 'Seleziona una squadra',
  };

  /// The `userId`/`squadraId` [AdminApiClient.checkScheduleConflicts] should test — only `Direct`
  /// and `Team` sources are ever flagged as conflicts server-side (see
  /// `SchedulesController.FindConflictsAsync`'s remarks: a lead or legacy-staff booking elsewhere
  /// has never been a conflict), so a `capoSquadra` assignment has nothing to check yet.
  (String? userId, String? squadraId) get _conflictCheckTargets => switch (_assignmentType) {
    AssignmentType.tecnico => (_selectedUserId, null),
    AssignmentType.capoSquadra => (null, null),
    AssignmentType.squadra => (null, _selectedSquadraId),
  };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_assignmentIsValid) {
      showAppToast(context, message: _assignmentErrorMessage, tone: ToastTone.warning);
      return;
    }
    if (_selectedLocationId == null) {
      showAppToast(context, message: 'Seleziona una sede', tone: ToastTone.warning);
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      final (checkUserId, checkSquadraId) = _conflictCheckTargets;
      var force = false;
      if (checkUserId != null || checkSquadraId != null) {
        final conflicts = await api.checkScheduleConflicts(
          activityDate: _selectedDate,
          timeStartMinutes: _timeOfDayToMinutes(_startTime),
          timeEndMinutes: _timeOfDayToMinutes(_endTime),
          userId: checkUserId,
          squadraId: checkSquadraId,
          excludeScheduleId: widget.scheduleId,
        );
        if (conflicts.isNotEmpty) {
          if (!mounted) return;
          final confirmed = await _showConflictDialog(conflicts);
          if (confirmed != true) {
            setState(() => _isSaving = false);
            return;
          }
          force = true;
        }
      }

      await _submit(api: api, force: force);

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        showAppToast(
          context,
          message: _isEditing ? 'Pianificazione aggiornata' : 'Pianificazione creata',
          tone: ToastTone.success,
        );
        context.pop(true);
      }
    } on DioException catch (e) {
      // A conflict may have appeared between the pre-flight check and the save itself — the same
      // 409 shape the pre-flight would have shown, just discovered late (SchedulesController.Create
      // / .Update both answer 409 with `conflicts` when `force` is not set).
      final data = e.response?.data;
      if (e.response?.statusCode == 409 && data is Map && data['conflicts'] is List) {
        final conflicts = (data['conflicts'] as List)
            .map((c) => ScheduleConflict.fromJson(c as Map<String, dynamic>))
            .toList();
        if (mounted) {
          final confirmed = await _showConflictDialog(conflicts);
          if (confirmed == true) {
            try {
              final api = ref.read(adminApiClientProvider);
              await _submit(api: api, force: true);
              unawaited(ref.read(syncProvider.notifier).performSync());
              if (mounted) {
                showAppToast(
                  context,
                  message: _isEditing ? 'Pianificazione aggiornata' : 'Pianificazione creata',
                  tone: ToastTone.success,
                );
                context.pop(true);
              }
              return;
            } catch (_) {
              _showSaveError();
            }
          }
        }
      } else {
        _showSaveError();
      }
    } catch (e) {
      _showSaveError();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSaveError() {
    if (!mounted) return;
    showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
  }

  Future<void> _submit({required AdminApiClient api, required bool force}) async {
    final empty = AdminApiClient.emptyAssignmentId;
    // On edit, a field that is not this assignment's own has to be explicitly cleared (the
    // all-zeros GUID / "[]") rather than omitted — see AdminApiClient.updateSchedule's doc comment
    // for why omission cannot express "no longer this" once a schedule already has an assignment.
    final userId = _assignmentType == AssignmentType.tecnico
        ? _selectedUserId
        : (_isEditing ? empty : null);
    final teamLeadId = _assignmentType == AssignmentType.capoSquadra
        ? _selectedTeamLeadId
        : (_isEditing ? empty : null);
    final staffIds = _assignmentType == AssignmentType.capoSquadra
        ? jsonEncode(_selectedStaffIds.toList())
        : (_isEditing ? '[]' : null);
    final squadraId = _assignmentType == AssignmentType.squadra
        ? _selectedSquadraId
        : (_isEditing ? empty : null);

    if (_isEditing) {
      await api.updateSchedule(
        widget.scheduleId!,
        activityDate: _selectedDate,
        timeStartMinutes: _timeOfDayToMinutes(_startTime),
        timeEndMinutes: _timeOfDayToMinutes(_endTime),
        userId: userId,
        locationId: _selectedLocationId,
        ticketId: _selectedTicketId,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        teamLeadId: teamLeadId,
        staffIds: staffIds,
        squadraId: squadraId,
        force: force,
      );
    } else {
      await api.createSchedule(
        activityDate: _selectedDate,
        timeStartMinutes: _timeOfDayToMinutes(_startTime),
        timeEndMinutes: _timeOfDayToMinutes(_endTime),
        userId: userId,
        locationId: _selectedLocationId!,
        ticketId: _selectedTicketId,
        statusId: 0,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        teamLeadId: teamLeadId,
        staffIds: staffIds,
        squadraId: squadraId,
        force: force,
      );
    }
  }

  /// Shows who/when overlaps and lets the admin force-save. Returns `true` when they chose to
  /// save anyway, `false`/`null` when they cancelled.
  Future<bool?> _showConflictDialog(List<ScheduleConflict> conflicts) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Conflitti rilevati'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Questo orario è già occupato da:'),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: conflicts.length,
                  itemBuilder: (context, i) {
                    final c = conflicts[i];
                    final dateLabel = DateFormat('EEE d MMM', 'it').format(c.activityDate);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title.isNotEmpty ? c.title : 'Intervento',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '$dateLabel · ${c.timeStart.substring(0, 5)}–${c.timeEnd.substring(0, 5)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva comunque'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_selectedDate);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica pianificazione' : 'Nuova pianificazione',
        showBack: true,
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                context.navClearance,
              ),
              children: [
            AppTextField(label: 'Titolo', controller: _titleCtrl),
            const SizedBox(height: 16),

            // ── Date picker ──────────────────────────────────────────────
            AdminDateField(label: 'Data', value: dateLabel, onTap: _pickDate),
            const SizedBox(height: 16),

            // ── Time pickers ─────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AdminDateField(
                    label: 'Inizio',
                    value: _startTime.format(context),
                    icon: LucideIcons.clock,
                    onTap: _pickStartTime,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminDateField(
                    label: 'Fine',
                    value: _endTime.format(context),
                    icon: LucideIcons.clock,
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Assignment ────────────────────────────────────────────────
            Text(
              'Assegnazione *',
              style: AppTextStyles.labelMedium.copyWith(color: context.colors.inkMuted),
            ),
            const SizedBox(height: 6),
            AppTabs(
              tabs: const [
                AppTab(label: 'Tecnico'),
                AppTab(label: 'Capo squadra'),
                AppTab(label: 'Squadra'),
              ],
              selectedIndex: _assignmentType.index,
              onSelected: (i) => setState(() => _assignmentType = AssignmentType.values[i]),
            ),
            const SizedBox(height: 12),
            if (_isLoadingAssignment)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              _AssignmentPicker(
                type: _assignmentType,
                selectedUserId: _selectedUserId,
                onUserChanged: (v) => setState(() => _selectedUserId = v),
                selectedTeamLeadId: _selectedTeamLeadId,
                onTeamLeadChanged: (v) => setState(() => _selectedTeamLeadId = v),
                selectedStaffIds: _selectedStaffIds,
                onStaffToggled: (id, selected) => setState(() {
                  if (selected) {
                    _selectedStaffIds.add(id);
                  } else {
                    _selectedStaffIds.remove(id);
                  }
                }),
                selectedSquadraId: _selectedSquadraId,
                onSquadraChanged: (v) => setState(() => _selectedSquadraId = v),
                squadraDisabled: _isEditing && !_assignmentLoadedLive,
              ),
            const SizedBox(height: 16),

            // ── Location selector ────────────────────────────────────────
            AppFieldShell(
              label: 'Sede *',
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _selectedLocationId,
                items: locations
                    .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedLocationId = v),
                validator: (v) => v == null ? 'Campo obbligatorio' : null,
              ),
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _descriptionCtrl, maxLines: 3),
            const SizedBox(height: 32),

            AppButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea pianificazione',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picker(s) for whichever [AssignmentType] tab is active.
class _AssignmentPicker extends ConsumerWidget {
  const _AssignmentPicker({
    required this.type,
    required this.selectedUserId,
    required this.onUserChanged,
    required this.selectedTeamLeadId,
    required this.onTeamLeadChanged,
    required this.selectedStaffIds,
    required this.onStaffToggled,
    required this.selectedSquadraId,
    required this.onSquadraChanged,
    required this.squadraDisabled,
  });

  final AssignmentType type;
  final String? selectedUserId;
  final ValueChanged<String?> onUserChanged;
  final String? selectedTeamLeadId;
  final ValueChanged<String?> onTeamLeadChanged;
  final Set<String> selectedStaffIds;
  final void Function(String id, bool selected) onStaffToggled;
  final String? selectedSquadraId;
  final ValueChanged<String?> onSquadraChanged;

  /// True when editing a schedule whose live assignment could not be loaded (offline) — the
  /// squadra tab is disabled rather than let the admin confirm a squadra id this device cannot
  /// resolve a name for.
  final bool squadraDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final techniciansAsync = ref.watch(techniciansProvider);
    final technicians = techniciansAsync.valueOrNull ?? [];

    switch (type) {
      case AssignmentType.tecnico:
        return AppFieldShell(
          label: 'Tecnico *',
          child: DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — controlled field, needs value not initialValue
            value: selectedUserId,
            items: technicians
                .map(
                  (t) => DropdownMenuItem(
                    value: t['id'] as String,
                    child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                  ),
                )
                .toList(),
            onChanged: onUserChanged,
          ),
        );

      case AssignmentType.capoSquadra:
        final staffOptions = technicians.where((t) => t['id'] != selectedTeamLeadId).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFieldShell(
              label: 'Capo squadra *',
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: selectedTeamLeadId,
                items: technicians
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: onTeamLeadChanged,
              ),
            ),
            if (staffOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Staff aggiuntivo',
                style: AppTextStyles.labelMedium.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: staffOptions.map((t) {
                  final id = t['id'] as String;
                  final name = t['displayName'] as String? ?? t['email'] as String? ?? '';
                  return AppChip(
                    label: name,
                    active: selectedStaffIds.contains(id),
                    onTap: () => onStaffToggled(id, !selectedStaffIds.contains(id)),
                  );
                }).toList(),
              ),
            ],
          ],
        );

      case AssignmentType.squadra:
        if (squadraDisabled) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Assegnazione a squadra non disponibile offline. Torna online per modificarla.',
              style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
            ),
          );
        }
        final squadreAsync = ref.watch(adminSquadreProvider);
        final squadre = squadreAsync.valueOrNull ?? [];
        return AppFieldShell(
          label: 'Squadra *',
          child: DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — controlled field, needs value not initialValue
            value: selectedSquadraId,
            items: squadre
                .map(
                  (s) => DropdownMenuItem(
                    value: s['id'] as String,
                    child: Text(s['nome'] as String? ?? ''),
                  ),
                )
                .toList(),
            onChanged: onSquadraChanged,
          ),
        );
    }
  }
}
