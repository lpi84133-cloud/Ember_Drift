// Basic smoke test: the app boots and shows the loading screen first.

import 'package:flutter_test/flutter_test.dart';

import 'package:emberdrift/main.dart';

void main() {
  testWidgets('App boots into the loading screen', (WidgetTester tester) async {
    await tester.pumpWidget(const EmberDriftApp());
    await tester.pump();

    expect(find.textContaining('Loading'), findsOneWidget);
  });
}
