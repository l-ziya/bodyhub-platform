import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bodyhub_student/main.dart';

void main() {
  testWidgets('Uygulama açılış ekranı gösterilir', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: BodyHubApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
