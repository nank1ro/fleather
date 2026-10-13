import 'package:parchment_delta/parchment_delta.dart';

import '../document/attributes.dart';
import 'utils.dart';

/// Returns a delta to compose after [change] so that the answer override of
/// the line that [change] inserts into stays on exactly one line.
///
/// [document] is the document before [change]. When the insert happens at the
/// end of the line (including an empty line), the override stays with the
/// existing text: the first inserted line break takes it and the original line
/// break loses it. Otherwise the original line break keeps it. Inserted line
/// breaks never carry any other override.
///
/// Returns an empty delta when nothing needs to change.
Delta fixAnswerPlacement(Delta document, Delta change) {
  final key = ParchmentAttribute.answer.key;

  // Walk the inserts of [change], tracking positions in [document] (base) and
  // in the resulting document (pos).
  var base = 0;
  var pos = 0;
  int? insertIndex;
  var insertsBlockEmbed = false;
  final newlines = <int, Object?>{};
  final deleted = <(int, int)>[];
  for (final op in change.toList()) {
    if (op.isDelete) {
      deleted.add((base, base + op.length));
      base += op.length;
    } else if (op.isRetain) {
      base += op.length;
      pos += op.length;
    } else {
      insertIndex ??= base;
      final data = op.data;
      if (data is String) {
        for (var i = data.indexOf('\n');
            i >= 0;
            i = data.indexOf('\n', i + 1)) {
          newlines[pos + i] = op.attributes?[key];
        }
      } else if (isBlockEmbed(data)) {
        insertsBlockEmbed = true;
      }
      pos += op.length;
    }
  }
  if (insertIndex == null || (newlines.isEmpty && !insertsBlockEmbed)) {
    return Delta();
  }

  // Find the line break that terminated the line at the insert position.
  final iter = DeltaIterator(document)..skip(insertIndex);
  var terminator = insertIndex;
  Object? value;
  var found = false;
  while (iter.hasNext) {
    final op = iter.next();
    final lf = op.data is String ? (op.data as String).indexOf('\n') : -1;
    if (lf >= 0) {
      terminator += lf;
      value = op.attributes?[key];
      found = true;
      break;
    }
    terminator += op.length;
  }
  if (!found) return Delta();
  final atLineEnd = terminator == insertIndex;

  final fixes = <int, Object?>{};
  var first = true;
  newlines.forEach((position, current) {
    final wanted = atLineEnd && first ? value : null;
    first = false;
    if (current != wanted) fixes[position] = wanted;
  });
  if (atLineEnd &&
      value != null &&
      !deleted
          .any((range) => range.$1 <= terminator && terminator < range.$2)) {
    fixes[change.transformPosition(terminator)] = null;
  }

  final result = Delta();
  var offset = 0;
  for (final position in fixes.keys.toList()..sort()) {
    result
      ..retain(position - offset)
      ..retain(1, {key: fixes[position]});
    offset = position + 1;
  }
  return result;
}
