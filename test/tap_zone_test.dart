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

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/page/zoom/tap_zone.dart';

/// 屏幕尺寸，方便按比例算坐标。
const Size _screen = Size(400, 800);

/// 按归一化坐标取点击位置。
Offset _at(double x, double y) => Offset(_screen.width * x, _screen.height * y);

TapZoneAction _resolve(
  TapZoneMode mode,
  double x,
  double y, {
  TapZoneInvert invert = TapZoneInvert.none,
}) => resolveTapZone(mode, _at(x, y), _screen, invert: invert);

/// 把某个布局的分区压成便于比较的字符串集合。
Set<String> _shape(TapZoneMode mode, {TapZoneInvert invert = TapZoneInvert.none}) =>
    zonesOf(mode, invert: invert)
        .map((z) => '${z.action.name}:${z.rect.left},${z.rect.top},'
            '${z.rect.right},${z.rect.bottom}')
        .toSet();

/// 某个布局在某个方向上的边界值，用来跳过恰好压在边线上的采样点。
Set<double> _boundaries(TapZoneMode mode, TapZoneInvert invert) {
  return {
    for (final z in zonesOf(mode, invert: invert)) ...[z.rect.left, z.rect.right],
  };
}

bool _onBoundary(double v, Set<double> boundaries) =>
    boundaries.any((b) => (v - b).abs() < 1e-6);

/// 逐边做容差比较：1-0.7 这类运算在浮点下不保证与原字面量逐位相等。
void _expectRect(Rect actual, double l, double t, double r, double b) {
  expect(actual.left, moreOrLessEquals(l, epsilon: 1e-12));
  expect(actual.top, moreOrLessEquals(t, epsilon: 1e-12));
  expect(actual.right, moreOrLessEquals(r, epsilon: 1e-12));
  expect(actual.bottom, moreOrLessEquals(b, epsilon: 1e-12));
}

