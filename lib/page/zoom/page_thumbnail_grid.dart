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
import 'package:pixez/i18n.dart';
import 'package:pixez/page/zoom/viewer_quality.dart';

/// 缩略图形状：统一大小裁切，或按原图比例完整显示。
enum ThumbnailShape {
  /// 所有格子一样大，长图会被裁掉一部分。
  uniform,

  /// 用 BoxFit.contain，图片按自己的比例完整显示，
  /// 这样横图和竖图一眼就能分辨。
  originalRatio;

  static ThumbnailShape fromValue(int value) =>
      value == 1 ? ThumbnailShape.originalRatio : ThumbnailShape.uniform;

  int get value => this == ThumbnailShape.originalRatio ? 1 : 0;

  BoxFit get fit =>
      this == ThumbnailShape.uniform ? BoxFit.cover : BoxFit.contain;

  ThumbnailShape get toggled =>
      this == ThumbnailShape.uniform ? ThumbnailShape.originalRatio : uniform;
}

/// 展开页的高度：占屏幕的 95%，顶上留一点点缝。
double thumbnailGridHeight(double screenHeight) => screenHeight * 0.95;

/// 网格里每行的高度（含行间距）。
double thumbnailGridRowHeight({
  required double availableWidth,
  required int columns,
  required double spacing,
  required double horizontalPadding,
  required double aspectRatio,
}) {
  if (columns <= 0 || aspectRatio <= 0) return 0;
  final usable =
      availableWidth - horizontalPadding * 2 - spacing * (columns - 1);
  if (usable <= 0) return 0;
  final cellWidth = usable / columns;
  return cellWidth / aspectRatio + spacing;
}

/// 打开网格时应该滚到哪，让当前页所在的那一行出现在视野里。
///
/// 刻意不用 Scrollable.ensureVisible：GridView 是懒加载的，
/// 当前页离屏很远时那个格子根本没被构建，拿不到 context，会静默失效。
/// 这里直接按行列几何算，确定且可测。
double thumbnailGridInitialOffset({
  required int index,
  required int columns,
  required double rowHeight,
}) {
  if (columns <= 0 || rowHeight <= 0 || index < 0) return 0;
  final row = index ~/ columns;
  // 往上留半行，让当前页不至于紧贴顶边。
  final target = row * rowHeight - rowHeight * 0.5;
  return target < 0 ? 0 : target;
}

/// 全局缩略图：把整本作品（哪怕只有一张）铺成一个网格。
///
/// 刻意只吃 [List<ViewerUrls>] 而不是 Illusts：单图作品的图片放在
/// metaSinglePage 里、metaPages 是空的，解耦之后两种情况共用同一套。
class PageThumbnailGrid extends StatefulWidget {
  final List<ViewerUrls> pages;
  final int currentIndex;

  /// 每行几张。
  final int columns;

  /// 缩略图形状。
  final ThumbnailShape shape;

  /// 长按某张缩略图：下载该页原图。
  final ValueChanged<int>? onLongPressPage;

  /// 在展开页里切换形状时回调，用于持久化到设置。
  final ValueChanged<ThumbnailShape>? onShapeChanged;

  const PageThumbnailGrid({
    super.key,
    required this.pages,
    required this.currentIndex,
    this.columns = 5,
    this.shape = ThumbnailShape.uniform,
    this.onLongPressPage,
    this.onShapeChanged,
  });

  @override
  State<PageThumbnailGrid> createState() => _PageThumbnailGridState();
}

class _PageThumbnailGridState extends State<PageThumbnailGrid> {
  final ScrollController _controller = ScrollController();
  bool _didInitialScroll = false;

  /// 当前选中的页码。顶部进度条改它，关闭时以它作为结果返回。
  late int _selectedIndex = widget.currentIndex;

  /// 就地切换形状，改完同时写回设置，两处保持一致。
  late ThumbnailShape _shape = widget.shape;

  static const double _spacing = 8.0;
  static const double _padding = 8.0;
  static const double _aspectRatio = 0.72;

  int get _pageCount => widget.pages.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把选中的那一页滚进视野。
  void _scrollToSelected(double availableWidth, {bool animate = true}) {
    final rowHeight = thumbnailGridRowHeight(
      availableWidth: availableWidth,
      columns: widget.columns,
      spacing: _spacing,
      horizontalPadding: _padding,
      aspectRatio: _aspectRatio,
    );
    final target = thumbnailGridInitialOffset(
      index: _selectedIndex,
      columns: widget.columns,
      rowHeight: rowHeight,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      final clamped = target > max ? max : target;
      if (animate) {
        _controller.animateTo(
          clamped,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _controller.jumpTo(clamped);
      }
    });
  }

