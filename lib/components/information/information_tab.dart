import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/information/information_content.dart';
import 'package:fstapp/components/information/song/songbook_content.dart';
import 'package:fstapp/theme_config.dart';

class InformationTab extends StatefulWidget {
  const InformationTab({super.key});

  @override
  _InformationTabState createState() => _InformationTabState();
}

class _InformationTabState extends State<InformationTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _tabLength;

  @override
  void initState() {
    super.initState();
    _tabLength = 1; // InformationContent is always present
    if (FeatureService.isFeatureEnabled(FeatureConstants.songbook)) {
      _tabLength++; // Add SongbookContent if enabled
    }
    _tabController = TabController(length: _tabLength, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabLength,
      child: Column(
        children: [
          Container(
            color: ThemeConfig.backgroundColor(context),
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                DataGridHelper.buildTab(
                    context, Icons.info, InformationStrings.information),
                if (FeatureService.isFeatureEnabled(FeatureConstants.songbook))
                  DataGridHelper.buildTab(
                      context, Icons.library_music, CommonStrings.songbook),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                InformationContent(),
                if (FeatureService.isFeatureEnabled(FeatureConstants.songbook))
                  SongbookContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
