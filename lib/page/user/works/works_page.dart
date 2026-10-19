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

import 'dart:math';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/component/illust_filter_sheet.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/illust_filter.dart';
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class WorksPage extends StatefulWidget {
  final int id;
  final String portal;
  final LightingStore store;
  final String workType;
  final ValueChanged<String> onWorkTypeChange;

  const WorksPage(
      {Key? key,
      required this.id,
      required this.store,
      required this.portal,
      required this.workType,
      required this.onWorkTypeChange})
      : super(key: key);

  @override
  _WorksPageState createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage> {
  late LightingStore _store;
  late EasyRefreshController _easyRefreshController;
  late String _workType;

  /// 页数 / 观看数 / 点赞数 / 标签筛选。纯本地过滤，进页面时从上次的选择恢复。
  late IllustFilter _filter = loadIllustFilter(IllustFilterScope.userWorks);

  /// 过滤后实际要显示的列表。
  ///
  /// 这个页面没走 `LightingList`（排序条要在 pinned header 里），
  /// 所以"渲染时计算、不动原始数据"得在这儿自己再做一遍：
  /// 否则改筛选条件后已经被删掉的条目就回不来了。
  List<IllustStore> _visibleStores = const [];

  /// 筛得太狠时主动多拉几页，避免列表撑不满一屏就再也触发不了"加载更多"。
  bool _backfilling = false;
  int _backfillRounds = 0;
  static const int _filterTargetCount = 12;
  static const int _maxBackfillRounds = 4;

  @override
  void initState() {
    _easyRefreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _store = widget.store;
    _store.easyRefreshController = _easyRefreshController;
    super.initState();
    _store.fetch();
    _workType = widget.workType;
  }

  @override
  void dispose() {
    _easyRefreshController.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return _buildContent(context);
    });
  }

  /// 按当前筛选条件算出可见列表。
  List<IllustStore> _computeVisible() {
    final all = _store.iStores;
    if (_filter.isAny) return all.toList(growable: false);
    return all
        .where((e) => e.illusts != null && _filter.matches(e.illusts!))
        .toList(growable: false);
  }

  /// 过滤后条目太少时，继续拉取更多投稿直到够一屏或到达上限。
  Future<void> _backfillForFilter() async {
    if (_backfilling) return;
    if (_filter.isAny) return;
    if (!shouldFetchMoreForFilter(
      visibleCount: _visibleStores.length,
      targetCount: _filterTargetCount,
      nextUrl: _store.nextUrl,
      roundsDone: _backfillRounds,
      maxRounds: _maxBackfillRounds,
    )) {
      return;
    }
    _backfilling = true;
    try {
      while (mounted &&
          shouldFetchMoreForFilter(
            visibleCount: _visibleStores.length,
            targetCount: _filterTargetCount,
            nextUrl: _store.nextUrl,
            roundsDone: _backfillRounds,
            maxRounds: _maxBackfillRounds,
          )) {
        final before = _store.iStores.length;
        _backfillRounds++;
        await _store.fetchNext();
        if (!mounted) return;
        _visibleStores = _computeVisible();
        // 没有拿到新数据就收手，避免空转。
        if (_store.iStores.length == before) break;
      }
    } finally {
      _backfilling = false;
      if (mounted) setState(() {});
    }
  }

  /// 延后一帧再补足，避免在 build 期间触发网络请求与 setState。
  void _scheduleBackfill() {
    if (_filter.isAny) return;
    if (_visibleStores.length >= _filterTargetCount) return;
    if (_backfillRounds >= _maxBackfillRounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backfillForFilter();
    });
  }

  Widget _buildContent(context) {
    return _store.errorMessage != null && _store.iStores.isEmpty
        ? _buildErrorContent(context)
        : _buildWorks(context);
  }

  Widget _buildErrorContent(context) {
    return Container(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            height: 50,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                Text(':(', style: Theme.of(context).textTheme.headlineMedium),
          ),
          TextButton(
              onPressed: () {
                _store.fetch(force: true);
              },
              child: Text(I18n.of(context).retry)),
          Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                (_store.errorMessage?.contains("400") == true
                    ? '${I18n.of(context).error_400_hint}\n ${_store.errorMessage}'
                    : '${_store.errorMessage}'),
              ))
        ],
      ),
    );
  }

  Widget _buildWorks(BuildContext context) {
    return SafeArea(
        top: false,
        bottom: false,
        child: Builder(
          builder: (BuildContext context) {
            return EasyRefresh.builder(
                controller: _easyRefreshController,
                onLoad: () {
                  _store.fetchNext();
                },
                onRefresh: () {
                  _store.fetch(force: true);
                },
                header: PixezDefault.header(
                  context,
                  position: IndicatorPosition.locator,
                  safeArea: false,
                ),
                footer: PixezDefault.footer(
                  context,
                  position: IndicatorPosition.locator,
                ),
                childBuilder: (context, phy) {
                  return Observer(builder: (_) {
                    // 筛选是渲染时计算的：原始 iStores 不动，
                    // 这样改条件能让之前被隐藏的投稿重新出现。
                    _store.iStores.removeWhere(
                        (element) => element.illusts!.hateByUser(ai: false));
                    _visibleStores = _computeVisible();
                    _scheduleBackfill();
                    return CustomScrollView(
                      physics: phy,
                      key: PageStorageKey<String>(widget.portal),
                      slivers: [
                        SliverPinnedOverlapInjector(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                  context),
                        ),
                        const HeaderLocator.sliver(),
                        SliverPersistentHeader(
                            delegate: SliverChipDelegate(
                                Container(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      _buildSortChip(),
                                      // 筛选按钮靠右，排序条保持居中。
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                              right: 4.0),
                                          child: IllustFilterButton(
                                            scope: IllustFilterScope.userWorks,
                                            filter: _filter,
                                            onChanged: (filter) => setState(() {
                                              _filter = filter;
                                              // 换了条件就重新给补足逻辑一次机会。
                                              _backfillRounds = 0;
                                            }),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                height: 52),
                            pinned: true),
                        if (_store.refreshing && _store.iStores.isEmpty)
                          SliverToBoxAdapter(
                            child: Container(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        _buildSliverContent(context),
                        const FooterLocator.sliver(),
                      ],
                    );
                  });
                });
          },
        ));
  }

  SliverWaterfallFlowDelegate _buildGridDelegate() {
    var count = 2;
    if (MediaQuery.of(context).orientation == Orientation.portrait
        ? userSetting.crossAdapt
        : userSetting.hCrossAdapt) {
      count = _buildSliderValue();
    } else {
      count = (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
    return SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
    );
  }

  /// 列表主体。有数据但被筛光时给提示 + 手动入口——
  /// 空白列表滚不动，会卡住"加载更多"。
  Widget _buildSliverContent(BuildContext context) {
    if (_visibleStores.isNotEmpty) {
      return SliverWaterfallFlow(
        gridDelegate: _buildGridDelegate(),
        delegate: _buildSliverChildBuilderDelegate(context),
      );
    }
    if (_store.iStores.isNotEmpty) {
      return SliverToBoxAdapter(child: _buildFilteredEmpty(context));
    }
    return SliverToBoxAdapter(child: Container(height: 30));
  }

  Widget _buildFilteredEmpty(BuildContext context) {
    return Container(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              I18n.of(context).filter_no_result,
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: _backfilling
                ? null
                : () {
                    _backfillRounds = 0;
                    _backfillForFilter();
                  },
            child: Text(
              _backfilling
                  ? I18n.of(context).footer_loading
                  : I18n.of(context).load_more,
            ),
          ),
        ],
      ),
    );
  }

  SliverChildBuilderDelegate _buildSliverChildBuilderDelegate(
      BuildContext context) {
    return SliverChildBuilderDelegate((BuildContext context, int index) {
      return IllustCard(
        lightingStore: _store,
        store: _visibleStores[index],
        // 点开后的上一张/下一张也只在筛选结果里走，不会跳到被筛掉的投稿。
        iStores: _visibleStores,
      );
    }, childCount: _visibleStores.length);
  }

  int _buildSliderValue() {
    final currentValue =
        (MediaQuery.of(context).orientation == Orientation.portrait
                ? userSetting.crossAdapterWidth
                : userSetting.hCrossAdapterWidth)
            .toDouble();
    var nowAdaptWidth = max(currentValue, 50.0);
    nowAdaptWidth = min(nowAdaptWidth, 2160.0);
    final screenWidth = MediaQuery.of(context).size.width;
    final result = max(screenWidth / nowAdaptWidth, 1.0).toInt();
    return result;
  }

  Widget _buildSortChip() {
    return SortGroup(
      onChange: (index) {
        final type = index == 0 ? 'illust' : 'manga';
        setState(() {
          _workType = type;
          // 换了一类投稿，补足轮数重新算，否则切过去发现筛空了却不再补。
          _backfillRounds = 0;
        });
        widget.onWorkTypeChange(_workType);
        _store.source = ApiForceSource(
            futureGet: (bool e) => apiClient.getUserIllusts(widget.id, type));
        _store.fetch();
      },
      children: [
        I18n.of(context).illust,
        I18n.of(context).manga,
      ],
      initIndex: _workType == 'illust' ? 0 : 1,
    );
  }
}

