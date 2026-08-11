// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'rapportino_list_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
        loading: () =>
            const Center(child: CircularProgressIndicator()),
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
                    body:
                        'Il rapportino richiesto non è disponibile in cache.',
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
    final dateLabel = DateFormat('dd/MM/yyyy', 'it').format(
      (draft.updatedAt ?? draft.createdAt).toLocal(),
    );

    final staff = staffAsync.valueOrNull ?? [];
    final materiali = materialiAsync.valueOrNull ?? [];

    final tecnicoLabel = staff.isNotEmpty
        ? staff.map((s) => s.userId).join(', ')
        : draft.insertedUserId;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: draft.title,
            showBack: true,
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Header card: StatusPill + date + KeyVal metadata ──────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 8, 19, 16),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Row(
                              children: [
                                StatusPill(stato: statusLabel),
                                const SizedBox(width: 8),
                                Text(
                                  dateLabel,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: context.colors.borderLight,
                          ),
                          KeyVal(
                            label: 'Sede',
                            value: draft.locationId.isEmpty
                                ? '—'
                                : draft.locationId,
                          ),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(
                            label: 'Cliente',
                            value: draft.customerId ?? '—',
                          ),
                          KeyVal(
                            label: 'Ore',
                            value: oreLabel,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Descrizione ───────────────────────────────────────────────
                if (draft.details != null && draft.details!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Descrizione'),
                            const SizedBox(height: 4),
                            Text(
                              draft.details!,
                              style: GoogleFonts.manrope(
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
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: SectionTitle(title: 'Materiali'),
                            ),
                            ...materiali.map((m) {
                              final name =
                                  m.freeTextName ?? m.materialeId ?? '—';
                              final qty = m.quantity.toStringAsFixed(
                                m.quantity.truncateToDouble() == m.quantity
                                    ? 0
                                    : 2,
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
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: context.colors.bg3,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    LucideIcons.package,
                                    size: 18,
                                    color: context.colors.inkMuted,
                                  ),
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
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Firma cliente'),
                            const SizedBox(height: 8),
                            _SignatureBlock(
                              allegatoId: draft.customerSignatureAllegatoId,
                              signedAt: draft.customerSignoffAt ??
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
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 24),
                    child: AppButton(
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

                const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
              ],
            ),
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
  const _SignatureBlock({
    required this.allegatoId,
    required this.signedAt,
  });

  /// The allegato id for the customer signature (not null at call site).
  final String? allegatoId;
  final DateTime signedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedLabel = DateFormat('dd/MM/yyyy HH:mm', 'it').format(
      signedAt.toLocal(),
    );

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
          Icon(
            LucideIcons.penTool,
            size: 28,
            color: context.colors.inkMuted,
          ),
          const SizedBox(height: 6),
          Text(
            'Firmato il $signedLabel',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: context.colors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
