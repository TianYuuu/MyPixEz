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

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/page/novel/novel_filter.dart';
import 'package:pixez/page/search/count_filter.dart';

/// 用真实的反序列化路径造一个 [Novel]，
/// 顺便确认筛选读的就是 `total_view` / `total_bookmarks` / `text_length` / `tags`。
Novel _novel({
  int totalView = 0,
  int totalBookmarks = 0,
  int textLength = 0,
  List<Map<String, dynamic>> tags = const [],
}) {
  return Novel.fromJson({
    'id': 1,
    'title': 'title',
    'caption': '',
    'restrict': 0,
    'x_restrict': 0,
    'is_original': false,
    'image_urls': {'square_medium': '', 'medium': '', 'large': ''},
    'create_date': '2026-10-19T00:00:00+09:00',
    'tags': tags,
    'page_count': 1,
    'text_length': textLength,
    'user': {
      'id': 1,
      'name': 'name',
      'account': 'account',
      'profile_image_urls': {'medium': ''},
      'is_followed': false,
    },
    'series': {'id': null, 'title': null},
    'is_bookmarked': false,
    'total_bookmarks': totalBookmarks,
    'total_view': totalView,
    'visible': true,
    'total_comments': 0,
    'is_muted': false,
    'is_mypixiv_only': false,
    'is_x_restricted': false,
    'novel_ai_type': 0,
  });
}

Map<String, dynamic> _tag(String name, [String? translated]) => {
  'name': name,
  'translated_name': translated,
  'added_by_uploaded_user': false,
};

void main() {
  group('NovelFilter.matches', () {
    test('不限时任何小说都通过', () {
      final filter = NovelFilter.any;
      expect(filter.matches(_novel()), isTrue);
      expect(
        filter.matches(_novel(totalView: 999999, textLength: 999999)),
        isTrue,
      );
    });

    test('阅读数范围', () {
      final filter = const NovelFilter(views: CountRange(min: 1000));
      expect(filter.matches(_novel(totalView: 999)), isFalse);
      expect(filter.matches(_novel(totalView: 1000)), isTrue);
    });

    test('收藏数上限', () {
      final filter = const NovelFilter(bookmarks: CountRange(max: 500));
      expect(filter.matches(_novel(totalBookmarks: 501)), isFalse);
      expect(filter.matches(_novel(totalBookmarks: 500)), isTrue);
    });

    test('字数范围', () {
      final filter = const NovelFilter(
        textLength: CountRange(min: 1000, max: 10000),
      );
      expect(filter.matches(_novel(textLength: 999)), isFalse);
      expect(filter.matches(_novel(textLength: 5000)), isTrue);
      expect(filter.matches(_novel(textLength: 10001)), isFalse);
    });

    test('标签命中原文', () {
      final filter = const NovelFilter(tags: ['初音ミク']);
      expect(filter.matches(_novel(tags: [_tag('初音ミク', '初音未来')])), isTrue);
    });

    test('标签命中译名（输入中文）', () {
      final filter = const NovelFilter(tags: ['初音未来']);
      expect(filter.matches(_novel(tags: [_tag('初音ミク', '初音未来')])), isTrue);
    });

    test('多个标签是"或"', () {
      final filter = const NovelFilter(tags: ['初音未来', '東方']);
      expect(
        filter.matches(_novel(tags: [_tag('東方Project', '东方Project')])),
        isTrue,
      );
    });

    test('全部条件同时满足才通过（条件之间是"且"）', () {
      final filter = const NovelFilter(
        views: CountRange(min: 100),
        bookmarks: CountRange(min: 10),
      );
      expect(
        filter.matches(_novel(totalView: 200, totalBookmarks: 5)),
        isFalse,
      );
      expect(
        filter.matches(_novel(totalView: 200, totalBookmarks: 20)),
        isTrue,
      );
    });
  });

  group('NovelFilter.isAny / activeCount', () {
    test('默认是不限', () {
      expect(NovelFilter.any.isAny, isTrue);
      expect(NovelFilter.any.activeCount, 0);
    });

    test('设了几项就数几项', () {
      const filter = NovelFilter(views: CountRange(min: 100));
      expect(filter.isAny, isFalse);
      expect(filter.activeCount, 1);
      expect(
        const NovelFilter(
          bookmarks: CountRange(min: 10),
          textLength: CountRange(max: 5000),
        ).activeCount,
        2,
      );
      expect(const NovelFilter(tags: ['初音未来']).activeCount, 1);
    });
  });

  group('存取', () {
    test('encode / decode 往返一致', () {
      const filter = NovelFilter(
        views: CountRange(min: 1000),
        bookmarks: CountRange(max: 500),
        textLength: CountRange(min: 2000, max: 10000),
        tags: ['初音未来', '東方'],
      );
      expect(NovelFilter.decode(filter.encode()), filter);
    });

    test('没存过就是不限', () {
      expect(NovelFilter.decode(null), NovelFilter.any);
      expect(NovelFilter.decode(''), NovelFilter.any);
    });

    test('坏数据不会崩', () {
      expect(NovelFilter.decode('not json'), NovelFilter.any);
      expect(NovelFilter.decode('{"a":1}'), NovelFilter.any);
      expect(NovelFilter.decode('[1,2,3]'), NovelFilter.any);
    });

    test('去重、去空、忽略大小写', () {
      final filter = const NovelFilter(
        tags: ['初音未来', '  ', '初音未来', 'Miku'],
      ).normalized();
      expect(filter.tags, ['初音未来', 'Miku']);
    });
  });
}
