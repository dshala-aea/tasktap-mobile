/// Build-time switch for passkey payload diagnostics.
///
/// Off in normal builds. On only in the throwaway APK used to capture what the
/// gateway actually returned; the messages it produces are for support, not users.
const bool kPasskeyDiagnostics = bool.fromEnvironment('PASSKEY_DIAGNOSTICS');

/// A short, safe description of a payload: the keys and runtime types, never values.
String describePasskeyPayload(dynamic value) {
  if (value is Map) {
    return 'Map(keys=${value.keys.take(12).toList()})';
  }
  return value?.runtimeType.toString() ?? 'null';
}
