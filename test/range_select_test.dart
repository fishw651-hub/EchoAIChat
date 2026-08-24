import 'package:flutter_test/flutter_test.dart';
import 'package:aichat/utils/range_select.dart';

void main() {
  group('selectRangeTo', () {
    test('空选择集时仅选中目标', () {
      expect(selectRangeTo({}, 5), {5});
    });

    test('目标在锚点之后：选中锚点到目标的闭区间', () {
      expect(selectRangeTo({2}, 5), {2, 3, 4, 5});
    });

    test('目标在锚点之前：选中目标到锚点的闭区间', () {
      expect(selectRangeTo({5}, 2), {2, 3, 4, 5});
    });

    test('锚点取已选最小 index，而非最新选中', () {
      expect(selectRangeTo({4, 2}, 6), {2, 3, 4, 5, 6});
    });

    test('目标等于锚点：不新增', () {
      expect(selectRangeTo({3}, 3), {3});
    });

    test('保留已选区间外的选择', () {
      expect(selectRangeTo({2, 9}, 4), {2, 3, 4, 9});
    });
  });
}
