// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/location/geocoding_service.dart' show GeocodedPoint;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/geo_map_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../magazzino/magazzino_providers.dart';
import '../../ticket/steps/step_assegnazione.dart' show techniciansProvider;

/// Admin magazzino detail — the wave-0 summary shell: SummaryHero + `Modifica`, then
/// Sintesi (sotto scorta) → Movimenti → Documenti. No FAB: the hero owns the edit action.
///
/// The warehouse travels as `extra` from the list row that pushed here (there is no
/// `GET /api/magazzino/{id}` call site to re-fetch it), so the screen reads no entity at open.
/// Stock and movements are online-only and arrive through the existing giacenze/movimenti
/// providers, but only after a tap: a warehouse detail must not spend two network reads just to
/// open, and a stale quantity is worse than an explicit "load from the server" affordance.
///
/// The prototype's `148 articoli` total and its `6 sotto scorta` hero status are not in the
/// warehouse entity. The short-stock count is shown once the on-demand read lands; the article
/// total is dropped rather than fetched with a second request just to fill a subtitle.
class AdminMagazzinoDetailScreen extends ConsumerStatefulWidget {
  const AdminMagazzinoDetailScreen({super.key, required this.magazzino});

  final MagazzinoDto? magazzino;

  @override
  ConsumerState<AdminMagazzinoDetailScreen> createState() => _AdminMagazzinoDetailScreenState();
}

class _AdminMagazzinoDetailScreenState extends ConsumerState<AdminMagazzinoDetailScreen> {
  /// Both sections are opt-in: watching either provider before the first tap would turn opening
  /// the detail into a network read, which this screen deliberately does not do.
  bool _scorteRequested = false;
  bool _movimentiRequested = false;

