/// A complete two-ticket atomic swap, including its authoritative money effect.
Map<String, dynamic> blueprintSwapPreviewFixture() => {
      'code': 200,
      'occasionId': 1,
      'blueprintId': 1,
      'layoutRevision': 1,
      'firstSpotId': 11,
      'secondSpotId': 13,
      'sourceSpotIds': [11, 15],
      'targetSpotIds': [13, 14],
      'confirmationHash': List.filled(64, 'b').join(),
      'seats': [
        for (final id in [11, 15])
          {
            'spotId': id,
            'title': id == 11 ? 'Approved source' : 'Source companion',
            'state': 'ordered',
            'productId': 1,
            'productTitle': 'Seat',
            'orderId': 77,
            'ticketId': id == 11 ? 51 : 52,
            'customer': {
              'name': 'Synthetic',
              'surname': 'Customer',
              'email': 'swap@example.invalid'
            },
          },
        for (final id in [13, 14])
          {
            'spotId': id,
            'title':
                id == 13 ? 'Approved destination' : 'Destination companion',
            'state': 'available',
            'productId': 2,
            'productTitle': 'Premium seat',
            'orderId': null,
            'ticketId': null,
          },
      ],
      'orders': [
        {
          'orderId': 77,
          'beforeAmount': '200.00',
          'afterAmount': '300.00',
          'delta': '100.00',
          'currencyCode': 'CZK',
          'beforeState': 'paid',
          'afterState': 'ordered'
        },
      ],
    };
