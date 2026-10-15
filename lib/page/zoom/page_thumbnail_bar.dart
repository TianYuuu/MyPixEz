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
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/models/illust.dart';

/// 缩略图宽度的可选值。
const List<int> kThumbnailSizeOptions = [36, 48, 64, 80, 96];

/// 缩略图宽度默认值。
const double kDefaultThumbnailSize = 48;

/// 缩略图按 3:4 的竖版显示。
double thumbnailHeightFor(double width) => width * 4 / 3;

/// 整条缩略图的高度（缩略图 + 上下留白）。
double thumbnailBarHeightFor(double width) => thumbnailHeightFor(width) + 12;

/// 让第 [index] 张缩略图居中所需的滚动偏移。
///
/// 列表左右两端各留了 `(viewport - itemExtent) / 2` 的空白，
/// 所以偏移恰好就是 `index * itemExtent`，与滚动方向无关。
/// 两端留白也正是"第 1 张就能居中"的原因。
double thumbnailScrollOffset({
  required int index,
  required int count,
  required double itemExtent,
  required double viewportWidth,
}) {
  if (count <= 0 || itemExtent <= 0 || viewportWidth <= 0) return 0;
  final maxOffset = (count - 1) * itemExtent;
  if (maxOffset <= 0) return 0;
  return (index * itemExtent).clamp(0.0, maxOffset);
}

/// 当前落在视口正中的是第几张缩略图。
///
/// 同样因为两端留白，`offset / itemExtent` 四舍五入就是居中索引，
/// 从右到左与从左到右都是这个结果。
int thumbnailIndexAtCenter({
  required double offset,
  required int count,
  required double itemExtent,
}) {
  if (count <= 0 || itemExtent <= 0) return 0;
  final raw = (offset / itemExtent).round();
  if (raw < 0) return 0;
  if (raw > count - 1) return count - 1;
  return raw;
}

/// 阅读器底部的缩略图条。
///
/// 两端留白让任意一张（含第一张和最后一张）都能滚到正中，
/// 滚动时通过 [onCenteredIndexChanged] 上报居中索引，
/// 交给调用方实现"像 iOS 相册那样滑到哪张就翻到哪页"。
class PageThumbnailBar extends StatefulWidget {
  final Illusts illusts;
  final int currentIndex;

  /// 从右到左排列：第 1 张在最右。
  final bool reverse;

  /// 单个缩略图的宽度。
  final double itemSize;
  final ValueChanged<int> onTap;

  /// 居中索引变化时的回调。
  final ValueChanged<int>? onCenteredIndexChanged;

  /// 长按某张缩略图：下载该页原图。
  final ValueChanged<int>? onLongPressPage;

  const PageThumbnailBar({
    super.key,
    required this.illusts,
    required this.currentIndex,
    required this.onTap,
    this.reverse = false,
    this.itemSize = kDefaultThumbnailSize,
    this.onCenteredIndexChanged,
    this.onLongPressPage,
  });

  @override
  State<PageThumbnailBar> createState() => _PageThumbnailBarState();
}

class _PageThumbnailBarState extends State<PageThumbnailBar> {
  final ScrollController _controller = ScrollController();
  bool _didInitialScroll = false;

  /// 最近一次由"滚动"上报出去的索引。
  ///
  /// 用它防止回环：滚动上报 → 上层改 currentIndex → 又触发自动滚动 →
  /// 和用户的手指抢位置。
  int? _lastReportedIndex;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant PageThumbnailBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      // 如果这次变化正是我们自己上报的，就不要再滚，否则会打架。
      if (widget.currentIndex == _lastReportedIndex) return;
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final centered = thumbnailIndexAtCenter(
      offset: _controller.offset,
      count: widget.illusts.metaPages.length,
      itemExtent: widget.itemSize,
    );
    if (centered == _lastReportedIndex) return;
    _lastReportedIndex = centered;
    widget.onCenteredIndexChanged?.call(centered);
  }

  void _scrollToCurrent({bool animate = true}) {
    if (!_controller.hasClients) return;
    final target = thumbnailScrollOffset(
      index: widget.currentIndex,
      count: widget.illusts.metaPages.length,
      itemExtent: widget.itemSize,
      viewportWidth: _controller.position.viewportDimension,
    );
    if (animate) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastReportedIndex = widget.currentIndex;
      _scrollToCurrent(animate: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.illusts.metaPages;
    if (pages.isEmpty) return const SizedBox.shrink();
    _scheduleInitialScroll();
    final primary = Theme.of(context).colorScheme.primary;
    final itemSize = widget.itemSize;
    return SizedBox(
      height: thumbnailBarHeightFor(itemSize),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 两端留白，让第一张和最后一张也能滚到正中。
          final pad = (constraints.maxWidth - itemSize) / 2;
          return ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            reverse: widget.reverse,
            itemExtent: itemSize,
            padding: EdgeInsets.symmetric(horizontal: pad > 0 ? pad : 0),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final selected = index == widget.currentIndex;
              return GestureDetector(
                onTap: () => widget.onTap(index),
                onLongPress: widget.onLongPressPage == null
                    ? null
                    : () => widget.onLongPressPage!(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2.0,
                    vertical: 6.0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4.0),
                      border: Border.all(
                        color: selected ? primary : Colors.white24,
                        width: selected ? 2.0 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    // 用 medium 而不是方形的 squareMedium：
                    // 方图会把长页裁成中间一块，反而认不出是哪一页。
                    child: PixivImage(
                      pages[index].imageUrls?.medium ?? '',
                      // 横条一律铺满格子：contain 会把图缩小，
                      // 横条上本来就小，再缩就更看不清了。
                      fit: BoxFit.cover,
                      fade: false,
                      enableMemoryCache: false,
                      placeWidget: Container(color: Colors.white10),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
