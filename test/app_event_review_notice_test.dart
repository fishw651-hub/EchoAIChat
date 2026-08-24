import 'package:aichat/providers/app_event_provider.dart';
import 'package:aichat/providers/auth_provider.dart';
import 'package:aichat/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multiple offline rejections remain available one by one', () {
    final statuses = <Map<String, dynamic>>[
      {
        'resource_type': 'agent',
        'id': 2,
        'name': 'Second',
        'status': 'rejected',
        'reject_reason': 'second reason',
        'version': 3,
        'reviewed_at': '2026-08-16T11:00:00Z',
      },
      {
        'resource_type': 'agent',
        'id': 1,
        'name': 'First',
        'status': 'rejected',
        'reject_reason': 'first reason',
        'version': 2,
        'reviewed_at': '2026-08-16T10:00:00Z',
      },
    ];

    final all = unseenReviewNotices(statuses, const {});
    expect(all.map((notice) => notice.resourceId), [2, 1]);

    final remaining = unseenReviewNotices(statuses, {all.first.eventId});
    expect(remaining.map((notice) => notice.resourceId), [1]);
  });

  test('non-rejected and empty reasons are not shown', () {
    final notices = unseenReviewNotices([
      {
        'resource_type': 'agent',
        'id': 1,
        'status': 'approved',
        'reject_reason': 'old reason',
      },
      {
        'resource_type': 'group',
        'id': 2,
        'status': 'rejected',
        'reject_reason': '   ',
      },
    ], const {});

    expect(notices, isEmpty);
  });

  test('旧账号审核请求不能写入新账号状态', () {
    final requestOwner = UserProfile(
      id: 1,
      uuid: 'user-a',
      username: 'alice',
      email: 'alice@example.test',
    );
    final switchedOwner = UserProfile(
      id: 2,
      uuid: 'user-b',
      username: 'bob',
      email: 'bob@example.test',
    );

    expect(
      isSameReviewSession(
        const AuthState(isLoggedIn: true, jwtToken: 'jwt-a'),
        owner: 'alice',
        jwt: 'jwt-a',
      ),
      isFalse,
      reason: '缺少用户资料时不能接受旧请求结果',
    );
    expect(
      isSameReviewSession(
        AuthState(isLoggedIn: true, jwtToken: 'jwt-a', user: requestOwner),
        owner: 'alice',
        jwt: 'jwt-a',
      ),
      isTrue,
    );
    expect(
      isSameReviewSession(
        AuthState(isLoggedIn: true, jwtToken: 'jwt-b', user: switchedOwner),
        owner: 'alice',
        jwt: 'jwt-a',
      ),
      isFalse,
    );
  });
}
