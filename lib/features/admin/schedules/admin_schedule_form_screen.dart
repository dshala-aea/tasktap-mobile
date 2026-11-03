// dart format width=100
import 'dart:async';

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
/// backend's model since ADR-0022: `Direct` (§1 — one or more technicians, exactly one of whom may
/// be the report's author) and `Team` (`Squadra`). Legacy staff-only assignment is deliberately not
/// a fourth tab: a staff participant was exactly what ADR-0022 retired (§Context — they could not
/// write the report), and a leaderless group would just be a worse version of [capoSquadra].
enum AssignmentType { tecnico, capoSquadra, squadra }

/// Admin schedule form — create or edit, with a real assignment picker (a single technician, a
/// shared job of co-equal technicians with one designated to compile the rapportino, or a squadra)
/// and a pre-save conflict check.
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

  /// True once the edit-mode row has actually resolved from the mirror; create mode starts true
  /// because there is nothing to await. An id the mirror does not hold (never synced, or purged by
  /// a delta) leaves this false on purpose: the form has no row to write, so it stays unarmed
  /// rather than offer a save that could only fail.
  bool _scheduleLoaded = false;

  /// A day owned by a multi-day plan is a materialised occupancy row, and the backend refuses
  /// every write to it (`block_occupancy_read_only`) — the detail screen hides Modifica for these
  /// rows, but a deep link or a stale back-stack entry can still land here, so the form refuses on
  /// its own rather than filling a form the server can only reject. False until the row loads, and
  /// false on a mirror that synced before the server sent the flag: that device still reaches the
  /// server, whose 400 is recognised by [_lockFromServerCode] instead of ending in the generic
  /// "Impossibile salvare. Riprova." with the button still armed.
  bool _lockedByBlock = false;

  /// The same lock for an absence-owned row (`absence_schedule_read_only`). Such a row exists only
  /// so the approved absence shows on the calendar; it is changed by cancelling and re-filing the
  /// request in Ferie e Permessi, never from this form.
  bool _lockedByAbsence = false;

  bool get _isEditing => widget.scheduleId != null;

  /// The save control is dead until the row resolves, and stays dead for a read-only row. [_save]
  /// repeats the same check so no other path can slip past the button.
  bool get _canSave => _scheduleLoaded && !_lockedByBlock && !_lockedByAbsence;

  /// Why an occupancy row refuses to save — the same opening the detail screen's banner uses.
  static const String _blockLockedMessage =
      'Piano multi-giorno: questa giornata è occupata da un intervento pianificato su più giorni '
      'e non si può modificare da qui.';

  /// Why an absence-owned row refuses to save. Names the screen that owns it instead of leaving
  /// the office with a dead button.
  static const String _absenceLockedMessage =
      'Assenza approvata: questa giornata è gestita dalla richiesta di ferie, permesso o malattia '
      'e non si può modificare da qui. Per cambiarla, annulla la richiesta da Ferie e Permessi.';

  @override
  void initState() {
    super.initState();
    _scheduleLoaded = !_isEditing;
    if (_isEditing) _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final db = ref.read(appDatabaseProvider);
    final schedule = await (db.select(
      db.schedules,
    )..where((s) => s.id.equals(widget.scheduleId!))).getSingleOrNull();
    if (!mounted) return;
    if (schedule == null) {
      // No row to load means nothing to write. `_scheduleLoaded` is already false, and returning
      // here keeps the form unarmed for an id that is not in the mirror.
      return;
    }
    setState(() {
      _titleCtrl.text = schedule.title;
      _descriptionCtrl.text = schedule.description;
      _selectedDate = schedule.activityDate;
      _startTime = _minutesToTimeOfDay(schedule.timeStartMinutes);
      _endTime = _minutesToTimeOfDay(schedule.timeEndMinutes);
      _selectedLocationId = schedule.locationId;
      _selectedTicketId = schedule.ticketId;
      _lockedByBlock = schedule.isBlockOccupied;
      _lockedByAbsence = schedule.isAssenza;
      _scheduleLoaded = true;
    });

    await _loadAssignment();
  }

  /// Resolves the current assignment for edit mode.
  ///
  /// The assignment is rebuilt from the `assignees[]` rows — the **Direct** set and the one row
  /// carrying `isLead` — never from the retired scalar `userId`/`teamLeadId` or the legacy
  /// `isLegacyStaff` blur. Since ADR-0022 §1 every technician, the report's author included, is a
  /// Direct row, and the Direct set is exactly what [_submit] writes back; reading anything else
  /// opened a shared job with only its lead and silently dropped the colleagues on save.
  ///
  /// Tries the live detail endpoint first ([AdminApiClient.fetchScheduleDetail]), which also carries
  /// `squadraId`. Offline, or on any failure, falls back to the local `ScheduleAssignees` mirror: it
  /// carries the same direct/lead/team flags, just not the squadra's id, so the squadra tab stays
  /// disabled in that case rather than preselect a team the admin cannot see the name of.
  Future<void> _loadAssignment() async {
    setState(() => _isLoadingAssignment = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final detail = await api.fetchScheduleDetail(widget.scheduleId!);
      if (detail == null || !mounted) return;

      final squadraId = detail['squadraId'] as String?;
      final assignees = (detail['assignees'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final directIds = assignees
          .where((a) => a['isDirect'] == true)
          .map((a) => a['userId'] as String)
          .toList();
      final leadId = assignees
          .where((a) => a['isLead'] == true)
          .map((a) => a['userId'] as String)
          .firstOrNull;

      setState(() {
        _assignmentLoadedLive = true;
        if (squadraId != null) {
          _assignmentType = AssignmentType.squadra;
          _selectedSquadraId = squadraId;
        } else if (directIds.length >= 2) {
          // Two or more Direct rows: a shared job. Its lead is whoever carries `isLead`; when that
          // flag is missing (data that violates ADR-0022 §4) the selection is left blank and
          // [_assignmentLeadErrorMessage] asks the office — this form never picks a lead for them.
          _assignmentType = AssignmentType.capoSquadra;
          _selectedTeamLeadId = leadId;
          _selectedStaffIds
            ..clear()
            ..addAll(directIds.where((id) => id != leadId));
        } else if (directIds.isNotEmpty) {
          // A lone Direct technician: the server promotes them to `Role = Lead` (ADR-0022 §3), so
          // `teamLeadId` comes back non-null, but the job is still a one-person `tecnico` assignment.
          // Round-tripping through this tab is stable (the server re-promotes); opening the
          // "Capo squadra" tab instead would misdescribe the job — and send a `leadUserId` it should
          // not.
          _assignmentType = AssignmentType.tecnico;
          _selectedUserId = directIds.first;
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
      // Same reconstruction as the live branch, from the mirror's identical direct/lead/team flags.
      final directIds = assignees.where((a) => a.isDirect).map((a) => a.userId).toList();
      final leadId = assignees.where((a) => a.isLead).map((a) => a.userId).firstOrNull;
      final isTeam = assignees.any((a) => a.isTeam);
      setState(() {
        if (isTeam) {
          _assignmentType = AssignmentType.squadra; // id unknown — tab stays disabled below
        } else if (directIds.length >= 2) {
          _assignmentType = AssignmentType.capoSquadra;
          _selectedTeamLeadId = leadId;
          _selectedStaffIds
            ..clear()
            ..addAll(directIds.where((id) => id != leadId));
        } else if (directIds.isNotEmpty) {
          _assignmentType = AssignmentType.tecnico;
          _selectedUserId = directIds.first;
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

  /// Everyone the active assignment tab directly assigns, in the order the wire wants them — the
  /// lead first for a capoSquadra. Single source of the list, shared by [_submit] and the
  /// pre-flight so the two can never name different people.
  List<String> get _technicianIds => switch (_assignmentType) {
    AssignmentType.tecnico => _selectedUserId == null ? <String>[] : [_selectedUserId!],
    AssignmentType.capoSquadra => [
      ?_selectedTeamLeadId,
      ..._selectedStaffIds.where((id) => id != _selectedTeamLeadId),
    ],
    // A squadra assigns no individuals directly. On edit this list is sent (empty) to clear any
    // directly-assigned technicians the schedule used to carry; on create it is omitted entirely.
    AssignmentType.squadra => const <String>[],
  };

  /// Which of [_technicianIds] compiles the rapportino. Only a capoSquadra names one; a lone
  /// technician is promoted to lead server-side (ADR-0022 §3).
  String? get _leadUserId =>
      _assignmentType == AssignmentType.capoSquadra ? _selectedTeamLeadId : null;

  /// Mirrors the server's ADR-0022 §4 rule before the round trip (`SchedulesController`'s
  /// create/update guards): a capoSquadra assignment with two or more people must name a lead who
  /// is one of them — a removed lead is rejected, never silently resolved. The picker already
  /// requires a lead, so this keeps that promise should the picker ever change.
  bool get _assignmentLeadIsCoherent {
    if (_assignmentType != AssignmentType.capoSquadra) return true;
    final selected = <String>{?_selectedTeamLeadId, ..._selectedStaffIds};
    if (selected.length >= 2 && _selectedTeamLeadId == null) return false;
    if (_selectedTeamLeadId != null && !selected.contains(_selectedTeamLeadId)) return false;
    return true;
  }

  String get _assignmentLeadErrorMessage => _selectedTeamLeadId == null
      ? 'Seleziona un capo squadra'
      : 'Il capo squadra deve essere tra i tecnici selezionati';

  /// The technicians/squadra [AdminApiClient.checkScheduleConflicts] should test. Every assignment
  /// kind now produces a technician list, so every kind can be pre-flighted — a capoSquadra's lead
  /// and staff are co-equal direct assignees since ADR-0022 §1, so they are booked as such.
  (List<String>? technicianIds, String? squadraId) get _conflictCheckTargets =>
      switch (_assignmentType) {
        AssignmentType.squadra => (null, _selectedSquadraId),
        AssignmentType.tecnico || AssignmentType.capoSquadra => (
          _technicianIds.isEmpty ? null : _technicianIds,
          null,
        ),
      };

  Future<void> _save() async {
    // Defence in depth: the button is already disabled below, but no path may reach the server
    // with a write this row can only answer with a 400.
    if (!_scheduleLoaded) return;
    if (_lockedByBlock) {
      showAppToast(context, message: _blockLockedMessage, tone: ToastTone.warning);
      return;
    }
    if (_lockedByAbsence) {
      showAppToast(context, message: _absenceLockedMessage, tone: ToastTone.warning);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_assignmentIsValid) {
      showAppToast(context, message: _assignmentErrorMessage, tone: ToastTone.warning);
      return;
    }
    if (!_assignmentLeadIsCoherent) {
      showAppToast(context, message: _assignmentLeadErrorMessage, tone: ToastTone.warning);
      return;
    }
    if (_selectedLocationId == null) {
      showAppToast(context, message: 'Seleziona una sede', tone: ToastTone.warning);
      return;
    }
    if (_timeOfDayToMinutes(_endTime) <= _timeOfDayToMinutes(_startTime)) {
      showAppToast(
        context,
        message: "L'orario di fine deve essere successivo all'orario di inizio",
        tone: ToastTone.warning,
      );
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      final (checkTechnicianIds, checkSquadraId) = _conflictCheckTargets;
      var force = false;
      if (checkTechnicianIds != null || checkSquadraId != null) {
        final conflicts = await api.checkScheduleConflicts(
          activityDate: _selectedDate,
          timeStartMinutes: _timeOfDayToMinutes(_startTime),
          timeEndMinutes: _timeOfDayToMinutes(_endTime),
          technicianIds: checkTechnicianIds,
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
      // The row can be read-only server-side even when this device's mirror does not know it: the
      // flag is absent on a mirror that synced before the server sent it, and an absence row can
      // arrive mid-edit. `ScheduleCommandService` answers both with a 400 problem+json whose `code`
      // names the owner, so recognise it and switch the form into the same locked state the flags
      // would have produced — otherwise the office reads "Impossibile salvare. Riprova." and the
      // button stays armed to retry the same refusal forever.
      final data = e.response?.data;
      final code = data is Map ? data['code'] : null;
      if (_lockFromServerCode(code)) return;
      // A conflict may have appeared between the pre-flight check and the save itself — the same
      // 409 shape the pre-flight would have shown, just discovered late (SchedulesController.Create
      // / .Update both answer 409 with `conflicts` when `force` is not set).
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

  /// Translates the server's read-only refusal into the lock state the mirror's flags would have
  /// produced, and says why. Returns false for any other error so the caller can fall through to
  /// the conflict dialog / generic message.
  bool _lockFromServerCode(Object? code) {
    if (code != 'block_occupancy_read_only' && code != 'absence_schedule_read_only') {
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _lockedByBlock = code == 'block_occupancy_read_only';
      _lockedByAbsence = code == 'absence_schedule_read_only';
    });
    showAppToast(
      context,
      message: _lockedByBlock ? _blockLockedMessage : _absenceLockedMessage,
      tone: ToastTone.warning,
    );
    return true;
  }

  void _showSaveError() {
    if (!mounted) return;
    showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
  }

  Future<void> _submit({required AdminApiClient api, required bool force}) async {
    // One list and one lead, for every assignment kind. capoSquadra used to send its extras as
    // staffIds — the shape ADR-0022 exists to eliminate, because a staff participant cannot write
    // the report. They are co-equal technicians now, and the lead still names the author.
    //
    // On edit the list is always sent, empty included: an empty list clears the direct set on a
    // schedule that is now the squadra's, where omitting it would leave the old technicians. On
    // create a squadra-only schedule omits the field entirely.
    final List<String>? technicianIds = _assignmentType == AssignmentType.squadra && !_isEditing
        ? null
        : _technicianIds;

    // A squadra row is cleared only by naming the all-zeros GUID: an absent squadraId does not
    // mention the Team source at all, so it cannot remove one already stored (see
    // AdminApiClient.updateSchedule's doc comment). The direct set needs no such sentinel.
    final squadraId = _assignmentType == AssignmentType.squadra
        ? _selectedSquadraId
        : (_isEditing ? AdminApiClient.emptyAssignmentId : null);

    if (_isEditing) {
      await api.updateSchedule(
        widget.scheduleId!,
        activityDate: _selectedDate,
        timeStartMinutes: _timeOfDayToMinutes(_startTime),
        timeEndMinutes: _timeOfDayToMinutes(_endTime),
        technicianIds: technicianIds,
        leadUserId: _leadUserId,
        locationId: _selectedLocationId,
        ticketId: _selectedTicketId,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        squadraId: squadraId,
        force: force,
      );
    } else {
      await api.createSchedule(
        activityDate: _selectedDate,
        timeStartMinutes: _timeOfDayToMinutes(_startTime),
        timeEndMinutes: _timeOfDayToMinutes(_endTime),
        technicianIds: technicianIds,
        leadUserId: _leadUserId,
        locationId: _selectedLocationId!,
        ticketId: _selectedTicketId,
        statusId: 0,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
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
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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

  /// The read-only explanation shown above the form. Constrained to the same width as the fields
  /// so it does not stretch across a wide screen while the form underneath stays centred.
  Widget _lockBanner({required String message, required IconData icon}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            0,
          ),
          child: InlineAlert(icon: icon, color: context.colors.amber, message: message),
        ),
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
      // Outside the ListView on purpose: `AppTabs` reveals the selected assignment tab with
      // `Scrollable.ensureVisible`, which scrolls every enclosing scrollable — the form opens with
      // its list already scrolled to the tab strip, so a banner at the top of the list would be
      // off-screen exactly when the office needs to read why the save button is dead. The banner
      // still shares the form's 560px cap (see [_lockBanner]) so it lines up with the fields
      // instead of spanning a wide screen edge to edge.
      body: Column(
        children: [
          if (_lockedByBlock)
            _lockBanner(message: _blockLockedMessage, icon: LucideIcons.calendarDays),
          if (_lockedByAbsence)
            _lockBanner(message: _absenceLockedMessage, icon: LucideIcons.calendarX),
          Expanded(
            child: Form(
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
                        onSelected: (i) =>
                            setState(() => _assignmentType = AssignmentType.values[i]),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingAssignment)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
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
                        onPressed: _isSaving || !_canSave ? null : _save,
                        isLoading: _isSaving,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
              // "Altri tecnici", not "Staff aggiuntivo": the people in this picker are co-equal
              // technicians (they can all write the report — ADR-0022 §Context), not the retired
              // staff participants who could not. Mirrors the web form's `tecniciLabel` ("Tecnici").
              Text(
                'Altri tecnici',
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
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
