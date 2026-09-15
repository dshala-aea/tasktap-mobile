// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// SelezionaCantiereScreen
//
// Full-screen cantiere picker — the technician's entry point into Timbra cantiere when arriving
// with no cantiere context yet (the dashboard's generic "Timbra cantiere" quick action). Used to
// be an inline picker embedded at the top of CantiereTimbraScreen's check-in body
// (`showPicker: true`); extracted to its own screen so every real entry into CantiereTimbraScreen
// now arrives with a cantiereId already resolved — see that screen's own header comment for why.
//
// Reads the same cantieriProvider-backed local Drift mirror the old inline picker read (see that
// provider's own doc comment for why this needs no live network call of its own), with a simple
// client-side name/city filter added on top — there was no search on the old inline picker.
//
// Tapping a row uses `context.pushReplacement`, not `context.push`: this screen has done its one
// job (resolve a cantiere) once a row is tapped, and leaving it on the navigation stack under
// CantiereTimbraScreen would make the back button return to a stale search screen instead of
// straight back to wherever launched the picker (matches how CantiereDetailScreen's own
// "Timbra cantiere" button already knows exactly which cantiere it wants and never shows a
// picker at all).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';
import 'cantiere_timbra_screen.dart' show cantieriProvider;

class SelezionaCantiereScreen extends ConsumerStatefulWidget {
  const SelezionaCantiereScreen({super.key, this.ticketId, this.customerId});

  /// Carried through to the resulting CantiereTimbraScreen when this was reached with ticket
  /// context (mirrors CantiereTimbraScreen's own optional ticketId/customerId) — not exercised by
  /// the dashboard's own generic entry point today, but kept so a future ticket-context caller
  /// doesn't need a second picker screen of its own.
  final String? ticketId;
  final String? customerId;

  @override
  ConsumerState<SelezionaCantiereScreen> createState() => _SelezionaCantiereScreenState();
}

class _SelezionaCantiereScreenState extends ConsumerState<SelezionaCantiereScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(CantieriData c) {
    context.pushReplacement(
      AppRoutes.cantiereTimbraPath(
        cantiereId: c.id,
        ticketId: widget.ticketId,
        customerId: widget.customerId,
      ),
    );
  }

  bool _matches(CantieriData c, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return c.name.toLowerCase().contains(q) || (c.city?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final cantieriAsync = ref.watch(cantieriProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Seleziona cantiere', showBack: true),
            AppSearchBar(
              controller: _searchController,
              hint: 'Cerca per nome o città…',
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              // Same RefreshIndicator+performSync() pattern as cantieri_list_screen.dart, and the
              // same reason its own doc comment gives for wrapping every branch (loading/error/
              // empty/populated) in one Scrollable, not just the populated ListView: a
              // RefreshIndicator only fires over a Scrollable descendant. The copy used to send
              // the technician to "an[other] tab" to pull-to-refresh because this screen had none
              // of its own — it does now.
              child: RefreshIndicator(
                onRefresh: () => ref.read(syncProvider.notifier).performSync(),
                child: cantieriAsync.when(
                loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Center(child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xxxl),
                      child: CircularProgressIndicator(),
                    )),
                  ],
                ),
                error: (e, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    UnavailableState(
                      icon: LucideIcons.hardHat,
                      titolo: 'Impossibile caricare i cantieri',
                      motivo: 'Trascina in basso per aggiornare, oppure riprova tra poco.',
                    ),
                  ],
                ),
                data: (cantieri) {
                  if (cantieri.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        UnavailableState(
                          icon: LucideIcons.hardHat,
                          titolo: 'Nessun cantiere disponibile',
                          motivo:
                              'Non risultano cantieri attivi sincronizzati su questo dispositivo. Se ne '
                              'è stato creato uno di recente, trascina in basso per aggiornare, '
                              'oppure riprova tra poco.',
                        ),
                      ],
                    );
                  }

                  // Prefer cantieri matching the ticket's customerId — same ordering the old
                  // inline picker gave (see _CheckInBody's own "preferred" logic before this).
                  final preferred = widget.customerId != null
                      ? cantieri.where((c) => c.customerId == widget.customerId).toList()
                      : <CantieriData>[];
                  final others = cantieri.where((c) => !preferred.contains(c)).toList();
                  final ordered = [
                    ...preferred,
                    ...others,
                  ].where((c) => _matches(c, _query)).toList();

                  if (ordered.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        UnavailableState(
                          icon: LucideIcons.searchX,
                          titolo: 'Nessun risultato',
                          motivo: 'Nessun cantiere corrisponde a "$_query".',
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      0,
                      AppSpacing.pagePadding,
                      AppSpacing.xxl,
                    ),
                    itemCount: ordered.length,
                    itemBuilder: (context, i) {
                      final c = ordered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard.pressable(
                          onTap: () => _select(c),
                          child: Row(
                            children: [
                              const RowIconTile(icon: LucideIcons.hardHat),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: context.colors.ink,
                                      ),
                                    ),
                                    if (c.city != null && c.city!.isNotEmpty)
                                      Text(
                                        c.city!,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          color: context.colors.inkMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                LucideIcons.chevronRight,
                                size: 16,
                                color: context.colors.inkDisabled,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
