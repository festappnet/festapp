import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/views/form_responses_content.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/theme_config.dart';

import '../form_strings.dart';

import 'package:fstapp/components/forms/views/form_design_content.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class FormTab extends StatefulWidget {
  final String formLink;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onDataUpdated;
  const FormTab({
    super.key,
    required this.formLink,
    this.onActionCompleted,
    this.onDataUpdated,
  });

  @override
  _FormTabState createState() => _FormTabState();
}

class _FormTabState extends State<FormTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  context, Icons.data_object, FormStrings.tabForm),
              DataGridHelper.buildTab(
                  context, Icons.settings, CommonStrings.settings),
              DataGridHelper.buildTab(context, Icons.palette, FormStrings.tabDesign),
              DataGridHelper.buildTab(
                  context, Icons.list, FormStrings.tabResponses),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              FormEditorContent(
                formLink: widget.formLink,
                onDataUpdated: widget.onDataUpdated,
              ),
              FormSettingsContent(
                formLink: widget.formLink,
                onActionCompleted: widget.onActionCompleted,
                onDataUpdated: widget.onDataUpdated,
              ),
              FormDesignContent(
                formLink: widget.formLink,
                onActionCompleted: widget.onActionCompleted,
                onDataUpdated: widget.onDataUpdated,
              ),
              FormResponsesContent(formLink: widget.formLink),
            ],
          ),
        ),
      ],
    );
  }
}
