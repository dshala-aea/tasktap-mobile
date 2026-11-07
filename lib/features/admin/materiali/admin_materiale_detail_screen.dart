// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/detail/detail_attachment_row.dart';
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/dio_client.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';

/// Single materiale by id from Drift cache.
final adminMaterialeDetailProvider = StreamProvider.autoDispose.family<MaterialiData?, String>((
  ref,
  id,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..where((m) => m.id.equals(id))).watchSingleOrNull();
});

/// Admin materiale detail — the wave-0 summary shell.
///
/// Hero + `Modifica`, then Movimenti → Sintesi → Documenti. The local mirror carries the article's
/// anagrafica and prices but no stock level, so the movement list itself is not shown: the first
/// section keeps the existing `Giacenze e movimenti` route reachable on demand (no new read at
/// open). Empty sections are hidden by the shell, and the hero owns `Modifica`, so there is no FAB.
class AdminMaterialeDetailScreen extends ConsumerWidget {
  const AdminMaterialeDetailScreen({super.key, required this.materialeId});

  final String materialeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialeAsync = ref.watch(adminMaterialeDetailProvider(materialeId));

    return materialeAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Materiale'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Materiale',
        icon: LucideIcons.alertTriangle,
        title: 'Materiale non disponibile',
        reason: 'Non è stato possibile leggere il materiale da questo telefono.',
        onRetry: () => ref.invalidate(adminMaterialeDetailProvider(materialeId)),
      ),
      data: (materiale) {
        if (materiale == null) {
          // Missing on a synced device means the catalogue no longer holds this id; saying
          // "not synced" there sent the user to wait for an update that would never come.
          return ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false
              ? const DetailScaffold.unavailable(
                  screenTitle: 'Materiale',
                  icon: LucideIcons.cloudOff,
                  title: 'Materiale non disponibile',
                  reason:
                      'Il catalogo materiali non è ancora sincronizzato sul '
                      'dispositivo, quindi questo materiale non può essere '
                      'letto dalla cache locale anche se esiste sul server.',
                )
              : const DetailScaffold.unavailable(
                  screenTitle: 'Materiale',
                  icon: LucideIcons.package,
                  title: 'Materiale non trovato',
                  reason:
                      'Questo materiale non è più nel catalogo: potrebbe essere stato '
                      'eliminato.',
                );
        }
        return _MaterialeDetailBody(materiale: materiale);
      },
    );
  }
}

/// Toggles a materiale's active state — Gap 5 of the feature audit: `isActive` was only ever
/// *displayed* here (and on the list row), never written from mobile, even though the backend's
/// soft-delete (`DELETE /api/materiali/{id}` → `IsActive = false`) and reactivate
/// (`PUT` with `isActive: true`) both already exist.
Future<void> _toggleActive(BuildContext context, WidgetRef ref, MaterialiData materiale) async {
  final deactivating = materiale.isActive;
  final confirmed = await confirmDeleteDialog(
    context,
    title: deactivating ? 'Disattiva materiale' : 'Riattiva materiale',
    message: deactivating
        ? 'Il materiale "${materiale.name}" non sarà più selezionabile nei nuovi '
              'rapporti di intervento o carichi/scarichi. Puoi riattivarlo in qualsiasi momento.'
        : 'Il materiale "${materiale.name}" tornerà selezionabile.',
    confirmLabel: deactivating ? 'Disattiva' : 'Riattiva',
    danger: deactivating,
  );
  if (!confirmed) return;
  if (!context.mounted) return;
  if (!ensureOnlineOrWarn(context, ref)) return;

  try {
    final api = ref.read(adminApiClientProvider);
    if (deactivating) {
      await api.deleteMateriale(materiale.id);
    } else {
      await api.updateMateriale(materiale.id, isActive: true);
    }
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      showAppToast(
        context,
        message: deactivating ? 'Materiale disattivato' : 'Materiale riattivato',
        tone: ToastTone.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: 'Impossibile aggiornare lo stato. Riprova.',
        tone: ToastTone.error,
      );
    }
  }
}

class _MaterialeDetailBody extends ConsumerWidget {
  const _MaterialeDetailBody({required this.materiale});

