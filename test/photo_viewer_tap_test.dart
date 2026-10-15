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

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixez/page/zoom/tap_zone.dart';

/// 查看器里照片的显示区域（要能完整放进测试窗口）。
const Size _viewer = Size(300, 500);

/// 把归一化坐标换算成屏幕坐标。
///
/// tester.tapAt 收的是屏幕坐标，而 PhotoViewGallery 在测试窗口里是居中的，
/// 所以要叠加它的左上角偏移，不能直接用局部坐标。
Offset _at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byType(PhotoViewGallery));
  return Offset(rect.left + rect.width * x, rect.top + rect.height * y);
}

/// 立刻可用的图片。
///
/// photo_view 只有在拿到图片尺寸、算出 scaleBoundaries 之后才会构建手势层，
/// 图片没解码完时它直接返回一个空 Container，点击自然收不到回调。
/// 所以测试里必须用同步完成的 ImageProvider，而不是 MemoryImage。
class _SyncImageProvider extends ImageProvider<_SyncImageProvider> {
  final ui.Image image;

  _SyncImageProvider(this.image);

  @override
  Future<_SyncImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SyncImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _SyncImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}

late ui.Image _testImage;

Widget _buildGallery({
  required ValueChanged<TapUpDetails> onTapUp,
  PageController? controller,
  ValueChanged<int>? onPageChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewer.width,
          height: _viewer.height,
          child: PhotoViewGallery.builder(
            pageController: controller ?? PageController(),
            onPageChanged: onPageChanged,
            itemCount: 3,
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: _SyncImageProvider(_testImage),
                initialScale: PhotoViewComputedScale.contained,
                onTapUp: (context, details, controllerValue) =>
                    onTapUp(details),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// 推进若干帧。
///
/// 这里刻意不用 pumpAndSettle：PhotoView 在图片解码完成前会显示
/// 一个无限循环的加载指示器，pumpAndSettle 会一直等下去而超时。
Future<void> _advance(WidgetTester tester, [int frames = 3]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 让双击识别器的等待定时器过期，使单击的 onTapUp 有机会触发。
/// DoubleTapGestureRecognizer 会占住手势竞技场约 300ms，
/// TapGestureRecognizer 要等它放弃之后才会触发 onTapUp。
Future<void> _settleTap(WidgetTester tester) async {
  await _advance(tester, 4);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _testImage = await createTestImage(width: 100, height: 200);
  });

  testWidgets('单击图库能拿到 onTapUp（不会被双击缩放识别器吞掉）', (tester) async {
    final taps = <TapUpDetails>[];
    await tester.pumpWidget(_buildGallery(onTapUp: taps.add));
    await _advance(tester);

    expect(taps, isEmpty, reason: '还没点击时不应有回调');

    await tester.tapAt(_at(tester, 0.5, 0.5));
    await _settleTap(tester);

    expect(taps, hasLength(1), reason: '一次单击应当恰好触发一次 onTapUp');
  });

  testWidgets('左右两侧点击都能拿到回调，且坐标落在预期的分区里', (tester) async {
    const mode = TapZoneMode.lShape;
    final actions = <TapZoneAction>[];
    await tester.pumpWidget(
      _buildGallery(
        onTapUp: (details) => actions.add(
          resolveTapZone(mode, details.localPosition, _viewer),
        ),
      ),
    );
    await _advance(tester);

    // 左侧 → 上一张
    await tester.tapAt(_at(tester, 0.1, 0.5));
    await _settleTap(tester);
    // 右侧 → 下一张
    await tester.tapAt(_at(tester, 0.9, 0.5));
    await _settleTap(tester);

    expect(actions, [TapZoneAction.previous, TapZoneAction.next]);
  });

  testWidgets('双击不会触发翻页回调（保留双击缩放）', (tester) async {
    final taps = <TapUpDetails>[];
    await tester.pumpWidget(_buildGallery(onTapUp: taps.add));
    await _advance(tester);

    final spot = _at(tester, 0.5, 0.5);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await _advance(tester, 4);

    expect(taps, isEmpty, reason: '双击应当被双击识别器消费，不应误触发翻页');
  });

  testWidgets('PageController.jumpToPage 能真正切页并回调 onPageChanged', (tester) async {
    final controller = PageController();
    final visited = <int>[];
    await tester.pumpWidget(
      _buildGallery(
        onTapUp: (_) {},
        controller: controller,
        onPageChanged: visited.add,
      ),
    );
    await _advance(tester);

    controller.jumpToPage(2);
    await _advance(tester, 4);

    expect(visited, contains(2), reason: '跳页后应当回调新的页码');
    expect(controller.page?.round(), 2);
  });
}
