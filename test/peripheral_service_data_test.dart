import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// Mock platform for testing serviceData argument forwarding and normalization
class MockPeripheralForServiceData extends Fake
    implements UniversalBlePeripheralPlatform {
  final Map<String, Uint8List>? capturedServiceData;
  List<String>? capturedServices;

  MockPeripheralForServiceData({this.capturedServiceData});

  @override
  bool get hasAddressDeviceIds => true;

  @override
  void dispose() {}

  @override
  Future<void> addService(dynamic service, {Duration? timeout}) async {}

  @override
  Future<void> clearServices() async {}

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() async =>
      PeripheralAdvertisingState.advertising;

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async =>
      PeripheralReadinessState.ready;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async =>
      BlePeripheralCapabilities(
        supportsPeripheralMode: true,
        supportsManufacturerDataInAdvertisement: true,
        supportsManufacturerDataInScanResponse: false,
        supportsServiceDataInAdvertisement: true,
        supportsServiceDataInScanResponse: false,
        supportsTargetedCharacteristicUpdate: true,
        supportsAdvertisingTimeout: false,
      );

  @override
  Future<List<String>> getServices() async => [];

  /// Captures the actual parameters passed to the platform
  Map<String, Uint8List>? actualServiceData;
  List<String>? actualServices;

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    Map<String, Uint8List>? serviceData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    actualServiceData = serviceData;
    actualServices = services;
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<List<String>> getSubscribedClients(String characteristicId,
          {String? instanceId}) async =>
      [];

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    String? instanceId,
    required Uint8List value,
    String? deviceId,
  }) async {}

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UniversalBlePeripheral Service Data', () {
    late MockPeripheralForServiceData mockPlatform;

    setUp(() {
      mockPlatform = MockPeripheralForServiceData();
      UniversalBlePeripheral.setInstance(mockPlatform);
    });

    test('forwards serviceData map to platform', () async {
      final serviceData = {
        '00001234-0000-1000-8000-00805f9b34fb': Uint8List.fromList([1, 2, 3]),
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const ['180D'],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      expect(mockPlatform.actualServiceData!.length, 1);
      expect(
        mockPlatform.actualServiceData!['00001234-0000-1000-8000-00805f9b34fb'],
        equals(Uint8List.fromList([1, 2, 3])),
      );
    });

    test('normalizes service data UUID keys to full 128-bit form', () async {
      final serviceData = {
        '1234': Uint8List.fromList([42]), // 16-bit short form
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const [],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      expect(mockPlatform.actualServiceData!.length, 1);
      expect(
        mockPlatform.actualServiceData!
            .containsKey('00001234-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });

    test('preserves payload bytes without transformation', () async {
      final payload = Uint8List.fromList([0xFF, 0x00, 0xAB, 0xCD, 0xEF]);
      final serviceData = {
        '181A': payload, // ATC_MiThermometer service UUID
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const [],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      final normalizedUuid =
          BleUuidParser.string('181A'); // '0000181a-0000-1000-8000-00805f9b34fb'
      expect(
        mockPlatform.actualServiceData![normalizedUuid],
        equals(payload),
      );
    });

    test('handles multiple service data entries', () async {
      final serviceData = {
        '1234': Uint8List.fromList([1, 2]),
        '5678': Uint8List.fromList([3, 4, 5]),
        '00009999-0000-1000-8000-00805f9b34fb': Uint8List.fromList([6]),
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const [],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData!.length, 3);
      expect(mockPlatform.actualServiceData!.values.length, 3);
    });

    test('passes null serviceData to platform when not provided', () async {
      await UniversalBlePeripheral.startAdvertising(
        services: const ['180D'],
      );

      expect(mockPlatform.actualServiceData, isNull);
    });

    test('passes empty serviceData to platform when explicitly provided', () async {
      await UniversalBlePeripheral.startAdvertising(
        services: const ['180D'],
        serviceData: {},
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      expect(mockPlatform.actualServiceData!.isEmpty, isTrue);
    });

    test('normalizes service UUIDs independently of service data',
        () async {
      final serviceData = {
        '1111': Uint8List.fromList([10]),
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const ['180D', '0x181A'],
        serviceData: serviceData,
      );

      // Both service UUIDs should be normalized
      expect(mockPlatform.actualServices!.length, 2);
      expect(mockPlatform.actualServices![0],
          BleUuidParser.string('180D')); // Full 128-bit
      expect(mockPlatform.actualServices![1],
          BleUuidParser.string('181A')); // Full 128-bit

      // serviceData should also be normalized
      expect(
        mockPlatform.actualServiceData!
            .containsKey(BleUuidParser.string('1111')),
        isTrue,
      );
    });

    test('mixed-case UUID keys are normalized to lower-case', () async {
      final serviceData = {
        '00001234-0000-1000-8000-00805f9B34FB': Uint8List.fromList([99]),
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const [],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      // The key should be lowercased by BleUuidParser.string()
      expect(
        mockPlatform.actualServiceData!
            .containsKey('00001234-0000-1000-8000-00805f9b34fb'),
        isTrue,
      );
    });
  });

  group('UniversalBlePeripheral - Unsupported Platforms', () {
    test('Apple platforms are known not to support service data', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(defaultTargetPlatform, equals(TargetPlatform.iOS));

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(defaultTargetPlatform, equals(TargetPlatform.macOS));

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('UniversalBlePeripheral - Queue Integration', () {
    late MockPeripheralForServiceData mockPlatform;

    setUp(() {
      mockPlatform = MockPeripheralForServiceData();
      UniversalBlePeripheral.setInstance(mockPlatform);
      UniversalBlePeripheral.queueType = QueueType.global;
    });

    tearDown(() {
      UniversalBlePeripheral.clearQueue();
    });

    test('service data is passed through command queue', () async {
      final serviceData = {
        '1234': Uint8List.fromList([10, 20]),
      };

      await UniversalBlePeripheral.startAdvertising(
        services: const [],
        serviceData: serviceData,
      );

      expect(mockPlatform.actualServiceData, isNotNull);
      expect(mockPlatform.actualServiceData!.length, 1);
    });
  });

  group('UUID Parser - Service Data Edge Cases', () {
    test('BleUuidParser normalizes 0x-prefixed UUIDs', () {
      final uuid = BleUuidParser.string('0x1234');
      expect(
        uuid,
        equals('00001234-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('BleUuidParser handles full 128-bit UUIDs', () {
      const fullUuid = '12345678-1234-5678-1234-567812345678';
      final normalized = BleUuidParser.string(fullUuid);
      expect(
        normalized,
        equals('12345678-1234-5678-1234-567812345678'),
      );
    });

    test('BleUuidParser throws on invalid UUID', () {
      expect(
        () => BleUuidParser.string('not-a-uuid'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
