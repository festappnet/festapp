import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('round trips the versioned venue document', () {
    final document = VenueSeatDocument(
      rows: 2,
      columns: 3,
      backdrop: const SvgVenueBackdrop('<svg></svg>'),
      seats: const [
        VenueSeat(
          id: 'A1',
          position: SeatPosition(0, 1),
          status: SeatStatus.booked,
          label: 'A1',
          metadata: {'priceBand': 'gold'},
        ),
      ],
    );

    final decoded = VenueSeatDocument.fromJson(document.toJson());
    expect(decoded.schemaVersion, 1);
    expect(decoded.rows, 2);
    expect(decoded.seats.single.status, SeatStatus.booked);
    expect(decoded.seats.single.metadata['priceBand'], 'gold');
    expect(decoded.backdrop?.source, '<svg></svg>');
  });

  test('rejects unknown status values', () {
    expect(
      () => SeatStatus.fromWireName('not-a-status'),
      throwsFormatException,
    );
  });

  test('round trips an in-memory image backdrop as a data URL', () {
    final original = MemoryVenueBackdrop(
      Uint8List.fromList([137, 80, 78, 71]),
      mimeType: 'image/png',
    );

    final decoded = VenueBackdrop.parse(original.source);

    expect(decoded, isA<MemoryVenueBackdrop>());
    expect((decoded as MemoryVenueBackdrop).bytes, original.bytes);
    expect(decoded.mimeType, 'image/png');
  });

  test('rejects empty or non-image in-memory backdrops', () {
    expect(() => MemoryVenueBackdrop(Uint8List(0)), throwsArgumentError);
    expect(
      () =>
          MemoryVenueBackdrop(Uint8List.fromList([1]), mimeType: 'text/plain'),
      throwsArgumentError,
    );
    expect(
      () => MemoryVenueBackdrop(
        Uint8List.fromList([1]),
        mimeType: 'image/svg+xml',
      ),
      throwsArgumentError,
    );
  });

  test('routes SVG data URLs to the SVG backdrop renderer', () {
    final source = UriData.fromString(
      '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
      mimeType: 'image/svg+xml',
    ).toString();

    final decoded = VenueBackdrop.parse(source);

    expect(decoded, isA<SvgVenueBackdrop>());
    expect(decoded.source, contains('<svg'));
  });

  test('keeps in-memory backdrop bytes isolated from caller mutation', () {
    final input = Uint8List.fromList([1, 2, 3]);
    final backdrop = MemoryVenueBackdrop(input);
    input[0] = 9;
    final exposed = backdrop.bytes..[1] = 9;

    expect(backdrop.bytes, [1, 2, 3]);
    expect(exposed, [1, 9, 3]);
  });
}
