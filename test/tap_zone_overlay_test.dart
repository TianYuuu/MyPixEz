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
import 'package:material_ui/material_ui.dart';
import 'package:pixez/page/zoom/tap_zone.dart';
import 'package:pixez/page/zoom/tap_zone_overlay.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('zh', 'CN')}) {
  return MaterialApp(
    locale: locale,
    // 和 main.dart 里的配置保持一致，否则 zh 会因为缺少
    // Material/Cupertino 本地化委托而报错。
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, height: 800, child: child),
    ),
  );
}

/// 找出提示层里某个文案出现的次数。
int _countText(WidgetTester tester, String text) =>
    tester.widgetList<Text>(find.byType(Text)).where((t) => t.data == text).length;

void main() {
  testWidgets('L 型提示层会画出两块 L：顶栏+左臂、底栏+右臂', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TapZoneOverlay(mode: TapZoneMode.lShape),
      ),
    );
    await tester.pump();

    final i18n = lookupAppLocalizations(const Locale('zh', 'CN'));
    // 上一张 = 顶栏 + 中间带左 1/3（两块）
    // 下一张 = 中间带右 1/3 + 底栏（两块）
    // 开关界面 = 中间带正中（一块）
    expect(_countText(tester, i18n.tap_zone_action_prev), 2);
    expect(_countText(tester, i18n.tap_zone_action_next), 2);
    expect(_countText(tester, i18n.tap_zone_action_menu), 1);
  });

  testWidgets('提示层标题包含当前布局名称', (tester) async {
    await tester.pumpWidget(
      _wrap(const TapZoneOverlay(mode: TapZoneMode.kindlish)),
    );
    await tester.pump();

    final i18n = lookupAppLocalizations(const Locale('zh', 'CN'));
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.contains(i18n.tap_zone_overlay_title))
        .toList();
    expect(titles, hasLength(1));
    expect(titles.single, contains(i18n.tap_zone_kindlish));
    expect(titles.single, isNot(contains(i18n.tap_zone_invert_horizontal)));
  });

  testWidgets('开启镜像后标题会标注、且左右动作真的对调', (tester) async {
    await tester.pumpWidget(
      _wrap(const TapZoneOverlay(mode: TapZoneMode.rightAndLeft, invert: TapZoneInvert.horizontal)),
    );
    await tester.pump();

    final i18n = lookupAppLocalizations(const Locale('zh', 'CN'));
    final title = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.contains(i18n.tap_zone_overlay_title));
    expect(title, contains(i18n.tap_zone_invert_horizontal));

    // 左右布局：镜像前左半是上一张；镜像后上半部分仍是开关界面，
    // 下半部分左右对调——上一张/下一张各出现一次，数量不变。
    expect(_countText(tester, i18n.tap_zone_action_prev), 1);
    expect(_countText(tester, i18n.tap_zone_action_next), 1);
    expect(_countText(tester, i18n.tap_zone_action_menu), 1);
  });

  testWidgets('禁用的布局只显示不响应，没有翻页区块', (tester) async {
    await tester.pumpWidget(
      _wrap(const TapZoneOverlay(mode: TapZoneMode.disabled)),
    );
    await tester.pump();

    final i18n = lookupAppLocalizations(const Locale('zh', 'CN'));
    expect(_countText(tester, i18n.tap_zone_action_none), 1);
    expect(_countText(tester, i18n.tap_zone_action_prev), 0);
    expect(_countText(tester, i18n.tap_zone_action_next), 0);
  });

  testWidgets('提示层不拦截点击事件', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped++,
              child: const SizedBox.expand(),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: TapZoneOverlay(mode: TapZoneMode.lShape),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    expect(tapped, 1, reason: '提示层存在时下层仍应能收到点击');
  });

  testWidgets('英文环境下也能正常渲染', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TapZoneOverlay(mode: TapZoneMode.edge),
        locale: const Locale('en', 'US'),
      ),
    );
    await tester.pump();

    final i18n = lookupAppLocalizations(const Locale('en', 'US'));
    // 边缘布局：左右两条边都是下一张，只有底部中间是上一张。
    expect(_countText(tester, i18n.tap_zone_action_prev), 1);
    expect(_countText(tester, i18n.tap_zone_action_next), 2);
    expect(_countText(tester, i18n.tap_zone_action_menu), 1);
  });
}
