// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/timbratura/sync_queue_repository.dart';
import '../../data/timbratura/timbra_sync_service.dart';
import '../../data/timbratura/work_session_repository.dart' show syncFailedMarker;
import '../../data/sync/sync_service.dart' show appDatabaseProvider;

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>(
  (ref) => SyncQueueRepository(ref.watch(appDatabaseProvider)),
);

final syncQueueProvider = StreamProvider.autoDispose<List<WorkSession>>(
  (ref) => ref.watch(syncQueueRepositoryProvider).watchQueue(),
);

String _kindLabel(String type) => switch (type) {
  'ingresso' => 'Inizio turno',
  'fine' => 'Fine turno',
  'pausa' => 'Pausa',
  'ripresa' => 'Ripresa',
  _ => type,
};

String _two(int n) => n.toString().padLeft(2, '0');

String _when(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.day)}/${_two(l.month)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// "Coda di sincronizzazione": the personal-timbra punches this phone still owes the server
/// (in attesa) or that the server refused (non inviato — rifiutato), with delete and retry.
///
/// Scope: timbra only. Cantiere and ticket-timer queues are not listed here.
///
/// Delete safety — see [SyncQueueRepository.canDelete]: a waiting punch can only be removed when it
/// is the newest waiting one; a refused punch can always be removed. Anything else is refused with a
/// message instead of deleting a chain by surprise.
class SyncQueueScreen extends ConsumerStatefulWidget {
  const SyncQueueScreen({super.key});

  @override
  ConsumerState<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends ConsumerState<SyncQueueScreen> {
  bool _retrying = false;

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(timbraSyncServiceProvider).syncNow(manual: true);
      if (mounted) _say('Sincronizzazione eseguita');
    } catch (_) {
      if (mounted) _say('Sincronizzazione non riuscita, riprova più tardi');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _delete(WorkSession item, List<WorkSession> queue) async {
    if (!SyncQueueRepository.canDelete(item, queue)) {
      _say('Elimina prima le timbrature successive: questa serve a interpretarle.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la timbratura?'),
        content: Text(
          '${_kindLabel(item.eventType)} delle ${_when(item.eventTime)} verrà eliminata '
          'dal telefono e non sarà mai inviata.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(syncQueueRepositoryProvider).delete(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(syncQueueProvider);
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Coda di sincronizzazione', showBack: true),
            Expanded(
              child: queue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const Center(child: Text('Impossibile leggere la coda')),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.pagePadding),
                        child: Text('Nessuna timbratura in coda', textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.pagePadding),
                    children: [
                      for (final item in items)
                        _QueueTile(item: item, onDelete: () => _delete(item, items)),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: _retrying ? null : _retry,
                        child: Text(_retrying ? 'Invio in corso…' : 'Riprova ora'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.item, required this.onDelete});

  final WorkSession item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final failed = item.notes == syncFailedMarker;
    final kind = _kindLabel(item.eventType);
    final state = failed ? 'non inviato — rifiutato' : 'in attesa';
    return Card(
      child: ListTile(
        leading: Icon(failed ? LucideIcons.alertTriangle : LucideIcons.clock),
        title: Text('$kind · ${_when(item.eventTime)}'),
        subtitle: Text(state),
        trailing: IconButton(
          tooltip: 'Elimina $kind delle ${_when(item.eventTime)}',
          icon: const Icon(LucideIcons.trash2),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
