import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/speakers/counseling_picker.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/widgets/navigate_back_button.dart';

/// Standalone counseling page. The whole flow lives in [CounselingPicker]; this
/// is just a routed Scaffold around it (the same picker is also embedded inline
/// on the entry event page, above the description).
@RoutePage()
class CounselingPage extends StatelessWidget {
  static const ROUTE = "counseling";

  const CounselingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const ScheduleBackButton(),
        title: Text(SpeakersStrings.counselingTitle),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: CounselingPicker(),
          ),
        ),
      ),
    );
  }
}
