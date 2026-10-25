import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:nm/nm.dart';
import 'package:test/test.dart';

class MockNetworkManagerObject extends DBusObject {
  MockNetworkManagerObject(DBusObjectPath path) : super(path);
}

class MockNetworkManagerManager extends MockNetworkManagerObject {
  final MockNetworkManagerServer server;

  MockNetworkManagerManager(this.server)
      : super(DBusObjectPath('/org/freedesktop/NetworkManager'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager': {
          'ActivatingConnection':
              server.activatingConnection?.path ?? DBusObjectPath('/'),
          'ActiveConnections': DBusArray.objectPath(
              server.activeConnections.map((device) => device.path)),
          'AllDevices': DBusArray.objectPath(
              server.allDevices.map((device) => device.path)),
          'Capabilities': DBusArray.uint32(server.capabilities),
          'Checkpoints': DBusArray.objectPath([]), // FIXME
          'Connectivity': DBusUint32(server.connectivity),
          'ConnectivityCheckAvailable':
              DBusBoolean(server.connectivityCheckAvailable),
          'ConnectivityCheckEnabled':
              DBusBoolean(server.connectivityCheckEnabled),
          'ConnectivityCheckUri': DBusString(server.connectivityCheckUri),
          'Devices': DBusArray(
              DBusSignature('o'), server.devices.map((device) => device.path)),
          'Metered': DBusUint32(server.metered),
          'NetworkingEnabled': DBusBoolean(server.networkingEnabled),
          'PrimaryConnection': server.activeConnections.isNotEmpty
              ? server.activeConnections[0].path
              : DBusObjectPath('/'),
          'PrimaryConnectionType': DBusString(
              server.activeConnections.isNotEmpty
                  ? server.activeConnections[0].type
                  : ''),
          'Startup': DBusBoolean(server.startup),
          'State': DBusUint32(server.state),
          'Version': DBusString(server.version),
          'WimaxHardwareEnabled': DBusBoolean(server.wimaxHardwareEnabled),
          'WirelessEnabled': DBusBoolean(server.wirelessEnabled),
          'WirelessHardwareEnabled':
              DBusBoolean(server.wirelessHardwareEnabled),
          'WwanEnabled': DBusBoolean(server.wwanEnabled),
          'WwanHardwareEnabled': DBusBoolean(server.wwanHardwareEnabled)
        }
      };

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface != 'org.freedesktop.NetworkManager') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (name) {
      case 'ConnectivityCheckEnabled':
        server.connectivityCheckEnabled = (value as DBusBoolean).value;
        await emitPropertiesChanged('org.freedesktop.NetworkManager',
            changedProperties: {
              'ConnectivityCheckEnabled':
                  DBusBoolean(server.connectivityCheckEnabled)
            });
        return DBusMethodSuccessResponse();
      case 'WirelessEnabled':
        server.wirelessEnabled = (value as DBusBoolean).value;
        await emitPropertiesChanged('org.freedesktop.NetworkManager',
            changedProperties: {
              'WirelessEnabled': DBusBoolean(server.wirelessEnabled)
            });
        return DBusMethodSuccessResponse();
      case 'WwanEnabled':
        server.wwanEnabled = (value as DBusBoolean).value;
        await emitPropertiesChanged('org.freedesktop.NetworkManager',
            changedProperties: {
              'WwanEnabled': DBusBoolean(server.wwanEnabled)
            });
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.freedesktop.NetworkManager') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'ActivateConnection':
        var path = methodCall.values[0] as DBusObjectPath;
        var index = server.connectionSettings
            .indexWhere((s) => s.path == path || path == DBusObjectPath('/'));
        await server.addActiveConnection(
            id: server.connectionSettings[index].path.value);
        return DBusMethodSuccessResponse(
            [server.activeConnections[index].path]);
      case 'AddAndActivateConnection':
        final device = server.devices.firstWhere(
            (device) => device.path == methodCall.values[1] as DBusObjectPath);
        var connection = await server.addConnectionSettings(
          settings: (methodCall.values[0] as DBusDict).children.map(
              (group, properties) => MapEntry(
                  (group as DBusString).value,
                  (properties as DBusDict).children.map((key, value) =>
                      MapEntry((key as DBusString).value,
                          (value as DBusVariant).value)))),
        );
        var activeConnection = await server
            .addActiveConnection(id: connection.path.value, devices: [device]);
        return DBusMethodSuccessResponse(
            [connection.path, activeConnection.path]);
      case 'CheckConnectivity':
        return DBusMethodSuccessResponse([DBusUint32(server.connectivity)]);
      case 'DeactivateConnection':
        var path = methodCall.values[0] as DBusObjectPath;
        var connection =
            server.activeConnections.singleWhere((c) => c.path == path);
        await server.removeActiveConnection(connection);
        return DBusMethodSuccessResponse([]);
      case 'Enable':
        return DBusMethodSuccessResponse([]);
      case 'GetAllDevices':
        return DBusMethodSuccessResponse([
          DBusArray.objectPath(server.allDevices.map((device) => device.path))
        ]);
      case 'GetDeviceByIpIface':
        return DBusMethodSuccessResponse([DBusObjectPath('/')]);
      case 'GetDevices':
        return DBusMethodSuccessResponse([
          DBusArray.objectPath(server.allDevices.map((device) => device.path))
        ]);
      case 'GetPermissions':
        return DBusMethodSuccessResponse(
            [DBusDict(DBusSignature('s'), DBusSignature('s'), {})]);
      case 'Reload':
        return DBusMethodSuccessResponse([]);
      case 'SetLogging':
        return DBusMethodSuccessResponse([]);
      case 'Sleep':
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockNetworkManagerDnsManager extends MockNetworkManagerObject {
  final MockNetworkManagerServer server;

  MockNetworkManagerDnsManager(this.server)
      : super(DBusObjectPath('/org/freedesktop/NetworkManager/DnsManager'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.DnsManager': {
          'Configuration': DBusArray(
              DBusSignature('a{sv}'),
              server.dnsConfiguration
                  .map((data) => DBusDict.stringVariant(data))),
          'Mode': DBusString(server.dnsMode),
          'RcManager': DBusString(server.dnsRcManager)
        }
      };
}

class MockNetworkManagerSettings extends MockNetworkManagerObject {
  final MockNetworkManagerServer server;

  MockNetworkManagerSettings(this.server)
      : super(DBusObjectPath('/org/freedesktop/NetworkManager/Settings'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.Settings': {
          'CanModify': DBusBoolean(server.settingsCanModify),
          'Connections': DBusArray.objectPath(
              server.connectionSettings.map((setting) => setting.path)),
          'Hostname': DBusString(server.hostname)
        }
      };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.freedesktop.NetworkManager.Settings') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'AddConnection':
        var connection = await server.addConnectionSettings();
        return DBusMethodSuccessResponse([connection.path]);
      case 'AddConnectionUnsaved':
        var connection = await server.addConnectionSettings(unsaved: true);
        return DBusMethodSuccessResponse([connection.path]);
      case 'ListConnections':
        return DBusMethodSuccessResponse([
          DBusArray.objectPath(
              server.connectionSettings.map((setting) => setting.path))
        ]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockNetworkManagerConnectionSettings extends MockNetworkManagerObject {
  final String filename;
  final int flags;
  final bool unsaved;

  var deleted = false;
  var saved = false;
  Map<String, Map<String, DBusValue>> secrets;
  Map<String, Map<String, DBusValue>> settings;

  MockNetworkManagerConnectionSettings(int id,
      {this.filename = '',
      this.flags = 0,
      Map<String, Map<String, DBusValue>>? secrets,
      Map<String, Map<String, DBusValue>>? settings,
      this.unsaved = false})
      : secrets = secrets ?? <String, Map<String, DBusValue>>{},
        settings = settings ?? <String, Map<String, DBusValue>>{},
        super(DBusObjectPath('/org/freedesktop/NetworkManager/Settings/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.Settings.Connection': {
          'Filename': DBusString(filename),
          'Flags': DBusUint32(flags),
          'Unsaved': DBusBoolean(unsaved)
        }
      };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface !=
        'org.freedesktop.NetworkManager.Settings.Connection') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'ClearSecrets':
        secrets = {};
        return DBusMethodSuccessResponse([]);
      case 'Delete':
        deleted = true;
        return DBusMethodSuccessResponse([]);
      case 'GetSecrets':
        //FIXME var settingName = (methodCall.values[0] as DBusString).value;
        return DBusMethodSuccessResponse([
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              secrets.map((group, properties) => MapEntry(
                  DBusString(group), DBusDict.stringVariant(properties))))
        ]);
      case 'GetSettings':
        return DBusMethodSuccessResponse([
          DBusDict(
              DBusSignature('s'),
              DBusSignature('a{sv}'),
              settings.map((group, properties) => MapEntry(
                  DBusString(group), DBusDict.stringVariant(properties))))
        ]);
      case 'Save':
        saved = true;
        return DBusMethodSuccessResponse([]);
      case 'Update':
        settings = (methodCall.values[0] as DBusDict).children.map(
            (group, properties) => MapEntry(
                (group as DBusString).value,
                (properties as DBusDict).children.map((key, value) => MapEntry(
                    (key as DBusString).value, (value as DBusVariant).value))));
        saved = true;
        return DBusMethodSuccessResponse([]);
      case 'UpdateUnsaved':
        settings = (methodCall.values[0] as DBusDict).children.map(
            (group, properties) => MapEntry(
                (group as DBusString).value,
                (properties as DBusDict).children.map((key, value) => MapEntry(
                    (key as DBusString).value, (value as DBusVariant).value))));
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockNetworkManagerActiveConnection extends MockNetworkManagerObject {
  final bool default4;
  final bool default6;
  final List<MockNetworkManagerDevice> devices;
  final MockNetworkManagerDHCP4Config? dhcp4Config;
  final MockNetworkManagerDHCP6Config? dhcp6Config;
  final String id;
  final MockNetworkManagerIP4Config? ip4Config;
  final MockNetworkManagerIP6Config? ip6Config;
  final int state;
  final int stateFlags;
  final String type;
  final String uuid;
  final bool vpn;

  MockNetworkManagerActiveConnection(int number,
      {this.default4 = false,
      this.default6 = false,
      this.devices = const [],
      this.dhcp4Config,
      this.dhcp6Config,
      this.id = '',
      this.ip4Config,
      this.ip6Config,
      this.state = 0,
      this.stateFlags = 0,
      this.type = '',
      this.uuid = '',
      this.vpn = false})
      : super(DBusObjectPath(
            '/org/freedesktop/NetworkManager/ActiveConnection/$number'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.Connection.Active': {
          'Connection': DBusObjectPath('/'), // FIXME
          'Devices': DBusArray(
              DBusSignature('o'), devices.map((device) => device.path)),
          'Default': DBusBoolean(default4),
          'Default6': DBusBoolean(default6),
          'Dhcp4Config': dhcp4Config?.path ?? DBusObjectPath('/'),
          'Dhcp6Config': dhcp6Config?.path ?? DBusObjectPath('/'),
          'Id': DBusString(id),
          'Ip4Config': ip4Config?.path ?? DBusObjectPath('/'),
          'Ip6Config': ip6Config?.path ?? DBusObjectPath('/'),
          'Master': DBusObjectPath('/'), // FIXME
          'SpecificObject': DBusObjectPath('/'), // FIXME
          'State': DBusUint32(state),
          'StateFlags': DBusUint32(stateFlags),
          'Type': DBusString(type),
          'Uuid': DBusString(uuid),
          'Vpn': DBusBoolean(vpn),
        }
      };
}

class MockNetworkManagerDevice extends MockNetworkManagerObject {
  bool autoconnect;
  final int capabilities;
  final int deviceType;
  final MockNetworkManagerDHCP4Config? dhcp4Config;
  final MockNetworkManagerDHCP6Config? dhcp6Config;
  final String driver;
  final String driverVersion;
  final bool firmwareMissing;
  final String firmwareVersion;
  final String hwAddress;
  final String interface;
  final int interfaceFlags;
  final MockNetworkManagerIP4Config? ip4Config;
  final int ip4Connectivity;
  final MockNetworkManagerIP6Config? ip6Config;
  final int ip6Connectivity;
  final String ipInterface;
  bool managed;
  final int metered;
  final int mtu;
  final bool nmPluginMissing;
  final String path_;
  final String permHwAddress;
  final String physicalPortId;
  final bool real;
  final int state;
  final int stateReason;
  final String udi;

  final bool hasBluetooth;
  final int btCapabilities;
  final String name;

  final bool hasBridge;
  final List<MockNetworkManagerDevice> slaves;

  final bool hasGeneric;
  final String typeDescription;

  final bool hasTun;
  final int group;
  final bool multiQueue;
  final bool noPi;
  final int owner;
  final String tunMode;
  final bool vnetHdr;

  final bool hasVlan;
  final MockNetworkManagerDevice? parent;
  final int vlanId;

  final bool hasWired;
  final List<String> s390Subchannels;
  final int speed;

  final bool hasWireless;
  final List<MockNetworkManagerAccessPoint> accessPoints;
  final MockNetworkManagerAccessPoint? activeAccessPoint;
  final int bitrate;
  final int lastScan;
  final int wirelessMode;
  final int wirelessCapabilities;

  final bool hasStatistics;
  int refreshRateMs;
  final int rxBytes;
  final int txBytes;

  bool scanRequested = false;
  var scanOptions = <String, DBusValue>{};
  bool disconnected = false;
  bool deleted = false;

  MockNetworkManagerDevice(int id,
      {this.autoconnect = false,
      this.capabilities = 0,
      this.deviceType = 0,
      this.dhcp4Config,
      this.dhcp6Config,
      this.driver = '',
      this.driverVersion = '',
      this.firmwareMissing = false,
      this.firmwareVersion = '',
      this.hwAddress = '',
      this.interface = '',
      this.interfaceFlags = 0,
      this.ip4Config,
      this.ip4Connectivity = 0,
      this.ip6Config,
      this.ip6Connectivity = 0,
      this.ipInterface = '',
      this.managed = true,
      this.metered = 0,
      this.mtu = 0,
      this.nmPluginMissing = false,
      this.path_ = '',
      this.permHwAddress = '',
      this.physicalPortId = '',
      this.real = true,
      this.state = 0,
      this.stateReason = -1,
      this.udi = '',
      this.hasBluetooth = false,
      this.btCapabilities = 0,
      this.name = '',
      this.hasBridge = false,
      this.slaves = const [],
      this.hasGeneric = false,
      this.typeDescription = '',
      this.hasTun = false,
      this.group = -1,
      this.multiQueue = false,
      this.noPi = false,
      this.owner = -1,
      this.tunMode = '',
      this.vnetHdr = false,
      this.hasVlan = false,
      this.parent,
      this.vlanId = 0,
      this.hasWired = false,
      this.speed = 0,
      this.s390Subchannels = const [],
      this.hasWireless = false,
      this.accessPoints = const [],
      this.activeAccessPoint,
      this.bitrate = 0,
      this.lastScan = 0,
      this.wirelessMode = 0,
      this.wirelessCapabilities = 0,
      this.hasStatistics = false,
      this.refreshRateMs = 0,
      this.rxBytes = 0,
      this.txBytes = 0})
      : super(DBusObjectPath('/org/freedesktop/NetworkManager/Devices/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties {
    var interfacesAndProperties_ = {
      'org.freedesktop.NetworkManager.Device': {
        'Autoconnect': DBusBoolean(autoconnect),
        'Capabilities': DBusUint32(capabilities),
        'DeviceType': DBusUint32(deviceType),
        'Dhcp4Config': dhcp4Config?.path ?? DBusObjectPath('/'),
        'Dhcp6Config': dhcp6Config?.path ?? DBusObjectPath('/'),
        'Driver': DBusString(driver),
        'DriverVersion': DBusString(driverVersion),
        'FirmwareMissing': DBusBoolean(firmwareMissing),
        'FirmwareVersion': DBusString(firmwareVersion),
        'HwAddress': DBusString(hwAddress),
        'Interface': DBusString(interface),
        'InterfaceFlags': DBusUint32(interfaceFlags),
        'Ip4Config': ip4Config?.path ?? DBusObjectPath('/'),
        'Ip4Connectivity': DBusUint32(ip4Connectivity),
        'Ip6Config': ip6Config?.path ?? DBusObjectPath('/'),
        'Ip6Connectivity': DBusUint32(ip6Connectivity),
        'IpInterface': DBusString(ipInterface),
        'Managed': DBusBoolean(managed),
        'Metered': DBusUint32(metered),
        'Mtu': DBusUint32(mtu),
        'NmPluginMissing': DBusBoolean(nmPluginMissing),
        'Path': DBusString(path_),
        'PhysicalPortId': DBusString(physicalPortId),
        'Real': DBusBoolean(real),
        'State': DBusUint32(state),
        'StateReason': DBusStruct([DBusUint32(state), DBusUint32(stateReason)]),
        'Udi': DBusString(udi)
      }
    };
    if (hasBluetooth) {
      interfacesAndProperties_[
          'org.freedesktop.NetworkManager.Device.Bluetooth'] = {
        'BtCapabilities': DBusUint32(btCapabilities),
        'Name': DBusString(name)
      };
    }
    if (hasBridge) {
      interfacesAndProperties_['org.freedesktop.NetworkManager.Device.Bridge'] =
          {'Slaves': DBusArray.objectPath(slaves.map((slave) => slave.path))};
    }
    if (hasGeneric) {
      interfacesAndProperties_[
          'org.freedesktop.NetworkManager.Device.Generic'] = {
        'TypeDescription': DBusString(typeDescription)
      };
    }
    if (hasTun) {
      interfacesAndProperties_['org.freedesktop.NetworkManager.Device.Tun'] = {
        'Group': DBusInt64(group),
        'Mode': DBusString(tunMode),
        'MultiQueue': DBusBoolean(multiQueue),
        'NoPi': DBusBoolean(noPi),
        'Owner': DBusInt64(owner),
        'VnetHdr': DBusBoolean(vnetHdr)
      };
    }
    if (hasVlan) {
      interfacesAndProperties_['org.freedesktop.NetworkManager.Device.Vlan'] = {
        'Parent': parent?.path ?? DBusObjectPath('/'),
        'VlanId': DBusUint32(vlanId)
      };
    }
    if (hasWired) {
      interfacesAndProperties_['org.freedesktop.NetworkManager.Device.Wired'] =
          {
        'S390Subchannels': DBusArray.string(s390Subchannels),
        'Speed': DBusUint32(speed),
        'PermHwAddress': DBusString(permHwAddress)
      };
    }
    if (hasWireless) {
      interfacesAndProperties_[
          'org.freedesktop.NetworkManager.Device.Wireless'] = {
        'AccessPoints': DBusArray.objectPath(
            accessPoints.map((accessPoint) => accessPoint.path)),
        'ActiveAccessPoint': activeAccessPoint?.path ?? DBusObjectPath('/'),
        'Bitrate': DBusUint32(bitrate),
        'LastScan': DBusInt64(lastScan),
        'Mode': DBusUint32(wirelessMode),
        'PermHwAddress': DBusString(permHwAddress),
        'WirelessCapabilities': DBusUint32(wirelessCapabilities)
      };
    }
    if (hasStatistics) {
      interfacesAndProperties_[
          'org.freedesktop.NetworkManager.Device.Statistics'] = {
        'RefreshRateMs': DBusUint32(refreshRateMs),
        'RxBytes': DBusUint64(rxBytes),
        'TxBytes': DBusUint64(txBytes)
      };
    }

    return interfacesAndProperties_;
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface == 'org.freedesktop.NetworkManager.Device') {
      if (name == 'Autoconnect') {
        autoconnect = (value as DBusBoolean).value;
        await emitPropertiesChanged('org.freedesktop.NetworkManager.Device',
            changedProperties: {'Autoconnect': DBusBoolean(autoconnect)});
        return DBusMethodSuccessResponse();
      } else if (name == 'Managed') {
        managed = (value as DBusBoolean).value;
        await emitPropertiesChanged('org.freedesktop.NetworkManager.Device',
            changedProperties: {'Managed': DBusBoolean(managed)});
        return DBusMethodSuccessResponse();
      } else {
        return DBusMethodErrorResponse.propertyReadOnly();
      }
    } else if (hasBluetooth &&
        interface == 'org.freedesktop.NetworkManager.Device.Bluetooth') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasBridge &&
        interface == 'org.freedesktop.NetworkManager.Device.Bridge') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasGeneric &&
        interface == 'org.freedesktop.NetworkManager.Device.Generic') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasTun &&
        interface == 'org.freedesktop.NetworkManager.Device.Tun') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasVlan &&
        interface == 'org.freedesktop.NetworkManager.Device.Vlan') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasWired &&
        interface == 'org.freedesktop.NetworkManager.Device.Wired') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasWireless &&
        interface == 'org.freedesktop.NetworkManager.Device.Wireless') {
      return DBusMethodErrorResponse.propertyReadOnly();
    } else if (hasStatistics &&
        interface == 'org.freedesktop.NetworkManager.Device.Statistics') {
      if (name == 'RefreshRateMs') {
        refreshRateMs = (value as DBusUint32).value;
        return DBusMethodSuccessResponse();
      } else {
        return DBusMethodErrorResponse.propertyReadOnly();
      }
    } else {
      return DBusMethodErrorResponse.unknownInterface();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.freedesktop.NetworkManager.Device') {
      switch (methodCall.name) {
        case 'Disconnect':
          disconnected = true;
          return DBusMethodSuccessResponse([]);
        case 'Delete':
          deleted = true;
          return DBusMethodSuccessResponse([]);
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    } else if (hasWireless &&
        methodCall.interface ==
            'org.freedesktop.NetworkManager.Device.Wireless') {
      switch (methodCall.name) {
        case 'RequestScan':
          var options = (methodCall.values[0] as DBusDict).mapStringVariant();
          scanRequested = true;
          scanOptions = options;
          return DBusMethodSuccessResponse([]);
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    } else {
      return DBusMethodErrorResponse.unknownInterface();
    }
  }
}

