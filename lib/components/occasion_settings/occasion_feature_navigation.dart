import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:fstapp/app_router.gr.dart';

const occasionFeatureParameter = 'feature';

Future<void> openOccasionFeatureSettings(BuildContext context, String code) =>
    context.tabsRouter.navigate(
      const SettingsSectionRoute().copyWith(
        queryParams: {occasionFeatureParameter: code},
      ),
    );
