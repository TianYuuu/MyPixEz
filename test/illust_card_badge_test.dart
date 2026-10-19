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
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/models/illust.dart';

/// 用真实的反序列化路径造一个 [Illusts]，
/// 这样也顺带确认角标读的就是 `type` / `page_count` / `meta_pages`。
Illusts _illust({
  String type = 'illust',
  int pageCount = 1,
  int metaPages = 0,
}) {
  return Illusts.fromJson({
    'id': 1,
    'title': 'title',
    'type': type,
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
    'meta_pages': List.generate(
      metaPages,
      (i) => {
        'image_urls': {
          'square_medium': '',
          'medium': '',
          'large': '',
          'original': '',
        },
      },
    ),
    'total_view': 0,
    'total_bookmarks': 0,
    'is_bookmarked': false,
    'visible': true,
    'is_muted': false,
    'illust_ai_type': 0,
  });
}

String? _label(Illusts illusts) =>
    illustCardBadgeLabel(illusts, mangaLabel: '漫画');

void main() {
  group('缩略图角标', () {
    test('单页插画不标（标个 1 只是噪音）', () {
      expect(_label(_illust(pageCount: 1)), isNull);
    });

    test('多页插画标页数', () {
      expect(_label(_illust(pageCount: 3)), '3');
    });

    test('插画接口没给 meta_pages 时，仍然按 page_count 标', () {
      // 列表接口有时会省略 meta_pages，页数却还在；
      // 这正是旧实现（看 meta_pages.length）会漏标的情况。
      expect(_label(_illust(pageCount: 4, metaPages: 0)), '4');
    });

    test('漫画标类型 + 页数', () {
      expect(_label(_illust(type: 'manga', pageCount: 12)), '漫画 · 12');
    });

    test('单页漫画只标类型，不标 1', () {
      expect(_label(_illust(type: 'manga', pageCount: 1)), '漫画');
    });

    test('漫画的 meta_pages 与 page_count 不一致时以 page_count 为准', () {
      expect(
        _label(_illust(type: 'manga', pageCount: 9, metaPages: 2)),
        '漫画 · 9',
      );
    });

    test('动了画的页数是 1，跟插画一样不标', () {
      expect(_label(_illust(pageCount: 1, metaPages: 1)), isNull);
    });
  });
}
