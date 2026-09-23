import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'repository.dart';

class AppModel extends ChangeNotifier {
  final Repository repository;
  Snapshot snapshot = const Snapshot();
  Json permissions = {};
  String? error;
  bool loading = true, busy = false;
  AppModel(this.repository);
  Future<void> refresh() async {
    try {
      await repository.syncReminders();
      snapshot = await repository.load();
      permissions = await repository.reminderStatus();
      error = null;
    } catch (e) {
      error = '读取失败：$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> commit(List<Json> operations) async {
    if (busy) throw StateError('正在保存，请稍后再试');
    busy = true;
    notifyListeners();
    try {
      await repository.transact(operations);
      await refresh();
      if (error != null) throw StateError(error!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<Occurrence> on(DateTime d) => snapshot.between(day(d), day(d));
  List<Occurrence> get unscheduled =>
      snapshot.between(DateTime.now(), DateTime.now(), unscheduled: true);
  List<Occurrence> get overdue {
    final today = day(DateTime.now());
    final dated = snapshot.entries.where(
      (e) => e.kind == EntryKind.task && e.date != null,
    );
    if (dated.isEmpty) return [];
    final first = dated
        .map((e) => e.date!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return snapshot
        .between(first, shiftDay(today, -1))
        .where((o) => o.entry.kind == EntryKind.task && !o.done)
        .toList();
  }

  Future<void> complete(Occurrence o) => commit([
    put('completions', {'id': o.key, 'done': !o.done}),
  ]);
  Future<void> save(
    Entry value, {
    Occurrence? original,
    bool following = false,
  }) async {
    if (original != null &&
        !following &&
        snapshot.entries.firstWhere((e) => e.id == original.entry.id).repeat !=
            Repeat.none) {
      value = value.patch({'repeat': 'none', 'until': null});
    }
    final issue = value.validate();
    if (issue != null) throw FormatException(issue);
    final operations = <Json>[];
    if (original == null) {
      operations.add(put('entries', value.toJson()));
    } else {
      final source = snapshot.entries.firstWhere(
        (e) => e.id == original.entry.id,
      );
      if (source.repeat == Repeat.none) {
        operations.add(put('entries', value.patch({'id': source.id}).toJson()));
      } else if (!following) {
        operations.add(
          put('exceptions', {
            'id': original.key,
            'seriesId': source.id,
            'originalDate': dayKey(original.originalDate!),
            'deleted': false,
            'entry': value.patch({
              'id': source.id,
              'repeat': 'none',
              'until': null,
            }).toJson(),
          }),
        );
      } else {
        final cutoff = original.originalDate!;
        operations.add(
          put(
            'entries',
            source.patch({'until': dayKey(shiftDay(cutoff, -1))}).toJson(),
          ),
        );
        // If splitting at the first occurrence, retain no empty/invalid series.
        if (!cutoff.isAfter(source.date!)) {
          operations[0] = remove('entries', source.id);
        }
        operations.add(put('entries', value.patch({'id': newId()}).toJson()));
        for (final x in snapshot.exceptions.values) {
          if (x['seriesId'] == source.id &&
              !DateTime.parse(x['originalDate']).isBefore(cutoff)) {
            operations.add(remove('exceptions', x['id']));
          }
        }
        for (final key in snapshot.completions.keys) {
          if (key.startsWith('${source.id}@') &&
              key.substring(source.id.length + 1).compareTo(dayKey(cutoff)) >=
                  0) {
            operations.add(remove('completions', key));
          }
        }
      }
    }
    await commit(operations);
  }

  Future<void> delete(Occurrence o, bool following) async {
    final source = snapshot.entries.firstWhere((e) => e.id == o.entry.id);
    final ops = <Json>[];
    if (source.repeat == Repeat.none) {
      ops.add(remove('entries', source.id));
      ops.add(remove('completions', o.key));
    } else if (!following) {
      ops.add(
        put('exceptions', {
          'id': o.key,
          'seriesId': source.id,
          'originalDate': dayKey(o.originalDate!),
          'deleted': true,
        }),
      );
      ops.add(remove('completions', o.key));
    } else {
      final cutoff = o.originalDate!;
      ops.add(
        cutoff.isAfter(source.date!)
            ? put(
                'entries',
                source.patch({'until': dayKey(shiftDay(cutoff, -1))}).toJson(),
              )
            : remove('entries', source.id),
      );
      for (final x in snapshot.exceptions.values) {
        if (x['seriesId'] == source.id &&
            !DateTime.parse(x['originalDate']).isBefore(cutoff)) {
          ops.add(remove('exceptions', x['id']));
        }
      }
      for (final key in snapshot.completions.keys) {
        if (key.startsWith('${source.id}@') &&
            key.substring(source.id.length + 1).compareTo(dayKey(cutoff)) >=
                0) {
          ops.add(remove('completions', key));
        }
      }
    }
    await commit(ops);
  }

  Future<void> setSetting(String key, dynamic value) => commit([
    put('settings', {'id': key, 'value': value}),
  ]);
  Future<void> renameCategory(String old, String replacement) async {
    final categories = snapshot.categories
        .map((v) => v == old ? replacement : v)
        .toSet()
        .toList();
    final ops = [
      put('settings', {'id': 'categories', 'value': categories}),
    ];
    for (final e in snapshot.entries.where((e) => e.category == old)) {
      ops.add(put('entries', e.patch({'category': replacement}).toJson()));
    }
    for (final x in snapshot.exceptions.values) {
      if (x['deleted'] == false && x['entry']['category'] == old) {
        ops.add(
          put('exceptions', {
            ...x,
            'entry': {
              ...Map<String, dynamic>.from(x['entry']),
              'category': replacement,
            },
          }),
        );
      }
    }
    await commit(ops);
  }

  Future<void> export() =>
      repository.exportBackup(jsonEncode(snapshot.toJson()));
  Future<Snapshot?> pickImport() async {
    final text = await repository.pickBackup();
    return text == null ? null : decodeBackup(text);
  }

  Future<void> restore(Snapshot data) async {
    await repository.restore(data);
    await refresh();
  }
}
