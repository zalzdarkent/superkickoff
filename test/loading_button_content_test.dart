import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/ui/widgets/common.dart';

void main() {
  testWidgets('shows progress alongside the button label while loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilledButton(
            onPressed: null,
            child: LoadingButtonContent(
              isLoading: true,
              child: Text('Advance Week'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Advance Week'), findsOneWidget);
  });

  testWidgets('keeps the normal button content when not loading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilledButton(
            onPressed: null,
            child: LoadingButtonContent(
              isLoading: false,
              child: Text('Advance Week'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Advance Week'), findsOneWidget);
  });
}
