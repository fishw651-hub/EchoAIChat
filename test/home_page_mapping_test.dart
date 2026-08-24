import 'package:aichat/screens/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('homePageToTabIndex', () {
    test('maps all 6 pages to the 4 navigation tabs', () {
      expect(homePageToTabIndex(0), 0); // 首页
      expect(homePageToTabIndex(1), 1); // 智能体子页
      expect(homePageToTabIndex(2), 1); // 群聊子页
      expect(homePageToTabIndex(3), 2); // 发现-智能体
      expect(homePageToTabIndex(4), 2); // 发现-群聊
      expect(homePageToTabIndex(5), 3); // 账户
    });
  });

  group('homeTabToPageIndex', () {
    test('maps tabs without sub pages directly', () {
      expect(homeTabToPageIndex(0), 0);
      expect(homeTabToPageIndex(3), 5);
    });

    test('merged agent/group tab lands on its current sub page', () {
      expect(homeTabToPageIndex(1, subPageGroups: false), 1);
      expect(homeTabToPageIndex(1, subPageGroups: true), 2);
    });

    test('discovery tab lands on its current sub page', () {
      expect(homeTabToPageIndex(2, subPageGroups: false), 3);
      expect(homeTabToPageIndex(2, subPageGroups: true), 4);
    });
  });

  test('tab -> page -> tab round trip is stable', () {
    for (final tab in [0, 1, 2, 3]) {
      for (final subPageGroups in [false, true]) {
        expect(
          homePageToTabIndex(
            homeTabToPageIndex(tab, subPageGroups: subPageGroups),
          ),
          tab,
        );
      }
    }
  });
}
