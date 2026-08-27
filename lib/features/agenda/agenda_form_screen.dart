// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/widgets.dart';
import '../../data/agenda/agenda_api_client.dart';
import '../admin/admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Create/edit form for one personal agenda item — title, date, time, priority. See the file doc
/// in `agenda_api_client.dart` for why this is a plain online-only submit (`admin/squadre`'s own
/// pattern), not the Drift-backed forms most of this app uses.
///
/// [item] is the full row passed as GoRouter `extra` when editing — `AgendaController` has no
/// GET-by-id route, only list-by-date and list-by-range, so there is nothing to re-fetch here.
class AgendaFormScreen extends ConsumerStatefulWidget {
  const AgendaFormScreen({super.key, this.item});

  final AgendaItemDto? item;

  @override
  ConsumerState<AgendaFormScreen> createState() => _AgendaFormScreenState();
}

class _AgendaFormScreenState extends ConsumerState<AgendaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  int _priority = 0;
  bool _isSaving = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _titleCtrl.text = item.title;
      _selectedDate = item.date;
      _selectedTime = _parseTimeOfDay(item.timeStart);
      _priority = item.priority;
    }
  }

  static TimeOfDay? _parseTimeOfDay(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(agendaApiClientProvider);
      final timeStart = _selectedTime != null ? _formatTimeOfDay(_selectedTime!) : null;

      if (_isEditing) {
        await api.updateAgendaItem(
          widget.item!.id,
          date: _selectedDate,
          timeStart: timeStart,
          // Passed straight back: AgendaApiClient.updateAgendaItem's doc explains why omitting it
          // would clear it server-side, and this form has no field to edit it with.
          timeEnd: widget.item!.timeEnd,
          title: _titleCtrl.text.trim(),
          priority: _priority,
        );
      } else {
        await api.createAgendaItem(
          date: _selectedDate,
          timeStart: timeStart,
          title: _titleCtrl.text.trim(),
          priority: _priority,
        );
      }

      ref.invalidate(agendaListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Task aggiornato' : 'Task creato'),
            backgroundColor: context.colors.green,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile salvare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy', 'it').format(_selectedDate);
    final timeLabel = _selectedTime?.format(context) ?? 'Nessun orario';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(title: _isEditing ? 'Modifica task' : 'Nuovo task', showBack: true),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            context.navClearance,
          ),
          children: [
            AppTextField(
              label: 'Titolo *',
              controller: _titleCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            AdminDateField(label: 'Data', value: dateLabel, onTap: _pickDate),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Orario',
              value: timeLabel,
              icon: LucideIcons.clock,
              onTap: _pickTime,
            ),
            const SizedBox(height: 16),

            Text(
              'Priorità',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _priority,
              isExpanded: true,
              items: [
                for (var i = 0; i < kAgendaPriorityLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(kAgendaPriorityLabels[i])),
              ],
              onChanged: (p) => p != null ? setState(() => _priority = p) : null,
            ),
            const SizedBox(height: 32),

            VetroButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea task',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
