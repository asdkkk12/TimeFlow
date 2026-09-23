import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timeflow/domain/models.dart';

Entry task({
  String id = 't',
  Repeat repeat = Repeat.none,
  DateTime? date,
  DateTime? until,
  List<int> weekdays = const [],
}) => Entry(
  id: id,
  title: '学习',
  date: date ?? DateTime(2026, 9, 21),
  repeat: repeat,
  until: until,
  weekdays: weekdays,
);
void main() {
  test('backup rejects normalized invalid date and orphan completion', () {
    final badDate = Snapshot(entries: [task()]).toJson();
    (badDate['entries'] as List).first['date'] = '2026-02-31';
    expect(() => decodeBackup(jsonEncode(badDate)), throwsFormatException);
    expect(
      () => decodeBackup(
        jsonEncode(
          const Snapshot(
            completions: {
              'missing': {'id': 'missing', 'done': true},
            },
          ).toJson(),
        ),
      ),
      throwsFormatException,
    );
  });

  test('daily spans month boundary, inclusive repeat end', () {
    final s = Snapshot(
      entries: [
        task(
          repeat: Repeat.daily,
          date: DateTime(2026, 9, 29),
          until: DateTime(2026, 10, 2),
        ),
      ],
    );
    expect(s.between(DateTime(2026, 9, 29), DateTime(2026, 10, 3)).length, 4);
  });
  test('workdays exclude weekend and weekly honors chosen days', () {
    final start = DateTime(2026, 9, 21), end = DateTime(2026, 9, 27);
    expect(
      Snapshot(entries: [task(repeat: Repeat.weekdays)])
          .between(start, end)
          .length,
      5,
    );
    expect(
      Snapshot(
        entries: [
          task(repeat: Repeat.weekly, weekdays: [2, 7]),
        ],
      ).between(start, end).map((o) => o.entry.date!.weekday),
      [2, 7],
    );
  });
  test('moved occurrence retains original key and completion attribution', () {
    final e = task(repeat: Repeat.daily);
    const key = 't@2026-09-22';
    final s = Snapshot(
      entries: [e],
      exceptions: {
        key: {
          'id': key,
          'seriesId': 't',
          'originalDate': '2026-09-22',
          'deleted': false,
          'entry': e.patch({'date': '2026-09-24', 'repeat': 'none'}).toJson(),
        },
      },
      completions: {
        key: {'id': key, 'done': true},
      },
    );
    expect(s.between(DateTime(2026, 9, 22), DateTime(2026, 9, 22)), isEmpty);
    final moved = s.between(DateTime(2026, 9, 24), DateTime(2026, 9, 24));
    expect(moved.length, 2);
    expect(moved.firstWhere((o) => o.key == key).done, true);
    expect(
      moved.firstWhere((o) => o.key == key).originalDate,
      DateTime(2026, 9, 22),
    );
  });
  test('single deletion does not remove other repeat instances', () {
    final s = Snapshot(
      entries: [task(repeat: Repeat.daily)],
      exceptions: {
        't@2026-09-22': {
          'id': 't@2026-09-22',
          'seriesId': 't',
          'originalDate': '2026-09-22',
          'deleted': true,
        },
      },
    );
    expect(s.between(DateTime(2026, 9, 21), DateTime(2026, 9, 23)).length, 2);
  });
  test('cross-day event appears on both dates, never completes itself', () {
    final event = Entry(
      id: 'e',
      title: '跨夜',
      kind: EntryKind.event,
      date: DateTime(2026, 9, 21),
      minute: 1380,
      endMinute: 60,
      endDays: 1,
    );
    final s = Snapshot(entries: [event]);
    expect(event.validate(), isNull);
    expect(
      s.between(DateTime(2026, 9, 22), DateTime(2026, 9, 22)).single.done,
      false,
    );
  });
  test('reminder requires date and time, event requires valid end', () {
    expect(
      const Entry(id: 'a', title: '任务', reminder: 0).validate(),
      isNotNull,
    );
    expect(
      const Entry(id: 'a', title: '日程', kind: EntryKind.event).validate(),
      isNotNull,
    );
  });
  test('undated tasks only appear in inbox', () {
    const s = Snapshot(
      entries: [Entry(id: 'i', title: '想法')],
    );
    expect(s.between(DateTime(2026), DateTime(2027)), isEmpty);
    expect(
      s.between(DateTime(2026), DateTime(2027), unscheduled: true).length,
      1,
    );
  });
  test('backup round trip preserves full data and settings', () {
    final s = Snapshot(
      entries: [task()],
      completions: {
        't': {'id': 't', 'done': true},
      },
      settings: {
        'theme': 'dark',
        'categories': ['个人'],
      },
    );
    final restored = decodeBackup(jsonEncode(s.toJson()));
    expect(restored.toJson(), s.toJson());
  });
  test('invalid backups are rejected before any mutation', () {
    expect(() => decodeBackup('{"version":2}'), throwsFormatException);
    final data = Snapshot(entries: [task(), task()]).toJson();
    expect(() => decodeBackup(jsonEncode(data)), throwsFormatException);
    final invalid = Snapshot(
      entries: [
        task().patch({'title': ''}),
      ],
    ).toJson();
    expect(() => decodeBackup(jsonEncode(invalid)), throwsFormatException);
    final orphan = Snapshot(
      exceptions: {
        'bad': {'id': 'bad', 'seriesId': 'missing', 'deleted': true},
      },
    ).toJson();
    expect(() => decodeBackup(jsonEncode(orphan)), throwsFormatException);
  });
  test('5000 entries produce a stable complete query', () {
    final s = Snapshot(entries: List.generate(5000, (i) => task(id: '$i')));
    expect(
      s.between(DateTime(2026, 9, 21), DateTime(2026, 9, 21)).length,
      5000,
    );
  });
}