class MockNetworkManagerAccessPoint extends MockNetworkManagerObject {
  final int flags;
  final int frequency;
  final String hwAddress;
  final int lastSeen;
  final int maxBitrate;
  final int mode;
  final int rsnFlags;
  final List<int> ssid;
  final int strength;
  final int wpaFlags;

  MockNetworkManagerAccessPoint(int id,
      {this.flags = 0,
      this.frequency = 0,
      this.hwAddress = '',
      this.lastSeen = 0,
      this.maxBitrate = 0,
      this.mode = 0,
      this.rsnFlags = 0,
      this.ssid = const [],
      this.strength = 0,
      this.wpaFlags = 0})
      : super(
            DBusObjectPath('/org/freedesktop/NetworkManager/AccessPoints/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.AccessPoint': {
          'Flags': DBusUint32(flags),
          'Frequency': DBusUint32(frequency),
          'HwAddress': DBusString(hwAddress),
          'LastSeen': DBusInt32(lastSeen),
          'MaxBitrate': DBusUint32(maxBitrate),
          'Mode': DBusUint32(mode),
          'RsnFlags': DBusUint32(rsnFlags),
          'Ssid': DBusArray.byte(ssid),
          'Strength': DBusByte(strength),
          'WpaFlags': DBusUint32(wpaFlags)
        }
      };
}

class MockNetworkManagerIP4Config extends MockNetworkManagerObject {
  final List<Map<String, DBusValue>> addressData;
  final List<String> dnsOptions;
  final int dnsPriority;
  final List<String> domains;
  final String gateway;
  final List<Map<String, DBusValue>> nameserverData;
  final List<Map<String, DBusValue>> routeData;
  final List<String> searches;
  final List<String> winsServerData;

