import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixez/utils/haptic_util.dart';

/// 分步推进时最多走几步，防止异常情况下死循环。
const int _maxRevealSteps = 80;

/// 锚点是否已经布局出来。
///
/// 懒加载列表里离屏太远的东西压根不会被建，这时 currentContext 是空的。
bool _anchorReady(GlobalKey anchorKey) {
  final ro = anchorKey.currentContext?.findRenderObject();
  return ro is RenderBox && ro.attached && ro.hasSize;
}

/// 把详情锚点滚进视野。
///
/// 锚点已经布局好就直接滚过去；还没布局（在很下面）就先往下推，逼它布局，
/// 再精确定位。
///
/// 注意这里刻意**不**用 `animateTo(maxScrollExtent)` 那种一步到底的写法：
/// 懒加载列表的 maxScrollExtent 是**估算值**，只布局了第一个超长子项时会
/// 离谱地大（实测真实末尾 2810 被估成 8400）。冲过去会停在越界位置回不来，
/// 画面直接空白，锚点也照样没建出来——表现就是"点了没反应"。
///
/// 改成按视口一步步往下推，每步等一帧让布局跟上、用最新尺寸重算。
/// jumpTo 是瞬时的，所以多走几步也不会卡顿。
Future<void> revealDetailAnchor({
  required GlobalKey anchorKey,
  required ScrollController scrollController,
  double alignment = 0.5,
}) async {
  if (_anchorReady(anchorKey)) {
    await _ensureAnchorVisible(anchorKey, alignment);
    return;
  }
  if (!scrollController.hasClients) return;

  for (var i = 0; i < _maxRevealSteps; i++) {
    if (_anchorReady(anchorKey)) break;
    final pos = scrollController.position;
    final next = math.min(
      pos.maxScrollExtent,
      pos.pixels + pos.viewportDimension * 0.9,
    );
    // 已经到底了，再推也没用
    if (next <= pos.pixels + 1) break;
    scrollController.jumpTo(next);
    await WidgetsBinding.instance.endOfFrame;
  }

  if (_anchorReady(anchorKey)) {
    await _ensureAnchorVisible(anchorKey, alignment);
  }
}

/// 平滑地把锚点滚到视口中间。
Future<void> _ensureAnchorVisible(GlobalKey anchorKey, double alignment) async {
  final anchorContext = anchorKey.currentContext;
  final ro = anchorContext?.findRenderObject();
  if (anchorContext == null || ro is! RenderBox || !ro.attached) return;

  await Scrollable.ensureVisible(
    anchorContext,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
    alignment: alignment,
  );

  // clamped = 锚点仍在视口下方（相关作品网格还在加载 -> 最大滚动范围太小）。
  // 等一次再纠正，否则就停在这儿。
  // 成功落位时锚点顶部约在 screenH/2 - h/2。
  final screenH = MediaQuery.of(anchorContext).size.height;
  if (ro.attached && ro.localToGlobal(Offset.zero).dy > screenH - 24) {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!ro.attached) return;
    await Scrollable.ensureVisible(
      anchorContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: alignment,
    );
  }
}

/// 锚点当前是否在视口下方（还没滚到）。
bool detailAnchorIsBelow({
  required GlobalKey anchorKey,
  required double screenHeight,
}) {
  final ro = anchorKey.currentContext?.findRenderObject();
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return true;
  return ro.localToGlobal(Offset.zero).dy > screenHeight;
}

/// Top-bar button that jumps to the detail (author info) anchor of the
/// illust detail page. Tracks whether the anchor sits below or above the
/// current viewport and flips its chevron accordingly.
class DetailJumpButton extends StatefulWidget {
  final GlobalKey anchorKey;
  final ScrollController scrollController;

  const DetailJumpButton({
    super.key,
    required this.anchorKey,
    required this.scrollController,
  });

  @override
  State<DetailJumpButton> createState() => _DetailJumpButtonState();
}

class _DetailJumpButtonState extends State<DetailJumpButton> {
  bool _anchorBelow = true;
  double? _screenH;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenH = MediaQuery.of(context).size.height;
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    // Notification callbacks run before the frame re-layouts, so geometry
    // read here is stale. Defer the computation to after the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAnchorState();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Recompute the anchor direction from fresh layout; rebuild on change.
  /// Safe to call from async completions and post-frame callbacks.
  void _refreshAnchorState() {
    final below = detailAnchorIsBelow(
      anchorKey: widget.anchorKey,
      screenHeight: _screenH ?? 800,
    );
    if (below != _anchorBelow) {
      _anchorBelow = below;
      if (mounted) setState(() {});
    }
  }

  Future<void> _jump() async {
    HapticUtil.selectionClick();
    await revealDetailAnchor(
      anchorKey: widget.anchorKey,
      scrollController: widget.scrollController,
    );
    _refreshAnchorState();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_anchorBelow ? Icons.expand_more : Icons.expand_less),
      onPressed: _jump,
    );
  }
}
