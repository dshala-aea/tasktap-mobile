// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_rack.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ferie/absence_request_api_client.dart';
import '../admin/admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// New-request form. Create-only — AbsenceRequestsController has no update endpoint, only
/// create/approve/reject/cancel, so this never edits an existing row.
class FeriePermessiFormScreen extends ConsumerStatefulWidget {
  const FeriePermessiFormScreen({super.key});

  @override
  ConsumerState<FeriePermessiFormScreen> createState() => _FeriePermessiFormScreenState();
}

class _FeriePermessiFormScreenState extends ConsumerState<FeriePermessiFormScreen> {
  final _reasonCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  int _type = 0; // Ferie
  bool _partialTime = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  static String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  bool get _partialTimeValid =>
      !_partialTime ||
      (_type == 1 && _isSameDay(_startDate, _endDate) && _startTime != null && _endTime != null);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _save() async {
    if (!_partialTimeValid) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(absenceRequestApiClientProvider)
          .create(
            type: _type,
            startDate: _startDate,
            endDate: _endDate,
            startTime: _partialTime && _startTime != null ? _formatTimeOfDay(_startTime!) : null,
            endTime: _partialTime && _endTime != null ? _formatTimeOfDay(_endTime!) : null,
            reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
          );

      ref.invalidate(myAbsenceRequestsProvider);

      if (mounted) {
        showAppToast(context, message: 'Richiesta inviata', tone: ToastTone.success);
        context.pop(true);
      }
    } on AbsenceRequestValidationError catch (e) {
      if (mounted) {
        showAppToast(context, message: e.detail, tone: ToastTone.error);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile inviare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_startDate);
    final endLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_endDate);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: const ScreenHeaderBar(title: 'Nuova richiesta', showBack: true),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          AppSpacing.pagePadding,
          context.navClearance,
        ),
        children: [
          Text(
            'Tipo',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _type,
            isExpanded: true,
            items: [
              for (var i = 0; i < kAbsenceTypeLabels.length; i++)
                DropdownMenuItem(value: i, child: Text(kAbsenceTypeLabels[i])),
            ],
            onChanged: (t) => t != null ? setState(() => _type = t) : null,
          ),
          const SizedBox(height: 16),

          AdminDateField(label: 'Data inizio', value: startLabel, onTap: _pickStartDate),
          const SizedBox(height: 16),
          AdminDateField(label: 'Data fine', value: endLabel, onTap: _pickEndDate),
          const SizedBox(height: 16),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Permesso orario (solo un giorno singolo)'),
            value: _partialTime,
            onChanged: (v) => setState(() => _partialTime = v),
          ),
          if (_partialTime) ...[
            const SizedBox(height: 8),
            AdminDateField(
              label: 'Ora inizio',
              value: _startTime?.format(context) ?? 'Seleziona',
              onTap: () => _pickTime(true),
            ),
            const SizedBox(height: 16),
            AdminDateField(
              label: 'Ora fine',
              value: _endTime?.format(context) ?? 'Seleziona',
              onTap: () => _pickTime(false),
            ),
          ],
          const SizedBox(height: 16),

          AppTextField(label: 'Motivo (facoltativo)', controller: _reasonCtrl, maxLines: 2),
          const SizedBox(height: 32),

          AppButton(
            label: 'Invia richiesta',
            onPressed: _isSaving || !_partialTimeValid ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }
}