class SliverPinnedOverlapInjector extends SingleChildRenderObjectWidget {
  const SliverPinnedOverlapInjector({
    required this.handle,
    Key? key,
  }) : super(key: key);

  final SliverOverlapAbsorberHandle handle;

  @override
  RenderSliverPinnedOverlapInjector createRenderObject(BuildContext context) {
    return RenderSliverPinnedOverlapInjector(
      handle: handle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPinnedOverlapInjector renderObject,
  ) {
    renderObject.handle = handle;
  }
}

class RenderSliverPinnedOverlapInjector extends RenderSliver {
  RenderSliverPinnedOverlapInjector({
    required SliverOverlapAbsorberHandle handle,
  }) : _handle = handle;

  double? _currentLayoutExtent;
  double? _currentMaxExtent;

  SliverOverlapAbsorberHandle get handle => _handle;
  SliverOverlapAbsorberHandle _handle;

  set handle(SliverOverlapAbsorberHandle value) {
    if (handle == value) return;
    if (attached) {
      handle.removeListener(markNeedsLayout);
    }
    _handle = value;
    if (attached) {
      handle.addListener(markNeedsLayout);
      if (handle.layoutExtent != _currentLayoutExtent ||
          handle.scrollExtent != _currentMaxExtent) markNeedsLayout();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    handle.addListener(markNeedsLayout);
    if (handle.layoutExtent != _currentLayoutExtent ||
        handle.scrollExtent != _currentMaxExtent) markNeedsLayout();
  }

  @override
  void detach() {
    handle.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    _currentLayoutExtent = handle.layoutExtent;

    final paintedExtent = min(
      _currentLayoutExtent!,
      constraints.remainingPaintExtent - constraints.overlap,
    );

    geometry = SliverGeometry(
      paintExtent: paintedExtent,
      maxPaintExtent: _currentLayoutExtent!,
      maxScrollObstructionExtent: _currentLayoutExtent!,
      paintOrigin: constraints.overlap,
      scrollExtent: _currentLayoutExtent!,
      layoutExtent: max(0, paintedExtent - constraints.scrollOffset),
      hasVisualOverflow: paintedExtent < _currentLayoutExtent!,
    );
  }
}

class SliverChipDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  double height = 45;

  SliverChipDelegate(this.child, {this.height = 45});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(SliverChipDelegate oldDelegate) {
    // 以前恒为 false：这个 header 里的排序条自己管状态，不需要重建。
    // 但现在里面还放了筛选按钮，它的角标要跟着 `_filter` 变，
    // 返回 false 会让外层 setState 传下来的新 child 被丢掉（角标不刷新）。
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
