import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/widgets/profile_place_field.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  Widget testApp({
    required PlaceModel? place,
    required ValueChanged<int> onOpenPlace,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProfilePlaceField(
          label: UserInfoModel.userGroupColumn,
          value: Tb.user_group_info.title,
          place: place,
          icon: Icons.groups_outlined,
          onOpenPlace: onOpenPlace,
        ),
      ),
    );
  }

  testWidgets('opens an assigned place through the canonical callback',
      (tester) async {
    final placeId = Tb.places.id.hashCode;
    int? openedPlaceId;

    await tester.pumpWidget(testApp(
      place: PlaceModel(id: placeId),
      onOpenPlace: (id) => openedPlaceId = id,
    ));

    await tester.tap(find.byType(InkWell));

    expect(openedPlaceId, placeId);
  });

  testWidgets('keeps an unassigned value read-only', (tester) async {
    int? openedPlaceId;

    await tester.pumpWidget(testApp(
      place: null,
      onOpenPlace: (id) => openedPlaceId = id,
    ));

    expect(find.byType(InkWell), findsNothing);
    expect(openedPlaceId, isNull);
  });

  test('cached user info retains the group place used by offline navigation',
      () {
    final placeId = Tb.places.id.hashCode;
    final cached = UserInfoModel(
      eventUserGroup: UserGroupInfoModel(
        id: Tb.user_group_info.id.hashCode,
        title: Tb.user_group_info.title,
        place: PlaceModel(id: placeId, title: Tb.places.title),
      ),
    ).toJson();

    final restored = UserInfoModel.fromJson(cached);

    expect(restored.eventUserGroup?.place?.id, placeId);
    expect(restored.eventUserGroup?.place?.title, Tb.places.title);
  });

  test('current profile stays canonical while occasion stay stays contextual',
      () {
    final profile = UserInfoModel.fromJson({
      'id': '00000000-0000-0000-0000-000000000001',
      'email_readonly': 'canonical@test.local',
      'name': 'Canonical',
      'surname': 'Person',
      'sex': 'female',
      'phone': 'canonical-phone',
      'birth_date': '2000-02-03',
      'occasionUser': {
        'occasion': 643,
        'user': '00000000-0000-0000-0000-000000000001',
        'data': {
          'email': 'historic@test.local',
          'name': 'Historic',
          'phone': 'historic-phone',
        },
        'services': {
          DbOccasions.serviceTypeAccommodation: {'room-a': 'paid'},
        },
      },
    });

    expect(profile.email, 'canonical@test.local');
    expect(profile.name, 'Canonical');
    expect(profile.phone, 'canonical-phone');
    expect(profile.birthDate, DateTime(2000, 2, 3));
    expect(profile.occasionUser?.data?['name'], 'Historic');
    expect(
      profile.occasionUser?.services?[DbOccasions.serviceTypeAccommodation],
      {'room-a': 'paid'},
    );

    final restored = UserInfoModel.fromJson(profile.toJson());
    expect(restored.phone, 'canonical-phone');
    expect(
      restored.occasionUser?.services?[DbOccasions.serviceTypeAccommodation]
          ?['room-a'],
      'paid',
    );
  });

  test('attaching participation cannot replace the current profile identity',
      () {
    final profile = UserInfoModel(
      id: '00000000-0000-0000-0000-000000000001',
      email: 'canonical@test.local',
      name: 'Canonical',
      surname: 'Person',
      sex: 'female',
      phone: 'canonical-phone',
      birthDate: DateTime(2000, 2, 3),
    );
    final participation = OccasionUserModel(
      occasion: 643,
      user: profile.id,
      data: {
        'email': 'historic@test.local',
        'name': 'Historic',
      },
      services: {
        DbOccasions.serviceTypeAccommodation: {'room-a': 'paid'},
      },
    );

    final combined = profile.withOccasionParticipation(participation);

    expect(combined.email, 'canonical@test.local');
    expect(combined.name, 'Canonical');
    expect(combined.phone, 'canonical-phone');
    expect(combined.occasionUser, same(participation));
    expect(
      combined.occasionUser?.services?[DbOccasions.serviceTypeAccommodation]
          ?['room-a'],
      'paid',
    );
  });
}
