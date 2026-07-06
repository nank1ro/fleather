import 'package:fleather/fleather.dart';
import 'package:fleather/src/widgets/editor_input_client_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing.dart';

void main() {
  group('onFocusReceived', () {
    testWidgets('requests focus when the editor can receive focus',
        (tester) async {
      final editor = EditorSandBox(tester: tester);
      await editor.pump();

      final inputClient = getInputClient();
      expect(editor.focusNode.hasFocus, isFalse);

      expect(inputClient.onFocusReceived(), isTrue);
      await tester.pump();

      expect(editor.focusNode.hasFocus, isTrue);
    });

    testWidgets('returns false when the editor already has focus',
        (tester) async {
      final editor = EditorSandBox(tester: tester);
      await editor.pumpAndTap();

      final inputClient = getInputClient();

      expect(inputClient.onFocusReceived(), isFalse);
      expect(editor.focusNode.hasFocus, isTrue);
    });

    testWidgets('returns false when focus cannot be requested', (tester) async {
      final focusNode = FocusNode(canRequestFocus: false);
      final editor = EditorSandBox(tester: tester, focusNode: focusNode);
      await editor.pump();

      final inputClient = getInputClient();

      expect(inputClient.onFocusReceived(), isFalse);
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
    });
  });

  group('send text editing state to TextInputConnection', () {
    final composingRanges = <TextRange>[];

    void bind(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput, (MethodCall methodCall) async {
        if (methodCall.method == 'TextInput.setEditingState') {
          final Map<String, dynamic> args =
              methodCall.arguments as Map<String, dynamic>;
          composingRanges.add(TextRange(
              start: args['composingBase'], end: args['composingExtent']));
        }
        return null;
      });
    }

    setUp(() => composingRanges.clear());

    testWidgets(
        'sends empty composing range if composing range becomes invalid',
        (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'some text\n'}
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();
      tester.binding.scheduleWarmUpFrame();
      final editorState =
          tester.state(find.byType(RawEditor)) as RawEditorState;
      editorState.updateEditingValueWithDeltas([
        TextEditingDeltaNonTextUpdate(
          oldText: editorState.textEditingValue.text,
          selection: const TextSelection.collapsed(offset: 9),
          composing: const TextRange(start: 5, end: 9),
        )
      ]);
      await tester.pumpAndSettle();
      editor.controller.replaceText(4, 5, '',
          selection: const TextSelection.collapsed(offset: 4));
      await tester.pumpAndSettle(throttleDuration);
      expect(
          composingRanges.fold(
              true, (v, e) => v && (e == TextRange.empty || e.isValid)),
          isTrue);
    });
  });

  group('sets style to TextInputConnection', () {
    final log = <TextInputConnectionStyle>[];

    void bind(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput, (MethodCall methodCall) async {
        if (methodCall.method == 'TextInput.setStyle') {
          final Map<String, dynamic> args =
              methodCall.arguments as Map<String, dynamic>;
          final fontFamily = args['fontFamily'];
          final fontSize = args['fontSize'];
          final fontWeightIndex = args['fontWeightIndex'];
          final textAlignIndex = args['textAlignIndex'];
          final textDirectionIndex = args['textDirectionIndex'];
          final TextInputConnectionStyle style = TextInputConnectionStyle(
              textStyle: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: fontWeightIndex != null
                      ? FontWeight.values[fontWeightIndex]
                      : null),
              textAlign: textAlignIndex != null
                  ? TextAlign.values[textAlignIndex]
                  : TextAlign.left,
              textDirection: textDirectionIndex != null
                  ? TextDirection.values[textDirectionIndex]
                  : TextDirection.ltr);
          log.add(style);
        }
        return null;
      });
    }

    setUp(() => log.clear());

    testWidgets('sets style on position 0 by default', (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'some text\n'}
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();
      tester.binding.scheduleWarmUpFrame();
      expect(log.length, 1);
      expect(
          log.first,
          const TextInputConnectionStyle(
              textStyle: TextStyle(
                  inherit: true,
                  fontFamily: 'Roboto',
                  fontSize: 16.0,
                  fontWeight: FontWeight.w400),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left));
    });

    testWidgets('changing selection updates text input connection style',
        (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'Heading 1'},
        {
          'insert': '\n',
          'attributes': {'heading': 1}
        },
        {'insert': 'Normal paragraph\n'},
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      final context = tester.element(find.byType(RawEditor));
      final themeData = FleatherThemeData.fallback(context);
      await tester.tapAt(tester.getTopLeft(find.byType(FleatherEditor)) +
          Offset(20, themeData.heading1.spacing.top));
      tester.binding.scheduleWarmUpFrame();
      expect(log.length, 1);
      expect(
          log.first,
          TextInputConnectionStyle(
              textStyle: TextStyle(
                  inherit: true,
                  fontFamily: 'Roboto',
                  fontSize: themeData.heading1.style.fontSize,
                  fontWeight: themeData.heading1.style.fontWeight),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left));
      log.clear();
      final paragraphOffset = Offset(
          20,
          themeData.heading1.spacing.top +
              (themeData.heading1.style.fontSize ?? 0) +
              themeData.paragraph.spacing.top +
              10);
      await tester.tapAt(
          tester.getTopLeft(find.byType(FleatherEditor)) + paragraphOffset);
      tester.binding.scheduleWarmUpFrame();
      expect(log.length, 1);
      expect(
          log.first,
          TextInputConnectionStyle(
              textStyle: TextStyle(
                  inherit: true,
                  fontFamily: 'Roboto',
                  fontSize: themeData.paragraph.style.fontSize,
                  fontWeight: themeData.paragraph.style.fontWeight),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left));
    });

    testWidgets('sets style to TextInputConnection for all line/block styles',
        (tester) async {
      bind(tester);
      final coveredAttributes = [
        ParchmentAttribute.h2,
        ParchmentAttribute.h3,
        ParchmentAttribute.h4,
        ParchmentAttribute.h5,
        ParchmentAttribute.h6,
        ParchmentAttribute.code,
      ];
      TextBlockTheme themeFromAttribute(
          ParchmentAttribute attribute, FleatherThemeData themeData) {
        final styles = {
          ParchmentAttribute.h2: themeData.heading2,
          ParchmentAttribute.h3: themeData.heading3,
          ParchmentAttribute.h4: themeData.heading4,
          ParchmentAttribute.h5: themeData.heading5,
          ParchmentAttribute.h6: themeData.heading6,
          ParchmentAttribute.code: themeData.code
        };
        return styles[attribute]!;
      }

      for (final attribute in coveredAttributes) {
        final document = ParchmentDocument.fromJson([
          {'insert': 'text that will be tapped'},
          {
            'insert': '\n',
            'attributes': {attribute.key: attribute.value}
          },
        ]);
        final editor = EditorSandBox(tester: tester, document: document);
        await editor.pump();
        await editor.tap();
        final context = tester.element(find.byType(RawEditor));
        final themeData = FleatherThemeData.fallback(context);
        final themeDataItem = themeFromAttribute(attribute, themeData);
        tester.binding.scheduleWarmUpFrame();
        expect(log.length, 1);
        expect(
            log.first,
            TextInputConnectionStyle(
                textStyle: TextStyle(
                    inherit: true,
                    fontFamily: attribute == ParchmentAttribute.code
                        ? 'Roboto Mono'
                        : null,
                    fontSize: themeDataItem.style.fontSize,
                    fontWeight: themeDataItem.style.fontWeight),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left));
        log.clear();
      }
    });

    testWidgets('sets style to TextInputConnection for RTL direction',
        (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'text that will be tapped'},
        {
          'insert': '\n',
          'attributes': {
            ParchmentAttribute.rtl.key: ParchmentAttribute.rtl.value
          }
        },
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();
      final context = tester.element(find.byType(RawEditor));
      final themeData = FleatherThemeData.fallback(context);
      tester.binding.scheduleWarmUpFrame();
      expect(log.length, 1);
      expect(
          log.first,
          TextInputConnectionStyle(
              textStyle: TextStyle(
                  inherit: true,
                  fontFamily: 'Roboto',
                  fontSize: themeData.paragraph.style.fontSize,
                  fontWeight: themeData.paragraph.style.fontWeight),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.left));
    });

    testWidgets('sets style to TextInputConnection for all TextAlign',
        (tester) async {
      bind(tester);
      final coveredAlignments = {
        ParchmentAttribute.left: TextAlign.left,
        ParchmentAttribute.justify: TextAlign.justify,
        ParchmentAttribute.center: TextAlign.center,
        ParchmentAttribute.right: TextAlign.right
      };

      for (final alignmentMapping in coveredAlignments.entries) {
        final attribute = alignmentMapping.key;
        final alignment = alignmentMapping.value;
        final document = ParchmentDocument.fromJson([
          {'insert': 'text that will be tapped'},
          {
            'insert': '\n',
            'attributes': {attribute.key: attribute.value}
          },
        ]);
        final editor = EditorSandBox(tester: tester, document: document);
        await editor.pump();
        if (alignment == TextAlign.right) {
          await tester.tapAt(tester.getTopRight(find.byType(RawEditor)) +
              const Offset(-20, 10));
        } else {
          await editor.tap();
        }
        final context = tester.element(find.byType(RawEditor));
        final themeData = FleatherThemeData.fallback(context);
        tester.binding.scheduleWarmUpFrame();
        expect(log.length, 1);
        expect(
            log.first,
            TextInputConnectionStyle(
                textStyle: TextStyle(
                    inherit: true,
                    fontFamily: 'Roboto',
                    fontSize: themeData.paragraph.style.fontSize,
                    fontWeight: themeData.paragraph.style.fontWeight),
                textDirection: TextDirection.ltr,
                textAlign: alignment));
        log.clear();
      }
    });
  });

  testWidgets('send editor options to TextInputConnection', (tester) async {
    Map<String, dynamic>? textInputSetClientProperties;
    Map<String, dynamic>? textInputUpdateConfigProperties;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput, (MethodCall methodCall) async {
      if (methodCall.method == 'TextInput.setClient') {
        textInputSetClientProperties = methodCall.arguments[1];
      } else if (methodCall.method == 'TextInput.updateConfig') {
        textInputUpdateConfigProperties = methodCall.arguments;
      }
      return null;
    });

    final controller = FleatherController();
    Future<void> pumpEditor(bool enable) async {
      final editor = MaterialApp(
          home: FleatherField(
        controller: controller,
        enableSuggestions: enable,
        autocorrect: enable,
      ));
      await tester.pumpWidget(editor);
      await tester.tapAt(tester.getCenter(find.byType(RawEditor)));
      tester.binding.scheduleWarmUpFrame();
      await tester.pumpAndSettle();
    }

    await pumpEditor(true);
    expect(textInputSetClientProperties?['autocorrect'], true);
    expect(textInputSetClientProperties?['enableSuggestions'], true);
    expect(textInputUpdateConfigProperties, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await pumpEditor(false);
    expect(textInputSetClientProperties?['autocorrect'], false);
    expect(textInputSetClientProperties?['enableSuggestions'], false);
    expect(textInputUpdateConfigProperties, isNull);

    textInputSetClientProperties = null;
    await pumpEditor(true);
    expect(textInputUpdateConfigProperties?['autocorrect'], true);
    expect(textInputUpdateConfigProperties?['enableSuggestions'], true);
    expect(textInputSetClientProperties, isNull);
  });

  group('guards against stale deltas (Sentry 132143638)', () {
    // Reproduces the crash: a native TextEditingDelta is computed by the
    // platform against a document snapshot, but before it arrives here
    // something else (e.g. the app calling `FleatherController.replaceText`
    // directly, as textcalc's autocomplete-accept does) mutates the document
    // out from under it. Applying the delta's stale start/length verbatim
    // used to let `ParchmentDocument.replace` call `insert` past the end of
    // the live document, throwing a null-check error in
    // `ContainerNode.insert`.
    final capturedEditingStates = <Map<String, dynamic>>[];

    void bind(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput, (MethodCall methodCall) async {
        if (methodCall.method == 'TextInput.setEditingState') {
          capturedEditingStates
              .add(methodCall.arguments as Map<String, dynamic>);
        }
        return null;
      });
    }

    setUp(() => capturedEditingStates.clear());

    testWidgets(
        'drops an entirely out-of-range delta without crashing and resyncs '
        'the remote value', (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'Hello world\n'} // length 12
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();

      // Mimic the app mutating the document directly (bypassing the
      // TextInput channel), e.g. an autocomplete accept: replace "world"
      // (start 6, length 5) with "hi" -> "Hello hi\n" (length 9).
      editor.controller.replaceText(6, 5, 'hi',
          selection: const TextSelection.collapsed(offset: 8));
      await tester.pumpAndSettle(throttleDuration);
      capturedEditingStates.clear();

      final editorState =
          tester.state(find.byType(RawEditor)) as RawEditorState;

      // A native delta computed against the OLD 12-length document: e.g.
      // autocorrect replacing "ld" (start 9, end 11) with "LD". The live
      // document is now only 9 characters long, so `start` (9) is already
      // at/beyond the current document length -> entirely out of bounds.
      const staleDelta = TextEditingDeltaReplacement(
        oldText: 'Hello world\n',
        replacedRange: TextRange(start: 9, end: 11),
        replacementText: 'LD',
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange.empty,
      );

      // Must not throw (previously crashed with the null-check error from
      // ContainerNode.insert).
      expect(() => editorState.updateEditingValueWithDeltas([staleDelta]),
          returnsNormally);
      await tester.pumpAndSettle(throttleDuration);

      // The document is untouched by the dropped delta - still exactly
      // what the app's direct mutation produced.
      expect(editor.controller.document.toPlainText(), 'Hello hi\n');

      // The editor resynced the engine with the live state instead of
      // silently trusting the stale native value.
      expect(capturedEditingStates, isNotEmpty);
      expect(capturedEditingStates.last['text'], 'Hello hi\n');
    });

    testWidgets(
        'clamps a delta whose range extends past the current document',
        (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'Hello world foo\n'} // length 16
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();

      // Direct app mutation shrinks the tail: remove " foo" (start 11,
      // length 4) -> "Hello world\n" (length 12).
      editor.controller.replaceText(11, 4, '',
          selection: const TextSelection.collapsed(offset: 11));
      await tester.pumpAndSettle(throttleDuration);
      capturedEditingStates.clear();

      final editorState =
          tester.state(find.byType(RawEditor)) as RawEditorState;

      // A native deletion computed against the OLD 16-length document:
      // deleting "world foo" (start 6, end 15, length 9). The live
      // document is now only 12 characters long, so `start` (6) is still
      // valid but `start + length` (15) overruns it -> clamp to what's
      // actually still there (length 6, i.e. delete through position 12).
      const staleDelta = TextEditingDeltaDeletion(
        oldText: 'Hello world foo\n',
        deletedRange: TextRange(start: 6, end: 15),
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      );

      expect(() => editorState.updateEditingValueWithDeltas([staleDelta]),
          returnsNormally);
      await tester.pumpAndSettle(throttleDuration);

      // Parchment itself preserves the document's trailing newline
      // invariant, so the clamped delete(6, 6) only removes "world" and
      // leaves a valid, non-corrupt document.
      expect(editor.controller.document.toPlainText(), 'Hello \n');
      expect(editor.controller.selection.extentOffset,
          lessThanOrEqualTo(editor.controller.document.length));
    });

    testWidgets('an in-bounds delta still applies exactly as before',
        (tester) async {
      bind(tester);
      final document = ParchmentDocument.fromJson([
        {'insert': 'Hello world\n'} // length 12
      ]);
      final editor = EditorSandBox(tester: tester, document: document);
      await editor.pump();
      await editor.tap();

      final editorState =
          tester.state(find.byType(RawEditor)) as RawEditorState;

      // In-sync delta: replace "world" (start 6, end 11) with "there".
      const delta = TextEditingDeltaReplacement(
        oldText: 'Hello world\n',
        replacedRange: TextRange(start: 6, end: 11),
        replacementText: 'there',
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange.empty,
      );
      editorState.updateEditingValueWithDeltas([delta]);
      await tester.pumpAndSettle(throttleDuration);

      expect(editor.controller.document.toPlainText(), 'Hello there\n');
    });
  });
}
