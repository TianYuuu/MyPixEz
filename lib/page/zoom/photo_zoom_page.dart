import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixez/clipboard_plugin.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/zoom/page_thumbnail_bar.dart';
import 'package:pixez/page/zoom/page_thumbnail_grid.dart';
import 'package:pixez/page/zoom/tap_zone.dart';
import 'package:pixez/page/zoom/viewer_quality.dart';
import 'package:pixez/page/zoom/tap_zone_overlay.dart';
import 'package:pixez/utils/haptic_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart';

class PhotoZoomPage extends StatefulWidget {
  final int index;
  final Illusts illusts;
  final IllustStore illustStore;

  const PhotoZoomPage({
    Key? key,
    required this.index,
    required this.illusts,
    required this.illustStore,
  }) : super(key: key);

  @override
  _PhotoZoomPageState createState() => _PhotoZoomPageState();
}

class _PhotoZoomPageState extends State<PhotoZoomPage> {
  late Illusts _illusts;
  int _index = 0;
  late PageController _pageController;

  /// 用来把点击的全局坐标换算到查看器区域内，以便判定落在哪个点击分区。
  final GlobalKey _viewerKey = GlobalKey();

  /// 底部工具栏与缩略图条是否可见。点击分区的"menu"动作会切换它。
  ///
  /// 默认收起（和 JHenTai 一样），进页面时图片占满全屏，
  /// 点一下中间才浮出缩略图条和工具栏。
  /// 进入看图页就显示底部横条，省得还要先点一下中间。
  bool _uiVisible = true;

  /// 进入时短暂显示的分区提示层。
  bool _overlayVisible = false;
  Timer? _overlayTimer;

  /// 当前页是否已经换成最终画质。
  ///
  /// 翻页/滑动途中先用缩略图条已经在缓存的 medium 顶上，避免黑屏；
  /// 停稳后再换成大图（或原图）。
  bool _currentIsFinal = true;
  Timer? _settleTimer;

  /// 停稳的判定时长。每次翻页都会重置，所以连续滑动不会触发升级。
  static const Duration _settleDelay = Duration(milliseconds: 200);

  /// 判定为"上滑"的竖直速度阈值（像素/秒，负数是向上）。
  static const double _swipeUpVelocity = -260;

  /// 判定为"上滑"的累计距离阈值（逻辑像素）。
  static const double _swipeUpMinDistance = 80;

  /// 本次竖直拖动累计往上拖了多远。
  double _swipeUpAccumulated = 0;

  /// 分区提示层停留时长。
  static const Duration _overlayDuration = Duration(milliseconds: 1800);
  static const Duration _overlayFade = Duration(milliseconds: 350);