  void _scheduleInitialScroll(double availableWidth) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    _scrollToSelected(availableWidth, animate: false);
  }

  void _onSliderChanged(double value, double availableWidth) {
    final next = value.round();
    if (next == _selectedIndex) return;
    setState(() {
      _selectedIndex = next;
    });
    _scrollToSelected(availableWidth);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: thumbnailGridHeight(MediaQuery.of(context).size.height),
      // 用 Material 而不是 Container：Slider 需要 Material 祖先，
      // 只看 showModalBottomSheet 提供的话就是个隐式依赖，很容易踩坑。
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 4),
              child: _buildHeader(),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _scheduleInitialScroll(constraints.maxWidth);
                  return _buildGrid(primary);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部栏：标题左对齐，进度条占住中间（尽量长），
  /// 页数 + 形状开关 + 关闭全部右对齐。
  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          I18n.of(context).thumbnail_grid_title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Expanded(child: _buildHeaderSlider()),
        Text(
          '${_selectedIndex + 1}/$_pageCount',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _buildShapeToggle(),
        _compactIcon(
          icon: Icons.close,
          // 返回当前选中页，进度条的选择才会生效。
          onPressed: () => Navigator.of(context).pop(_selectedIndex),
        ),
      ],
    );
  }

  /// 顶栏图标比默认的紧凑，把空间让给进度条。
  Widget _compactIcon({required IconData icon, VoidCallback? onPressed}) {
    return IconButton(
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  /// 右上角的形状开关：一键在"统一大小"和"按原图比例"之间切换。
  Widget _buildShapeToggle() {
    final uniform = _shape == ThumbnailShape.uniform;
    final label = uniform
        ? I18n.of(context).thumbnail_shape_uniform
        : I18n.of(context).thumbnail_shape_original;
    return Tooltip(
      message: '${I18n.of(context).thumbnail_shape}: $label',
      child: _compactIcon(
        // 统一大小 = 方方正正的格子；按原图比例 = 自由形状。
        icon: uniform ? Icons.crop_square : Icons.aspect_ratio,
        onPressed: () {
          final next = _shape.toggled;
          setState(() {
            _shape = next;
          });
          widget.onShapeChanged?.call(next);
        },
      ),
    );
  }

  Widget _buildHeaderSlider() {
    final max = (_pageCount - 1).toDouble();
    final safeMax = max < 0 ? 0.0 : max;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
        activeTrackColor: Theme.of(context).colorScheme.primary,
        inactiveTrackColor: Colors.black12,
      ),
      child: Slider(
        value: _selectedIndex.toDouble().clamp(0.0, safeMax),
        min: 0.0,
        max: safeMax,
        divisions: _pageCount > 1 ? _pageCount - 1 : null,
        onChanged: (value) => _onSliderChanged(
          value,
          MediaQuery.of(context).size.width,
        ),
      ),
    );
  }

  Widget _buildGrid(Color primary) {
    return GridView.builder(
      controller: _controller,
      padding: const EdgeInsets.all(_padding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        mainAxisSpacing: _spacing,
        crossAxisSpacing: _spacing,
        childAspectRatio: _aspectRatio,
      ),
      itemCount: _pageCount,
      itemBuilder: (context, index) => _buildCell(context, index, primary),
    );
  }

  Widget _buildCell(BuildContext context, int index, Color primary) {
    final selected = index == _selectedIndex;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(index),
      // 长按直接下载这一页的原图。
      onLongPress: widget.onLongPressPage == null
          ? null
          : () {
              widget.onLongPressPage!(index);
              setState(() {
                _selectedIndex = index;
              });
            },
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? primary : Colors.black12,
                  width: selected ? 2.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: PixivImage(
                widget.pages[index].medium ?? '',
                // PixivImage 在 initState 里把 fit 存了一份状态副本，
                // 不换 key 的话改 fit 对已存在的元素不起作用，
                // 表现为"要点出去重进一次才生效"。
                key: ValueKey('thumb_${index}_${_shape.name}'),
                fit: _shape.fit,
                fade: false,
                enableMemoryCache: false,
                placeWidget: Container(color: Colors.black12),
              ),
            ),
          ),
          const SizedBox(height: 3),
          // 页码强制 LTR，免得 RTL 环境下数字顺序看着别扭。
          Text(
            '${index + 1}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
