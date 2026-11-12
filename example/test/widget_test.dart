import 'package:flutter/material.dart'; // ignore: deprecated_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:vaani_flutter_sdk_example/main.dart';

void main() {
  testWidgets('shows setup hint without dart-defines', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VoiceDemo()));
    expect(find.textContaining('VAANI_API_KEY'), findsOneWidget);
  });
}
