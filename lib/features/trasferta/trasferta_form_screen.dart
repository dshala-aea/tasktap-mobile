// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/trasferta/trasferta_request_api_client.dart';
import '../admin/admin_widgets.dart';

/// New Trasferta: the day, when the travel started, how many hours, and an optional note.
///
/// Create-only for the technician (the office edits). The server writes the worklog and answers
/// with its own sentence when a rule refuses — one trasferta per day, an approved absence, a locked
/// payroll period — and that sentence reaches the technician unchanged. Online-only: no queue.
class TrasfertaFormScreen extends ConsumerStatefulWidget {
  const TrasfertaFormScreen({
    super.key,
    @visibleForTesting this.initialDate,
    @visibleForTesting this.initialStartTime,
    @visibleForTesting this.initialHours,
  });

  /// Test seams only: the production form opens on today with no start time and no hours.
  final DateTime? initialDate;
  final TimeOfDay? initialStartTime;
  final String? initialHours;

  @override
  ConsumerState<TrasfertaFormScreen> createState() => _TrasfertaFormScreenState();
}

class _TrasfertaFormScreenState extends ConsumerState<TrasfertaFormScreen> {
  final _hoursCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  late DateTime _date;
  TimeOfDay? _startTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.initialDate ?? now;
    _date = DateTime(d.year, d.month, d.day);
    _startTime = widget.initialStartTime;
    _hoursCtrl.text = widget.initialHours ?? '';
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // A trasferta is usually filed after the trip; the server's payroll lock is what closes the
      // past, and its message is shown if the day is already locked.
      firstDate: base.subtract(const Duration(days: 366)),
      lastDate: base.add(const Duration(days: 366)),
    );
    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  static void _refreshList(ProviderContainer container) {
    try {
      container.invalidate(myTrasfertaRequestsProvider);
    } on StateError {
      // Container already disposed — nothing left to refresh.
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final start = _startTime;
    if (start == null) {
      showAppToast(context, message: 'Indica l\'ora di inizio.', tone: ToastTone.error);
      return;
    }
    final hours = parseTrasfertaHours(_hoursCtrl.text);
    final error = trasfertaRulesError(hours: hours, startMinutes: start.hour * 60 + start.minute);
    if (error != null) {
      showAppToast(context, message: error, tone: ToastTone.error);
      return;
    }

    // Online-only: a trasferta the server never saw would never become a worklog.
    if (!ensureOnlineOrWarn(context, ref)) return;

    final reason = _reasonCtrl.text.trim();
    final container = ProviderScope.containerOf(context, listen: false);

    setState(() => _isSaving = true);
    try {
      await ref
          .read(trasfertaRequestApiClientProvider)
          .create(
            date: _date,
            startHour: start.hour,
            startMinute: start.minute,
            hours: hours!,
            reason: reason.isEmpty ? null : reason,
          );
      _refreshList(container);
      if (!mounted) return;
      showAppToast(context, message: 'Trasferta registrata', tone: ToastTone.success);
      context.pop(true);
    } on TrasfertaRuleError catch (e) {
      if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile registrare la trasferta. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_date);
    final start = _startTime;
    final startLabel = start == null
        ? 'Seleziona'
        : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: const ScreenHeaderBar(title: 'Nuova trasferta'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          context.navClearance,
        ),
        children: [
          AdminDateField(label: 'Giorno', value: dateLabel, onTap: _pickDate),
          const SizedBox(height: 16),
          AdminDateField(
            label: 'Ora di inizio',
            value: startLabel,
            onTap: _pickStart,
            icon: LucideIcons.clock,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Ore di viaggio',
            hint: 'Es. 1,5',
            controller: _hoursCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            maxLength: 6,
            counterText: '',
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Motivo (facoltativo)',
            controller: _reasonCtrl,
            maxLines: 2,
            maxLength: 1000,
            counterText: '',
          ),
          const SizedBox(height: 32),
          AppButton(
            label: 'Registra trasferta',
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }
}
