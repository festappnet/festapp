// Real seating RPCs and production worklist/canvas against disposable loopback
// PostgREST. Never accepts a remote endpoint or a production credential source.
import 'dart:convert';

import 'package:fstapp/services/web_bootstrap_bridge.dart';

import 'package:fstapp/widgets/dependency_material_bridge.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/seating_transition_controller.dart';
import 'package:fstapp/components/blueprint/seating_transition_models.dart';
import 'package:fstapp/components/blueprint/seating_transition_panel.dart';
import 'package:fstapp/components/blueprint/seating_transition_transport.dart';
import 'package:fstapp/components/blueprint/views/blueprint_plan_editor.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_saver.dart';
import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/blueprint/seating_transition_strings.dart';

const _endpoint = String.fromEnvironment('SEATING_E2E_REST_URL');
const _jwt = String.fromEnvironment('SEATING_E2E_JWT');
// Query values select only fixed fixtures supplied by the disposable owner.
// They never become database IDs, actor credentials or arbitrary RPC scope.
final _scenario = Uri.base.queryParameters['scenario'] ?? 'original';
int get _occasion => switch (_scenario) {
  'original' => const int.fromEnvironment('SEATING_E2E_OCCASION'),
  'publication' => const int.fromEnvironment(
    'SEATING_E2E_PUBLICATION_OCCASION',
  ),
  'pagination' => const int.fromEnvironment('SEATING_E2E_PAGINATION_OCCASION'),
  _ => throw StateError('Unknown local seating scenario'),
};
int get _blueprint => switch (_scenario) {
  'original' => const int.fromEnvironment('SEATING_E2E_BLUEPRINT'),
  'publication' => const int.fromEnvironment(
    'SEATING_E2E_PUBLICATION_BLUEPRINT',
  ),
  'pagination' => const int.fromEnvironment('SEATING_E2E_PAGINATION_BLUEPRINT'),
  _ => throw StateError('Unknown local seating scenario'),
};
String get _link => switch (_scenario) {
  'original' => const String.fromEnvironment('SEATING_E2E_LINK'),
  'publication' => const String.fromEnvironment('SEATING_E2E_PUBLICATION_LINK'),
  'pagination' => const String.fromEnvironment('SEATING_E2E_PAGINATION_LINK'),
  _ => throw StateError('Unknown local seating scenario'),
};

Future<Object?> _rpc(String name, Map<String, dynamic> parameters) async {
  final response = await http.post(
    Uri.parse('$_endpoint/rpc/$name'),
    headers: {
      'authorization': 'Bearer $_jwt',
      'content-type': 'application/json',
    },
    body: jsonEncode(parameters),
  );
  if (response.statusCode != 200) {
    if (response.statusCode == 403) throw const SeatingRejection('FORBIDDEN');
    throw StateError('Local seating RPC failed (${response.statusCode})');
  }
  return jsonDecode(response.body);
}

Future<BlueprintModel> _loadPlan() async {
  final result = seatingMap(
    await _rpc('get_blueprint_for_edit', {
      'occasion_link': _link,
      'p_blueprint_id': _blueprint,
    }),
  );
  return BlueprintModel.fromJson(seatingMap(result['data']));
}

Future<void> main() async {
  final endpoint = Uri.parse(_endpoint);
  if (!const bool.fromEnvironment('SEATING_E2E_DISPOSABLE') ||
      !{'127.0.0.1', 'localhost'}.contains(endpoint.host) ||
      _jwt.isEmpty ||
      _occasion == 0 ||
      _blueprint == 0) {
    throw StateError(
      'Seating browser check requires an explicitly marked disposable loopback target',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => WebBootstrapBridge.markAppReady(),
  );
  await EasyLocalization.ensureInitialized();
  final plan = await _loadPlan();
  final transport = SeatingTransitionTransport.withTransport(
    _rpc,
    ClientCommandTransport(
      _rpc,
      principalBinding: 'seating-e2e:$_endpoint:$_occasion',
      retrySerialization: true,
    ),
  );
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs'), Locale('en')],
      startLocale: const Locale('cs'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      child: _App(plan: plan, transport: transport),
    ),
  );
}

