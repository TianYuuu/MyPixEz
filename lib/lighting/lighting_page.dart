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
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/lighting_filter.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class WaterFallLoading extends StatefulWidget {
  const WaterFallLoading({Key? key}) : super(key: key);

  @override
  State<WaterFallLoading> createState() => _WaterFallLoadingState();
}

class _WaterFallLoadingState extends State<WaterFallLoading> {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class LightingList extends StatefulWidget {
  final LightSource source;
  final Widget? header;
  final bool? isNested;
  final ScrollController? scrollController;
  final String? portal;
  final bool? ai;
  final bool Function(Illusts)? filter;

  const LightingList(
      {Key? key,
      required this.source,
      this.header,
      this.isNested,
      this.scrollController,
      this.portal,
      this.ai,
      this.filter})
      : super(key: key);

  @override
  _LightingListState createState() => _LightingListState();
}

class _LightingListState extends State<LightingList> {
  late LightingStore _store;
  late bool _isNested;
  late ScrollController _scrollController;
  late bool _ai;

  /// 过滤后实际要显示的列表。
  ///
  /// 以前是在 build 里对 [_store.iStores] 做破坏性 removeWhere，
  /// 导致"改动筛选条件后已经删掉的条目回不来"。现在改成渲染时计算：
  /// 原始数据保持不动，[widget.filter] 只是视图。这样筛选条件一变，
  /// 已经加载过的数据可以立刻重新参与判断，不必重新搜索。
  List<IllustStore> _visibleStores = const [];

  /// 自动补足用的状态。客户端过滤会把一部分结果筛掉，
  /// 若可见条目少到无法滚动，列表就再也不会触发"加载更多"而卡死，
  /// 所以这里主动多拉几页直到凑够一屏。
  bool _backfilling = false;
  int _backfillRounds = 0;

  /// 希望过滤后至少能看到多少条。
  static const int _filterTargetCount = 12;

  /// 每次筛选条件变化后最多额外拉取几轮，避免筛得太严时狂发请求。
  static const int _maxBackfillRounds = 4;

  @override
  void didUpdateWidget(LightingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _backfillRounds = 0;
      _store.source = widget.source;
      _fetch();
    }
  }

  _fetch() async {
    await _store.fetch(force: true);
    _backfillRounds = 0;
    if (!_isNested &&
        _store.errorMessage == null &&
        !_store.iStores.isEmpty &&
        _scrollController.hasClients) {
      _scrollController.position.jumpTo(0.0);
    }
    _recomputeVisible();
  }

  /// 按当前筛选条件算出可见列表。
  List<IllustStore> _computeVisible() {
    final filter = widget.filter;
    if (filter == null) return _store.iStores.toList(growable: false);
    return _store.iStores
        .where((e) => e.illusts != null && filter(e.illusts!))
        .toList(growable: false);
  }

  void _recomputeVisible() {
    _visibleStores = _computeVisible();
  }

