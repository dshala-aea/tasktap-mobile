import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/ticket/ticket_label.dart';

/// How a ticket names itself.
///
/// Five screens rendered `ticket.id.substring(0, 8)` as the thing identifying a job, and the
/// detail screen used it as the *page title* — so the largest text on the screen was eight hex
/// characters of a GUID and the ticket's real name was demoted to the subtitle.
///
/// The rule under test is the same one the rapportino wizard already follows: **an identifier a
/// human cannot recognise is worse than no identifier.** Every case below that returns null is
/// asserting the absence of a fallback, because a fallback is exactly how the id got onto the
/// screen in the first place.
void main() {
  group('a ticket with a number', () {
    test('is referenced by it', () {
      expect(ticketReference('1842'), '#1842');
    });

    test('does not get a second hash when the tenant format carries one', () {
      expect(ticketReference('#TK-1842'), '#TK-1842');
    });

    test('keeps a tenant-specific format intact rather than reformatting it', () {
      expect(ticketReference('2026/INT/0044'), '#2026/INT/0044');
    });

    test('is trimmed, because a stray space reads as a broken layout', () {
      expect(ticketReference('  TK-1842  '), '#TK-1842');
    });
  });

  group('a ticket without one', () {
    // Tickets created before numbering existed have no numero, and that is permanent rather than
    // a loading state. Returning null lets the caller drop the line entirely.
    test('has no reference at all when the number is null', () {
      expect(ticketReference(null), isNull);
    });

    test('has no reference when the number is empty', () {
      expect(ticketReference(''), isNull);
    });

    test('has no reference when the number is only whitespace', () {
      expect(ticketReference('   '), isNull);
    });

    test('never falls back to anything id-shaped', () {
      // The regression, stated directly: nothing this function returns may be derived from a GUID,
      // because there is no input through which an id can reach it.
      for (final input in [null, '', '  ']) {
        expect(ticketReference(input), isNull, reason: 'input ${input == null ? 'null' : '"$input"'}');
      }
    });
  });
}
