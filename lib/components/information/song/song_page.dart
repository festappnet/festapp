import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/information/song/song_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';

@RoutePage()
class SongbookPage extends StatefulWidget {
  final String? type = "song";
  static const ROUTE = "songbook";

  const SongbookPage({super.key});

  @override
  _SongbookPageState createState() => _SongbookPageState();
}

class _SongbookPageState extends State<SongbookPage> {
  List<InformationModel>? _informationList;
  static bool? isDarkMode;
  static bool isDarkModeDefault = false;

  final ThemeData lightTheme = ThemeConfig.theme();
  final ThemeData darkTheme = ThemeConfig.theme(brightness: Brightness.dark);

  bool _isDialogOpen = false;

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
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadData();
  }

  @override
  Widget build(BuildContext context) {
    isDarkMode = isDarkMode ?? ThemeConfig.isDarkMode(context);
    return PopScope(
      onPopInvokedWithResult: (result, x) {
        if (_isDialogOpen) {
          Navigator.of(context).pop(); // Close the dialog
          setState(() {
            _isDialogOpen = false;
          });
          result = false;
        }
        result = true; // Allow page pop
      },
      child: Theme(
        data: isDarkMode ?? isDarkModeDefault ? darkTheme : lightTheme,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              CommonStrings.songbook,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            leading: BackButton(
              onPressed: () {
                if (_isDialogOpen) {
                  Navigator.of(context).pop(); // Close the dialog
                  setState(() {
                    _isDialogOpen = false;
                  });
                } else {
                  RouterService.popOrHome(context); // Pop the page
                }
              },
            ),
            actions: [
              Row(
                children: [
                  Icon(Icons.wb_sunny, color: Colors.grey),
                  Switch(
                    value: isDarkMode ?? isDarkModeDefault,
                    onChanged: (value) {
                      setState(() {
                        isDarkMode = value;
                      });
                    },
                    activeThumbColor: Colors.grey[600],
                    inactiveThumbColor: Colors.grey[400],
                    inactiveTrackColor: Colors.grey[300],
                    activeTrackColor: Colors.grey[600],
                  ),
                  Icon(Icons.nightlight_round, color: Colors.grey),
                ],
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
              child: ListView.builder(
                itemCount: _informationList?.length ?? 0,
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return Column(
                      children: [
                        SizedBox(height: 16),
                        buildListItem(index),
                      ],
                    );
                  }
                  return buildListItem(index);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildListItem(int index) {
    return TextButton(
      onPressed: () async {
        await loadItemDescription(index);
        setState(() {
          _isDialogOpen = true;
        });
        showDialog(
          context: context,
          builder: (context) => SongDialog(
            title: _informationList![index].title ?? "",
            description: _informationList![index].description ?? "",
            isDarkMode: isDarkMode ?? isDarkModeDefault,
          ),
        ).then((_) {
          setState(() {
            _isDialogOpen = false;
          });
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          _informationList![index].title ?? "-",
          textAlign: TextAlign.left,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Future<void> loadData() async {
    _informationList =
        (await OfflineDataService.getAllInfo()).filterByType(widget.type);
    setState(() {});
    if (ClientSyncRuntime.isV1Selected) return;
    var allInfo = await DbInformation.getAllActiveInformation();
    _informationList = allInfo.filterByType(widget.type);
    OfflineDataService.saveAllInfo(allInfo);
    setState(() {});
  }

  Future<void> loadItemDescription(int index) async {
    var info = _informationList![index];
    await DbInformation.fillDescriptionFromOffline(info);
  }
}
