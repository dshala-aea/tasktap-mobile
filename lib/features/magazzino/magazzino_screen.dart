import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/utils/error_message.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/vetro_card.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/magazzino/magazzino_api_client.dart';
import '../../data/materiali/materiale_barcode_lookup.dart';
import 'magazzino_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Magazzino: the catalogue, current stock, and recent movements.
///
/// ## What changed and why the old header comment was wrong
///
/// This file carried a `TODO(backend)` saying the materiali catalogue was never fetched and
/// `db.materiali` "stays empty forever". That stopped being true when sync started filling the
/// mirror, and the stale note had a worse consequence than being out of date: the empty branch
/// below rendered an [UnavailableState] reading *"L'app non scarica ancora l'elenco materiali"*
/// for **any** empty result — including a search that simply matched nothing. A technician typing
/// a part number that is not stocked was told the app was broken.
///
/// Empty-because-no-match and empty-because-no-data are now different states, and the second one
/// names the real reason.
///
/// Giacenze and Movimenti are new here. `GET /api/app/magazzino/giacenze` and `/movimenti` have
/// been live all along with no call site, which is why this screen could show *what exists*
/// without ever showing *how many are left* — the number the technician came for.
enum _MagazzinoTab { articoli, giacenze, movimenti }

class MagazzinoScreen extends StatefulWidget {
  const MagazzinoScreen({super.key});

  @override
  State<MagazzinoScreen> createState() => _MagazzinoScreenState();
}

class _MagazzinoScreenState extends State<MagazzinoScreen> {
  _MagazzinoTab _tab = _MagazzinoTab.articoli;
  String _query = '';
  String? _activeCategory;
  bool _soloSottoScorta = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _MagazzinoBody(
          tab: _tab,
          query: _query,
          activeCategory: _activeCategory,
          soloSottoScorta: _soloSottoScorta,
          searchCtrl: _searchCtrl,
          onTabChanged: (t) => setState(() => _tab = t),
          onQueryChanged: (q) => setState(() => _query = q),
          onSottoScortaChanged: (v) => setState(() => _soloSottoScorta = v),
          onCategoryChanged: (cat) => setState(() {
            _activeCategory = _activeCategory == cat ? null : cat;
          }),
        ),
      ),
    );
  }
}

class _MagazzinoBody extends ConsumerWidget {
  const _MagazzinoBody({
    required this.tab,
    required this.query,
    required this.activeCategory,
    required this.soloSottoScorta,
    required this.searchCtrl,
    required this.onTabChanged,
    required this.onQueryChanged,
    required this.onSottoScortaChanged,
    required this.onCategoryChanged,
  });

  final _MagazzinoTab tab;
  final String query;
  final String? activeCategory;
  final bool soloSottoScorta;
  final TextEditingController searchCtrl;
  final ValueChanged<_MagazzinoTab> onTabChanged;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onSottoScortaChanged;
  final ValueChanged<String> onCategoryChanged;