  /// 过滤后条目太少时，继续拉取更多结果直到够一屏或到达上限。
  Future<void> _backfillForFilter() async {
    if (_backfilling) return;
    if (widget.filter == null) return;
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
        _recomputeVisible();
        // 没有拿到新数据就收手，避免空转。
        if (_store.iStores.length == before) break;
      }
    } finally {
      _backfilling = false;
      if (mounted) setState(() {});
    }
  }

  ReactionDisposer? disposer;

  @override
  void initState() {
    _ai = widget.ai ?? false;
    _isNested = widget.isNested ?? false;
    _scrollController = widget.scrollController ?? ScrollController();
    _refreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _store = LightingStore(
      widget.source,
    );
    _store.easyRefreshController = _refreshController;
    super.initState();
    _store.fetch();
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _store.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  bool backToTopVisible = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Observer(builder: (_) {
        return Container(child: _buildContent(context));
      }),
    );
  }

  late EasyRefreshController _refreshController;

  Widget _buildWithoutHeader(context) {
    return NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (widget.isNested == true) {
            return true;
          }
          ScrollMetrics metrics = notification.metrics;
          if (backToTopVisible == metrics.atEdge && mounted) {
            setState(() {
              backToTopVisible = !backToTopVisible;
            });
          }
          return true;
        },
        child: EasyRefresh.builder(
          controller: _refreshController,
          header: PixezDefault.header(context),
          footer: PixezDefault.footer(context),
          scrollController: _scrollController,
          onRefresh: () {
            _store.fetch(force: true);
          },
          onLoad: () {
            _store.fetchNext().then((_) {
              if (mounted) setState(() {});
            });
          },
          childBuilder: (context, physics) => WaterfallFlow.builder(
            physics: physics,
            controller: widget.isNested ?? false ? null : _scrollController,
            padding: EdgeInsets.all(5.0),
            itemCount: _visibleStores.length,
            itemBuilder: (context, index) {
              return _buildItem(index);
            },
            gridDelegate: _buildGridDelegate(),
          ),
        ));
  }

  bool needToBan(Illusts illust) {
    for (var i in muteStore.banillusts) {
      if (i.illustId == illust.id.toString()) return true;
    }
    for (var j in muteStore.banUserIds) {
      if (j.userId == illust.user.id.toString()) return true;
    }
    for (var t in muteStore.banTags) {
      for (var f in illust.tags) {
        if (f.name == t.name) return true;
      }
    }
    return false;
  }

  /// 过滤后一条都不剩但原始数据还在时，不能直接显示空白：
  /// 空白列表无法滚动，就再也不会触发"加载更多"，会彻底卡死。
  Widget _buildFilteredEmpty() {
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

  Widget _buildContent(context) {
    if (_store.errorMessage != null) return _buildErrorContent(context);
    if (_store.iStores.isEmpty) {
      return Container(
        child: _store.refreshing ? WaterFallLoading() : Container(),
      );
    }
    // 屏蔽类过滤是会话级的一次性剔除，保留原有的破坏性行为；
    // 业务筛选（widget.filter）改成渲染时计算，不动原始数据。
    _store.iStores.removeWhere(
      (element) =>
          element.illusts == null || element.illusts!.hateByUser(ai: _ai),
    );
    _visibleStores = _computeVisible();
    if (_visibleStores.isEmpty && widget.filter != null) {
      // 有数据但被筛光了：给提示与手动入口，并继续自动补足，
      // 否则空白列表无法滚动，就再也不会触发"加载更多"。
      _scheduleBackfill();
      return _buildFilteredEmpty();
    }
    _scheduleBackfill();
    return widget.header != null
        ? _buildWithHeader(context)
        : _buildWithoutHeader(context);
  }

  Widget _buildErrorContent(context) {
    final errorText = _buildErrorText(context);
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
                errorText,
              ))
        ],
      ),
    );
  }

  String _buildErrorText(BuildContext context) {
    final errorMessage = _store.errorMessage;
    final message = errorMessage?.contains("400") == true
        ? '${I18n.of(context).error_400_hint}\n $errorMessage'
        : '$errorMessage';
    return '(${Constants.tagName}) $message';
  }

  Widget _buildWithHeader(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        ScrollMetrics metrics = notification.metrics;
        if (backToTopVisible == metrics.atEdge && mounted) {
          setState(() {
            backToTopVisible = !backToTopVisible;
          });
        }
        return true;
      },
      child: EasyRefresh.builder(
        controller: _refreshController,
        scrollController: _scrollController,
        header: PixezDefault.header(context),
        footer:
            PixezDefault.footer(context, position: IndicatorPosition.locator),
        onRefresh: () {
          _store.fetch(force: true);
        },
        onLoad: () {
          _store.fetchNext();
        },
        childBuilder: ((context, physics) {
          return CustomScrollView(
            physics: physics,
            controller: widget.isNested ?? false ? null : _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Container(child: widget.header),
              ),
              SliverWaterfallFlow(
                gridDelegate: _buildGridDelegate(),
                delegate: _buildSliverChildBuilderDelegate(context),
              ),
              const FooterLocator.sliver(),
            ],
          );
        }),
      ),
    );
  }

  SliverChildBuilderDelegate _buildSliverChildBuilderDelegate(
      BuildContext context) {
    final visible = _visibleStores
        .map((e) => e)
        .toList(growable: false);
    return SliverChildBuilderDelegate((BuildContext context, int index) {
      return IllustCard(
        lightingStore: _store,
        store: visible[index],
        iStores: visible,
      );
    }, childCount: visible.length);
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

  Widget _buildItem(int index) {
    return IllustCard(
      store: _visibleStores[index],
      lightingStore: _store,
      iStores: _visibleStores,
    );
  }

  /// 延后一帧再补足，避免在 build 期间触发网络请求与 setState。
  void _scheduleBackfill() {
    if (widget.filter == null) return;
    if (_visibleStores.length >= _filterTargetCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backfillForFilter();
    });
  }
}
