import 'package:bodyhub_student/features/scheduling/presentation/v2_booking_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'V2 request notice does not present a pending request as a reservation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: V2BookingRequestNotice())),
      );

      expect(find.textContaining('Henüz onaylanmadı'), findsOneWidget);
      expect(find.textContaining('ders rezervasyonu oluşmadı'), findsOneWidget);
      expect(
        find.text('Derslerin uygulama süresi 50 dakikadır.'),
        findsOneWidget,
      );
    },
  );
}
