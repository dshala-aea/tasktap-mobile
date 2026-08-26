// dart format width=100
import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/widgets/vetro_button.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'create_draft.dart';
import 'rapportino_list_providers.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RapportinoViewScreen — read-only view for submitted rapportini (D3b).
// ══════════════════════════════════════════════════════════════════════════════

class RapportinoViewScreen extends ConsumerWidget {
  const RapportinoViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(rapportinoByIdProvider(reportId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              ScreenHeader(title: 'Rapportino', showBack: true),
              EmptyState(
                icon: LucideIcons.xCircle,
                title: 'Errore',
                body: 'Impossibile caricare il rapportino.',
              ),
            ],
          ),
        ),
        data: (draft) {
          if (draft == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(title: 'Rapportino', showBack: true),
                  EmptyState(
                    icon: LucideIcons.fileX,
                    title: 'Rapportino non trovato',
                    body: 'Il rapportino richiesto non è disponibile in cache.',
                  ),
                ],
              ),
            );
          }
          return _RapportinoViewBody(draft: draft);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Body
// ══════════════════════════════════════════════════════════════════════════════

class _RapportinoViewBody extends ConsumerWidget {
  const _RapportinoViewBody({required this.draft});

  final DraftReport draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(rapportinoStaffProvider(draft.id));
    final materialiAsync = ref.watch(rapportinoMaterialiProvider(draft.id));
    final oreLabel = ref.watch(rapportinoOreProvider(draft.id));

    final statusLabel = rapportinoStatusLabel(draft);
    final dateLabel = DateFormat(
      'dd/MM/yyyy',
      'it',
    ).format((draft.updatedAt ?? draft.createdAt).toLocal());

    final staff = staffAsync.valueOrNull ?? [];
    final materiali = materialiAsync.valueOrNull ?? [];

