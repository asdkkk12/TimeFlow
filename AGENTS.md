# TimeFlow 项目指引

这是一个离线优先的中文时间管理 App。当前只交付 Android，技术栈为 Flutter/Dart + Kotlin + SQLite；最低 Android 8.0（API 26）。没有服务端、登录、网络权限、广告或分析 SDK。

## 先按任务定位文件

- `lib/domain/models.dart`：`Entry`、重复规则、实例展开、校验、备份数据模型。日期是设备本地日期；时间保存为当天分钟数。
- `lib/data/app_model.dart`：页面业务操作、重复事项拆分、Repository 调用。
- `lib/data/repository.dart`：Flutter 与原生平台通道 `app.timeflow/native`。
- `lib/ui/home.dart`：今天、计划、回顾、设置四页及权限引导。
- `lib/ui/editor.dart`：新建/编辑事项。新建默认日程、下一个 15 分钟整点、时长一小时、到点提醒；其他日期默认 09:00～10:00。
- `android/app/src/main/kotlin/app/timeflow/timeflow/Store.kt`：SQLite JSON 行存储和事务。
- `OccurrenceRules.kt`：原生日历实例、提醒时间和事项指纹。
- `Reminders.kt`：AlarmManager 调度、token 幂等、重复事项续接、通知动作和重建。
- `AlarmSession.kt`：活动强提醒批次及 60 秒单调时钟截止时间。
- `AlarmService.kt`：前台服务、唤醒锁和有限强振动波形。
- `AlarmNotifications.kt`：全屏 Intent、强提醒/未处理通知类别及按钮。
- `AlarmActivity.kt`：锁屏提醒原生页面。
- `MainActivity.kt`：Flutter 平台接口、权限设置入口、备份文件选择器。
- `android/app/src/main/AndroidManifest.xml`：安卓组件和权限。
- `test/`：Dart、领域及 Widget 测试；`android/app/src/androidTest/`：SQLite、AlarmManager、锁屏与通知测试。
- `docs/TESTING.md`：最近验证结果与尚待真机验收项；`README.md`：用户操作、构建和架构说明。

只读取与当前任务相关的文件。不要遍历 `build/`、`.dart_tool/`、IDE 文件或 APK，除非任务明确需要构建产物或日志。

## 不可破坏的产品规则

- 任务和日程分开建模、合并展示；日程不计入任务完成率，也没有“完成”动作。
- 无具体时间的任务不安排提醒。日程默认到点提醒。
- 重复事项支持每日、工作日、每周；仅本次用 `exceptions`，完成历史用 `completions`。
- 提醒用稳定实例 ID、事项指纹和代次 token；旧广播和旧按钮必须失效。
- 日程使用用户可见精确闹钟。获得精确权限时用 `setAlarmClock`；无权限才降级为非精确调度，并在界面明确提示。
- 日程强提醒通知类别是 `timeflow_event_alarms_v2`：高重要度、振动、无铃声。Android 通知类别创建后行为不可由 App 修改，不要复用旧错误类别。
- 日程触发后最多强振动 60 秒（800 ms 振动/200 ms 间隔）；关闭只结束本次，稍后提醒为 10 分钟并生成新 token。
- 同期日程加入当前批次，不延长截止时间；任务通知不进入批次。
- 锁屏弹出依赖高优先级全屏通知；Android 14+ 必须检查并引导 `USE_FULL_SCREEN_INTENT`。不得用悬浮窗绕过系统。
- 删除、改期、恢复备份或取消提醒时，必须同步取消系统闹钟、活动振动和旧通知。
- 进程终止或重启后不重新播放已经开始的强提醒；只恢复未来提醒及已保存的稍后提醒。
- SQLite 当前为 v1：`entries`、`exceptions`、`completions`、`settings`、`reminders`。备份不包含 `reminders`；改变格式必须考虑兼容与迁移。

## 验证与构建

本机参考环境记录在 `.flutter-version`、`android/local.properties` 和 `docs/TESTING.md`。临时 Flutter 通常位于 `/private/tmp/timeflow-flutter/bin/flutter`，Java 使用 JDK 17。

常规改动按影响范围运行：

```sh
/private/tmp/timeflow-flutter/bin/flutter analyze
/private/tmp/timeflow-flutter/bin/flutter test test
```

安卓提醒、SQLite、Manifest 或 Kotlin 改动还要在隔离模拟器运行：

```sh
cd android
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home \
  ./gradlew :app:connectedDebugAndroidTest -Ptarget="$PWD/../lib/main.dart"
```

原生测试会清空测试安装的数据并操作锁屏，只能对确认过的模拟器运行。执行 ADB 命令前先看 `adb devices -l`，不要自动选择或清空用户真机。模拟器不能验证真实振动强度和厂商后台策略。

不要并行运行 Flutter 测试、Flutter 构建和 Gradle APK 构建；它们可能同时改写插件注册产物。最终 APK 用现有脚本顺序生成：

```sh
TIMEFLOW_FLUTTER=/private/tmp/timeflow-flutter/bin/flutter ./打包APK.command --debug
TIMEFLOW_FLUTTER=/private/tmp/timeflow-flutter/bin/flutter ./打包APK.command --release
```

输出位于 `artifacts/TimeFlow-debug.apk` 和 `artifacts/TimeFlow-release.apk`。发布前同步 Release 到 `artifacts/TimeFlow-1.0.0-test.apk`，更新 SHA-256，并用 Android `apksigner` 校验。当前 Release 仍使用测试签名。

## 文档维护

行为、权限、测试覆盖或安装包发生变化时，同步更新 `README.md` 和 `docs/TESTING.md`。不要把临时绝对路径、构建日志清单或容易过期的测试数量复制到本文件；以对应配置和测试记录为准。
