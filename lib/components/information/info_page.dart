import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/information/information_expansion_state.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/information/game/game_page.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/information/song/song_page.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/js/js_stub.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/widgets/pop_button.dart';
import 'package:fstapp/components/images/zoomable_image/zoomable_image.dart';
import '../../services/toast_helper.dart';

@RoutePage()
class InfoPage extends StatefulWidget {
  int? id;
  static const ROUTE = "info";
  InfoPage({@pathParam this.id, super.key});

  @override
  _InfoPageState createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final _htmlSave = HtmlSaveCoordinator();
  final JSInterop jsInterop = JSInterop();
  final ScrollController _scrollController = ScrollController();
  List<InformationModel>? _informationList;
  Map<int, bool> _isItemLoading = {};
  List<GlobalKey> _itemKeys = [];
  final Set<int> _expandedInformationIds = {};
  bool _hasInitializedExpansion = false;

  String title = InformationStrings.information;

  @override
  void initState() {
    super.initState();
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
  }

  void _onProjectionChanged() {
    if (ClientSyncRuntime.isV1Selected) unawaited(loadData());
  }

  @override
  void dispose() {
    _htmlSave.dispose();
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.id == null && context.routeData.hasPendingChildren) {
      widget.id = context.routeData.pendingChildren[0].params.getInt("id");
    }
    if (!_hasInitializedExpansion) {
      if (widget.id != null) {
        _expandedInformationIds.add(widget.id!);
      }
      _hasInitializedExpansion = true;
    }
    loadData();
  }

  @override
  Widget build(BuildContext context) => HtmlEditingScope(coordinator: _htmlSave, child: _buildHtmlParent(context));

  Widget _buildHtmlParent(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConfig.infoPageColor(context),
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(color: ThemeConfig.appBarColorNegative()),
        ),
        leading: PopButton(),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: PinchScrollView(
            builder: (onPinchStart, onPinchEnd) => SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  if (FeatureService.isFeatureEnabled(FeatureConstants.game) ||
                      FeatureService.isFeatureEnabled(
                          FeatureConstants.songbook))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (FeatureService.isFeatureEnabled(
                                FeatureConstants.game))
                              ButtonsHelper.buildReferenceButton(
                                context: context,
                                onPressed: () {
                                  if (!AuthService.isLoggedIn()) {
                                    ToastHelper.Show(
                                        context, InformationStrings.gameSignIn);
                                    return;
                                  }
                                  RouterService.navigateOccasion(
                                      context, GamePage.ROUTE);
                                },
                                icon: Icons.gamepad,
                                label: CommonStrings.game,
                              ),
                            if (FeatureService.isFeatureEnabled(
                                FeatureConstants.songbook))
                              const SizedBox(width: 16),
                            if (FeatureService.isFeatureEnabled(
                                FeatureConstants.songbook))
                              ButtonsHelper.buildReferenceButton(
                                context: context,
                                onPressed: () {
                                  RouterService.navigateOccasion(
                                      context, SongbookPage.ROUTE);
                                },
                                icon: Icons.library_music,
                                label: CommonStrings.songbook,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ExpansionPanelList(
                    expansionCallback: (panelIndex, isExpanded) async {
                      await handleExpansion(panelIndex, isExpanded);
                    },
                    children: _informationList == null
                        ? []
                        : _informationList!
                            .map<ExpansionPanel>((InformationModel item) {
                            final htmlVersion = item.aggregateVersion;
                            int index = _informationList!.indexOf(item);
                            return ExpansionPanel(
                              backgroundColor:
                                  ThemeConfig.backgroundColor(context),
                              headerBuilder:
                                  (BuildContext context, bool isExpanded) {
                                return Container(
                                  key: _itemKeys[index],
                                  child: ListTile(
                                    title: Text(item.title ?? ""),
                                  ),
                                );
                              },
                              body: _isItemLoading[index] ?? false
                                  ? const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    )
                                  : Column(
                                      children: [
                                        Padding(padding: const EdgeInsets.all(12),
                                          child: EditableHtmlField(key: ValueKey('information-html-${item.id}'),
                                            html: item.description, enabled: RightsService.isEditor(),
                                            owner: item.unit != null ? HtmlMediaOwner.unit(item.unit) :
                                              HtmlMediaOwner.occasion(RightsService.currentOccasionId()),
                                            twoFingersOn: onPinchStart, twoFingersOff: onPinchEnd,
                                            onChanged: (_) {}, onSave: (html) async {
                                              final snapshot = InformationModel(id: item.id, title: item.title,
                                                description: html, type: item.type, isHidden: item.isHidden,
                                                order: item.order, unit: item.unit, data: item.data,
                                                informationHidden: item.informationHidden, updatedAt: item.updatedAt,
                                                aggregateVersion: htmlVersion);
                                              await DbInformation.updateInformation(snapshot);
                                              if (mounted) await loadData();
                                            })),
                                      ],
                                    ),
                              isExpanded: item.isExpanded,
                              canTapOnHeader: true,
                            );
                          }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> loadData() async {
    await loadDataOffline();
    setState(() {});
    if (ClientSyncRuntime.isV1Selected) return;
    var allInfo = await DbInformation.getAllActiveInformation();
    await OfflineDataService.saveAllInfo(allInfo);
    await loadDataOffline();
    setState(() {});
  }

  Future<void> handleExpansion(int panelIndex, bool isExpanded) async {
    setState(() {
      final item = _informationList![panelIndex];
      item.isExpanded = isExpanded;
      updateExpandedInformationIds(
        _expandedInformationIds,
        item.id,
        isExpanded,
      );
    });

    // ensure header of expanded item is visible
    if (_informationList![panelIndex].isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(Duration(milliseconds: 100));
        final contextItem = _itemKeys[panelIndex].currentContext;
        if (contextItem != null) {
          Scrollable.ensureVisible(
            contextItem,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }

    if (kIsWeb) {
      if (_informationList![panelIndex].isExpanded) {
        jsInterop.changeUrl(
            "${RouterService.getCurrentUriWithOccasion()}${InfoPage.ROUTE}/${_informationList![panelIndex].id}");
      } else {
        jsInterop.changeUrl(
            "${RouterService.getCurrentUriWithOccasion()}${InfoPage.ROUTE}");
      }
    }
  }

  Future<void> loadDataOffline() async {
    _informationList = applyInformationExpansionState(
      (await OfflineDataService.getAllInfo()).filterByType(null),
      _expandedInformationIds,
    );
    // initialize keys for ensuring visibility
    _itemKeys = List.generate(_informationList!.length, (_) => GlobalKey());

    _isItemLoading = {
      for (int i = 0; i < _informationList!.length; i++) i: false
    };
  }
}
