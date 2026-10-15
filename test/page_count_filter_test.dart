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
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';

void main() {
  group('PageCountRange', () {
    test('默认不限，任何页数都通过', () {
      const range = PageCountRange.any;
      expect(range.isAny, isTrue);
      for (final count in [1, 2, 10, 999]) {
        expect(range.matches(count), isTrue);
      }
    });

    test('只设下界：页数大于等于下界才通过', () {
      const range = PageCountRange(min: 20);
      expect(range.matches(1), isFalse);
      expect(range.matches(19), isFalse);
      expect(range.matches(20), isTrue);
      expect(range.matches(1000), isTrue);
    });

    test('只设上界：页数小于等于上界才通过', () {
      const range = PageCountRange(max: 5);
      expect(range.matches(1), isTrue);
      expect(range.matches(5), isTrue);
      expect(range.matches(6), isFalse);
    });

    test('区间：两端都是闭区间', () {
      const range = PageCountRange(min: 10, max: 30);
      expect(range.matches(9), isFalse);
      expect(range.matches(10), isTrue);
      expect(range.matches(30), isTrue);
      expect(range.matches(31), isFalse);
    });

    test('单页作品也能被正常判定', () {
      expect(const PageCountRange(min: 2).matches(1), isFalse);
      expect(const PageCountRange(max: 1).matches(1), isTrue);
    });

    test('上下界写反时归一化成只保留下界，避免死区间', () {
      // min>max 会筛不出任何东西，normalized 把上界放开。
      final inverted = const PageCountRange(min: 30, max: 5).normalized();
      expect(inverted.min, 30);
      expect(inverted.max, 0);
      expect(inverted.matches(30), isTrue);
      expect(inverted.matches(29), isFalse);
    });

    test('正常范围归一化后不变', () {
      const range = PageCountRange(min: 5, max: 20);
      expect(range.normalized(), range);
      const noLimit = PageCountRange.any;
      expect(noLimit.normalized(), PageCountRange.any);
    });

    test('相等性与 hashCode 按上下界判断', () {
      expect(const PageCountRange(min: 3, max: 9),
          const PageCountRange(min: 3, max: 9));
      expect(const PageCountRange(min: 3, max: 9),
          isNot(const PageCountRange(min: 3, max: 10)));
      expect(const PageCountRange(min: 3).hashCode,
          const PageCountRange(min: 3).hashCode);
    });

    test('copyWith 可以只改一侧', () {
      const base = PageCountRange(min: 5, max: 10);
      expect(base.copyWith(min: 8), const PageCountRange(min: 8, max: 10));
      expect(base.copyWith(max: 20), const PageCountRange(min: 5, max: 20));
      expect(base.copyWith(), base);
    });

  });

  group('shouldFetchMoreForFilter', () {
    test('可见条目已经够多时不再拉取', () {
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 12,
          targetCount: 12,
          nextUrl: 'https://example/next',
          roundsDone: 0,
          maxRounds: 4,
        ),
        isFalse,
      );
    });

    test('条目不足且还有下一页时继续拉取', () {
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 3,
          targetCount: 12,
          nextUrl: 'https://example/next',
          roundsDone: 0,
          maxRounds: 4,
        ),
        isTrue,
      );
    });

    test('没有下一页地址时停止', () {
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 0,
          targetCount: 12,
          nextUrl: null,
          roundsDone: 0,
          maxRounds: 4,
        ),
        isFalse,
      );
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 0,
          targetCount: 12,
          nextUrl: '',
          roundsDone: 0,
          maxRounds: 4,
        ),
        isFalse,
      );
    });

    test('达到轮次上限就收手，避免筛得太严时无限请求', () {
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 0,
          targetCount: 12,
          nextUrl: 'https://example/next',
          roundsDone: 3,
          maxRounds: 4,
        ),
        isTrue,
      );
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 0,
          targetCount: 12,
          nextUrl: 'https://example/next',
          roundsDone: 4,
          maxRounds: 4,
        ),
        isFalse,
      );
    });

    test('空列表且没有更多结果时不会空转', () {
      expect(
        shouldFetchMoreForFilter(
          visibleCount: 0,
          targetCount: 12,
          nextUrl: null,
          roundsDone: 0,
          maxRounds: 4,
        ),
        isFalse,
      );
    });
  });
}
