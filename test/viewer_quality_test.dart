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
import 'package:pixez/page/zoom/viewer_quality.dart';

const _full = ViewerUrls(
  medium: 'M',
  large: 'L',
  original: 'O',
);

void main() {
  group('settledUrlOf', () {
    test('选大图就用大图，选原图才用原图', () {
      // 这两条是核心：preferOriginal 必须真的起作用，
      // 否则"大图"这个画质设置会形同虚设。
      expect(settledUrlOf(_full, preferOriginal: false), 'L');
      expect(settledUrlOf(_full, preferOriginal: true), 'O');
    });

    test('缺原图时退回大图', () {
      const urls = ViewerUrls(medium: 'M', large: 'L');
      expect(settledUrlOf(urls, preferOriginal: true), 'L');
      expect(settledUrlOf(urls, preferOriginal: false), 'L');
    });

    test('缺大图时，选大图也退回可用的那张', () {
      const urls = ViewerUrls(medium: 'M', original: 'O');
      expect(settledUrlOf(urls, preferOriginal: false), 'O');
      expect(settledUrlOf(urls, preferOriginal: true), 'O');
    });

    test('只剩缩略图时用它兜底', () {
      const urls = ViewerUrls(medium: 'M');
      expect(settledUrlOf(urls, preferOriginal: false), 'M');
      expect(settledUrlOf(urls, preferOriginal: true), 'M');
    });

    test('全空时返回空串而不是抛异常', () {
      const urls = ViewerUrls();
      expect(settledUrlOf(urls, preferOriginal: false), '');
      expect(settledUrlOf(urls, preferOriginal: true), '');
    });

    test('空字符串按缺失处理', () {
      const urls = ViewerUrls(medium: '', large: 'L', original: '');
      expect(settledUrlOf(urls, preferOriginal: true), 'L');
    });
  });

  group('previewUrlOf', () {
    test('一律优先缩略图（它才是已经缓存的）', () {
      expect(previewUrlOf(_full), 'M');
    });

    test('没有缩略图时退回大图，再退回原图', () {
      expect(previewUrlOf(const ViewerUrls(large: 'L', original: 'O')), 'L');
      expect(previewUrlOf(const ViewerUrls(original: 'O')), 'O');
    });

    test('全空时返回空串', () {
      expect(previewUrlOf(const ViewerUrls()), '');
    });
  });

  group('viewerUrlFor', () {
    test('停稳的当前页用最终画质', () {
      expect(
        viewerUrlFor(_full,
            preferOriginal: false, isCurrent: true, currentIsFinal: true),
        'L',
      );
      expect(
        viewerUrlFor(_full,
            preferOriginal: true, isCurrent: true, currentIsFinal: true),
        'O',
      );
    });

    test('当前页还没停稳时用缩略图占位（关键：避免黑屏）', () {
      for (final preferOriginal in [false, true]) {
        expect(
          viewerUrlFor(_full,
              preferOriginal: preferOriginal,
              isCurrent: true,
              currentIsFinal: false),
          'M',
        );
      }
    });

    test('非当前页一律用缩略图占位', () {
      // 滑动途中被拖进来的那一页就靠这条立刻出画面。
      for (final currentIsFinal in [false, true]) {
        expect(
          viewerUrlFor(_full,
              preferOriginal: true,
              isCurrent: false,
              currentIsFinal: currentIsFinal),
          'M',
        );
      }
    });

    test('任何组合都不会返回空串（全都有值的情况下）', () {
      for (final preferOriginal in [false, true]) {
        for (final isCurrent in [false, true]) {
          for (final currentIsFinal in [false, true]) {
            expect(
              viewerUrlFor(_full,
                  preferOriginal: preferOriginal,
                  isCurrent: isCurrent,
                  currentIsFinal: currentIsFinal),
              isNotEmpty,
            );
          }
        }
      }
    });
  });

  group('prefetchTargets', () {
    List<String?> urls(int n) => List<String?>.generate(n, (i) => 'L$i');

    test('从当前页往后再取 count 张', () {
      expect(
        prefetchTargets(
            currentIndex: 0, prefetchCount: 3, pageCount: 10, largeUrls: urls(10)),
        [1, 2, 3],
      );
    });

    test('0 表示关闭', () {
      expect(
        prefetchTargets(
            currentIndex: 0, prefetchCount: 0, pageCount: 10, largeUrls: urls(10)),
        isEmpty,
      );
    });

    test('不越界：临近末尾时只取还存在的页', () {
      expect(
        prefetchTargets(
            currentIndex: 7, prefetchCount: 5, pageCount: 10, largeUrls: urls(10)),
        [8, 9],
      );
      expect(
        prefetchTargets(
            currentIndex: 9, prefetchCount: 5, pageCount: 10, largeUrls: urls(10)),
        isEmpty,
      );
    });

    test('单页作品不预加载', () {
      expect(
        prefetchTargets(
            currentIndex: 0, prefetchCount: 5, pageCount: 1, largeUrls: urls(1)),
        isEmpty,
      );
    });

    test('跳过没有大图地址的页，但不中断后面的', () {
      final u = urls(10);
      u[2] = null;
      u[3] = '';
      expect(
        prefetchTargets(
            currentIndex: 0, prefetchCount: 5, pageCount: 10, largeUrls: u),
        [1, 4, 5],
      );
    });

    test('结果始终是递增的合法索引', () {
      for (var current = 0; current < 12; current++) {
        final r = prefetchTargets(
            currentIndex: current,
            prefetchCount: 6,
            pageCount: 12,
            largeUrls: urls(12));
        for (var i = 0; i < r.length; i++) {
          expect(r[i], greaterThan(current));
          expect(r[i], lessThan(12));
          if (i > 0) expect(r[i], greaterThan(r[i - 1]));
        }
      }
    });

    test('不重复预加载当前页自己', () {
      final r = prefetchTargets(
          currentIndex: 4, prefetchCount: 6, pageCount: 12, largeUrls: urls(12));
      expect(r, isNot(contains(4)));
    });
  });
}
