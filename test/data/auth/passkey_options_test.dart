import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/passkey_options.dart';

const _inner = <String, dynamic>{'challenge': 'Y2hhbGxlbmdl', 'rpId': 'auth.tasktap.it'};

void main() {
  Map<String, dynamic>? parse(dynamic raw) =>
      passkeyOptionsMap(raw, wrapperKey: 'publicKey', requiredKey: 'challenge');

  test('accepts the unwrapped options object', () {
    expect(parse(_inner)?['challenge'], 'Y2hhbGxlbmdl');
  });

  test('accepts a top-level publicKey wrapper', () {
    expect(parse({'publicKey': _inner})?['rpId'], 'auth.tasktap.it');
  });

  test('accepts a JSON-encoded options string', () {
    expect(parse('{"challenge":"Y2hhbGxlbmdl","rpId":"auth.tasktap.it"}')?['challenge'], 'Y2hhbGxlbmdl');
  });

  test('accepts a wrapper whose publicKey is JSON-encoded', () {
    expect(
      parse({'publicKey': '{"challenge":"Y2hhbGxlbmdl","rpId":"auth.tasktap.it"}'})?['rpId'],
      'auth.tasktap.it',
    );
  });

  test('rejects an object without a challenge', () {
    expect(parse({'foo': 'bar'}), isNull);
  });

  test('rejects a non-map, non-JSON value', () {
    expect(parse('not json'), isNull);
    expect(parse(42), isNull);
    expect(parse(null), isNull);
  });
}
