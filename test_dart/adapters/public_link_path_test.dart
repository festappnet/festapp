import 'package:test/test.dart';
import 'package:fstapp/services/public_link_path.dart';

void main() {
  test('resolved public aliases preserve subpages, query and capability', () {
    for (final alias in ['a', 'b']) {
      expect(
          canonicalPublicPath('/form/$alias?preview=true#order?token=secret',
              'form', alias, 'c'),
          '/form/c?preview=true#order?token=secret');
      expect(
          canonicalPublicPath('/$alias/admin/forms/f/design?q=%2f#anchor',
              'occasion', alias, 'c'),
          '/c/admin/forms/f/design?q=%2f#anchor');
    }
    expect(canonicalPublicPath('/form/other', 'form', 'a', 'c'), '/form/other');
    expect(
        canonicalPublicPath('https://foreign.invalid/form/a', 'form', 'a', 'c'),
        'https://foreign.invalid/form/a');
  });
}
