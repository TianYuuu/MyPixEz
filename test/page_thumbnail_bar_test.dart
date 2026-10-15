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
import 'package:pixez/page/zoom/page_thumbnail_bar.dart';

const int _count = 30;
const double _extent = 48;
const double _viewport = 400;

double _offset(int index) => thumbnailScrollOffset(
      index: index,
      count: _count,
      itemExtent: _extent,
      viewportWidth: _viewport,
    );

int _center(double offset) => thumbnailIndexAtCenter(
      offset: offset,
      count: _count,
      itemExtent: _extent,
    );

void main() {
  group('thumbnailScrollOffset', () {
    test('第 1 张不需要滚动（两端留白让它本来就在正中）', () {
      expect(_offset(0), 0);
    });

    test('最后一张的偏移是 (count-1)*宽度', () {
      expect(_offset(_count - 1), closeTo((_count - 1) * _extent, 1e-9));
    });

    test('偏移与索引成正比', () {
      for (var i = 0; i < _count; i++) {
        expect(_offset(i), closeTo(i * _extent, 1e-9));
      }
    });

    test('偏移随索引单调不减，且永不越界', () {
      final maxOffset = (_count - 1) * _extent;
      double prev = -1;
      for (var i = 0; i < _count; i++) {
        final v = _offset(i);
        expect(v, greaterThanOrEqualTo(prev));
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(maxOffset + 1e-9));
        prev = v;
      }
    });

    test('非法输入回退到 0', () {
      expect(
        thumbnailScrollOffset(
            index: 0, count: 0, itemExtent: 48, viewportWidth: 400),
        0,
      );
      expect(
        thumbnailScrollOffset(
            index: 0, count: 10, itemExtent: 0, viewportWidth: 400),
        0,
      );
      expect(
        thumbnailScrollOffset(
            index: 0, count: 10, itemExtent: 48, viewportWidth: 0),
        0,
      );
    });

    test('只有一张图时不滚动', () {
      expect(
        thumbnailScrollOffset(
            index: 0, count: 1, itemExtent: 48, viewportWidth: 400),
        0,
      );
    });
  });

  group('thumbnailIndexAtCenter', () {
    test('偏移 0 时正中间就是第 1 张', () {
      expect(_center(0), 0);
    });

    test('偏移等于 i*宽度时，正中间就是第 i 张', () {
      for (var i = 0; i < _count; i++) {
        expect(_center(i * _extent), i, reason: 'offset=${i * _extent}');
      }
    });

    test('往回偏一点仍算同一张，过半才切到下一张', () {
      for (var i = 0; i + 1 < _count; i++) {
        // 不到半格：仍是第 i 张
        expect(_center(i * _extent + _extent * 0.49), i);
        // 超过半格：切到第 i+1 张
        expect(_center(i * _extent + _extent * 0.51), i + 1);
      }
    });

    test('越界会被夹到合法范围', () {
      expect(_center(-100), 0);
      expect(_center(999999), _count - 1);
    });

    test('非法输入回退到 0', () {
      expect(thumbnailIndexAtCenter(offset: 100, count: 0, itemExtent: 48), 0);
      expect(thumbnailIndexAtCenter(offset: 100, count: 10, itemExtent: 0), 0);
    });
  });

  group('缩略图尺寸与高度', () {
    test('高度按 3:4 推算，横条高度再加留白', () {
      expect(thumbnailHeightFor(48), closeTo(64, 1e-9));
      expect(thumbnailBarHeightFor(48), closeTo(76, 1e-9));
      // 尺寸调大，条也跟着变高
      expect(thumbnailBarHeightFor(96), greaterThan(thumbnailBarHeightFor(48)));
    });

    test('可选尺寸是递增的且不含非法值', () {
      final sizes = kThumbnailSizeOptions;
      expect(sizes, isNotEmpty);
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]));
      }
      expect(sizes, contains(kDefaultThumbnailSize.round()));
    });
  });

  /// 上面全是纯函数断言，模型错了会一起错。
  /// 这一组搭一个和真实控件同构的列表（带两端留白），实测位置关系。
  group('与 Flutter 真实滚动语义对齐', () {
    Future<Rect> pumpProbe(
      WidgetTester tester,
      ScrollController controller, {
      required bool reverse,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _viewport,
                height: 60,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pad = (constraints.maxWidth - _extent) / 2;
                    return ListView.builder(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      reverse: reverse,
                      itemExtent: _extent,
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      itemCount: _count,
                      itemBuilder: (c, i) => Text('i$i'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getRect(find.byType(ListView));
    }

    testWidgets('两端留白后，第 1 张天然落在正中（两个方向都成立）', (tester) async {
      for (final reverse in [false, true]) {
        final controller = ScrollController();
        final listRect = await pumpProbe(tester, controller, reverse: reverse);
        expect(controller.offset, 0);
        final r0 = tester.getRect(find.text('i0'));
        expect(
          r0.center.dx,
          closeTo(listRect.center.dx, 0.5),
          reason: 'reverse=$reverse 时第 1 张应在正中',
        );
      }
    });

    testWidgets('jumpTo 之后，正中间确实是指定的那张', (tester) async {
      for (final reverse in [false, true]) {
        final controller = ScrollController();
        final listRect = await pumpProbe(tester, controller, reverse: reverse);
        for (final index in [0, 1, 7, 15, 29]) {
          controller.jumpTo(thumbnailScrollOffset(
            index: index,
            count: _count,
            itemExtent: _extent,
            viewportWidth: listRect.width,
          ));
          await tester.pump();
          // 用真实渲染位置反推：谁的矩形盖住视口中心，谁就是居中的那张
          int? rendered;
          for (var i = 0; i < _count; i++) {
            final f = find.text('i$i');
            if (f.evaluate().isEmpty) continue;
            final r = tester.getRect(f);
            if (r.left <= listRect.center.dx && listRect.center.dx < r.right) {
              rendered = i;
              break;
            }
          }
          expect(rendered, index,
              reason: 'reverse=$reverse 想跳到第 $index 张，实际居中却是第 $rendered 张');
          expect(
            thumbnailIndexAtCenter(
              offset: controller.offset,
              count: _count,
              itemExtent: _extent,
            ),
            index,
            reason: 'reverse=$reverse 时公式算出的居中索引应等于 $index',
          );
        }
      }
    });

    testWidgets('为了第 1 张居中不需要往回滚（旧实现的问题）', (tester) async {
      final controller = ScrollController();
      await pumpProbe(tester, controller, reverse: true);
      expect(_offset(0), 0);
      expect(controller.offset, 0);
      final r0 = tester.getRect(find.text('i0'));
      expect(r0.left, greaterThan(0));
    });
  });
}
