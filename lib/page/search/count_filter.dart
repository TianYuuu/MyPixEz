/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

/// 按数量（观看数、点赞数）筛选作品。
///
/// 和页数筛选一样是**纯客户端过滤**：这两个数字本来就在搜索结果里，
/// 不需要额外请求，所以不会增加任何封号风险。
///
/// 为什么不做粉丝数筛选：搜索结果里的作者对象只有
/// id / name / account / 头像，**没有粉丝数**。要拿到它必须对每个作者
/// 再发一次请求，几百个结果就是几百次请求——正是要避免的事。
///
/// 顺带一提，点赞数其实 pixiv 的搜索接口原生支持（bookmark_num_min/max，
/// 服务端筛选、翻页也准）。这里仍然走本地过滤，是为了和页数筛选保持
/// 一致的行为：都是"筛已经加载出来的结果"。
/// 解析用户手填的数字。空、非法、负数一律当作 0（不限）。
///
/// 抽成纯函数是为了能直接测：输入框里什么都可能出现。
int parseCountInput(String? text) {
  if (text == null) return 0;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  final value = int.tryParse(trimmed);
  if (value == null || value < 0) return 0;
  return value;
}

class CountRange {
  /// 下限，0 表示不限。
  final int min;

  /// 上限，0 表示不限。
  final int max;

  const CountRange({this.min = 0, this.max = 0});

  /// 不做任何限制。
  static const CountRange any = CountRange();

  bool get isAny => min == 0 && max == 0;

  /// [count] 是否落在范围内。
  bool matches(int count) {
    if (min > 0 && count < min) return false;
    if (max > 0 && count > max) return false;
    return true;
  }

  /// 上下界写反时以"不限"为准，避免出现筛不出任何东西的死区间。
  CountRange normalized() {
    if (min > 0 && max > 0 && min > max) {
      return CountRange(min: min, max: 0);
    }
    return this;
  }

  CountRange copyWith({int? min, int? max}) =>
      CountRange(min: min ?? this.min, max: max ?? this.max);

  @override
  bool operator ==(Object other) =>
      other is CountRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'CountRange(min: $min, max: $max)';
}
