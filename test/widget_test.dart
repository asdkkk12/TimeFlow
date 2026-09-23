import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timeflow/main.dart';
import 'package:timeflow/data/app_model.dart';
import 'package:timeflow/data/repository.dart';
import 'package:timeflow/domain/models.dart';
import 'package:timeflow/ui/editor.dart';

class MemoryRepository implements Repository {
  Snapshot data = const Snapshot();
  String? requestedPermission;
  bool vibrationEnabled = true;
  bool vivoDevice = false;
  bool fullScreen = true;
  @override
  Future<Snapshot> load() async => data;
  @override
  Future<void> transact(List<Json> operations) async {
    final json = data.toJson();
    for (final op in operations) {
      final rows = json[op['table']] as List;
      rows.removeWhere((r) => r['id'] == (op['delete'] ?? op['row']['id']));
      if (op['row'] != null) rows.add(op['row']);
    }
    data = Snapshot.fromJson(json);
  }

  @override
  Future<Json> reminderStatus() async => {
    'notifications': true,
    'exact': true,
    'missed': 0,
    'vibratorAvailable': true,
    'vibrationEnabled': vibrationEnabled,
    'strongNotifications': true,
    'strongVibrationEnabled': true,
    'fullScreen': fullScreen,
    'vivoDevice': vivoDevice,
    'fullScreenSpecialAccess': false,
  };
  @override
  Future<void> syncReminders() async {}
  @override
  Future<void> requestPermission(String type) async {
    requestedPermission = type;
  }

  @override
  Future<void> exportBackup(String text) async {}
  @override
  Future<String?> pickBackup() async => null;
  @override
  Future<void> restore(Snapshot snapshot) async {
    data = snapshot;
  }
}

void main() {
  testWidgets('new item defaults to event and at-time reminder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntryEditor(
          date: DateTime(2026, 9, 23),
          categories: const ['个人'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selector = tester.widget<SegmentedButton<EntryKind>>(
      find.byType(SegmentedButton<EntryKind>),
    );
    expect(selector.selected, {EntryKind.event});
    await tester.scrollUntilVisible(
      find.text('到点提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('到点提醒'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'vibration settings reflect disabled channel and open system settings',
    (tester) async {
      final repo = MemoryRepository()..vibrationEnabled = false;
      final model = AppModel(repo);
      await model.refresh();
      await tester.pumpWidget(TimeFlowApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('未开启或通知已静音 · 点击设置'), findsOneWidget);
      await tester.tap(find.text('任务振动提醒'));
      await tester.pumpAndSettle();
      expect(repo.requestedPermission, 'vibration');
      repo.vibrationEnabled = true;
      await model.refresh();
      await tester.pumpAndSettle();
      expect(find.text('已开启 · 到点随通知振动'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'vivo lock screen settings expose both system and vendor routes',
    (tester) async {
      final repo = MemoryRepository()..vivoDevice = true;
      final model = AppModel(repo);
      await model.refresh();
      await tester.pumpWidget(TimeFlowApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('锁屏弹出提醒'), 200);
      expect(find.text('还需在 vivo 系统中检查后台弹出界面与锁屏通知'), findsOneWidget);
      await tester.tap(find.text('锁屏弹出提醒'));
      expect(repo.requestedPermission, 'fullScreen');
      await tester.scrollUntilVisible(find.text('vivo 后台弹出界面'), 200);
      await tester.tap(find.text('vivo 后台弹出界面'));
      expect(repo.requestedPermission, 'backgroundPopup');
      await tester.scrollUntilVisible(find.text('vivo 锁屏后台运行'), 200);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('vivo 锁屏后台运行'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('vivo 锁屏后台运行'));
      expect(repo.requestedPermission, 'backgroundPower');
      repo.fullScreen = false;
      await model.refresh();
      await tester.pumpAndSettle();
      expect(find.text('未允许 · 点击打开系统全屏提醒设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('small screen, large text and dark theme remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = MemoryRepository();
    repo.data = const Snapshot(settings: {'theme': 'dark'});
    final model = AppModel(repo);
    await model.refresh();
    await tester.pumpWidget(TimeFlowApp(model: model));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty app navigates and saves a default event end to end', (
    tester,
  ) async {
    final model = AppModel(MemoryRepository());
    await model.refresh();
    await tester.pumpWidget(TimeFlowApp(model: model));
    await tester.pumpAndSettle();
    expect(find.text('把时间，留给重要的事。'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '准备明天的会议');
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();
    expect(model.snapshot.entries.single.title, '准备明天的会议');
    expect(model.snapshot.entries.single.kind, EntryKind.event);
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();
    expect(find.text('给未来留好位置'), findsOneWidget);
    await tester.tap(find.text('回顾').last);
    await tester.pumpAndSettle();
    expect(find.text('每一步，都算数。'), findsOneWidget);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('让 TimeFlow 适合你'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('split series keeps earlier completion records', () async {
    final repo = MemoryRepository();
    final e = Entry(
      id: 'r',
      title: '阅读',
      date: DateTime(2026, 9, 21),
      repeat: Repeat.daily,
    );
    repo.data = Snapshot(
      entries: [e],
      completions: {
        'r@2026-09-21': {'id': 'r@2026-09-21', 'done': true},
      },
    );
    final model = AppModel(repo);
    await model.refresh();
    final o = model.on(DateTime(2026, 9, 23)).single;
    await model.save(
      o.entry.patch({'title': '阅读新版'}),
      original: o,
      following: true,
    );
    expect(model.on(DateTime(2026, 9, 21)).single.done, true);
    expect(model.on(DateTime(2026, 9, 22)).single.entry.title, '阅读');
    expect(model.on(DateTime(2026, 9, 23)).single.entry.title, '阅读新版');
    expect(model.on(DateTime(2026, 9, 24)).length, 1);
  });
  test(
    'delete following at start removes series without invalid end date',
    () async {
      final repo = MemoryRepository();
      repo.data = Snapshot(
        entries: [
          Entry(
            id: 'r',
            title: '阅读',
            date: DateTime(2026, 9, 21),
            repeat: Repeat.daily,
          ),
        ],
      );
      final model = AppModel(repo);
      await model.refresh();
      await model.delete(model.on(DateTime(2026, 9, 21)).single, true);
      expect(model.snapshot.entries, isEmpty);
    },
  );
}
