import 'dart:async';

import 'package:dbus/dbus.dart';

/// D-Bus interface names
const _managerInterfaceName = 'org.freedesktop.NetworkManager';
const _settingsInterfaceName = 'org.freedesktop.NetworkManager.Settings';
const _settingsConnectionInterfaceName =
    'org.freedesktop.NetworkManager.Settings.Connection';
const _dnsManagerInterfaceName = 'org.freedesktop.NetworkManager.DnsManager';
const _deviceInterfaceName = 'org.freedesktop.NetworkManager.Device';
const _bluetoothDeviceInterfaceName =
    'org.freedesktop.NetworkManager.Device.Bluetooth';
const _bridgeDeviceInterfaceName =
    'org.freedesktop.NetworkManager.Device.Bridge';
const _genericDeviceInterfaceName =
    'org.freedesktop.NetworkManager.Device.Generic';
const _statisticsDeviceInterfaceName =
    'org.freedesktop.NetworkManager.Device.Statistics';
const _tunDeviceInterfaceName = 'org.freedesktop.NetworkManager.Device.Tun';
const _vlanDeviceInterfaceName = 'org.freedesktop.NetworkManager.Device.Vlan';
const _wiredDeviceInterfaceName = 'org.freedesktop.NetworkManager.Device.Wired';
const _wirelessDeviceInterfaceName =
    'org.freedesktop.NetworkManager.Device.Wireless';
const _activeConnectionInterfaceName =
    'org.freedesktop.NetworkManager.Connection.Active';
const _ip4ConfigInterfaceName = 'org.freedesktop.NetworkManager.IP4Config';
const _dhcp4ConfigInterfaceName = 'org.freedesktop.NetworkManager.DHCP4Config';
const _ip6ConfigInterfaceName = 'org.freedesktop.NetworkManager.IP6Config';
const _dhcp6ConfigInterfaceName = 'org.freedesktop.NetworkManager.DHCP6Config';
const _accessPointInterfaceName = 'org.freedesktop.NetworkManager.AccessPoint';

/// Overall networking states.
enum NetworkManagerState {
  unknown,
  asleep,
  disconnected,
  disconnecting,
  connecting,
  connectedLocal,
  connectedSite,
  connectedGlobal,
}

NetworkManagerState _decodeState(int value) {
  switch (value) {
    case 10:
      return NetworkManagerState.asleep;
    case 20:
      return NetworkManagerState.disconnected;
    case 30:
      return NetworkManagerState.disconnecting;
    case 40:
      return NetworkManagerState.connecting;
    case 50:
      return NetworkManagerState.connectedLocal;
    case 60:
      return NetworkManagerState.connectedSite;
    case 70:
      return NetworkManagerState.connectedGlobal;
    default:
      return NetworkManagerState.unknown;
  }
}

/// Internet connectivity states.
enum NetworkManagerConnectivityState { unknown, none, portal, limited, full }

NetworkManagerConnectivityState _decodeConnectivityState(int value) {
  switch (value) {
    case 1:
      return NetworkManagerConnectivityState.none;
    case 2:
      return NetworkManagerConnectivityState.portal;
    case 3:
      return NetworkManagerConnectivityState.limited;
    case 4:
      return NetworkManagerConnectivityState.full;
    default:
      return NetworkManagerConnectivityState.unknown;
  }
}

/// Device states.
enum NetworkManagerDeviceState {
  unknown,
  unmanaged,
  unavailable,
  disconnected,
  prepare,
  config,
  needAuth,
  ipConfig,
  ipCheck,
  secondaries,
  activated,
  deactivating,
  failed
}

NetworkManagerDeviceState _decodeDeviceState(int value) {
  switch (value) {
    case 10:
      return NetworkManagerDeviceState.unmanaged;
    case 20:
      return NetworkManagerDeviceState.unavailable;
    case 30:
      return NetworkManagerDeviceState.disconnected;
    case 40:
      return NetworkManagerDeviceState.prepare;
    case 50:
      return NetworkManagerDeviceState.config;
    case 60:
      return NetworkManagerDeviceState.needAuth;
    case 70:
      return NetworkManagerDeviceState.ipConfig;
    case 80:
      return NetworkManagerDeviceState.ipCheck;
    case 90:
      return NetworkManagerDeviceState.secondaries;
    case 100:
      return NetworkManagerDeviceState.activated;
    case 110:
      return NetworkManagerDeviceState.deactivating;
    case 120:
      return NetworkManagerDeviceState.failed;
    default:
      return NetworkManagerDeviceState.unknown;
  }
}

/// Reasons for a device state.
enum NetworkManagerDeviceStateReason {
  none,
  unknown,
  nowManaged,
  nowUnmanaged,
  configFailed,
  ipConfigUnavailable,
  ipConfigExpired,
  noSecrets,
  supplicantDisconnect,
  supplicantConfigFailed,
  supplicantFailed,
  supplicantTimeout,
  pppStartFailed,
  pppDisconnect,
  pppFailed,
  dhcpStartFailed,
  dhcpError,
  dhcpFailed,
  sharedStartFailed,
  sharedFailed,
  autoIpStartFailed,
  autoIpError,
  autoIpFailed,
  modemBusy,
  modemNoDialTone,
  modemNoCarrier,
  modemDialTimeout,
  modemDialFailed,
  modemInitFailed,
  gsmApnFailed,
  gsmRegistrationNotSearching,
  gsmRegistrationDenied,
  gsmRegistrationTimeout,
  gsmRegistrationFailed,
  gsmPinCheckFailed,
  firmwareMissing,
  removed,
  sleeping,
  connectionRemoved,
  userRequested,
  carrier,
  connectionAssumed,
  supplicantAvailable,
  modemNotFound,
  btFailed,
  gsmSimNotInserted,
  gsmSimPinRequired,
  gsmSimPukRequired,
  gsmSimWrong,
  infinibandMode,
  dependencyFailed,
  br2684Failed,
  modemManagerUnavailable,
  ssidNotFound,
  secondaryConnectionFailed,
  dcbFcoeFailed,
  teamdControlFailed,
  modemFailed,
  modemAvailable,
  simPinIncorrect,
  newActivation,
  parentChanged,
  parentManagedChanged,
  ovsdbFailed,
  ipAddressDuplicate,
  ipMethodUnsupported,
  sriovConfigurationFailed,
  peerNotFound
}

NetworkManagerDeviceStateReason _decodeDeviceStateReason(int value) {
  switch (value) {
    case 0:
      return NetworkManagerDeviceStateReason.none;
    case 1:
      return NetworkManagerDeviceStateReason.unknown;
    case 2:
      return NetworkManagerDeviceStateReason.nowManaged;
    case 3:
      return NetworkManagerDeviceStateReason.nowUnmanaged;
    case 4:
      return NetworkManagerDeviceStateReason.configFailed;
    case 5:
      return NetworkManagerDeviceStateReason.ipConfigUnavailable;
    case 6:
      return NetworkManagerDeviceStateReason.ipConfigExpired;
    case 7:
      return NetworkManagerDeviceStateReason.noSecrets;
    case 8:
      return NetworkManagerDeviceStateReason.supplicantDisconnect;
    case 9:
      return NetworkManagerDeviceStateReason.supplicantConfigFailed;
    case 10:
      return NetworkManagerDeviceStateReason.supplicantFailed;
    case 11:
      return NetworkManagerDeviceStateReason.supplicantTimeout;
    case 12:
      return NetworkManagerDeviceStateReason.pppStartFailed;
    case 13:
      return NetworkManagerDeviceStateReason.pppDisconnect;
    case 14:
      return NetworkManagerDeviceStateReason.pppFailed;
    case 15:
      return NetworkManagerDeviceStateReason.dhcpStartFailed;
    case 16:
      return NetworkManagerDeviceStateReason.dhcpError;
    case 17:
      return NetworkManagerDeviceStateReason.dhcpFailed;
    case 18:
      return NetworkManagerDeviceStateReason.sharedStartFailed;
    case 19:
      return NetworkManagerDeviceStateReason.sharedFailed;
    case 20:
      return NetworkManagerDeviceStateReason.autoIpStartFailed;
    case 21:
      return NetworkManagerDeviceStateReason.autoIpError;
    case 22:
      return NetworkManagerDeviceStateReason.autoIpFailed;
    case 23:
      return NetworkManagerDeviceStateReason.modemBusy;
    case 24:
      return NetworkManagerDeviceStateReason.modemNoDialTone;
    case 25:
      return NetworkManagerDeviceStateReason.modemNoCarrier;
    case 26:
      return NetworkManagerDeviceStateReason.modemDialTimeout;
    case 27:
      return NetworkManagerDeviceStateReason.modemDialFailed;
    case 28:
      return NetworkManagerDeviceStateReason.modemInitFailed;
    case 29:
      return NetworkManagerDeviceStateReason.gsmApnFailed;
    case 30:
      return NetworkManagerDeviceStateReason.gsmRegistrationNotSearching;
    case 31:
      return NetworkManagerDeviceStateReason.gsmRegistrationDenied;
    case 32:
      return NetworkManagerDeviceStateReason.gsmRegistrationTimeout;
    case 33:
      return NetworkManagerDeviceStateReason.gsmRegistrationFailed;
    case 34:
      return NetworkManagerDeviceStateReason.gsmPinCheckFailed;
    case 35:
      return NetworkManagerDeviceStateReason.firmwareMissing;
    case 36:
      return NetworkManagerDeviceStateReason.removed;
    case 37:
      return NetworkManagerDeviceStateReason.sleeping;
    case 38:
      return NetworkManagerDeviceStateReason.connectionRemoved;
    case 39:
      return NetworkManagerDeviceStateReason.userRequested;
    case 40:
      return NetworkManagerDeviceStateReason.carrier;
    case 41:
      return NetworkManagerDeviceStateReason.connectionAssumed;
    case 42:
      return NetworkManagerDeviceStateReason.supplicantAvailable;
    case 43:
      return NetworkManagerDeviceStateReason.modemNotFound;
    case 44:
      return NetworkManagerDeviceStateReason.btFailed;
    case 45:
      return NetworkManagerDeviceStateReason.gsmSimNotInserted;
    case 46:
      return NetworkManagerDeviceStateReason.gsmSimPinRequired;
    case 47:
      return NetworkManagerDeviceStateReason.gsmSimPukRequired;
    case 48:
      return NetworkManagerDeviceStateReason.gsmSimWrong;
    case 49:
      return NetworkManagerDeviceStateReason.infinibandMode;
    case 50:
      return NetworkManagerDeviceStateReason.dependencyFailed;
    case 51:
      return NetworkManagerDeviceStateReason.br2684Failed;
    case 52:
      return NetworkManagerDeviceStateReason.modemManagerUnavailable;
    case 53:
      return NetworkManagerDeviceStateReason.ssidNotFound;
    case 54:
      return NetworkManagerDeviceStateReason.secondaryConnectionFailed;
    case 55:
      return NetworkManagerDeviceStateReason.dcbFcoeFailed;
    case 56:
      return NetworkManagerDeviceStateReason.teamdControlFailed;
    case 57:
      return NetworkManagerDeviceStateReason.modemFailed;
    case 58:
      return NetworkManagerDeviceStateReason.modemAvailable;
    case 59:
      return NetworkManagerDeviceStateReason.simPinIncorrect;
    case 60:
      return NetworkManagerDeviceStateReason.newActivation;
    case 61:
      return NetworkManagerDeviceStateReason.parentChanged;
    case 62:
      return NetworkManagerDeviceStateReason.parentManagedChanged;
    case 63:
      return NetworkManagerDeviceStateReason.ovsdbFailed;
    case 64:
      return NetworkManagerDeviceStateReason.ipAddressDuplicate;
    case 65:
      return NetworkManagerDeviceStateReason.ipMethodUnsupported;
    case 66:
      return NetworkManagerDeviceStateReason.sriovConfigurationFailed;
    case 67:
      return NetworkManagerDeviceStateReason.peerNotFound;
    default:
      return NetworkManagerDeviceStateReason.unknown;
  }
}

