import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_io.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_layout.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_tab.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'occasion_settings_ticket_data.dart';

/// Explicit in-memory I/O for the real occasion settings page. No Supabase
/// client is installed. Unsupported local operations fail before any transport.
class OccasionSettingsFixture {
  int saves = 0, refreshes = 0, ticketSaves = 0, uploads = 0;
  OccasionModel saved = OccasionModel(
    id: 991,
    unit: 97,
    organization: 95,
    link: 'ples-u-lipy',
    title: 'Společenský ples U Lípy',
    startTime: DateTime(2027, 2, 20, 19),
    endTime: DateTime(2027, 2, 21, 2),
    description: '<p>Zveme Vás na večer plný hudby a tance.</p>',
    isOpen: true,
    isHidden: false,
    isPromoted: false,
    data: {'place_name': 'Kulturní dům U Lípy', 'timezone': 'Europe/Prague'},
    features: [
      FormFeature(
        code: FeatureConstants.form,
        isEnabled: true,
        reserveButtonTitle: 'Rezervovat vstupenky',
        reminderIsEnabled: true,
        deadlineDurationSeconds: 604800,
        reminderIntervalSeconds: 86400,
      ),
      TicketFeature(code: FeatureConstants.ticket, isEnabled: true),
    ],
  );
  late final ticketService = LocalOccasionTicketService();
  late final htmlSave = HtmlSaveCoordinator(
    media: HtmlMediaDraft(
      fetch: (source, owner) async =>
          throw StateError('Místní náhled nepřebírá vzdálené obrázky.'),
      owns: (source, owner) async => source.startsWith('data:image/'),
      upload: (bytes, owner) async => localImage(bytes),
    ),
  );
  String localImage(Uint8List bytes) {
    uploads++;
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  OccasionModel copy() =>
      OccasionModel.fromJson(jsonDecode(jsonEncode(saved.toJson())));
  void installRights({bool editable = true}) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      code: 200,
      occasion: copy(),
      capabilities: {
        AuthorizationCapabilities.occasionsWrite: editable,
        AuthorizationCapabilities.ticketLayoutsWrite: editable,
        // Deletion is deliberately unavailable in this fixture.
      },
    );
  }

  late final io = OccasionSettingsIo(
    updateOccasion: (occasion) async {
      saved = OccasionModel.fromJson(jsonDecode(jsonEncode(occasion.toJson())));
      saves++;
    },
    refreshSaved: (context, previous, next) async {
      refreshes++;
    },
    reloadOccasion: (id) async => copy(),
    uploadImage: (bytes, id) async => localImage(bytes),
  );
  Widget page() => OccasionSettingsTab(
    loadOccasion: (_) async => copy(),
    io: io,
    htmlSave: htmlSave,
    ticketLayoutService: ticketService,
    saveTicketLayout: (occasion, draft) async {
      saved.features.whereType<TicketFeature>().first.loadSavedLayout(
        draft.layout,
      );
      ticketSaves++;
    },
    initialChapter: OccasionSettingsChapter.features,
  );
}

class OccasionSettingsFixtureRouter extends RootStackRouter {
  OccasionSettingsFixtureRouter(this.fixture);
  final OccasionSettingsFixture fixture;
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo(
        'OccasionSettingsPreview',
        builder: (_) => Scaffold(body: fixture.page()),
      ),
      path: '/:${AppRouter.linkFormatted}/settings',
    ),
  ];
}

class LocalOccasionTicketService extends TicketLayoutService {
  LocalOccasionTicketService()
    : super(
        transport: (_) async =>
            throw StateError('Tato operace vyžaduje připojený backend.'),
        readPreference: (_) async => 'true',
        writePreference: (_, _) async {},
      );
  @override
  Future<bool> walletReady(int organizationId) async => false;
  @override
  Future<Map<String, dynamic>> deliveryPreview({
    required int occasionId,
    required TicketDeliveryMode mode,
    required bool walletEnabled,
  }) async => {
    'title': 'Společenský ples U Lípy',
    'tone': 'formal',
    'subject': 'Vaše vstupenky na ples',
    'html': '<p>Děkujeme za Vaši objednávku.</p>',
  };
  @override
  Future<String?> uploadWalletImage(
    Uint8List bytes,
    int? occasionId,
    int? unitId,
  ) async => 'data:image/png;base64,${base64Encode(bytes)}';
  @override
  Future<String?> uploadBackground(Uint8List bytes, int occasionId) async =>
      'data:image/png;base64,${base64Encode(bytes)}';
  @override
  Future<bool> openTemplatePickerOnce(
    int occasionId,
    String userId, {
    required bool configured,
  }) async => false;
  @override
  Future<TicketLayoutResources> resolve(
    int occasionId,
    String type,
    Map<String, dynamic>? layout,
    String? background, {
    bool borrowResourcesOnly = false,
    bool readOnly = false,
  }) async {
    final data = jsonDecode(occasionSettingsTicketData) as Map;
    final template = TicketTemplate.fromJson(data['template']);
    return TicketLayoutResources(
      template: template,
      preset: template,
      scenarios: (data['scenarios'] as Map).map(
        (k, v) => MapEntry(k as String, Map<String, String?>.from(v)),
      ),
      metrics: TicketFontMetrics.fromJson(data['metrics']),
      qrSize: data['qrMatrix']['size'],
      qrModules: (data['qrMatrix']['data'] as List).cast<int>(),
    );
  }
}
