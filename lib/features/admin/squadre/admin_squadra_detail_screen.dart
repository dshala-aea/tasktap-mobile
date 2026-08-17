// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Fetches squadra detail with membri from backend API.
final adminSquadraDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, id) async {
    final api = ref.watch(adminApiClientProvider);
    return api.fetchSquadraDetail(id);
  },
);

/// Admin squadra detail — shows membri, allows add/remove.
class AdminSquadraDetailScreen extends ConsumerWidget {
  const AdminSquadraDetailScreen({super.key, required this.squadra});

  final Map<String, dynamic> squadra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminSquadraDetailProvider(squadra['id'] as String));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.userPlus,
          tooltip: 'Aggiungi membro',
          onPressed: () => _showAddMemberSheet(context, ref),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (detail) {
          final data = detail ?? squadra;
          final membri = (data['membri'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          return _SquadraDetailBody(squadra: data, membri: membri);
        },
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddMemberSheet(
        squadraId: squadra['id'] as String,
        api: ref.read(adminApiClientProvider),
      ),
    );
  }
}

class _SquadraDetailBody extends StatelessWidget {
  const _SquadraDetailBody({required this.squadra, required this.membri});

  final Map<String, dynamic> squadra;
  final List<Map<String, dynamic>> membri;

  @override
  Widget build(BuildContext context) {
    final nome = squadra['nome'] as String? ?? '';
    final descrizione = squadra['descrizione'] as String? ?? '';
    final spec = squadra['specializzazione'] as String? ?? '';
    final note = squadra['note'] as String? ?? '';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: nome,
            subtitle: spec.isNotEmpty ? spec : '',
            showBack: true,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Modifica'))],
                onSelected: (v) {
                  if (v == 'edit') {
                    context.push('/altro/squadre/${squadra['id']}/modifica', extra: squadra);
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (descrizione.isNotEmpty) _InfoRow(label: 'Descrizione', value: descrizione),
                _InfoRow(label: 'Specializzazione', value: spec.isNotEmpty ? spec : '—'),
                if (note.isNotEmpty) _InfoRow(label: 'Note', value: note),
              ],
            ),
          ),
        ),
        // ── Membri section ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 8),
            child: Text(
              'MEMBRI (${membri.length})',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: context.colors.inkMuted, letterSpacing: 1.2),
            ),
          ),
        ),
        if (membri.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(19),
              child: Text('Nessun membro nella squadra.'),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              final membro = membri[i];
              final userId = membro['userId'] as String? ?? '';
              final ruolo = membro['ruolo'] as String? ?? 'Membro';
              return ListRow(
                leading: const CircleAvatar(radius: 18, child: Icon(LucideIcons.user, size: 18)),
                title: userId.substring(0, 8),
                subtitle: ruolo,
                meta: IconButton(
                  icon: const Icon(LucideIcons.userMinus, size: 18),
                  onPressed: () => _removeMember(context, userId),
                ),
                showDivider: i < membri.length - 1,
              );
            }, childCount: membri.length),
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }

  Future<void> _removeMember(BuildContext context, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi membro'),
        content: const Text('Vuoi rimuovere questo membro dalla squadra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        final api = ProviderScope.containerOf(context).read(adminApiClientProvider);
        await api.removeSquadraMember(squadra['id'] as String, userId);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Membro rimosso')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
        }
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: context.colors.inkMuted, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to add a member to a squadra.
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.squadraId, required this.api});

  final String squadraId;
  final AdminApiClient api;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  String? _selectedUserId;
  String _ruolo = 'Membro';
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _technicians = [];

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    try {
      final techs = await widget.api.fetchTechnicians();
      if (mounted) {
        setState(() {
          _technicians = techs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedUserId == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.api.addSquadraMember(widget.squadraId, userId: _selectedUserId!, ruolo: _ruolo);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Membro aggiunto')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(19, 19, 19, MediaQuery.of(context).viewInsets.bottom + 19),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aggiungi membro', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            AppFieldShell(
              label: 'Tecnico *',
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _selectedUserId,
                items: _technicians
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
              ),
            ),
          const SizedBox(height: 16),
          AppFieldShell(
            label: 'Ruolo',
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use — controlled field, needs value not initialValue
              value: _ruolo,
              items: const [
                DropdownMenuItem(value: 'Membro', child: Text('Membro')),
                DropdownMenuItem(value: 'TeamLead', child: Text('Team Lead')),
              ],
              onChanged: (v) => setState(() => _ruolo = v ?? 'Membro'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isSaving ? 'Salvataggio…' : 'Aggiungi',
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
