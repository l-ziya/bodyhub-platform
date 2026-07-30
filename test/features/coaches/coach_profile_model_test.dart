import 'package:bodyhub_student/features/coaches/models/coach_profile_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coach profile mapping normalizes immutable specialty IDs', () {
    final profile = CoachProfileModel.fromFirestore('coach-a', {
      'displayName': 'Coach A',
      'active': true,
      'bookingEnabled': true,
      'specialtyIds': ['tennis', ' fitness ', 'tennis', ''],
      'bio': 'Public profile',
      'photoUrl': '',
    });

    expect(profile.specialtyIds, ['tennis', 'fitness']);
    expect(() => profile.specialtyIds.add('swimming'), throwsUnsupportedError);
  });
}
