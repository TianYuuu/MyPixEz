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
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'dart:convert';

import 'package:pixez/er/prefer.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/page/search/count_filter.dart';

/// 小说列表用的筛选：标签 + 阅读数 / 收藏数 / 字数。
///
/// 和插画那套 `IllustFilter` 是同一套思路——pixiv 返回的 `Novel` 里本来
/// 就带着 `tags`、`total_view`、`total_bookmarks`、`text_length`，
/// 所以这是**纯客户端过滤**：不发额外请求，也就没有额外风控风险。
///
/// 和插画筛选的差别只有一点：插画的第三个数量维度是"页数"，
/// 小说的页数基本都是 1，改成更有意义的"字数"（`text_length`）。
class NovelFilter {
  /// 阅读数范围（对应插画的"观看数"）。
  final CountRange views;

  /// 收藏数（点赞数）范围。
  final CountRange bookmarks;

  /// 正文字数范围。小说独有的维度。
  final CountRange textLength;

  /// 标签条件。空表示不限；多个之间是**"或"**（命中任意一个就留下）。
  ///
  /// 理由和插画一样：这是在已经加载出来的那几十上百条里筛选，
  /// 用"且"很容易筛空。
  final List<String> tags;

  const NovelFilter({
    this.views = CountRange.any,
    this.bookmarks = CountRange.any,
    this.textLength = CountRange.any,
    this.tags = const [],
  });

  /// 不做任何限制。
  static const NovelFilter any = NovelFilter();

  bool get isAny =>
      views.isAny && bookmarks.isAny && textLength.isAny && tags.isEmpty;

  /// 设了几项。用来给筛选按钮上的角标显示数字（标签整体算一项）。
  int get activeCount =>
      (views.isAny ? 0 : 1) +
      (bookmarks.isAny ? 0 : 1) +
      (textLength.isAny ? 0 : 1) +
      (tags.isEmpty ? 0 : 1);

  /// [novel] 是否满足全部条件。
  bool matches(Novel novel) =>
      views.matches(novel.totalView) &&
      bookmarks.matches(novel.totalBookmarks) &&
      textLength.matches(novel.textLength) &&
      matchesTags(novel.tags);

  /// 标签是否命中。空条件一律通过。
  ///
  /// pixiv 的 tag 同时有原文 `name`（通常是日文）和 `translated_name`
  /// （`Accept_Language=zh-CN` 时的中文译名），两个都比一遍。
  /// 用 `contains` 而不是 `==`：译名常常多带后缀。
  bool matchesTags(List<Tag> novelTags) {
    if (tags.isEmpty) return true;
    for (final tag in novelTags) {
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

  /// 上下界写反的项按"不限"处理；标签顺手去空、去重（忽略大小写）。
  NovelFilter normalized() => NovelFilter(
    views: views.normalized(),
    bookmarks: bookmarks.normalized(),
    textLength: textLength.normalized(),
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

  NovelFilter copyWith({
    CountRange? views,
    CountRange? bookmarks,
    CountRange? textLength,
    List<String>? tags,
  }) => NovelFilter(
    views: views ?? this.views,
    bookmarks: bookmarks ?? this.bookmarks,
    textLength: textLength ?? this.textLength,
    tags: tags ?? this.tags,
  );

  /// 存进 SharedPreferences 的形式：一个 JSON 对象。
  String encode() => jsonEncode({
    'views': [views.min, views.max],
    'bookmarks': [bookmarks.min, bookmarks.max],
    'text_length': [textLength.min, textLength.max],
    'tags': tags,
  });

  /// 解析存下来的字符串。空的、坏掉的一律当作"不限"。
  factory NovelFilter.decode(String? raw) {
    if (raw == null || raw.isEmpty) return NovelFilter.any;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return NovelFilter.any;
      final views = _decodeRange(data['views']);
      final bookmarks = _decodeRange(data['bookmarks']);
      final textLength = _decodeRange(data['text_length']);
      final tags = data['tags'] is List
          ? (data['tags'] as List).whereType<String>().toList()
          : const <String>[];
      return NovelFilter(
        views: CountRange(min: views.$1, max: views.$2),
        bookmarks: CountRange(min: bookmarks.$1, max: bookmarks.$2),
        textLength: CountRange(min: textLength.$1, max: textLength.$2),
        tags: tags,
      ).normalized();
    } catch (_) {
      return NovelFilter.any;
    }
  }

  /// 读一对 `[min, max]`，坏值一律当 0（不限）。
  static (int, int) _decodeRange(Object? value) {
    if (value is! List || value.length != 2) return (0, 0);
    int at(int i) => value[i] is int ? value[i] as int : 0;
    return (at(0), at(1));
  }

  @override
  bool operator ==(Object other) =>
      other is NovelFilter &&
      other.views == views &&
      other.bookmarks == bookmarks &&
      other.textLength == textLength &&
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
      Object.hash(views, bookmarks, textLength, Object.hashAll(tags));

  @override
  String toString() =>
      'NovelFilter(views: $views, bookmarks: $bookmarks, '
      'textLength: $textLength, tags: $tags)';
}

/// 每个小说列表单独存一份筛选条件，互不影响。
class NovelFilterScope {
  /// 小说「推荐」页。
  static const String recommend = 'novel_recommend';

  /// 小说「动态」（关注）列表。
  static const String newList = 'novel_new';

  /// 小说「收藏」列表。
  static const String bookmark = 'novel_bookmark';
}

String _prefKey(String scope) => 'novel_filter_$scope';

/// 读取某个小说列表上次用的筛选条件。没存过就是"不限"。
NovelFilter loadNovelFilter(String scope) =>
    NovelFilter.decode(Prefer.getString(_prefKey(scope)));

/// 记住某个小说列表的筛选条件，下次进来还在。
Future<void> saveNovelFilter(String scope, NovelFilter filter) =>
    Prefer.setString(_prefKey(scope), filter.encode());
