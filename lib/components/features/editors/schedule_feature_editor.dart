import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/features_strings.dart';
import '../schedule_feature.dart';

extension ScheduleFeatureSettingsEditor on ScheduleFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return _ScheduleFeatureForm(feature: this);
  }
}

class _ScheduleFeatureForm extends StatefulWidget {
  final ScheduleFeature feature;

  const _ScheduleFeatureForm({required this.feature});

  @override
  State<_ScheduleFeatureForm> createState() => _ScheduleFeatureFormState();
}

class _ScheduleFeatureFormState extends State<_ScheduleFeatureForm> {
  void _refresh(VoidCallback change) {
    setState(change);
    EditorDraftScope.changed(context);
  }

  late String _scheduleType;
  late bool _enableChildren;
  late String _breakDefinition;
  late TimeOfDay _afternoonBreakTime;
  late TimeOfDay _eveningBreakTime;
  late List<EventType> _eventTypes;

  final List<String> _seedColorOptions = [
    "seed1",
    "seed2",
    "seed3",
    "seed4",
    "custom"
  ];

  @override
  void initState() {
    super.initState();
    _scheduleType =
        widget.feature.scheduleType ?? ScheduleFeature.scheduleTypeBasic;
    _enableChildren = widget.feature.enableChildren;
    _breakDefinition = widget.feature.breakDefinition;
    _afternoonBreakTime = widget.feature.afternoonBreakTime;
    _eveningBreakTime = widget.feature.eveningBreakTime;
    _eventTypes = widget.feature.eventTypes
        .map((et) => EventType(
            code: et.code,
            title: et.title,
            colorDefinition: et.colorDefinition))
        .toList();
  }

  void _saveEventTypesToFeature() {
    widget.feature.eventTypes = List<EventType>.from(_eventTypes.map((et) =>
        EventType(
            code: et.code,
            title: et.title,
            colorDefinition: et.colorDefinition)));
  }

