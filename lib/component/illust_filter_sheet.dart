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
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/illust_filter.dart';
import 'package:pixez/page/search/count_filter.dart';
import 'package:pixez/page/search/page_count_filter.dart';
import 'package:pixez/page/search/result_page.dart';

/// 标签输入框的 key。
///
/// 弹窗里还有 6 个数字输入框（内部也是 `TextField`），测试里要能单独定位到
/// 标签这一个，所以给它一个稳定的 key。
const Key tagInputKey = Key('illust_filter_tag_input');

/// 筛选弹窗：标签 + 页数 / 观看数 / 点赞数。
///
/// 数量部分和搜索页的筛选弹窗长得一样；标签是这里独有的——
/// 首页那些列表没有"搜索词"，想只看某个 tag 就只能自己填。
class IllustCountFilterSheet extends StatefulWidget {
  final IllustFilter initial;

  const IllustCountFilterSheet({Key? key, required this.initial})
    : super(key: key);

  @override
  State<IllustCountFilterSheet> createState() => _IllustCountFilterSheetState();
}

class _IllustCountFilterSheetState extends State<IllustCountFilterSheet> {
  /// 六个输入框各管一个 controller。
  ///
  /// 用 controller 而不是 `TextFormField.initialValue`：initialValue 只在
  /// 第一次创建时生效，"清空"按钮改了值输入框不会跟着变（搜索页的弹窗就有
  /// 这个毛病，只是那边没有清空按钮所以看不出来）。有了 controller，
  /// 读值也不需要 onChanged 转一手，直接 parse 就行。
  late final TextEditingController _pageMin = _numberController(
    widget.initial.pages.min,
  );
  late final TextEditingController _pageMax = _numberController(
    widget.initial.pages.max,
  );
  late final TextEditingController _viewMin = _numberController(
    widget.initial.views.min,
  );
  late final TextEditingController _viewMax = _numberController(
    widget.initial.views.max,
  );
  late final TextEditingController _bookmarkMin = _numberController(
    widget.initial.bookmarks.min,
  );
  late final TextEditingController _bookmarkMax = _numberController(
    widget.initial.bookmarks.max,
  );

  /// 标签用"输入 → 回车/加号变成 chip"的方式，而不是一行文字按空格切。
  /// pixiv 有些 tag 自带空格（"Blue Archive"、"Fate/Grand Order"），
  /// 按空格切会把它拆成两个条件。
  late final List<String> _tags = List<String>.of(widget.initial.tags);
  final TextEditingController _tagInput = TextEditingController();

  TextEditingController _numberController(int value) =>
      TextEditingController(text: value == 0 ? '' : '$value');

  Iterable<TextEditingController> get _allControllers => [
    _pageMin,
    _pageMax,
    _viewMin,
    _viewMax,
    _bookmarkMin,
    _bookmarkMax,
  ];

