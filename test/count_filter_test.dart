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
import 'package:pixez/page/search/count_filter.dart';

void main() {
  group('CountRange.matches', () {
    test('不限时任何数值都通过（含 0）', () {
      const range = CountRange.any;
      expect(range.isAny, isTrue);
      expect(range.matches(0), isTrue);
      expect(range.matches(1), isTrue);
      expect(range.matches(999999), isTrue);
    });

    test('只设下限', () {
      const range = CountRange(min: 1000);
      expect(range.matches(999), isFalse);
      expect(range.matches(1000), isTrue, reason: '边界值应当算通过');
      expect(range.matches(1001), isTrue);
      expect(range.matches(0), isFalse);
    });

    test('只设上限', () {
      const range = CountRange(max: 1000);
      expect(range.matches(1001), isFalse);
      expect(range.matches(1000), isTrue);
      expect(range.matches(0), isTrue);
    });

    test('同时设上下限', () {
      const range = CountRange(min: 100, max: 1000);
      expect(range.matches(99), isFalse);
      expect(range.matches(100), isTrue);
      expect(range.matches(500), isTrue);
      expect(range.matches(1000), isTrue);
      expect(range.matches(1001), isFalse);
    });

    test('用户想要的例子：观看数大于 1000', () {
      const range = CountRange(min: 1000);
      expect(range.matches(1001), isTrue);
      expect(range.matches(1000), isTrue);
      expect(range.matches(999), isFalse);
    });
  });

  group('CountRange.normalized', () {
    test('上下界写反时清掉上限，不会变成死区间', () {
      const range = CountRange(min: 5000, max: 100);
      final fixed = range.normalized();
      expect(fixed.min, 5000);
      expect(fixed.max, 0);
      // 修完之后至少还能筛出东西
      expect(fixed.matches(6000), isTrue);
      expect(fixed.matches(4000), isFalse);
    });

    test('正常的区间原样返回', () {
      const range = CountRange(min: 100, max: 500);
      expect(range.normalized(), range);
    });

    test('只有一个边界时不会误清', () {
      expect(const CountRange(min: 5000).normalized().min, 5000);
      expect(const CountRange(max: 5000).normalized().max, 5000);
    });
  });

  group('CountRange.copyWith / 相等性', () {
    test('copyWith 只改指定的那个边界', () {
      const range = CountRange(min: 100, max: 500);
      expect(range.copyWith(min: 200), const CountRange(min: 200, max: 500));
      expect(range.copyWith(max: 900), const CountRange(min: 100, max: 900));
      expect(range.copyWith(), range);
    });

    test('相同范围相等、hashCode 一致', () {
      expect(const CountRange(min: 1, max: 2), const CountRange(min: 1, max: 2));
      expect(
        const CountRange(min: 1, max: 2).hashCode,
        const CountRange(min: 1, max: 2).hashCode,
      );
      expect(
        const CountRange(min: 1, max: 2),
        isNot(const CountRange(min: 1, max: 3)),
      );
    });
  });

  group('parseCountInput（手填输入框的解析）', () {
    test('正常数字原样返回', () {
      expect(parseCountInput('1000'), 1000);
      expect(parseCountInput('0'), 0);
      expect(parseCountInput('123456'), 123456);
    });

    test('留空表示不限（0）', () {
      expect(parseCountInput(''), 0);
      expect(parseCountInput('   '), 0);
      expect(parseCountInput(null), 0);
    });

    test('前后空格会被忽略', () {
      expect(parseCountInput(' 1000 '), 1000);
      expect(parseCountInput('\t500\n'), 500);
    });

    test('非数字内容当作不限，不会崩', () {
      expect(parseCountInput('abc'), 0);
      expect(parseCountInput('1a'), 0);
      expect(parseCountInput('--5'), 0);
    });

    test('负数当作不限', () {
      expect(parseCountInput('-1'), 0);
      expect(parseCountInput('-1000'), 0);
    });

    test('解析结果能直接喂给 matches', () {
      // 用户填 "1000" 到 "-" 左边（下限），右边留空
      final range = CountRange(min: parseCountInput('1000'), max: parseCountInput(''));
      expect(range, const CountRange(min: 1000, max: 0));
      expect(range.matches(1001), isTrue);
      expect(range.matches(999), isFalse);
    });
  });
}
