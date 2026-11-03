import 'package:festapp_core/forms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/form_appearance_theme.dart';

void main() {
  FormDefinition definition({String mode = 'solid', String? secondary}) =>
      FormDefinition.fromJson({
        'id': 1,
        'data': {
          'design': {
            'primary_color': '#4465A6',
            'background_mode': mode,
            if (secondary != null) 'secondary_color': secondary,
          },
        },
      });

  testWidgets(
    'system mode follows the selected app theme and explicit mode overrides it',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final system = FormDefinition.fromJson({'id': 1});
      expect(
        formAppearanceBaseTheme(context, system).brightness,
        Brightness.dark,
      );
      final light = FormDefinition.fromJson({
        'id': 2,
        'data': {
          'design': {'theme_mode': 'light'},
        },
      });
      expect(
        formAppearanceBaseTheme(context, light).brightness,
        Brightness.light,
      );
    },
  );

  test('public color owner keeps backgrounds subtle and selected controls on the accent in both themes', () {
    for (final brightness in Brightness.values) {
      final form = definition(mode: 'gradient', secondary: '#885268');
      final theme = formAppearanceTheme(
        ThemeData(brightness: brightness),
        form,
      );
      final background = formAppearanceBackground(theme, form)!;
      expect(background.color, theme.scaffoldBackgroundColor);
      expect(background.gradient!.colors.first, background.color);
      expect(background.gradient!.colors.last, isNot(background.color));
      expect(background.color, isNot(const Color(0xff4465a6)));
      expect(
        theme.radioTheme.fillColor!.resolve({WidgetState.selected}),
        theme.primaryColor,
      );
      expect(
        theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
        theme.primaryColor,
      );
      expect(
        theme.elevatedButtonTheme.style!.backgroundColor!.resolve({}),
        theme.primaryColor,
      );
      if (brightness == Brightness.dark) {
        expect(
          HSLColor.fromColor(theme.primaryColor).lightness,
          closeTo(.75, .01),
        );
      } else {
        expect(theme.primaryColor, const Color(0xff4465a6));
      }
    }
  });

  test('dormant secondary does not create a gradient and absent appearance retains the base theme', () {
    final base = ThemeData();
    final form = definition(secondary: '#885268');
    expect(
      formAppearanceBackground(formAppearanceTheme(base, form), form)!.gradient,
      isNull,
    );
    final plain = FormDefinition.fromJson({'id': 2});
    expect(formAppearanceTheme(base, plain), same(base));
    expect(formAppearanceBackground(base, plain), isNull);
  });
}
