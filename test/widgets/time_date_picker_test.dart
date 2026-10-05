import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

Widget app(Widget child, {Locale locale = const Locale('cs')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(() => initializeDateFormatting('cs'));

  for (final entry in [
    (const Locale('cs'), '15. 10. 2090'),
    (const Locale('en'), '10/15/2090'),
  ]) {
    testWidgets('date display follows ${entry.$1} locale', (tester) async {
      await tester.pumpWidget(app(
          TimeDatePicker(
            date: DateTime(2090, 10, 15),
            time: const TimeOfDay(hour: 9, minute: 0),
            timeLabel: 'Time',
            dateLabel: 'Date',
            onDateChanged: (_) {},
            onTimeChanged: (_) {},
          ),
          locale: entry.$1));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((field) => field.readOnly),
          isTrue);
    });
  }

  testWidgets('clicking fields opens the standard date and time pickers',
      (tester) async {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    await tester.pumpWidget(app(TimeDatePicker(
      date: DateTime(2090, 10, 15),
      time: const TimeOfDay(hour: 9, minute: 0),
      timeLabel: 'Time',
      dateLabel: 'Date',
      maxDate: DateTime(2100),
      onDateChanged: (value) => selectedDate = value,
      onTimeChanged: (value) => selectedTime = value,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextFormField, 'Date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('16'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selectedDate, DateTime(2090, 10, 16));
    await tester.tap(find.widgetWithText(TextFormField, 'Time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selectedTime, const TimeOfDay(hour: 9, minute: 0));
  });

  testWidgets('occasion range keeps both times when moving its date bounds',
      (tester) async {
    var start = DateTime(2090, 10, 15, 9);
    var end = DateTime(2090, 10, 15, 18);
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) => TimeDateRangePicker(
        start: start,
        end: end,
        onStartChanged: (value) => setState(() => start = value!),
        onEndChanged: (value) => setState(() => end = value!),
      ),
    )));
    await tester.pumpAndSettle();
    tester
        .widgetList<TimeDatePicker>(find.byType(TimeDatePicker))
        .first
        .onDateChanged(DateTime(2090, 10, 16));
    await tester.pumpAndSettle();
    expect(start, DateTime(2090, 10, 16, 9));
    expect(end, DateTime(2090, 10, 16, 18));
    tester
        .widgetList<TimeDatePicker>(find.byType(TimeDatePicker))
        .last
        .onDateChanged(DateTime(2090, 10, 14));
    await tester.pumpAndSettle();
    expect(start, DateTime(2090, 10, 14, 9));
    expect(end, DateTime(2090, 10, 14, 18));
  });
}