class NetworkManagerDeviceStateAndReason {
  final NetworkManagerDeviceState state;
  final NetworkManagerDeviceStateReason reason;

  NetworkManagerDeviceStateAndReason(this.state, this.reason);
}

/// Device types.
enum NetworkManagerDeviceType {
  unknown,
  ethernet,
  wifi,
  bluetooth,
  olpcMesh,
  wimax,
  modem,
  infiniband,
  bond,
  vlan,
  adsl,
  bridge,
  generic,
  team,
  tun,
  ipTunnel,
  macVlan,
  vxlan,
  veth,
  macsec,
  dummy,
  ppp,
  ovsInterface,
  ovsPort,
  ovsBridge,
  wpan,
  sixLoWpan,
  wireguard,
  wifiP2p,
  vrf
}

/// Traffic limitations.
enum NetworkManagerMetered { unknown, yes, no, guessYes, guessNo }

NetworkManagerMetered _decodeMetered(int value) =>
    value < NetworkManagerMetered.values.length
        ? NetworkManagerMetered.values[value]
        : NetworkManagerMetered.unknown;

/// State of a [NetworkManagerActiveConnection].
enum NetworkManagerActiveConnectionState {
  unknown,
  activating,
  activated,
  deactivating,
  deactivated
}

NetworkManagerActiveConnectionState _decodeActiveConnectionState(int value) {
  switch (value) {
    case 1:
      return NetworkManagerActiveConnectionState.activating;
    case 2:
      return NetworkManagerActiveConnectionState.activated;
    case 3:
      return NetworkManagerActiveConnectionState.deactivating;
    case 4:
      return NetworkManagerActiveConnectionState.deactivated;
    default:
      return NetworkManagerActiveConnectionState.unknown;
  }
}

/// Flags describing a [NetworkManagerActiveConnectionState].
enum NetworkManagerActivationStateFlag {
  isMaster,
  isSlave,
  layer2Ready,
  ip4Ready,
  ip6Ready,
  masterHasSlaves,
  lifetimeBoundToProfileVisibility,
  external
}

/// Flags for a [NetworkManagerSettingsConnection].
enum NetworkManagerConnectionFlag {
  unsaved,
  networkManagerGenerated,
  volatile,
  external
}

/// Capabilities of a [NetworkManagerDevice].
enum NetworkManagerDeviceCapability {
  networkManagerSupported,
  carrierDetect,
  isSoftware,
  singleRootIOVirtualization
}

/// Interface flags for a [NetworkManagerDevice].
enum NetworkManagerDeviceInterfaceFlag { up, lowerUp, carrier }

/// WiFi operating modes.
enum NetworkManagerWifiMode { unknown, adhoc, infra, ap, mesh }

NetworkManagerWifiMode _decodeWifiMode(int value) {
  if (value == 1) {
    return NetworkManagerWifiMode.adhoc;
  } else if (value == 2) {
    return NetworkManagerWifiMode.infra;
  } else if (value == 3) {
    return NetworkManagerWifiMode.ap;
  } else if (value == 4) {
    return NetworkManagerWifiMode.mesh;
  } else {
    return NetworkManagerWifiMode.unknown;
  }
}

/// Wifi capabilities.
enum NetworkManagerDeviceWifiCapability {
  cipherWep40,
  cipherWep104,
  cipherTkip,
  cipherCcmp,
  wpa,
  rsn,
  ap,
  adhoc,
  freqValid,
  freq2GHz,
  freq5GHz,
  mesh,
  ibssRsn
}

/// Flags for a [NetworkManagerAccessPoint].
enum NetworkManagerWifiAccessPointFlag { privacy, wps, wpsPushButton, wpsPin }

/// Security flags for a [NetworkManagerAccessPoint].
enum NetworkManagerWifiAccessPointSecurityFlag {
  pairWep40,
  pairWep104,
  pairTkip,
  pairCcmp,
  groupWep40,
  groupWep104,
  groupTkip,
  groupCcmp,
  keyManagementPsk,
  keyManagement802_1X,
  keyManagementSae,
  keyManagementOwe,
  keyManagementOweTm
}

List<NetworkManagerWifiAccessPointSecurityFlag>
    _decodeWifiAccessPointSecurityFlags(int value) {
  var flags = <NetworkManagerWifiAccessPointSecurityFlag>[];
  if ((value & 0x1) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.pairWep40);
  }
  if ((value & 0x2) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.pairWep104);
  }
  if ((value & 0x4) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.pairTkip);
  }
  if ((value & 0x8) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.pairCcmp);
  }
  if ((value & 0x10) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.groupWep40);
  }
  if ((value & 0x20) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.groupWep104);
  }
  if ((value & 0x40) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.groupTkip);
  }
  if ((value & 0x80) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.groupCcmp);
  }
  if ((value & 0x100) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.keyManagementPsk);
  }
  if ((value & 0x200) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.keyManagement802_1X);
  }
  if ((value & 0x400) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.keyManagementSae);
  }
  if ((value & 0x800) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.keyManagementOwe);
  }
  if ((value & 0x1000) != 0) {
    flags.add(NetworkManagerWifiAccessPointSecurityFlag.keyManagementOweTm);
  }
  return flags;
}

/// Tunnel modes.
enum NetworkManagerTunnelMode { tun, tap }

/// Capabilities of a [NetworkManagerDeviceBluetooth].
enum NetworkManagerBluetoothCapability { dun, tun }

/// Settings profile manager.
class NetworkManagerSettings {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  NetworkManagerSettings(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_settingsInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Saved connections.
  List<NetworkManagerSettingsConnection> get connections {
    var objectPaths = _object.getObjectPathArrayProperty(
            _settingsInterfaceName, 'Connections') ??
        [];
    var connections = <NetworkManagerSettingsConnection>[];
    for (var objectPath in objectPaths) {
      var connection = _client._getConnection(objectPath);
      if (connection != null) {
        connections.add(connection);
      }
    }
    return connections;
  }

  /// The machine hostname.
  String get hostname =>
      _object.getStringProperty(_settingsInterfaceName, 'Hostname') ?? '';

  /// True if connections can be added or modified.
  bool get canModify =>
      _object.getBooleanProperty(_settingsInterfaceName, 'CanModify') ?? false;

  /// Add new connection and save it to disk.
  Future<NetworkManagerSettingsConnection> addConnection(
      Map<String, Map<String, DBusValue>> connection) async {
    var result = await _object.callMethod(
        _settingsInterfaceName,
        'AddConnection',
        [
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              connection.map((key, value) =>
                  MapEntry(DBusString(key), DBusDict.stringVariant(value))))
        ],
        replySignature: DBusSignature('o'));
    return _client._getConnection(result.returnValues[0] as DBusObjectPath)!;
  }

  /// Add new connection but do not save it to disk immediately.
  Future<NetworkManagerSettingsConnection> addConnectionUnsaved(
      Map<String, Map<String, DBusValue>> connection) async {
    var result = await _object.callMethod(
        _settingsInterfaceName,
        'AddConnectionUnsaved',
        [
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              connection.map((key, value) =>
                  MapEntry(DBusString(key), DBusDict.stringVariant(value))))
        ],
        replySignature: DBusSignature('o'));
    return _client._getConnection(result.returnValues[0] as DBusObjectPath)!;
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerSettings && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Settings for a connection.
class NetworkManagerSettingsConnection {
  final _NetworkManagerObject _object;

