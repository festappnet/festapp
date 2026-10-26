import 'package:auto_route/auto_route.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/information/game/game_settings_model.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart' show ThemeConfig;
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'dart:async';

@RoutePage()
class GamePage extends StatefulWidget {
  final String? type = InformationModel.gameType;

  static const ROUTE = "game";

  const GamePage({super.key});

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const refreshInterval = Duration(seconds: 5);

  List<InformationModel> _gameList = [];
  Set<int> _correctGuesses = {};
  String _groupTitle = CommonStrings.game;
  GameSettingsModel? _gameSettings;
  Timer? _countdownTimer;
  Timer? _correctGuessesTimer;
  Duration? _remainingTime;
  bool _isUserInGameGroup = false;
  bool _isOffline = false; // Track offline status

  late StreamSubscription _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    loadGameData();
    if (!ClientSyncRuntime.isV1Selected) {
      _correctGuessesTimer = Timer.periodic(refreshInterval, (timer) {
        loadCorrectGuesses();
      });
    }

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOffline = result.contains(ConnectivityResult.none);
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _correctGuessesTimer?.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> loadGameData() async {
    _gameSettings = await DbOccasions.loadGameSettings();
    var userGroups = await DbGroups.getUserGroups();

    _isUserInGameGroup =
        userGroups.any((g) => g.type == InformationModel.gameType);

    if (_isUserInGameGroup) {
      var userGroup =
          userGroups.firstWhere((g) => g.type == InformationModel.gameType);
      setState(() {
        _groupTitle = userGroup.title;
      });
    }

    var allInfo = await DbInformation.getAllInformationForDataGrid(
        InformationModel.gameType);
    setState(() {
      _gameList = allInfo.toList();
    });

    await loadCorrectGuesses();

    if (_gameSettings != null && DateTime.now().isBefore(_gameSettings!.end!)) {
      if (DateTime.now().isAfter(_gameSettings!.start!)) {
        startCountdown(_gameSettings!.end!);
      }
    }
  }

  Future<void> loadCorrectGuesses() async {
    if (!_isUserInGameGroup) return;

    var correctGuesses = await DbGroups.getCorrectlyGuessedCheckpoints();
    setState(() {
      _correctGuesses = correctGuesses.toSet();
    });
  }

  void startCountdown(DateTime endTime) {
    _remainingTime = endTime.difference(DateTime.now());
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _remainingTime = endTime.difference(DateTime.now());
        if (_remainingTime!.isNegative) {
          _countdownTimer?.cancel();
          _remainingTime = null;
          Navigator.of(context, rootNavigator: true)
              .popUntil((route) => route.isFirst);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hasNotStarted =
        _gameSettings != null && now.isBefore(_gameSettings!.start!);
    final hasEnded = _gameSettings != null && now.isAfter(_gameSettings!.end!);

    return Scaffold(
      appBar: AppBar(
        title: Text(_groupTitle),
        leading: BackButton(
          onPressed: () => RouterService.popOrHome(context),
        ),
      ),
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _gameList.length,
                itemBuilder: (BuildContext context, int index) {
                  return GestureDetector(
                    onTap: () => _showGuessDialog(context, index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _correctGuesses.contains(_gameList[index].id)
                            ? ThemeConfig.correctGuessColor(context)
                            : Colors.grey,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _gameList[index].title ?? "-",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (!_isUserInGameGroup)
            _buildOverlay(InformationStrings.gameNeedsGroup),

          if (_isUserInGameGroup && hasNotStarted)
            _buildOverlay(InformationStrings.gameNotStarted),

          if (_isUserInGameGroup &&
              !hasNotStarted &&
              !hasEnded &&
              _remainingTime != null)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  InformationStrings.gameTimeLeft(
                      time:
                          "${_remainingTime!.inHours}:${(_remainingTime!.inMinutes % 60).toString().padLeft(2, '0')}:${(_remainingTime!.inSeconds % 60).toString().padLeft(2, '0')}"),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),

          if (_isUserInGameGroup && hasEnded)
            _buildOverlay(InformationStrings.gameEnded),

          // Overlay for offline status
          if (_isOffline) _buildOverlay(InformationStrings.offlineWarning),
        ],
      ),
    );
  }

  Widget _buildOverlay(String message) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showGuessDialog(BuildContext context, int index) async {
    String? userGuess;
    String gameTitle = _gameList[index].title ?? CommonStrings.game;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(InformationStrings.gameCheckPoint(title: gameTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => userGuess = value,
                decoration: InputDecoration(
                  hintText: InformationStrings.gameTakeAGuess,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                var isCorrect = await DbInformation.makeGameGuess(
                    context, _gameList[index].id!, userGuess ?? "");
                if (isCorrect) {
                  setState(() {
                    _correctGuesses.add(_gameList[index].id!);
                  });
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(InformationStrings.gameGuess),
            ),
          ],
        );
      },
    );
  }
}
