import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/health_sync/data/sources/health_connect_intent_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.hustl.app/health_connect');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The bridge is Android-guarded; pretend we're on Android for the channel work.
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('init fires onShowRationale when a cold-start signal is pending', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'consumePendingHealthPermissionRationale') return true;
      return null;
    });

    var shown = 0;
    await HealthConnectIntentBridge(channel: channel).init(
      onShowRationale: () async => shown++,
    );

    expect(shown, 1);
    expect(
      calls.map((c) => c.method),
      contains('consumePendingHealthPermissionRationale'),
    );
  });

  test('init does NOT fire onShowRationale when nothing is pending', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumePendingHealthPermissionRationale') return false;
      return null;
    });

    var shown = 0;
    await HealthConnectIntentBridge(channel: channel).init(
      onShowRationale: () async => shown++,
    );

    expect(shown, 0);
  });

  test(
    'incoming showHealthPermissionRationale call triggers onShowRationale',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'consumePendingHealthPermissionRationale') {
          return false;
        }
        return null;
      });

      var shown = 0;
      await HealthConnectIntentBridge(channel: channel).init(
        onShowRationale: () async => shown++,
      );
      expect(shown, 0);

      // Simulate the native side pushing the rationale notification at us.
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('showHealthPermissionRationale'),
        ),
        (_) {},
      );

      expect(shown, 1);
    },
  );

  test('openManagePermissions returns the channel bool (true)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openHealthConnectPermissions') return true;
      return null;
    });

    final result =
        await HealthConnectIntentBridge(channel: channel).openManagePermissions();
    expect(result, isTrue);
  });

  test('openManagePermissions returns the channel bool (false)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openHealthConnectPermissions') return false;
      return null;
    });

    final result =
        await HealthConnectIntentBridge(channel: channel).openManagePermissions();
    expect(result, isFalse);
  });

  test('openManagePermissions returns false when no native handler', () async {
    // No mock handler set -> MissingPluginException -> swallowed to false.
    final result =
        await HealthConnectIntentBridge(channel: channel).openManagePermissions();
    expect(result, isFalse);
  });

  test('all bridge methods no-op off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    var shown = 0;
    final bridge = HealthConnectIntentBridge(channel: channel);
    await bridge.init(onShowRationale: () async => shown++);
    final opened = await bridge.openManagePermissions();

    expect(shown, 0);
    expect(opened, isFalse);
    expect(calls, isEmpty);
  });
}
