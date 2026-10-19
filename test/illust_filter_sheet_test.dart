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
import 'package:pixez/component/illust_filter_sheet.dart';
import 'package:pixez/lighting/illust_filter.dart';
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

/// 首页那三个列表共用的数量筛选弹窗。
const Size _screen = Size(400, 800);

/// 宿主页面接住弹窗的返回值，这样测的是真实的"打开 → 填 → 应用"链路。
Future<void> _pumpHost(
  WidgetTester tester, {
  IllustFilter initial = IllustFilter.any,
  required void Function(IllustFilter?) onResult,
  Size screen = _screen,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(await showIllustCountFilterSheet(context, initial));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('三行 A—B 输入，共 6 个数字框', (tester) async {
    await _pumpHost(tester, onResult: (_) {});
    expect(find.text('页数'), findsOneWidget);
    expect(find.text('观看数'), findsOneWidget);
    expect(find.text('点赞数'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('已有的筛选值会回填', (tester) async {
    await _pumpHost(
      tester,
      initial: const IllustFilter(
        pages: PageCountRange(min: 2, max: 10),
        views: CountRange(min: 1000),
      ),
      onResult: (_) {},
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('0'), findsNothing, reason: '0 应当显示成空，不是字面上的 0');
  });

  testWidgets('点"应用"把填的值交回去', (tester) async {
    IllustFilter? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    // 0,1 = 页数；2,3 = 观看数；4,5 = 点赞数
    await tester.enterText(find.byType(TextFormField).at(4), '1000');
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(1), '20');
    await tester.pump();

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(
      result,
      const IllustFilter(
        pages: PageCountRange(max: 20),
        bookmarks: CountRange(min: 1000),
      ),
    );
  });

  testWidgets('只填上限也能生效', (tester) async {
    IllustFilter? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextFormField).at(3), '500');
    await tester.pump();

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result, const IllustFilter(views: CountRange(max: 500)));
  });

  testWidgets('"清空"把三个条件都清掉', (tester) async {
    IllustFilter? result;
    await _pumpHost(
      tester,
      initial: const IllustFilter(
        pages: PageCountRange(min: 2),
        views: CountRange(min: 100),
        bookmarks: CountRange(min: 10),
      ),
      onResult: (r) => result = r,
    );

    expect(find.text('100'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('100'), findsNothing);
    expect(find.text('2'), findsNothing);

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result, IllustFilter.any);
  });

  testWidgets('上下界写反时应用后不会留下死区间', (tester) async {
    IllustFilter? result;
    await _pumpHost(tester, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextFormField).at(0), '10');
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    await tester.pump();

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result?.pages, const PageCountRange(min: 10, max: 0));
  });

  testWidgets('弹窗只占内容高度，不挡满屏', (tester) async {
    await _pumpHost(tester, onResult: (_) {});
    final size = tester.getSize(find.byType(IllustCountFilterSheet));
    expect(size.height, lessThan(_screen.height * 0.5));
  });

  testWidgets('窄屏也不溢出', (tester) async {
    await _pumpHost(tester, screen: const Size(320, 640), onResult: (_) {});
    // overflow 会直接抛异常
    expect(tester.takeException(), isNull);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
  });

  group('列表角上的筛选按钮', () {
    Future<void> pumpButton(
      WidgetTester tester,
      IllustFilter filter, {
      ValueChanged<IllustFilter>? onChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: IllustFilterButton(
              scope: IllustFilterScope.recommend,
              filter: filter,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('没筛选时不显示角标，图标也不染色', (tester) async {
      await pumpButton(tester, IllustFilter.any);

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);

      final icon = tester.widget<Icon>(find.byIcon(Icons.filter_alt_outlined));
      expect(icon.color, isNull);
    });

    testWidgets('有筛选时角标数字等于设的项数', (tester) async {
      await pumpButton(
        tester,
        const IllustFilter(
          pages: PageCountRange(min: 2),
          bookmarks: CountRange(min: 100),
        ),
      );

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('点一下能打开弹窗', (tester) async {
      await pumpButton(tester, IllustFilter.any);

      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(IllustCountFilterSheet), findsOneWidget);
    });
  });
}
