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

/// 首页那些列表用的筛选：标签 + 页数 / 观看数 / 点赞数。
///
/// 和搜索页的筛选是同一套思路——pixiv 返回的 `Illusts` 里本来就带着
/// `tags`、`page_count`、`total_view`、`total_bookmarks`，所以这是
/// **纯客户端过滤**：不发额外请求，也就没有额外的风控风险。
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

  /// 标签条件。空表示不限；多个之间是**"或"**（命中任意一个就留下）。
  ///
  /// 之所以取"或"：这是在已经加载出来的那几十上百条里筛选，
  /// 用"且"很容易筛成空列表（一个作品同时带"初音未来"和"東方"的概率很低），
  /// 而"或"正好对应"我只想看这几个 tag 里的作品"。
  final List<String> tags;

  const IllustFilter({
    this.pages = PageCountRange.any,
    this.views = CountRange.any,
    this.bookmarks = CountRange.any,
    this.tags = const [],
  });

  /// 不做任何限制。
  static const IllustFilter any = IllustFilter();

  bool get isAny =>
      pages.isAny && views.isAny && bookmarks.isAny && tags.isEmpty;

  /// 设了几项。用来给筛选按钮上的角标显示数字（标签整体算一项）。
  int get activeCount =>
      (pages.isAny ? 0 : 1) +
      (views.isAny ? 0 : 1) +
      (bookmarks.isAny ? 0 : 1) +
      (tags.isEmpty ? 0 : 1);

  /// [illust] 是否满足全部条件。
  bool matches(Illusts illust) =>
      pages.matches(illust.pageCount) &&
      views.matches(illust.totalView) &&
      bookmarks.matches(illust.totalBookmarks) &&
      matchesTags(illust.tags);

  /// 标签是否命中。空条件一律通过。
  ///
  /// pixiv 的 tag 同时有原文 `name`（通常是日文）和 `translated_name`
  /// （`Accept_Language=zh-CN` 时的中文译名），两个都比一遍：
  /// 输 "初音ミク" 和输 "初音未来" 都能命中同一批作品。
  ///
  /// 用 `contains` 而不是 `==`：译名常常多带后缀（"初音未来" vs
  /// "初音未来3D"），完全相等会把它们漏掉。
  bool matchesTags(List<Tags> illustTags) {
    if (tags.isEmpty) return true;
    for (final tag in illustTags) {
      final name = tag.name.toLowerCase();
      final translated = tag.translatedName?.toLowerCase();
      for (final query in tags) {
        final keyword = query.toLowerCase();
        if (keyword.isEmpty) continue;
        if (name.contains(keyword)) return true;
        if (translated != null && translated.contains(keyword)) return true;
      }
    }
    return false;
  }

  /// 用"他的作品里有一张满足条件"来判断一个作者。
  ///
  /// 推荐作者（`/v1/user/recommended`）只给几张近期作品，没有粉丝数，
  /// 所以筛作者只能拿这些作品当证据。命中任意一张就算留下——
  /// 和标签筛选一样取"或"，理由也一样：条件取"且"会把列表筛空。
  ///
  /// 没有任何作品（比如只写小说的作者）时**保留**：没有证据不等于不合格，
  /// 无端把人藏起来更让人困惑。
  bool matchesAnyIllust(List<Illusts> illusts) {
    if (isAny) return true;
    if (illusts.isEmpty) return true;
    return illusts.any(matches);
  }

  /// 上下界写反的项按"不限"处理，避免出现筛不出任何东西的死区间；
  /// 标签顺手去空、去重（忽略大小写）。
  IllustFilter normalized() => IllustFilter(
    pages: pages.normalized(),
    views: views.normalized(),
    bookmarks: bookmarks.normalized(),
    tags: normalizeTags(tags),
  );

  /// 去掉空白项、去掉重复项（忽略大小写），保留用户输入的顺序。
  static List<String> normalizeTags(List<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in raw) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;
      result.add(trimmed);
    }
    return List<String>.unmodifiable(result);
  }

  IllustFilter copyWith({
    PageCountRange? pages,
    CountRange? views,
    CountRange? bookmarks,
    List<String>? tags,
  }) => IllustFilter(
    pages: pages ?? this.pages,
    views: views ?? this.views,
    bookmarks: bookmarks ?? this.bookmarks,
    tags: tags ?? this.tags,
  );

  /// 存进 SharedPreferences 的形式：一个 JSON 对象。
  ///
  /// 早期版本存的是"六个数字的数组"，[decode] 仍然认那种格式，
  /// 免得升级后之前设好的条件莫名其妙失效。
  String encode() => jsonEncode({
    'pages': [pages.min, pages.max],
    'views': [views.min, views.max],
    'bookmarks': [bookmarks.min, bookmarks.max],
    'tags': tags,
  });

  /// 解析存下来的字符串。空的、坏掉的一律当作"不限"，
  /// 免得旧版本或手改过的值把列表筛成空白。
  factory IllustFilter.decode(String? raw) {
    if (raw == null || raw.isEmpty) return IllustFilter.any;
    try {
      final data = jsonDecode(raw);
      if (data is List) return _decodeLegacy(data);
      if (data is! Map) return IllustFilter.any;
      final pages = _decodeRange(data['pages']);
      final views = _decodeRange(data['views']);
      final bookmarks = _decodeRange(data['bookmarks']);
      final tags = data['tags'] is List
          ? (data['tags'] as List).whereType<String>().toList()
          : const <String>[];
      return IllustFilter(
        pages: PageCountRange(min: pages.$1, max: pages.$2),
        views: CountRange(min: views.$1, max: views.$2),
        bookmarks: CountRange(min: bookmarks.$1, max: bookmarks.$2),
        tags: tags,
      ).normalized();
    } catch (_) {
      return IllustFilter.any;
    }
  }

  /// 老格式：`[页数min, 页数max, 观看min, 观看max, 点赞min, 点赞max]`。
  static IllustFilter _decodeLegacy(List<dynamic> data) {
    if (data.length != 6) return IllustFilter.any;
    int at(int i) => data[i] is int ? data[i] as int : 0;
    return IllustFilter(
      pages: PageCountRange(min: at(0), max: at(1)).normalized(),
      views: CountRange(min: at(2), max: at(3)).normalized(),
      bookmarks: CountRange(min: at(4), max: at(5)).normalized(),
    );
  }

  /// 读一对 `[min, max]`，坏值一律当 0（不限）。
  static (int, int) _decodeRange(Object? value) {
    if (value is! List || value.length != 2) return (0, 0);
    int at(int i) => value[i] is int ? value[i] as int : 0;
    return (at(0), at(1));
  }

  @override
  bool operator ==(Object other) =>
      other is IllustFilter &&
      other.pages == pages &&
      other.views == views &&
      other.bookmarks == bookmarks &&
      _sameTags(other.tags, tags);

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(pages, views, bookmarks, Object.hashAll(tags));

  @override
  String toString() =>
      'IllustFilter(pages: $pages, views: $views, bookmarks: $bookmarks, '
      'tags: $tags)';
}

/// 每个列表单独存一份筛选条件，互不影响。
///
/// 之所以按列表分开：在"动态"里按点赞数筛几乎什么都剩不下（新作还没攒到赞），
/// 在"收藏"里却很合理。混用一份会让人莫名其妙。
class IllustFilterScope {
  static const String recommend = 'recommend';
  static const String newIllust = 'new_illust';
  static const String bookmark = 'bookmark';

  /// 首页「推荐为你」右边那排头像点进去的作者列表。
  static const String recommendUser = 'recommend_user';
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
