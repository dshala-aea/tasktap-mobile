// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/auth/access.dart';
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
import '../../../data/entitlements/entitlement_providers.dart';
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
/// anagrafica and prices but no stock level or image: Movimenti opens the existing stock screen on
/// demand and Documenti resolves the live photo only on tap (the sync payload never carries
/// `Materiali.imageUrl`). Empty data sections are hidden by the shell, and the hero owns
/// `Modifica`, so there is no FAB.
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
          return ref.watch(hasSyncedAtLeastOnceProvider).value == false
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
    final salePrice = materiale.salePrice;
    final purchasePrice = materiale.purchasePrice;
    final canWrite = capabilityHeld(
      ref.watch(cachedEntitlementProvider).value,
      'magazzino.article.write',
    );

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
          enabled: canWrite,
          disabledReason: canWrite ? null : noPermissionReason,
          onPressed: () async {
            await context.push<bool>('/altro/magazzino/${materiale.id}/modifica');
          },
        ),
      ),
      headerActions: [
        if (canWrite)
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
            title: 'Apri magazzino',
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
        DetailSectionData(
          title: 'Documenti',
          trailing: const DetailSectionMeta('Foto'),
          child: DetailAttachmentRow(
            name: 'Apri foto materiale',
            icon: const Icon(LucideIcons.camera, size: 14),
            isLast: true,
            onTap: () => _openPhoto(context, ref),
          ),
        ),
      ],
    );
  }

  /// The photo is resolved only when the user asks for it: the sync payload never carries
  /// `Materiali.imageUrl`, so the live detail endpoint (already used by the edit form) is read on
  /// tap. No network call fires just by opening this screen.
  Future<void> _openPhoto(BuildContext context, WidgetRef ref) async {
    Map<String, dynamic>? detail;
    try {
      detail = await ref.read(adminApiClientProvider).fetchMaterialeDetail(materiale.id);
    } catch (_) {
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Foto non disponibile offline: riprova quando sei online.',
          tone: ToastTone.error,
        );
      }
      return;
    }
    if (!context.mounted) return;

    final url = _clean(detail?['imageContentUrl'] as String?);
    if (url == null) {
      showAppToast(context, message: 'Nessuna foto per questo materiale.', tone: ToastTone.warning);
      return;
    }

    await openAttachment(
      context,
      dio: ref.read(dioProvider),
      fileName: _photoFileName(url),
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

String _photoFileName(String url) {
  final segments = Uri.tryParse(url)?.pathSegments;
  final last = segments == null || segments.isEmpty ? '' : segments.last;
  // API content paths end in a bare segment such as `image`; a name without an extension would
  // show up as the viewer's title. Fall back to a friendly name in that case.
  return last.isEmpty || !last.contains('.') ? 'foto-materiale.jpg' : last;
}
