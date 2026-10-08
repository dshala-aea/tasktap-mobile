// dart format width=100

/// How a control renders its input and stores its value. Mirrors the backend's `ControlTypeEnum`
/// (a string on the wire via `JsonStringEnumConverter`). Moved here from the ticket feature so the
/// domain layer can use it; `ticket_detail_api_client.dart` re-exports it, so every existing import
/// keeps working.
enum ControlType { text, number, dateTime, checkbox, trueFalse, options, unknown }

ControlType controlTypeFromWire(String? value) {
  return switch (value) {
    'Text' => ControlType.text,
    'Number' => ControlType.number,
    'DateTime' => ControlType.dateTime,
    'Checkbox' => ControlType.checkbox,
    'TrueFalse' => ControlType.trueFalse,
    'Options' => ControlType.options,
    _ => ControlType.unknown,
  };
}

String controlTypeToWire(ControlType type) => switch (type) {
  ControlType.text => 'Text',
  ControlType.number => 'Number',
  ControlType.dateTime => 'DateTime',
  ControlType.checkbox => 'Checkbox',
  ControlType.trueFalse => 'TrueFalse',
  ControlType.options => 'Options',
  ControlType.unknown => 'Unknown',
};

/// Bulk "mark checked" applies only to these two types (backend: `bool_set_requires_boolean_control`).
bool isBooleanControl(ControlType type) =>
    type == ControlType.checkbox || type == ControlType.trueFalse;
