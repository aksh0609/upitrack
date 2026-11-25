import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/widgets/app_lock.dart';

void main() {
  Widget app(
          {required bool enabled, required Future<bool> Function() unlock}) =>
      MaterialApp(
        builder: (context, child) => AppLockGate(
            enabled: () async => enabled, unlock: unlock, child: child!),
        home: const Text('payments'),
      );

  testWidgets('off: the app shows at once', (tester) async {
    await tester.pumpWidget(app(enabled: false, unlock: () async => false));
    await tester.pump();
    expect(find.text('UPI Track is locked'), findsNothing);
    expect(find.text('payments'), findsOneWidget);
  });

  testWidgets('on: locked until the device says yes', (tester) async {
    var answer = false;
    var asked = 0;
    await tester.pumpWidget(app(
        enabled: true,
        unlock: () async {
          asked++;
          return answer;
        }));
    await tester.pump();
    expect(asked, 1, reason: 'asks at launch');
    expect(find.text('UPI Track is locked'), findsOneWidget);

    answer = true;
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(asked, 2);
    expect(find.text('UPI Track is locked'), findsNothing);
  });

  testWidgets('locks again after time away, not for an inactive blip',
      (tester) async {
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppLockGate(
        enabled: () async => true,
        unlock: () async {
          asked++;
          return true;
        },
        // Below zero: any time away counts as long enough.
        grace: const Duration(microseconds: -1),
        child: child!,
      ),
      home: const Text('payments'),
    ));
    await tester.pump();
    expect(find.text('UPI Track is locked'), findsNothing);

    final binding = tester.binding;
    // A system dialog over the app: inactive and back, no lock.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(asked, 1);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(asked, 2, reason: 'locked again and asked');
    expect(find.text('UPI Track is locked'), findsNothing);
  });
}
