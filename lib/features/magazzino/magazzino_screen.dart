import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/magazzino/magazzino_api_client.dart';
import 'magazzino_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
      body: Rack(
        child: SafeArea(
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

  static final _priceFormat = NumberFormat.currency(locale: 'it', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: ScreenHeader(title: 'Magazzino', showBack: true)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
            child: AppSearchBar(
              controller: searchCtrl,
              hint: tab == _MagazzinoTab.articoli
                  ? 'Cerca per nome, codice o marca…'
                  : 'Cerca materiale…',
              onChanged: onQueryChanged,
            ),
          ),
        ...switch (tab) {
          _MagazzinoTab.articoli => _articoliSlivers(context, ref),
          _MagazzinoTab.giacenze => _giacenzeSlivers(context, ref),
          _MagazzinoTab.movimenti => _movimentiSlivers(context, ref),
        },
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppChip(
                      label: 'Tutti',
                      active: activeCategory == null,
                      onTap: () {
                        if (activeCategory != null) onCategoryChanged(activeCategory!);
                      },
                    ),
                  ),
                  ...categories.map(
                    (cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
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
            (context, i) => _MaterialeRow(materiale: filtered[i], priceFormat: _priceFormat),
            childCount: filtered.length,
          ),
        ),
    ];
  }

  // ── Giacenze: current stock, read through to the server ────────────────────

  List<Widget> _giacenzeSlivers(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      giacenzeProvider(
        GiacenzeQuery(q: query.isEmpty ? null : query, soloSottoScorta: soloSottoScorta),
      ),
    );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
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
                  icon: soloSottoScorta ? LucideIcons.checkCircle : LucideIcons.searchX,
                  title: soloSottoScorta ? 'Nessuna scorta sotto minimo' : 'Nessuna giacenza',
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
            motivo: 'Lo storico movimenti si legge solo online. Riprova quando hai segnale.',
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
    child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
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
      if (materiale.marca != null && materiale.marca!.isNotEmpty) materiale.marca,
    ].join(' · ');

    final subParts = [
      if (materiale.unitOfMeasure != null && materiale.unitOfMeasure!.isNotEmpty)
        materiale.unitOfMeasure!,
      if (materiale.category != null && materiale.category!.isNotEmpty) materiale.category!,
    ].join(' · ');

    final priceLabel = materiale.salePrice != null ? priceFormat.format(materiale.salePrice) : null;

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

class _GiacenzaRow extends StatelessWidget {
  const _GiacenzaRow({required this.giacenza});

  final GiacenzaDto giacenza;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final qty = giacenza.quantita;
    final qtyLabel = qty == qty.truncateToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(1);
    final unit = giacenza.unitOfMeasure;

    return ListRow(
      // Below-minimum lines take the danger ledge, not the yellow strap: the strap means "this one
      // is live", and a short stock line is a warning, not a running job. Overloading the strap
      // here would cost it the meaning it has everywhere else.
      ledgeColor: giacenza.sottoScorta ? c.red : null,
      leading: _Tile(
        icon: giacenza.sottoScorta ? LucideIcons.alertTriangle : LucideIcons.package,
        tint: giacenza.sottoScorta ? c.red : null,
      ),
      title: giacenza.materialeNome ?? giacenza.materialeId,
      subtitle: [
        if (giacenza.magazzinoNome != null) giacenza.magazzinoNome!,
        if (giacenza.stockMinimo != null) 'min ${giacenza.stockMinimo!.toStringAsFixed(0)}',
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
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.red),
            ),
        ],
      ),
    );
  }
}

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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
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
