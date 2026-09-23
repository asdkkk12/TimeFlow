import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_model.dart';
import '../domain/models.dart';
import 'editor.dart';

class Home extends StatefulWidget {
  final AppModel model;
  const Home({super.key, required this.model});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int index = 0, visible = 50;
  DateTime selected = day(DateTime.now());
  late Timer timer;
  AppModel get model => widget.model;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) model.refresh();
  }

  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作未完成：$e')));
      }
    }
  }

  String? nextReminderPermission() {
    if (model.permissions['notifications'] != true) return 'notifications';
    if (model.permissions['exact'] != true) return 'exact';
    if (model.permissions['strongNotifications'] != true ||
        model.permissions['strongVibrationEnabled'] != true) {
      return 'strongVibration';
    }
    if (model.permissions['strongHeadsUp'] == false) return 'strongVibration';
    if (model.permissions['fullScreen'] != true) return 'fullScreen';
    return null;
  }

  String reminderPermissionText(String permission) => switch (permission) {
    'notifications' => '通知权限未开启，日程无法提醒',
    'exact' => '准时提醒权限未开启，到点提醒可能延迟',
    'strongVibration' => '请开启日程强提醒的振动和悬浮通知（高重要性）',
    'fullScreen' => '锁屏弹出权限未开启，锁屏时可能只显示通知',
    _ => '提醒权限未完整',
  };

  Future<bool?> scope(String verb) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$verb重复事项'),
      content: const Text('选择本次操作的范围，之前的历史记录会保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('仅本次'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('本次及以后'),
        ),
      ],
    ),
  );
  bool isRecurring(Occurrence o) =>
      model.snapshot.entries.firstWhere((e) => e.id == o.entry.id).repeat !=
      Repeat.none;
  Future<void> edit([Occurrence? original]) async {
    bool following = false;
    if (original != null && isRecurring(original)) {
      final answer = await scope('编辑');
      if (answer == null) return;
      following = answer;
    }
    if (!mounted) return;
    final value = await Navigator.push<Entry>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditor(
          initial: original == null
              ? null
              : following
              ? original.entry.patch({
                  'repeat': model.snapshot.entries
                      .firstWhere((e) => e.id == original.entry.id)
                      .repeat
                      .name,
                  'weekdays': model.snapshot.entries
                      .firstWhere((e) => e.id == original.entry.id)
                      .weekdays,
                  'until': model.snapshot.entries
                      .firstWhere((e) => e.id == original.entry.id)
                      .toJson()['until'],
                })
              : original.entry,
          date: index == 1 ? selected : day(DateTime.now()),
          categories: model.snapshot.categories,
          single: original != null && isRecurring(original) && !following,
        ),
      ),
    );
    if (value == null || !mounted) return;
    if (value.kind == EntryKind.event) {
      final start = DateTime(
        value.date!.year,
        value.date!.month,
        value.date!.day,
        0,
        value.minute!,
      );
      final end = DateTime(
        value.date!.year,
        value.date!.month,
        value.date!.day + value.endDays,
        0,
        value.endMinute!,
      );
      final conflicts = model.snapshot
          .between(value.date!, day(end))
          .where(
            (o) =>
                o.entry.kind == EntryKind.event &&
                o.key != original?.key &&
                o.start!.isBefore(end) &&
                o.end!.isAfter(start),
          );
      if (conflicts.isNotEmpty) {
        final yes = await confirm(
          '日程时间有重叠',
          '与「${conflicts.first.entry.title}」时间重叠，仍然保存吗？',
        );
        if (!yes) return;
      }
    }
    var saved = false;
    await act(() async {
      await model.save(value, original: original, following: following);
      saved = true;
    });
    final missing = nextReminderPermission();
    if (saved &&
        value.kind == EntryKind.event &&
        value.reminder != null &&
        missing != null &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(reminderPermissionText(missing)),
          action: SnackBarAction(
            label: '去开启',
            onPressed: () =>
                act(() => model.repository.requestPermission(missing)),
          ),
        ),
      );
    }
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> delete(Occurrence o) async {
    final following = isRecurring(o)
        ? await scope('删除')
        : await confirm('删除事项', '确定删除「${o.entry.title}」吗？')
        ? false
        : null;
    if (following != null) await act(() => model.delete(o, following));
  }

  Widget heading(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (subtitle != null)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  Widget empty(String title, String subtitle, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
  Widget occurrence(Occurrence o) {
    final e = o.entry;
    final accent = e.kind == EntryKind.event
        ? const Color(0xFF5985C4)
        : e.priority == 2
        ? const Color(0xFFCE8553)
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          leading: IconButton(
            tooltip: o.done ? '撤销完成' : '标记完成',
            onPressed: model.busy ? null : () => act(() => model.complete(o)),
            icon: Icon(
              o.done
                  ? Icons.check_circle
                  : e.kind == EntryKind.event
                  ? Icons.event_outlined
                  : Icons.radio_button_unchecked,
              color: accent,
            ),
          ),
          title: Text(
            e.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: o.done ? TextDecoration.lineThrough : null,
              color: o.done ? Theme.of(context).colorScheme.outline : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${e.category} · ${e.date == null ? '待安排' : '${dayKey(e.date!).substring(5)}  ${clockText(e.minute)}'}${e.kind == EntryKind.event ? ' — ${e.endDays > 0 ? '+${e.endDays}天 ' : ''}${clockText(e.endMinute)}' : ''}${isRecurring(o) ? ' · 重复' : ''}${e.reminder != null ? ' · 提醒' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          onTap: () => edit(o),
          trailing: PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (v) {
              if (v == 'edit') edit(o);
              if (v == 'delete') delete(o);
              if (v == 'move') {
                act(
                  () => model.save(
                    e.patch({'date': dayKey(shiftDay(DateTime.now(), 1))}),
                    original: o,
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              if (e.kind == EntryKind.task)
                const PopupMenuItem(value: 'move', child: Text('顺延到明天')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> list(List<Occurrence> rows) => [
    for (final row in rows.take(visible)) occurrence(row),
    if (rows.length > visible)
      TextButton(
        onPressed: () => setState(() => visible += 50),
        child: Text('加载更多（还有 ${rows.length - visible} 项）'),
      ),
  ];
  Widget permissionNotice() {
    final missing = nextReminderPermission();
    if (missing == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer
            .withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: const Icon(Icons.notifications_none),
          title: const Text('提醒权限未完整'),
          subtitle: Text(reminderPermissionText(missing)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => act(() => model.repository.requestPermission(missing)),
        ),
      ),
    );
  }

  List<Widget> today() {
    final now = DateTime.now();
    final rows = model.on(now);
    final tasks = rows.where((o) => o.entry.kind == EntryKind.task).toList();
    final events = rows.where((o) => o.entry.kind == EntryKind.event).toList();
    final done = tasks.where((o) => o.done).length;
    final upcoming = model.snapshot
        .between(day(now), shiftDay(now, 7))
        .where(
          (o) =>
              o.entry.kind == EntryKind.event &&
              o.start!.isAfter(now) &&
              !o.done,
        )
        .toList();
    final late = model.overdue;
    return [
      Text(
        '${now.month} 月 ${now.day} 日 · 星期${'一二三四五六日'[now.weekday - 1]}',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
      const SizedBox(height: 10),
      Text(
        '把时间，留给重要的事。',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF176B58),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TODAY / 今日进度',
              style: TextStyle(color: Color(0xFFC1E3CE), letterSpacing: 1.5),
            ),
            const SizedBox(height: 18),
            Text(
              tasks.isEmpty ? '今天，从容开始' : '$done / ${tasks.length}  项已完成',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: tasks.isEmpty ? 0 : done / tasks.length,
                minHeight: 7,
                backgroundColor: Colors.white24,
                color: const Color(0xFFDBEE9B),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tasks.isEmpty
                  ? '还没有任务，给今天一个小目标吧。'
                  : done == tasks.length
                  ? '今天的目标已经完成，做得很好。'
                  : '一件一件来，按自己的节奏前进。',
              style: const TextStyle(color: Color(0xFFD7E7DF)),
            ),
          ],
        ),
      ),
      permissionNotice(),
      if ((model.permissions['missed'] as int? ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '有 ${model.permissions['missed']} 条提醒已错过，可在计划中查看；不会补发历史通知。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (upcoming.isNotEmpty) ...[
        heading('下一项安排'),
        occurrence(upcoming.first),
      ],
      heading('日程时间轴', '${events.length} 项安排'),
      if (events.isEmpty)
        empty('留一点自由时间', '今天没有固定日程', Icons.wb_sunny_outlined)
      else
        ...list(events),
      heading(
        '今日待办',
        tasks.isEmpty ? '暂无任务' : '${(done / tasks.length * 100).round()}% 完成',
      ),
      if (tasks.isEmpty)
        empty('一个小目标，也值得记录', '点击下方“新建”，安排今天的第一件事', Icons.checklist_rounded)
      else
        ...list(tasks),
      if (late.isNotEmpty) ...[
        heading('逾期事项', '${late.length} 项待处理'),
        ...list(late),
      ],
    ];
  }

  List<Widget> plan() {
    final rows = model.on(selected);
    return [
      Text(
        '给未来留好位置',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('日程与任务，在这里一目了然。'),
      const SizedBox(height: 18),
      Card(
        child: CalendarDatePicker(
          initialDate: selected,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          onDateChanged: (v) => setState(() {
            selected = v;
            visible = 50;
          }),
        ),
      ),
      heading('${selected.month} 月 ${selected.day} 日', '${rows.length} 项'),
      if (rows.isEmpty)
        empty('这一天还很轻盈', '添加任务或日程，慢慢安排', Icons.event_note_outlined)
      else
        ...list(rows),
      heading('待安排', '${model.unscheduled.length} 项'),
      if (model.unscheduled.isEmpty)
        empty('想法都有了去处', '没有日期的任务会收纳在这里', Icons.inbox_outlined)
      else
        ...list(model.unscheduled),
    ];
  }

  List<Widget> review() {
    final today = day(DateTime.now());
    final week = List.generate(7, (i) => shiftDay(today, i - 6));
    final tasks = model
        .on(selected)
        .where((o) => o.entry.kind == EntryKind.task)
        .toList();
    final done = tasks.where((o) => o.done).toList();
    final pending = tasks.where((o) => !o.done).toList();
    return [
      Text(
        '每一步，都算数。',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('按计划日期回顾，补做也会更新原日记录。'),
      heading('最近七天'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: week.map((date) {
              final list = model
                  .on(date)
                  .where((o) => o.entry.kind == EntryKind.task)
                  .toList();
              final n = list.where((o) => o.done).length;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text('${date.month}/${date.day}'),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: list.isEmpty ? 0 : n / list.length,
                          minHeight: 10,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: Text(
                        list.isEmpty
                            ? '暂无任务'
                            : '$n/${list.length} · ${(n / list.length * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: selected,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) {
            setState(() {
              selected = d;
              visible = 50;
            });
          }
        },
        icon: const Icon(Icons.calendar_month),
        label: Text(dayKey(selected)),
      ),
      heading('已完成', '${done.length} 项'),
      if (done.isEmpty)
        empty('进步不必着急', '完成的任务会出现在这里', Icons.done_all)
      else
        ...list(done),
      heading('未完成', '${pending.length} 项'),
      if (pending.isEmpty)
        empty('没有未完成任务', '享受属于自己的时间', Icons.spa_outlined)
      else
        ...list(pending),
    ];
  }

  Future<void> categoryDialog([String? old]) async {
    final controller = TextEditingController(text: old);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(old == null ? '新增分类' : '重命名分类'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog route retains its controller until the close animation finishes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (value == null) return;
    await act(
      () => old == null
          ? model.setSetting(
              'categories',
              {...model.snapshot.categories, value}.toList(),
            )
          : model.renameCategory(old, value),
    );
  }

  String get fullScreenStatus {
    if (model.permissions['fullScreen'] != true) {
      return '未允许 · 点击打开系统全屏提醒设置';
    }
    if (model.permissions['strongHeadsUp'] == false) {
      return '日程通知未开启或重要性不足 · 请先设置日程强提醒';
    }
    if (model.permissions['vivoDevice'] == true) {
      return '还需在 vivo 系统中检查后台弹出界面与锁屏通知';
    }
    return model.permissions['fullScreenSpecialAccess'] == true
        ? '系统全屏权限已允许 · 仍受锁屏通知设置影响'
        : '请检查日程的锁屏与悬浮通知 · 当前系统无单独全屏授权';
  }

  List<Widget> settings() => [
    Text(
      '让 TimeFlow 适合你',
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    const Text('无需登录，数据只保存在这台设备。'),
    heading('提醒与权限'),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知权限'),
            subtitle: Text(
              model.permissions['notifications'] == true
                  ? '已开启'
                  : '提醒不可用 · 点击设置',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                act(() => model.repository.requestPermission('notifications')),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.vibration),
            title: const Text('任务振动提醒'),
            subtitle: Text(
              model.permissions['vibratorAvailable'] == false
                  ? '当前设备不支持振动'
                  : model.permissions['notifications'] != true
                  ? '请先开启通知权限'
                  : model.permissions['vibrationEnabled'] == true
                  ? '已开启 · 到点随通知振动'
                  : '未开启或通知已静音 · 点击设置',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                act(() => model.repository.requestPermission('vibration')),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('日程强提醒'),
            subtitle: Text(
              model.permissions['vibratorAvailable'] == false
                  ? '当前设备不支持振动'
                  : model.permissions['strongNotifications'] != true
                  ? '通知类别已关闭 · 点击设置'
                  : model.permissions['strongHeadsUp'] == false
                  ? '通知重要性不足 · 请开启悬浮通知以支持锁屏弹出'
                  : model.permissions['strongVibrationEnabled'] == true
                  ? '已开启 · 最多持续强振动 60 秒'
                  : '振动已关闭或类别已静音 · 点击设置',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => act(
              () => model.repository.requestPermission('strongVibration'),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('锁屏弹出提醒'),
            subtitle: Text(fullScreenStatus),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                act(() => model.repository.requestPermission('fullScreen')),
          ),
          const Divider(height: 1),
          if (model.permissions['vivoDevice'] == true) ...[
            ListTile(
              leading: const Icon(Icons.settings_applications_outlined),
              title: const Text('vivo 后台弹出界面'),
              subtitle: const Text(
                '点击进入应用信息，在权限中允许“后台弹出界面”（若有）；'
                '也可在系统设置搜索该名称。通知中开启锁屏显示、悬浮通知；'
                '若到点完全无提醒，再检查自启动与后台耗电管理。系统版本不同，入口名称可能不同。',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => act(
                () => model.repository.requestPermission('backgroundPopup'),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('vivo 锁屏后台运行'),
              subtitle: const Text(
                '锁屏后没有通知或振动？请在系统设置中允许 TimeFlow 自启动，'
                '并在“电池 → 后台耗电管理”中允许后台运行。'
                '点击可检查系统电池优化；vivo 专属限制仍需手动检查。',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => act(
                () => model.repository.requestPermission('backgroundPower'),
              ),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('准时提醒'),
            subtitle: Text(
              model.permissions['exact'] == true ? '已开启' : '可能延迟 · 点击开启权限',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => act(() => model.repository.requestPermission('exact')),
          ),
        ],
      ),
    ),
    const SizedBox(height: 10),
    Text(
      '开启提醒的日程会在锁屏时请求弹出提醒页，并以 800 毫秒振动、200 毫秒间隔持续最多 60 秒；关闭或稍后提醒会立即停止。任务仍使用普通通知。提前提醒及延后提醒同样适用，实际效果受系统通知、振动、勿扰和厂商后台设置控制。强行停止应用后，请重新打开以恢复未来提醒。',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    heading('外观'),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          initialValue: model.snapshot.settings['theme'] ?? 'system',
          decoration: const InputDecoration(labelText: '主题'),
          items: const [
            DropdownMenuItem(value: 'system', child: Text('跟随系统')),
            DropdownMenuItem(value: 'light', child: Text('浅色')),
            DropdownMenuItem(value: 'dark', child: Text('深色')),
          ],
          onChanged: (v) => act(() => model.setSetting('theme', v)),
        ),
      ),
    ),
    heading('分类'),
    Card(
      child: Column(
        children: [
          for (final c in model.snapshot.categories)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(c),
              onTap: () => categoryDialog(c),
              trailing: model.snapshot.categories.length > 1
                  ? IconButton(
                      tooltip: '删除分类并合并事项',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final replacement = model.snapshot.categories
                            .firstWhere((x) => x != c);
                        if (await confirm(
                          '删除分类',
                          '「$c」中的事项将合并至「$replacement」。',
                        )) {
                          await act(() => model.renameCategory(c, replacement));
                        }
                      },
                    )
                  : null,
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新增分类'),
            onTap: () => categoryDialog(),
          ),
        ],
      ),
    ),
    heading('数据备份'),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('保存到自己选择的位置'),
            onTap: () => act(model.export),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('恢复备份'),
            subtitle: const Text('先校验文件，再确认覆盖'),
            onTap: () => act(() async {
              final data = await model.pickImport();
              if (data != null &&
                  await confirm(
                    '覆盖本机数据',
                    '备份包含 ${data.entries.length} 个任务或日程。恢复会替换当前记录，建议先导出当前数据。',
                  )) {
                await model.restore(data);
              }
            }),
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    Text(
      '备份文件为明文 JSON，请保存在可信位置。TimeFlow 不上传你的任务与日程。',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 32),
    Center(
      child: Text(
        'TimeFlow  ·  1.0.0\n把时间，留给重要的事。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Icon(
            Icons.timelapse_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 9),
          const Flexible(
            child: Text(
              'TimeFlow',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: model.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: model.loading
        ? const Center(child: CircularProgressIndicator())
        : model.error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(model.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: model.refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          )
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: RefreshIndicator(
                onRefresh: model.refresh,
                child: ListView(
                  key: ValueKey(index),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 110),
                  children: switch (index) {
                    0 => today(),
                    1 => plan(),
                    2 => review(),
                    _ => settings(),
                  },
                ),
              ),
            ),
          ),
    floatingActionButton: index == 3
        ? null
        : FloatingActionButton.extended(
            onPressed: model.busy ? null : () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('新建'),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (v) => setState(() {
        index = v;
        visible = 50;
        selected = day(DateTime.now());
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.wb_sunny_outlined),
          selectedIcon: Icon(Icons.wb_sunny),
          label: '今天',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: '计划',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: '回顾',
        ),
        NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
      ],
    ),
  );
}