  static final _priceFormat = NumberFormat.currency(
    locale: 'it',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(title: 'Magazzino', showBack: true),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppTabs(
              tabs: const [
                AppTab(label: 'Articoli'),
                AppTab(label: 'Giacenze'),
                AppTab(label: 'Movimenti'),
              ],
              selectedIndex: tab.index,
              onSelected: (i) => onTabChanged(_MagazzinoTab.values[i]),
            ),
          ),
        ),
        if (tab != _MagazzinoTab.movimenti)
          SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    controller: searchCtrl,
                    hint: tab == _MagazzinoTab.articoli
                        ? 'Cerca per nome, codice o marca…'
                        : 'Cerca materiale…',
                    onChanged: onQueryChanged,
                    // Own right margin dropped to a small gap — the scan button follows it now,
                    // rather than the field sitting flush against the screen edge.
                    margin: const EdgeInsets.fromLTRB(19, 0, 8, 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 12),
                  child: IconButton(
                    icon: const Icon(LucideIcons.scanLine),
                    tooltip: 'Scansiona codice',
                    onPressed: () async {
                      final match = await scanForMateriale(context, ref, title: 'Cerca materiale');
                      if (match == null) return;
                      searchCtrl.text = match.code;
                      onQueryChanged(match.code);
                    },
                  ),
                ),
              ],
            ),
          ),
        ...switch (tab) {
          _MagazzinoTab.articoli => _articoliSlivers(context, ref),
          _MagazzinoTab.giacenze => _giacenzeSlivers(context, ref),
          _MagazzinoTab.movimenti => _movimentiSlivers(context, ref),
        },
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }

  // ── Articoli: the catalogue, from the offline mirror ───────────────────────

  List<Widget> _articoliSlivers(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(materialiCatalogProvider);
    final categories = ref.watch(materialiCategoriesProvider).valueOrNull ?? [];
    final allMateriali = materialiAsync.valueOrNull ?? [];

    final filtered = allMateriali.where((m) {
      if (activeCategory != null && m.category != activeCategory) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.code.toLowerCase().contains(q) ||
          (m.marca?.toLowerCase().contains(q) ?? false);
    }).toList();

    return [
      if (categories.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.md,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: AppChip(
                      label: 'Tutti',
                      active: activeCategory == null,
                      onTap: () {
                        if (activeCategory != null)
                          onCategoryChanged(activeCategory!);
                      },
                    ),
                  ),
                  ...categories.map(
                    (cat) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: AppChip(
                        label: cat,
                        active: activeCategory == cat,
                        onTap: () => onCategoryChanged(cat),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (materialiAsync.isLoading)
        const SliverToBoxAdapter(child: _Spinner())
      // The two empty states are different claims and no longer share one message. An empty
      // catalogue means sync has not delivered it; an empty *filter* means this technician's
      // search matched nothing, which is not a fault at all.
      else if (allMateriali.isEmpty)
        SliverToBoxAdapter(
          child: UnavailableState(
            icon: LucideIcons.package,
            titolo: 'Catalogo non ancora sincronizzato',
            motivo:
                "L'elenco materiali arriva con la sincronizzazione. "
                'Se hai appena effettuato l\'accesso, attendi il primo aggiornamento.',
          ),
        )
      else if (filtered.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            icon: LucideIcons.searchX,
            title: 'Nessun articolo trovato',
            body: 'Nessun materiale corrisponde ai filtri attivi.',
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _MaterialeRow(
              materiale: filtered[i],
              priceFormat: _priceFormat,
            ),
            childCount: filtered.length,
          ),
        ),
    ];
  }

  // ── Giacenze: current stock, read through to the server ────────────────────

  List<Widget> _giacenzeSlivers(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      giacenzeProvider(
        GiacenzeQuery(
          q: query.isEmpty ? null : query,
          soloSottoScorta: soloSottoScorta,
        ),
      ),
    );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            0,
            AppSpacing.pagePadding,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              AppChip(
                label: 'Tutte',
                active: !soloSottoScorta,
                onTap: () => onSottoScortaChanged(false),
              ),
              const SizedBox(width: 8),
              AppChip(
                label: 'Sotto scorta',
                active: soloSottoScorta,
                onTap: () => onSottoScortaChanged(true),
              ),
            ],
          ),
        ),
      ),
      async.when(
        loading: () => const SliverToBoxAdapter(child: _Spinner()),
        // Stock is the one figure worth refusing to guess at. No cached fallback, and the reason
        // is named rather than dressed as an empty list.
        error: (e, _) => SliverToBoxAdapter(
          child: UnavailableState(
            icon: LucideIcons.wifiOff,
            titolo: 'Giacenze non disponibili',
            motivo:
                'Le quantità in magazzino si leggono solo online, perché un valore '
                'vecchio è peggio di nessun valore. Riprova quando hai segnale.',
          ),
        ),
        data: (page) => page.elementi.isEmpty
            ? SliverToBoxAdapter(
                child: EmptyState(
                  icon: soloSottoScorta
                      ? LucideIcons.checkCircle
                      : LucideIcons.searchX,
                  title: soloSottoScorta
                      ? 'Nessuna scorta sotto minimo'
                      : 'Nessuna giacenza',
                  body: soloSottoScorta
                      ? 'Tutti i materiali sono sopra la soglia minima.'
                      : 'Nessuna giacenza corrisponde alla ricerca.',
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _GiacenzaRow(giacenza: page.elementi[i]),
                  childCount: page.elementi.length,
                ),
              ),
      ),
    ];
  }

  // ── Movimenti ──────────────────────────────────────────────────────────────

  List<Widget> _movimentiSlivers(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movimentiProvider);

    return [
      async.when(
        loading: () => const SliverToBoxAdapter(child: _Spinner()),
        error: (e, _) => SliverToBoxAdapter(
          child: UnavailableState(
            icon: LucideIcons.wifiOff,
            titolo: 'Movimenti non disponibili',
            motivo:
                'Lo storico movimenti si legge solo online. Riprova quando hai segnale.',
          ),
        ),
        data: (page) => page.elementi.isEmpty
            ? SliverToBoxAdapter(
                child: EmptyState(
                  icon: LucideIcons.arrowLeftRight,
                  title: 'Nessun movimento',
                  body: 'Non risultano movimenti di magazzino recenti.',
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _MovimentoRow(movimento: page.elementi[i]),
                  childCount: page.elementi.length,
                ),
              ),
      ),
    ];
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.xxxl),
      child: CircularProgressIndicator(),
    ),
  );
}

