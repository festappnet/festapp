import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/images/image_url_helper.dart';

void main() {
  const source = 'https://img.festapp.net/images/42/photo.jpg';
  const options =
      'width=300,fit=scale-down,format=auto,quality=75,onerror=redirect';

  test('builds the canonical bounded transform and strips query/fragment', () {
    expect(ImageUrlHelper.transformImageUrl('$source?old=1#x'),
        'https://img.festapp.net/cdn-cgi/image/$options/$source');
  });

  test('supports the exact project A host', () {
    const projectA = 'https://a.img.festapp.net/images/1/a.png';
    expect(ImageUrlHelper.transformImageUrl(projectA, width: 600),
        'https://a.img.festapp.net/cdn-cgi/image/width=600,fit=scale-down,format=auto,quality=75,onerror=redirect/$projectA');
  });

  test('leaves noncanonical inputs unchanged', () {
    for (final value in [
      'https://evil-img.festapp.net/images/1/a.jpg',
      'https://img.festapp.net/private/a.jpg',
      'https://img.festapp.net/images/1/file.pdf',
      'https://img.festapp.net/images%2f1/a.jpg',
      'not-a-url',
    ]) {
      expect(ImageUrlHelper.transformImageUrl(value), value);
    }
    expect(ImageUrlHelper.transformImageUrl(source, width: 301), source);
  });
}
