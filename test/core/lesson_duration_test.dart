import 'package:bodyhub_student/core/config/lesson_duration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BODY HUB lesson duration is 50 minutes', () {
    expect(lessonDuration, const Duration(minutes: 50));
  });
}
