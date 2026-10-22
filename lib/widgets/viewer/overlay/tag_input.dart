import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/viewer/action/entry_info_action_delegate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

// inline tag input over the viewed entry, with ghost autocompletion from existing tags
class ViewerTagInputOverlay extends StatefulWidget {
  final AvesEntry entry;
  final VoidCallback onDismissed;

  const new({
    super.key,
    required this.entry,
    required this.onDismissed,
  });

  @override
  State<ViewerTagInputOverlay> createState() => _ViewerTagInputOverlayState();
}

class _ViewerTagInputOverlayState extends State<ViewerTagInputOverlay> {
  final _GhostTextEditingController _textController = .new();
  final FocusNode _focusNode = FocusNode();
  final EntryInfoActionDelegate _actionDelegate = .new();
  late final List<String> _candidates;
  String? _suggestion;

  static const double dimOpacity = .4;
  static const EdgeInsets fieldContentPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  @override
  void initState() {
    super.initState();
    _candidates = _rankCandidates();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge!;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom ? mediaQuery.viewInsets.bottom : mediaQuery.viewPadding.bottom;

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: kThemeAnimationDuration,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDismissed,
                child: const ColoredBox(color: Color.fromRGBO(0, 0, 0, dimOpacity)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Themes.secondLayerColor(context),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: mediaQuery.viewPadding.left + 8,
                    right: mediaQuery.viewPadding.right + 8,
                    top: 8,
                    bottom: bottomInset + 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                TextField(
                                  controller: _textController,
                                  focusNode: _focusNode,
                                  style: textStyle,
                                  autofocus: true,
                                  autocorrect: false,
                                  textInputAction: .done,
                                  decoration: InputDecoration(
                                    hintText: l10n.tagEditorPageNewTagFieldLabel,
                                    contentPadding: fieldContentPadding,
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addTag(_textController.text),
                                ),
                                ..._buildGhostTapTarget(context, textStyle, constraints.maxWidth),
                              ],
                            );
                          },
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _textController,
                        builder: (context, value, child) {
                          return IconButton(
                            icon: const Icon(AIcons.add),
                            onPressed: value.text.trim().isEmpty ? null : () => _addTag(value.text),
                            tooltip: l10n.tagEditorPageAddTagTooltip,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // transparent target over the ghost text, so that tapping the ghost accepts the suggestion
  List<Widget> _buildGhostTapTarget(BuildContext context, TextStyle textStyle, double fieldWidth) {
    final suggestion = _suggestion;
    final ghost = _textController.ghost;
    if (suggestion == null || ghost == null) return [];

    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final typedWidth = measure(_textController.text);
    final ghostWidth = measure(ghost);
    final availableWidth = fieldWidth - fieldContentPadding.horizontal;
    // when text overflows, the field scrolls and the ghost position is unreliable
    if (typedWidth + ghostWidth > availableWidth) return [];

    return [
      PositionedDirectional(
        start: fieldContentPadding.left + typedWidth,
        top: 0,
        bottom: 0,
        width: availableWidth - typedWidth,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _addTag(suggestion),
        ),
      ),
    ];
  }

  // recent tags first, then most used tags in the collection
  List<String> _rankCandidates() {
    final recentTags = settings.recentTags.whereType<TagFilter>().map((v) => v.tag).where((v) => v.isNotEmpty);

    final Map<String, int> entryCountByTag = {};
    context.read<CollectionSource?>()?.visibleEntries.forEach((entry) {
      entry.tags.forEach((tag) => entryCountByTag[tag] = (entryCountByTag[tag] ?? 0) + 1);
    });
    final usedTags = entryCountByTag.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    return {...recentTags, ...usedTags.map((kv) => kv.key)}.toList();
  }

  void _onTextChanged() {
    final query = _textController.text.trimLeft();
    String? suggestion;
    if (query.isNotEmpty) {
      final upQuery = query.toUpperCase();
      final currentTags = widget.entry.tags;
      suggestion = _candidates.firstWhere(
        (v) => v.length > query.length && v.toUpperCase().startsWith(upQuery) && !currentTags.contains(v),
        orElse: () => '',
      );
      if (suggestion.isEmpty) suggestion = null;
    }
    _textController.ghost = suggestion?.substring(query.length);
    // rebuild even when the suggestion is unchanged, as the ghost tap target follows the typed text width
    setState(() => _suggestion = suggestion);
  }

  Future<void> _addTag(String tag) async {
    tag = tag.trim();
    if (tag.isEmpty) return;

    final filter = TagFilter(tag);
    settings.recentTags = settings.recentTags
      ..remove(filter)
      ..insert(0, filter);
    _textController.clear();
    _focusNode.requestFocus();

    await _actionDelegate.quickTag(context, widget.entry, filter);
  }
}

class _GhostTextEditingController extends TextEditingController {
  String? _ghost;

  String? get ghost => _ghost;

  set ghost(String? value) {
    if (_ghost == value) return;
    _ghost = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final span = super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final ghost = _ghost;
    if (ghost == null || ghost.isEmpty) return span;

    final ghostColor = (style?.color ?? Theme.of(context).colorScheme.onSurface).withValues(alpha: .4);
    return TextSpan(
      style: style,
      children: [
        span,
        TextSpan(
          text: ghost,
          style: style?.copyWith(color: ghostColor) ?? TextStyle(color: ghostColor),
        ),
      ],
    );
  }
}
