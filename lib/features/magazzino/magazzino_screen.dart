import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'magazzino_providers.dart';

// TODO(backend): warehouses + movements not synced to mobile.
// Only the Articoli catalog is available on device; tabs + valore-totale
// require backend endpoints not yet in /api/sync/mobile.

class MagazzinoScreen extends StatefulWidget {
  const MagazzinoScreen({super.key});

  @override
  State<MagazzinoScreen> createState() => _MagazzinoScreenState();
}

class _MagazzinoScreenState extends State<MagazzinoScreen> {
  String _query = '';
  String? _activeCategory;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: _MagazzinoBody(
          query: _query,
          activeCategory: _activeCategory,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
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
    required this.query,
    required this.activeCategory,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onCategoryChanged,
  });

  final String query;
  final String? activeCategory;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCategoryChanged;

  static final _priceFormat = NumberFormat.currency(
    locale: 'it',
    symbol: '€',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(materialiCatalogProvider);
    final categoriesAsync = ref.watch(materialiCategoriesProvider);

    final allMateriali = materialiAsync.valueOrNull ?? [];
    final categories = categoriesAsync.valueOrNull ?? [];

    // Filter by query and category.
    final filtered = allMateriali.where((m) {
      if (activeCategory != null && m.category != activeCategory) return false;
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.code.toLowerCase().contains(q) ||
          (m.marca?.toLowerCase().contains(q) ?? false);
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Magazzino',
            subtitle: 'Articoli',
            showBack: true,
          ),
        ),
        SliverToBoxAdapter(
          child: AppSearchBar(
            controller: searchCtrl,
            hint: 'Cerca per nome, codice o marca…',
            onChanged: onQueryChanged,
          ),
        ),

        // Category filter chips
        if (categories.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // "Tutti" chip
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppChip(
                        label: 'Tutti',
                        active: activeCategory == null,
                        onTap: () {
                          // Clear filter by tapping active category or Tutti
                          if (activeCategory != null) {
                            onCategoryChanged(activeCategory!);
                          }
                        },
                      ),
                    ),
                    ...categories.map((cat) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppChip(
                          label: cat,
                          active: activeCategory == cat,
                          onTap: () => onCategoryChanged(cat),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

        if (materialiAsync.isLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.package,
              title: 'Nessun articolo',
              body: 'Gli articoli sincronizzati appariranno qui.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final m = filtered[i];
                return _MateriaLeRow(
                  materiale: m,
                  isLast: i == filtered.length - 1,
                  priceFormat: _priceFormat,
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

class _MateriaLeRow extends StatelessWidget {
  const _MateriaLeRow({
    required this.materiale,
    required this.isLast,
    required this.priceFormat,
  });

  final MaterialiData materiale;
  final bool isLast;
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.BG3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          LucideIcons.package,
          size: 20,
          color: AppColors.MUTED,
        ),
      ),
      title: materiale.name,
      subtitle: codeMarca.isNotEmpty ? '$codeMarca\n$subParts' : subParts,
      meta: priceLabel != null
          ? Text(
              priceLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.DARK,
              ),
            )
          : null,
      showDivider: !isLast,
    );
  }
}
