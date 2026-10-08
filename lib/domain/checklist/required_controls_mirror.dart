// dart format width=100
import 'checklist_items.dart';
import 'checklist_models.dart';
import 'control_answer_rules.dart';

class MissingRequired {
  const MissingRequired({
    required this.controlId,
    required this.label,
    required this.assetId,
    required this.assetName,
  });
  final String controlId;
  final String label;
  final String assetId;
  final String assetName;
}

class AssetChecklistStatus {
  const AssetChecklistStatus({
    required this.missing,
    required this.assetCount,
    required this.requiredTotal,
    required this.omitted,
  });
  final List<MissingRequired> missing;
  final int assetCount;
  final int requiredTotal;
  final bool omitted;
  bool get hasAssetChecklists => assetCount > 0;
}

AssetChecklistStatus assetChecklistStatus(TicketChecklist tree, AnswerLookup local) {
  final missing = <MissingRequired>[];
  var assets = 0;
  var requiredTotal = 0;
  for (final a in tree.distinctAssets) {
    if (!a.templated || !a.coveredNow) continue;
    assets++;
    for (final c in a.controls) {
      if (c.isRetained || !c.isRequired) continue;
      requiredTotal++;
      if (!isAnswered(c, local(c.id))) {
        missing.add(MissingRequired(
          controlId: c.id,
          label: c.label,
          assetId: a.assetId,
          assetName: a.name,
        ));
      }
    }
  }
  missing.sort((x, y) {
    final byAsset = naturalCompare(x.assetName, y.assetName);
    return byAsset != 0 ? byAsset : naturalCompare(x.label, y.label);
  });
  return AssetChecklistStatus(
    missing: missing,
    assetCount: assets,
    requiredTotal: requiredTotal,
    omitted: tree.omitted && assets == 0,
  );
}
