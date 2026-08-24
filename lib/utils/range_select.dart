/// 微信式"选到这里"：以已选中最小的 index 为锚点，
/// 把锚点到 [target] 之间的所有消息 index 加入选择集（纯函数，便于测试）。
Set<int> selectRangeTo(Set<int> selected, int target) {
  if (selected.isEmpty) return {target};
  var anchor = selected.first;
  for (final i in selected) {
    if (i < anchor) anchor = i;
  }
  final lo = anchor < target ? anchor : target;
  final hi = anchor > target ? anchor : target;
  return {
    ...selected,
    for (var i = lo; i <= hi; i++) i,
  };
}
