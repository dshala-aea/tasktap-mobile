// dart format width=100
import 'package:flutter/widgets.dart';

/// One field the single step microphone can write into.
class DictationTarget {
  const DictationTarget({
    required this.id,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  /// Stable across rebuilds — identity of a target is its id, never the object.
  final String id;

  /// Shown on the bar so the destination is never a guess ("Scrive in: Diagnosi").
  final String label;

  final TextEditingController controller;

  /// Kept in step with the controller, because the editor's state (not the controller) is what
  /// reaches the draft row and then the submit payload.
  final ValueChanged<String> onChanged;
}

/// Which field the step microphone writes into: the last one the technician touched.
class DictationTargetRegistry extends ChangeNotifier {
  final _targets = <String, DictationTarget>{};
  String? _activeId;

  DictationTarget? get active => _activeId == null ? null : _targets[_activeId];

  void register(DictationTarget target) {
    _targets[target.id] = target;
    // The first field to register is the default, so the microphone is never pointing at nothing
    // on a step the technician has not touched yet.
    if (_activeId == null) {
      _activeId = target.id;
      notifyListeners();
    }
  }

  void select(String id) {
    if (_activeId == id || !_targets.containsKey(id)) return;
    _activeId = id;
    notifyListeners();
  }
}
