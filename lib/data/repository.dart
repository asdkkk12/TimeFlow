import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models.dart';

abstract class Repository {
  Future<Snapshot> load();
  Future<void> transact(List<Json> operations);
  Future<Json> reminderStatus();
  Future<void> syncReminders();
  Future<void> requestPermission(String type);
  Future<void> exportBackup(String text);
  Future<String?> pickBackup();
  Future<void> restore(Snapshot snapshot);
}

class AndroidRepository implements Repository {
  static const channel = MethodChannel('app.timeflow/native');
  @override
  Future<Snapshot> load() async => Snapshot.fromJson(
    jsonDecode(await channel.invokeMethod<String>('snapshot') ?? '{}'),
  );
  @override
  Future<void> transact(List<Json> operations) =>
      channel.invokeMethod('transact', jsonEncode(operations));
  @override
  Future<Json> reminderStatus() async =>
      Map<String, dynamic>.from(await channel.invokeMethod('reminderStatus'));
  @override
  Future<void> syncReminders() => channel.invokeMethod('syncReminders');
  @override
  Future<void> requestPermission(String type) =>
      channel.invokeMethod('permission', type);
  @override
  Future<void> exportBackup(String text) =>
      channel.invokeMethod('export', text);
  @override
  Future<String?> pickBackup() => channel.invokeMethod<String>('import');
  @override
  Future<void> restore(Snapshot snapshot) =>
      channel.invokeMethod('restore', jsonEncode(snapshot.toJson()));
}

Json put(String table, Json row) => {'table': table, 'row': row};
Json remove(String table, String id) => {'table': table, 'delete': id};