  MockNetworkManagerIP4Config(int id,
      {this.addressData = const [],
      this.dnsOptions = const [],
      this.dnsPriority = 0,
      this.domains = const [],
      this.gateway = '',
      this.nameserverData = const [],
      this.routeData = const [],
      this.searches = const [],
      this.winsServerData = const []})
      : super(DBusObjectPath('/org/freedesktop/NetworkManager/IP4Config/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.IP4Config': {
          'AddressData': DBusArray(DBusSignature('a{sv}'),
              addressData.map((data) => DBusDict.stringVariant(data))),
          'DnsOptions': DBusArray.string(dnsOptions),
          'DnsPriority': DBusInt32(dnsPriority),
          'Domains': DBusArray.string(domains),
          'Gateway': DBusString(gateway),
          'NameserverData': DBusArray(DBusSignature('a{sv}'),
              nameserverData.map((data) => DBusDict.stringVariant(data))),
          'RouteData': DBusArray(DBusSignature('a{sv}'),
              routeData.map((data) => DBusDict.stringVariant(data))),
          'Searches': DBusArray.string(searches),
          'WinsServerData': DBusArray.string(winsServerData)
        }
      };
}

class MockNetworkManagerIP6Config extends MockNetworkManagerObject {
  final List<Map<String, DBusValue>> addressData;
  final List<String> dnsOptions;
  final int dnsPriority;
  final List<String> domains;
  final String gateway;
  final List<Map<String, DBusValue>> nameserverData;
  final List<Map<String, DBusValue>> routeData;
  final List<String> searches;

  MockNetworkManagerIP6Config(int id,
      {this.addressData = const [],
      this.dnsOptions = const [],
      this.dnsPriority = 0,
      this.domains = const [],
      this.gateway = '',
      this.nameserverData = const [],
      this.routeData = const [],
      this.searches = const []})
      : super(DBusObjectPath('/org/freedesktop/NetworkManager/IP6Config/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.IP6Config': {
          'AddressData': DBusArray(DBusSignature('a{sv}'),
              addressData.map((data) => DBusDict.stringVariant(data))),
          'DnsOptions': DBusArray.string(dnsOptions),
          'DnsPriority': DBusInt32(dnsPriority),
          'Domains': DBusArray.string(domains),
          'Gateway': DBusString(gateway),
          'NameserverData': DBusArray(DBusSignature('a{sv}'),
              nameserverData.map((data) => DBusDict.stringVariant(data))),
          'RouteData': DBusArray(DBusSignature('a{sv}'),
              routeData.map((data) => DBusDict.stringVariant(data))),
          'Searches': DBusArray.string(searches)
        }
      };
}

class MockNetworkManagerDHCP4Config extends MockNetworkManagerObject {
  final Map<String, DBusValue> options;

  MockNetworkManagerDHCP4Config(int id, {this.options = const {}})
      : super(
            DBusObjectPath('/org/freedesktop/NetworkManager/DHCP4Config/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.DHCP4Config': {
          'Options': DBusDict.stringVariant(options)
        }
      };
}

class MockNetworkManagerDHCP6Config extends MockNetworkManagerObject {
  final Map<String, DBusValue> options;

  MockNetworkManagerDHCP6Config(int id, {this.options = const {}})
      : super(
            DBusObjectPath('/org/freedesktop/NetworkManager/DHCP6Config/$id'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.freedesktop.NetworkManager.DHCP6Config': {
          'Options': DBusDict.stringVariant(options)
        }
      };
}

class MockNetworkManagerServer extends DBusClient {
  final List<int> capabilities;
  final int connectivity;
  final bool connectivityCheckAvailable;
  bool connectivityCheckEnabled;
  final String connectivityCheckUri;
  final List<Map<String, DBusValue>> dnsConfiguration;
  final String dnsMode;
  final String dnsRcManager;
  final String hostname;
  int metered;
  final bool networkingEnabled;
  final bool settingsCanModify;
  bool startup;
  int state;
  final String version;
  final bool wimaxEnabled;
  final bool wimaxHardwareEnabled;
  bool wirelessEnabled;
  bool wirelessHardwareEnabled;
  bool wwanEnabled;
  bool wwanHardwareEnabled;

  final DBusObject _root;
  late final MockNetworkManagerManager _manager;
  late final MockNetworkManagerSettings _settings;
  late final MockNetworkManagerDnsManager _dnsManager;
  var _nextIp4ConfigId = 1;
  var _nextIp6ConfigId = 1;
  var _nextDhcp4ConfigId = 1;
  var _nextDhcp6ConfigId = 1;
  var _nextAccessPointId = 1;
  var _nextDeviceId = 1;
  var _nextActiveConnectionId = 1;
  var _nextSettingsId = 1;

  final allDevices = <MockNetworkManagerDevice>[];
  final devices = <MockNetworkManagerDevice>[];
  MockNetworkManagerActiveConnection? activatingConnection;
  final activeConnections = <MockNetworkManagerActiveConnection>[];
  final connectionSettings = <MockNetworkManagerConnectionSettings>[];

  MockNetworkManagerServer(DBusAddress clientAddress,
      {this.capabilities = const [],
      this.connectivity = 0,
      this.connectivityCheckAvailable = false,
      this.connectivityCheckEnabled = false,
      this.connectivityCheckUri = '',
      this.dnsConfiguration = const [],
      this.dnsMode = '',
      this.dnsRcManager = '',
      this.hostname = '',
      this.metered = 0,
      this.networkingEnabled = true,
      this.settingsCanModify = false,
      this.startup = true,
      this.state = 0,
      this.version = '',
      this.wimaxEnabled = false,
      this.wimaxHardwareEnabled = false,
      this.wirelessEnabled = false,
      this.wirelessHardwareEnabled = false,
      this.wwanEnabled = false,
      this.wwanHardwareEnabled = false})
      : _root = DBusObject(DBusObjectPath('/org/freedesktop'),
            isObjectManager: true),
        super(clientAddress) {
    _manager = MockNetworkManagerManager(this);
    _settings = MockNetworkManagerSettings(this);
    _dnsManager = MockNetworkManagerDnsManager(this);
  }

  Future<void> start() async {
    await requestName('org.freedesktop.NetworkManager');
    await registerObject(_root);
    await registerObject(_manager);
    await registerObject(_settings);
    await registerObject(_dnsManager);
  }

  Future<MockNetworkManagerIP4Config> addIp4Config({
    List<Map<String, DBusValue>> addressData = const [],
    List<String> dnsOptions = const [],
    int dnsPriority = 0,
    List<String> domains = const [],
    String gateway = '',
    List<Map<String, DBusValue>> nameserverData = const [],
    List<Map<String, DBusValue>> routeData = const [],
    List<String> searches = const [],
    List<String> winsServerData = const [],
  }) async {
    var config = MockNetworkManagerIP4Config(_nextIp4ConfigId,
        addressData: addressData,
        dnsOptions: dnsOptions,
        dnsPriority: dnsPriority,
        domains: domains,
        gateway: gateway,
        nameserverData: nameserverData,
        routeData: routeData,
        searches: searches,
        winsServerData: winsServerData);
    _nextIp4ConfigId++;
    await registerObject(config);
    return config;
  }

  Future<MockNetworkManagerIP6Config> addIp6Config(
      {List<Map<String, DBusValue>> addressData = const [],
      List<String> dnsOptions = const [],
      int dnsPriority = 0,
      List<String> domains = const [],
      String gateway = '',
      List<Map<String, DBusValue>> nameserverData = const [],
      List<Map<String, DBusValue>> routeData = const [],
      List<String> searches = const []}) async {
    var config = MockNetworkManagerIP6Config(_nextIp6ConfigId,
        addressData: addressData,
        dnsOptions: dnsOptions,
        dnsPriority: dnsPriority,
        domains: domains,
        gateway: gateway,
        nameserverData: nameserverData,
        routeData: routeData,
        searches: searches);
    _nextIp6ConfigId++;
    await registerObject(config);
    return config;
  }

  Future<MockNetworkManagerDHCP4Config> addDhcp4Config(
      {Map<String, DBusValue> options = const {}}) async {
    var config =
        MockNetworkManagerDHCP4Config(_nextDhcp4ConfigId, options: options);
    _nextDhcp4ConfigId++;
    await registerObject(config);
    return config;
  }

