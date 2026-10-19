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
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixez/models/tags.dart' as suggest;
import 'package:pixez/page/novel/component/novel_filter_sheet.dart';
import 'package:pixez/page/novel/novel_filter.dart';
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

const Size _screen = Size(400, 800);

Future<void> _pumpHost(
  WidgetTester tester, {
  NovelFilter initial = NovelFilter.any,
  required void Function(NovelFilter?) onResult,
  Size screen = _screen,
  Future<List<suggest.Tags>> Function(String word)? suggestionLoader,
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
              onResult(
                await showNovelCountFilterSheet(
                  context,
                  initial,
                  suggestionLoader: suggestionLoader,
                ),
              );
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
  testWidgets('三行 A—B 输入：阅读数/收藏数/字数，共 6 个数字框', (tester) async {
    await _pumpHost(tester, onResult: (_) {});
    expect(find.text('阅读数'), findsOneWidget);
    expect(find.text('收藏数'), findsOneWidget);
    expect(find.text('字数'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('默认标签框是空的', (tester) async {
    await _pumpHost(tester, onResult: (_) {});
    final field = tester.widget<TextField>(find.byKey(novelTagInputKey));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('填数字点应用，返回正确条件', (tester) async {
    NovelFilter? result;
    await _pumpHost(tester, onResult: (f) => result = f);

    final fields = find.byType(TextFormField);
    // 阅读数 min / max，收藏数 min / max，字数 min / max 依次排列。
    await tester.enterText(fields.at(0), '100');
    await tester.enterText(fields.at(1), '10000');
    await tester.enterText(fields.at(2), '10');
    await tester.enterText(fields.at(4), '5000');

    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.views.min, 100);
    expect(result!.views.max, 10000);
    expect(result!.bookmarks.min, 10);
    expect(result!.textLength.min, 5000);
  });

  testWidgets('清空会把输入框和标签都复位', (tester) async {
    await _pumpHost(
      tester,
      initial: const NovelFilter(views: CountRange(min: 100), tags: ['初音未来']),
      onResult: (_) {},
    );

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(novelTagInputKey));
    expect(field.controller!.text, isEmpty);
    expect(find.text('初音未来'), findsNothing);
  });

  testWidgets('点候选变成 chip（补全走注入的假数据）', (tester) async {
    await _pumpHost(
      tester,
      suggestionLoader: (word) async => [
        suggest.Tags(name: '初音ミク', translated_name: '初音未来'),
      ],
      onResult: (_) {},
    );

    await tester.enterText(find.byKey(novelTagInputKey), '初音');
    // 等 350ms 防抖 + 补全结果回来。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('初音ミク'), findsOneWidget);
    await tester.tap(find.text('初音ミク'));
    await tester.pumpAndSettle();

    // chip 用的是原文 name。
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('窄屏也不溢出', (tester) async {
    await _pumpHost(tester, screen: const Size(320, 640), onResult: (_) {});
    expect(tester.takeException(), isNull);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
  });
}
