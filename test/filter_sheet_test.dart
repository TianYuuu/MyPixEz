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
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';
import 'package:pixez/page/search/result_illust_list.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

/// 筛选弹窗的布局测试。
///
/// 起因是个真实 bug：选项变多之后弹窗长过屏幕，"应用"被顶到通知栏底下
/// 点不到了。修法是把标题栏固定住、内容单独滚动，高度定成 95%。
const Size _screen = Size(400, 800);

Future<void> _pumpSheet(
  WidgetTester tester, {
  VoidCallback? onApply,
  void Function(PageCountRange page, CountRange view, CountRange bookmark)?
      onState,
  PageCountRange pageRange = PageCountRange.any,
  CountRange viewRange = CountRange.any,
  CountRange bookmarkRange = CountRange.any,
}) async {
  tester.view.physicalSize = _screen;
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
        body: ResultIllustSortWidget(
          searchAIType: 0,
          selectSort: 'date_desc',
          searchTarget: 'partial_match_for_tags',
          ugoiraFilter: UgoiraFilter.all,
          pageRange: pageRange,
          viewRange: viewRange,
          bookmarkRange: bookmarkRange,
          onPremium: () {},
          onApply: onApply ?? () {},
          onSateChange: ({
            required String searchTarget,
            required String selectSort,
            required int searchAIType,
            required UgoiraFilter ugoiraFilter,
            required PageCountRange pageRange,
            required CountRange viewRange,
            required CountRange bookmarkRange,
            required bool recordRememberCurrentSelection,
          }) {
            onState?.call(pageRange, viewRange, bookmarkRange);
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('弹窗高度是屏幕的 95%', (tester) async {
    await _pumpSheet(tester);
    final size = tester.getSize(find.byType(ResultIllustSortWidget));
    expect(size.height, closeTo(_screen.height * 0.95, 0.5));
    expect(size.height, lessThan(_screen.height));
  });

  testWidgets('"应用"在屏幕内且点得到（不会顶到通知栏）', (tester) async {
    var applied = 0;
    await _pumpSheet(tester, onApply: () => applied++);

    final rect = tester.getRect(find.text('应用'));
    expect(rect.top, greaterThanOrEqualTo(0.0));
    expect(rect.bottom, lessThanOrEqualTo(_screen.height));

    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(applied, 1, reason: '"应用"必须真的能点到');
  });

  testWidgets('"应用"固定在顶部，不会随内容滚走', (tester) async {
    await _pumpSheet(tester);
    final before = tester.getTopLeft(find.text('应用'));

    // 把内容滚到底
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump();

    final after = tester.getTopLeft(find.text('应用'));
    expect(after.dy, closeTo(before.dy, 0.5), reason: '标题栏不该跟着滚');
  });

  testWidgets('自定义筛选排在最上面', (tester) async {
    await _pumpSheet(tester);

    final pages = tester.getTopLeft(find.text('页数')).dy;
    final views = tester.getTopLeft(find.text('观看数')).dy;
    final bookmarks = tester.getTopLeft(find.text('点赞数')).dy;
    final firstSwitch =
        tester.getTopLeft(find.byType(SwitchListTile).first).dy;

    expect(pages, lessThan(views));
    expect(views, lessThan(bookmarks));
    expect(
      bookmarks,
      lessThan(firstSwitch),
      reason: '自定义筛选应当排在其它选项之前',
    );
  });

  testWidgets('三行 A—B 输入，共 6 个数字框', (tester) async {
    await _pumpSheet(tester);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('已有筛选值会回填进输入框', (tester) async {
    await _pumpSheet(
      tester,
      pageRange: const PageCountRange(min: 2, max: 10),
      viewRange: const CountRange(min: 1000),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    // 没设的那几个框是空的
    expect(find.text('0'), findsNothing, reason: '0 应当显示成空，不是字面上的 0');
  });

  testWidgets('手填的数字会通过"应用"传出去', (tester) async {
    CountRange? capturedView;
    await _pumpSheet(
      tester,
      onState: (page, view, bookmark) => capturedView = view,
    );

    // 0,1 = 页数；2,3 = 观看数；4,5 = 点赞数
    await tester.enterText(find.byType(TextFormField).at(2), '1000');
    await tester.pump();

    await tester.tap(find.text('应用'));
    await tester.pump();

    expect(capturedView, const CountRange(min: 1000, max: 0));
  });

  testWidgets('只填上限也能生效', (tester) async {
    CountRange? capturedBookmark;
    await _pumpSheet(
      tester,
      onState: (page, view, bookmark) => capturedBookmark = bookmark,
    );

    await tester.enterText(find.byType(TextFormField).at(5), '500');
    await tester.pump();

    await tester.tap(find.text('应用'));
    await tester.pump();

    expect(capturedBookmark, const CountRange(min: 0, max: 500));
  });

  testWidgets('窄屏也不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
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
          body: ResultIllustSortWidget(
            searchAIType: 0,
            selectSort: 'date_desc',
            searchTarget: 'partial_match_for_tags',
            ugoiraFilter: UgoiraFilter.all,
            pageRange: PageCountRange.any,
            viewRange: CountRange.any,
            bookmarkRange: CountRange.any,
            onPremium: () {},
            onApply: () {},
            onSateChange: ({
              required String searchTarget,
              required String selectSort,
              required int searchAIType,
              required UgoiraFilter ugoiraFilter,
              required PageCountRange pageRange,
              required CountRange viewRange,
              required CountRange bookmarkRange,
              required bool recordRememberCurrentSelection,
            }) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // 没有溢出异常就算过（overflow 会在测试里直接抛错）
    expect(tester.takeException(), isNull);
    expect(find.text('应用'), findsOneWidget);
  });
}