  @override
  void didUpdateWidget(covariant AdminMagazzinoDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magazzino?.id != widget.magazzino?.id) {
      _scorteRequested = false;
      _movimentiRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mag = widget.magazzino;
    if (mag == null) {
      return const DetailScaffold.unavailable(
        screenTitle: 'Magazzino',
        icon: LucideIcons.warehouse,
        title: 'Magazzino non disponibile',
        reason: 'Torna all\'elenco e riapri questo magazzino.',
      );
    }

    final tipo = _clean(mag.tipo);
    final address = _clean(mag.indirizzo);
    final note = _clean(mag.note);
    final assignedId = _clean(mag.assegnatoUserId);
    // Preserve the old screen's live technician read, but only for a Furgone that has an
    // assignee: a Sede never needs it, and watching it there would add a read at open.
    final assignedName = assignedId == null
        ? null
        : ref
              .watch(techniciansProvider)
              .valueOrNull
              ?.cast<Map<String, dynamic>>()
              .where((t) => t['id'] == assignedId)
              .map((t) => t['displayName'] as String? ?? t['email'] as String? ?? assignedId)
              .firstOrNull;

    final scorteQuery = GiacenzeQuery(magazzinoId: mag.id, soloSottoScorta: true, pageSize: 20);
    final scorteAsync = _scorteRequested ? ref.watch(giacenzeProvider(scorteQuery)) : null;
    final movimentiAsync = _movimentiRequested
        ? ref.watch(movimentiMagazzinoProvider(mag.id))
        : null;

    final heroFacts = <String>[
      ?tipo,
      ?address,
      if (assignedId != null) 'Assegnato a ${assignedName ?? assignedId}',
    ].join(' · ');

    return DetailScaffold(
      screenTitle: 'Magazzino',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · magazzino',
        kicker: 'Summary · magazzino',
        title: _clean(mag.nome) ?? 'Magazzino',
        status: mag.isActive
            ? const DetailStatus(label: 'Attivo', tone: DetailStatusTone.good)
            : const DetailStatus(label: 'Inattivo', tone: DetailStatusTone.bad),
        subtitle: heroFacts.isEmpty ? null : heroFacts,
        primaryAction: DetailAction(
          label: 'Modifica',
          onPressed: () async {
            final saved = await context.push<bool>(
              '/altro/magazzino/magazzini/${mag.id}/modifica',
              extra: mag,
            );
            // The screen holds a static snapshot passed via `extra`, so it cannot show the edit
            // it was just used to make; the form already refreshes `magazziniProvider` behind
            // this screen, so pop back to the list rather than keep pre-edit values.
            if (saved == true && context.mounted) context.pop();
          },
        ),
      ),
      sections: [
        DetailSectionData(
          title: 'Sintesi',
          trailing: _sintesiTrailing(scorteAsync),
          child: _sintesiContent(ref, note: note, query: scorteQuery, async: scorteAsync),
        ),
        DetailSectionData(
          title: 'Movimenti',
          trailing: _movimentiTrailing(movimentiAsync),
          child: _movimentiContent(ref, magazzinoId: mag.id, async: movimentiAsync),
        ),
        DetailSectionData(
          title: 'Documenti',
          isEmpty: address == null,
          trailing: const DetailSectionMeta('Mappa'),
          child: GeoMapCard(
            key: const Key('magazzino-map'),
            pointAsync: AsyncValue<GeocodedPoint?>.data(null),
            address: address ?? '',
          ),
        ),
      ],
    );
  }

  Widget? _sintesiTrailing(AsyncValue<PagedResult<GiacenzaDto>>? async) {
    if (async == null) return const DetailSectionMeta('Sotto scorta');
    return async.when(
      loading: () => const DetailSectionMeta('Caricamento'),
      error: (_, _) => const DetailSectionMeta('Non disponibile'),
      data: (page) => DetailSectionMeta('${page.totaleElementi} sotto scorta'),
    );
  }

  Widget? _movimentiTrailing(AsyncValue<PagedResult<MovimentoDto>>? async) {
    if (async == null) return const DetailSectionMeta('Ultimi carichi e scarichi');
    return async.when(
      loading: () => const DetailSectionMeta('Caricamento'),
      error: (_, _) => const DetailSectionMeta('Non disponibile'),
      data: (page) => DetailSectionMeta(
        '${page.totaleElementi} '
        '${page.totaleElementi == 1 ? 'movimento' : 'movimenti'}',
      ),
    );
  }

  Widget _sintesiContent(
    WidgetRef ref, {
    required String? note,
    required GiacenzeQuery query,
    required AsyncValue<PagedResult<GiacenzaDto>>? async,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (async == null)
          DetailLinkRow(
            key: const Key('magazzino-scorte-load'),
            title: 'Controlla le scorte',
            meta: 'Carica dal server',
            showDivider: false,
            onTap: () => setState(() => _scorteRequested = true),
          )
        else
          async.when(
            loading: () => const _LoadingRow(label: 'Caricamento scorte…'),
            error: (_, _) => _ErrorBlock(
              message:
                  'Le scorte si leggono solo online: un valore vecchio è '
                  'peggio di nessun valore.',
              onRetry: () => ref.invalidate(giacenzeProvider(query)),
            ),
            data: (page) => page.elementi.isEmpty
                ? const DetailLinkRow(
                    title: 'Nessuna scorta sotto minimo',
                    meta: 'Tutte sopra soglia',
                    showDivider: false,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < page.elementi.length; i++)
                        DetailLinkRow(
                          key: ValueKey('magazzino-scorta-${page.elementi[i].id}'),
                          title: _giacenzaTitle(page.elementi[i]),
                          meta: _giacenzaMeta(page.elementi[i]),
                          showDivider: i < page.elementi.length - 1,
                        ),
                    ],
                  ),
          ),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.md),
          _TextBlock(label: 'Note', value: note),
        ],
      ],
    );
  }

  Widget _movimentiContent(
    WidgetRef ref, {
    required String magazzinoId,
    required AsyncValue<PagedResult<MovimentoDto>>? async,
  }) {
    if (async == null) {
      return DetailLinkRow(
        key: const Key('magazzino-movimenti-load'),
        title: 'Carica i movimenti',
        meta: 'Carica dal server',
        showDivider: false,
        onTap: () => setState(() => _movimentiRequested = true),
      );
    }

    return async.when(
      loading: () => const _LoadingRow(label: 'Caricamento movimenti…'),
      error: (_, _) => _ErrorBlock(
        message:
            'Lo storico movimenti si legge solo online. Riprova quando hai '
            'segnale.',
        onRetry: () => ref.invalidate(movimentiMagazzinoProvider(magazzinoId)),
      ),
      data: (page) => page.elementi.isEmpty
          ? const DetailLinkRow(
              title: 'Nessun movimento recente',
              meta: 'Nessun carico o scarico',
              showDivider: false,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < page.elementi.length; i++)
                  DetailLinkRow(
                    key: ValueKey('magazzino-movimento-${page.elementi[i].id}'),
                    title: _movimentoTitle(page.elementi[i]),
                    meta: _movimentoMeta(page.elementi[i]),
                    showDivider: i < page.elementi.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DetailLinkRow(
      title: label,
      showDivider: false,
      trailing: const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineAlert(message: message, icon: LucideIcons.wifiOff),
        const SizedBox(height: AppSpacing.sm),
        DetailLinkRow(
          title: 'Riprova',
          meta: 'Tocca per ricaricare',
          showDivider: false,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.value});

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

final DateFormat _movementDateFormat = DateFormat('dd/MM HH:mm');

String _giacenzaTitle(GiacenzaDto giacenza) =>
    _clean(giacenza.materialeNome) ?? giacenza.materialeId;

String _giacenzaMeta(GiacenzaDto giacenza) {
  final qty = _quantity(giacenza.quantita);
  final unit = _clean(giacenza.unitOfMeasure);
  final minimum = giacenza.stockMinimo;
  return [
    unit == null ? qty : '$qty $unit',
    if (minimum != null) 'min ${_quantity(minimum)}',
  ].join(' · ');
}

String _movimentoTitle(MovimentoDto movimento) =>
    _clean(movimento.materialeNome) ?? movimento.materialeId;

String _movimentoMeta(MovimentoDto movimento) {
  final where = [
    _clean(movimento.magazzinoOrigineNome),
    _clean(movimento.magazzinoDestinazioneNome),
  ].whereType<String>().join(' → ');
  return [
    if (_clean(movimento.tipo) != null) _clean(movimento.tipo)!,
    if (where.isNotEmpty) where,
    _quantity(movimento.quantita),
    _movementDateFormat.format(movimento.data.toLocal()),
  ].join(' · ');
}

String _quantity(double value) =>
    value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
