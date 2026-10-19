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

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/lighting/illust_filter.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';

/// 用真实的反序列化路径造一个 [Illusts]，
/// 顺便确认筛选读的就是 `page_count` / `total_view` / `total_bookmarks`。
Illusts _illust({
  int pageCount = 1,
  int totalView = 0,
  int totalBookmarks = 0,
}) {
  return Illusts.fromJson({
    'id': 1,
    'title': 'title',
    'type': 'illust',
    'image_urls': {'square_medium': '', 'medium': '', 'large': ''},
    'caption': '',
    'restrict': 0,
    'user': {
      'id': 1,
      'name': 'name',
      'account': 'account',
      'profile_image_urls': {'medium': ''},
    },
    'tags': <dynamic>[],
    'tools': <dynamic>[],
    'create_date': '2026-10-19T00:00:00+09:00',
    'page_count': pageCount,
    'width': 100,
    'height': 100,
    'sanity_level': 2,
    'x_restrict': 0,
    'meta_pages': <dynamic>[],
    'total_view': totalView,
    'total_bookmarks': totalBookmarks,
    'is_bookmarked': false,
    'visible': true,
    'is_muted': false,
    'illust_ai_type': 0,
  });
}

void main() {
  group('IllustFilter.matches', () {
    test('不限时任何作品都通过', () {
      final filter = IllustFilter.any;
      expect(filter.matches(_illust(pageCount: 1, totalView: 0)), isTrue);
      expect(
        filter.matches(_illust(pageCount: 200, totalView: 999999)),
        isTrue,
      );
    });

    test('页数范围', () {
      final filter = const IllustFilter(pages: PageCountRange(min: 2, max: 10));
      expect(filter.matches(_illust(pageCount: 1)), isFalse);
      expect(filter.matches(_illust(pageCount: 2)), isTrue);
      expect(filter.matches(_illust(pageCount: 10)), isTrue);
      expect(filter.matches(_illust(pageCount: 11)), isFalse);
    });

    test('点赞数下限', () {
      final filter = const IllustFilter(bookmarks: CountRange(min: 1000));
      expect(filter.matches(_illust(totalBookmarks: 999)), isFalse);
      expect(filter.matches(_illust(totalBookmarks: 1000)), isTrue);
    });

    test('观看数上限', () {
      final filter = const IllustFilter(views: CountRange(max: 500));
      expect(filter.matches(_illust(totalView: 500)), isTrue);
      expect(filter.matches(_illust(totalView: 501)), isFalse);
    });

    test('多项条件必须同时满足', () {
      final filter = const IllustFilter(
        pages: PageCountRange(min: 2),
        views: CountRange(min: 100),
        bookmarks: CountRange(min: 10),
      );
      // 页数不够
      expect(
        filter.matches(
          _illust(pageCount: 1, totalView: 500, totalBookmarks: 50),
        ),
        isFalse,
      );
      // 观看数不够
      expect(
        filter.matches(
          _illust(pageCount: 5, totalView: 99, totalBookmarks: 50),
        ),
        isFalse,
      );
      // 点赞数不够
      expect(
        filter.matches(
          _illust(pageCount: 5, totalView: 500, totalBookmarks: 9),
        ),
        isFalse,
      );
      // 全部满足
      expect(
        filter.matches(
          _illust(pageCount: 5, totalView: 500, totalBookmarks: 10),
        ),
        isTrue,
      );
    });
  });

  group('IllustFilter.normalized', () {
    test('上下界写反的那一项按不限处理', () {
      final filter = const IllustFilter(
        pages: PageCountRange(min: 10, max: 2),
        views: CountRange(min: 5),
      ).normalized();
      expect(filter.pages, const PageCountRange(min: 10, max: 0));
      expect(filter.views, const CountRange(min: 5));
    });

    test('写反的范围不会把列表筛成空的', () {
      final filter = const IllustFilter(
        pages: PageCountRange(min: 10, max: 2),
      ).normalized();
      expect(filter.matches(_illust(pageCount: 50)), isTrue);
    });
  });

  group('IllustFilter.isAny / activeCount', () {
    test('默认是不限', () {
      expect(IllustFilter.any.isAny, isTrue);
      expect(IllustFilter.any.activeCount, 0);
    });

    test('设了几项就数几项', () {
      const filter = IllustFilter(views: CountRange(min: 100));
      expect(filter.isAny, isFalse);
      expect(filter.activeCount, 1);
      expect(
        const IllustFilter(
          pages: PageCountRange(min: 2),
          bookmarks: CountRange(max: 50),
        ).activeCount,
        2,
      );
    });
  });

  group('存取', () {
    test('encode / decode 往返一致', () {
      const filter = IllustFilter(
        pages: PageCountRange(min: 2, max: 10),
        views: CountRange(min: 1000),
        bookmarks: CountRange(max: 500),
      );
      expect(IllustFilter.decode(filter.encode()), filter);
    });

    test('没存过就是不限', () {
      expect(IllustFilter.decode(null), IllustFilter.any);
      expect(IllustFilter.decode(''), IllustFilter.any);
    });

    test('坏数据不会崩，也不会筛出空白', () {
      expect(IllustFilter.decode('not json'), IllustFilter.any);
      expect(IllustFilter.decode('{"a":1}'), IllustFilter.any);
      expect(IllustFilter.decode('[1,2,3]'), IllustFilter.any);
    });

    test('存的值里上下界写反也能正常解析', () {
      final filter = IllustFilter.decode('[10,2,0,0,0,0]');
      expect(filter.pages, const PageCountRange(min: 10, max: 0));
    });
  });
}
