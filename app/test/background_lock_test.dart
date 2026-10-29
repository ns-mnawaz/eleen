// The platform overlay engine (BackgroundReminderOverlay) is DISPLAY ONLY:
// the main isolate pushes reminder toasts and the live last-minute
// countdown; the engine renders those pills over whatever app is running.
// The interactive lock is deliberately not an overlay — a platform window
// cannot take TV-remote key input — so a lock while backgrounded brings the
// Eleen activity to the front (see background_toast_test.dart).

import 'dart:async';

import 'package:eleen/tv/lock_overlay.dart';
import 'package:eleen/tv/overlay_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the main isolate at the other end of the overlay messenger.
class FakeMainIsolate {
  final toOverlay = StreamController<Object?>.broadcast();
  final sentToMain = <Object?>[];

  Stream<Object?> get messages => toOverlay.stream;

  Future<void> pushToast(String message) async {
    toOverlay.add({'type': 'toast', 'message': message});
  }

  Future<void> pushLastMinute(int seconds) async {
    toOverlay.add({'type': 'lastMinute', 'seconds': seconds});
  }
}

void main() {
  group('OverlayChannelClient protocol', () {
    test('parses toast and last-minute pushes; ignores the rest', () async {
      final fake = FakeMainIsolate();
      final client = OverlayChannelClient(messages: fake.messages)..listen();

      final toasts = <String>[];
      final minutes = <int>[];
      final sub1 = client.toastPushes.listen(toasts.add);
      final sub2 = client.lastMinutePushes.listen(minutes.add);

      await fake.pushToast('10 minutes left');
      await fake.pushLastMinute(42);
      fake.toOverlay.add({'type': 'unknown'});
      fake.toOverlay.add('not a map');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(toasts, ['10 minutes left']);
      expect(minutes, [42]);
      expect(fake.sentToMain, isEmpty,
          reason: 'the engine never sends anything — display only');

      await sub1.cancel();
      await sub2.cancel();
      client.dispose();
    });
  });

  group('BackgroundReminderOverlay widget', () {
    Future<void> pumpOverlay(WidgetTester tester, FakeMainIsolate fake) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
            home: BackgroundReminderOverlay(
                client: OverlayChannelClient(messages: fake.messages))),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a toast push shows the pill and it dismisses itself',
        (tester) async {
      final fake = FakeMainIsolate();
      await pumpOverlay(tester, fake);

      expect(find.byKey(const Key('reminder-toast')), findsNothing);

      await fake.pushToast('10 minutes left');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('reminder-toast')), findsOneWidget);
      expect(find.text('10 minutes left'), findsOneWidget);

      // ~5 seconds later the pill is gone (transparent idle mode).
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const Key('reminder-toast')), findsNothing);
    });

    testWidgets('the last-minute countdown renders live per push',
        (tester) async {
      final fake = FakeMainIsolate();
      await pumpOverlay(tester, fake);

      await fake.pushLastMinute(42);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('last-minute-countdown')), findsOneWidget);

      await fake.pushLastMinute(41);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('last-minute-countdown')), findsOneWidget);

      // A zero push ends it (time added from the phone).
      await fake.pushLastMinute(0);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('last-minute-countdown')), findsNothing);
    });

    testWidgets('toast and badge render together over the running app',
        (tester) async {
      final fake = FakeMainIsolate();
      await pumpOverlay(tester, fake);

      await fake.pushLastMinute(30);
      await fake.pushToast('5 minutes left');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('reminder-toast')), findsOneWidget);
      expect(find.byKey(const Key('last-minute-countdown')), findsOneWidget);
    });
  });
}