class _App extends StatelessWidget {
  const _App({required this.plan, required this.transport});
  final BlueprintModel plan;
  final SeatingTransitionTransport transport;
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: context.locale,
    supportedLocales: context.supportedLocales,
    localizationsDelegates: [
      ...context.localizationDelegates,
      ...GlobalMaterialLocalizations.delegates,
    ],
    builder: DependencyMaterialBridge.builder,
    home: _Workspace(plan: plan, transport: transport),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.plan, required this.transport});
  final BlueprintModel plan;
  final SeatingTransitionTransport transport;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late BlueprintModel plan = widget.plan;
  late final blueprint = BlueprintLayoutController(
    source: plan,
    saver: BlueprintLayoutSaver(
      SupabaseFormCommands.withTransport(
        ClientCommandTransport(
          _rpc,
          principalBinding: 'seating-e2e:$_endpoint:$_occasion',
          retrySerialization: true,
        ),
      ),
    ),
  );
  bool _open = false;
  String? _error;
  late final seating = SeatingTransitionController(
    transport: widget.transport,
    occasionId: _occasion,
    blueprintId: _blueprint,
  );
  @override
  void initState() {
    super.initState();
    seating.load(discover: true);
  }

  @override
  void dispose() {
    seating.dispose();
    blueprint.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final updated = await _loadPlan();
    if (mounted)
      setState(() {
        plan = updated;
        blueprint.refreshLive(updated);
      });
  }

  Future<void> _openWorkspace() async {
    await finishBlueprintTextEditing();
    if (!mounted) return;
    final ready = await confirmSeatingSavedPlan(
      context,
      isDirty: () => blueprint.isDirty,
      save: () async {
        try {
          await blueprint.save();
        } catch (_) {
          if (mounted)
            setState(
              () => _error = SeatingTransitionStrings.text('UNAVAILABLE'),
            );
        }
      },
      discard: blueprint.cancel,
    );
    if (!mounted || !ready) return;
    setState(() => _open = true);
    await seating.load(discover: true);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([seating, blueprint]),
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!_open)
              SeatingTransitionSummary(
                controller: seating,
                open: _openWorkspace,
              ),
            if (_error != null) Text(_error!),
            Expanded(
              child: SeatingWorkspaceFrame(
                active: _open,
                panel: SeatingTransitionPanel(
                  controller: seating,
                  onClose: () => setState(() => _open = false),
                  onCommitted: _refresh,
                ),
                child: BlueprintPlanEditor(
                  controller: blueprint.layout,
                  occasionId: _occasion,
                  interactionEnabled: !_open,
                  toolbarTrailing: !_open
                      ? EditorActionBar(
                          inline: true,
                          hasChanges: blueprint.isDirty,
                          enabled: !blueprint.isBusy,
                          onSave: () async {
                            try {
                              await blueprint.save();
                            } catch (_) {
                              if (mounted)
                                setState(
                                  () => _error = SeatingTransitionStrings.text(
                                    'UNAVAILABLE',
                                  ),
                                );
                            }
                          },
                          onDiscard: () async => blueprint.cancel(),
                        )
                      : null,
                  showGallery: !_open,
                  openGalleryOnStart: false,

                  inspectorOverride: _open ? const SizedBox.shrink() : null,
                  viewSelection: !_open
                      ? null
                      : {
                          for (final seat
                              in plan.layoutSnapshot!.seatBindings.values)
                            if (seating.pairs.values.any(
                              (p) => p.targetSpotId == seat.spotId,
                            ))
                              seat.nodeId,
                        },
                  viewSelectableIds: !_open
                      ? null
                      : {
                          for (final seat
                              in plan.layoutSnapshot!.seatBindings.values)
                            if (seating.selectableSpotIds.contains(seat.spotId))
                              seat.nodeId,
                        },
                  viewSelectionTarget: (id) => id,
                  onViewSelectionChanged: (ids) {
                    if (ids.isNotEmpty) {
                      final spot =
                          plan.layoutSnapshot!.seatBindings[ids.last]?.spotId;
                      if (spot != null) seating.pair(spot);
                    }
                  },
                  seatPresentation: {
                    for (final seat in plan.layoutSnapshot!.seatBindings.values)
                      seat.nodeId: {
                        'label': seat.title,
                        'accessibilityLabel': seat.title,
                        'highlighted': seating.compatible.any(
                          (s) => s.id == seat.spotId,
                        ),
                        'fill':
                            seating.context?.seats.any(
                                  (s) => s.id == seat.spotId && s.available,
                                ) ==
                                true
                            ? '#267329FF'
                            : '#999999FF',
                      },
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
