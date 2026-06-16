import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

/// Builds OTel resource attributes from already-resolved device/app values.
///
/// Kept pure (no platform channels) so it is unit-testable. The async
/// [detectMobileResourceAttributes] resolves the raw values and delegates here.
Map<String, Object> mobileResourceAttributesFrom({
  required String osName,
  required String osVersion,
  String? deviceModelIdentifier,
  String? deviceManufacturer,
  String? serviceVersion,
}) {
  return <String, Object>{
    'os.name': osName,
    'os.version': osVersion,
    if (deviceModelIdentifier != null && deviceModelIdentifier.isNotEmpty)
      'device.model.identifier': deviceModelIdentifier,
    if (deviceManufacturer != null && deviceManufacturer.isNotEmpty)
      'device.manufacturer': deviceManufacturer,
    // service.version is conditional: emitted only when a non-empty version is
    // resolved. On a built app PackageInfo.version is always present; in tests
    // or unusual hosts it may be empty, in which case the attribute is omitted.
    if (serviceVersion != null && serviceVersion.isNotEmpty)
      'service.version': serviceVersion,
  };
}

/// Resolves device and app metadata into OTel resource attributes.
///
/// Reads only non-PII device identity (OS name/version, model identifier,
/// manufacturer) — deliberately NOT the iOS `name` field, which is the
/// user-assigned device name ("iPhone de João") and would re-introduce the
/// host.name PII this package omits on mobile. Platform-channel-bound, so it
/// is verified via the example app / staging rather than unit tests; the pure
/// [mobileResourceAttributesFrom] above carries the unit-tested mapping.
/// Non-PII resource values extracted from iOS device info.
///
/// Reads [IosDeviceInfo.systemName] ("iOS"/"iPadOS") — deliberately NOT
/// [IosDeviceInfo.name], the user-assigned device name ("iPhone de João") that
/// would re-introduce the host.name PII this package omits on mobile. Kept as a
/// named seam so a regression (reading `name`) is caught by a unit test.
@visibleForTesting
({String osName, String osVersion, String modelId, String manufacturer})
iosResourceValuesFrom(IosDeviceInfo ios) {
  return (
    osName: ios.systemName,
    osVersion: ios.systemVersion,
    modelId: ios.utsname.machine,
    manufacturer: 'Apple',
  );
}

Future<Map<String, Object>> detectMobileResourceAttributes() async {
  final deviceInfo = DeviceInfoPlugin();
  final packageInfo = await PackageInfo.fromPlatform();

  var osName = Platform.operatingSystem;
  var osVersion = '';
  String? deviceModelIdentifier;
  String? deviceManufacturer;

  if (Platform.isIOS) {
    final ios = await deviceInfo.iosInfo;
    final values = iosResourceValuesFrom(ios);
    osName = values.osName;
    osVersion = values.osVersion;
    deviceModelIdentifier = values.modelId;
    deviceManufacturer = values.manufacturer;
  } else if (Platform.isAndroid) {
    final android = await deviceInfo.androidInfo;
    osName = 'Android';
    osVersion = android.version.release; // "14"
    deviceModelIdentifier = android.model;
    deviceManufacturer = android.manufacturer;
  } else {
    osVersion = Platform.operatingSystemVersion;
  }

  return mobileResourceAttributesFrom(
    osName: osName,
    osVersion: osVersion,
    deviceModelIdentifier: deviceModelIdentifier,
    deviceManufacturer: deviceManufacturer,
    serviceVersion: packageInfo.version,
  );
}
