import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/information/game/game_settings_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class GameSettingsContent extends StatefulWidget {
  const GameSettingsContent({super.key});

  @override
  _GameSettingsContentState createState() => _GameSettingsContentState();
}

class _GameSettingsContentState extends State<GameSettingsContent> {
  DateTime? _startDateTime;
  DateTime? _endDateTime;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    // Load game settings from the database
    final gameSettings = await DbOccasions.loadGameSettings();
    if (gameSettings != null) {
      setState(() {
        _startDateTime = gameSettings.start?.toOccasionTime();
        _endDateTime = gameSettings.end?.toOccasionTime();
      });
    }
    setState(() {
      _isLoading = false; // Set loading to false after data is loaded
    });
  }

  Future<void> saveData() async {
    if (_startDateTime != null &&
        _endDateTime != null &&
        _startDateTime!.isAfter(_endDateTime!)) {
      ToastHelper.Show(context, GroupsStrings.startBeforeEnd,
          severity: ToastSeverity.NotOk);
      return;
    }

    final gameSettings = GameSettingsModel(
      start: _startDateTime?.toUtcFromOccasionTime(),
      end: _endDateTime?.toUtcFromOccasionTime(),
    );

    final success = await DbOccasions.updateGameSettings(gameSettings);
    if (success) {
      ToastHelper.Show(context, CommonStrings.saved,
          severity: ToastSeverity.Ok);
    } else {
      ToastHelper.Show(context, "Failed to save game settings.",
          severity: ToastSeverity.NotOk);
    }
  }

  Future<void> _selectDateTime(BuildContext context, bool isStart) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selectedDate != null) {
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (selectedTime != null) {
        final selectedDateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        );

        setState(() {
          if (isStart) {
            _startDateTime = selectedDateTime;
          } else {
            _endDateTime = selectedDateTime;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator if data is still loading
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(CommonStrings.start),
              TextButton(
                onPressed: () => _selectDateTime(context, true),
                child: Text(_startDateTime?.toOccasionTime().toString() ?? ""),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Text(CommonStrings.end),
              TextButton(
                onPressed: () => _selectDateTime(context, false),
                child: Text(_endDateTime?.toOccasionTime().toString() ?? ""),
              ),
            ],
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: saveData,
            child: Text(CommonStrings.save),
          ),
        ],
      ),
    );
  }
}