    // Names, not user ids. This joined raw GUIDs — on the read-only view of the document that
    // becomes an invoice, where "who did the work" is the line a customer actually reads back.
    // The colleagues mirror is synced, so this still resolves with the radio off; an id the mirror
    // does not know falls through as itself rather than vanishing from the list.
    final tecnicoLabel = staff.isNotEmpty
        ? staff
              .map((s) => ref.watch(colleagueNameProvider(s.userId)).valueOrNull ?? s.userId)
              .join(', ')
        : (ref.watch(colleagueNameProvider(draft.insertedUserId)).valueOrNull ??
              draft.insertedUserId);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(title: draft.title, showBack: true),
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Header card: StatusPill + date + KeyVal metadata ──────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.sm,
                      AppSpacing.pagePadding,
                      AppSpacing.base,
                    ),
                    child: VetroCard(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                StatusPill(stato: statusLabel, outlined: true),
                                const SizedBox(width: 8),
                                Text(
                                  dateLabel,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, thickness: 1, color: context.colors.borderLight),
                          KeyVal(
                            label: 'Sede',
                            value: draft.locationId.isEmpty ? '—' : draft.locationId,
                          ),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(label: 'Cliente', value: draft.customerId ?? '—'),
                          KeyVal(label: 'Ore', value: oreLabel, showDivider: false),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Rejection banner + rework affordance ────────────────────────
                //
                // The office rejected this report (POST /api/reports/{id}/respingi). The
                // backend has no rejection-reason field to show (checked: ReportsController,
                // ReportService.RespingiAsync, the Report entity itself all take/carry none), so
                // this states the fact plainly instead of inventing a reason. "Rilavora" clones
                // this report's data into a brand-new local draft — see createReworkDraft's own
                // doc comment for why it can't simply reopen this same report id (the backend's
                // state machine only allows Bozza → Inviato).
                if (rapportinoIsRejected(draft))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: _RejectionBanner(draft: draft),
                    ),
                  ),

                // ── Descrizione ───────────────────────────────────────────────
                if (draft.details != null && draft.details!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: VetroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Descrizione'),
                            const SizedBox(height: 4),
                            Text(
                              draft.details!,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: context.colors.ink,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Materiali list ────────────────────────────────────────────
                if (materiali.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: VetroCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                                bottom: AppSpacing.xs,
                              ),
                              child: SectionTitle(title: 'Materiali'),
                            ),
                            ...materiali.map((m) {
                              final name = m.freeTextName ?? m.materialeId ?? '—';
                              final qty = m.quantity.toStringAsFixed(
                                m.quantity.truncateToDouble() == m.quantity ? 0 : 2,
                              );
                              final priceStr = m.unitPrice != null
                                  ? '€${m.unitPrice!.toStringAsFixed(2)}'
                                  : null;
                              final uom = m.unitOfMeasure;
                              final metaSub = [
                                '$qty${uom != null ? ' $uom' : ''}',
                                ?priceStr,
                              ].join(' · ');
                              return ListRow(
                                leading: const RowIconTile(
                                  icon: LucideIcons.package,
                                  size: 36,
                                  iconSize: 18,
                                ),
                                title: name,
                                subtitle: metaSub,
                                showDivider: m != materiali.last,
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Firma cliente ─────────────────────────────────────────────
                if (draft.customerSignatureAllegatoId != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.base,
                      ),
                      child: VetroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Firma cliente'),
                            const SizedBox(height: 8),
                            _SignatureBlock(
                              allegatoId: draft.customerSignatureAllegatoId,
                              signedAt:
                                  draft.customerSignoffAt ??
                                  draft.inviatoAt ??
                                  draft.updatedAt ??
                                  draft.createdAt,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Download PDF ──────────────────────────────────────────────
                // GET /api/Reports/{id}/pdf exists and generates the PDF
                // server-side, but no client code path in lib/ calls it yet
                // (verified by grep — no Dio request to any /pdf route).
                // This button names that gap instead of promising a date
                // nobody has set.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.xl,
                    ),
                    child: VetroButton(
                      label: 'Scarica PDF',
                      icon: const Icon(LucideIcons.download, size: 16),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Il PDF viene generato dal server ma il '
                              "download non è ancora collegato nell'app.",
                            ),
                            duration: Duration(seconds: 4),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Rejection banner + rework button
// ══════════════════════════════════════════════════════════════════════════════

class _RejectionBanner extends ConsumerStatefulWidget {
  const _RejectionBanner({required this.draft});

  final DraftReport draft;

  @override
  ConsumerState<_RejectionBanner> createState() => _RejectionBannerState();
}

class _RejectionBannerState extends ConsumerState<_RejectionBanner> {
  bool _busy = false;

  Future<void> _rilavora() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final newId = await createReworkDraft(ref, widget.draft);
      if (!mounted) return;
      if (newId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Accedi per rilavorare il rapportino.')));
        return;
      }
      context.push(AppRoutes.rapportiniEditor(newId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: context.colors.red.withValues(alpha: 0.12),
        border: Border.all(color: context.colors.red),
        borderRadius: AppRack.freeShape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.xCircle, color: context.colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "L'ufficio ha respinto questo rapportino.",
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // The backend has no motivo/reason field to show here — POST
            // /api/reports/{id}/respingi takes no body and Report carries none — so this says
            // what is true instead of a reason that does not exist yet.
            "Rilavoralo per correggerlo e inviarlo di nuovo. L'ufficio non ha registrato "
            'un motivo per questo rifiuto.',
            style: TextStyle(color: context.colors.ink, fontSize: 13),
          ),
          const SizedBox(height: 12),
          VetroButton(
            label: 'Rilavora',
            icon: const Icon(LucideIcons.penTool),
            onPressed: _busy ? null : _rilavora,
            isLoading: _busy,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Signature block
// ══════════════════════════════════════════════════════════════════════════════

class _SignatureBlock extends ConsumerWidget {
  const _SignatureBlock({required this.allegatoId, required this.signedAt});

  /// The allegato id for the customer signature (not null at call site).
  final String? allegatoId;
  final DateTime signedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(signedAt.toLocal());

    // We can't easily resolve a local path from allegatoId here without
    // querying the allegati table — show a placeholder icon + date stamp.
    // When the allegati watcher is added to view, this can show the image.
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 90),
      decoration: BoxDecoration(
        border: Border.all(
          color: context.colors.borderStrong,
          width: 1.5,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(10),
        color: context.colors.bg1,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.penTool, size: 28, color: context.colors.inkMuted),
          const SizedBox(height: 6),
          Text(
            'Firmato il $signedLabel',
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
          ),
        ],
      ),
    );
  }
}
