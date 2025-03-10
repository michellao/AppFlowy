import 'package:appflowy/mobile/presentation/inline_actions/mobile_inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/handlers/child_page.dart';
import 'package:appflowy/plugins/inline_actions/handlers/inline_page_reference.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_result.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_service.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

const _bracketChar = '[';
const _plusChar = '+';

CharacterShortcutEvent pageReferenceShortcutBrackets(
  BuildContext context,
  String viewId,
  InlineActionsMenuStyle style,
) =>
    CharacterShortcutEvent(
      key: 'show the inline page reference menu by [',
      character: _bracketChar,
      handler: (editorState) => inlinePageReferenceCommandHandler(
        _bracketChar,
        context,
        viewId,
        editorState,
        style,
        previousChar: _bracketChar,
      ),
    );

CharacterShortcutEvent pageReferenceShortcutPlusSign(
  BuildContext context,
  String viewId,
  InlineActionsMenuStyle style,
) =>
    CharacterShortcutEvent(
      key: 'show the inline page reference menu by +',
      character: _plusChar,
      handler: (editorState) => inlinePageReferenceCommandHandler(
        _plusChar,
        context,
        viewId,
        editorState,
        style,
      ),
    );

InlineActionsMenuService? selectionMenuService;

Future<bool> inlinePageReferenceCommandHandler(
  String character,
  BuildContext context,
  String currentViewId,
  EditorState editorState,
  InlineActionsMenuStyle style, {
  String? previousChar,
}) async {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }

  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }

  // Check for previous character
  if (previousChar != null) {
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null || delta.isEmpty) {
      return false;
    }

    if (selection.end.offset > 0) {
      final plain = delta.toPlainText();

      final previousCharacter = plain[selection.end.offset - 1];
      if (previousCharacter != _bracketChar) {
        return false;
      }
    }
  }

  if (!context.mounted) {
    return false;
  }

  final service = InlineActionsService(
    context: context,
    handlers: [
      if (FeatureFlag.inlineSubPageMention.isOn)
        InlineChildPageService(currentViewId: currentViewId),
      InlinePageReferenceService(
        currentViewId: currentViewId,
        limitResults: 10,
      ),
    ],
  );

  await editorState.insertTextAtPosition(character, position: selection.start);

  final List<InlineActionsResult> initialResults = [];
  for (final handler in service.handlers) {
    final group = await handler.search(null);

    if (group.results.isNotEmpty) {
      initialResults.add(group);
    }
  }

  if (context.mounted) {
    keepEditorFocusNotifier.increase();
    selectionMenuService?.dismiss();
    selectionMenuService = UniversalPlatform.isMobile
        ? MobileInlineActionsMenu(
            context: service.context!,
            editorState: editorState,
            service: service,
            initialResults: initialResults,
            startCharAmount: previousChar != null ? 2 : 1,
            style: style,
          )
        : InlineActionsMenu(
            context: service.context!,
            editorState: editorState,
            service: service,
            initialResults: initialResults,
            style: style,
            startCharAmount: previousChar != null ? 2 : 1,
            cancelBySpaceHandler: () {
              if (character == _plusChar) {
                final currentSelection = editorState.selection;
                if (currentSelection == null) {
                  return false;
                }
                // check if the space is after the character
                if (currentSelection.isCollapsed &&
                    currentSelection.start.offset ==
                        selection.start.offset + character.length) {
                  _cancelInlinePageReferenceMenu(editorState);
                  return true;
                }
              }
              return false;
            },
          );
    // disable the keyboard service
    editorState.service.keyboardService?.disable();

    await selectionMenuService?.show();

    // enable the keyboard service
    editorState.service.keyboardService?.enable();
  }

  return true;
}

void _cancelInlinePageReferenceMenu(EditorState editorState) {
  selectionMenuService?.dismiss();
  selectionMenuService = null;

  // re-focus the selection
  final selection = editorState.selection;
  if (selection != null) {
    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
    );
  }
}
