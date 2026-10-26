[![Pub Package](https://img.shields.io/pub/v/nm.svg)](https://pub.dev/packages/nm)
[![codecov](https://codecov.io/gh/canonical/nm.dart/branch/main/graph/badge.svg?token=6P72PJAA7F)](https://codecov.io/gh/canonical/nm.dart)

Provides a client to connect to [NetworkManager](https://gitlab.freedesktop.org/NetworkManager/NetworkManager) - the service that manages network connections on Linux.

```dart
import 'package:nm/nm.dart';

var client = NetworkManagerClient();
await client.connect();
print('Running NetworkManager ${client.version}');
await client.close();
```

## Contributing to nm.dart

We welcome contributions! See the [contribution guide](CONTRIBUTING.md) for more details.
