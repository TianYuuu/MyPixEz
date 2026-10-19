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
/// 顺便确认筛选读的就是 `page_count` / `total_view` / `total_bookmarks` / `tags`。
Illusts _illust({
  int pageCount = 1,
  int totalView = 0,
  int totalBookmarks = 0,
  List<Map<String, dynamic>> tags = const [],
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
    'tags': tags,
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

/// pixiv 的 tag：原文 + 可选的本地化译名。
Map<String, dynamic> _tag(String name, [String? translated]) => {
  'name': name,
  'translated_name': translated,
};

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

    test('标签：命中原文', () {
      const filter = IllustFilter(tags: ['初音ミク']);
      expect(filter.matches(_illust(tags: [_tag('初音ミク', '初音未来')])), isTrue);
    });

    test('标签：输中文译名也能命中', () {
      const filter = IllustFilter(tags: ['初音未来']);
      expect(filter.matches(_illust(tags: [_tag('初音ミク', '初音未来')])), isTrue);
    });

    test('标签：没有译名时只看原文', () {
      const filter = IllustFilter(tags: ['初音未来']);
      expect(filter.matches(_illust(tags: [_tag('初音ミク')])), isFalse);
    });

    test('标签：大小写不敏感', () {
      const filter = IllustFilter(tags: ['blue archive']);
      expect(filter.matches(_illust(tags: [_tag('Blue Archive')])), isTrue);
    });

    test('标签：包含即可，不必完全相等', () {
      const filter = IllustFilter(tags: ['初音']);
      expect(filter.matches(_illust(tags: [_tag('初音ミク')])), isTrue);
    });

    test('标签：多个之间是"或"', () {
      const filter = IllustFilter(tags: ['東方Project', '初音ミク']);
      expect(filter.matches(_illust(tags: [_tag('初音ミク')])), isTrue);
      expect(filter.matches(_illust(tags: [_tag('東方Project')])), isTrue);
      expect(filter.matches(_illust(tags: [_tag('原神')])), isFalse);
    });

    test('标签：作品没有任何标签时被筛掉', () {
      const filter = IllustFilter(tags: ['初音ミク']);
      expect(filter.matches(_illust()), isFalse);
    });

    test('标签和数量条件要同时满足', () {
      const filter = IllustFilter(
        tags: ['初音ミク'],
        bookmarks: CountRange(min: 100),
      );
      expect(
        filter.matches(_illust(tags: [_tag('初音ミク')], totalBookmarks: 100)),
        isTrue,
      );
      expect(
        filter.matches(_illust(tags: [_tag('初音ミク')], totalBookmarks: 99)),
        isFalse,
      );
      expect(
        filter.matches(_illust(tags: [_tag('原神')], totalBookmarks: 500)),
        isFalse,
      );
    });
  });

  group('IllustFilter.matchesAnyIllust（筛作者用）', () {
    const filter = IllustFilter(
      pages: PageCountRange(min: 2),
      bookmarks: CountRange(min: 100),
    );

    test('近期作品里有一张满足就留下', () {
      final illusts = [
        _illust(pageCount: 1, totalBookmarks: 0), // 这张不合格
        _illust(pageCount: 3, totalBookmarks: 500), // 这张合格
      ];
      expect(filter.matchesAnyIllust(illusts), isTrue);
    });

    test('一张都不合格就剔除', () {
      final illusts = [
        _illust(pageCount: 1, totalBookmarks: 0),
        _illust(pageCount: 1, totalBookmarks: 99),
        _illust(pageCount: 1, totalBookmarks: 1000), // 点赞够但页数不够
      ];
      expect(filter.matchesAnyIllust(illusts), isFalse);
    });

    test('没有作品（比如只写小说的作者）时保留', () {
      expect(filter.matchesAnyIllust(const []), isTrue);
    });

    test('条件不限时全都保留', () {
      expect(IllustFilter.any.matchesAnyIllust(const []), isTrue);
      expect(
        IllustFilter.any.matchesAnyIllust([_illust(pageCount: 1)]),
        isTrue,
      );
    });

    test('标签条件对作者同样生效', () {
      const tagFilter = IllustFilter(tags: ['初音ミク']);
      expect(
        tagFilter.matchesAnyIllust([
          _illust(tags: [_tag('原神')]),
          _illust(tags: [_tag('初音ミク', '初音未来')]),
        ]),
        isTrue,
      );
      expect(
        tagFilter.matchesAnyIllust([_illust(tags: [_tag('原神')])]),
        isFalse,
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

    test('标签会去掉空白项和重复项', () {
      final filter = const IllustFilter(
        tags: [' 初音未来 ', '初音未来', '', '  ', '初音ミク'],
      ).normalized();
      expect(filter.tags, ['初音未来', '初音ミク']);
    });

    test('标签去重忽略大小写，但保留原始写法', () {
      final filter = const IllustFilter(
        tags: ['Blue Archive', 'blue archive'],
      ).normalized();
      expect(filter.tags, ['Blue Archive']);
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

    test('只设标签也算筛选中，且只算一项', () {
      const filter = IllustFilter(tags: ['初音ミク', '東方Project']);
      expect(filter.isAny, isFalse);
      expect(filter.activeCount, 1);
    });
  });

  group('存取', () {
    test('encode / decode 往返一致', () {
      const filter = IllustFilter(
        pages: PageCountRange(min: 2, max: 10),
        views: CountRange(min: 1000),
        bookmarks: CountRange(max: 500),
        tags: ['初音未来', 'Blue Archive'],
      );
      expect(IllustFilter.decode(filter.encode()), filter);
    });

    test('只有标签也能存下来', () {
      const filter = IllustFilter(tags: ['初音ミク']);
      final decoded = IllustFilter.decode(filter.encode());
      expect(decoded.tags, ['初音ミク']);
      expect(decoded.isAny, isFalse);
    });

    test('没存过就是不限', () {
      expect(IllustFilter.decode(null), IllustFilter.any);
      expect(IllustFilter.decode(''), IllustFilter.any);
    });

    test('坏数据不会崩，也不会筛出空白', () {
      expect(IllustFilter.decode('not json'), IllustFilter.any);
      expect(IllustFilter.decode('{"a":1}'), IllustFilter.any);
      expect(IllustFilter.decode('[1,2,3]'), IllustFilter.any);
      // 键在但值坏掉
      expect(IllustFilter.decode('{"pages":"x","tags":42}'), IllustFilter.any);
    });

    test('老格式（六个数字的数组）仍然读得出来', () {
      final filter = IllustFilter.decode('[10,2,0,0,0,0]');
      expect(filter.pages, const PageCountRange(min: 10, max: 0));
      expect(filter.tags, isEmpty);
    });

    test('存的值里上下界写反也能正常解析', () {
      final filter = IllustFilter.decode(
        '{"pages":[10,2],"views":[0,0],"bookmarks":[0,0],"tags":[]}',
      );
      expect(filter.pages, const PageCountRange(min: 10, max: 0));
    });
  });
}
