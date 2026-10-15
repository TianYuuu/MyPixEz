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

/// 这个测试要回答一个问题：
/// 在 PhotoViewGallery 上面套一层 GestureDetector 的竖直拖动，
/// 手势到底能不能到达外层？如果不能，"上滑呼出全屏缩略图"就是白写的。
///
/// 这里刻意照抄 photo_zoom_page.dart 里的判定方式（速度或距离任一满足）。

const Size _viewer = Size(300, 500);
const double _swipeUpVelocity = -260;
const double _swipeUpMinDistance = 80;

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

/// 和看图页同构：外层 GestureDetector 负责竖直拖动，里面是图库。
Widget _buildViewer({required VoidCallback onSwipeUp}) {
  double accumulated = 0;
  return MaterialApp(
    home: Scaffold(
      body: GestureDetector(
        onVerticalDragStart: (_) => accumulated = 0,
        onVerticalDragUpdate: (details) => accumulated -= details.delta.dy,
        onVerticalDragEnd: (details) {
          final fast = (details.primaryVelocity ?? 0) < _swipeUpVelocity;
          final far = accumulated > _swipeUpMinDistance;
          if (fast || far) onSwipeUp();
        },
        child: Center(
          child: SizedBox(
            width: _viewer.width,
            height: _viewer.height,
            child: PhotoViewGallery.builder(
              pageController: PageController(),
              scrollPhysics: const BouncingScrollPhysics(),
              itemCount: 3,
              builder: (context, index) => PhotoViewGalleryPageOptions(
                imageProvider: _SyncImageProvider(_testImage),
                initialScale: PhotoViewComputedScale.contained,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _advance(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Offset _at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byType(PhotoViewGallery));
  return Offset(rect.left + rect.width * x, rect.top + rect.height * y);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _testImage = await createTestImage(width: 100, height: 200);
  });

  testWidgets('快甩上滑能呼出缩略图（没被图库吞掉）', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_buildViewer(onSwipeUp: () => opened++));
    await _advance(tester);

    expect(opened, 0, reason: '还没滑时不应触发');

    await tester.flingFrom(_at(tester, 0.5, 0.75), const Offset(0, -220), 1500);
    await _advance(tester);

    expect(opened, 1, reason: '快速上滑应当呼出缩略图');
  });

  testWidgets('慢慢上拖也能呼出（primaryVelocity 为 0 的情况）', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_buildViewer(onSwipeUp: () => opened++));
    await _advance(tester);

    // 用手动分段拖动制造"速度几乎为 0、但距离够长"的情形
    final gesture = await tester.startGesture(_at(tester, 0.5, 0.8));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await gesture.up();
    await _advance(tester);

    expect(opened, 1, reason: '累计上拖超过阈值就该触发，不能只看速度');
  });

  testWidgets('下滑不会误触发', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_buildViewer(onSwipeUp: () => opened++));
    await _advance(tester);

    await tester.flingFrom(_at(tester, 0.5, 0.25), const Offset(0, 220), 1500);
    await _advance(tester);

    expect(opened, 0, reason: '下滑是别的操作，不该呼出缩略图');
  });

  testWidgets('水平滑动（翻页方向）不会误触发', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_buildViewer(onSwipeUp: () => opened++));
    await _advance(tester);

    await tester.flingFrom(_at(tester, 0.8, 0.5), const Offset(-220, 0), 1500);
    await _advance(tester);

    expect(opened, 0, reason: '横向是翻页，不该呼出缩略图');
  });
}
