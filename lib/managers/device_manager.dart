import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:saken/clients/api_client.dart';

class DeviceManager {
  List<String> deviceId = <String>[];
  bool syncing = false;
  String syncedDevice = "";

  DeviceManager();

  String getUniqueId() {
    return deviceId[1];
  }

  bool isDeviceSyncing() {
    return (syncing && syncedDevice != getUniqueId());
  }

  void stopSync(ApiClient apiClient) async {
    invokeDeviceCommand('sync-end', syncedDevice, apiClient);
    syncing = false;
    syncedDevice = "";
  }

  Future<void> invokeDeviceCommand(
    String command,
    String targetId,
    ApiClient apiClient, {
    dynamic data,
  }) async {
    // Return early if the targetId is somehow the same as the device ID,
    // or when the user cancelled the device selection dialogue.
    if ((deviceId[1] == targetId) || (targetId == "unknown")) return;

    Map<String, String> requests = {};
    requests['reason'] = command;
    requests['origin'] = deviceId[1];
    requests['key'] = targetId;
    requests['filename'] = "unknown";
    if (data != null) requests['extra'] = data.toString();

    apiClient.sendPostRequest("devices/$targetId", requests);
  }

  Future<void> registerDevice(List<String> value, ApiClient apiClient) async {
    Map<String, String> requests = {};

    requests['nickname'] = value[0];
    requests['key'] = value[1];
    requests['device_type'] = value[2];

    apiClient.sendPostRequest('devices', requests);

    // Update our local deviceId value.
    deviceId = value;
  }

  Future<List<String>> getDeviceIdentifier() async {
    String deviceName = "unknown";
    String deviceIdentifier = "unknown";
    String deviceType = "unknown";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      // The web doesnt have a device UID, so use a combination fingerprint as an example
      WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
      deviceName = "${webInfo.browserName.name} on ${webInfo.platform}";
      deviceIdentifier =
          "${webInfo.browserName.name}:${webInfo.hardwareConcurrency.toString()}${webInfo.platform.toString()}${webInfo.maxTouchPoints.toString()}";
      deviceType = "web";
    } else if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceName = androidInfo.name;
      deviceIdentifier = "${androidInfo.name}:${androidInfo.model}";
      deviceType = "mobile";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceName = iosInfo.name;
      deviceIdentifier = "${iosInfo.name}:${iosInfo.model}";
      deviceType = "mobile";
    } else if (Platform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
      deviceName = linuxInfo.id;
      deviceIdentifier = "${linuxInfo.id}:${linuxInfo.machineId}";
      deviceType = "pc";
    } else if (Platform.isWindows) {
      WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
      deviceName = windowsInfo.computerName;
      deviceIdentifier = "${windowsInfo.computerName}:${windowsInfo.deviceId}";
      deviceType = "pc";
    } else if (Platform.isMacOS) {
      MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
      deviceName = macInfo.computerName;
      deviceIdentifier = "${macInfo.computerName}:${macInfo.systemGUID}";
      deviceType = "pc";
    }
    return [deviceName, deviceIdentifier, deviceType];
  }
}
