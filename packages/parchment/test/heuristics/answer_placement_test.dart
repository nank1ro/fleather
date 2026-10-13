import 'dart:convert';

import 'package:parchment/parchment.dart';
import 'package:test/test.dart';

const _key = 'nc-answer';
final _ul = ParchmentAttribute.ul.toJson();

Map<String, dynamic> _answer(String value, [Map<String, dynamic>? other]) =>
    {...?other, _key: value};

/// Describes every line of [doc] as its text, followed by ` [value]` when the
/// line carries an answer override. Block embeds show as `<hr>`.
List<String> _lines(Delta doc) {
  final result = <String>[];
  var text = StringBuffer();
  for (final op in doc.toList()) {
    final data = op.data;
    if (data is! String) {
      text.write('<hr>');
      continue;
    }
    final parts = data.split('\n');
    for (var i = 0; i < parts.length; i++) {
      text.write(parts[i]);
      if (i == parts.length - 1) break;
      final answer = op.attributes?[_key];
      result.add(answer == null ? '$text' : '$text [$answer]');
      text = StringBuffer();
    }
  }
  return result;
}

List<String> _docLines(ParchmentDocument doc) => _lines(doc.toDelta());

ParchmentDocument _doc(Delta delta) => ParchmentDocument.fromDelta(delta);

/// `Intro`, `Total` (override A, optional extra line style), `Tail`.
ParchmentDocument _totalDoc([Map<String, dynamic>? lineStyle]) => _doc(Delta()
  ..insert('Intro\nTotal')
  ..insert('\n', _answer('A', lineStyle))
  ..insert('Tail\n'));

