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

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/page/zoom/page_thumbnail_grid.dart';
import 'package:pixez/page/zoom/viewer_quality.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';

/// 造一批页面地址。缩略图在测试环境里没有网络和缓存，
/// 会落到错误占位，但布局和交互逻辑照样会被走到。
List<ViewerUrls> _fakePages(int count) => [
      for (var i = 0; i < count; i++)
        ViewerUrls(
          medium: 'https://example.com/m$i.jpg',
          large: 'https://example.com/l$i.jpg',
          original: 'https://example.com/o$i.jpg',
        ),
    ];

/// 图片加载不会成功，用固定次数 pump，避免 pumpAndSettle 卡死。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// 结果容器：网格 pop 出来的页码写在这里。
class _Result {
  int? value;
}

/// 打开网格，返回结果容器。
///
/// 走真正的路由 push，这样 pop 的返回值能被捕获到。
Future<_Result> _openGrid(
  WidgetTester tester, {
  required int pages,
  required int currentIndex,
  ThumbnailShape shape = ThumbnailShape.uniform,
  ValueChanged<ThumbnailShape>? onShapeChanged,
  ValueChanged<int>? onLongPressPage,
  Size size = const Size(400, 800),
}) async {
  final result = _Result();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      // 和 main.dart 一致：I18n.of 内部是 AppLocalizations.of(context)!，
      // 缺了委托会直接抛空指针。
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result.value = await Navigator.of(context).push(
                  MaterialPageRoute<int>(
                    builder: (_) => PageThumbnailGrid(
                      pages: _fakePages(pages),
                      currentIndex: currentIndex,
                      columns: 5,
                      shape: shape,
                      onShapeChanged: onShapeChanged,
                      onLongPressPage: onLongPressPage,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return result;
}

void main() {
  setUp(() {
    // pixivCacheManager 依赖 App 启动时初始化的 DioCacheManager，
    // 测试环境里没这一步会直接抛 LateInitializationError。
    pixivCacheManager = null;
  });

  testWidgets('窄屏上渲染不溢出（顶栏有标题+进度条+页数+两个按钮）', (tester) async {
    await _openGrid(
      tester,
      pages: 40,
      currentIndex: 5,
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('右上角开关能切换形状并回调出去', (tester) async {
    final changes = <ThumbnailShape>[];
    await _openGrid(
      tester,
      pages: 12,
      currentIndex: 0,
      onShapeChanged: changes.add,
    );

    // 初始是"统一大小"，图标是方框
    expect(find.byIcon(Icons.crop_square), findsOneWidget);

    await tester.tap(find.byIcon(Icons.crop_square));
    await _settle(tester);

    // 切到"按原图比例"：图标换成自由形状，并且回调了一次
    expect(find.byIcon(Icons.aspect_ratio), findsOneWidget);
    expect(find.byIcon(Icons.crop_square), findsNothing);
    expect(changes, [ThumbnailShape.originalRatio]);

    // 再点一次切回去
    await tester.tap(find.byIcon(Icons.aspect_ratio));
    await _settle(tester);
    expect(find.byIcon(Icons.crop_square), findsOneWidget);
    expect(changes, [ThumbnailShape.originalRatio, ThumbnailShape.uniform]);
  });

  testWidgets('切换形状立刻生效，不用退出去重进', (tester) async {
    await _openGrid(tester, pages: 6, currentIndex: 0);

    // 初始是统一大小 → cover
    expect(
      tester
          .widget<PixivImage>(find.byKey(const ValueKey('thumb_0_uniform')))
          .fit,
      BoxFit.cover,
    );

    await tester.tap(find.byIcon(Icons.crop_square));
    await _settle(tester);

    // PixivImage 在 initState 里把 fit 存了一份副本，
    // 只有换 key 才会重建。这条就是在钉住"点了就变"。
    expect(
      tester
          .widget<PixivImage>(
            find.byKey(const ValueKey('thumb_0_originalRatio')),
          )
          .fit,
      BoxFit.contain,
    );
    expect(find.byKey(const ValueKey('thumb_0_uniform')), findsNothing);
  });

  testWidgets('顶栏：标题在左、页数+两个按钮在右', (tester) async {
    await _openGrid(tester, pages: 40, currentIndex: 0);
    final title = tester.getRect(find.text('全部页面'));
    final count = tester.getRect(find.text('1/40'));
    final slider = tester.getRect(find.byType(Slider));
    final close = tester.getRect(find.byIcon(Icons.close));
    final toggle = tester.getRect(find.byIcon(Icons.crop_square));
    final screenWidth = tester.view.physicalSize.width;

    // 标题贴左
    expect(title.left, lessThan(screenWidth * 0.25));
    // 页数、开关、关闭都在右半边，且依次向右
    expect(count.left, greaterThan(screenWidth * 0.5));
    expect(toggle.left, greaterThan(count.left));
    expect(close.left, greaterThan(toggle.left));
    // 进度条夹在标题和页数之间（Expanded 会紧贴标题右缘，视觉间距由
    // Slider 自身的内边距提供，所以这里用 >= ）
    expect(slider.left, greaterThanOrEqualTo(title.right));
    expect(slider.right, lessThanOrEqualTo(count.left));
    // 而且它确实占掉了中间一大块，不是短短一小截
    expect(slider.width, greaterThan(100));
  });

  testWidgets('什么都不动就关闭，返回原来的页码（等于没改）', (tester) async {
    final result = await _openGrid(tester, pages: 12, currentIndex: 7);
    await tester.tap(find.byIcon(Icons.close));
    await _settle(tester);
    expect(result.value, 7);
  });

  testWidgets('顶部进度条能改选中页，关闭时把新页码带回去', (tester) async {
    final result = await _openGrid(tester, pages: 11, currentIndex: 0);

    // 页数显示里一开始是第 1 页
    expect(find.textContaining('11'), findsWidgets);

    // 点进度条靠右的位置，把选中页推到末尾附近
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(slider.right - 1, slider.center.dy));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.close));
    await _settle(tester);
    expect(result.value, isNotNull);
    expect(result.value, greaterThan(5));
  });

  testWidgets('长按缩略图会触发下载回调', (tester) async {
    final downloads = <int>[];
    await _openGrid(
      tester,
      pages: 12,
      currentIndex: 0,
      onLongPressPage: downloads.add,
    );

    // 长按第 3 张（页码文字在格子里，命中同一个 GestureDetector）
    await tester.longPress(find.text('3'));
    await _settle(tester);

    expect(downloads, [2]);
  });

  testWidgets('没传长按回调时不会出错', (tester) async {
    await _openGrid(tester, pages: 6, currentIndex: 0);
    await tester.longPress(find.text('3'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
