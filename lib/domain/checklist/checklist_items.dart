// dart format width=100
import 'checklist_models.dart';
import 'control_answer_rules.dart';

enum ChecklistFilter { all, toFill, requiredMissing, exceptions }

enum ChecklistLayout { byAsset, byControl }

class ChecklistQuery {
  const ChecklistQuery({
    this.text = '',
    this.filter = ChecklistFilter.all,
    this.layout = ChecklistLayout.byAsset,
    this.expandedAssetIds = const {},
  });

  /// byAsset: matches the asset name or matricola. byControl: the control label or the asset name.
  final String text;
  final ChecklistFilter filter;
  final ChecklistLayout layout;
  final Set<String> expandedAssetIds;

  ChecklistQuery copyWith({
    String? text,
    ChecklistFilter? filter,
    ChecklistLayout? layout,
    Set<String>? expandedAssetIds,
  }) => ChecklistQuery(
    text: text ?? this.text,
    filter: filter ?? this.filter,
    layout: layout ?? this.layout,
    expandedAssetIds: expandedAssetIds ?? this.expandedAssetIds,
  );
}

typedef AnswerLookup = ChecklistAnswer? Function(String controlId);

sealed class ChecklistListItem {
  const ChecklistListItem();

  /// Stable across rebuilds and unique per placement (a child under two librettos appears twice).
  String get key;
}

class LibrettoHeaderItem extends ChecklistListItem {
  const LibrettoHeaderItem({required this.libretto, required this.childCount});
  final AssetChecklist libretto;
  final int childCount;
  @override
  String get key => 'lib:${libretto.assetId}';
}

class AssetHeaderItem extends ChecklistListItem {
  const AssetHeaderItem({
    required this.asset,
    required this.progress,
    required this.expanded,
    this.librettoId,
  });
  final AssetChecklist asset;
  final AssetProgress progress;
  final bool expanded;
  final String? librettoId;
  @override
  String get key => 'asset:${librettoId ?? '-'}:${asset.assetId}';
}

class ControlGroupItem extends ChecklistListItem {
  const ControlGroupItem({required this.ownerKey, required this.path});
  final String ownerKey;
  final String path;
  @override
  String get key => 'grp:$ownerKey:$path';
}

class ControlItem extends ChecklistListItem {
  const ControlItem({
    required this.asset,
    required this.control,
    required this.groupPath,
    this.librettoId,
  });
  final AssetChecklist asset;
  final ChecklistControl control;
  final String groupPath;
  final String? librettoId;
  @override
  String get key => 'ctl:${librettoId ?? '-'}:${asset.assetId}:${control.id}';
}

class ControlHeaderItem extends ChecklistListItem {
  const ControlHeaderItem({required this.lineageId, required this.label, required this.assetCount});
  final String lineageId;
  final String label;
  final int assetCount;
  @override
  String get key => 'hdr:$lineageId';
}

/// Flattens the checklist into the list the screen windows over. Pure and linear: every control is
/// visited once per placement, answers are looked up by id.
List<ChecklistListItem> buildChecklistItems(
  TicketChecklist tree,
  ChecklistQuery q,
  AnswerLookup local,
) {
  final text = q.text.trim().toLowerCase();
  final filtering = q.filter != ChecklistFilter.all;

  bool controlMatches(ChecklistControl c) {
    if (c.isRetained) return !filtering;
    final a = local(c.id);
    switch (q.filter) {
      case ChecklistFilter.all:
        return true;
      case ChecklistFilter.toFill:
        return !isAnswered(c, a);
      case ChecklistFilter.requiredMissing:
        return c.isRequired && !isAnswered(c, a);
      case ChecklistFilter.exceptions:
        return isException(c, a);
    }
  }

  return q.layout == ChecklistLayout.byAsset
      ? _byAsset(tree, q, text, filtering, local, controlMatches)
      : _byControl(tree, text, local, controlMatches);
}

List<ChecklistListItem> _byAsset(
  TicketChecklist tree,
  ChecklistQuery q,
  String text,
  bool filtering,
  AnswerLookup local,
  bool Function(ChecklistControl) controlMatches,
) {
  bool assetMatchesText(AssetChecklist a) =>
      text.isEmpty ||
      a.name.toLowerCase().contains(text) ||
      (a.matricola ?? '').toLowerCase().contains(text);

  List<ChecklistListItem> block(AssetChecklist a, String? librettoId) {
    final shown = [
      for (final p in a.placed)
        if (controlMatches(p.$2)) p,
    ];
    if (filtering && shown.isEmpty) return const [];
    final expanded = filtering || q.expandedAssetIds.contains(a.assetId);
    final header = AssetHeaderItem(
      asset: a,
      progress: progressOf(a.controls, local),
      expanded: expanded,
      librettoId: librettoId,
    );
    if (!expanded) return [header];
    final out = <ChecklistListItem>[header];
    String? last;
    for (final p in shown) {
      if (p.$1 != last && p.$1.isNotEmpty) {
        out.add(ControlGroupItem(ownerKey: header.key, path: p.$1));
      }
      last = p.$1;
      out.add(ControlItem(asset: a, control: p.$2, groupPath: p.$1, librettoId: librettoId));
    }
    return out;
  }

  final items = <ChecklistListItem>[];
  for (final lg in tree.librettos) {
    final own = assetMatchesText(lg.libretto) && lg.libretto.controls.isNotEmpty
        ? block(lg.libretto, null)
        : const <ChecklistListItem>[];
    final kids = <ChecklistListItem>[];
    for (final child in lg.children) {
      if (assetMatchesText(child)) kids.addAll(block(child, lg.libretto.assetId));
    }
    if (own.isEmpty && kids.isEmpty && (filtering || text.isNotEmpty)) continue;
    items.add(LibrettoHeaderItem(libretto: lg.libretto, childCount: lg.children.length));
    items.addAll(own);
    items.addAll(kids);
  }
  for (final a in tree.standalone) {
    if (assetMatchesText(a)) items.addAll(block(a, null));
  }
  return items;
}

List<ChecklistListItem> _byControl(
  TicketChecklist tree,
  String text,
  AnswerLookup local,
  bool Function(ChecklistControl) controlMatches,
) {
  final byLineage = <String, List<(AssetChecklist, String, ChecklistControl)>>{};
  final labels = <String, String>{};
  for (final a in tree.distinctAssets) {
    for (final p in a.placed) {
      final c = p.$2;
      if (c.isRetained) continue;
      (byLineage[c.lineageId] ??= []).add((a, p.$1, c));
      labels.putIfAbsent(c.lineageId, () => c.label);
    }
  }
  final lineages = byLineage.keys.toList()
    ..sort((x, y) => naturalCompare(labels[x]!, labels[y]!));

  final items = <ChecklistListItem>[];
  for (final l in lineages) {
    final label = labels[l]!;
    final entries = byLineage[l]!.where((e) {
      final textOk = text.isEmpty ||
          label.toLowerCase().contains(text) ||
          l.toLowerCase().contains(text) ||
          e.$1.name.toLowerCase().contains(text);
      return textOk && controlMatches(e.$3);
    }).toList();
    if (entries.isEmpty) continue;
    entries.sort((x, y) => naturalCompare(x.$1.name, y.$1.name));
    items.add(ControlHeaderItem(lineageId: l, label: label, assetCount: entries.length));
    for (final e in entries) {
      items.add(ControlItem(asset: e.$1, control: e.$3, groupPath: e.$2));
    }
  }
  return items;
}