  NetworkManagerSettingsConnection(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_settingsConnectionInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Updates the settings for this connection, writing them to persistent storage.
  Future<void> update(Map<String, Map<String, DBusValue>> properties) async {
    await _object.callMethod(
        _settingsConnectionInterfaceName,
        'Update',
        [
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              properties.map((key, value) =>
                  MapEntry(DBusString(key), DBusDict.stringVariant(value))))
        ],
        replySignature: DBusSignature(''));
  }

  /// Updates the settings for this connection, not writing them to persistent storage.
  Future<void> updateUnsaved(
      Map<String, Map<String, DBusValue>> properties) async {
    await _object.callMethod(
        _settingsConnectionInterfaceName,
        'UpdateUnsaved',
        [
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              properties.map((key, value) =>
                  MapEntry(DBusString(key), DBusDict.stringVariant(value))))
        ],
        replySignature: DBusSignature(''));
  }

  /// Deletes this network connection settings.
  Future<void> delete() async {
    await _object.callMethod(_settingsConnectionInterfaceName, 'Delete', [],
        replySignature: DBusSignature(''));
  }

  /// Gets the settings belonging to this network connection.
  Future<Map<String, Map<String, DBusValue>>> getSettings() async {
    var result = await _object.callMethod(
        _settingsConnectionInterfaceName, 'GetSettings', [],
        replySignature: DBusSignature('a{sa{sv}}'));
    return (result.returnValues[0] as DBusDict).children.map(
          (key, value) => MapEntry(
            (key as DBusString).value,
            (value as DBusDict).children.map((k, v) =>
                MapEntry((k as DBusString).value, (v as DBusVariant).value)),
          ),
        );
  }

  /// Gets the secrets belonging to this network connection.
  Future<Map<String, Map<String, DBusValue>>> getSecrets(
      [String settingName = '']) async {
    var result = await _object.callMethod(_settingsConnectionInterfaceName,
        'GetSecrets', [DBusString(settingName)],
        replySignature: DBusSignature('a{sa{sv}}'));
    return (result.returnValues[0] as DBusDict).children.map((key, value) =>
        MapEntry(
            (key as DBusString).value,
            (value as DBusDict).children.map((k, v) =>
                MapEntry((k as DBusString).value, (v as DBusVariant).value))));
  }

  /// Clears the secrets belonging to this network connection.
  Future<void> clearSecrets() async {
    await _object.callMethod(
        _settingsConnectionInterfaceName, 'ClearSecrets', [],
        replySignature: DBusSignature(''));
  }

  /// Saves the connection settings to persistent storage.
  Future<void> save() async {
    await _object.callMethod(_settingsConnectionInterfaceName, 'Save', [],
        replySignature: DBusSignature(''));
  }

  // FIXME: Update2

  /// True if the settings have yet to be written to persistent storage.
  bool get unsaved =>
      _object.getBooleanProperty(_settingsConnectionInterfaceName, 'Unsaved') ??
      false;

  /// Flags associated with this connection.
  List<NetworkManagerConnectionFlag> get flags {
    var value =
        _object.getUint32Property(_settingsConnectionInterfaceName, 'Flags') ??
            0;
    var flags = <NetworkManagerConnectionFlag>[];
    if ((value & 0x01) != 0) {
      flags.add(NetworkManagerConnectionFlag.unsaved);
    }
    if ((value & 0x02) != 0) {
      flags.add(NetworkManagerConnectionFlag.networkManagerGenerated);
    }
    if ((value & 0x04) != 0) {
      flags.add(NetworkManagerConnectionFlag.volatile);
    }
    if ((value & 0x08) != 0) {
      flags.add(NetworkManagerConnectionFlag.external);
    }
    return flags;
  }

  /// File that stores these settings.
  String get filename =>
      _object.getStringProperty(_settingsConnectionInterfaceName, 'Filename') ??
      '';

  @override
  bool operator ==(other) =>
      other is NetworkManagerSettingsConnection && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// DNS configuration and state.
class NetworkManagerDnsManager {
  final _NetworkManagerObject _object;

