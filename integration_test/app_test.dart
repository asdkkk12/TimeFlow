import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timeflow/data/app_model.dart';
import 'package:timeflow/data/repository.dart';
import 'package:timeflow/domain/models.dart';
import 'package:timeflow/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android SQLite, recurrence, reminder scheduling and UI', (
    tester,
  ) async {
    final repository = AndroidRepository();
    // Runs only on a disposable emulator; do not run against a user's device.
    await repository.restore(const Snapshot());
    final bulk = Snapshot(
      entries: List.generate(
        5000,
        (i) => Entry(id: 'bulk-$i', title: '事项 $i', date: day(DateTime.now())),
      ),
    );
    final watch = Stopwatch()..start();
    await repository.restore(bulk);
    expect((await repository.load()).entries.length, 5000);
    watch.stop();
    binding.reportData = {'sqlite5000RoundTripMs': watch.elapsedMilliseconds};
    await repository.restore(const Snapshot());
    final model = AppModel(repository);
    await model.refresh();
    expect(model.error, isNull);
    final today = day(DateTime.now());
    final reminderAt = DateTime.now().add(const Duration(minutes: 2));
    final task = Entry(
      id: 'integration-task',
      title: '整理今天的重点',
      category: '工作',
      date: today,
      priority: 2,
    );
    final recurring = Entry(
      id: 'integration-repeat',
      title: '阅读 20 分钟',
      category: '学习',
      date: today,
      minute: 21 * 60,
      repeat: Repeat.daily,
      reminder: 15,
    );
    final event = Entry(
      id: 'integration-event',
      title: 'TimeFlow 提醒验证',
      category: '工作',
      kind: EntryKind.event,
      date: day(reminderAt),
      minute: reminderAt.hour * 60 + reminderAt.minute,
      endMinute: (reminderAt.hour * 60 + reminderAt.minute + 30) % 1440,
      endDays: (reminderAt.hour * 60 + reminderAt.minute + 30) ~/ 1440,
      reminder: 0,
    );
    await model.save(task);
    await model.save(recurring);
    await model.save(event);
    final reloaded = await repository.load();
    expect(reloaded.entries.length, 3);
    await model.complete(model.on(today).firstWhere((o) => o.key == task.id));
    expect((await repository.load()).completions[task.id]?['done'], true);
    final original = model
        .on(shiftDay(today, 1))
        .firstWhere((o) => o.entry.id == recurring.id);
    await model.save(
      original.entry.patch({
        'title': '只修改这一次',
        'repeat': 'none',
        'reminder': null,
      }),
      original: original,
    );
    expect(
      model
          .on(shiftDay(today, 1))
          .firstWhere((o) => o.entry.id == recurring.id)
          .entry
          .title,
      '只修改这一次',
    );
    expect(
      model
          .on(shiftDay(today, 2))
          .firstWhere((o) => o.entry.id == recurring.id)
          .entry
          .title,
      recurring.title,
    );
    final copy = model.snapshot;
    await repository.restore(copy);
    expect((await repository.load()).toJson(), copy.toJson());
    await tester.pumpWidget(TimeFlowApp(model: model));
    await tester.pumpAndSettle();
    expect(find.text('TimeFlow'), findsOneWidget);
    expect(find.text('1 / 2  项已完成'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('today');
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await binding.takeScreenshot('plan');
    await tester.tap(find.text('回顾').last);
    await tester.pumpAndSettle();
    expect(find.text('最近七天'), findsOneWidget);
    await binding.takeScreenshot('review');
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('settings');
    await tester.tap(find.text('今天').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
