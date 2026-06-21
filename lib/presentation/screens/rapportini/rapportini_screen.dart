// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/draft_submission_state.dart';
import '../../../data/sync/submission_queue_watcher.dart';
import '../../providers/report_editor_providers.dart';

/// Rapportini list screen — shows local draft list + "Nuovo rapportino" FAB.
class RapportiniScreen extends ConsumerWidget {
  const RapportiniScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(draftReportRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Rapportini', style: AppTextStyles.titleLarge),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
      ),
      body: StreamBuilder<List<DraftReport>>(
        stream: repo.watchLocalDrafts(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final drafts = snap.data ?? [];
          if (drafts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Nessuna bozza locale.\nPremi + per creare un nuovo rapportino.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _DraftTile(
              draft: drafts[i],
              onTap: () => context.push(
                AppRoutes.rapportiniEditor(drafts[i].id),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNewDraft(context, ref),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuovo rapportino',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _createNewDraft(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(draftReportRepositoryProvider);
    final id = 'draft-${DateTime.now().millisecondsSinceEpoch}';
    await repo.createDraft(
      DraftReportsCompanion.insert(
        id: id,
        tenantId: 'local',
        createdAt: DateTime.now().toUtc(),
        title: 'Nuovo rapportino',
        insertedUserId: 'local-user',
        locationId: '',
        isLocalOnly: const Value(true),
        stato: const Value('Bozza'),
      ),
    );
    if (context.mounted) {
      context.push(AppRoutes.rapportiniEditor(id));
    }
  }
}

class _DraftTile extends ConsumerWidget {
  const _DraftTile({required this.draft, required this.onTap});

  final DraftReport draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subState =
        DraftSubmissionState.fromString(draft.submissionState);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.description_outlined),
        ),
        title: Text(
          draft.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creato: ${_fmt(draft.createdAt)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 2),
            _SubmissionStateBadge(subState: subState),
            if (subState == DraftSubmissionState.failed &&
                draft.submissionError != null)
              Text(
                draft.submissionError!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        isThreeLine: true,
        trailing: subState == DraftSubmissionState.failed
            ? IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                tooltip: 'Riprova invio',
                onPressed: () {
                  final queue = ref.read(realSubmissionQueueProvider);
                  queue.retry(draft.id);
                },
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _SubmissionStateBadge extends StatelessWidget {
  const _SubmissionStateBadge({required this.subState});

  final DraftSubmissionState subState;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (subState) {
      DraftSubmissionState.draft => ('Bozza locale', Colors.grey),
      DraftSubmissionState.readyToSubmit =>
        ('Pronto per invio', Colors.blue),
      DraftSubmissionState.uploadingMedia =>
        ('Caricamento media...', Colors.orange),
      DraftSubmissionState.submitting =>
        ('Invio in corso...', Colors.orange),
      DraftSubmissionState.submitted => ('Inviato', Colors.green),
      DraftSubmissionState.failed => ('Errore invio', Colors.red),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
