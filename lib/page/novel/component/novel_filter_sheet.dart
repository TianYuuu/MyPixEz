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

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/tags.dart' as suggest;
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/novel_filter.dart';
import 'package:pixez/page/novel/search/novel_result_page.dart';
import 'package:pixez/page/search/count_filter.dart';

/// 标签输入框的 key。弹窗里还有 6 个数字输入框，测试里要单独定位标签这一格。
const Key novelTagInputKey = Key('novel_filter_tag_input');

/// 小说筛选弹窗：标签 + 阅读数 / 收藏数 / 字数。
///
/// 和插画筛选弹窗（`IllustCountFilterSheet`）是同一套交互，只把数量维度
/// 从"页数 / 观看数 / 点赞数"换成"阅读数 / 收藏数 / 字数"。
class NovelCountFilterSheet extends StatefulWidget {
  final NovelFilter initial;

  /// 补全数据来源。默认走 `apiClient`（和搜索页同一个接口），
  /// 测试里可以塞假的，免得 mock 网络。
  final Future<List<suggest.Tags>> Function(String word)? suggestionLoader;

  const NovelCountFilterSheet({
    Key? key,
    required this.initial,
    this.suggestionLoader,
  }) : super(key: key);

  @override
  State<NovelCountFilterSheet> createState() => _NovelCountFilterSheetState();
}

class _NovelCountFilterSheetState extends State<NovelCountFilterSheet> {
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
  late final TextEditingController _lengthMin = _numberController(
    widget.initial.textLength.min,
  );
  late final TextEditingController _lengthMax = _numberController(
    widget.initial.textLength.max,
  );

  late final List<String> _tags = List<String>.of(widget.initial.tags);
  final TextEditingController _tagInput = TextEditingController();

  Timer? _suggestDebounce;
  List<suggest.Tags> _suggestions = const [];

  static const Duration _suggestDelay = Duration(milliseconds: 350);
  static const int _maxSuggestions = 8;

  TextEditingController _numberController(int value) =>
      TextEditingController(text: value == 0 ? '' : '$value');

  Iterable<TextEditingController> get _allControllers => [
    _viewMin,
    _viewMax,
    _bookmarkMin,
    _bookmarkMax,
    _lengthMin,
    _lengthMax,
  ];

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    for (final controller in [..._allControllers, _tagInput]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTagChanged(String raw) {
    _suggestDebounce?.cancel();
    final word = raw.trim();
    if (word.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
      return;
    }
    _suggestDebounce = Timer(_suggestDelay, () => _fetchSuggestions(word));
  }

  Future<void> _fetchSuggestions(String word) async {
    try {
      final loader = widget.suggestionLoader ?? _defaultSuggestionLoader;
      final tags = await loader(word);
      if (!mounted || _tagInput.text.trim() != word) return;
      setState(() {
        _suggestions = tags.take(_maxSuggestions).toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = const []);
    }
  }

  static Future<List<suggest.Tags>> _defaultSuggestionLoader(
    String word,
  ) async {
    final autoWords = await apiClient.getSearchAutoCompleteKeywords(word);
    return autoWords.tags;
  }

  void _pickSuggestion(suggest.Tags tag) {
    _suggestDebounce?.cancel();
    setState(() => _suggestions = const []);
    _addTag(tag.name);
  }

  void _addTag(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    _suggestDebounce?.cancel();
    final exists = _tags.any((tag) => tag.toLowerCase() == value.toLowerCase());
    setState(() {
      if (!exists) _tags.add(value);
      _suggestions = const [];
    });
    _tagInput.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  /// 本地筛不动了就去全站搜（走 pixiv 小说搜索接口）。
  void _searchCurrentTag() {
    final typed = _tagInput.text.trim();
    final word = typed.isNotEmpty
        ? typed
        : (_tags.isNotEmpty ? _tags.last : '');
    if (word.isEmpty) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => NovelResultPage(word: word)),
    );
  }

  void _clear() {
    _suggestDebounce?.cancel();
    for (final controller in _allControllers) {
      controller.clear();
    }
    _tagInput.clear();
    setState(() {
      _tags.clear();
      _suggestions = const [];
    });
  }

  void _apply() {
    _suggestDebounce?.cancel();
    // 输入框里还有没按回车的内容也要算进去。
    final pending = _tagInput.text.trim();
    final tags = [..._tags, if (pending.isNotEmpty) pending];
    Navigator.of(context).pop(
      NovelFilter(
        views: CountRange(
          min: parseCountInput(_viewMin.text),
          max: parseCountInput(_viewMax.text),
        ),
        bookmarks: CountRange(
          min: parseCountInput(_bookmarkMin.text),
          max: parseCountInput(_bookmarkMax.text),
        ),
        textLength: CountRange(
          min: parseCountInput(_lengthMin.text),
          max: parseCountInput(_lengthMax.text),
        ),
        tags: tags,
      ).normalized(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTagSection(context),
                      _buildRangeRow(
                        label: I18n.of(context).novel_view_count_range,
                        minController: _viewMin,
                        maxController: _viewMax,
                      ),
                      _buildRangeRow(
                        label: I18n.of(context).novel_bookmark_count_range,
                        minController: _bookmarkMin,
                        maxController: _bookmarkMax,
                      ),
                      _buildRangeRow(
                        label: I18n.of(context).text_length_range,
                        minController: _lengthMin,
                        maxController: _lengthMax,
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
                  key: novelTagInputKey,
                  controller: _tagInput,
                  textInputAction: TextInputAction.done,
                  onChanged: _onTagChanged,
                  onSubmitted: _addTag,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 10.0,
                    ),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _addTag(_tagInput.text),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.travel_explore, size: 20),
                tooltip: I18n.of(context).search,
                visualDensity: VisualDensity.compact,
                onPressed: _searchCurrentTag,
              ),
            ],
          ),
          if (_suggestions.isNotEmpty) _buildSuggestions(context),
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

  Widget _buildSuggestions(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 72.0, top: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tag in _suggestions)
            InkWell(
              onTap: () => _pickSuggestion(tag),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((tag.translated_name ?? '').isNotEmpty)
                      Flexible(
                        flex: 2,
                        child: Text(
                          tag.translated_name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
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

/// 打开小说筛选弹窗。返回 null 表示用户直接关掉了。
Future<NovelFilter?> showNovelCountFilterSheet(
  BuildContext context,
  NovelFilter initial, {
  Future<List<suggest.Tags>> Function(String word)? suggestionLoader,
}) {
  return showModalBottomSheet<NovelFilter>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8.0)),
    ),
    builder: (context) => NovelCountFilterSheet(
      initial: initial,
      suggestionLoader: suggestionLoader,
    ),
  );
}

/// 小说列表角落里的筛选按钮。
class NovelFilterButton extends StatelessWidget {
  /// 见 [NovelFilterScope]。
  final String scope;

  /// 当前的筛选条件，用来回填弹窗和显示"有没有在筛"。
  final NovelFilter filter;

  final ValueChanged<NovelFilter> onChanged;

  const NovelFilterButton({
    Key? key,
    required this.scope,
    required this.filter,
    required this.onChanged,
  }) : super(key: key);

  Future<void> _open(BuildContext context) async {
    final result = await showNovelCountFilterSheet(context, filter);
    if (result == null) return;
    await saveNovelFilter(scope, result);
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