  NetworkManagerDnsManager(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_dnsManagerInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Current DNS processing mode.
  String get mode =>
      _object.getStringProperty(_dnsManagerInterfaceName, 'Mode') ?? '';

  /// Current resolv.conf management mode.
  String get rcManager =>
      _object.getStringProperty(_dnsManagerInterfaceName, 'RcManager') ?? '';

  /// Current DNS configuration. Each item has at least 'nameservers', 'priority' and optionally 'interface' and 'vpn'.
  List<Map<String, dynamic>> get configuration =>
      _object.getDataListProperty(_dnsManagerInterfaceName, 'Configuration') ??
      [];

  @override
  bool operator ==(other) =>
      other is NetworkManagerDnsManager && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// A device managed by NetworkManager.
class NetworkManagerDevice {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  /// Information for Bluetooth devices or null.
  NetworkManagerDeviceBluetooth? get bluetooth =>
      _object.interfaces.containsKey(_bluetoothDeviceInterfaceName)
          ? NetworkManagerDeviceBluetooth(_object)
          : null;

  /// Information for bridge devices or null.
  NetworkManagerDeviceBridge? get bridge =>
      _object.interfaces.containsKey(_bridgeDeviceInterfaceName)
          ? NetworkManagerDeviceBridge(_client, _object)
          : null;

  /// Generic device information or null.
  NetworkManagerDeviceGeneric? get generic =>
      _object.interfaces.containsKey(_genericDeviceInterfaceName)
          ? NetworkManagerDeviceGeneric(_object)
          : null;

  /// Device statistics or null.
  NetworkManagerDeviceStatistics? get statistics =>
      _object.interfaces.containsKey(_statisticsDeviceInterfaceName)
          ? NetworkManagerDeviceStatistics(_object)
          : null;

  /// TUN device information or null.
  NetworkManagerDeviceTun? get tun =>
      _object.interfaces.containsKey(_tunDeviceInterfaceName)
          ? NetworkManagerDeviceTun(_object)
          : null;

  /// Information for Virtual LAN devices or null.
  NetworkManagerDeviceVlan? get vlan =>
      _object.interfaces.containsKey(_vlanDeviceInterfaceName)
          ? NetworkManagerDeviceVlan(_client, _object)
          : null;

  /// Information for wired devices (e.g. Ethernet) or null.
  NetworkManagerDeviceWired? get wired =>
      _object.interfaces.containsKey(_wiredDeviceInterfaceName)
          ? NetworkManagerDeviceWired(_object)
          : null;

  /// Information for wireless devices (e.g WiFi) or null.
  NetworkManagerDeviceWireless? get wireless =>
      _object.interfaces.containsKey(_wirelessDeviceInterfaceName)
          ? NetworkManagerDeviceWireless(_client, _object)
          : null;

  NetworkManagerDevice(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_deviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Disconnects a device and prevents the device from automatically activating further connections without user intervention.
  Future<void> disconnect() async {
    await _object.callMethod(_deviceInterfaceName, 'Disconnect', [],
        replySignature: DBusSignature(''));
  }

  /// Deletes a software device from NetworkManager and removes the interface from the system.
  /// The method returns an error when called for a hardware device.
  Future<void> delete() async {
    await _object.callMethod(_deviceInterfaceName, 'Delete', [],
        replySignature: DBusSignature(''));
  }

  /// UDI for this device.
  String get udi =>
      _object.getStringProperty(_deviceInterfaceName, 'Udi') ?? '';

  /// Device filesystem path.
  String get path =>
      _object.getStringProperty(_deviceInterfaceName, 'Path') ?? '';

  /// Name of the device's control (and often data) interface.
  String get interface =>
      _object.getStringProperty(_deviceInterfaceName, 'Interface') ?? '';

  /// The name of the device's data interface when available.
  String get ipInterface =>
      _object.getStringProperty(_deviceInterfaceName, 'IpInterface') ?? '';

  /// The kernel driver this device is using.
  String get driver =>
      _object.getStringProperty(_deviceInterfaceName, 'Driver') ?? '';

  /// The version of the kernel driver this device is using.
  String get driverVersion =>
      _object.getStringProperty(_deviceInterfaceName, 'DriverVersion') ?? '';

  /// The version of the firmware this device is using.
  String get firmwareVersion =>
      _object.getStringProperty(_deviceInterfaceName, 'FirmwareVersion') ?? '';

  /// Capabilities of this device
  List<NetworkManagerDeviceCapability> get capabilities {
    var value =
        _object.getUint32Property(_deviceInterfaceName, 'Capabilities') ?? 0;
    var values = <NetworkManagerDeviceCapability>[];
    if ((value & 0x01) != 0) {
      values.add(NetworkManagerDeviceCapability.networkManagerSupported);
    }
    if ((value & 0x02) != 0) {
      values.add(NetworkManagerDeviceCapability.carrierDetect);
    }
    if ((value & 0x03) != 0) {
      values.add(NetworkManagerDeviceCapability.isSoftware);
    }
    if ((value & 0x04) != 0) {
      values.add(NetworkManagerDeviceCapability.singleRootIOVirtualization);
    }
    return values;
  }

  /// The connection state of this device.
  NetworkManagerDeviceState get state {
    var value = _object.getUint32Property(_deviceInterfaceName, 'State') ?? 0;
    return _decodeDeviceState(value);
  }

  /// The state of this connection and the reason for that state.
  NetworkManagerDeviceStateAndReason get stateReason {
    var value = _object.getCachedProperty(_deviceInterfaceName, 'StateReason');
    if (value == null || value.signature != DBusSignature('(uu)')) {
      return NetworkManagerDeviceStateAndReason(
          NetworkManagerDeviceState.unknown,
          NetworkManagerDeviceStateReason.unknown);
    }
    var values = (value as DBusStruct).children.toList();
    var state = _decodeDeviceState((values[0] as DBusUint32).value);
    var reason = _decodeDeviceStateReason((values[1] as DBusUint32).value);

    return NetworkManagerDeviceStateAndReason(state, reason);
  }

  /// Connection that owns this device.
  NetworkManagerActiveConnection? get activeConnection {
    var objectPath =
        _object.getObjectPathProperty(_deviceInterfaceName, 'ActiveConnection');
    return _client._getActiveConnection(objectPath);
  }

  /// IPv4 configuration for this device.
  NetworkManagerIP4Config? get ip4Config {
    var objectPath =
        _object.getObjectPathProperty(_deviceInterfaceName, 'Ip4Config');
    return _client._getIP4Config(objectPath);
  }

  /// DHCPv4 configuration for this device.
  NetworkManagerDHCP4Config? get dhcp4Config {
    var objectPath =
        _object.getObjectPathProperty(_deviceInterfaceName, 'Dhcp4Config');
    return _client._getDHCP4Config(objectPath);
  }

  /// IPv6 configuration for this device.
  NetworkManagerIP6Config? get ip6Config {
    var objectPath =
        _object.getObjectPathProperty(_deviceInterfaceName, 'Ip6Config');
    return _client._getIP6Config(objectPath);
  }

  /// DHCPv6 configuration for this device.
  NetworkManagerDHCP6Config? get dhcp6Config {
    var objectPath =
        _object.getObjectPathProperty(_deviceInterfaceName, 'Dhcp6Config');
    return _client._getDHCP6Config(objectPath);
  }

  /// True if this device is being managed by NetworkManager.
  bool get managed =>
      _object.getBooleanProperty(_deviceInterfaceName, 'Managed') ?? false;

  /// Sets if this device is being managed by NetworkManager.
  Future<void> setManaged(bool value) async {
    await _object.setProperty(
        _deviceInterfaceName, 'Managed', DBusBoolean(value));
  }

  /// True if this device is allowed to automatically connect.
  bool get autoconnect =>
      _object.getBooleanProperty(_deviceInterfaceName, 'Autoconnect') ?? false;

  /// Sets if this device is allowed to automatically connect.
  Future<void> setAutoconnect(bool value) async {
    await _object.setProperty(
        _deviceInterfaceName, 'Autoconnect', DBusBoolean(value));
  }

  /// True if this device is missing firware required for it to operate.
  bool get firmwareMissing =>
      _object.getBooleanProperty(_deviceInterfaceName, 'FirmwareMissing') ??
      false;

  /// True if this device is missing a plugin or needs plugin configuration for it to operate.
  bool get nmPluginMissing =>
      _object.getBooleanProperty(_deviceInterfaceName, 'NmPluginMissing') ??
      false;

  /// The type of device.
  NetworkManagerDeviceType get deviceType {
    var value = _object.getUint32Property(
          _deviceInterfaceName,
          'DeviceType',
        ) ??
        0;
    switch (value) {
      case 1:
        return NetworkManagerDeviceType.ethernet;
      case 2:
        return NetworkManagerDeviceType.wifi;
      case 5:
        return NetworkManagerDeviceType.bluetooth;
      case 6:
        return NetworkManagerDeviceType.olpcMesh;
      case 7:
        return NetworkManagerDeviceType.wimax;
      case 8:
        return NetworkManagerDeviceType.modem;
      case 9:
        return NetworkManagerDeviceType.infiniband;
      case 10:
        return NetworkManagerDeviceType.bond;
      case 11:
        return NetworkManagerDeviceType.vlan;
      case 12:
        return NetworkManagerDeviceType.adsl;
      case 13:
        return NetworkManagerDeviceType.bridge;
      case 14:
        return NetworkManagerDeviceType.generic;
      case 15:
        return NetworkManagerDeviceType.team;
      case 16:
        return NetworkManagerDeviceType.tun;
      case 17:
        return NetworkManagerDeviceType.ipTunnel;
      case 18:
        return NetworkManagerDeviceType.macVlan;
      case 19:
        return NetworkManagerDeviceType.vxlan;
      case 20:
        return NetworkManagerDeviceType.veth;
      case 21:
        return NetworkManagerDeviceType.macsec;
      case 22:
        return NetworkManagerDeviceType.dummy;
      case 23:
        return NetworkManagerDeviceType.ppp;
      case 24:
        return NetworkManagerDeviceType.ovsInterface;
      case 25:
        return NetworkManagerDeviceType.ovsPort;
      case 26:
        return NetworkManagerDeviceType.ovsBridge;
      case 27:
        return NetworkManagerDeviceType.wpan;
      case 28:
        return NetworkManagerDeviceType.sixLoWpan;
      case 29:
        return NetworkManagerDeviceType.wireguard;
      case 30:
        return NetworkManagerDeviceType.wifiP2p;
      case 31:
        return NetworkManagerDeviceType.vrf;
      default:
        return NetworkManagerDeviceType.unknown;
    }
  }

  // The connections that are configured for this device.
  List<NetworkManagerSettingsConnection> get availableConnections {
    var objectPaths = _object.getObjectPathArrayProperty(
            _deviceInterfaceName, 'AvailableConnections') ??
        [];
    var connections = <NetworkManagerSettingsConnection>[];
    for (var objectPath in objectPaths) {
      var connection = _client._getConnection(objectPath);
      if (connection != null) {
        connections.add(connection);
      }
    }
    return connections;
  }

  /// The pyhsical network port associated with this device.
  String get physicalPortId =>
      _object.getStringProperty(_deviceInterfaceName, 'PhysicalPortId') ?? '';

  /// The device MTU.
  int get mtu => _object.getUint32Property(_deviceInterfaceName, 'Mtu') ?? 0;

  /// True if the device has traffic limitations.
  NetworkManagerMetered get metered => _decodeMetered(
      _object.getUint32Property(_deviceInterfaceName, 'Metered') ?? 0);

  // FIXME: LldpNeighbors

  /// True if the device exists.
  bool get real =>
      _object.getBooleanProperty(_deviceInterfaceName, 'Real') ?? false;

  /// IPv4 connectivity state.
  NetworkManagerConnectivityState get ip4Connectivity {
    var value =
        _object.getUint32Property(_deviceInterfaceName, 'Ip4Connectivity') ?? 0;
    return _decodeConnectivityState(value);
  }

  /// IPv6 connectivity state.
  NetworkManagerConnectivityState get ip6Connectivity {
    var value =
        _object.getUint32Property(_deviceInterfaceName, 'Ip6Connectivity') ?? 0;
    return _decodeConnectivityState(value);
  }

  /// Flags for network interfaces.
  List<NetworkManagerDeviceInterfaceFlag> get interfaceFlags {
    var value =
        _object.getUint32Property(_deviceInterfaceName, 'InterfaceFlags') ?? 0;
    var flags = <NetworkManagerDeviceInterfaceFlag>[];
    if ((value & 0x01) != 0) {
      flags.add(NetworkManagerDeviceInterfaceFlag.up);
    }
    if ((value & 0x02) != 0) {
      flags.add(NetworkManagerDeviceInterfaceFlag.lowerUp);
    }
    if ((value & 0x10000) != 0) {
      flags.add(NetworkManagerDeviceInterfaceFlag.carrier);
    }
    return flags;
  }

  /// Hardware address for this device.
  String get hwAddress =>
      _object.getStringProperty(_deviceInterfaceName, 'HwAddress') ?? '';

  @override
  bool operator ==(other) =>
      other is NetworkManagerDevice && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for Bluetooth devices.
class NetworkManagerDeviceBluetooth {
  final _NetworkManagerObject _object;

  NetworkManagerDeviceBluetooth(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_bluetoothDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Bluetooth capabilities of this device.
  List<NetworkManagerBluetoothCapability> get btCapabilities {
    var value = _object.getUint32Property(
            _bluetoothDeviceInterfaceName, 'BtCapabilities') ??
        0;
    var flags = <NetworkManagerBluetoothCapability>[];
    if ((value & 0x1) != 0) {
      flags.add(NetworkManagerBluetoothCapability.dun);
    }
    if ((value & 0x2) != 0) {
      flags.add(NetworkManagerBluetoothCapability.tun);
    }
    return flags;
  }

  /// Bluetooth name of the device.
  String get name =>
      _object.getStringProperty(_bluetoothDeviceInterfaceName, 'Name') ?? '';

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceBluetooth && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for bridge network devices.
class NetworkManagerDeviceBridge {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  NetworkManagerDeviceBridge(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_bridgeDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Devices which are currently enslaved to this device.
  List<NetworkManagerDevice> get slaves {
    var objectPaths = _object.getObjectPathArrayProperty(
            _bridgeDeviceInterfaceName, 'Slaves') ??
        [];
    var devices = <NetworkManagerDevice>[];
    for (var objectPath in objectPaths) {
      var device = _client._getDevice(objectPath);
      if (device != null) {
        devices.add(device);
      }
    }
    return devices;
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceBridge && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for generic devices.
class NetworkManagerDeviceGeneric {
  final _NetworkManagerObject _object;

  NetworkManagerDeviceGeneric(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_genericDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// A human readable description of this device.
  String get typeDescription =>
      _object.getStringProperty(
          _genericDeviceInterfaceName, 'TypeDescription') ??
      '';

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceGeneric && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Statistics for devices.
class NetworkManagerDeviceStatistics {
  final _NetworkManagerObject _object;

  NetworkManagerDeviceStatistics(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_statisticsDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Maximum time between properties being updated in milliseconds or 0 if guaranteed refresh rate.
  int get refreshRateMs =>
      _object.getUint32Property(
          _statisticsDeviceInterfaceName, 'RefreshRateMs') ??
      0;

  /// Sets the vlaue of [refreshRateMs].
  Future<void> setRefreshRateMs(int value) async {
    await _object.setProperty(
        _statisticsDeviceInterfaceName, 'RefreshRateMs', DBusUint32(value));
  }

  /// How many bytes have been transmitted.
  int get txBytes =>
      _object.getUint64Property(_statisticsDeviceInterfaceName, 'TxBytes') ?? 0;

  /// How many bytes have been received.
  int get rxBytes =>
      _object.getUint64Property(_statisticsDeviceInterfaceName, 'RxBytes') ?? 0;

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceStatistics && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for userspace tunneling devices.
class NetworkManagerDeviceTun {
  final _NetworkManagerObject _object;

  NetworkManagerDeviceTun(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_tunDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Permanent hardware address, e.g. '00:0a:95:9d:68:16'.
  String get permHwAddress =>
      _object.getStringProperty(_tunDeviceInterfaceName, 'PermHwAddress') ?? '';

  /// UID of tunnel owner or -1 if no owner.
  int get owner =>
      _object.getInt64Property(_tunDeviceInterfaceName, 'Owner') ?? 0;

  /// GID of tunnel group or -1 if no owner.
  int get group =>
      _object.getInt64Property(_tunDeviceInterfaceName, 'Group') ?? 0;

  /// Tunnel mode.
  NetworkManagerTunnelMode get mode => {
        'tun': NetworkManagerTunnelMode.tun,
        'tap': NetworkManagerTunnelMode.tap
      }[_object.getStringProperty(_tunDeviceInterfaceName, 'Mode')]!;

  /// True if no protocol info is prepended to the tunnel packets.
  bool get noPi =>
      _object.getBooleanProperty(_tunDeviceInterfaceName, 'NoPi') ?? false;

  /// True if the tunnel packets include a virtio network header.
  bool get vnetHdr =>
      _object.getBooleanProperty(_tunDeviceInterfaceName, 'VnetHdr') ?? false;

  /// True if callers can connect to the tap device multiple times, for multiple send/receive queues.
  bool get multiQueue =>
      _object.getBooleanProperty(_tunDeviceInterfaceName, 'MultiQueue') ??
      false;

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceTun && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for Virtual LAN devices.
class NetworkManagerDeviceVlan {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  NetworkManagerDeviceVlan(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_vlanDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Parent device of this VLAN device.
  NetworkManagerDevice get parent {
    var objectPath =
        _object.getObjectPathProperty(_vlanDeviceInterfaceName, 'Parent');
    return _client._getDevice(objectPath)!;
  }

  /// The VLAN ID in use.
  int get vlanId =>
      _object.getUint32Property(_vlanDeviceInterfaceName, 'VlanId') ?? 0;

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceVlan && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for wired network devices.
class NetworkManagerDeviceWired {
  final _NetworkManagerObject _object;

  NetworkManagerDeviceWired(this._object);

  /// Permanent hardware address, e.g. '00:0a:95:9d:68:16'.
  String get permHwAddress =>
      _object.getStringProperty(_wiredDeviceInterfaceName, 'PermHwAddress') ??
      '';

  /// Design speed of this device in megabits/second.
  int get speed =>
      _object.getUint32Property(_wiredDeviceInterfaceName, 'Speed') ?? 0;

  /// Array of S/390 subchannels for S/390 or z/Architecture devices.
  List<String> get s390Subchannels =>
      _object.getStringArrayProperty(
          _wiredDeviceInterfaceName, 'S390Subchannels') ??
      [];

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceWired && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Information for wireless network devices.
class NetworkManagerDeviceWireless {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  NetworkManagerDeviceWireless(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_wirelessDeviceInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Permanent hardware address, e.g. '00:0a:95:9d:68:16'.
  String get permHwAddress =>
      _object.getStringProperty(
          _wirelessDeviceInterfaceName, 'PermHwAddress') ??
      '';

  /// Operating mode of the device.
  NetworkManagerWifiMode get mode {
    var value =
        _object.getUint32Property(_wirelessDeviceInterfaceName, 'Mode') ?? 0;
    return _decodeWifiMode(value);
  }

  // Bitrate currently in use, in kilobits/second.
  int get bitrate =>
      _object.getUint32Property(_wirelessDeviceInterfaceName, 'Bitrate') ?? 0;

  /// Access points available on this device.
  List<NetworkManagerAccessPoint> get accessPoints {
    var objectPaths = _object.getObjectPathArrayProperty(
            _wirelessDeviceInterfaceName, 'AccessPoints') ??
        [];
    var accessPoints = <NetworkManagerAccessPoint>[];
    for (var objectPath in objectPaths) {
      var accessPoint = _client._getAccessPoint(objectPath);
      if (accessPoint != null) {
        accessPoints.add(accessPoint);
      }
    }

    return accessPoints;
  }

  /// Access point currently in use.
  NetworkManagerAccessPoint? get activeAccessPoint {
    var objectPath = _object.getObjectPathProperty(
        _wirelessDeviceInterfaceName, 'ActiveAccessPoint');
    return _client._getAccessPoint(objectPath);
  }

  /// Device capabilities.
  List<NetworkManagerDeviceWifiCapability> get wirelessCapabilities {
    var value = _object.getUint32Property(
            _wirelessDeviceInterfaceName, 'WirelessCapabilities') ??
        0;
    var flags = <NetworkManagerDeviceWifiCapability>[];
    if ((value & 0x1) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.cipherWep40);
    }
    if ((value & 0x2) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.cipherWep104);
    }
    if ((value & 0x4) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.cipherTkip);
    }
    if ((value & 0x8) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.cipherCcmp);
    }
    if ((value & 0x10) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.wpa);
    }
    if ((value & 0x20) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.rsn);
    }
    if ((value & 0x40) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.ap);
    }
    if ((value & 0x80) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.adhoc);
    }
    if ((value & 0x100) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.freqValid);
    }
    if ((value & 0x200) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.freq2GHz);
    }
    if ((value & 0x400) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.freq5GHz);
    }
    if ((value & 0x1000) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.mesh);
    }
    if ((value & 0x2000) != 0) {
      flags.add(NetworkManagerDeviceWifiCapability.ibssRsn);
    }
    return flags;
  }

  /// Last time this device completed a network scan in milliseconds since boot. -1 if has never scanned for access points.
  int get lastScan =>
      _object.getInt64Property(_wirelessDeviceInterfaceName, 'LastScan') ?? -1;

  /// Request this device to scan for access points.
  Future requestScan({List<List<int>>? ssids}) async {
    var options = <String, DBusValue>{};
    if (ssids != null) {
      options['ssids'] = DBusArray(
          DBusSignature('ay'), ssids.map((ssid) => DBusArray.byte(ssid)));
    }
    await _object.callMethod(_wirelessDeviceInterfaceName, 'RequestScan',
        [DBusDict.stringVariant(options)],
        replySignature: DBusSignature(''));
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerDeviceWireless && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// Active connection.
class NetworkManagerActiveConnection {
  final NetworkManagerClient _client;
  final _NetworkManagerObject _object;

  NetworkManagerActiveConnection(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_activeConnectionInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// The connection settings.
  NetworkManagerSettingsConnection? get connection {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Connection',
    );
    return _client._getConnection(objectPath);
  }

  /// ID for this connection, e.g. 'Ethernet', 'my-cool-wifi'.
  String get id =>
      _object.getStringProperty(_activeConnectionInterfaceName, 'Id') ?? '';

  /// Unique ID for this connection, e.g. '123e4567-e89b-12d3-a456-426614174000'.
  String get uuid =>
      _object.getStringProperty(_activeConnectionInterfaceName, 'Uuid') ?? '';

  /// Type of this connection, e.g. '802-11-wireless', '802-3-ethernet'.
  String get type =>
      _object.getStringProperty(_activeConnectionInterfaceName, 'Type') ?? '';

  /// The state of this connection.
  NetworkManagerActiveConnectionState get state {
    var value =
        _object.getUint32Property(_activeConnectionInterfaceName, 'State') ?? 0;
    return _decodeActiveConnectionState(value);
  }

  /// Flags related to [state].
  List<NetworkManagerActivationStateFlag> get stateFlags {
    var value = _object.getUint32Property(
            _activeConnectionInterfaceName, 'StateFlags') ??
        0;
    var flags = <NetworkManagerActivationStateFlag>[];
    if ((value & 0x01) != 0) {
      flags.add(NetworkManagerActivationStateFlag.isMaster);
    }
    if ((value & 0x02) != 0) {
      flags.add(NetworkManagerActivationStateFlag.isSlave);
    }
    if ((value & 0x04) != 0) {
      flags.add(NetworkManagerActivationStateFlag.layer2Ready);
    }
    if ((value & 0x08) != 0) {
      flags.add(NetworkManagerActivationStateFlag.ip4Ready);
    }
    if ((value & 0x10) != 0) {
      flags.add(NetworkManagerActivationStateFlag.ip6Ready);
    }
    if ((value & 0x20) != 0) {
      flags.add(NetworkManagerActivationStateFlag.masterHasSlaves);
    }
    if ((value & 0x40) != 0) {
      flags.add(
          NetworkManagerActivationStateFlag.lifetimeBoundToProfileVisibility);
    }
    if ((value & 0x80) != 0) {
      flags.add(NetworkManagerActivationStateFlag.external);
    }
    return flags;
  }

  /// True if this is the default IPv4 connection.
  bool get default4 =>
      _object.getBooleanProperty(_activeConnectionInterfaceName, 'Default') ??
      false;

  /// IPv4 configuration for this connection.
  NetworkManagerIP4Config? get ip4Config {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Ip4Config',
    );
    return _client._getIP4Config(objectPath);
  }

  /// DHCPv4 configuration for this connection.
  NetworkManagerDHCP4Config? get dhcp4Config {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Dhcp4Config',
    );
    return _client._getDHCP4Config(objectPath);
  }

  /// True if this is the default IPv6 connection.
  bool get default6 =>
      _object.getBooleanProperty(_activeConnectionInterfaceName, 'Default6') ??
      false;

  /// IPv6 configuration for this connection.
  NetworkManagerIP6Config? get ip6Config {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Ip6Config',
    );
    return _client._getIP6Config(objectPath);
  }

  /// DHCPv6 configuration for this connection.
  NetworkManagerDHCP6Config? get dhcp6Config {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Dhcp6Config',
    );
    return _client._getDHCP6Config(objectPath);
  }

  /// True if this is a VPN connection.
  bool get vpn =>
      _object.getBooleanProperty(
        _activeConnectionInterfaceName,
        'Vpn',
      ) ??
      false;

  /// Devices this connection uses.
  List<NetworkManagerDevice> get devices {
    var deviceObjectPaths = _object.getObjectPathArrayProperty(
          _activeConnectionInterfaceName,
          'Devices',
        ) ??
        [];
    var devices = <NetworkManagerDevice>[];
    for (var objectPath in deviceObjectPaths) {
      var device = _client._getDevice(objectPath);
      if (device != null) {
        devices.add(device);
      }
    }
    return devices;
  }

  /// Master device if this connection is a slave.
  NetworkManagerDevice? get master {
    var objectPath = _object.getObjectPathProperty(
      _activeConnectionInterfaceName,
      'Master',
    );
    return _client._getDevice(objectPath);
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerActiveConnection && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// IPv4 configuration.
class NetworkManagerIP4Config {
  final _NetworkManagerObject _object;

  NetworkManagerIP4Config(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_ip4ConfigInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// IP addresses. Each item will contain at least 'address' and 'prefix'. e.g. '192.168.1.42' and 24.
  List<Map<String, dynamic>> get addressData =>
      _object.getDataListProperty(_ip4ConfigInterfaceName, 'AddressData') ?? [];

  /// The gateway in use, e.g. '192.168.1.1'.
  String get gateway =>
      _object.getStringProperty(_ip4ConfigInterfaceName, 'Gateway') ?? '';

  /// Routes. Each item will contain at least 'dest' and 'prefix'.
  /// Some routes may include 'next-hop' and 'metric'.
  List<Map<String, dynamic>> get routeData =>
      _object.getDataListProperty(_ip4ConfigInterfaceName, 'RouteData') ?? [];

  /// Nameservers in use. Each item will contain at least 'address'.
  List<Map<String, dynamic>> get nameserverData =>
      _object.getDataListProperty(_ip4ConfigInterfaceName, 'NameserverData') ??
      [];

  /// Domains this address belongs to.
  List<String> get domains =>
      _object.getStringArrayProperty(_ip4ConfigInterfaceName, 'Domains') ?? [];

  /// DNS searches.
  List<String> get searches =>
      _object.getStringArrayProperty(_ip4ConfigInterfaceName, 'Searches') ?? [];

  /// Options that modify the behaviour of the DNS resolver.
  List<String> get dnsOptions =>
      _object.getStringArrayProperty(_ip4ConfigInterfaceName, 'DnsOptions') ??
      [];

  /// Relative priority of DNS servers.
  int get dnsPriority =>
      _object.getInt32Property(_ip4ConfigInterfaceName, 'DnsPriority') ?? 0;

  ///  The Windows Internet Name Service servers associated with the connection.
  List<String> get winsServerData =>
      _object.getStringArrayProperty(
          _ip4ConfigInterfaceName, 'WinsServerData') ??
      [];

  @override
  bool operator ==(other) =>
      other is NetworkManagerIP4Config && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// DCHPv4 configuration.
class NetworkManagerDHCP4Config {
  final _NetworkManagerObject _object;

  NetworkManagerDHCP4Config(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_dhcp4ConfigInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Configuration options returned by a DHCP server.
  Map<String, dynamic> get options {
    var value = _object.getCachedProperty(_dhcp4ConfigInterfaceName, 'Options');
    if (value == null) {
      return {};
    }
    if (value.signature != DBusSignature('a{sv}')) {
      return {};
    }
    return (value as DBusDict).children.map((key, value) => MapEntry(
        (key as DBusString).value, (value as DBusVariant).value.toNative()));
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerDHCP4Config && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// IPv6 configuration.
class NetworkManagerIP6Config {
  final _NetworkManagerObject _object;

  NetworkManagerIP6Config(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_ip6ConfigInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// IP addresses. Each item will contain at least 'address' and 'prefix'. e.g. '2001:db8:85a3::8a2e:370:7334' and 64.
  List<Map<String, dynamic>> get addressData =>
      _object.getDataListProperty(_ip6ConfigInterfaceName, 'AddressData') ?? [];

  /// The gateway in use, e.g. '2001:db8:85a3::8a2e:370:7334'.
  String get gateway =>
      _object.getStringProperty(_ip6ConfigInterfaceName, 'Gateway') ?? '';

  /// Routes. Each item will contain at least 'dest' and 'prefix'.
  /// Some routes may include 'next-hop' and 'metric'.
  List<Map<String, dynamic>> get routeData =>
      _object.getDataListProperty(_ip6ConfigInterfaceName, 'RouteData') ?? [];

  /// Nameservers in use. Each item will contain at least 'address'.
  List<Map<String, dynamic>> get nameserverData =>
      _object.getDataListProperty(_ip6ConfigInterfaceName, 'NameserverData') ??
      [];

  /// Domains this address belongs to.
  List<String> get domains =>
      _object.getStringArrayProperty(_ip6ConfigInterfaceName, 'Domains') ?? [];

  /// DNS searches.
  List<String> get searches =>
      _object.getStringArrayProperty(_ip6ConfigInterfaceName, 'Searches') ?? [];

  /// Options that modify the behaviour of the DNS resolver.
  List<String> get dnsOptions =>
      _object.getStringArrayProperty(_ip6ConfigInterfaceName, 'DnsOptions') ??
      [];

  /// Relative priority of DNS servers.
  int get dnsPriority =>
      _object.getInt32Property(_ip6ConfigInterfaceName, 'DnsPriority') ?? 0;

  @override
  bool operator ==(other) =>
      other is NetworkManagerIP6Config && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// DCHPv6 configuration.
class NetworkManagerDHCP6Config {
  final _NetworkManagerObject _object;

  NetworkManagerDHCP6Config(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_dhcp6ConfigInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Configuration options returned by a DHCP server.
  Map<String, dynamic> get options {
    var value = _object.getCachedProperty(_dhcp6ConfigInterfaceName, 'Options');
    if (value == null) {
      return {};
    }
    if (value.signature != DBusSignature('a{sv}')) {
      return {};
    }
    return (value as DBusDict).children.map((key, value) => MapEntry(
        (key as DBusString).value, (value as DBusVariant).value.toNative()));
  }

  @override
  bool operator ==(other) =>
      other is NetworkManagerDHCP6Config && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

/// WiFi access point.
class NetworkManagerAccessPoint {
  final _NetworkManagerObject _object;

  NetworkManagerAccessPoint(this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _object.interfaces[_accessPointInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Capabilities of this access point.
  List<NetworkManagerWifiAccessPointFlag> get flags {
    var value =
        _object.getUint32Property(_accessPointInterfaceName, 'Flags') ?? 0;
    var flags = <NetworkManagerWifiAccessPointFlag>[];
    if ((value & 0x01) != 0) {
      flags.add(NetworkManagerWifiAccessPointFlag.privacy);
    }
    if ((value & 0x02) != 0) {
      flags.add(NetworkManagerWifiAccessPointFlag.wps);
    }
    if ((value & 0x04) != 0) {
      flags.add(NetworkManagerWifiAccessPointFlag.wpsPushButton);
    }
    if ((value & 0x08) != 0) {
      flags.add(NetworkManagerWifiAccessPointFlag.wpsPin);
    }
    return flags;
  }

  /// WPA security capabilities of this access point.
  List<NetworkManagerWifiAccessPointSecurityFlag> get wpaFlags {
    var value =
        _object.getUint32Property(_accessPointInterfaceName, 'WpaFlags') ?? 0;
    return _decodeWifiAccessPointSecurityFlags(value);
  }

  /// RSN security capabilities of this access point.
  List<NetworkManagerWifiAccessPointSecurityFlag> get rsnFlags {
    var value =
        _object.getUint32Property(_accessPointInterfaceName, 'RsnFlags') ?? 0;
    return _decodeWifiAccessPointSecurityFlags(value);
  }

  /// SSID advertised by the access point.
  /// Note this is in binary form, but is likely to contain a text string.
  List<int> get ssid {
    var value = _object.getCachedProperty(_accessPointInterfaceName, 'Ssid');
    if (value == null) {
      return [];
    }
    if (value.signature != DBusSignature('ay')) {
      return [];
    }
    return (value as DBusArray)
        .children
        .map((e) => (e as DBusByte).value)
        .toList();
  }

  /// Radio frequency of this access point in MHz.
  int get frequency =>
      _object.getUint32Property(_accessPointInterfaceName, 'Frequency') ?? 0;

  /// The hardware address (BSSID) of this access point.
  String get hwAddress =>
      _object.getStringProperty(_accessPointInterfaceName, 'HwAddress') ?? '';

  /// Mode this access point is operating in.
  NetworkManagerWifiMode get mode {
    var value =
        _object.getUint32Property(_accessPointInterfaceName, 'Mode') ?? 0;
    return _decodeWifiMode(value);
  }

  /// Maximum bitrate this access point is capable of in kilobits/second.
  int get maxBitrate =>
      _object.getUint32Property(_accessPointInterfaceName, 'MaxBitrate') ?? 0;

  /// Signal quality of access point in percent.
  int get strength =>
      _object.getByteProperty(_accessPointInterfaceName, 'Strength') ?? 0;

  /// Last time this access point was seen in a scan in seconds since boot.
  int get lastSeen =>
      _object.getInt32Property(_accessPointInterfaceName, 'LastSeen') ?? 0;

  @override
  bool operator ==(other) =>
      other is NetworkManagerAccessPoint && other._object == _object;

  @override
  int get hashCode => _object.hashCode;

  @override
  String toString() => '$runtimeType(path: ${_object.path.value})';
}

class _NetworkManagerInterface {
  final Map<String, DBusValue> properties;
  final propertiesChangedStreamController =
      StreamController<List<String>>.broadcast();

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      propertiesChangedStreamController.stream;

  _NetworkManagerInterface(this.properties);

  void updateProperties(Map<String, DBusValue> changedProperties) {
    properties.addAll(changedProperties);
    propertiesChangedStreamController.add(changedProperties.keys.toList());
  }
}

class _NetworkManagerObject extends DBusRemoteObject {
  final interfaces = <String, _NetworkManagerInterface>{};

  void updateInterfaces(
      Map<String, Map<String, DBusValue>> interfacesAndProperties) {
    interfacesAndProperties.forEach((interfaceName, properties) {
      interfaces[interfaceName] = _NetworkManagerInterface(properties);
    });
  }

  /// Returns true if removing [interfaceNames] would remove all interfaces on this object.
  bool wouldRemoveAllInterfaces(List<String> interfaceNames) {
    for (var interface in interfaces.keys) {
      if (!interfaceNames.contains(interface)) {
        return false;
      }
    }
    return true;
  }

  void removeInterfaces(List<String> interfaceNames) {
    for (var interfaceName in interfaceNames) {
      interfaces.remove(interfaceName);
    }
  }

  void updateProperties(
      String interfaceName, Map<String, DBusValue> changedProperties) {
    var interface = interfaces[interfaceName];
    if (interface != null) {
      interface.updateProperties(changedProperties);
    }
  }

  /// Gets a cached property.
  DBusValue? getCachedProperty(String interfaceName, String name) {
    var interface = interfaces[interfaceName];
    if (interface == null) {
      return null;
    }
    return interface.properties[name];
  }

  /// Gets a cached boolean property, or returns null if not present or not the correct type.
  bool? getBooleanProperty(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('b')) {
      return null;
    }
    return (value as DBusBoolean).value;
  }

  /// Gets a cached unsigned 8 bit integer property, or returns null if not present or not the correct type.
  int? getByteProperty(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('y')) {
      return null;
    }
    return (value as DBusByte).value;
  }

  /// Gets a cached signed 32 bit integer property, or returns null if not present or not the correct type.
  int? getInt32Property(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('i')) {
      return null;
    }
    return (value as DBusInt32).value;
  }

  /// Gets a cached unsigned 32 bit integer property, or returns null if not present or not the correct type.
  int? getUint32Property(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('u')) {
      return null;
    }
    return (value as DBusUint32).value;
  }

  /// Gets a cached signed 64 bit integer property, or returns null if not present or not the correct type.
  int? getInt64Property(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('x')) {
      return null;
    }
    return (value as DBusInt64).value;
  }

  /// Gets a cached unsigned 64 bit integer property, or returns null if not present or not the correct type.
  int? getUint64Property(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('t')) {
      return null;
    }
    return (value as DBusUint64).value;
  }

  /// Gets a cached string property, or returns null if not present or not the correct type.
  String? getStringProperty(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('s')) {
      return null;
    }
    return (value as DBusString).value;
  }

  /// Gets a cached string array property, or returns null if not present or not the correct type.
  List<String>? getStringArrayProperty(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('as')) {
      return null;
    }
    return (value as DBusArray)
        .children
        .map((e) => (e as DBusString).value)
        .toList();
  }

  /// Gets a cached object path property, or returns null if not present or not the correct type.
  DBusObjectPath? getObjectPathProperty(String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('o')) {
      return null;
    }
    return (value as DBusObjectPath);
  }

  /// Gets a cached object path array property, or returns null if not present or not the correct type.
  List<DBusObjectPath>? getObjectPathArrayProperty(
      String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('ao')) {
      return null;
    }
    return (value as DBusArray)
        .children
        .map((e) => (e as DBusObjectPath))
        .toList();
  }

  /// Gets a cached list of data property, or returns null if not present or not the correct type.
  List<Map<String, dynamic>>? getDataListProperty(
      String interface, String name) {
    var value = getCachedProperty(interface, name);
    if (value == null) {
      return null;
    }
    if (value.signature != DBusSignature('aa{sv}')) {
      return null;
    }
    Map<String, dynamic> convertData(DBusValue value) {
      return (value as DBusDict).children.map((key, value) => MapEntry(
            (key as DBusString).value,
            (value as DBusVariant).value.toNative(),
          ));
    }

    return (value as DBusArray)
        .children
        .map((value) => convertData(value))
        .toList();
  }

  _NetworkManagerObject(DBusClient client, DBusObjectPath path,
      Map<String, Map<String, DBusValue>> interfacesAndProperties)
      : super(client, name: 'org.freedesktop.NetworkManager', path: path) {
    updateInterfaces(interfacesAndProperties);
  }
}

/// A client that connects to NetworkManager.
class NetworkManagerClient {
  /// Stream of devices as they are added.
  Stream<NetworkManagerDevice> get deviceAdded =>
      _deviceAddedStreamController.stream;

  /// Stream of devices as they are removed.
  Stream<NetworkManagerDevice> get deviceRemoved =>
      _deviceRemovedStreamController.stream;

  /// Stream of active connections as they are added.
  Stream<NetworkManagerActiveConnection> get activeConnectionAdded =>
      _activeConnectionAddedStreamController.stream;

  /// Stream of active connections as they are removed.
  Stream<NetworkManagerActiveConnection> get activeConnectionRemoved =>
      _activeConnectionRemovedStreamController.stream;

  /// The bus this client is connected to.
  final DBusClient _bus;
  final bool _closeBus;

  /// The root D-Bus NetworkManager object at path '/org/freedesktop'.
  late final DBusRemoteObjectManager _root;

  // Objects exported on the bus.
  final _objects = <DBusObjectPath, _NetworkManagerObject>{};

  // Subscription to object manager signals.
  StreamSubscription? _objectManagerSubscription;

  final _deviceAddedStreamController =
      StreamController<NetworkManagerDevice>.broadcast();
  final _deviceRemovedStreamController =
      StreamController<NetworkManagerDevice>.broadcast();
  final _activeConnectionAddedStreamController =
      StreamController<NetworkManagerActiveConnection>.broadcast();
  final _activeConnectionRemovedStreamController =
      StreamController<NetworkManagerActiveConnection>.broadcast();

  /// Creates a new NetworkManager client connected to the system D-Bus.
  NetworkManagerClient({DBusClient? bus})
      : _bus = bus ?? DBusClient.system(),
        _closeBus = bus == null {
    _root = DBusRemoteObjectManager(
      _bus,
      name: 'org.freedesktop.NetworkManager',
      path: DBusObjectPath('/org/freedesktop'),
    );
  }

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged =>
      _manager?.interfaces[_managerInterfaceName]
          ?.propertiesChangedStreamController.stream ??
      Stream<List<String>>.empty();

  /// Connects to the NetworkManager D-Bus objects.
  /// Must be called before accessing methods and properties.
  Future<void> connect() async {
    // Already connected
    if (_objectManagerSubscription != null) {
      return;
    }

    // Subscribe to changes
    _objectManagerSubscription = _root.signals.listen((signal) {
      if (signal is DBusObjectManagerInterfacesAddedSignal) {
        var object = _objects[signal.changedPath];
        if (object != null) {
          object.updateInterfaces(signal.interfacesAndProperties);
        } else {
          object = _NetworkManagerObject(
              _bus, signal.changedPath, signal.interfacesAndProperties);
          _objects[signal.changedPath] = object;
          if (object.interfaces.containsKey(_deviceInterfaceName)) {
            _deviceAddedStreamController
                .add(NetworkManagerDevice(this, object));
          } else if (object.interfaces
              .containsKey(_activeConnectionInterfaceName)) {
            _activeConnectionAddedStreamController
                .add(NetworkManagerActiveConnection(this, object));
          }
        }
      } else if (signal is DBusObjectManagerInterfacesRemovedSignal) {
        var object = _objects[signal.changedPath];
        if (object != null) {
          // If all the interface are removed, then this object has been removed.
          // Keep the previous values around for the client to use.
          if (object.wouldRemoveAllInterfaces(signal.interfaces)) {
            _objects.remove(signal.changedPath);
          } else {
            object.removeInterfaces(signal.interfaces);
          }

          if (signal.interfaces.contains(_deviceInterfaceName)) {
            _deviceRemovedStreamController
                .add(NetworkManagerDevice(this, object));
          }
          if (signal.interfaces.contains(_activeConnectionInterfaceName)) {
            _activeConnectionRemovedStreamController
                .add(NetworkManagerActiveConnection(this, object));
          }
        }
      } else if (signal is DBusPropertiesChangedSignal) {
        var object = _objects[signal.path];
        if (object != null) {
          object.updateProperties(
              signal.propertiesInterface, signal.changedProperties);
        }
      }
    });

    // Find all the objects exported.
    var objects = await _root.getManagedObjects();
    objects.forEach((objectPath, interfacesAndProperties) {
      _objects[objectPath] =
          _NetworkManagerObject(_bus, objectPath, interfacesAndProperties);
    });
  }

  /// The list of realized network device.
  /// Realized devices are those which have backing resources (eg from the kernel or a management daemon like ModemManager, teamd, etc).
  List<NetworkManagerDevice> get devices {
    return _getDevices('Devices');
  }

  /// The list of both realized and un-realized network devices.
  /// Un-realized devices are software devices which do not yet have backing resources, but for which backing resources can be created if the device is activated.
  List<NetworkManagerDevice> get allDevices {
    return _getDevices('AllDevices');
  }

  List<NetworkManagerDevice> _getDevices(String propertyName) {
    var deviceObjectPaths = _manager?.getObjectPathArrayProperty(
            _managerInterfaceName, propertyName) ??
        [];
    var devices = <NetworkManagerDevice>[];
    for (var objectPath in deviceObjectPaths) {
      var device = _getDevice(objectPath);
      if (device != null) {
        devices.add(device);
      }
    }

    return devices;
  }

  // FIXME: Checkpoints

  /// True if networking is enabled.
  bool get networkingEnabled {
    return _manager?.getBooleanProperty(
          _managerInterfaceName,
          'NetworkingEnabled',
        ) ??
        false;
  }

  /// True if wireless network is enabled.
  bool get wirelessEnabled {
    return _manager?.getBooleanProperty(
            _managerInterfaceName, 'WirelessEnabled') ??
        false;
  }

  /// Sets if wireless network is enabled.
  Future<void> setWirelessEnabled(bool value) async {
    await _manager?.setProperty(
      _managerInterfaceName,
      'WirelessEnabled',
      DBusBoolean(value),
    );
  }

  /// True if wireless network is enabled via a hardware switch.
  bool get wirelessHardwareEnabled {
    return _manager?.getBooleanProperty(
            _managerInterfaceName, 'WirelessHardwareEnabled') ??
        false;
  }

  /// True if mobile broadband is enabled.
  bool get wwanEnabled {
    return _manager?.getBooleanProperty(_managerInterfaceName, 'WwanEnabled') ??
        false;
  }

  /// Sets if mobile broadband is enabled.
  Future<void> setWwanEnabled(bool value) async {
    await _manager?.setProperty(
      _managerInterfaceName,
      'WwanEnabled',
      DBusBoolean(value),
    );
  }

  /// True if mobile broadband is enabled via a hardware switch.
  bool get wwanHardwareEnabled {
    return _manager?.getBooleanProperty(
          _managerInterfaceName,
          'WwanHardwareEnabled',
        ) ??
        false;
  }

  /// Currently active connections.
  List<NetworkManagerActiveConnection> get activeConnections {
    var connectionObjectPaths = _manager?.getObjectPathArrayProperty(
          _managerInterfaceName,
          'ActiveConnections',
        ) ??
        [];
    var connections = <NetworkManagerActiveConnection>[];
    for (var objectPath in connectionObjectPaths) {
      var connection = _objects[objectPath];
      if (connection != null) {
        connections.add(NetworkManagerActiveConnection(this, connection));
      }
    }

    return connections;
  }

  /// The primary connection being used to access the network.
  NetworkManagerActiveConnection? get primaryConnection {
    var objectPath = _manager?.getObjectPathProperty(
        _managerInterfaceName, 'PrimaryConnection');
    var connection = _objects[objectPath];
    if (connection == null) {
      return null;
    }

    return NetworkManagerActiveConnection(this, connection);
  }

  /// The type of connection being used to access the network.
  String get primaryConnectionType {
    return _manager?.getStringProperty(
          _managerInterfaceName,
          'PrimaryConnectionType',
        ) ??
        '';
  }

  /// True if the primary connection has traffic limitations.
  NetworkManagerMetered get metered => _decodeMetered(
      _manager?.getUint32Property(_managerInterfaceName, 'Metered') ?? 0);

  // FIXME: ActivatingConnection

  /// True is NetworkManager is still starting up.
  bool get startup {
    return _manager?.getBooleanProperty(_managerInterfaceName, 'Startup') ??
        false;
  }

  /// The version of NetworkManager running.
  String get version {
    return _manager?.getStringProperty(_managerInterfaceName, 'Version') ?? '';
  }

  // FIXME: Capabilities

  /// The result of the last connectivity check.
  NetworkManagerConnectivityState get connectivity {
    var value =
        _manager?.getUint32Property(_managerInterfaceName, 'Connectivity') ?? 0;
    return _decodeConnectivityState(value);
  }

  /// True if connectivity checking is available.
  bool get connectivityCheckAvailable {
    return _manager?.getBooleanProperty(
          _managerInterfaceName,
          'ConnectivityCheckAvailable',
        ) ??
        false;
  }

  /// True if connectivity checking is enabled.
  bool get connectivityCheckEnabled {
    return _manager?.getBooleanProperty(
          _managerInterfaceName,
          'ConnectivityCheckEnabled',
        ) ??
        false;
  }

  /// Sets if connectivity checking is enabled.
  Future<void> setConnectivityCheckEnabled(bool value) async {
    await _manager?.setProperty(
      _managerInterfaceName,
      'ConnectivityCheckEnabled',
      DBusBoolean(value),
    );
  }

  /// URI used for connectivity checking.
  String get connectivityCheckUri {
    return _manager?.getStringProperty(
          _managerInterfaceName,
          'ConnectivityCheckUri',
        ) ??
        '';
  }

  /// The overall networking state.
  NetworkManagerState get state {
    var value =
        _manager?.getUint32Property(_managerInterfaceName, 'State') ?? 0;
    return _decodeState(value);
  }

  // FIXME: GlobalDnsConfiguration

  _NetworkManagerObject? get _manager =>
      _objects[DBusObjectPath('/org/freedesktop/NetworkManager')];

  /// Gets the settings object.
  NetworkManagerSettings get settings {
    var object =
        _objects[DBusObjectPath('/org/freedesktop/NetworkManager/Settings')];
    return NetworkManagerSettings(
        this, object ?? _NetworkManagerObject(_bus, DBusObjectPath('/'), {}));
  }

  /// Gets the DNS manager object.
  NetworkManagerDnsManager get dnsManager {
    var object =
        _objects[DBusObjectPath('/org/freedesktop/NetworkManager/DnsManager')];
    return NetworkManagerDnsManager(
        object ?? _NetworkManagerObject(_bus, DBusObjectPath('/'), {}));
  }

  /// Adds a new connection for [device] and activates it.
  ///
  /// Optionally, [connection] settings may be specified as a template. Missing
  /// settings are automatically filled in.
  Future<NetworkManagerActiveConnection> addAndActivateConnection(
      {Map<String, Map<String, DBusValue>> connection = const {},
      required NetworkManagerDevice device,
      NetworkManagerAccessPoint? accessPoint}) async {
    var result = await _manager!.callMethod(
        _managerInterfaceName,
        'AddAndActivateConnection',
        [
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              connection.map((key, value) =>
                  MapEntry(DBusString(key), DBusDict.stringVariant(value)))),
          device._object.path,
          accessPoint?._object.path ?? DBusObjectPath('/'),
        ],
        replySignature: DBusSignature('oo'));
    var path = result.returnValues[1] as DBusObjectPath;
    return activeConnectionAdded
        .firstWhere((connection) => connection._object.path == path);
  }

  /// Activates a connection for [device].
  ///
  /// A specific [connection] may be specified, or else it is detected automatically.
  Future<NetworkManagerActiveConnection> activateConnection(
      {required NetworkManagerDevice device,
      NetworkManagerSettingsConnection? connection,
      NetworkManagerAccessPoint? accessPoint}) async {
    var result = await _manager!.callMethod(
        _managerInterfaceName,
        'ActivateConnection',
        [
          connection?._object.path ?? DBusObjectPath('/'),
          device._object.path,
          accessPoint?._object.path ?? DBusObjectPath('/'),
        ],
        replySignature: DBusSignature('o'));
    return _getActiveConnection(result.returnValues[0] as DBusObjectPath)!;
  }

  /// Deactivates an active [connection].
  Future<void> deactivateConnection(
      NetworkManagerActiveConnection connection) async {
    await _manager?.callMethod(
        _managerInterfaceName,
        'DeactivateConnection',
        [
          connection._object.path,
        ],
        replySignature: DBusSignature(''));
  }

  /// Terminates all active connections. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    if (_objectManagerSubscription != null) {
      await _objectManagerSubscription!.cancel();
      _objectManagerSubscription = null;
    }
    if (_closeBus) {
      await _bus.close();
    }
  }

  NetworkManagerDevice? _getDevice(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerDevice(this, config);
  }

  NetworkManagerSettingsConnection? _getConnection(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerSettingsConnection(config);
  }

  NetworkManagerActiveConnection? _getActiveConnection(
      DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerActiveConnection(this, config);
  }

  NetworkManagerIP4Config? _getIP4Config(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerIP4Config(config);
  }

  NetworkManagerDHCP4Config? _getDHCP4Config(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerDHCP4Config(config);
  }

  NetworkManagerIP6Config? _getIP6Config(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerIP6Config(config);
  }

  NetworkManagerDHCP6Config? _getDHCP6Config(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerDHCP6Config(config);
  }

  NetworkManagerAccessPoint? _getAccessPoint(DBusObjectPath? objectPath) {
    if (objectPath == null) {
      return null;
    }
    var config = _objects[objectPath];
    if (config == null) {
      return null;
    }
    return NetworkManagerAccessPoint(config);
  }
}