  Future<void> _selectTime(BuildContext context, TimeOfDay initialTime,
      ValueChanged<TimeOfDay> onTimeChanged) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null && picked != initialTime) {
      _refresh(() {
        onTimeChanged(picked);
      });
    }
  }

  String _getTranslatedScheduleOption(String value) {
    switch (value) {
      case ScheduleFeature.scheduleTypeBasic:
        return FeaturesStrings.optionBasic;
      case ScheduleFeature.scheduleTypeAdvanced:
        return FeaturesStrings.optionAdvanced;
      case ScheduleFeature.scheduleTypeLight:
        return FeaturesStrings.optionLight;
      default:
        return value;
    }
  }

  String _getTranslatedBreakOption(String value) {
    switch (value) {
      case ScheduleFeature.breakDefinitionTime:
        return FeaturesStrings.optionTime;
      case ScheduleFeature.breakDefinitionPlace:
        return FeaturesStrings.optionPlace;
      default:
        return value;
    }
  }

  void _addEventType() {
    _refresh(() {
      _eventTypes.add(EventType(
          code: 'new_type_${_eventTypes.length + 1}',
          title: FeaturesStrings.eventTypeDefaultTitle,
          colorDefinition: 'seed1'));
    });
  }

  void _removeEventType(int index) {
    _refresh(() {
      _eventTypes.removeAt(index);
    });
  }

  void _updateEventType(int index, EventType updatedType) {
    if (index >= 0 && index < _eventTypes.length) {
      _refresh(() {
        _eventTypes[index] = updatedType;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
            initialValue: _scheduleType,
            decoration:
                InputDecoration(labelText: FeaturesStrings.labelScheduleType),
            items: <String>[
              ScheduleFeature.scheduleTypeBasic,
              ScheduleFeature.scheduleTypeAdvanced,
              ScheduleFeature.scheduleTypeLight,
            ]
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(_getTranslatedScheduleOption(value)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                _refresh(() => _scheduleType = val);
              }
            },
            onSaved: (val) {
              widget.feature.scheduleType = val;
              _saveEventTypesToFeature();
            }),
        const SizedBox(height: 8),
        // New Switch for enabling children
        SwitchListTile(
          title: Text(FeaturesStrings.labelEnableChildren),
          subtitle: Text(FeaturesStrings.subtitleEnableChildren),
          value: _enableChildren,
          onChanged: (bool value) {
            _refresh(() {
              _enableChildren = value;
              widget.feature.enableChildren =
                  value; // Directly update the feature object
            });
          },
          contentPadding: EdgeInsets.zero, // Align with form fields
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            initialValue: _breakDefinition,
            decoration: InputDecoration(
                labelText: FeaturesStrings.labelBreakDefinition),
            items: <String>[
              ScheduleFeature.breakDefinitionTime,
              ScheduleFeature.breakDefinitionPlace
            ]
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(_getTranslatedBreakOption(value)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                _refresh(() => _breakDefinition = val);
              }
            },
            onSaved: (val) {
              widget.feature.breakDefinition =
                  val ?? ScheduleFeature.breakDefinitionTime;
              _saveEventTypesToFeature();
            }),
        if (_breakDefinition == ScheduleFeature.breakDefinitionTime) ...[
          const SizedBox(height: 24),
          Text(FeaturesStrings.titleTimeBasedBreaks,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildTimePickerField(
            context: context,
            label: FeaturesStrings.labelAfternoonTime,
            time: _afternoonBreakTime,
            onTap: () => _selectTime(context, _afternoonBreakTime, (newTime) {
              _afternoonBreakTime = newTime;
              widget.feature.afternoonBreakTime = newTime;
            }),
          ),
          const SizedBox(height: 16),
          _buildTimePickerField(
            context: context,
            label: FeaturesStrings.labelEveningTime,
            time: _eveningBreakTime,
            onTap: () => _selectTime(context, _eveningBreakTime, (newTime) {
              _eveningBreakTime = newTime;
              widget.feature.eveningBreakTime = newTime;
            }),
          ),
        ],
        const SizedBox(height: 24),
        ExpansionTile(
          title: Text(FeaturesStrings.titleEventTypes,
              style: Theme.of(context).textTheme.titleLarge),
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 0.0),
          childrenPadding:
              const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
          children: <Widget>[
            if (_eventTypes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(FeaturesStrings.emptyEventTypes,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _eventTypes.length,
              itemBuilder: (context, index) {
                return _buildEventTypeFormItem(_eventTypes[index], index);
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addEventType,
                label: Text(FeaturesStrings.buttonAddEventType),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimePickerField({
    required BuildContext context,
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
        ),
        child: Text(
          time.format(context),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5),
        ),
      ),
    );
  }

  Widget _buildEventTypeFormItem(EventType eventType, int index) {
    bool isCustom = !_seedColorOptions.contains(eventType.colorDefinition) ||
        eventType.colorDefinition.toLowerCase() == "custom";
    String currentDropdownValue =
        isCustom ? "custom" : eventType.colorDefinition;

    TextEditingController hexColorController = TextEditingController(
        text: isCustom && eventType.colorDefinition.toLowerCase() != "custom"
            ? eventType.colorDefinition
            : "");
    hexColorController.selection = TextSelection.fromPosition(
        TextPosition(offset: hexColorController.text.length));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: eventType.code,
              decoration: InputDecoration(
                  labelText: FeaturesStrings.labelEventTypeCode, filled: true),
              onChanged: (value) {
                _updateEventType(
                    index,
                    EventType(
                        code: value,
                        title: eventType.title,
                        colorDefinition: eventType.colorDefinition));
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: eventType.title,
              decoration: InputDecoration(
                  labelText: FeaturesStrings.labelEventTypeTitle, filled: true),
              onChanged: (value) {
                _updateEventType(
                    index,
                    EventType(
                        code: eventType.code,
                        title: value,
                        colorDefinition: eventType.colorDefinition));
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: currentDropdownValue,
                    decoration: InputDecoration(
                        labelText: FeaturesStrings.labelColorSource,
                        filled: true),
                    items: _seedColorOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value == "custom"
                            ? FeaturesStrings.optionCustomColor
                            : value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        String newColorDef = newValue;
                        if (newValue == "custom") {
                          newColorDef = hexColorController.text.isNotEmpty &&
                                  hexColorController.text.startsWith("#")
                              ? hexColorController.text
                              : "#A0A0A0";
                          if (hexColorController.text.isEmpty ||
                              !hexColorController.text.startsWith("#")) {
                            hexColorController.text = newColorDef;
                          }
                        }
                        _updateEventType(
                            index,
                            EventType(
                                code: eventType.code,
                                title: eventType.title,
                                colorDefinition: newColorDef));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: eventType.getColor(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 2,
                            offset: Offset(0, 1))
                      ]),
                ),
              ],
            ),
            if (currentDropdownValue == "custom")
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: TextFormField(
                  controller: hexColorController,
                  decoration: InputDecoration(
                      labelText: FeaturesStrings.labelCustomColorHex,
                      hintText: "#RRGGBB or #AARRGGBB",
                      filled: true),
                  onChanged: (value) {
                    _updateEventType(
                        index,
                        EventType(
                            code: eventType.code,
                            title: eventType.title,
                            colorDefinition:
                                value.startsWith("#") ? value : "#$value"));
                  },
                  onEditingComplete: () {
                    String finalHex = hexColorController.text;
                    if (!finalHex.startsWith("#")) finalHex = "#$finalHex";
                    _updateEventType(
                        index,
                        EventType(
                            code: eventType.code,
                            title: eventType.title,
                            colorDefinition: finalHex));
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error, size: 28),
                tooltip: FeaturesStrings.tooltipRemoveEventType,
                onPressed: () => _removeEventType(index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
