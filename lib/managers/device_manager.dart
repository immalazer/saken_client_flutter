import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:saken/clients/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceManager {
  List<String> deviceId = <String>[];
  bool syncing = false;
  String syncedDevice = "";
  
  DateTime? syncInitiatedTime;
  Duration playbackOffset = Duration.zero;
  Duration estimatedNetworkLatency = Duration.zero;

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
    syncInitiatedTime = null;
    playbackOffset = Duration.zero;
    estimatedNetworkLatency = Duration.zero;
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

    final requestTime = DateTime.now();
    
    Map<String, String> requests = {};
    requests['reason'] = command;
    requests['origin'] = deviceId[1];
    requests['key'] = targetId;
    requests['filename'] = "unknown";
    requests['timestamp'] = requestTime.millisecondsSinceEpoch.toString();
    if (data != null) requests['extra'] = data.toString();

    await apiClient.sendAPIRequest('POST', "devices/$targetId", requests).then((_) {
      // Update estimated network latency based on round-trip time
      final responseTime = DateTime.now();
      final latency = responseTime.difference(requestTime);
      estimatedNetworkLatency = (estimatedNetworkLatency + latency) ~/ 2;
    });
  }

  Future<void> registerDevice(List<String> value, ApiClient apiClient) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, String> requests = {};

    requests['nickname'] = value[0];
    requests['key'] = value[1];
    requests['device_type'] = value[2];

    await apiClient.sendAPIRequest('POST', 'devices', requests).then((json) {
      // Update our local deviceId value.
      // If it's still unknown, then just assume we never had one set.
      if (value[1] == 'unknown') {
        prefs.setString('deviceId', json?['uuid']);
      } else {
        deviceId = value;
      }
    });
  }

  Future<List<String>> getDeviceIdentifier() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    String deviceName = "unknown";
    String deviceIdentifier = prefs.getString('deviceId') ?? "unknown";
    String deviceType = "unknown";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      // The web doesnt have a device UID, so use a combination fingerprint as an example
      WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
      deviceName = "${webInfo.browserName.name} on ${webInfo.platform}";
      deviceType = "web";
    } else if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceName = androidInfo.name;
      deviceType = "mobile";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceName = iosInfo.name;
      deviceType = "mobile";
    } else if (Platform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
      deviceName = linuxInfo.id;
      deviceType = "pc";
    } else if (Platform.isWindows) {
      WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
      deviceName = windowsInfo.computerName;
      deviceType = "pc";
    } else if (Platform.isMacOS) {
      MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
      deviceName = macInfo.computerName;
      deviceType = "pc";
    }
    return [deviceName, deviceIdentifier, deviceType];
  }
}