  @override
  void initState() {
    _loadSource = userSetting.zoomQuality == 1;
    _illusts = widget.illusts;
    _index = widget.index;
    _pageController = PageController(initialPage: _index);
    nowUrl = _illusts.pageCount == 1
        ? (_loadSource
              ? _illusts.metaSinglePage!.originalImageUrl!
              : _illusts.imageUrls.large)
        : (_loadSource
              ? _illusts.metaPages[_index].imageUrls!.original
              : _illusts.metaPages[_index].imageUrls!.large);

    // 点击分区被禁用时没有任何"menu"动作可选，
    // 界面若默认收起就再也唤不出来了，所以这种情况强制展开。
    if (TapZoneModeValue.fromValue(userSetting.tapZoneMode) ==
        TapZoneMode.disabled) {
      _uiVisible = true;
    }
    super.initState();
    initCache();
    _maybeShowOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAhead();
    });
  }

  /// 按设置决定是否在进入时展示一次分区提示。
  void _maybeShowOverlay() {
    if (!userSetting.showTapZoneOverlay) return;
    // 单图没有翻页分区可言，不打扰。
    if (_illusts.pageCount <= 1 || _illusts.metaPages.isEmpty) return;
    _overlayVisible = true;
    _overlayTimer = Timer(_overlayDuration, () {
      if (mounted) {
        setState(() {
          _overlayVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _settleTimer?.cancel();
    _pageController.dispose();
    if (_fullScreen)
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    super.dispose();
  }

  initCache() async {
    var fileInfo = await pixivCacheManager!.getFileFromCache(nowUrl);
    if (mounted)
      setState(() {
        shareShow = fileInfo != null;
      });
  }

  /// 记录当前页并同步分享按钮的可用状态。
  void _applyIndex(int index) {
    // nowUrl 始终记"最终要显示的那张"，分享按钮据此判断缓存是否就绪。
    nowUrl = _loadSource
        ? _illusts.metaPages[index].imageUrls!.original
        : _illusts.metaPages[index].imageUrls!.large;
    _index = index;
    shareShow = false;
    // 先退回缩略图占位，等停稳后再升级。
    // 调用点都在 setState 里（onPageChanged 与 _jumpTo），字段改动会立刻生效。
    _currentIsFinal = false;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, _upgradeCurrent);
  }

  /// 停稳后把当前页从缩略图占位换成最终画质。
  ///
  /// 先把最终图放进内存缓存再切 provider：CachedNetworkImageProvider 按 URL
  /// 做相等性判断，命中缓存时切换是瞬时的，不会闪一下白屏。
  /// 反过来说，如果最终图本来就在缓存里（预加载生效了），
  /// 这里几乎同步完成，用户看不出"先糊后清"的过程。
  Future<void> _upgradeCurrent() async {
    if (!mounted) return;
    final index = _index;
    final finalUrl = _settledUrlFor(index);
    if (finalUrl.isEmpty) {
      setState(() {
        _currentIsFinal = true;
      });
      return;
    }
    var failed = false;
    await precacheImage(
      PixivProvider.url(finalUrl),
      this.context,
      onError: (error, stack) => failed = true,
    );
    // 期间可能又翻页了，过期的结果直接丢弃。
    if (!mounted || index != _index) return;
    if (failed) {
      // 最终图拿不到就留在缩略图上，至少画面是完整的，不是黑的。
      return;
    }
    setState(() {
      _currentIsFinal = true;
    });
    _prefetchAhead();
  }

  /// 提前加载后面几张。
  ///
  /// 只取大图、绝不取原图：原图体积大，预取会拖慢当前这张的加载，
  /// 也白白消耗流量。真正需要原图时由 _upgradeCurrent 单独处理当前页。
  void _prefetchAhead() {
    final count = userSetting.prefetchCount;
    if (count <= 0) return;
    final pages = _illusts.metaPages;
    if (pages.length <= 1) return;
    final targets = prefetchTargets(
      currentIndex: _index,
      prefetchCount: count,
      pageCount: pages.length,
      largeUrls: [for (final page in pages) page.imageUrls?.large],
    );
    for (final index in targets) {
      precacheImage(
        PixivProvider.url(pages[index].imageUrls!.large),
        this.context,
        onError: (error, stack) {},
      ).ignore();
    }
  }

  /// 整本作品的页面列表。
  ///
  /// 单图作品的图片放在 metaSinglePage 里、metaPages 是空的，
  /// 这里统一成一份列表，缩略图条和全屏网格都不用再区分两种情况。
  List<ViewerUrls> _viewerPages() {
    if (_illusts.metaPages.isNotEmpty) {
      return [
        for (final page in _illusts.metaPages)
          ViewerUrls(
            medium: page.imageUrls?.medium,
            large: page.imageUrls?.large,
            original: page.imageUrls?.original,
          ),
      ];
    }
    return [
      ViewerUrls(
        medium: _illusts.imageUrls.medium,
        large: _illusts.imageUrls.large,
        original: _illusts.metaSinglePage?.originalImageUrl,
      ),
    ];
  }

  /// 把一页的三个画质地址取出来交给纯函数决策。
  ViewerUrls _urlsOf(int index) {
    if (_illusts.metaPages.isEmpty) return _viewerPages().first;
    final urls = _illusts.metaPages[index].imageUrls;
    return ViewerUrls(
      medium: urls?.medium,
      large: urls?.large,
      original: urls?.original,
    );
  }

  /// 按画质设置算出的"最终图"，忽略过渡状态。转场标记也用它。
  String _settledUrlFor(int index) =>
      settledUrlOf(_urlsOf(index), preferOriginal: _loadSource);

  /// 某个索引当前实际该显示哪张。
  String _urlFor(int index) => viewerUrlFor(
    _urlsOf(index),
    preferOriginal: _loadSource,
    isCurrent: index == _index,
    currentIsFinal: _currentIsFinal,
  );

  Future<void> _refreshShareState() async {
    final url = nowUrl;
    final file = await pixivCacheManager!.getFileFromCache(url);
    // 期间可能已经翻到别的页，只接受仍然对应当前 URL 的结果。
    if (mounted && url == nowUrl) {
      setState(() {
        shareShow = file != null;
      });
    }
  }

  /// 处理点击分区：左右翻页或开关界面。
  ///
  /// 单图作品没有上一张/下一张，所以点击一律用来开关界面。
  void _handleTapUp(TapUpDetails details) {
    if (_illusts.pageCount <= 1 || _illusts.metaPages.isEmpty) {
      _toggleUi();
      return;
    }
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    // 注意：本文件导入了 package:path，它有一个名为 context 的全局变量，
    // 会遮蔽 State.context，所以这里必须显式写成 this.context。
    final size = box?.size ?? MediaQuery.sizeOf(this.context);
    final local = box != null
        ? box.globalToLocal(details.globalPosition)
        : details.localPosition;
    final action = resolveTapZone(
      TapZoneModeValue.fromValue(userSetting.tapZoneMode),
      local,
      size,
      invert: TapZoneInvertValue.fromValue(userSetting.tapZoneInvert),
    );
    switch (action) {
      case TapZoneAction.previous:
        _jumpTo(_index - 1);
        break;
      case TapZoneAction.next:
        _jumpTo(_index + 1);
        break;
      case TapZoneAction.menu:
        _toggleUi();
        break;
      case TapZoneAction.none:
        break;
    }
  }

  void _toggleUi() {
    HapticUtil.selectionClick();
    setState(() {
      _uiVisible = !_uiVisible;
    });
  }

  /// 直接跳页。刻意不使用滚动动画，避免快速翻页时画面晃眼。
  ///
  /// [haptic] 在进度条连续拖动时置为 false，否则会一路震个不停。
  void _jumpTo(int target, {bool haptic = true}) {
    if (target < 0 || target >= _illusts.metaPages.length) return;
    if (target == _index) return;
    if (haptic) HapticUtil.selectionClick();
    setState(() {
      _applyIndex(target);
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
    _refreshShareState();
  }

  /// 上滑缩略图条展开成全局网格；选中哪张就跳哪张。
  Future<void> _openThumbnailGrid() async {
    if (_viewerPages().isEmpty) return;
    HapticUtil.light();
    final target = await showModalBottomSheet<int>(
      context: this.context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PageThumbnailGrid(
        pages: _viewerPages(),
        currentIndex: _index,
        columns: userSetting.thumbnailGridColumns,
        shape: ThumbnailShape.fromValue(userSetting.thumbnailShape),
        onLongPressPage: _downloadPage,
        onShapeChanged: (shape) => userSetting.setThumbnailShape(shape.value),
      ),
    );
    if (!mounted) return;
    // 展开页里可能改过形状，重建一次让底部横条也跟着变。
    setState(() {});
    if (target != null) _jumpTo(target);
  }

  /// 长按图片保存当前这一张。
  Future<void> _longPressSave() async {
    HapticUtil.heavy();
    if (userSetting.longPressSaveConfirm) {
      final confirmed = await showDialog<bool>(
        context: this.context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(I18n.of(dialogContext).save),
            content: Text(_illusts.title),
            actions: <Widget>[
              TextButton(
                child: Text(I18n.of(dialogContext).cancel),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                child: Text(I18n.of(dialogContext).ok),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }
    _saveCurrent();
  }

  /// 长按缩略图时下载这一页的原图。
  ///
  /// saveImage 内部固定取 imageUrls.original，所以这里不用另写下载逻辑。
  void _downloadPage(int index) {
    if (index < 0 || index >= _illusts.metaPages.length) return;
    HapticUtil.heavy();
    saveStore.saveImage(_illusts, index: index);
    BotToast.showText(
      text: I18n.of(this.context).download_original_toast(index + 1),
    );
  }

  void _saveCurrent() {
    if (_illusts.metaPages.isNotEmpty) {
      saveStore.saveImage(_illusts, index: _index);
    } else {
      saveStore.saveImage(_illusts);
    }
    if (userSetting.starAfterSave && (widget.illustStore.state == 0)) {
      widget.illustStore.star(
        restrict: userSetting.defaultPrivateLike ? "private" : "public",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Scaffold(
          extendBody: true,
          bottomNavigationBar: _uiVisible
              ? _buildBottomArea(context)
              : const SizedBox.shrink(),
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.black,
          body: GestureDetector(
            key: _viewerKey,
            onLongPress: _longPressSave,
            // 在画面上直接上滑就呼出全屏缩略图，不用先点出底部横条。
            // 图片放大之后 PhotoView 会在手势竞技场里赢走这个手势，
            // 那时它是平移，不会误触。
            onVerticalDragStart: (_) => _swipeUpAccumulated = 0,
            onVerticalDragUpdate: (details) =>
                _swipeUpAccumulated -= details.delta.dy,
            onVerticalDragEnd: (details) {
              // 快甩和慢慢拖都算：慢速拖动的 primaryVelocity 是 0，
              // 只看速度会漏判。
              final fast = (details.primaryVelocity ?? 0) < _swipeUpVelocity;
              final far = _swipeUpAccumulated > _swipeUpMinDistance;
              if (fast || far) {
                HapticUtil.light();
                _openThumbnailGrid();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildViewer(context),
                // 提示层只负责展示，不拦截点击。
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _overlayVisible ? 1 : 0,
                      duration: _overlayFade,
                      child: TapZoneOverlay(
                        mode: TapZoneModeValue.fromValue(
                          userSetting.tapZoneMode,
                        ),
                        invert: TapZoneInvertValue.fromValue(
                          userSetting.tapZoneInvert,
                        ),
                      ),
                    ),
                  ),
                ),
                // 底部常显的小号页码。必须 IgnorePointer：
                // 否则它会挡住底部那块点击分区。
                // 底部横条出现时不再显示这个浮层页码——横条本身就标了位置，
                // 重复显示反而乱。只在完全没有 UI 的时候才显示。
                if (userSetting.showPageIndicator && _hasPages && !_uiVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: _bottomRowBottom,
                    child: IgnorePointer(
                      child: SizedBox(
                        height: _bottomRowHeight,
                        child: Center(child: _buildPageIndicator()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewer(BuildContext context) {
    if (_illusts.pageCount == 1) {
      final url = _loadSource
          ? _illusts.metaSinglePage!.originalImageUrl!
          : _illusts.imageUrls.large;
      return Container(
        child: PhotoView(
          filterQuality: FilterQuality.high,
          initialScale: PhotoViewComputedScale.contained,
          heroAttributes: PhotoViewHeroAttributes(tag: url),
          imageProvider: PixivProvider.url(url),
          loadingBuilder: (context, event) => _buildLoading(event),
          onTapUp: (context, details, controllerValue) => _handleTapUp(details),
        ),
      );
    }
    return ScrollConfiguration(
      // Flutter excludes mouse from dragDevices by default (#1308).
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.mouse,
        },
      ),
      child: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        pageController: _pageController,
        // 从右到左阅读：第 1 张在最右侧，向左依次是 2、3、4。
        reverse: userSetting.readRightToLeft,
        builder: (BuildContext context, int index) {
          final url = _urlFor(index);
          return PhotoViewGalleryPageOptions(
            imageProvider: PixivProvider.url(url),
            initialScale: PhotoViewComputedScale.contained,
            // tag 固定用最终图：占位阶段换 provider 时转场标记保持不变。
            heroAttributes: PhotoViewHeroAttributes(tag: _settledUrlFor(index)),
            filterQuality: FilterQuality.high,
            onTapUp: (context, details, controllerValue) =>
                _handleTapUp(details),
          );
        },
        itemCount: _illusts.metaPages.length,
        onPageChanged: (index) async {
          setState(() {
            _applyIndex(index);
          });
          await _refreshShareState();
        },
        loadingBuilder: (context, event) => _buildLoading(event),
      ),
    );
  }

  String nowUrl = "";

  bool show = false;
  bool shareShow = false;
  bool _loadSource = false;
  bool _fullScreen = false;

  /// 底部整块：缩略图条在上，工具栏在下。
  Widget _buildBottomArea(BuildContext context) {
    if (_fullScreen) return _buildBottom(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (userSetting.showThumbnailBar && _hasPages) _buildThumbnailStrip(),
        // 进度条已经搬到全局网格的顶部栏，这里不再重复占位置。
        _buildBottom(context),
      ],
    );
  }

  /// 至少有一页可以展示（单图作品也算，这样体验统一）。
  bool get _hasPages => _viewerPages().isNotEmpty;

  /// 底部缩略图条。按住往上一滑就展开成全局网格。
  ///
  /// 这里不再单独占一行画把手，改成把把手叠在缩略图上方几像素处，
  /// 整条能矮一点、更贴近屏幕底部，少挡住当前这张图。
  Widget _buildThumbnailStrip() {
    return ColoredBox(
      // 比原来浅一些，少压暗画面。
      color: Colors.black.withValues(alpha: 0.25),
      child: GestureDetector(
        // 与缩略图自身的横向滚动方向垂直，不会互相抢手势。
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < 0) _openThumbnailGrid();
        },
        child: Stack(
          children: [
            PageThumbnailBar(
              illusts: _illusts,
              currentIndex: _index,
              reverse: userSetting.thumbnailStripRightToLeft,
              itemSize: userSetting.thumbnailStripSize,
              onTap: _jumpTo,
              // 像 iOS 相册那样：滑到哪张居中，大图就翻到哪页。
              onCenteredIndexChanged: _onThumbnailScrubbed,
              onLongPressPage: _downloadPage,
            ),
            // 上滑提示把手，点它也能直接展开全局网格。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openThumbnailGrid,
                child: Container(
                  height: 8,
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 横条滚到某一页居中时同步大图。
  void _onThumbnailScrubbed(int index) {
    if (index == _index) return;
    if (userSetting.thumbnailScrubHaptic) HapticUtil.selectionClick();
    _jumpTo(index, haptic: false);
  }

  /// 底部一行的高度。
  ///
  /// 常显页码和工具栏共用它，两者的图标/文字才会在同一水平线上。
  static const double _bottomRowHeight = 44;

  /// 这一行离屏幕底部（含系统手势条）的距离。
  static const double _bottomRowInset = 4;

  double get _bottomRowBottom =>
      MediaQuery.of(this.context).padding.bottom + _bottomRowInset;

  /// 底部常显的小号页码。外层撑满一行高度再居中，
  /// 这样它和工具栏那一行是严格同高的。
  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_index + 1}/${_illusts.pageCount}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 一个紧凑的工具栏图标。
  ///
  /// 默认 IconButton 是 48x48，塞进 44 高的一行会溢出，
  /// 所以这里显式收紧约束。
  Widget _toolbarIcon({
    required IconData icon,
    VoidCallback? onPressed,
    double opacity = 1,
  }) {
    return IconButton(
      iconSize: 22,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(icon, color: Colors.white.withValues(alpha: opacity)),
      onPressed: onPressed,
    );
  }

  Widget _buildBottom(BuildContext context) {
    if (_fullScreen) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _bottomRowInset),
          child: SizedBox(
            height: _bottomRowHeight,
            child: Row(
              children: [
                _toolbarIcon(
                  icon: Icons.fullscreen_exit,
                  opacity: 0.5,
                  onPressed: () {
                    setState(() {
                      _fullScreen = false;
                    });
                    SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.manual,
                      overlays: SystemUiOverlay.values,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 和底部常显页码共用同一行高与同一个底部内边距，
    // 这样左下的页数、右下的按钮和中间的页码严格在同一水平线上，
    // 省下来的高度全留给图片。
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: _bottomRowInset, left: 4, right: 4),
        child: SizedBox(
          height: _bottomRowHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  _toolbarIcon(icon: Icons.photo_library_outlined),
                  Text(
                    "${_index + 1}/${widget.illusts.pageCount}",
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium!.copyWith(color: Colors.white),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _toolbarIcon(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  _toolbarIcon(
                    icon: Icons.fullscreen,
                    onPressed: () {
                      setState(() {
                        _fullScreen = true;
                      });
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.manual,
                        overlays: [],
                      );
                    },
                  ),
                  if (ClipboardPlugin.supported)
                    _toolbarIcon(
                      icon: Icons.copy,
                      onPressed: () =>
                          ClipboardPlugin.copy(context, _illusts, _index),
                    ),
                  _toolbarIcon(icon: Icons.save_alt, onPressed: _saveCurrent),
                  AnimatedOpacity(
                    opacity: shareShow ? 1 : 0.5,
                    duration: const Duration(milliseconds: 500),
                    child: Builder(
                      builder: (context) {
                        return _toolbarIcon(
                          icon: Icons.share,
                          onPressed: () async {
                            var file = await pixivCacheManager!
                                .getFileFromCache(nowUrl);
                            if (file != null) {
                              String targetPath = join(
                                (await getTemporaryDirectory()).path,
                                "share_cache",
                                basenameWithoutExtension(file.file.path) +
                                    (nowUrl.endsWith(".png") ? ".png" : ".jpg"),
                              );
                              File targetFile = File(targetPath);
                              if (!targetFile.existsSync()) {
                                targetFile.createSync(recursive: true);
                              }
                              file.file.copySync(targetPath);
                              final box =
                                  context.findRenderObject() as RenderBox?;
                              SharePlus.instance.share(
                                ShareParams(
                                  files: [XFile(targetPath)],
                                  sharePositionOrigin:
                                      box!.localToGlobal(Offset.zero) &
                                      box.size,
                                ),
                              );
                            } else {
                              BotToast.showText(
                                text: "can not find image cache",
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                  _toolbarIcon(
                    icon: !_loadSource ? Icons.hd_outlined : Icons.hd,
                    onPressed: () {
                      setState(() {
                        _loadSource = !_loadSource;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Center _buildLoading(ImageChunkEvent? event) {
    double value = event == null || event.expectedTotalBytes == null
        ? 0
        : event.cumulativeBytesLoaded / event.expectedTotalBytes!;
    if (value == 1.0) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            shareShow = true;
          });
        }
      });
    }
    return Center(
      child: Container(
        width: 20.0,
        height: 20.0,
        child: CircularProgressIndicator(value: value),
      ),
    );
  }
}
