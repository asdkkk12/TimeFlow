import 'dart:convert';

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime parseDay(String text) {
  final value = DateTime.parse(text);
  if (dayKey(value) != text || value.year < 2000 || value.year > 2100) {
    throw const FormatException('日期必须在 2000～2100 年内且格式正确');
  }
  return value;
}

DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime shiftDay(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
int _serial = 0;
typedef Json = Map<String, dynamic>;

enum EntryKind { task, event }

enum Repeat { none, daily, weekdays, weekly }

class Entry {
  final String id, title, notes, category;
  final EntryKind kind;
  final DateTime? date, until;
  final int? minute, endMinute, reminder;
  final int endDays, priority;
  final Repeat repeat;
  final List<int> weekdays;
  const Entry({
    required this.id,
    required this.title,
    this.notes = '',
    this.category = '个人',
    this.kind = EntryKind.task,
    this.date,
    this.minute,
    this.endMinute,
    this.endDays = 0,
    this.priority = 1,
    this.repeat = Repeat.none,
    this.weekdays = const [],
    this.until,
    this.reminder,
  });
  factory Entry.fromJson(Json j) => Entry(
    id: j['id'] as String,
    title: j['title'] as String,
    notes: j['notes'] as String,
    category: j['category'] as String,
    kind: EntryKind.values.byName(j['kind']),
    date: j['date'] == null ? null : parseDay(j['date']),
    minute: j['minute'] as int?,
    endMinute: j['endMinute'] as int?,
    endDays: j['endDays'] as int,
    priority: j['priority'] as int,
    repeat: Repeat.values.byName(j['repeat']),
    weekdays: (j['weekdays'] as List).cast<int>(),
    until: j['until'] == null ? null : parseDay(j['until']),
    reminder: j['reminder'] as int?,
  );
  Json toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'category': category,
    'kind': kind.name,
    'date': date == null ? null : dayKey(date!),
    'minute': minute,
    'endMinute': endMinute,
    'endDays': endDays,
    'priority': priority,
    'repeat': repeat.name,
    'weekdays': weekdays,
    'until': until == null ? null : dayKey(until!),
    'reminder': reminder,
  };
  Entry patch(Json changes) => Entry.fromJson({...toJson(), ...changes});
  String? validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        title.trim().isEmpty ||
        title.length > 200 ||
        notes.length > 10000) {
      return '请输入 1～200 字标题，备注最多 10000 字';
    }
    if ([
      date,
      until,
    ].any((d) => d != null && (d.year < 2000 || d.year > 2100))) {
      return '日期必须在 2000～2100 年内';
    }
    if (category.trim().isEmpty ||
        category.length > 40 ||
        priority < 0 ||
        priority > 2) {
      return '分类或优先级无效';
    }
    if ([minute, endMinute].any((v) => v != null && (v < 0 || v >= 1440)) ||
        endDays < 0 ||
        endDays > 365) {
      return '时间范围无效';
    }
    if (minute != null && date == null) return '请先选择日期';
    if (kind == EntryKind.event &&
        (date == null ||
            minute == null ||
            endMinute == null ||
            endDays * 1440 + endMinute! <= minute!)) {
      return '日程结束时间必须晚于开始时间';
    }
    if (repeat != Repeat.none && date == null) return '重复事项需要开始日期';
    if (repeat == Repeat.weekly &&
        (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7))) {
      return '请选择重复星期';
    }
    if (until != null && (date == null || until!.isBefore(date!))) {
      return '重复结束日期不能早于开始日期';
    }
    if (reminder != null &&
        (date == null ||
            minute == null ||
            ![0, 5, 15, 30, 60].contains(reminder))) {
      return '开启提醒需要指定日期和时间';
    }
    return null;
  }

  bool occurs(DateTime d) {
    if (date == null ||
        day(d).isBefore(date!) ||
        (until != null && day(d).isAfter(until!))) {
      return false;
    }
    return switch (repeat) {
      Repeat.none => dayKey(d) == dayKey(date!),
      Repeat.daily => true,
      Repeat.weekdays => d.weekday <= 5,
      Repeat.weekly => weekdays.contains(d.weekday),
    };
  }
}

class Occurrence {
  final Entry entry;
  final String key;
  final DateTime? originalDate;
  final bool done;
  const Occurrence(this.entry, this.key, this.originalDate, this.done);
  DateTime? get start => entry.date == null
      ? null
      : DateTime(
          entry.date!.year,
          entry.date!.month,
          entry.date!.day,
          0,
          entry.minute ?? 0,
        );
  DateTime? get end => start == null
      ? null
      : DateTime(
          entry.date!.year,
          entry.date!.month,
          entry.date!.day + entry.endDays,
          0,
          entry.endMinute ?? entry.minute ?? 0,
        );
}

