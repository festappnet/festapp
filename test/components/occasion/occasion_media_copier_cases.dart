import '../../support/fixtures/localization_log_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_duplication.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/occasion/occasion_media_copier.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('duplicated occasion images are uploaded with one owner', () async {
    final ticket = TicketFeature(
      code: FeatureConstants.ticket,
      ticketBackground: 'https://img.festapp.net/images/ticket.jpg',
    );
    final layout = jsonDecode(File('test/fixtures/ticket_layout/layouts.json')
        .readAsStringSync())['valid'][0] as Map<String, dynamic>;
    ticket.layout = layout;
    final occasion = OccasionModel(
      id: 42,
      unit: 7,
      isOpen: false,
      isHidden: true,
      isPromoted: false,
      features: [ticket],
      data: {'image': 'https://img.festapp.net/images/event.jpg'},
    );
    final owners = <(int?, int?)>[];

    final changed =
        await copyOccasionMedia(occasion, (url, occasionId, unitId) async {
      owners.add((occasionId, unitId));
      return '$url-copy';
    });

    expect(changed, isTrue);
    expect(owners, [(42, null), (42, null)]);
    expect(ticket.ticketBackground, endsWith('-copy'));
    expect(ticket.layout, layout);
    expect(occasion.data!['image'], endsWith('-copy'));
  });

  test('shared ticket gallery artwork survives duplication without an upload',
      () async {
    const background =
        'https://img.festapp.net/ticket-presets/v1/silk-ivory-v1.jpg';
    final ticket = TicketFeature(
      code: FeatureConstants.ticket,
      ticketBackground: background,
    );
    final occasion = OccasionModel(
      id: 42,
      unit: 7,
      isOpen: false,
      isHidden: true,
      isPromoted: false,
      features: [ticket],
      data: {'image': 'https://img.festapp.net/images/event.jpg'},
    );
    final copied = <String>[];
    await copyOccasionMedia(occasion, (url, occasionId, unitId) async {
      copied.add(url);
      return '$url-copy';
    });
    expect(copied, ['https://img.festapp.net/images/event.jpg']);
    expect(ticket.ticketBackground, background);
  });

  test('copy without media performs one SQL command and no follow-up save',
      () async {
    final fixture = _DuplicationFixture();
    final result = await fixture.duplicator.duplicate(7);
    expect(result, (occasionId: 42, mediaCopied: true));
    expect(fixture.calls.map((call) => call.$1),
        ['duplicate_occasion_client_sync_v1']);
    expect(fixture.copied, isEmpty);
  });

  test('shared image source is copied once and its references saved together',
      () async {
    final fixture = _DuplicationFixture(sharedImage: true);
    final result = await fixture.duplicator.duplicate(7,
        targetUnitId: 8,
        locale: 'cs',
        commandId: '00000000-0000-4000-8000-000000000007');
    expect(result, (occasionId: 42, mediaCopied: true));
    expect(fixture.copied, ['https://img.festapp.net/shared.jpg']);
    expect(fixture.calls.map((call) => call.$1),
        ['duplicate_occasion_client_sync_v1', 'save_occasion_client_sync_v1']);
    final creation = fixture.calls.first.$2;
    expect(creation['p_command_id'], '00000000-0000-4000-8000-000000000007');
    expect(creation['p_target_unit'], 8);
    expect(creation['p_locale'], 'cs');
    final save = fixture.calls.last.$2;
    expect(save['p_expected_version'], 3);
    final config = save['p_config'];
    expect(config['data']['image'], endsWith('-copy'));
    expect(config['features'][0][FeatureConstants.ticketBackground], config['data']['image']);
  });

  test('unchanged media URL requires no additional SQL write', () async {
    final fixture =
        _DuplicationFixture(sharedImage: true, unchangedImage: true);
    expect((await fixture.duplicator.duplicate(7)).mediaCopied, isTrue);
    expect(fixture.copied, hasLength(1));
    expect(fixture.calls, hasLength(1));
  });

  for (final stage in ['load', 'copy', 'save']) {
    test(
        '$stage failure preserves the committed occasion and never repeats creation',
        () async {
      final fixture = _DuplicationFixture(sharedImage: true, failure: stage);
      expect(await fixture.duplicator.duplicate(7),
          (occasionId: 42, mediaCopied: false));
      expect(fixture.calls.where((call) => call.$1.startsWith('duplicate')),
          hasLength(1));
      expect(fixture.calls.where((call) => call.$1.startsWith('save')),
          hasLength(stage == 'save' ? 1 : 0));
    });
  }

  test('unconfirmed creation never enters media setup', () async {
    final fixture = _DuplicationFixture(failure: 'create');
    await expectLater(
        fixture.duplicator.duplicate(7), throwsA(isA<FormatException>()));
    expect(fixture.loads, 0);
    expect(fixture.copied, isEmpty);
  });
}

class _DuplicationFixture {
  _DuplicationFixture(
      {this.sharedImage = false, this.unchangedImage = false, this.failure});
  final bool sharedImage;
  final bool unchangedImage;
  final String? failure;
  final calls = <(String, Map<String, dynamic>)>[];
  final copied = <String>[];
  var loads = 0;

  late final duplicator = OccasionDuplicator(
    commands: SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, parameters) async {
      calls.add((name, parameters));
      if (failure == 'create')
        return {
          'code': 200,
          'data': {'occasionId': 42}
        };
      if (failure == 'save' && name.startsWith('save'))
        throw StateError('save failed');
      return commandResponseFixture(parameters['p_command_id'],
          data: name.startsWith('duplicate')
              ? {'occasionId': 42}
              : {
                  'occasion': {
                    ...parameters['p_config'],
                    'aggregate_version': 4
                  }
                });
    })),
    loadOccasion: (id) async {
      loads++;
      expect(id, 42);
      if (failure == 'load') throw StateError('load failed');
      return OccasionModel(
          id: id,
          aggregateVersion: 3,
          isOpen: false,
          isHidden: true,
          isPromoted: false,
          features: sharedImage
              ? [
                  TicketFeature(
                      code: FeatureConstants.ticket,
                      ticketBackground: 'https://img.festapp.net/shared.jpg')
                ]
              : [],
          data: sharedImage
              ? {'image': 'https://img.festapp.net/shared.jpg'}
              : {});
    },
    copyImage: (url, occasion, unit) async {
      expect((occasion, unit), (42, null));
      copied.add(url);
      if (failure == 'copy') throw StateError('copy failed');
      return unchangedImage ? url : '$url-copy';
    },
  );
}
