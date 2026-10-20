/// Protocol-shaped replies shared by command transport tests. Deliberately
/// malformed replies derive from this fixture and remove the field under test.
Map<String, dynamic> commandResponseFixture(
  String commandId, {
  String status = 'applied',
  int code = 200,
  Map<String, dynamic> data = const {},
}) => {
  'status': status,
  'code': code,
  'data': data,
  'mutation': {
    'commandId': commandId,
    'receiptId': commandId,
    'commitId': status == 'applied'
        ? '00000000-0000-4000-8000-000000000001'
        : null,
    'replayed': status == 'expired',
    'occurredAt': '2026-10-20T00:00:00Z',
    if (status == 'expired') 'expired': true,
  },
  'sync': {'replacements': <Object>[]},
};
