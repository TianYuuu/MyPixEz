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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/page/zoom/page_thumbnail_grid.dart';

void main() {
  group('thumbnailGridRowHeight', () {
    test('按可用宽度、列数、间距推算行高', () {
      // 400 - 16(左右内边距) - 8*4(列间距) = 352，cell 宽 70.4
      // 70.4 / 0.72 + 8 = 105.78
      final h = thumbnailGridRowHeight(
        availableWidth: 400,
        columns: 5,
        spacing: 8,
        horizontalPadding: 8,
        aspectRatio: 0.72,
      );
      expect(h, closeTo(70.4 / 0.72 + 8, 1e-6));
    });

    test('列数越多行高越小', () {
      double h(int c) => thumbnailGridRowHeight(
            availableWidth: 400,
            columns: c,
            spacing: 8,
            horizontalPadding: 8,
            aspectRatio: 0.72,
          );
      expect(h(6), lessThan(h(5)));
      expect(h(5), lessThan(h(4)));
      expect(h(4), lessThan(h(3)));
    });

    test('宽度不足时返回 0，不产生负数行高', () {
      expect(
        thumbnailGridRowHeight(
          availableWidth: 10,
          columns: 8,
          spacing: 8,
          horizontalPadding: 8,
          aspectRatio: 0.72,
        ),
        0,
      );
    });

    test('非法参数返回 0', () {
      expect(
        thumbnailGridRowHeight(
          availableWidth: 400,
          columns: 0,
          spacing: 8,
          horizontalPadding: 8,
          aspectRatio: 0.72,
        ),
        0,
      );
      expect(
        thumbnailGridRowHeight(
          availableWidth: 400,
          columns: 5,
          spacing: 8,
          horizontalPadding: 8,
          aspectRatio: 0,
        ),
        0,
      );
    });
  });

  group('ThumbnailShape', () {
    test('默认是统一大小', () {
      expect(ThumbnailShape.fromValue(0), ThumbnailShape.uniform);
      // 越界值也要安全回退，不能崩
      expect(ThumbnailShape.fromValue(-1), ThumbnailShape.uniform);
      expect(ThumbnailShape.fromValue(99), ThumbnailShape.uniform);
    });

    test('1 表示按原图比例', () {
      expect(ThumbnailShape.fromValue(1), ThumbnailShape.originalRatio);
    });

    test('统一大小用 cover（铺满并裁切）', () {
      expect(ThumbnailShape.uniform.fit, BoxFit.cover);
    });

    test('按原图比例用 contain（完整显示，能看出横竖）', () {
      // 这条是关键：cover 会把横图裁成和竖图一样的形状，就看不出区别了。
      expect(ThumbnailShape.originalRatio.fit, BoxFit.contain);
      expect(
        ThumbnailShape.originalRatio.fit,
        isNot(ThumbnailShape.uniform.fit),
      );
    });
  });

  group('thumbnailGridHeight', () {
    test('展开页是 95% 屏高，不是全高', () {
      expect(thumbnailGridHeight(1000), closeTo(950, 1e-9));
      expect(thumbnailGridHeight(800), closeTo(760, 1e-9));
      // 比全高矮、但比 9 成高
      expect(thumbnailGridHeight(1000), lessThan(1000));
      expect(thumbnailGridHeight(1000), greaterThan(900));
    });
  });

  group('ThumbnailShape 的取值与切换', () {
    test('value 与 fromValue 能来回转换', () {
      for (final shape in ThumbnailShape.values) {
        expect(ThumbnailShape.fromValue(shape.value), shape);
      }
      expect(ThumbnailShape.uniform.value, 0);
      expect(ThumbnailShape.originalRatio.value, 1);
    });

    test('toggled 来回切换', () {
      expect(ThumbnailShape.uniform.toggled, ThumbnailShape.originalRatio);
      expect(
        ThumbnailShape.originalRatio.toggled,
        ThumbnailShape.uniform,
      );
      // 点两次回到原点
      expect(ThumbnailShape.uniform.toggled.toggled, ThumbnailShape.uniform);
    });
  });

  group('thumbnailGridInitialOffset', () {
    const columns = 5;
    const rowHeight = 100.0;

    double off(int index) => thumbnailGridInitialOffset(
          index: index,
          columns: columns,
          rowHeight: rowHeight,
        );

    test('第一行不需要滚动', () {
      for (var i = 0; i < columns; i++) {
        expect(off(i), 0, reason: '第 $i 张在第一行，不该滚动');
      }
    });

    test('同一行的不同格子偏移相同', () {
      expect(off(5), off(9));
      expect(off(10), off(14));
    });

    test('每往下一行多滚一行的高度（首行除外）', () {
      // 第 1 行（index 5..9）→ 1*100 - 50 = 50
      expect(off(5), closeTo(50, 1e-9));
      // 第 2 行 → 2*100 - 50 = 150
      expect(off(10), closeTo(150, 1e-9));
      // 第 3 行 → 250
      expect(off(15), closeTo(250, 1e-9));
    });

    test('偏移随索引单调不减', () {
      var prev = 0.0;
      for (var i = 0; i < 100; i++) {
        final v = off(i);
        expect(v, greaterThanOrEqualTo(prev));
        prev = v;
      }
    });

    test('永远不为负', () {
      for (var i = 0; i < 50; i++) {
        expect(off(i), greaterThanOrEqualTo(0));
      }
    });

    test('非法参数回退到 0', () {
      expect(
        thumbnailGridInitialOffset(index: 5, columns: 0, rowHeight: 100),
        0,
      );
      expect(
        thumbnailGridInitialOffset(index: 5, columns: 5, rowHeight: 0),
        0,
      );
      expect(
        thumbnailGridInitialOffset(index: -1, columns: 5, rowHeight: 100),
        0,
      );
    });

    test('最后一行的偏移足够让该行进入视野', () {
      const total = 97;
      final lastIndex = total - 1;
      final row = lastIndex ~/ columns;
      final offset = off(lastIndex);
      // 当前行顶端距离列表顶部 = row*rowHeight，
      // 偏移至少要让它落在视口内（这里就算行高本身）。
      expect(offset, lessThanOrEqualTo(row * rowHeight));
      expect(offset + rowHeight, greaterThan(row * rowHeight));
    });
  });
}
