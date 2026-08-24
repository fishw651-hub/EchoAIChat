import 'package:aichat/providers/group_provider.dart';
import 'package:aichat/services/profile_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('narrator prompt requires third-person output within 150 characters', () {
    expect(GroupNotifier.narratorPersonaTemplate, contains('第三人称'));
    expect(GroupNotifier.narratorPersonaTemplate, contains('150'));
    expect(GroupNotifier.narratorPersonaTemplate, contains('manage_character'));
  });

  test('profile prompt does not turn agent facts into user facts', () {
    expect(
      ProfileAiService.userFactPolicy,
      contains('不要把智能体本人的信息归入用户画像'),
    );
  });
}