  final MaterialiData materiale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = _clean(materiale.name) ?? 'Materiale';
    final code = _clean(materiale.code);
    final category = _clean(materiale.category);
    final unit = _clean(materiale.unitOfMeasure);
    final marca = _clean(materiale.marca);
    final description = _clean(materiale.description);
    final imageUrl = _clean(materiale.imageUrl);
    final salePrice = materiale.salePrice;
    final purchasePrice = materiale.purchasePrice;

    // The prototype's hero line is `categoria · pz · prezzo`; stock is not in the mirror, so the
    // unit of measure takes the middle slot and the sale price closes it.
    final heroFacts = <String>[
      ?category,
      ?unit,
      if (salePrice != null) _priceLabel(salePrice),
    ].join(' · ');

    // No fact from the hero is repeated here: the category, unit and sale price stay above, and
    // Sintesi carries the code, brand and purchase price instead.
    final sintesiFacts = <DetailFact>[
      if (code != null) DetailFact(label: 'Codice', value: code),
      if (marca != null) DetailFact(label: 'Marca', value: marca),
      if (purchasePrice != null)
        DetailFact(label: 'Prezzo acquisto', value: _priceLabel(purchasePrice)),
    ];

    return DetailScaffold(
      screenTitle: 'Materiale',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · articolo',
        kicker: 'Summary · articolo',
        title: name,
        status: materiale.isActive
            ? const DetailStatus(label: 'Attivo', tone: DetailStatusTone.good)
            : const DetailStatus(label: 'Inattivo', tone: DetailStatusTone.bad),
        subtitle: heroFacts.isEmpty ? null : heroFacts,
        primaryAction: DetailAction(
          label: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/magazzino/${materiale.id}/modifica');
          },
        ),
      ),
      headerActions: [
        HeaderIconBtn(
          icon: materiale.isActive ? LucideIcons.xCircle : LucideIcons.checkCircle,
          label: materiale.isActive ? 'Disattiva' : 'Riattiva',
          glass: true,
          onTap: () => _toggleActive(context, ref, materiale),
        ),
      ],
      sections: [
        DetailSectionData(
          title: 'Movimenti',
          child: DetailLinkRow(
            title: 'Apri giacenze e movimenti',
            meta: 'Carichi, scarichi, rettifiche',
            onTap: () => context.push('/altro/magazzino/giacenze'),
          ),
        ),
        DetailSectionData(
          title: 'Sintesi',
          trailing: const DetailSectionMeta('Anagrafica e prezzi'),
          isEmpty: sintesiFacts.isEmpty && description == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailFactsGrid(facts: sintesiFacts),
              if (description != null)
                Padding(
                  padding: EdgeInsets.only(top: sintesiFacts.isEmpty ? 0 : AppSpacing.md),
                  child: _MaterialeTextBlock(label: 'Descrizione', value: description),
                ),
            ],
          ),
        ),
        if (imageUrl != null)
          DetailSectionData(
            title: 'Documenti',
            trailing: const DetailSectionMeta('1 foto'),
            child: DetailAttachmentRow(
              name: 'Foto materiale',
              icon: const Icon(LucideIcons.camera, size: 14),
              size: 'FOTO',
              isLast: true,
              onTap: () => _openImage(context, ref, imageUrl),
            ),
          ),
      ],
    );
  }

  /// The photo stays an on-demand attachment: opening it fetches the bytes, so no network image
  /// load fires just by opening this screen.
  Future<void> _openImage(BuildContext context, WidgetRef ref, String url) {
    return openAttachment(
      context,
      dio: ref.read(dioProvider),
      fileName: _fileNameFromUrl(url),
      contentType: 'image/*',
      url: url,
    );
  }
}

/// Long free text under the Sintesi facts grid: a mono label above wrapped prose.
class _MaterialeTextBlock extends StatelessWidget {
  const _MaterialeTextBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            letterSpacing: 0.64,
            color: colors.inkMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, height: 1.45, color: colors.ink),
        ),
      ],
    );
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _priceLabel(double value) => '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _fileNameFromUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments;
  final last = segments == null || segments.isEmpty ? '' : segments.last;
  return last.isEmpty ? 'foto-materiale' : last;
}
