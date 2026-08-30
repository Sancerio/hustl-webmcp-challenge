import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hustl_app/core/services/notification_service.dart';

void main() {
  group('NotificationService.buildRestCompletionDetails', () {
    test('returns loud, time-sensitive config when sound is allowed', () {
      final details = buildRestCompletionDetails(playSound: true);

      final android = details.android!;
      expect(android.channelId, 'rest_timer_channel_bell');
      expect(android.playSound, isTrue);
      expect(android.audioAttributesUsage, AudioAttributesUsage.alarm);
      expect(android.sound, isA<RawResourceAndroidNotificationSound>());
      final sound = android.sound as RawResourceAndroidNotificationSound;
      expect(sound.sound, 'rest_bell');

      final ios = details.iOS!;
      expect(ios.presentSound, isTrue);
      expect(ios.sound, 'rest_bell.wav');
      expect(ios.interruptionLevel, InterruptionLevel.timeSensitive);
    });

    test('returns silent, passive config when sound is suppressed', () {
      final details = buildRestCompletionDetails(playSound: false);

      final android = details.android!;
      expect(android.channelId, 'rest_timer_channel_silent');
      expect(android.playSound, isFalse);
      expect(android.audioAttributesUsage, AudioAttributesUsage.notification);
      expect(android.sound, isNull);

      final ios = details.iOS!;
      expect(ios.presentSound, isFalse);
      expect(ios.sound, isNull);
      expect(ios.interruptionLevel, InterruptionLevel.passive);
    });
  });

  group('computeRestNotificationPresentation', () {
    test('foreground bell only when not skipping and app in foreground', () {
      final p = computeRestNotificationPresentation(
        appInForeground: true,
        skipForegroundBell: false,
      );
      expect(p.playForegroundBell, isTrue);
      expect(p.playSound, isFalse);
      expect(p.presentAlert, isFalse);
    });

    test('background uses OS sound when not skipping', () {
      final p = computeRestNotificationPresentation(
        appInForeground: false,
        skipForegroundBell: false,
      );
      expect(p.playForegroundBell, isFalse);
      expect(p.playSound, isTrue);
      expect(p.presentAlert, isTrue);
    });

    test('skipForegroundBell silences both paths', () {
      final p = computeRestNotificationPresentation(
        appInForeground: true,
        skipForegroundBell: true,
      );
      expect(p.playForegroundBell, isFalse);
      expect(p.playSound, isFalse);
      expect(p.presentAlert, isFalse);
    });
  });
  group('NotificationService iOS rest bell staging', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rest_bell_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'copies bundled bell asset into Library/Sounds when missing',
      () async {
        final service = NotificationService();
        service.resetIosRestBellCacheForTest();
        final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
        await service.debugPrepareIosRestBellSound(
          libraryDirectoryProvider: () async => tempDir,
          assetLoader: (_) async => ByteData.view(bytes.buffer),
          force: true,
        );

        final file = File('${tempDir.path}/Sounds/rest_bell.wav');
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), bytes);
      },
    );

    test('skips copy when sound file already exists', () async {
      final service = NotificationService();
      service.resetIosRestBellCacheForTest();
      final soundsDir = Directory('${tempDir.path}/Sounds');
      await soundsDir.create(recursive: true);
      final file = File('${soundsDir.path}/rest_bell.wav');
      await file.writeAsBytes(<int>[9, 9]);

      var loaderCalled = false;
      await service.debugPrepareIosRestBellSound(
        libraryDirectoryProvider: () async => tempDir,
        assetLoader: (_) async {
          loaderCalled = true;
          return ByteData(0);
        },
        force: true,
      );

      expect(loaderCalled, isFalse);
      expect(await file.readAsBytes(), <int>[9, 9]);
    });
  });
}