  @override
  void dispose() {
    for (final controller in [..._allControllers, _tagInput]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addTag(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final exists = _tags.any((tag) => tag.toLowerCase() == value.toLowerCase());
    if (!exists) {
      setState(() {
        _tags.add(value);
      });
    }
    _tagInput.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  /// 本地筛选的短板：只筛已加载的那几十上百条，翻页也补不回来多少。
  /// 所以给个台阶——把当前输入的词直接丢给搜索页（走 pixiv 搜索接口，
  /// 能一直翻），相当于"这个标签在这儿没几条，那就去全站搜"。
  void _searchCurrentTag() {
    final typed = _tagInput.text.trim();
    final word = typed.isNotEmpty
        ? typed
        : (_tags.isNotEmpty ? _tags.last : '');
    if (word.isEmpty) return;
    final navigator = Navigator.of(context);
    // 先关弹窗再跳，否则返回时会落回一个空弹窗。
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => ResultPage(word: word)));
  }

  void _clear() {
    for (final controller in _allControllers) {
      controller.clear();
    }
    _tagInput.clear();
    setState(() {
      _tags.clear();
    });
  }

  void _apply() {
    // 输入框里还有没按回车的内容也要算进去，否则用户填完直接点"应用"会丢。
    final pending = _tagInput.text.trim();
    final tags = [..._tags, if (pending.isNotEmpty) pending];
    Navigator.of(context).pop(
      IllustFilter(
        pages: PageCountRange(
          min: parseCountInput(_pageMin.text),
          max: parseCountInput(_pageMax.text),
        ),
        views: CountRange(
          min: parseCountInput(_viewMin.text),
          max: parseCountInput(_viewMax.text),
        ),
        bookmarks: CountRange(
          min: parseCountInput(_bookmarkMin.text),
          max: parseCountInput(_bookmarkMax.text),
        ),
        tags: tags,
      ).normalized(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗跟着键盘上浮，否则手填数字时输入框会被键盘挡住。
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8.0)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        I18n.of(context).filter,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clear,
                      child: Text(I18n.of(context).clear),
                    ),
                    TextButton(
                      onPressed: _apply,
                      child: Text(I18n.of(context).apply),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 标签 chip 会越加越多，包一层滚动，免得撑破弹窗。
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTagSection(context),
                      _buildRangeRow(
                        label: I18n.of(context).page_count_range,
                        minController: _pageMin,
                        maxController: _pageMax,
                      ),
                      _buildRangeRow(
                        label: I18n.of(context).view_count_range,
                        minController: _viewMin,
                        maxController: _viewMax,
                      ),
                      _buildRangeRow(
                        label: I18n.of(context).bookmark_count_range,
                        minController: _bookmarkMin,
                        maxController: _bookmarkMax,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72.0,
                child: Text(
                  I18n.of(context).tag,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: TextField(
                  key: tagInputKey,
                  controller: _tagInput,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _addTag,
                  // 例子里用专有名词，不用翻译。
                  decoration: InputDecoration(
                    hintText: '初音未来',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 10.0,
                    ),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _addTag(_tagInput.text),
                    ),
                  ),
                ),
              ),
              // 本地筛不动了就去全站搜——搜索页走的是 pixiv 搜索接口。
              IconButton(
                icon: const Icon(Icons.search, size: 20),
                tooltip: I18n.of(context).search,
                visualDensity: VisualDensity.compact,
                onPressed: _searchCurrentTag,
              ),
            ],
          ),
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 72.0, top: 6.0),
              child: Wrap(
                spacing: 6.0,
                runSpacing: 6.0,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => _removeTag(tag),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRangeRow({
    required String label,
    required TextEditingController minController,
    required TextEditingController maxController,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 72.0,
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(child: _buildNumberField(minController)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('—'),
          ),
          Expanded(child: _buildNumberField(maxController)),
        ],
      ),
    );
  }

  /// 数字输入框。空着就是不限，非数字也当作不限（见 [parseCountInput]）。
  Widget _buildNumberField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: I18n.of(context).page_count_any,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8.0,
          vertical: 10.0,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// 打开筛选弹窗。返回 null 表示用户直接关掉了。
Future<IllustFilter?> showIllustCountFilterSheet(
  BuildContext context,
  IllustFilter initial,
) {
  return showModalBottomSheet<IllustFilter>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8.0)),
    ),
    builder: (context) => IllustCountFilterSheet(initial: initial),
  );
}

/// 列表角落里的筛选按钮。
///
/// 点开弹窗、存下结果、再把新条件交给父级。父级只负责拿这个值去过滤，
/// 不用关心持久化——`scope` 决定存在哪个键下，各列表互不干扰。
class IllustFilterButton extends StatelessWidget {
  /// 见 [IllustFilterScope]。
  final String scope;

  /// 当前的筛选条件，用来回填弹窗和显示"有没有在筛"。
  final IllustFilter filter;

  final ValueChanged<IllustFilter> onChanged;

  const IllustFilterButton({
    Key? key,
    required this.scope,
    required this.filter,
    required this.onChanged,
  }) : super(key: key);

  Future<void> _open(BuildContext context) async {
    final result = await showIllustCountFilterSheet(context, filter);
    if (result == null) return;
    await saveIllustFilter(scope, result);
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final active = !filter.isAny;
    final color = active ? Theme.of(context).colorScheme.primary : null;
    return IconButton(
      tooltip: I18n.of(context).filter,
      visualDensity: VisualDensity.compact,
      onPressed: () => _open(context),
      icon: Badge.count(
        count: filter.activeCount,
        isLabelVisible: active,
        backgroundColor: color,
        textColor: active ? Theme.of(context).colorScheme.onPrimary : null,
        child: Icon(Icons.filter_alt_outlined, color: color),
      ),
    );
  }
}
