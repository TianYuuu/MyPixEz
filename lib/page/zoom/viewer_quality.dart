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

/// 看图页的"渐进画质"与"预加载"决策。
///
/// 这两件事都只跟索引、设置和一个布尔状态有关，抽成纯函数便于直接测。

/// 一页在不同画质下的三个地址。任意一个都可能缺失。
class ViewerUrls {
  /// 缩略图条用的中等尺寸图，也是过渡时的占位图。
  final String? medium;

  /// 大图。默认画质。
  final String? large;

  /// 原图。体积最大，只在用户选了"原图"且页面停稳后才用。
  final String? original;

  const ViewerUrls({this.medium, this.large, this.original});
}

String? _usable(String? url) => (url == null || url.isEmpty) ? null : url;

/// 停稳时该用的最终图。
///
/// [preferOriginal] 为 true（用户选了"原图"）才优先原图，否则优先大图。
/// 另一个缺失时逐级退回，最后退回缩略图。
String settledUrlOf(ViewerUrls urls, {required bool preferOriginal}) {
  final original = _usable(urls.original);
  final large = _usable(urls.large);
  final medium = _usable(urls.medium);
  if (preferOriginal) return original ?? large ?? medium ?? '';
  return large ?? original ?? medium ?? '';
}

/// 过渡时的占位图：优先缩略图。
///
/// 之所以拿 medium 当占位，是因为缩略图条已经在加载它了，
/// 大概率已在内存缓存里，能立刻出画面。
String previewUrlOf(ViewerUrls urls) {
  return _usable(urls.medium) ??
      _usable(urls.large) ??
      _usable(urls.original) ??
      '';
}

/// 某个索引此刻实际该显示哪张图。
///
/// [isCurrent] 它是不是当前页；[currentIsFinal] 当前页是否已经升级到最终画质。
/// 只有"停稳后的当前页"才用最终画质，其余一律先用缩略图占位，
/// 这样滑动途中不会出现黑屏。
String viewerUrlFor(
  ViewerUrls urls, {
  required bool preferOriginal,
  required bool isCurrent,
  required bool currentIsFinal,
}) {
  if (isCurrent && currentIsFinal) {
    return settledUrlOf(urls, preferOriginal: preferOriginal);
  }
  return previewUrlOf(urls);
}

/// 该预加载哪些页。
///
/// 只看后面的若干页（往前翻才是主要场景），
/// 会跳过越界与空 URL 的页。返回的是索引列表。
List<int> prefetchTargets({
  required int currentIndex,
  required int prefetchCount,
  required int pageCount,
  required List<String?> largeUrls,
}) {
  if (prefetchCount <= 0 || pageCount <= 1) return const [];
  final result = <int>[];
  for (var i = 1; i <= prefetchCount; i++) {
    final index = currentIndex + i;
    if (index >= pageCount) break;
    if (index >= largeUrls.length) break;
    final url = largeUrls[index];
    if (url == null || url.isEmpty) continue;
    result.add(index);
  }
  return result;
}