void main() {
  group('TapZoneModeValue.fromValue', () {
    test('空值与越界值回退到 L 型', () {
      expect(TapZoneModeValue.fromValue(null), TapZoneMode.lShape);
      expect(TapZoneModeValue.fromValue(-1), TapZoneMode.lShape);
      expect(TapZoneModeValue.fromValue(999), TapZoneMode.lShape);
    });

    test('合法值原样还原，且与 value 互逆', () {
      for (final mode in TapZoneMode.values) {
        expect(TapZoneModeValue.fromValue(mode.value), mode);
      }
    });
  });

  group('TapZoneInvertValue.fromValue', () {
    test('空值与越界值回退到不反转', () {
      expect(TapZoneInvertValue.fromValue(null), TapZoneInvert.none);
      expect(TapZoneInvertValue.fromValue(-1), TapZoneInvert.none);
      expect(TapZoneInvertValue.fromValue(999), TapZoneInvert.none);
    });

    test('合法值原样还原，且与 value 互逆', () {
      for (final invert in TapZoneInvert.values) {
        expect(TapZoneInvertValue.fromValue(invert.value), invert);
      }
    });

    test('isHorizontal / isVertical 覆盖双向', () {
      expect(TapZoneInvert.none.isHorizontal, isFalse);
      expect(TapZoneInvert.none.isVertical, isFalse);
      expect(TapZoneInvert.horizontal.isHorizontal, isTrue);
      expect(TapZoneInvert.horizontal.isVertical, isFalse);
      expect(TapZoneInvert.vertical.isHorizontal, isFalse);
      expect(TapZoneInvert.vertical.isVertical, isTrue);
      expect(TapZoneInvert.both.isHorizontal, isTrue);
      expect(TapZoneInvert.both.isVertical, isTrue);
    });
  });

  group('分区必须完整覆盖屏幕', () {
    test('任何布局与任何反转方式下，面积之和都等于整屏', () {
      for (final mode in TapZoneMode.values) {
        for (final invert in TapZoneInvert.values) {
          var area = 0.0;
          for (final zone in zonesOf(mode, invert: invert)) {
            area += zone.rect.width * zone.rect.height;
          }
          expect(
            area,
            closeTo(1.0, 1e-9),
            reason: '$mode + $invert 的分区面积之和应为 1',
          );
        }
      }
    });

    test('任意采样点都能命中一个分区，不会返回空', () {
      for (final mode in TapZoneMode.values) {
        for (final invert in TapZoneInvert.values) {
          for (double x = 0.01; x < 1.0; x += 0.07) {
            for (double y = 0.01; y < 1.0; y += 0.07) {
              expect(
                _resolve(mode, x, y, invert: invert),
                isA<TapZoneAction>(),
                reason: '$mode + $invert 在 ($x, $y) 处应有动作',
              );
            }
          }
        }
      }
    });
  });

  group('L 型 = Mihon LNavigation', () {
    const mode = TapZoneMode.lShape;

    test('几何值与 Mihon 源码一致', () {
      expect(_shape(mode), {
        // Mihon: PREV (0, 0.33, 0.33, 0.66) 与 PREV (0, 0, 1, 0.33)
        'previous:0.0,0.0,1.0,0.3333333333333333',
        'previous:0.0,0.3333333333333333,0.3333333333333333,'
            '0.6666666666666666',
        // Mihon: NEXT (0.66, 0.33, 1, 0.66) 与 NEXT (0, 0.66, 1, 1)
        'next:0.6666666666666666,0.3333333333333333,1.0,'
            '0.6666666666666666',
        'next:0.0,0.6666666666666666,1.0,1.0',
        // Mihon 未覆盖的中心区 → MENU
        'menu:0.3333333333333333,0.3333333333333333,0.6666666666666666,'
            '0.6666666666666666',
      });
    });

    test('顶栏（全宽）是上一张', () {
      expect(_resolve(mode, 0.10, 0.15), TapZoneAction.previous);
      expect(_resolve(mode, 0.50, 0.15), TapZoneAction.previous);
      expect(_resolve(mode, 0.90, 0.15), TapZoneAction.previous);
    });

    test('底栏（全宽）是下一张', () {
      expect(_resolve(mode, 0.10, 0.85), TapZoneAction.next);
      expect(_resolve(mode, 0.50, 0.85), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.85), TapZoneAction.next);
    });

    test('中间带左 1/3 是上一张（与顶栏拼成开口朝右下的 L）', () {
      expect(_resolve(mode, 0.10, 0.50), TapZoneAction.previous);
      expect(_resolve(mode, 0.30, 0.60), TapZoneAction.previous);
    });

    test('中间带右 1/3 是下一张（与底栏拼成开口朝左上的 L）', () {
      expect(_resolve(mode, 0.90, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.70, 0.40), TapZoneAction.next);
    });

    test('中间带正中是开关界面', () {
      expect(_resolve(mode, 0.50, 0.50), TapZoneAction.menu);
      expect(_resolve(mode, 0.45, 0.40), TapZoneAction.menu);
    });

    test('左上角是上一张、右下角是下一张', () {
      expect(_resolve(mode, 0.05, 0.05), TapZoneAction.previous);
      expect(_resolve(mode, 0.95, 0.95), TapZoneAction.next);
    });
  });

  group('Kindle 型 = Mihon KindlishNavigation', () {
    const mode = TapZoneMode.kindlish;

    test('几何值与 Mihon 源码一致', () {
      expect(_shape(mode), {
        // Mihon: NEXT (0.33, 0.33, 1, 1)
        'next:0.3333333333333333,0.3333333333333333,1.0,1.0',
        // Mihon: PREV (0, 0.33, 0.33, 1)
        'previous:0.0,0.3333333333333333,0.3333333333333333,1.0',
        // Mihon 未覆盖的上方 1/3 → MENU
        'menu:0.0,0.0,1.0,0.3333333333333333',
      });
    });

    test('上方 1/3 是开关界面', () {
      expect(_resolve(mode, 0.10, 0.15), TapZoneAction.menu);
      expect(_resolve(mode, 0.50, 0.15), TapZoneAction.menu);
      expect(_resolve(mode, 0.90, 0.15), TapZoneAction.menu);
    });

    test('下方左 1/3 是上一张', () {
      expect(_resolve(mode, 0.10, 0.50), TapZoneAction.previous);
      expect(_resolve(mode, 0.30, 0.90), TapZoneAction.previous);
    });

    test('下方其余（右 2/3）是下一张，比上一张区域大得多', () {
      expect(_resolve(mode, 0.50, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.50, 0.90), TapZoneAction.next);
    });
  });

  group('边缘 = Mihon EdgeNavigation', () {
    const mode = TapZoneMode.edge;

    test('几何值与 Mihon 源码一致', () {
      expect(_shape(mode), {
        // Mihon: NEXT (0, 0, 0.33, 1) 与 NEXT (0.66, 0, 1, 1)
        'next:0.0,0.0,0.3333333333333333,1.0',
        'next:0.6666666666666666,0.0,1.0,1.0',
        // Mihon: PREV (0.33, 0.66, 0.66, 1)
        'previous:0.3333333333333333,0.6666666666666666,'
            '0.6666666666666666,1.0',
        // Mihon 未覆盖的中间偏上 → MENU
        'menu:0.3333333333333333,0.0,0.6666666666666666,'
            '0.6666666666666666',
      });
    });

    test('左右两条竖边都是下一张（Mihon 原样设计）', () {
      expect(_resolve(mode, 0.10, 0.20), TapZoneAction.next);
      expect(_resolve(mode, 0.10, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.10, 0.90), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.20), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.90), TapZoneAction.next);
    });

    test('只有底部正中间是上一张', () {
      expect(_resolve(mode, 0.50, 0.90), TapZoneAction.previous);
      expect(_resolve(mode, 0.40, 0.80), TapZoneAction.previous);
    });

    test('中间偏上是开关界面', () {
      expect(_resolve(mode, 0.50, 0.50), TapZoneAction.menu);
      expect(_resolve(mode, 0.50, 0.10), TapZoneAction.menu);
      expect(_resolve(mode, 0.40, 0.30), TapZoneAction.menu);
    });
  });

  group('左右 = Mihon RightAndLeftNavigation', () {
    const mode = TapZoneMode.rightAndLeft;

    test('几何值与 Mihon 源码一致', () {
      expect(_shape(mode), {
        // Mihon: LEFT (0, 0, 0.33, 1) → 左起阅读即上一张
        'previous:0.0,0.0,0.3333333333333333,1.0',
        // Mihon: RIGHT (0.66, 0, 1, 1) → 下一张
        'next:0.6666666666666666,0.0,1.0,1.0',
        // Mihon 未覆盖的中间 1/3 → MENU
        'menu:0.3333333333333333,0.0,0.6666666666666666,1.0',
      });
    });

    test('左 1/3 上一张、右 1/3 下一张', () {
      expect(_resolve(mode, 0.10, 0.10), TapZoneAction.previous);
      expect(_resolve(mode, 0.10, 0.50), TapZoneAction.previous);
      expect(_resolve(mode, 0.90, 0.50), TapZoneAction.next);
      expect(_resolve(mode, 0.90, 0.90), TapZoneAction.next);
    });

    test('中间 1/3 是开关界面（上下通栏）', () {
      expect(_resolve(mode, 0.50, 0.05), TapZoneAction.menu);
      expect(_resolve(mode, 0.50, 0.50), TapZoneAction.menu);
      expect(_resolve(mode, 0.50, 0.95), TapZoneAction.menu);
    });
  });

  group('禁用', () {
    test('任何位置都不翻页', () {
      expect(_resolve(TapZoneMode.disabled, 0.05, 0.50), TapZoneAction.none);
      expect(_resolve(TapZoneMode.disabled, 0.50, 0.50), TapZoneAction.none);
      expect(_resolve(TapZoneMode.disabled, 0.95, 0.50), TapZoneAction.none);
    });

    test('反转后依然不翻页', () {
      for (final invert in TapZoneInvert.values) {
        expect(
          _resolve(TapZoneMode.disabled, 0.05, 0.50, invert: invert),
          TapZoneAction.none,
        );
        expect(
          _resolve(TapZoneMode.disabled, 0.95, 0.50, invert: invert),
          TapZoneAction.none,
        );
      }
    });
  });

  group('反转 = Mihon TappingInvertMode', () {
    test('rect 翻转公式与 Mihon RectF.invert 一致', () {
      final rect = Rect.fromLTRB(0.2, 0.1, 0.6, 0.7);
      _expectRect(invertRect(rect, TapZoneInvert.none), 0.2, 0.1, 0.6, 0.7);
      // horizontal -> RectF(1-right, top, 1-left, bottom)
      _expectRect(
        invertRect(rect, TapZoneInvert.horizontal),
        0.4,
        0.1,
        0.8,
        0.7,
      );
      // vertical -> RectF(left, 1-bottom, right, 1-top)
      _expectRect(
        invertRect(rect, TapZoneInvert.vertical),
        0.2,
        0.3,
        0.6,
        0.9,
      );
      // both -> RectF(1-right, 1-bottom, 1-left, 1-top)
      _expectRect(invertRect(rect, TapZoneInvert.both), 0.4, 0.3, 0.8, 0.9);
    });

    test('整屏翻转后仍是整屏', () {
      final full = Rect.fromLTRB(0, 0, 1, 1);
      for (final invert in TapZoneInvert.values) {
        expect(invertRect(full, invert), full);
      }
    });

    test('水平翻转两次回到原样', () {
      for (final zone in zonesOf(TapZoneMode.lShape)) {
        final twice = invertRect(
          invertRect(zone.rect, TapZoneInvert.horizontal),
          TapZoneInvert.horizontal,
        );
        expect(twice.left, moreOrLessEquals(zone.rect.left, epsilon: 1e-12));
        expect(twice.top, moreOrLessEquals(zone.rect.top, epsilon: 1e-12));
        expect(twice.right, moreOrLessEquals(zone.rect.right, epsilon: 1e-12));
        expect(
          twice.bottom,
          moreOrLessEquals(zone.rect.bottom, epsilon: 1e-12),
        );
      }
    });

    test('水平：点 (1-x, y) 与不反转时点 (x, y) 动作相同', () {
      for (final mode in TapZoneMode.values) {
        final bounds = _boundaries(mode, TapZoneInvert.horizontal);
        for (double x = 0.01; x < 1.0; x += 0.07) {
          if (_onBoundary(x, bounds) || _onBoundary(1 - x, bounds)) continue;
          for (double y = 0.01; y < 1.0; y += 0.07) {
            expect(
              _resolve(mode, 1 - x, y, invert: TapZoneInvert.horizontal),
              _resolve(mode, x, y),
              reason: '$mode 在 x=$x 处水平反转应互为对调',
            );
          }
        }
      }
    });

    test('垂直：点 (x, 1-y) 与不反转时点 (x, y) 动作相同', () {
      for (final mode in TapZoneMode.values) {
        final bounds = <double>{1 / 3, 2 / 3};
        for (double x = 0.01; x < 1.0; x += 0.07) {
          if (_onBoundary(x, bounds)) continue;
          for (double y = 0.01; y < 1.0; y += 0.07) {
            if (_onBoundary(y, bounds) || _onBoundary(1 - y, bounds)) continue;
            expect(
              _resolve(mode, x, 1 - y, invert: TapZoneInvert.vertical),
              _resolve(mode, x, y),
              reason: '$mode 在 y=$y 处垂直反转应互为对调',
            );
          }
        }
      }
    });

    test('双向：点 (1-x, 1-y) 与不反转时点 (x, y) 动作相同', () {
      for (final mode in TapZoneMode.values) {
        final bounds = _boundaries(mode, TapZoneInvert.both);
        final all = <double>{...bounds, 1 / 3, 2 / 3};
        for (double x = 0.01; x < 1.0; x += 0.07) {
          if (_onBoundary(x, all) || _onBoundary(1 - x, all)) continue;
          for (double y = 0.01; y < 1.0; y += 0.07) {
            if (_onBoundary(y, all) || _onBoundary(1 - y, all)) continue;
            expect(
              _resolve(mode, 1 - x, 1 - y, invert: TapZoneInvert.both),
              _resolve(mode, x, y),
              reason: '$mode 在 ($x, $y) 处双向反转应等于旋转 180 度',
            );
          }
        }
      }
    });

    group('L 型', () {
      const mode = TapZoneMode.lShape;

      test('水平：中间带左右两臂互换，顶栏底栏不受影响', () {
        expect(
          _resolve(mode, 0.50, 0.15, invert: TapZoneInvert.horizontal),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.85, invert: TapZoneInvert.horizontal),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.10, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.90, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.menu,
        );
      });

      test('垂直：顶栏与底栏互换，中间带不受影响', () {
        expect(
          _resolve(mode, 0.50, 0.15, invert: TapZoneInvert.vertical),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.50, 0.85, invert: TapZoneInvert.vertical),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.10, 0.50, invert: TapZoneInvert.vertical),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.90, 0.50, invert: TapZoneInvert.vertical),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.50, 0.50, invert: TapZoneInvert.vertical),
          TapZoneAction.menu,
        );
      });

      test('双向：左上角变成下一张、右下角变成上一张', () {
        expect(
          _resolve(mode, 0.05, 0.05, invert: TapZoneInvert.both),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.95, 0.95, invert: TapZoneInvert.both),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.50, invert: TapZoneInvert.both),
          TapZoneAction.menu,
        );
      });
    });

    group('Kindle 型', () {
      const mode = TapZoneMode.kindlish;

      test('垂直：开关界面从顶部挪到底部', () {
        expect(
          _resolve(mode, 0.50, 0.15, invert: TapZoneInvert.vertical),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.10, 0.15, invert: TapZoneInvert.vertical),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.85, invert: TapZoneInvert.vertical),
          TapZoneAction.menu,
        );
      });
    });

    group('边缘', () {
      const mode = TapZoneMode.edge;

      test('水平：本身左右对称，等于没反转', () {
        final bounds = _boundaries(mode, TapZoneInvert.horizontal);
        for (double x = 0.01; x < 1.0; x += 0.07) {
          if (_onBoundary(x, bounds)) continue;
          for (double y = 0.01; y < 1.0; y += 0.07) {
            expect(
              _resolve(mode, x, y, invert: TapZoneInvert.horizontal),
              _resolve(mode, x, y),
              reason: '边缘布局在 ($x, $y) 处水平反转前后应一致',
            );
          }
        }
      });

      test('垂直：上一张从底部挪到顶部，中间开关界面挪到底部', () {
        expect(
          _resolve(mode, 0.50, 0.15, invert: TapZoneInvert.vertical),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.85, invert: TapZoneInvert.vertical),
          TapZoneAction.menu,
        );
        // 左右两条竖边是全高，垂直翻转后不变
        expect(
          _resolve(mode, 0.10, 0.50, invert: TapZoneInvert.vertical),
          TapZoneAction.next,
        );
      });
    });

    group('左右', () {
      const mode = TapZoneMode.rightAndLeft;

      test('水平：左 1/3 变下一张、右 1/3 变上一张', () {
        expect(
          _resolve(mode, 0.10, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.next,
        );
        expect(
          _resolve(mode, 0.90, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.previous,
        );
        expect(
          _resolve(mode, 0.50, 0.50, invert: TapZoneInvert.horizontal),
          TapZoneAction.menu,
        );
      });

      test('垂直：三个分区都是上下通栏，等于没反转', () {
        final bounds = _boundaries(mode, TapZoneInvert.vertical);
        for (double x = 0.01; x < 1.0; x += 0.07) {
          if (_onBoundary(x, bounds)) continue;
          for (double y = 0.01; y < 1.0; y += 0.07) {
            expect(
              _resolve(mode, x, y, invert: TapZoneInvert.vertical),
              _resolve(mode, x, y),
              reason: '左右布局在 ($x, $y) 处垂直反转前后应一致',
            );
          }
        }
      });
    });
  });

  group('异常输入', () {
    test('尺寸非法时回退到界面开关，不抛异常', () {
      expect(
        resolveTapZone(TapZoneMode.lShape, Offset.zero, Size.zero),
        TapZoneAction.menu,
      );
      expect(
        resolveTapZone(TapZoneMode.edge, Offset(10, 10), Size(0, 100)),
        TapZoneAction.menu,
      );
    });
  });
}
