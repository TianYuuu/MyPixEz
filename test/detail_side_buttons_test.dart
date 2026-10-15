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
import 'package:pixez/component/detail_side_buttons.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

/// 详情页左下角的两个按钮：上面回顶部，下面定位到作者区。
///
/// 起因：这组按钮第一次加错了文件（加到了横屏的 IllustRowPage 上），
/// 竖屏用的是 IllustVerticalPage，所以实际看不到。这里至少把组件本身
/// 钉住——渲染得出来、点了真的会滚。

/// 造一个能滚的页面：上面一大段空白，中间是"作者区"锚点，下面又一大段。
Widget _harness({
  required ScrollController controller,
  required GlobalKey anchorKey,
  int id = 1,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Stack(
        children: [
          SizedBox(
            height: 600,
            child: ListView(
              controller: controller,
              children: [
                // 一堆图片
                const SizedBox(height: 3000),
                // 作者/介绍区就在这个锚点下面。真实页面里它也确实挨着末尾
                // （图片 -> 锚点 -> 作者介绍 -> 推荐区），所以"先跳到底部
                // 逼它布局"那条兜底路径够得着。
                SizedBox(key: anchorKey, height: 10),
                // 推荐区
                const SizedBox(height: 400),
              ],
            ),
          ),
          DetailSideButtons(
            anchorKey: anchorKey,
            scrollController: controller,
            id: id,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('渲染出两个按钮：回顶部 + 定位作者区', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, anchorKey: GlobalKey()),
    );
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsNWidgets(2));
    expect(find.byIcon(Icons.vertical_align_top), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('两个按钮的 heroTag 必须不同，否则同页两个 FAB 会冲突', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, anchorKey: GlobalKey()),
    );
    await tester.pump();

    final tags = tester
        .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
        .map((f) => f.heroTag)
        .toList();
    expect(tags.toSet().length, 2, reason: 'heroTag 重复会在路由切换时直接崩');
  });

  testWidgets('不同作品的 heroTag 不串（详情页可以一层层往下推）', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, anchorKey: GlobalKey(), id: 42),
    );
    await tester.pump();

    final tags = tester
        .widgetList<FloatingActionButton>(find.byType(FloatingActionButton))
        .map((f) => f.heroTag)
        .toList();
    expect(tags, containsAll(<Object>['42_to_top', '42_to_author']));
  });

  testWidgets('点上面的按钮直接回到页面最上方', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, anchorKey: GlobalKey()),
    );
    await tester.pump();

    controller.jumpTo(1500);
    await tester.pump();
    expect(controller.offset, 1500);

    await tester.tap(find.byIcon(Icons.vertical_align_top));
    await tester.pumpAndSettle();

    expect(controller.offset, 0, reason: 'Top 键应当回到最上方');
  });

  testWidgets('点下面的按钮把作者区滚进视野', (tester) async {
    final anchorKey = GlobalKey();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _harness(controller: controller, anchorKey: anchorKey),
    );
    await tester.pump();

    // 停在最上面时，作者区在 2000px 之外。ListView 是懒加载的，
    // 所以那个锚点这会儿根本没被构建——这正是 revealDetailAnchor
    // 需要"先跳到底部逼它布局、再精确定位"那条兜底路径的原因。
    expect(controller.offset, 0);
    expect(
      find.byKey(anchorKey),
      findsNothing,
      reason: '离屏太远的锚点还没被布局',
    );

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    // 分步推进：滚动动画 300ms，兜底路径里还有一次 100ms 延迟。
    // 只用 pumpAndSettle 会在动画结束、还没有待处理帧时提前退出，
    // 那个延迟定时器就跑不到了。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 兜底路径走完之后，锚点必须真的出现在视口里
    expect(find.byKey(anchorKey), findsOneWidget);
    final rect = tester.getRect(find.byKey(anchorKey));
    expect(rect.top, lessThan(600));
    expect(rect.bottom, greaterThan(0), reason: '作者区应当落进视口里');
  });
}
