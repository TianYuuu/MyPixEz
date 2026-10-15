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

/// 按页数筛选作品。
///
/// pixiv 的搜索接口没有页数参数（只有 sort / search_target / 日期 /
/// bookmark_num / search_ai_type），所以这是纯客户端过滤：
/// `page_count` 本来就在搜索结果里，不需要额外请求。
class PageCountRange {
  /// 最少页数，0 表示不限。
  final int min;

  /// 最多页数，0 表示不限。
  final int max;

  const PageCountRange({this.min = 0, this.max = 0});

  /// 不做任何限制。
  static const PageCountRange any = PageCountRange();

  bool get isAny => min == 0 && max == 0;

  /// [pageCount] 是否落在范围内。
  bool matches(int pageCount) {
    if (min > 0 && pageCount < min) return false;
    if (max > 0 && pageCount > max) return false;
    return true;
  }

  /// 上下界写反时以"不限"为准，避免出现筛不出任何东西的死区间。
  PageCountRange normalized() {
    if (min > 0 && max > 0 && min > max) {
      return PageCountRange(min: min, max: 0);
    }
    return this;
  }

  PageCountRange copyWith({int? min, int? max}) =>
      PageCountRange(min: min ?? this.min, max: max ?? this.max);

  @override
  bool operator ==(Object other) =>
      other is PageCountRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'PageCountRange(min: $min, max: $max)';
}
