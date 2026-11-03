import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker_example/demo/locations.dart';

void main() {
  test('preview stays under the GitHub Pages project', () {
    expect(
      previewLocation(
        Uri.parse(
          'https://festappnet.github.io/venue_seat_picker/?fromPreview=token',
        ),
      ).toString(),
      'https://festappnet.github.io/venue_seat_picker/js/demo/',
    );
  });
  test('downloadable kit uses its sibling JS demo', () {
    expect(
      previewLocation(Uri.parse('http://localhost:8000/flutter/')).toString(),
      'http://localhost:8000/js/demo/',
    );
  });
}