// ── Rows ─────────────────────────────────────────────────────────────────────

class _MaterialeRow extends StatelessWidget {
  const _MaterialeRow({required this.materiale, required this.priceFormat});

  final MaterialiData materiale;
  final NumberFormat priceFormat;

  @override
  Widget build(BuildContext context) {
    final codeMarca = [
      materiale.code,
      if (materiale.marca != null && materiale.marca!.isNotEmpty)
        materiale.marca,
    ].join(' · ');

    final subParts = [
      if (materiale.unitOfMeasure != null &&
          materiale.unitOfMeasure!.isNotEmpty)
        materiale.unitOfMeasure!,
      if (materiale.category != null && materiale.category!.isNotEmpty)
        materiale.category!,
    ].join(' · ');

    final priceLabel = materiale.salePrice != null
        ? priceFormat.format(materiale.salePrice)
        : null;

    return ListRow(
      leading: _Tile(icon: LucideIcons.package),
      title: materiale.name,
      subtitle: codeMarca.isNotEmpty ? '$codeMarca · $subParts' : subParts,
      meta: priceLabel != null
          ? Text(
              priceLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            )
          : null,
    );
  }
}

class _GiacenzaRow extends ConsumerWidget {
  const _GiacenzaRow({required this.giacenza});

  final GiacenzaDto giacenza;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final qty = giacenza.quantita;
    final qtyLabel = qty == qty.truncateToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(1);
    final unit = giacenza.unitOfMeasure;

