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

/// 判断是否还需要继续拉取更多结果来填满过滤后的列表。
///
/// 客户端过滤的通病：筛掉一部分后可见条目变少，若少到撑不满一屏
/// 就无法滚动，列表也就再不会触发"加载更多"，直接卡死。
/// 所以需要主动补足几页。这里把判断抽成纯函数，方便覆盖边界情况。
bool shouldFetchMoreForFilter({
  /// 当前过滤后可见的条数。
  required int visibleCount,

  /// 希望至少凑够多少条。
  required int targetCount,

  /// 下一页地址，为空表示没有更多了。
  required String? nextUrl,

  /// 已经额外拉取过几轮。
  required int roundsDone,

  /// 最多额外拉取几轮，防止筛得太严时无限请求。
  required int maxRounds,
}) {
  if (roundsDone >= maxRounds) return false;
  if (visibleCount >= targetCount) return false;
  if (nextUrl == null || nextUrl.isEmpty) return false;
  return true;
}