  Future<MockNetworkManagerDHCP6Config> addDhcp6Config(
      {Map<String, DBusValue> options = const {}}) async {
    var config =
        MockNetworkManagerDHCP6Config(_nextDhcp6ConfigId, options: options);
    _nextDhcp6ConfigId++;
    await registerObject(config);
    return config;
  }

  Future<MockNetworkManagerAccessPoint> addAccessPoint(
      {int flags = 0,
      int frequency = 0,
      String hwAddress = '',
      int lastSeen = 0,
      int maxBitrate = 0,
      int mode = 0,
      int rsnFlags = 0,
      List<int> ssid = const [],
      int strength = 0,
      int wpaFlags = 0}) async {
    var accessPoint = MockNetworkManagerAccessPoint(_nextAccessPointId,
        flags: flags,
        frequency: frequency,
        hwAddress: hwAddress,
        lastSeen: lastSeen,
        maxBitrate: maxBitrate,
        mode: mode,
        rsnFlags: rsnFlags,
        ssid: ssid,
        strength: strength,
        wpaFlags: wpaFlags);
    _nextAccessPointId++;
    await registerObject(accessPoint);
    return accessPoint;
  }

  Future<MockNetworkManagerConnectionSettings> addConnectionSettings(
      {String filename = '',
      int flags = 0,
      Map<String, Map<String, DBusValue>>? secrets,
      Map<String, Map<String, DBusValue>>? settings,
      bool unsaved = false}) async {
    var s = MockNetworkManagerConnectionSettings(_nextSettingsId,
        filename: filename,
        flags: flags,
        secrets: secrets,
        settings: settings,
        unsaved: unsaved);
    _nextSettingsId++;
    await registerObject(s);
    connectionSettings.add(s);
    return s;
  }

  Future<MockNetworkManagerDevice> addDevice(
      {bool autoconnect = false,
      int capabilities = 0,
      int deviceType = 0,
      MockNetworkManagerDHCP4Config? dhcp4Config,
      MockNetworkManagerDHCP6Config? dhcp6Config,
      String driver = '',
      String driverVersion = '',
      bool firmwareMissing = false,
      String firmwareVersion = '',
      String hwAddress = '',
      String interface = '',
      int interfaceFlags = 0,
      MockNetworkManagerIP4Config? ip4Config,
      int ip4Connectivity = 0,
      MockNetworkManagerIP6Config? ip6Config,
      int ip6Connectivity = 0,
      String ipInterface = '',
      bool managed = false,
      int metered = 0,
      int mtu = 0,
      bool nmPluginMissing = false,
      String path = '',
      String physicalPortId = '',
      bool real = true,
      int state = 0,
      int stateReason = 0,
      String udi = '',
      bool hasBluetooth = false,
      int btCapabilities = 0,
      String name = '',
      bool hasBridge = false,
      List<MockNetworkManagerDevice> slaves = const [],
      bool hasGeneric = false,
      String typeDescription = '',
      bool hasTun = false,
      int group = -1,
      bool multiQueue = false,
      bool noPi = false,
      int owner = -1,
      String tunMode = '',
      bool vnetHdr = false,
      bool hasVlan = false,
      MockNetworkManagerDevice? parent,
      int vlanId = 0,
      bool hasWired = false,
      int speed = 0,
      List<String> s390Subchannels = const [],
      bool hasWireless = false,
      List<MockNetworkManagerAccessPoint> accessPoints = const [],
      MockNetworkManagerAccessPoint? activeAccessPoint,
      int bitrate = 0,
      int lastScan = 0,
      int wirelessMode = 0,
      String permHwAddress = '',
      int wirelessCapabilities = 0,
      bool hasStatistics = false,
      int refreshRateMs = 0,
      int rxBytes = 0,
      int txBytes = 0}) async {
    var device = MockNetworkManagerDevice(_nextDeviceId,
        autoconnect: autoconnect,
        capabilities: capabilities,
        deviceType: deviceType,
        dhcp4Config: dhcp4Config,
        dhcp6Config: dhcp6Config,
        driver: driver,
        driverVersion: driverVersion,
        firmwareMissing: firmwareMissing,
        firmwareVersion: firmwareVersion,
        hwAddress: hwAddress,
        interface: interface,
        interfaceFlags: interfaceFlags,
        ip4Config: ip4Config,
        ip4Connectivity: ip4Connectivity,
        ip6Config: ip6Config,
        ip6Connectivity: ip6Connectivity,
        ipInterface: ipInterface,
        managed: managed,
        metered: metered,
        mtu: mtu,
        nmPluginMissing: nmPluginMissing,
        path_: path,
        physicalPortId: physicalPortId,
        real: real,
        state: state,
        stateReason: stateReason,
        udi: udi,
        hasBluetooth: hasBluetooth,
        btCapabilities: btCapabilities,
        name: name,
        hasBridge: hasBridge,
        slaves: slaves,
        hasGeneric: hasGeneric,
        typeDescription: typeDescription,
        hasTun: hasTun,
        group: group,
        multiQueue: multiQueue,
        noPi: noPi,
        owner: owner,
        tunMode: tunMode,
        vnetHdr: vnetHdr,
        hasVlan: hasVlan,
        parent: parent,
        vlanId: vlanId,
        hasWired: hasWired,
        s390Subchannels: s390Subchannels,
        speed: speed,
        hasWireless: hasWireless,
        accessPoints: accessPoints,
        activeAccessPoint: activeAccessPoint,
        bitrate: bitrate,
        lastScan: lastScan,
        wirelessMode: wirelessMode,
        permHwAddress: permHwAddress,
        wirelessCapabilities: wirelessCapabilities,
        hasStatistics: hasStatistics,
        refreshRateMs: refreshRateMs,
        rxBytes: rxBytes,
        txBytes: txBytes);
    _nextDeviceId++;
    await registerObject(device);
    allDevices.add(device);
    devices.add(device);
    return device;
  }

  Future<void> removeDevice(MockNetworkManagerDevice device) async {
    await unregisterObject(device);
  }

  Future<MockNetworkManagerActiveConnection> addActiveConnection(
      {bool default4 = false,
      bool default6 = false,
      List<MockNetworkManagerDevice> devices = const [],
      MockNetworkManagerDHCP4Config? dhcp4Config,
      MockNetworkManagerDHCP6Config? dhcp6Config,
      String id = '',
      MockNetworkManagerIP4Config? ip4Config,
      MockNetworkManagerIP6Config? ip6Config,
      int state = 0,
      int stateFlags = 0,
      String type = '',
      String uuid = '',
      bool vpn = false}) async {
    var activeConnection = MockNetworkManagerActiveConnection(
        _nextActiveConnectionId,
        default4: default4,
        default6: default6,
        devices: devices,
        dhcp4Config: dhcp4Config,
        dhcp6Config: dhcp6Config,
        id: id,
        ip4Config: ip4Config,
        ip6Config: ip6Config,
        state: state,
        stateFlags: stateFlags,
        type: type,
        uuid: uuid,
        vpn: vpn);
    _nextActiveConnectionId++;
    await registerObject(activeConnection);
    activeConnections.add(activeConnection);
    await emitActiveConnectionsChanged();
    return activeConnection;
  }

  Future<void> removeActiveConnection(
      MockNetworkManagerActiveConnection connection) async {
    await unregisterObject(connection);
    activeConnections.remove(connection);
    await emitActiveConnectionsChanged();
  }

  Future<void> emitActiveConnectionsChanged() async {
    await _manager.emitPropertiesChanged(
      'org.freedesktop.NetworkManager',
      changedProperties: {
        'ActiveConnections': DBusArray.objectPath(
          activeConnections.map((connection) => connection.path),
        ),
      },
    );
  }

  Future<void> completeStartup() async {
    if (!startup) {
      return;
    }
    startup = false;
    await _manager.emitPropertiesChanged('org.freedesktop.NetworkManager',
        changedProperties: {'Startup': DBusBoolean(startup)});
  }

  Future<void> setMetered(int metered) async {
    if (this.metered == metered) {
      return;
    }
    this.metered = metered;
    await _manager.emitPropertiesChanged('org.freedesktop.NetworkManager',
        changedProperties: {'Metered': DBusUint32(this.metered)});
  }

  Future<void> setState(int state) async {
    if (this.state == state) {
      return;
    }
    this.state = state;
    await _manager.emitPropertiesChanged('org.freedesktop.NetworkManager',
        changedProperties: {'State': DBusUint32(this.state)});
  }

  Future<void> setWirelessHardwareEnabled(bool enabled) async {
    if (wirelessHardwareEnabled == enabled) {
      return;
    }
    wirelessHardwareEnabled = enabled;
    await _manager.emitPropertiesChanged('org.freedesktop.NetworkManager',
        changedProperties: {
          'WirelessHardwareEnabled': DBusBoolean(wirelessHardwareEnabled)
        });
  }

  Future<void> setWwanHardwareEnabled(bool enabled) async {
    if (wwanHardwareEnabled == enabled) {
      return;
    }
    wwanHardwareEnabled = enabled;
    await _manager.emitPropertiesChanged('org.freedesktop.NetworkManager',
        changedProperties: {
          'WwanHardwareEnabled': DBusBoolean(wwanHardwareEnabled)
        });
  }
}

void main() {
  test('version', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, version: '1.2.3');
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.version, equals('1.2.3'));
  });

