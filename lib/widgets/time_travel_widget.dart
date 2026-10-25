import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';

class TimeTravelWidget extends StatefulWidget {
  const TimeTravelWidget({super.key});

  @override
  _TimeTravelWidgetState createState() => _TimeTravelWidgetState();
}

class _TimeTravelWidgetState extends State<TimeTravelWidget> {
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  void _incrementYear() {
    setState(() {
      _selectedDate = DateTime(
          _selectedDate.year + 1, _selectedDate.month, _selectedDate.day);
    });
  }

  void _decrementYear() {
    setState(() {
      _selectedDate = DateTime(
          _selectedDate.year - 1, _selectedDate.month, _selectedDate.day);
    });
  }

  void _incrementMonth() {
    setState(() {
      int nextMonth = _selectedDate.month + 1;
      int year = _selectedDate.year;
      if (nextMonth > 12) {
        nextMonth = 1;
        year++;
      }
      _selectedDate = DateTime(year, nextMonth, _selectedDate.day);
    });
  }

  void _decrementMonth() {
    setState(() {
      int prevMonth = _selectedDate.month - 1;
      int year = _selectedDate.year;
      if (prevMonth < 1) {
        prevMonth = 12;
        year--;
      }
      _selectedDate = DateTime(year, prevMonth, _selectedDate.day);
    });
  }

  void _incrementDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
  }

  void _decrementDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _incrementHour() {
    setState(() {
      _selectedTime = TimeOfDay(
          hour: (_selectedTime.hour + 1) % 24, minute: _selectedTime.minute);
    });
  }

  void _decrementHour() {
    setState(() {
      _selectedTime = TimeOfDay(
          hour: (_selectedTime.hour - 1) % 24, minute: _selectedTime.minute);
    });
  }

  void _incrementMinute() {
    setState(() {
      _selectedTime = TimeOfDay(
        hour: _selectedTime.hour,
        minute: (_selectedTime.minute + 1) % 60,
      );
    });
  }

  void _decrementMinute() {
    setState(() {
      _selectedTime = TimeOfDay(
        hour: _selectedTime.hour,
        minute: (_selectedTime.minute - 1) % 60,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle textButtonStyle = TextButton.styleFrom(
      textStyle: const TextStyle(decoration: TextDecoration.none),
    );

    const TextStyle textStyle = TextStyle(
      fontSize: 12,
      color: Colors.black,
      decoration: TextDecoration.none,
    );

    return Visibility(
      visible: true,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Time travel",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none),
                ),
                TextButton(
                  onPressed: () {
                    TimeHelper.toggleTimeTravel?.call();
                  },
                  style: textButtonStyle,
                  child: const Icon(Icons.close, color: Colors.black),
                ),
              ],
            ),
            const SizedBox(
              height: 6,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    TextButton(
                      onPressed: _incrementYear,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_upward, color: Colors.black),
                    ),
                    Text(
                      '${_selectedDate.year}',
                      style: textStyle,
                    ),
                    TextButton(
                      onPressed: _decrementYear,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_downward, color: Colors.black),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5.0),
                ),
                Column(
                  children: [
                    TextButton(
                      onPressed: _incrementMonth,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_upward, color: Colors.black),
                    ),
                    Text(
                      _selectedDate.month.toString().padLeft(2, '0'),
                      style: textStyle,
                    ),
                    TextButton(
                      onPressed: _decrementMonth,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_downward, color: Colors.black),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5.0),
                ),
                Column(
                  children: [
                    TextButton(
                      onPressed: _incrementDay,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_upward, color: Colors.black),
                    ),
                    Text(
                      _selectedDate.day.toString().padLeft(2, '0'),
                      style: textStyle,
                    ),
                    TextButton(
                      onPressed: _decrementDay,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_downward, color: Colors.black),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    TextButton(
                      onPressed: _incrementHour,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_upward, color: Colors.black),
                    ),
                    Text(
                      _selectedTime.hour.toString().padLeft(2, '0'),
                      style: textStyle,
                    ),
                    TextButton(
                      onPressed: _decrementHour,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_downward, color: Colors.black),
                    ),
                  ],
                ),
                Column(
                  children: [
                    TextButton(
                      onPressed: _incrementMinute,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_upward, color: Colors.black),
                    ),
                    Text(
                      _selectedTime.minute.toString().padLeft(2, '0'),
                      style: textStyle,
                    ),
                    TextButton(
                      onPressed: _decrementMinute,
                      style: textButtonStyle,
                      child:
                          const Icon(Icons.arrow_downward, color: Colors.black),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(
              height: 6,
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  TimeHelper.currentTime = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    _selectedTime.hour,
                    _selectedTime.minute,
                  );
                });
              },
              child: const Text("Set Date and Time"),
            ),
          ],
        ),
      ),
    );
  }
}
