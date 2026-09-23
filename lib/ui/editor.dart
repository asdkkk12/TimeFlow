import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';

String clockText(int? minute) => minute == null
    ? '全天'
    : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
const repeatNames = ['不重复', '每天', '工作日', '每周'];

DateTime defaultEventStart(DateTime selected) {
  final selectedDay = day(selected);
  final now = DateTime.now();
  if (dayKey(selectedDay) != dayKey(now)) {
    return selectedDay.add(const Duration(hours: 9));
  }
  final nextQuarter = ((now.minute ~/ 15) + 1) * 15;
  return DateTime(now.year, now.month, now.day, now.hour, nextQuarter);
}

class EntryEditor extends StatefulWidget {
  final Entry? initial;
  final DateTime date;
  final List<String> categories;
  final bool single;
  const EntryEditor({
    super.key,
    this.initial,
    required this.date,
    required this.categories,
    this.single = false,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late final TextEditingController title, notes;
  late EntryKind kind;
  late DateTime? date, until;
  late DateTime endDate;
  late int? minute, endMinute, reminder;
  late int priority;
  late Repeat repeat;
  late Set<int> weekdays;
  late String category;
  String? error;
  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    final suggested = defaultEventStart(widget.date);
    title = TextEditingController(text: e?.title ?? '');
    notes = TextEditingController(text: e?.notes ?? '');
    kind = e?.kind ?? EntryKind.event;
    date = e == null ? day(suggested) : e.date;
    until = e?.until;
    minute =
        e?.minute ??
        (e == null ? suggested.hour * 60 + suggested.minute : null);
    final suggestedEnd = suggested.add(const Duration(hours: 1));
    endDate = e == null
        ? day(suggestedEnd)
        : shiftDay(date ?? widget.date, e.endDays);
    endMinute =
        e?.endMinute ??
        (e == null ? suggestedEnd.hour * 60 + suggestedEnd.minute : null);
    // New items start with an at-time reminder; existing items retain their
    // saved choice, including an explicit "no reminder" value.
    reminder = e == null ? 0 : e.reminder;
    priority = e?.priority ?? 1;
    repeat = widget.single ? Repeat.none : e?.repeat ?? Repeat.none;
    weekdays = {...?e?.weekdays};
    category = e?.category ?? widget.categories.first;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime? initial) async {
    final value = initial ?? day(DateTime.now());
    var year = value.year;
    var month = value.month;
    var selectedDay = value.day;
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setPickerState) {
          final days = DateUtils.getDaysInMonth(year, month);
          if (selectedDay > days) selectedDay = days;
          Widget wheel({
            required int value,
            required int first,
            required int count,
            required ValueChanged<int> onChanged,
            required String Function(int) label,
          }) => Expanded(
            child: CupertinoPicker(
              itemExtent: 44,
              scrollController: FixedExtentScrollController(
                initialItem: value - first,
              ),
              onSelectedItemChanged: (index) => onChanged(index + first),
              selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
                background: Color(0x1A29B6E6),
              ),
              children: [
                for (var i = first; i < first + count; i++)
                  Center(
                    child: Text(label(i), style: const TextStyle(fontSize: 23)),
                  ),
              ],
            ),
          );
          return SafeArea(
            child: SizedBox(
              height: 310,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                    child: Row(
                      children: [
                        const Text(
                          '选择日期',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            DateTime(year, month, selectedDay),
                          ),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        wheel(
                          value: year,
                          first: 2000,
                          count: 101,
                          onChanged: (v) => setPickerState(() => year = v),
                          label: (v) => '$v 年',
                        ),
                        wheel(
                          value: month,
                          first: 1,
                          count: 12,
                          onChanged: (v) => setPickerState(() => month = v),
                          label: (v) => '$v 月',
                        ),
                        wheel(
                          value: selectedDay,
                          first: 1,
                          count: days,
                          onChanged: (v) =>
                              setPickerState(() => selectedDay = v),
                          label: (v) => '$v 日',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<int?> pickTime(int? current) async {
    final initial =
        current ?? TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    var hour = initial ~/ 60;
    var minute = initial % 60;
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setPickerState) {
          Widget wheel({
            required int value,
            required int count,
            required ValueChanged<int> onChanged,
            required String Function(int) label,
          }) => Expanded(
            child: CupertinoPicker(
              itemExtent: 44,
              scrollController: FixedExtentScrollController(initialItem: value),
              onSelectedItemChanged: onChanged,
              selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
                background: Color(0x1A29B6E6),
              ),
              children: [
                for (var i = 0; i < count; i++)
                  Center(
                    child: Text(label(i), style: const TextStyle(fontSize: 24)),
                  ),
              ],
            ),
          );
          return SafeArea(
            child: SizedBox(
              height: 310,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                    child: Row(
                      children: [
                        const Text(
                          '选择时间',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, hour * 60 + minute),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        wheel(
                          value: hour,
                          count: 24,
                          onChanged: (v) => setPickerState(() => hour = v),
                          label: (v) => '${v.toString().padLeft(2, '0')} 时',
                        ),
                        const Text(
                          ':',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        wheel(
                          value: minute,
                          count: 60,
                          onChanged: (v) => setPickerState(() => minute = v),
                          label: (v) => '${v.toString().padLeft(2, '0')} 分',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void submit() {
    final e = Entry(
      id: widget.initial?.id ?? newId(),
      title: title.text.trim(),
      notes: notes.text.trim(),
      category: category,
      kind: kind,
      date: date,
      minute: minute,
      endMinute: kind == EntryKind.event ? endMinute : null,
      endDays: kind == EntryKind.event && date != null
          ? DateTime.utc(endDate.year, endDate.month, endDate.day)
                .difference(DateTime.utc(date!.year, date!.month, date!.day))
                .inDays
          : 0,
      priority: priority,
      repeat: repeat,
      weekdays: weekdays.toList()..sort(),
      until: repeat == Repeat.none ? null : until,
      // An all-day task has no concrete instant to schedule. Keep the editor's
      // at-time default, but persist no reminder until a time is selected.
      reminder: minute == null ? null : reminder,
    );
    final issue = e.validate();
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    Navigator.pop(context, e);
  }

  Widget section(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.initial == null ? '安排一件事' : '编辑事项'),
      actions: [TextButton(onPressed: submit, child: const Text('保存'))],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            if (widget.initial == null)
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                    value: EntryKind.task,
                    icon: Icon(Icons.check_circle_outline),
                    label: Text('任务'),
                  ),
                  ButtonSegment(
                    value: EntryKind.event,
                    icon: Icon(Icons.event_outlined),
                    label: Text('日程'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setState(() {
                  kind = v.first;
                  if (kind == EntryKind.event) {
                    date ??= day(widget.date);
                    minute ??= 9 * 60;
                    endMinute ??= 10 * 60;
                    endDate = date!;
                    reminder = 0;
                  } else {
                    reminder = null;
                  }
                }),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: title,
              autofocus: widget.initial == null,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: const InputDecoration(
                hintText: '想要完成什么？',
                labelText: '标题',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notes,
              maxLines: 3,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '留一点细节给未来的自己',
                counterText: '',
              ),
            ),
            section('时间安排'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(date == null ? '待安排' : dayKey(date!)),
              subtitle: Text(kind == EntryKind.event ? '开始日期' : '计划日期'),
              trailing: kind == EntryKind.task
                  ? IconButton(
                      tooltip: '清除日期',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        date = null;
                        minute = null;
                        reminder = null;
                        repeat = Repeat.none;
                        until = null;
                      }),
                    )
                  : null,
              onTap: () async {
                final v = await pickDate(date);
                if (v != null) {
                  setState(() {
                    final delta = endDate.difference(date ?? v).inDays;
                    date = v;
                    endDate = shiftDay(v, delta < 0 ? 0 : delta);
                  });
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(clockText(minute)),
              subtitle: Text(kind == EntryKind.event ? '开始时间' : '截止时间（可选）'),
              trailing: kind == EntryKind.task
                  ? IconButton(
                      tooltip: '清除时间',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        minute = null;
                        reminder = null;
                      }),
                    )
                  : null,
              onTap: () async {
                final v = await pickTime(minute);
                if (v != null) {
                  setState(() {
                    date ??= day(widget.date);
                    minute = v;
                  });
                }
              },
            ),
            if (kind == EntryKind.event) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: Text(dayKey(endDate)),
                subtitle: const Text('结束日期'),
                onTap: () async {
                  final v = await pickDate(endDate);
                  if (v != null) setState(() => endDate = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(clockText(endMinute)),
                subtitle: const Text('结束时间'),
                onTap: () async {
                  final v = await pickTime(endMinute);
                  if (v != null) setState(() => endMinute = v);
                },
              ),
            ],
            section('提醒与重复'),
            DropdownButtonFormField<int>(
              initialValue: reminder ?? -1,
              decoration: const InputDecoration(labelText: '提醒'),
              items: const [
                DropdownMenuItem(value: -1, child: Text('不提醒')),
                DropdownMenuItem(value: 0, child: Text('到点提醒')),
                DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
                DropdownMenuItem(value: 60, child: Text('提前 60 分钟')),
              ],
              onChanged: (v) => setState(() => reminder = v == -1 ? null : v),
            ),
            if (!widget.single) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<Repeat>(
                initialValue: repeat,
                decoration: const InputDecoration(labelText: '重复频率'),
                items: Repeat.values
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(repeatNames[r.index]),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  repeat = v!;
                  if (repeat != Repeat.none) date ??= day(widget.date);
                }),
              ),
              if (repeat == Repeat.weekly)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    children: List.generate(
                      7,
                      (i) => FilterChip(
                        label: Text('周${'一二三四五六日'[i]}'),
                        selected: weekdays.contains(i + 1),
                        onSelected: (yes) => setState(() {
                          yes ? weekdays.add(i + 1) : weekdays.remove(i + 1);
                        }),
                      ),
                    ),
                  ),
                ),
              if (repeat != Repeat.none)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(until == null ? '持续重复' : '重复至 ${dayKey(until!)}'),
                  trailing: until == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: '取消结束日期',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => until = null),
                        ),
                  onTap: () async {
                    final v = await pickDate(until ?? date);
                    if (v != null) setState(() => until = v);
                  },
                ),
            ],
            section('整理'),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '分类'),
              items: {
                ...widget.categories,
                category,
              }.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            if (kind == EntryKind.task) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  3,
                  (i) => ChoiceChip(
                    label: Text(['低优先级', '普通', '高优先级'][i]),
                    selected: priority == i,
                    onSelected: (_) => setState(() => priority = i),
                  ),
                ),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('保存安排'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
