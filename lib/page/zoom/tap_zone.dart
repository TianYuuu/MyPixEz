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

/// 点击图片时触发的动作。
enum TapZoneAction {
  /// 切换到上一张。
  previous,

  /// 切换到下一张。
  next,

  /// 切换界面（底部工具栏）的显示与隐藏。
  menu,

  /// 什么也不做。
  none,
}

/// 点击分区布局。
///
/// 五种布局的几何形状与 Mihon（Tachiyomi 后继）阅读器的 Tap zones
/// 一一对应，见 [_baseZonesOf] 里各分支的注释与出处。
enum TapZoneMode {
  /// L 型（对应 Mihon 的 `LNavigation`）。
  ///
  /// 上一张 = 顶栏 + 中间带左 1/3，拼成一个开口朝右下的 L；
  /// 下一张 = 底栏 + 中间带右 1/3，拼成一个开口朝左上的 L；
  /// 中间带正中的 1/3 是开关界面。
  lShape,

  /// Kindle 型（对应 Mihon 的 `KindlishNavigation`）。
  ///
  /// 上方 1/3 开关界面；下方左侧 1/3 上一张；下方其余（右 2/3）下一张。
  kindlish,

  /// 边缘（对应 Mihon 的 `EdgeNavigation`）。
  ///
  /// 左右两条竖边都是下一张——翻页时不必分辨点在左边还是右边；
  /// 只有底部正中的 1/3 是上一张，中间偏上是开关界面。
  edge,

  /// 左右（对应 Mihon 的 `RightAndLeftNavigation`）。
  ///
  /// 左 1/3 上一张、右 1/3 下一张，中间 1/3 开关界面。
  rightAndLeft,

  /// 禁用（对应 Mihon 的 `DisabledNavigation`）：点击不翻页。
  disabled,
}

/// 一个归一化（0~1）的矩形区域，以及落在该区域时要执行的动作。
class TapZone {
  /// 归一化矩形，(0,0) 为左上角，(1,1) 为右下角。
  final Rect rect;

  final TapZoneAction action;

  TapZone(this.rect, this.action);

  /// [normalized] 是归一化后的点击坐标。
  bool contains(Offset normalized) => rect.contains(normalized);
}

extension TapZoneModeValue on TapZoneMode {
  /// 用于持久化到 SharedPreferences 的整数值。
  int get value => index;

  /// 从持久化的整数还原；越界或为空时回退到 [TapZoneMode.lShape]。
  static TapZoneMode fromValue(int? value) {
    if (value == null || value < 0 || value >= TapZoneMode.values.length) {
      return TapZoneMode.lShape;
    }
    return TapZoneMode.values[value];
  }
}

/// 反转方式，取值与 Mihon 的 `TappingInvertMode` 一一对应。
///
/// 反转指把分区矩形在归一化坐标里翻转，从而交换各区域的动作。
enum TapZoneInvert {
  /// 关闭，不反转。
  none,

  /// 水平反转：左右对调（x 映射为 1-x）。
  horizontal,

  /// 垂直反转：上下对调（y 映射为 1-y）。
  vertical,

  /// 双向反转：水平 + 垂直，等价于旋转 180 度。
  both,
}

extension TapZoneInvertValue on TapZoneInvert {
  /// 用于持久化到 SharedPreferences 的整数值。
  int get value => index;

  /// 从持久化的整数还原；越界或为空时回退到 [TapZoneInvert.none]。
  static TapZoneInvert fromValue(int? value) {
    if (value == null || value < 0 || value >= TapZoneInvert.values.length) {
      return TapZoneInvert.none;
    }
    return TapZoneInvert.values[value];
  }

  bool get isHorizontal =>
      this == TapZoneInvert.horizontal || this == TapZoneInvert.both;

  bool get isVertical =>
      this == TapZoneInvert.vertical || this == TapZoneInvert.both;
}

/// 按 Mihon `RectF.invert(TappingInvertMode)` 的公式翻转一个归一化矩形。
///
/// 原实现见 Mihon 的
/// `app/src/main/java/eu/kanade/tachiyomi/util/lang/RectFExtensions.kt`。
Rect invertRect(Rect rect, TapZoneInvert invert) {
  final horizontal = invert.isHorizontal;
  final vertical = invert.isVertical;
  if (horizontal && vertical) {
    return Rect.fromLTRB(
      1 - rect.right,
      1 - rect.bottom,
      1 - rect.left,
      1 - rect.top,
    );
  }
  if (vertical) {
    return Rect.fromLTRB(rect.left, 1 - rect.bottom, rect.right, 1 - rect.top);
  }
  if (horizontal) {
    return Rect.fromLTRB(1 - rect.right, rect.top, 1 - rect.left, rect.bottom);
  }
  return rect;
}

/// 沿竖直轴左右镜像的简写，等价于 [TapZoneInvert.horizontal]。
Rect mirrorRectHorizontally(Rect rect) =>
    invertRect(rect, TapZoneInvert.horizontal);

/// 返回某个布局下的全部分区，按判定优先级排列（先匹配到的生效）。
///
/// [invert] 会按 Mihon 的规则翻转所有分区矩形，从而交换各区域的动作。
/// 翻转后各分区依然互不重叠，所以中间的开关界面不会被破坏。
///
/// 所有分区合起来必须覆盖整个 (0,0)-(1,1) 区域，这样 [resolveTapZone]
/// 永远能命中一个分区，不会出现"点空白处无响应"的情况。
List<TapZone> zonesOf(
  TapZoneMode mode, {
  TapZoneInvert invert = TapZoneInvert.none,
}) {
  final zones = _baseZonesOf(mode);
  if (invert == TapZoneInvert.none) return zones;
  return zones
      .map((zone) => TapZone(invertRect(zone.rect, invert), zone.action))
      .toList();
}

