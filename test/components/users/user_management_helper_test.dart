import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/user_management_helper.dart';

void main() {
  testWidgets('admin can set an existing user password without a legacy email',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));

    final user =
        OccasionUserModel(user: '00000000-0000-0000-0000-000000000001');
    String? changedPassword;

    await UserManagementHelper.unsafeChangeUserPassword(
      context,
      user,
      requestPassword: (_) async => 'new-password',
      changePassword: (target, password) async {
        expect(target, same(user));
        changedPassword = password;
      },
    );

    expect(changedPassword, 'new-password');
  });
}