  test('startup', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.startup, isTrue);
    await nm.completeStartup();
    await expectLater(client.propertiesChanged, emits(['Startup']));
    expect(client.startup, isFalse);
  });

  test('state', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, state: 10);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.state, equals(NetworkManagerState.asleep));
    await nm.setState(20);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.disconnected));
    await nm.setState(30);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.disconnecting));
    await nm.setState(40);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.connecting));
    await nm.setState(50);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.connectedLocal));
    await nm.setState(60);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.connectedSite));
    await nm.setState(70);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.connectedGlobal));
    await nm.setState(0);
    await expectLater(client.propertiesChanged, emits(['State']));
    expect(client.state, equals(NetworkManagerState.unknown));
  });

  test('networking enabled', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, networkingEnabled: true);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.networkingEnabled, isTrue);
  });

  test('metered', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, metered: 1);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.metered, equals(NetworkManagerMetered.yes));
    await nm.setMetered(2);
    await expectLater(client.propertiesChanged, emits(['Metered']));
    expect(client.metered, equals(NetworkManagerMetered.no));
    await nm.setMetered(3);
    await expectLater(client.propertiesChanged, emits(['Metered']));
    expect(client.metered, equals(NetworkManagerMetered.guessYes));
    await nm.setMetered(4);
    await expectLater(client.propertiesChanged, emits(['Metered']));
    expect(client.metered, equals(NetworkManagerMetered.guessNo));
    await nm.setMetered(999);
    await expectLater(client.propertiesChanged, emits(['Metered']));
    expect(client.metered, equals(NetworkManagerMetered.unknown));
  });

  test('connectivity', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress,
        connectivityCheckAvailable: true,
        connectivityCheckEnabled: true,
        connectivityCheckUri: 'http://example.com',
        connectivity: 4);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.connectivityCheckAvailable, isTrue);
    expect(client.connectivityCheckEnabled, isTrue);
    expect(client.connectivityCheckUri, equals('http://example.com'));
    expect(client.connectivity, NetworkManagerConnectivityState.full);
  });

  test('connectivity - enable', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(nm.connectivityCheckEnabled, isFalse);
    expect(client.connectivityCheckEnabled, isFalse);
    await client.setConnectivityCheckEnabled(true);
    expect(nm.connectivityCheckEnabled, isTrue);
    expect(client.connectivityCheckEnabled, isTrue);
  });

  test('wireless - enable', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(nm.wirelessEnabled, isFalse);
    expect(client.wirelessEnabled, isFalse);
    await client.setWirelessEnabled(true);
    expect(nm.wirelessEnabled, isTrue);
    expect(client.wirelessEnabled, isTrue);

    expect(nm.wwanEnabled, isFalse);
    expect(nm.wwanEnabled, isFalse);
    await client.setWwanEnabled(true);
    expect(nm.wwanEnabled, isTrue);
    expect(client.wwanEnabled, isTrue);
  });

  test('wireless - hardware enable', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.wirelessHardwareEnabled, isFalse);
    await nm.setWirelessHardwareEnabled(true);
    await expectLater(
        client.propertiesChanged, emits(['WirelessHardwareEnabled']));
    expect(client.wirelessHardwareEnabled, isTrue);

    expect(client.wwanHardwareEnabled, isFalse);
    await nm.setWwanHardwareEnabled(true);
    await expectLater(client.propertiesChanged, emits(['WwanHardwareEnabled']));
    expect(client.wwanHardwareEnabled, isTrue);
  });

  test('hostname', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, hostname: 'HOSTNAME');
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.hostname, equals('HOSTNAME'));
  });

  test('no settings', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, isEmpty);
  });

  test('settings', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress, settingsCanModify: true);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addConnectionSettings(
        filename:
            '/etc/NetworkManager/system-connections/Ethernet.nmconnection');
    await nm.addConnectionSettings(
        filename: '/etc/NetworkManager/system-connections/accesspoint1');
    await nm.addConnectionSettings(
        filename: '/etc/NetworkManager/system-connections/accesspoint2',
        unsaved: true,
        flags: 0xf);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.canModify, isTrue);
    expect(client.settings.connections, hasLength(3));
    expect(client.settings.connections[0].filename,
        equals('/etc/NetworkManager/system-connections/Ethernet.nmconnection'));
    expect(client.settings.connections[1].filename,
        equals('/etc/NetworkManager/system-connections/accesspoint1'));
    expect(client.settings.connections[2].filename,
        equals('/etc/NetworkManager/system-connections/accesspoint2'));
    expect(client.settings.connections[2].unsaved, isTrue);
    expect(
        client.settings.connections[2].flags,
        equals({
          NetworkManagerConnectionFlag.unsaved,
          NetworkManagerConnectionFlag.networkManagerGenerated,
          NetworkManagerConnectionFlag.volatile,
          NetworkManagerConnectionFlag.external
        }));
  });

  test('settings save', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var s = await nm.addConnectionSettings();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(s.saved, isFalse);
    await connection.save();
    expect(s.saved, isTrue);
  });

  test('settings delete', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var s = await nm.addConnectionSettings();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(s.deleted, isFalse);
    await connection.delete();
    expect(s.deleted, isTrue);
  });

  test('settings get', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addConnectionSettings(settings: {
      'group1': {'setting1a': DBusString('value')},
      'group2': {'setting2a': DBusUint32(42)}
    });

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(
        await connection.getSettings(),
        equals({
          'group1': {'setting1a': DBusString('value')},
          'group2': {'setting2a': DBusUint32(42)}
        }));
  });

  test('settings get secrets', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addConnectionSettings(secrets: {
      'group1': {'secret1a': DBusString('value')},
      'group2': {'secret2a': DBusUint32(42)}
    });

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(
        await connection.getSecrets(),
        equals({
          'group1': {'secret1a': DBusString('value')},
          'group2': {'secret2a': DBusUint32(42)}
        }));
  });

  test('settings clear secrets', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var s = await nm.addConnectionSettings(secrets: {
      'group1': {'secret1a': DBusString('value')},
      'group2': {'secret2a': DBusUint32(42)}
    });

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    await connection.clearSecrets();
    expect(s.secrets, equals({}));
  });

  test('settings update', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var s = await nm.addConnectionSettings(settings: {
      'group1': {'setting1a': DBusString('value')},
      'group2': {'setting2a': DBusUint32(42)}
    });

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(s.saved, isFalse);
    await connection.update({
      'group3': {'setting3a': DBusUint32(123)}
    });
    expect(
        s.settings,
        equals({
          'group3': {'setting3a': DBusUint32(123)}
        }));
    expect(s.saved, isTrue);
  });

  test('settings update unsaved', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var s = await nm.addConnectionSettings(settings: {
      'group1': {'setting1a': DBusString('value')},
      'group2': {'setting2a': DBusUint32(42)}
    });

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.settings.connections, hasLength(1));
    var connection = client.settings.connections[0];
    expect(s.saved, isFalse);
    await connection.updateUnsaved({
      'group3': {'setting3a': DBusUint32(123)}
    });
    expect(
        s.settings,
        equals({
          'group3': {'setting3a': DBusUint32(123)}
        }));
    expect(s.saved, isFalse);
  });

  test('DNS manager', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress,
        dnsMode: 'systemd-resolved',
        dnsRcManager: 'unmanaged',
        dnsConfiguration: [
          {
            'nameservers': DBusArray.string(['8.8.8.8']),
            'interface': DBusString('enp3s0'),
            'priority': DBusUint32(100),
            'vpn': DBusBoolean(false)
          },
          {
            'nameservers': DBusArray.string(['8.8.8.8']),
            'interface': DBusString('wlp5s0'),
            'priority': DBusUint32(100),
            'vpn': DBusBoolean(false)
          }
        ]);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.dnsManager.mode, equals('systemd-resolved'));
    expect(client.dnsManager.rcManager, equals('unmanaged'));
    expect(
        client.dnsManager.configuration,
        equals([
          {
            'nameservers': ['8.8.8.8'],
            'interface': 'enp3s0',
            'priority': 100,
            'vpn': false
          },
          {
            'nameservers': ['8.8.8.8'],
            'interface': 'wlp5s0',
            'priority': 100,
            'vpn': false
          }
        ]));
  });

  test('no devices', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, isEmpty);
  });

  test('devices', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:02');
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:03');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(3));
    expect(client.devices[0].hwAddress, equals('DE:71:CE:00:00:01'));
    expect(client.devices[1].hwAddress, equals('DE:71:CE:00:00:02'));
    expect(client.devices[2].hwAddress, equals('DE:71:CE:00:00:03'));
  });

  test('all devices', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:02');
    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:03');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.allDevices, hasLength(3));
    expect(client.allDevices[0].hwAddress, equals('DE:71:CE:00:00:01'));
    expect(client.allDevices[1].hwAddress, equals('DE:71:CE:00:00:02'));
    expect(client.allDevices[2].hwAddress, equals('DE:71:CE:00:00:03'));
  });

  test('device added', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    client.deviceAdded.listen(expectAsync1((device) {
      expect(device.hwAddress, equals('DE:71:CE:00:00:01'));
    }));

    await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
  });

  test('device removed', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();
    var d = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');

    client.deviceRemoved.listen(expectAsync1((device) {
      expect(device.hwAddress, equals('DE:71:CE:00:00:01'));
    }));

    await nm.removeDevice(d);
  });

  test('device properties', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        autoconnect: true,
        capabilities: 0xf,
        deviceType: 1,
        driver: 'DRIVER',
        driverVersion: 'DRIVER-VERSION',
        firmwareMissing: true,
        firmwareVersion: 'FIRMWARE-VERSION',
        hwAddress: 'DE:71:CE:00:00:01',
        interface: 'INTERFACE',
        interfaceFlags: 0x10003,
        ip4Connectivity: 4,
        ip6Connectivity: 4,
        ipInterface: 'IP-INTERFACE',
        managed: true,
        metered: 1,
        mtu: 1500,
        nmPluginMissing: true,
        path: '/PATH',
        physicalPortId: 'PHYSICAL-PORT-ID',
        real: true,
        state: 100,
        stateReason: 0,
        udi: 'UDI');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.bluetooth, isNull);
    expect(device.bridge, isNull);
    expect(device.generic, isNull);
    expect(device.statistics, isNull);
    expect(device.tun, isNull);
    expect(device.wired, isNull);
    expect(device.wireless, isNull);
    expect(device.vlan, isNull);
    expect(device.autoconnect, isTrue);
    expect(
        device.capabilities,
        equals({
          NetworkManagerDeviceCapability.networkManagerSupported,
          NetworkManagerDeviceCapability.carrierDetect,
          NetworkManagerDeviceCapability.isSoftware,
          NetworkManagerDeviceCapability.singleRootIOVirtualization
        }));
    expect(device.deviceType, equals(NetworkManagerDeviceType.ethernet));
    expect(device.dhcp4Config, isNull);
    expect(device.dhcp6Config, isNull);
    expect(device.driver, equals('DRIVER'));
    expect(device.driverVersion, equals('DRIVER-VERSION'));
    expect(device.firmwareMissing, isTrue);
    expect(device.firmwareVersion, equals('FIRMWARE-VERSION'));
    expect(device.hwAddress, equals('DE:71:CE:00:00:01'));
    expect(device.interface, equals('INTERFACE'));
    expect(
        device.interfaceFlags,
        equals({
          NetworkManagerDeviceInterfaceFlag.up,
          NetworkManagerDeviceInterfaceFlag.lowerUp,
          NetworkManagerDeviceInterfaceFlag.carrier
        }));
    expect(
        device.ip4Connectivity, equals(NetworkManagerConnectivityState.full));
    expect(
        device.ip6Connectivity, equals(NetworkManagerConnectivityState.full));
    expect(device.ip4Config, isNull);
    expect(device.ip6Config, isNull);
    expect(device.ipInterface, equals('IP-INTERFACE'));
    expect(device.managed, isTrue);
    expect(device.metered, equals(NetworkManagerMetered.yes));
    expect(device.mtu, equals(1500));
    expect(device.nmPluginMissing, isTrue);
    expect(device.path, equals('/PATH'));
    expect(device.physicalPortId, equals('PHYSICAL-PORT-ID'));
    expect(device.real, isTrue);
    expect(device.state, equals(NetworkManagerDeviceState.activated));
    expect(
        device.stateReason.state, equals(NetworkManagerDeviceState.activated));
    expect(device.stateReason.reason,
        equals(NetworkManagerDeviceStateReason.none));
    expect(device.udi, equals('UDI'));
  });

  test('device - set managed', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(managed: true);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.managed, isTrue);
    await device.setManaged(false);
    expect(device.managed, isFalse);
  });

  test('device - set autoconnect', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(autoconnect: true);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.autoconnect, isTrue);
    await device.setAutoconnect(false);
    expect(device.autoconnect, isFalse);
  });

  test('device ip config', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var ip4c = await nm.addIp4Config(
        addressData: [
          {'address': DBusString('192.168.0.2'), 'prefix': DBusUint32(16)},
          {'address': DBusString('10.0.0.2'), 'prefix': DBusUint32(8)}
        ],
        dnsOptions: ['option4a', 'option4b'],
        dnsPriority: 42,
        domains: ['domain4a', 'domain4b'],
        gateway: '192.168.0.1',
        nameserverData: [
          {'address': DBusString('8.8.8.8')},
          {'address': DBusString('8.8.4.4')}
        ],
        routeData: [
          {'dest': DBusString('192.168.0.0'), 'prefix': DBusUint32(16)},
          {'dest': DBusString('10.0.0.0'), 'prefix': DBusUint32(8)}
        ],
        searches: ['search4a', 'search4b'],
        winsServerData: ['wins1', 'wins2']);
    var ip6c = await nm.addIp6Config(
        addressData: [
          {
            'address': DBusString('2001:0db8:85a3:0000:0000:8a2e:0370:7334'),
            'prefix': DBusUint32(32)
          },
        ],
        dnsOptions: ['option6a', 'option6b'],
        dnsPriority: 128,
        domains: ['domain6a', 'domain6b'],
        gateway: '2001:0db8:85a3:0000:0000:8a2e:0370:1234',
        nameserverData: [
          {'address': DBusString('2001:4860:4860::8888')},
          {'address': DBusString('2001:4860:4860::8844')}
        ],
        routeData: [
          {
            'dest': DBusString('fe80::'),
            'prefix': DBusUint32(64),
            'metric': DBusUint32(600)
          }
        ],
        searches: ['search6a', 'search6b']);
    await nm.addDevice(ip4Config: ip4c, ip6Config: ip6c);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.ip4Config, isNotNull);
    var ip4Config = device.ip4Config!;
    expect(
        ip4Config.addressData,
        equals([
          {'address': '192.168.0.2', 'prefix': 16},
          {'address': '10.0.0.2', 'prefix': 8}
        ]));
    expect(ip4Config.dnsPriority, equals(42));
    expect(ip4Config.dnsOptions, equals(['option4a', 'option4b']));
    expect(ip4Config.domains, equals(['domain4a', 'domain4b']));
    expect(ip4Config.gateway, equals('192.168.0.1'));
    expect(
        ip4Config.nameserverData,
        equals([
          {'address': '8.8.8.8'},
          {'address': '8.8.4.4'}
        ]));
    expect(
        ip4Config.routeData,
        equals([
          {'dest': '192.168.0.0', 'prefix': 16},
          {'dest': '10.0.0.0', 'prefix': 8}
        ]));
    expect(ip4Config.searches, equals(['search4a', 'search4b']));
    expect(ip4Config.winsServerData, equals(['wins1', 'wins2']));
    expect(device.ip6Config, isNotNull);
    var ip6Config = device.ip6Config!;
    expect(
        ip6Config.addressData,
        equals([
          {'address': '2001:0db8:85a3:0000:0000:8a2e:0370:7334', 'prefix': 32},
        ]));
    expect(ip6Config.dnsPriority, equals(128));
    expect(ip6Config.dnsOptions, equals(['option6a', 'option6b']));
    expect(ip6Config.domains, equals(['domain6a', 'domain6b']));
    expect(
        ip6Config.gateway, equals('2001:0db8:85a3:0000:0000:8a2e:0370:1234'));
    expect(
        ip6Config.nameserverData,
        equals([
          {'address': '2001:4860:4860::8888'},
          {'address': '2001:4860:4860::8844'}
        ]));
    expect(
        ip6Config.routeData,
        equals([
          {'dest': 'fe80::', 'prefix': 64, 'metric': 600},
        ]));
    expect(ip6Config.searches, equals(['search6a', 'search6b']));
  });

  test('device dhcp config', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var dhcp4c = await nm.addDhcp4Config(options: {
      'option4a': DBusString('192.168.0.1'),
      'option4b': DBusUint32(42)
    });
    var dhcp6c = await nm.addDhcp6Config(options: {
      'option6a': DBusString('2001:0db8:85a3:0000:0000:8a2e:0370:1234'),
      'option6b': DBusUint32(42)
    });
    await nm.addDevice(dhcp4Config: dhcp4c, dhcp6Config: dhcp6c);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.dhcp4Config, isNotNull);
    expect(device.dhcp4Config!.options,
        equals({'option4a': '192.168.0.1', 'option4b': 42}));
    expect(device.dhcp6Config, isNotNull);
    expect(
        device.dhcp6Config!.options,
        equals({
          'option6a': '2001:0db8:85a3:0000:0000:8a2e:0370:1234',
          'option6b': 42
        }));
  });

  test('device disconnect', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d = await nm.addDevice();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(d.disconnected, isFalse);
    await device.disconnect();
    expect(d.disconnected, isTrue);
  });

  test('device delete', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d = await nm.addDevice();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(d.deleted, isFalse);
    await device.delete();
    expect(d.deleted, isTrue);
  });

  test('bluetooth device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        deviceType: 5, hasBluetooth: true, btCapabilities: 0x3, name: 'NAME');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.deviceType, equals(NetworkManagerDeviceType.bluetooth));
    expect(device.bluetooth, isNotNull);
    expect(
        device.bluetooth?.btCapabilities,
        equals({
          NetworkManagerBluetoothCapability.dun,
          NetworkManagerBluetoothCapability.tun
        }));
    expect(device.bluetooth?.name, equals('NAME'));
  });

  test('bridge device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d1 = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
    var d2 = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:02');
    await nm.addDevice(deviceType: 13, hasBridge: true, slaves: [d1, d2]);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(3));
    var device = client.devices[2];
    expect(device.deviceType, equals(NetworkManagerDeviceType.bridge));
    expect(device.bridge, isNotNull);
    expect(device.bridge!.slaves, hasLength(2));
    expect(device.bridge!.slaves[0].hwAddress, equals('DE:71:CE:00:00:01'));
    expect(device.bridge!.slaves[1].hwAddress, equals('DE:71:CE:00:00:02'));
  });

  test('generic device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        deviceType: 14, hasGeneric: true, typeDescription: 'TYPE-DESCRIPTION');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.deviceType, equals(NetworkManagerDeviceType.generic));
    expect(device.generic, isNotNull);
    expect(device.generic!.typeDescription, equals('TYPE-DESCRIPTION'));
  });

  test('tun device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        deviceType: 16,
        hasTun: true,
        owner: 1000,
        group: 1001,
        tunMode: 'tap',
        multiQueue: true,
        noPi: true,
        vnetHdr: true);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.deviceType, equals(NetworkManagerDeviceType.tun));
    expect(device.tun, isNotNull);
    expect(device.tun!.owner, equals(1000));
    expect(device.tun!.group, equals(1001));
    expect(device.tun!.mode, equals(NetworkManagerTunnelMode.tap));
    expect(device.tun!.multiQueue, isTrue);
    expect(device.tun!.noPi, isTrue);
    expect(device.tun!.vnetHdr, isTrue);
  });

  test('vlan device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
    await nm.addDevice(deviceType: 11, hasVlan: true, parent: d, vlanId: 42);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(2));
    var device = client.devices[1];
    expect(device.deviceType, equals(NetworkManagerDeviceType.vlan));
    expect(device.vlan, isNotNull);
    expect(device.vlan!.vlanId, equals(42));
    expect(device.vlan!.parent.hwAddress, equals('DE:71:CE:00:00:01'));
  });

  test('ethernet device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        deviceType: 1,
        hasWired: true,
        permHwAddress: 'DE:71:CE:00:00:01',
        speed: 100);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.deviceType, equals(NetworkManagerDeviceType.ethernet));
    expect(device.wired, isNotNull);
    expect(device.wired!.permHwAddress, equals('DE:71:CE:00:00:01'));
    expect(device.wired!.speed, equals(100));
  });

  test('wifi device', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var ap1 = await nm.addAccessPoint(
        flags: 0xf,
        frequency: 5745,
        hwAddress: 'AC:CE:55:00:00:01',
        lastSeen: 123456789,
        maxBitrate: 270000,
        mode: 2,
        rsnFlags: 0x188,
        ssid: [104, 101, 108, 108, 111],
        strength: 59,
        wpaFlags: 0x144);
    var ap2 = await nm.addAccessPoint(hwAddress: 'AC:CE:55:00:00:02');
    var ap3 = await nm.addAccessPoint(hwAddress: 'AC:CE:55:00:00:03');
    await nm.addDevice(
        deviceType: 2,
        hasWireless: true,
        accessPoints: [ap1, ap2, ap3],
        activeAccessPoint: ap1,
        bitrate: 135000,
        lastScan: 123456789,
        wirelessMode: 2,
        permHwAddress: 'DE:71:CE:00:00:01',
        wirelessCapabilities: 0x1027);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.deviceType, equals(NetworkManagerDeviceType.wifi));
    expect(device.wireless, isNotNull);
    expect(device.wireless!.accessPoints, hasLength(3));
    expect(device.wireless!.accessPoints[0].hwAddress,
        equals('AC:CE:55:00:00:01'));
    expect(device.wireless!.accessPoints[1].hwAddress,
        equals('AC:CE:55:00:00:02'));
    expect(device.wireless!.accessPoints[2].hwAddress,
        equals('AC:CE:55:00:00:03'));
    expect(device.wireless!.activeAccessPoint, isNotNull);
    var ap = device.wireless!.activeAccessPoint!;
    expect(
        ap.flags,
        equals({
          NetworkManagerWifiAccessPointFlag.privacy,
          NetworkManagerWifiAccessPointFlag.wps,
          NetworkManagerWifiAccessPointFlag.wpsPushButton,
          NetworkManagerWifiAccessPointFlag.wpsPin
        }));
    expect(ap.frequency, equals(5745));
    expect(ap.hwAddress, equals('AC:CE:55:00:00:01'));
    expect(ap.lastSeen, equals(123456789));
    expect(ap.maxBitrate, equals(270000));
    expect(ap.mode, equals(NetworkManagerWifiMode.infra));
    expect(
        ap.rsnFlags,
        equals({
          NetworkManagerWifiAccessPointSecurityFlag.pairCcmp,
          NetworkManagerWifiAccessPointSecurityFlag.groupCcmp,
          NetworkManagerWifiAccessPointSecurityFlag.keyManagementPsk
        }));
    expect(ap.ssid, equals([104, 101, 108, 108, 111]));
    expect(ap.strength, equals(59));
    expect(
        ap.wpaFlags,
        equals({
          NetworkManagerWifiAccessPointSecurityFlag.pairTkip,
          NetworkManagerWifiAccessPointSecurityFlag.groupTkip,
          NetworkManagerWifiAccessPointSecurityFlag.keyManagementPsk
        }));
    expect(device.wireless!.bitrate, equals(135000));
    expect(device.wireless!.lastScan, equals(123456789));
    expect(device.wireless!.mode, equals(NetworkManagerWifiMode.infra));
    expect(device.wireless!.permHwAddress, equals('DE:71:CE:00:00:01'));
    expect(
        device.wireless!.wirelessCapabilities,
        equals({
          NetworkManagerDeviceWifiCapability.cipherWep40,
          NetworkManagerDeviceWifiCapability.cipherWep104,
          NetworkManagerDeviceWifiCapability.cipherTkip,
          NetworkManagerDeviceWifiCapability.rsn,
          NetworkManagerDeviceWifiCapability.mesh
        }));
  });

  test('wifi modes', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(hasWireless: true, wirelessMode: 1);
    await nm.addDevice(hasWireless: true, wirelessMode: 2);
    await nm.addDevice(hasWireless: true, wirelessMode: 3);
    await nm.addDevice(hasWireless: true, wirelessMode: 4);
    await nm.addDevice(hasWireless: true, wirelessMode: 999);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(5));
    expect(
        client.devices[0].wireless!.mode, equals(NetworkManagerWifiMode.adhoc));
    expect(
        client.devices[1].wireless!.mode, equals(NetworkManagerWifiMode.infra));
    expect(client.devices[2].wireless!.mode, equals(NetworkManagerWifiMode.ap));
    expect(
        client.devices[3].wireless!.mode, equals(NetworkManagerWifiMode.mesh));
    expect(client.devices[4].wireless!.mode,
        equals(NetworkManagerWifiMode.unknown));
  });

  test('wifi security flags', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var ap1 = await nm.addAccessPoint(wpaFlags: 0x0001);
    var ap2 = await nm.addAccessPoint(wpaFlags: 0x0002);
    var ap3 = await nm.addAccessPoint(wpaFlags: 0x0004);
    var ap4 = await nm.addAccessPoint(wpaFlags: 0x0008);
    var ap5 = await nm.addAccessPoint(wpaFlags: 0x0010);
    var ap6 = await nm.addAccessPoint(wpaFlags: 0x0020);
    var ap7 = await nm.addAccessPoint(wpaFlags: 0x0040);
    var ap8 = await nm.addAccessPoint(wpaFlags: 0x0080);
    var ap9 = await nm.addAccessPoint(wpaFlags: 0x0100);
    var ap10 = await nm.addAccessPoint(wpaFlags: 0x0200);
    var ap11 = await nm.addAccessPoint(wpaFlags: 0x0400);
    var ap12 = await nm.addAccessPoint(wpaFlags: 0x0800);
    var ap13 = await nm.addAccessPoint(wpaFlags: 0x1000);
    await nm.addDevice(hasWireless: true, accessPoints: [
      ap1,
      ap2,
      ap3,
      ap4,
      ap5,
      ap6,
      ap7,
      ap8,
      ap9,
      ap10,
      ap11,
      ap12,
      ap13
    ]);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var accessPoints = client.devices[0].wireless!.accessPoints;
    expect(accessPoints, hasLength(13));
    expect(accessPoints[0].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.pairWep40}));
    expect(accessPoints[1].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.pairWep104}));
    expect(accessPoints[2].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.pairTkip}));
    expect(accessPoints[3].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.pairCcmp}));
    expect(accessPoints[4].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.groupWep40}));
    expect(accessPoints[5].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.groupWep104}));
    expect(accessPoints[6].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.groupTkip}));
    expect(accessPoints[7].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.groupCcmp}));
    expect(accessPoints[8].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.keyManagementPsk}));
    expect(
        accessPoints[9].wpaFlags,
        equals(
            {NetworkManagerWifiAccessPointSecurityFlag.keyManagement802_1X}));
    expect(accessPoints[10].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.keyManagementSae}));
    expect(accessPoints[11].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.keyManagementOwe}));
    expect(accessPoints[12].wpaFlags,
        equals({NetworkManagerWifiAccessPointSecurityFlag.keyManagementOweTm}));
  });

  test('wireless device - request scan', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d = await nm.addDevice(
        hasWireless: true, permHwAddress: 'DE:71:CE:00:00:01');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.wireless, isNotNull);
    expect(d.scanRequested, isFalse);
    await device.wireless!.requestScan(ssids: [
      [104, 101, 108, 108, 111],
      [119, 111, 114, 108, 100]
    ]);
    expect(d.scanRequested, isTrue);
    expect(
        d.scanOptions,
        equals({
          'ssids': DBusArray(DBusSignature('ay'), [
            DBusArray.byte([104, 101, 108, 108, 111]),
            DBusArray.byte([119, 111, 114, 108, 100])
          ])
        }));
  });

  test('other device types', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(deviceType: 6, permHwAddress: 'DE:71:CE:00:00:01');
    await nm.addDevice(deviceType: 7, permHwAddress: 'DE:71:CE:00:00:02');
    await nm.addDevice(deviceType: 8, permHwAddress: 'DE:71:CE:00:00:03');
    await nm.addDevice(deviceType: 9, permHwAddress: 'DE:71:CE:00:00:04');
    await nm.addDevice(deviceType: 10, permHwAddress: 'DE:71:CE:00:00:05');
    await nm.addDevice(deviceType: 11, permHwAddress: 'DE:71:CE:00:00:06');
    await nm.addDevice(deviceType: 12, permHwAddress: 'DE:71:CE:00:00:07');
    await nm.addDevice(deviceType: 15, permHwAddress: 'DE:71:CE:00:00:08');
    await nm.addDevice(deviceType: 17, permHwAddress: 'DE:71:CE:00:00:09');
    await nm.addDevice(deviceType: 18, permHwAddress: 'DE:71:CE:00:00:10');
    await nm.addDevice(deviceType: 19, permHwAddress: 'DE:71:CE:00:00:11');
    await nm.addDevice(deviceType: 20, permHwAddress: 'DE:71:CE:00:00:12');
    await nm.addDevice(deviceType: 21, permHwAddress: 'DE:71:CE:00:00:13');
    await nm.addDevice(deviceType: 22, permHwAddress: 'DE:71:CE:00:00:14');
    await nm.addDevice(deviceType: 23, permHwAddress: 'DE:71:CE:00:00:15');
    await nm.addDevice(deviceType: 24, permHwAddress: 'DE:71:CE:00:00:16');
    await nm.addDevice(deviceType: 25, permHwAddress: 'DE:71:CE:00:00:17');
    await nm.addDevice(deviceType: 26, permHwAddress: 'DE:71:CE:00:00:18');
    await nm.addDevice(deviceType: 27, permHwAddress: 'DE:71:CE:00:00:19');
    await nm.addDevice(deviceType: 28, permHwAddress: 'DE:71:CE:00:00:20');
    await nm.addDevice(deviceType: 29, permHwAddress: 'DE:71:CE:00:00:21');
    await nm.addDevice(deviceType: 30, permHwAddress: 'DE:71:CE:00:00:22');
    await nm.addDevice(deviceType: 31, permHwAddress: 'DE:71:CE:00:00:23');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(23));
    expect(client.devices[0].deviceType,
        equals(NetworkManagerDeviceType.olpcMesh));
    expect(
        client.devices[1].deviceType, equals(NetworkManagerDeviceType.wimax));
    expect(
        client.devices[2].deviceType, equals(NetworkManagerDeviceType.modem));
    expect(client.devices[3].deviceType,
        equals(NetworkManagerDeviceType.infiniband));
    expect(client.devices[4].deviceType, equals(NetworkManagerDeviceType.bond));
    expect(client.devices[5].deviceType, equals(NetworkManagerDeviceType.vlan));
    expect(client.devices[6].deviceType, equals(NetworkManagerDeviceType.adsl));
    expect(client.devices[7].deviceType, equals(NetworkManagerDeviceType.team));
    expect(client.devices[8].deviceType,
        equals(NetworkManagerDeviceType.ipTunnel));
    expect(
        client.devices[9].deviceType, equals(NetworkManagerDeviceType.macVlan));
    expect(
        client.devices[10].deviceType, equals(NetworkManagerDeviceType.vxlan));
    expect(
        client.devices[11].deviceType, equals(NetworkManagerDeviceType.veth));
    expect(
        client.devices[12].deviceType, equals(NetworkManagerDeviceType.macsec));
    expect(
        client.devices[13].deviceType, equals(NetworkManagerDeviceType.dummy));
    expect(client.devices[14].deviceType, equals(NetworkManagerDeviceType.ppp));
    expect(client.devices[15].deviceType,
        equals(NetworkManagerDeviceType.ovsInterface));
    expect(client.devices[16].deviceType,
        equals(NetworkManagerDeviceType.ovsPort));
    expect(client.devices[17].deviceType,
        equals(NetworkManagerDeviceType.ovsBridge));
    expect(
        client.devices[18].deviceType, equals(NetworkManagerDeviceType.wpan));
    expect(client.devices[19].deviceType,
        equals(NetworkManagerDeviceType.sixLoWpan));
    expect(client.devices[20].deviceType,
        equals(NetworkManagerDeviceType.wireguard));
    expect(client.devices[21].deviceType,
        equals(NetworkManagerDeviceType.wifiP2p));
    expect(client.devices[22].deviceType, equals(NetworkManagerDeviceType.vrf));
  });

  test('device state reasons', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    for (var reason = 2; reason <= 67; reason++) {
      await nm.addDevice(stateReason: reason);
    }
    await nm.addDevice(stateReason: 0);
    await nm.addDevice(stateReason: 999);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(68));
    expect(client.devices[0].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.nowManaged));
    expect(client.devices[1].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.nowUnmanaged));
    expect(client.devices[2].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.configFailed));
    expect(client.devices[3].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ipConfigUnavailable));
    expect(client.devices[4].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ipConfigExpired));
    expect(client.devices[5].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.noSecrets));
    expect(client.devices[6].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.supplicantDisconnect));
    expect(client.devices[7].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.supplicantConfigFailed));
    expect(client.devices[8].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.supplicantFailed));
    expect(client.devices[9].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.supplicantTimeout));
    expect(client.devices[10].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.pppStartFailed));
    expect(client.devices[11].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.pppDisconnect));
    expect(client.devices[12].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.pppFailed));
    expect(client.devices[13].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.dhcpStartFailed));
    expect(client.devices[14].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.dhcpError));
    expect(client.devices[15].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.dhcpFailed));
    expect(client.devices[16].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.sharedStartFailed));
    expect(client.devices[17].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.sharedFailed));
    expect(client.devices[18].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.autoIpStartFailed));
    expect(client.devices[19].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.autoIpError));
    expect(client.devices[20].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.autoIpFailed));
    expect(client.devices[21].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemBusy));
    expect(client.devices[22].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemNoDialTone));
    expect(client.devices[23].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemNoCarrier));
    expect(client.devices[24].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemDialTimeout));
    expect(client.devices[25].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemDialFailed));
    expect(client.devices[26].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemInitFailed));
    expect(client.devices[27].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmApnFailed));
    expect(client.devices[28].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmRegistrationNotSearching));
    expect(client.devices[29].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmRegistrationDenied));
    expect(client.devices[30].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmRegistrationTimeout));
    expect(client.devices[31].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmRegistrationFailed));
    expect(client.devices[32].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmPinCheckFailed));
    expect(client.devices[33].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.firmwareMissing));
    expect(client.devices[34].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.removed));
    expect(client.devices[35].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.sleeping));
    expect(client.devices[36].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.connectionRemoved));
    expect(client.devices[37].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.userRequested));
    expect(client.devices[38].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.carrier));
    expect(client.devices[39].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.connectionAssumed));
    expect(client.devices[40].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.supplicantAvailable));
    expect(client.devices[41].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemNotFound));
    expect(client.devices[42].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.btFailed));
    expect(client.devices[43].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmSimNotInserted));
    expect(client.devices[44].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmSimPinRequired));
    expect(client.devices[45].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmSimPukRequired));
    expect(client.devices[46].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.gsmSimWrong));
    expect(client.devices[47].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.infinibandMode));
    expect(client.devices[48].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.dependencyFailed));
    expect(client.devices[49].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.br2684Failed));
    expect(client.devices[50].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemManagerUnavailable));
    expect(client.devices[51].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ssidNotFound));
    expect(client.devices[52].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.secondaryConnectionFailed));
    expect(client.devices[53].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.dcbFcoeFailed));
    expect(client.devices[54].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.teamdControlFailed));
    expect(client.devices[55].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemFailed));
    expect(client.devices[56].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.modemAvailable));
    expect(client.devices[57].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.simPinIncorrect));
    expect(client.devices[58].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.newActivation));
    expect(client.devices[59].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.parentChanged));
    expect(client.devices[60].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.parentManagedChanged));
    expect(client.devices[61].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ovsdbFailed));
    expect(client.devices[62].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ipAddressDuplicate));
    expect(client.devices[63].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.ipMethodUnsupported));
    expect(client.devices[64].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.sriovConfigurationFailed));
    expect(client.devices[65].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.peerNotFound));
    expect(client.devices[66].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.none));
    expect(client.devices[67].stateReason.reason,
        equals(NetworkManagerDeviceStateReason.unknown));
  });

  test('device statistics', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
        hasStatistics: true, refreshRateMs: 100, rxBytes: 1024, txBytes: 2048);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.statistics, isNotNull);
    expect(device.statistics!.refreshRateMs, equals(100));
    expect(device.statistics!.rxBytes, equals(1024));
    expect(device.statistics!.txBytes, equals(2048));

    await device.statistics!.setRefreshRateMs(10);
    expect(device.statistics!.refreshRateMs, equals(100));
  });

  test('no active connections', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.activeConnections, isEmpty);
  });

  test('active connections', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addActiveConnection(id: 'connection1');
    await nm.addActiveConnection(id: 'connection2');
    await nm.addActiveConnection(id: 'connection3');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.activeConnections, hasLength(3));
    expect(client.activeConnections[0].id, equals('connection1'));
    expect(client.activeConnections[1].id, equals('connection2'));
    expect(client.activeConnections[2].id, equals('connection3'));
  });

  test('active connection added', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    client.activeConnectionAdded.listen(expectAsync1((connection) {
      expect(connection.id, equals('connection'));
    }));

    await nm.addActiveConnection(id: 'connection');
  });

  test('active connection removed', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();
    var d = await nm.addActiveConnection(id: 'connection');

    client.activeConnectionRemoved.listen(expectAsync1((connection) {
      expect(connection.id, equals('connection'));
    }));

    await nm.removeActiveConnection(d);
  });

  test('active connection properties', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    var d1 = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:01');
    var d2 = await nm.addDevice(hwAddress: 'DE:71:CE:00:00:02');
    var ip4c = await nm.addIp4Config(gateway: '192.168.0.1');
    var ip6c = await nm.addIp6Config(
        gateway: '2001:0db8:85a3:0000:0000:8a2e:0370:1234');
    var dhcp4c = await nm.addDhcp4Config(options: {
      'option4a': DBusString('192.168.0.1'),
      'option4b': DBusUint32(42)
    });
    var dhcp6c = await nm.addDhcp6Config(options: {
      'option6a': DBusString('2001:0db8:85a3:0000:0000:8a2e:0370:1234'),
      'option6b': DBusUint32(42)
    });
    await nm.addActiveConnection(
        default4: true,
        default6: true,
        devices: [d1, d2],
        dhcp4Config: dhcp4c,
        dhcp6Config: dhcp6c,
        id: 'ID',
        ip4Config: ip4c,
        ip6Config: ip6c,
        state: 1,
        stateFlags: 0xff,
        type: '802-3-ethernet',
        uuid: '123e4567-e89b-12d3-a456-426614174000',
        vpn: true);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.activeConnections, hasLength(1));
    var connection = client.activeConnections[0];
    expect(connection.default4, isTrue);
    expect(connection.default6, isTrue);
    expect(connection.devices, hasLength(2));
    expect(connection.devices[0].hwAddress, equals('DE:71:CE:00:00:01'));
    expect(connection.devices[1].hwAddress, equals('DE:71:CE:00:00:02'));
    expect(connection.dhcp4Config, isNotNull);
    expect(connection.dhcp4Config!.options,
        equals({'option4a': '192.168.0.1', 'option4b': 42}));
    expect(connection.dhcp6Config, isNotNull);
    expect(
        connection.dhcp6Config!.options,
        equals({
          'option6a': '2001:0db8:85a3:0000:0000:8a2e:0370:1234',
          'option6b': 42
        }));
    expect(connection.id, equals('ID'));
    expect(connection.ip4Config, isNotNull);
    expect(connection.ip4Config!.gateway, equals('192.168.0.1'));
    expect(connection.ip6Config, isNotNull);
    expect(connection.ip6Config!.gateway,
        equals('2001:0db8:85a3:0000:0000:8a2e:0370:1234'));
    expect(connection.state,
        equals(NetworkManagerActiveConnectionState.activating));
    expect(
        connection.stateFlags,
        equals({
          NetworkManagerActivationStateFlag.isMaster,
          NetworkManagerActivationStateFlag.isSlave,
          NetworkManagerActivationStateFlag.layer2Ready,
          NetworkManagerActivationStateFlag.ip4Ready,
          NetworkManagerActivationStateFlag.ip6Ready,
          NetworkManagerActivationStateFlag.masterHasSlaves,
          NetworkManagerActivationStateFlag.lifetimeBoundToProfileVisibility,
          NetworkManagerActivationStateFlag.external
        }));
    expect(connection.type, equals('802-3-ethernet'));
    expect(connection.uuid, equals('123e4567-e89b-12d3-a456-426614174000'));
    expect(connection.vpn, isTrue);
  });

  test('primary connection', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addActiveConnection(id: 'connection', type: '802-3-ethernet');

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.primaryConnection, isNotNull);
    expect(client.primaryConnection!.id, equals('connection'));
    expect(client.primaryConnection!.type, equals('802-3-ethernet'));
    expect(client.primaryConnectionType, equals('802-3-ethernet'));
  });

  test('add connection', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    var connection = await client.settings.addConnection({});
    expect(connection, isNotNull);
    expect(nm.connectionSettings, hasLength(1));
    expect(nm.connectionSettings[0].unsaved, isFalse);
  });

  test('add connection unsaved', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    var connection = await client.settings.addConnectionUnsaved({});
    expect(connection, isNotNull);
    expect(nm.connectionSettings, hasLength(1));
    expect(nm.connectionSettings[0].unsaved, isTrue);
  });

  test('activate ethernet connection', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(deviceType: NetworkManagerDeviceType.ethernet.index);
    var s1 = await nm.addConnectionSettings();
    var s2 = await nm.addConnectionSettings();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(client.settings.connections, hasLength(2));

    var connection1 = await client.activateConnection(device: device);
    expect(connection1.id, equals(s1.path.value));
    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, hasLength(1));
    expect(client.activeConnections[0].id, equals(s1.path.value));

    var connection2 = await client.activateConnection(
        device: device, connection: client.settings.connections[1]);
    expect(connection2.id, equals(s2.path.value));

    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, hasLength(2));
    expect(client.activeConnections[1].id, equals(s2.path.value));

    await client.deactivateConnection(connection1);
    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, hasLength(1));
    expect(client.activeConnections[0].id, equals(s2.path.value));

    await client.deactivateConnection(connection2);
    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, isEmpty);
  });

  test('activate wifi connection', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(
      deviceType: NetworkManagerDeviceType.wifi.index,
      hasWireless: true,
      accessPoints: [await nm.addAccessPoint(hwAddress: 'ap1')],
    );
    var s = await nm.addConnectionSettings();

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(client.settings.connections, hasLength(1));
    var settings = client.settings.connections[0];

    expect(device.wireless!.accessPoints, hasLength(1));
    var ap = device.wireless!.accessPoints[0];

    var connection = await client.activateConnection(
        device: device, connection: settings, accessPoint: ap);
    expect(connection.id, equals(s.path.value));
    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, hasLength(1));
    expect(client.activeConnections[0].id, equals(s.path.value));

    await client.deactivateConnection(connection);
    await expectLater(client.propertiesChanged, emits(['ActiveConnections']));
    expect(client.activeConnections, isEmpty);
  });

  test('add and activate connection', () async {
    var server = DBusServer();
    addTearDown(() async => await server.close());
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    var nm = MockNetworkManagerServer(clientAddress);
    addTearDown(() async => await nm.close());
    await nm.start();
    await nm.addDevice(deviceType: NetworkManagerDeviceType.ethernet.index);

    var client = NetworkManagerClient(bus: DBusClient(clientAddress));
    addTearDown(() async => await client.close());
    await client.connect();

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    var activeConnection =
        await client.addAndActivateConnection(device: device);
    expect(activeConnection.devices, hasLength(1));
    expect(activeConnection.devices[0].path, equals(device.path));
  });
}