/// 各种布局未经镜像时的原始分区。
///
/// 几何值逐条对应 Mihon 仓库里的
/// `app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/navigation/*.kt`。
/// Mihon 那边未覆盖到的区域会落到它的 menu 分支，这里为了让分区
/// 完整覆盖整屏（便于测试与绘制提示层），把那些区域显式写成 menu。
List<TapZone> _baseZonesOf(TapZoneMode mode) {
  switch (mode) {
    case TapZoneMode.lShape:
      // Mihon LNavigation:
      //   PREV (0, 0.33, 0.33, 0.66)  中间带左 1/3
      //   PREV (0, 0, 1, 0.33)        顶栏
      //   NEXT (0.66, 0.33, 1, 0.66)  中间带右 1/3
      //   NEXT (0, 0.66, 1, 1)        底栏
      // 未覆盖的中心 1/3 → MENU
      return [
        // 顶栏（全宽）→ 上一张
        TapZone(Rect.fromLTRB(0, 0, 1, 1 / 3), TapZoneAction.previous),
        // 中间带左 1/3 → 上一张（与顶栏拼成开口朝右下的 L）
        TapZone(Rect.fromLTRB(0, 1 / 3, 1 / 3, 2 / 3), TapZoneAction.previous),
        // 中间带右 1/3 → 下一张（与底栏拼成开口朝左上的 L）
        TapZone(Rect.fromLTRB(2 / 3, 1 / 3, 1, 2 / 3), TapZoneAction.next),
        // 底栏（全宽）→ 下一张
        TapZone(Rect.fromLTRB(0, 2 / 3, 1, 1), TapZoneAction.next),
        // 中间带正中 → 开关界面
        TapZone(Rect.fromLTRB(1 / 3, 1 / 3, 2 / 3, 2 / 3), TapZoneAction.menu),
      ];
    case TapZoneMode.kindlish:
      // Mihon KindlishNavigation:
      //   NEXT (0.33, 0.33, 1, 1)     下方右 2/3
      //   PREV (0, 0.33, 0.33, 1)     下方左 1/3
      // 未覆盖的上方 1/3 → MENU
      return [
        TapZone(Rect.fromLTRB(0, 0, 1, 1 / 3), TapZoneAction.menu),
        TapZone(Rect.fromLTRB(0, 1 / 3, 1 / 3, 1), TapZoneAction.previous),
        TapZone(Rect.fromLTRB(1 / 3, 1 / 3, 1, 1), TapZoneAction.next),
      ];
    case TapZoneMode.edge:
      // Mihon EdgeNavigation:
      //   NEXT (0, 0, 0.33, 1)            左边整列
      //   PREV (0.33, 0.66, 0.66, 1)      底部中间 1/3
      //   NEXT (0.66, 0, 1, 1)            右边整列
      // 未覆盖的中间偏上 → MENU
      // 注意：左右两边都是"下一张"是 Mihon 的原样设计，
      // 目的是翻页时不用分辨自己点的是哪一边。
      return [
        TapZone(Rect.fromLTRB(0, 0, 1 / 3, 1), TapZoneAction.next),
        TapZone(Rect.fromLTRB(1 / 3, 2 / 3, 2 / 3, 1), TapZoneAction.previous),
        TapZone(Rect.fromLTRB(2 / 3, 0, 1, 1), TapZoneAction.next),
        TapZone(Rect.fromLTRB(1 / 3, 0, 2 / 3, 2 / 3), TapZoneAction.menu),
      ];
    case TapZoneMode.rightAndLeft:
      // Mihon RightAndLeftNavigation:
      //   LEFT  (0, 0, 0.33, 1)     左 1/3
      //   RIGHT (0.66, 0, 1, 1)     右 1/3
      // 未覆盖的中间 1/3 → MENU
      // Mihon 的 LEFT/RIGHT 会按阅读方向取反，本项目是左起阅读，
      // 所以就是左=上一张、右=下一张。
      return [
        TapZone(Rect.fromLTRB(0, 0, 1 / 3, 1), TapZoneAction.previous),
        TapZone(Rect.fromLTRB(2 / 3, 0, 1, 1), TapZoneAction.next),
        TapZone(Rect.fromLTRB(1 / 3, 0, 2 / 3, 1), TapZoneAction.menu),
      ];
    case TapZoneMode.disabled:
      return [TapZone(Rect.fromLTRB(0, 0, 1, 1), TapZoneAction.none)];
  }
}

/// 根据点击位置判断应该执行什么动作。
///
/// [position] 是相对于被点击区域左上角的坐标，[size] 是该区域的尺寸。
/// [invert] 会先按 Mihon 的规则翻转布局再判定。
/// 尺寸非法（例如尚未完成布局）时按 [TapZoneAction.menu] 处理。
TapZoneAction resolveTapZone(
  TapZoneMode mode,
  Offset position,
  Size size, {
  TapZoneInvert invert = TapZoneInvert.none,
}) {
  if (size.width <= 0 || size.height <= 0) return TapZoneAction.menu;
  final normalized = Offset(
    position.dx / size.width,
    position.dy / size.height,
  );
  for (final zone in zonesOf(mode, invert: invert)) {
    if (zone.contains(normalized)) return zone.action;
  }
  return TapZoneAction.menu;
}