void main() {
  test('nc-answer round-trips through ParchmentDocument json', () {
    final json = [
      {'insert': 'Total'},
      {
        'insert': '\n',
        'attributes': {_key: '{"text":"Sum"}'}
      },
    ];
    final doc = ParchmentDocument.fromJson(json);
    expect(doc.toDelta(), Delta.fromJson(json));
    expect(jsonDecode(jsonEncode(doc)), json);
    expect(
        (doc.root.children.single as LineNode)
            .style
            .get(ParchmentAttribute.answer)
            ?.value,
        '{"text":"Sum"}');
  });

  group('Enter on an annotated ordinary line', () {
    test('at the start', () {
      final doc = _totalDoc()..insert(6, '\n');
      expect(_docLines(doc), ['Intro', '', 'Total [A]', 'Tail']);
    });

    test('in the middle', () {
      final doc = _totalDoc()..insert(9, '\n');
      expect(_docLines(doc), ['Intro', 'Tot', 'al [A]', 'Tail']);
    });

    test('at the end', () {
      final doc = _totalDoc()..insert(11, '\n');
      expect(_docLines(doc), ['Intro', 'Total [A]', '', 'Tail']);
    });

    test('on an empty line', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert('\n', _answer('A'))
        ..insert('Tail\n'))
        ..insert(6, '\n');
      expect(_docLines(doc), ['Intro', ' [A]', '', 'Tail']);
    });

    test('on two identical empty lines stored as one op', () {
      Delta twoEmpty() => Delta()
        ..insert('Intro\n')
        ..insert('\n\n', _answer('A'))
        ..insert('Tail\n');
      expect(_docLines(_doc(twoEmpty())..insert(6, '\n')),
          ['Intro', ' [A]', '', ' [A]', 'Tail']);
      expect(_docLines(_doc(twoEmpty())..insert(7, '\n')),
          ['Intro', ' [A]', ' [A]', '', 'Tail']);
    });
  });

  group('Enter on an annotated list line', () {
    test('at the start', () {
      final doc = _totalDoc(_ul)..insert(6, '\n');
      expect(_docLines(doc), ['Intro', '', 'Total [A]', 'Tail']);
    });

    test('in the middle', () {
      final doc = _totalDoc(_ul)..insert(9, '\n');
      expect(_docLines(doc), ['Intro', 'Tot', 'al [A]', 'Tail']);
      expect(doc.toDelta().toList()[1].attributes, _ul);
    });

    test('at the end', () {
      final doc = _totalDoc(_ul)..insert(11, '\n');
      expect(_docLines(doc), ['Intro', 'Total [A]', '', 'Tail']);
      expect(doc.toDelta().toList()[2].attributes, _ul);
    });

    test('on an empty line inside the list', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert('\n', _answer('A', _ul))
        ..insert('x')
        ..insert('\n', _ul)
        ..insert('Tail\n'))
        ..insert(6, '\n');
      expect(_docLines(doc), ['Intro', ' [A]', '', 'x', 'Tail']);
    });

    test('on the last empty line, directly above another annotated line', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert('\n', _answer('A', _ul))
        ..insert('Total')
        ..insert('\n', _answer('B'))
        ..insert('Tail\n'))
        ..insert(6, '\n');
      // The rule exits the list instead of inserting a line.
      expect(_docLines(doc), ['Intro', ' [A]', 'Total [B]', 'Tail']);
      expect(doc.toDelta().toList()[1].attributes, _answer('A'));
    });
  });

  group('Multi-line insert into an annotated line', () {
    test('at the start', () {
      final doc = _totalDoc()..insert(6, 'x\ny');
      expect(_docLines(doc), ['Intro', 'x', 'yTotal [A]', 'Tail']);
    });

    test('in the middle', () {
      final doc = _totalDoc()..insert(9, 'x\ny');
      expect(_docLines(doc), ['Intro', 'Totx', 'yal [A]', 'Tail']);
    });

    test('at the end', () {
      final doc = _totalDoc()..insert(11, 'x\ny');
      expect(_docLines(doc), ['Intro', 'Totalx [A]', 'y', 'Tail']);
    });

    test('into a list, in the middle', () {
      final doc = _totalDoc(_ul)..insert(9, 'x\ny');
      expect(_docLines(doc), ['Intro', 'Totx', 'yal [A]', 'Tail']);
    });

    test('into a list, at the end', () {
      final doc = _totalDoc(_ul)..insert(11, 'x\ny\nz');
      expect(_docLines(doc), ['Intro', 'Totalx [A]', 'y', 'z', 'Tail']);
    });
  });

  group('Divider on an annotated line', () {
    final hr = BlockEmbed.horizontalRule;

    test('at the start', () {
      final doc = _totalDoc()..insert(6, hr);
      expect(_docLines(doc), ['Intro', '<hr>', 'Total [A]', 'Tail']);
    });

    test('in the middle', () {
      final doc = _totalDoc()..insert(9, hr);
      expect(_docLines(doc), ['Intro', 'Tot', '<hr>', 'al [A]', 'Tail']);
    });

    test('at the end', () {
      final doc = _totalDoc()..insert(11, hr);
      expect(_docLines(doc), ['Intro', 'Total [A]', '<hr>', 'Tail']);
    });

    test('on an empty line', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert('\n', _answer('A'))
        ..insert('Tail\n'))
        ..insert(6, hr);
      expect(_docLines(doc), ['Intro', '<hr>', 'Tail']);
    });

    test('Enter after a divider above an annotated line', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert(hr.toJson())
        ..insert('\nTotal')
        ..insert('\n', _answer('A')))
        ..insert(7, '\n');
      expect(_docLines(doc), ['Intro', '<hr>', '', 'Total [A]']);
    });

    test('typing before a divider above an annotated line', () {
      final doc = _doc(Delta()
        ..insert('Intro\n')
        ..insert(hr.toJson())
        ..insert('\nTotal')
        ..insert('\n', _answer('A')))
        ..insert(6, 'x');
      expect(_docLines(doc), ['Intro', 'x', '<hr>', 'Total [A]']);
    });
  });

  group('fixAnswerPlacement', () {
    final document = Delta()
      ..insert('Total')
      ..insert('\n', _answer('B'));

    test('strips overrides carried by a pasted slice in the middle', () {
      final change = Delta()
        ..retain(3)
        ..insert('x')
        ..insert('\n', _answer('A'))
        ..insert('y');
      final fixed = change.compose(fixAnswerPlacement(document, change));
      expect(_lines(document.compose(fixed)), ['Totx', 'yal [B]']);
    });

    test('keeps the line override with the existing text at the end', () {
      final change = Delta()
        ..retain(5)
        ..insert('x')
        ..insert('\n', _answer('A'))
        ..insert('y');
      final fixed = change.compose(fixAnswerPlacement(document, change));
      expect(_lines(document.compose(fixed)), ['Totalx [B]', 'y']);
    });

    test('keeps the override when the replacement deletes the line break', () {
      final withTail = Delta()
        ..insert('Total')
        ..insert('\n', _answer('B'))
        ..insert('Tail\n');
      final change = Delta()
        ..retain(5)
        ..insert('x\n')
        ..delete(1);
      final fixed = change.compose(fixAnswerPlacement(withTail, change));
      expect(_lines(withTail.compose(fixed)), ['Totalx [B]', 'Tail']);
      // The deleted line break is gone, so there is nothing to unset.
      expect(
          fixAnswerPlacement(withTail, change),
          Delta()
            ..retain(6)
            ..retain(1, {_key: 'B'}));
    });

    test('strips the override when the selection spans text and the break', () {
      final change = Delta()
        ..retain(3)
        ..insert('x\n', _answer('A'))
        ..delete(3);
      final fixed = change.compose(fixAnswerPlacement(document, change));
      expect(_lines(document.compose(fixed)), ['Totx']);
    });

    test('returns an empty delta when no override is involved', () {
      final plain = Delta()..insert('Total\n');
      final change = Delta()
        ..retain(5)
        ..insert('\n');
      expect(fixAnswerPlacement(plain, change), Delta());
    });

    test('returns an empty delta when nothing is inserted', () {
      final change = Delta()
        ..retain(5)
        ..retain(1, _ul);
      expect(fixAnswerPlacement(document, change), Delta());
    });
  });

  // Backspace removes the line break before the cursor and forward Delete the
  // one after it, so each case names the line break that is deleted.
  group('Deleting a line break', () {
    test('empty annotated line below a plain line', () {
      Delta delta() => Delta()
        ..insert('Plain\n')
        ..insert('\n', _answer('A'))
        ..insert('Tail\n');
      // Backspace on the empty line, or forward Delete at the end of Plain.
      expect(_docLines(_doc(delta())..delete(5, 1)), ['Plain', 'Tail']);
      // Forward Delete on the empty line, or Backspace at the start of Tail.
      expect(_docLines(_doc(delta())..delete(6, 1)), ['Plain', 'Tail']);
    });

    test('empty annotated line above a plain line', () {
      final doc = _doc(Delta()
        ..insert('\n', _answer('A'))
        ..insert('Plain\n'))
        ..delete(0, 1);
      expect(_docLines(doc), ['Plain']);
    });

    test('empty annotated line between two annotated lines', () {
      Delta delta() => Delta()
        ..insert('Top')
        ..insert('\n', _answer('A'))
        ..insert('\n', _answer('B'))
        ..insert('Bottom')
        ..insert('\n', _answer('C'));
      expect(_docLines(_doc(delta())..delete(3, 1)), ['Top [A]', 'Bottom [C]']);
      expect(_docLines(_doc(delta())..delete(4, 1)), ['Top [A]', 'Bottom [C]']);
    });

    test('empty plain line above an annotated line keeps the override', () {
      final doc = _doc(Delta()
        ..insert('\nTotal')
        ..insert('\n', _answer('A')))
        ..delete(0, 1);
      expect(_docLines(doc), ['Total [A]']);
    });

    test('joining an annotated line into a plain line keeps the override', () {
      final doc = _doc(Delta()
        ..insert('abc\nTotal')
        ..insert('\n', _answer('A')))
        ..delete(3, 1);
      expect(_docLines(doc), ['abcTotal [A]']);
    });

    test('joining two annotated lines keeps the upper override', () {
      final doc = _doc(Delta()
        ..insert('abc')
        ..insert('\n', _answer('B'))
        ..insert('Total')
        ..insert('\n', _answer('A')))
        ..delete(3, 1);
      expect(_docLines(doc), ['abcTotal [B]']);
    });

    test('both lines empty: the upper value wins', () {
      Delta delta(Map<String, dynamic>? upper) => Delta()
        ..insert('Intro\n')
        ..insert('\n', upper)
        ..insert('\n', _answer('B'))
        ..insert('Tail\n');
      // Backspace on the lower empty line, or forward Delete on the upper one.
      expect(_docLines(_doc(delta(_answer('A')))..delete(6, 1)),
          ['Intro', ' [A]', 'Tail']);
      expect(_docLines(_doc(delta(null))..delete(6, 1)), ['Intro', '', 'Tail']);
    });

    test('other line attributes keep the existing merge behaviour', () {
      final doc = _doc(Delta()
        ..insert('abc\nTotal')
        ..insert('\n', _answer('A', _ul)))
        ..delete(3, 1);
      expect(
          doc.toDelta(),
          Delta()
            ..insert('abcTotal')
            ..insert('\n', _answer('A')));
    });
  });
}
