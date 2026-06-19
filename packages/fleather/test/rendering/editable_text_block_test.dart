// Regression test for the release-mode crash
// "TypeError: Null check operator used on a null value" in
// RenderEditableContainerBox.childAtPosition.
//
// childAtPosition used to end with `return targetChild!`. When a TextPosition
// resolves (via node.lookup) to a document node that has no matching child
// render box — the transient node-tree / render-tree desync that the selection
// overlay's scroll-driven metric update hits right after the document changed
// (EditorTextSelectionOverlay.updateForScroll -> preferredLineHeight) — the
// debug assert is stripped in release and the `!` throws. It must clamp to the
// last child instead (consistent with childAtOffset).

import 'package:fleather/fleather.dart';
import 'package:fleather/src/rendering/editable_text_block.dart';
import 'package:fleather/src/rendering/editable_text_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rendering_tools.dart';

void main() {
  late final CursorController cursorController;

  setUpAll(() {
    cursorController = CursorController(
      showCursor: ValueNotifier(false),
      style:
          const CursorStyle(color: Colors.blue, backgroundColor: Colors.blue),
      tickerProvider: FakeTickerProvider(),
    );
    TestRenderingFlutterBinding.ensureInitialized();
  });

  RenderEditableTextLine renderLineFor(LineNode node) => RenderEditableTextLine(
        node: node,
        padding: EdgeInsets.zero,
        textDirection: TextDirection.ltr,
        cursorController: cursorController,
        selection: const TextSelection.collapsed(offset: 0),
        selectionColor: Colors.blue,
        enableInteractiveSelection: false,
        hasFocus: false,
        inlineCodeTheme: InlineCodeThemeData(style: const TextStyle()),
      );

  group('$RenderEditableTextBlock.childAtPosition', () {
    test(
        'clamps to the last child when the position has no matching child '
        '(stale selection during relayout) instead of throwing', () {
      // The block node holds the current line, but the only render child
      // present represents a different (stale) line node — as happens for a
      // frame after an edit, before relayout rebuilds the children.
      final block = BlockNode()
        ..add(LineNode()..insert(0, 'current document line', null));
      final staleChild =
          renderLineFor(LineNode()..insert(0, 'stale render child', null));
      final renderBlock = RenderEditableTextBlock(
        node: block,
        children: [staleChild],
        textDirection: TextDirection.ltr,
        padding: EdgeInsets.zero,
        decoration: const BoxDecoration(),
        textWidthBasis: TextWidthBasis.parent,
      );

      expect(
        () => renderBlock.childAtPosition(const TextPosition(offset: 0)),
        returnsNormally,
      );
      expect(
        renderBlock.childAtPosition(const TextPosition(offset: 0)),
        same(staleChild),
      );
    });
  });
}