    return ListRow(
      // Below-minimum lines take the danger ledge, not the accent strap: the strap means
      // "selected or needs finishing", and a short stock line is a warning, not that. Overloading
      // the strap here would cost it the meaning it has everywhere else.
      ledgeColor: giacenza.sottoScorta ? c.red : null,
      leading: _Tile(
        icon: giacenza.sottoScorta
            ? LucideIcons.alertTriangle
            : LucideIcons.package,
        tint: giacenza.sottoScorta ? c.red : null,
      ),
      title: giacenza.materialeNome ?? giacenza.materialeId,
      subtitle: [
        if (giacenza.magazzinoNome != null) giacenza.magazzinoNome!,
        if (giacenza.stockMinimo != null)
          'min ${giacenza.stockMinimo!.toStringAsFixed(0)}',
      ].join(' · '),
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            unit == null || unit.isEmpty ? qtyLabel : '$qtyLabel $unit',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: giacenza.sottoScorta ? c.red : c.ink,
            ),
          ),
          // Never colour alone: the short state is also stated in words.
          if (giacenza.sottoScorta)
            Text(
              'sotto scorta',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.red,
              ),
            ),
        ],
      ),
      // Gap 3/4 of the feature audit: this row used to be read-only — the app could show a
      // shortage but never let a technician act on it from here.
      onTap: () => _showActions(context, ref),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final hasStockMinimo = giacenza.stockMinimo != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // VetroCard as the sheet shell, ListRow for each action — same vocabulary the rest of
          // the app's action lists use (ticket_detail_screen's attachment/report rows), rather
          // than the plain ListTiles this sheet used to hand-roll.
          child: VetroCard(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListRow(
                  leading: Icon(LucideIcons.arrowDownToLine, size: 20, color: ctx.colors.green),
                  title: 'Carico',
                  subtitle: 'Aggiungi quantità a questo magazzino',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMovimentoDialog(context, ref, MovimentoKind.carico);
                  },
                ),
                ListRow(
                  leading: Icon(LucideIcons.arrowUpFromLine, size: 20, color: ctx.colors.amber),
                  title: 'Scarico',
                  subtitle: 'Rimuovi quantità da questo magazzino',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMovimentoDialog(context, ref, MovimentoKind.scarico);
                  },
                ),
                ListRow(
                  leading: Icon(LucideIcons.arrowLeftRight, size: 20, color: ctx.colors.inkMuted),
                  title: 'Trasferisci',
                  subtitle: 'Sposta quantità verso un altro magazzino',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTrasferimentoDialog(context, ref);
                  },
                ),
                ListRow(
                  leading: Icon(LucideIcons.alertTriangle, size: 20, color: ctx.colors.inkMuted),
                  title: hasStockMinimo ? 'Modifica soglia minima' : 'Imposta soglia minima',
                  showDivider: hasStockMinimo,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showStockMinimoDialog(context, ref);
                  },
                ),
                if (hasStockMinimo)
                  ListRow(
                    leading: Icon(LucideIcons.x, size: 20, color: ctx.colors.red),
                    title: 'Rimuovi soglia minima',
                    showDivider: false,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _clearStockMinimo(context, ref);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMovimentoDialog(
    BuildContext context,
    WidgetRef ref,
    MovimentoKind kind,
  ) {
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();
    final isCarico = kind == MovimentoKind.carico;
    var isSaving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: VetroCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isCarico ? 'Carico' : 'Scarico',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ctx.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    giacenza.materialeNome ?? giacenza.materialeId,
                    style: TextStyle(fontSize: 13, color: ctx.colors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  AppFieldShell(
                    label: 'Quantità',
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppFieldShell(
                    label: 'Note',
                    child: TextField(controller: noteCtrl),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Annulla',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Conferma',
                          isLoading: isSaving,
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final qty = double.tryParse(qtyCtrl.text);
                                  if (qty == null || qty <= 0) return;
                                  if (!ensureOnlineOrWarn(context, ref)) return;

                                  setDialogState(() => isSaving = true);
                                  try {
                                    final client = ref.read(magazzinoApiClientProvider);
                                    final note = noteCtrl.text.trim().isEmpty
                                        ? null
                                        : noteCtrl.text.trim();
                                    if (isCarico) {
                                      await client.carico(
                                        magazzinoId: giacenza.magazzinoId,
                                        materialeId: giacenza.materialeId,
                                        quantita: qty,
                                        note: note,
                                      );
                                    } else {
                                      await client.scarico(
                                        magazzinoId: giacenza.magazzinoId,
                                        materialeId: giacenza.materialeId,
                                        quantita: qty,
                                        note: note,
                                      );
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _refresh(ref);
                                    if (context.mounted) {
                                      showAppToast(
                                        context,
                                        message: isCarico
                                            ? 'Carico registrato'
                                            : 'Scarico registrato',
                                        tone: ToastTone.success,
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    if (context.mounted) {
                                      showAppToast(
                                        context,
                                        message: _movimentoErrorMessage(e, isCarico: isCarico),
                                        tone: ToastTone.error,
                                      );
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      // Not disposed here: showDialog's returned Future completes at Navigator.pop() — the call
      // site above — not when the dialog's widget tree is actually unmounted, which happens later,
      // after the exit transition finishes. Disposing in a `.then()` here made both text fields
      // access their (already-disposed) controllers while still mid-transition, a real crash this
      // batch introduced and then caught on-device: "A TextEditingController was used after being
      // disposed." Correctly fixing the underlying real (if minor) controller leak needs these
      // dialogs to own their controllers in a dedicated StatefulWidget instead, so `dispose()` runs
      // exactly when Flutter unmounts the widget — not attempted in this pass.
    );
  }

  void _showTrasferimentoDialog(BuildContext context, WidgetRef ref) {
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();
    String? destinationId;
    var isSaving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: VetroCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Trasferisci',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ctx.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Not wrapped in Flexible: a plain SingleChildScrollView shrink-wraps to its
                  // child's actual height when the incoming constraint is loose (the case here,
                  // as a normal — not flex — child of this `mainAxisSize.min` Column), and only
                  // becomes scroll-constrained if content genuinely overflows the dialog's bounded
                  // max height. Same nesting the original AlertDialog's own `content:` used.
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          giacenza.materialeNome ?? giacenza.materialeId,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ctx.colors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Da: ${giacenza.magazzinoNome ?? giacenza.magazzinoId}',
                          style: TextStyle(fontSize: 12, color: ctx.colors.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        Consumer(
                          builder: (ctx, ref, _) {
                            final async = ref.watch(magazziniProvider);
                            return async.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: CircularProgressIndicator(),
                              ),
                              error: (e, _) => Text(
                                humanErrorMessage(e, azione: 'caricare i magazzini'),
                              ),
                              data: (list) {
                                final options = list
                                    .where((m) => m.id != giacenza.magazzinoId)
                                    .toList();
                                return AppFieldShell(
                                  label: 'Magazzino destinazione',
                                  child: DropdownButtonFormField<String>(
                                    // ignore: deprecated_member_use — controlled field
                                    value: destinationId,
                                    decoration: const InputDecoration(isDense: true),
                                    isExpanded: true,
                                    items: [
                                      for (final m in options)
                                        DropdownMenuItem(
                                          value: m.id,
                                          child: Text(m.nome),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setDialogState(() => destinationId = v),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        AppFieldShell(
                          label: 'Quantità',
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppFieldShell(
                          label: 'Note',
                          child: TextField(controller: noteCtrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Annulla',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Conferma',
                          isLoading: isSaving,
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final qty = double.tryParse(qtyCtrl.text);
                                  final dest = destinationId;
                                  if (qty == null || qty <= 0 || dest == null) return;
                                  if (!ensureOnlineOrWarn(context, ref)) return;

                                  setDialogState(() => isSaving = true);
                                  try {
                                    final client = ref.read(magazzinoApiClientProvider);
                                    await client.trasferimento(
                                      magazzinoId: giacenza.magazzinoId,
                                      materialeId: giacenza.materialeId,
                                      quantita: qty,
                                      magazzinoDestinazioneId: dest,
                                      note: noteCtrl.text.trim().isEmpty
                                          ? null
                                          : noteCtrl.text.trim(),
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _refresh(ref);
                                    if (context.mounted) {
                                      showAppToast(
                                        context,
                                        message: 'Trasferimento registrato',
                                        tone: ToastTone.success,
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    if (context.mounted) {
                                      showAppToast(
                                        context,
                                        message: _movimentoErrorMessage(e, isCarico: false),
                                        tone: ToastTone.error,
                                      );
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      // See _showMovimentoDialog's own comment: not disposed here for the same reason.
    );
  }

  void _showStockMinimoDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(
      text: giacenza.stockMinimo?.toStringAsFixed(0) ?? '',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: VetroCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Soglia minima',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ctx.colors.ink,
                ),
              ),
              const SizedBox(height: 16),
              AppFieldShell(
                label: 'Quantità minima',
                child: TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Annulla',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: 'Salva',
                      onPressed: () async {
                        final value = double.tryParse(ctrl.text);
                        if (value == null || value < 0) return;
                        if (!ensureOnlineOrWarn(context, ref)) return;
                        Navigator.pop(ctx);
                        try {
                          await ref
                              .read(magazzinoApiClientProvider)
                              .setStockMinimo(stockId: giacenza.id, stockMinimo: value);
                          _refresh(ref);
                          if (context.mounted) {
                            showAppToast(
                              context,
                              message: 'Soglia minima aggiornata',
                              tone: ToastTone.success,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showAppToast(
                              context,
                              message: humanErrorMessage(
                                e,
                                azione: 'salvare la soglia minima',
                              ),
                              tone: ToastTone.error,
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // See _showMovimentoDialog's own comment: not disposed here for the same reason — this one
      // pops before its async call even starts, so `.then()` fired sooner than the others did.
    );
  }

  Future<void> _clearStockMinimo(BuildContext context, WidgetRef ref) async {
    if (!ensureOnlineOrWarn(context, ref)) return;
    try {
      await ref
          .read(magazzinoApiClientProvider)
          .clearStockMinimo(stockId: giacenza.id);
      _refresh(ref);
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Soglia minima rimossa',
          tone: ToastTone.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          message: humanErrorMessage(e, azione: 'rimuovere la soglia minima'),
          tone: ToastTone.error,
        );
      }
    }
  }

  /// Prefers the server's own explanation over the generic humanizer — `InsufficientStockException`
  /// (Gap 3) reaches the client as a plain string 400 body, which `humanErrorMessage` cannot read
  /// (it only recognises `{detail|title|message}` JSON objects), so surfacing it here is the only
  /// way this specific, actionable error is not swallowed.
  String _movimentoErrorMessage(Object error, {required bool isCarico}) {
    if (error is DioException &&
        error.response?.statusCode == 400 &&
        error.response?.data is String) {
      final raw = (error.response!.data as String).trim();
      if (raw.isNotEmpty) return raw;
    }
    return humanErrorMessage(
      error,
      azione: isCarico ? 'registrare il carico' : 'registrare lo scarico',
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(giacenzeProvider);
    ref.invalidate(movimentiProvider);
  }
}

/// Which write action a `_showMovimentoDialog` call is for.
enum MovimentoKind { carico, scarico }

class _MovimentoRow extends StatelessWidget {
  const _MovimentoRow({required this.movimento});

  final MovimentoDto movimento;

  static final _dateFormat = DateFormat('dd/MM HH:mm', 'it');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tipo = movimento.tipo.toLowerCase();
    final (icon, tint) = switch (tipo) {
      'carico' => (LucideIcons.arrowDownToLine, c.green),
      'scarico' => (LucideIcons.arrowUpFromLine, c.amber),
      _ => (LucideIcons.arrowLeftRight, c.inkMuted),
    };

    final where = [
      movimento.magazzinoOrigineNome,
      movimento.magazzinoDestinazioneNome,
    ].whereType<String>().join(' → ');

    final qty = movimento.quantita;
    final qtyLabel = qty == qty.truncateToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(1);

    return ListRow(
      leading: _Tile(icon: icon, tint: tint),
      title: movimento.materialeNome ?? movimento.materialeId,
      subtitle: [
        movimento.tipo,
        if (where.isNotEmpty) where,
        if (movimento.userNome != null) movimento.userNome!,
      ].join(' · '),
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            qtyLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          Text(
            _dateFormat.format(movimento.data.toLocal()),
            style: TextStyle(fontSize: 10, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, this.tint});

  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: c.bg3, borderRadius: AppRack.insetShape),
      child: Icon(icon, size: 20, color: tint ?? c.inkMuted),
    );
  }
}