class Snapshot {
  final List<Entry> entries;
  final Map<String, Json> exceptions;
  final Map<String, Json> completions;
  final Json settings;
  const Snapshot({
    this.entries = const [],
    this.exceptions = const {},
    this.completions = const {},
    this.settings = const {},
  });
  factory Snapshot.fromJson(Json j) => Snapshot(
    entries: (j['entries'] as List)
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    exceptions: {
      for (final e in j['exceptions'] as List)
        e['id'] as String: Map<String, dynamic>.from(e),
    },
    completions: {
      for (final e in j['completions'] as List)
        e['id'] as String: Map<String, dynamic>.from(e),
    },
    settings: {
      for (final e in j['settings'] as List) e['id'] as String: e['value'],
    },
  );
  Json toJson() => {
    'version': 1,
    'entries': entries.map((e) => e.toJson()).toList(),
    'exceptions': exceptions.values.toList(),
    'completions': completions.values.toList(),
    'settings': settings.entries
        .map((e) => {'id': e.key, 'value': e.value})
        .toList(),
  };
  List<String> get categories =>
      (settings['categories'] as List? ?? ['个人', '工作', '学习', '生活'])
          .cast<String>();
  List<Occurrence> between(
    DateTime from,
    DateTime to, {
    bool unscheduled = false,
  }) {
    final result = <Occurrence>[];
    void add(Entry e, String key, DateTime? original) {
      final shown = e.date;
      final overlaps =
          shown != null &&
          !shown.isAfter(to) &&
          !shiftDay(
            shown,
            e.kind == EntryKind.event ? e.endDays : 0,
          ).isBefore(from);
      if ((unscheduled && shown == null) || (!unscheduled && overlaps)) {
        result.add(
          Occurrence(e, key, original, completions[key]?['done'] == true),
        );
      }
    }

    for (final e in entries) {
      if (e.date == null) {
        add(e, e.id, null);
        continue;
      }
      if (e.repeat == Repeat.none) {
        if (!exceptions.containsKey(e.id)) add(e, e.id, e.date);
      } else if (!unscheduled) {
        var cursor = shiftDay(from, e.kind == EntryKind.event ? -e.endDays : 0);
        if (cursor.isBefore(e.date!)) cursor = e.date!;
        for (; !cursor.isAfter(to); cursor = shiftDay(cursor, 1)) {
          if (!e.occurs(cursor)) continue;
          final key = '${e.id}@${dayKey(cursor)}';
          if (!exceptions.containsKey(key)) {
            add(e.patch({'date': dayKey(cursor)}), key, cursor);
          }
        }
      }
    }
    for (final x in exceptions.values) {
      if (x['deleted'] == true) continue;
      add(
        Entry.fromJson(Map<String, dynamic>.from(x['entry'])),
        x['id'],
        x['originalDate'] == null ? null : parseDay(x['originalDate']),
      );
    }
    result.sort((a, b) {
      final date = (a.entry.date ?? DateTime(9999)).compareTo(
        b.entry.date ?? DateTime(9999),
      );
      if (date != 0) return date;
      final minute = (a.entry.minute ?? 1440).compareTo(b.entry.minute ?? 1440);
      return minute != 0
          ? minute
          : b.entry.priority.compareTo(a.entry.priority);
    });
    return result;
  }
}

Snapshot decodeBackup(String text) {
  final j = jsonDecode(text);
  if (j is! Map<String, dynamic> || j['version'] != 1) {
    throw const FormatException('不支持的备份版本');
  }
  for (final name in ['entries', 'exceptions', 'completions', 'settings']) {
    if (j[name] is! List || (j[name] as List).length > 100000) {
      throw const FormatException('备份数据结构无效');
    }
    final ids = <String>{};
    for (final row in j[name]) {
      if (row is! Map ||
          row['id'] is! String ||
          (row['id'] as String).isEmpty ||
          !ids.add(row['id'])) {
        throw const FormatException('备份包含无效或重复 ID');
      }
    }
  }
  final s = Snapshot.fromJson(j);
  for (final e in s.entries) {
    if (e.validate() != null) throw FormatException(e.validate()!);
  }
  final ids = s.entries.map((e) => e.id).toSet();
  for (final x in s.exceptions.values) {
    if (!ids.contains(x['seriesId']) || x['deleted'] is! bool) {
      throw const FormatException('例外记录引用无效');
    }
    final source = s.entries.firstWhere((e) => e.id == x['seriesId']);
    if (source.repeat == Repeat.none || x['originalDate'] == null) {
      throw const FormatException('例外必须属于重复事项');
    }
    final original = parseDay(x['originalDate']);
    if (!source.occurs(original) ||
        x['id'] != '${source.id}@${dayKey(original)}') {
      throw const FormatException('例外日期或 ID 无效');
    }
    if (x['deleted'] == false && x['entry']['id'] != source.id) {
      throw const FormatException('例外所属事项不匹配');
    }
    if (x['deleted'] == false &&
        Entry.fromJson(Map<String, dynamic>.from(x['entry'])).validate() !=
            null) {
      throw const FormatException('例外事项无效');
    }
  }
  for (final c in s.completions.values) {
    if (!ids.contains((c['id'] as String).split('@').first)) {
      throw const FormatException('完成记录引用无效');
    }
    if (c['done'] is! bool) throw const FormatException('完成记录无效');
  }
  if (s.categories.isEmpty ||
      s.categories.any((c) => c.trim().isEmpty || c.length > 40) ||
      s.categories.toSet().length != s.categories.length) {
    throw const FormatException('分类无效');
  }
  if (!['system', 'light', 'dark'].contains(s.settings['theme'] ?? 'system')) {
    throw const FormatException('主题无效');
  }
  return s;
}
