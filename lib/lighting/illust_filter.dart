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

import 'dart:convert';

import 'package:pixez/er/prefer.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';

/// 首页那些列表用的数量筛选：页数 / 观看数 / 点赞数。
///
/// 和搜索页的筛选是同一套思路——pixiv 返回的 `Illusts` 里本来就带着
/// `page_count`、`total_view`、`total_bookmarks`，所以这是**纯客户端过滤**：
/// 不发额外请求，也就没有额外的风控风险。
///
/// 既然不发请求，翻页时就会"越翻越少"：被筛掉的条目只是不显示，
/// 不会从接口那边补回来。`LightingList` 已经处理了"筛完后不够一屏就多拉几页"
/// 的补足逻辑（见 `lighting_filter.dart` 的 `shouldFetchMoreForFilter`）。
///
/// 为什么不做粉丝数筛选：列表里的作者对象只有 id / 名字 / 账号 / 头像，
/// 要拿粉丝数就只能对每个作者再请求一次，几百个结果就是几百次请求。
class IllustFilter {
  /// 页数范围。动图（ugoira）的页数固定是 1。
  final PageCountRange pages;

  /// 观看数范围。
  final CountRange views;

  /// 点赞数（收藏数）范围。
  final CountRange bookmarks;

  const IllustFilter({
    this.pages = PageCountRange.any,
    this.views = CountRange.any,
    this.bookmarks = CountRange.any,
  });

  /// 不做任何限制。
  static const IllustFilter any = IllustFilter();

  bool get isAny => pages.isAny && views.isAny && bookmarks.isAny;

  /// 设了几项。用来给筛选按钮上的角标显示数字。
  int get activeCount =>
      (pages.isAny ? 0 : 1) + (views.isAny ? 0 : 1) + (bookmarks.isAny ? 0 : 1);

  /// [illust] 是否满足全部条件。
  bool matches(Illusts illust) =>
      pages.matches(illust.pageCount) &&
      views.matches(illust.totalView) &&
      bookmarks.matches(illust.totalBookmarks);

  /// 上下界写反的项按"不限"处理，避免出现筛不出任何东西的死区间。
  IllustFilter normalized() => IllustFilter(
    pages: pages.normalized(),
    views: views.normalized(),
    bookmarks: bookmarks.normalized(),
  );

  IllustFilter copyWith({
    PageCountRange? pages,
    CountRange? views,
    CountRange? bookmarks,
  }) => IllustFilter(
    pages: pages ?? this.pages,
    views: views ?? this.views,
    bookmarks: bookmarks ?? this.bookmarks,
  );

  /// 存进 SharedPreferences 的形式：六个数字排成一行 JSON 数组。
  String encode() => jsonEncode([
    pages.min,
    pages.max,
    views.min,
    views.max,
    bookmarks.min,
    bookmarks.max,
  ]);

  /// 解析存下来的字符串。空的、坏掉的一律当作"不限"，
  /// 免得旧版本或手改过的值把列表筛成空白。
  factory IllustFilter.decode(String? raw) {
    if (raw == null || raw.isEmpty) return IllustFilter.any;
    try {
      final list = jsonDecode(raw);
      if (list is! List || list.length != 6) return IllustFilter.any;
      int at(int i) => list[i] is int ? list[i] as int : 0;
      return IllustFilter(
        pages: PageCountRange(min: at(0), max: at(1)).normalized(),
        views: CountRange(min: at(2), max: at(3)).normalized(),
        bookmarks: CountRange(min: at(4), max: at(5)).normalized(),
      );
    } catch (_) {
      return IllustFilter.any;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is IllustFilter &&
      other.pages == pages &&
      other.views == views &&
      other.bookmarks == bookmarks;

  @override
  int get hashCode => Object.hash(pages, views, bookmarks);

  @override
  String toString() =>
      'IllustFilter(pages: $pages, views: $views, bookmarks: $bookmarks)';
}

/// 每个列表单独存一份筛选条件，互不影响。
///
/// 之所以按列表分开：在"动态"里按点赞数筛几乎什么都剩不下（新作还没攒到赞），
/// 在"收藏"里却很合理。混用一份会让人莫名其妙。
class IllustFilterScope {
  static const String recommend = 'recommend';
  static const String newIllust = 'new_illust';
  static const String bookmark = 'bookmark';
}

String _prefKey(String scope) => 'illust_count_filter_$scope';

/// 读取某个列表上次用的筛选条件。没存过就是"不限"。
///
/// 同步读取：`Prefer` 在 App 启动时就初始化好了，这里不需要 await。
IllustFilter loadIllustFilter(String scope) =>
    IllustFilter.decode(Prefer.getString(_prefKey(scope)));

/// 记住某个列表的筛选条件，下次进来还在。
Future<void> saveIllustFilter(String scope, IllustFilter filter) =>
    Prefer.setString(_prefKey(scope), filter.encode());
