# TimeFlow

离线优先的中文个人时间管理 App。Flutter 界面 + Kotlin 安卓适配层 + SQLite，最低 Android 8.0（API 26）。无需账号，不上传任务或日程。

用户可参阅 [用户操作说明](docs/用户操作说明.md)，了解权限授权和日程制定步骤。

## 已实现

- 今天：任务进度、下一项日程、时间轴、待办、逾期事项与顺延。
- 计划：月历、选中日期事项、无日期任务收纳。
- 任务与日程：标题、备注、分类、优先级、跨天日程、冲突提示、完成与撤销。
- 每日／工作日／指定星期重复，结束日期，单次例外及“本次及以后”编辑、删除。
- 安卓本地提醒：任务普通通知；日程锁屏弹出、最多 60 秒强振动、关闭／延后 10 分钟，以及重启和时区变更恢复。
- 每日回顾与七天任务完成统计；日程不计入任务完成率。
- 系统／浅色／深色主题、分类合并、系统文件选择器导出及校验后恢复 JSON 备份。

## 日程锁屏与强振动提醒

所有开启提醒的日程（包括提前提醒和“稍后提醒”）使用独立的原生强提醒：锁屏时请求点亮屏幕并显示日程提醒页，以 800 ms 振动、200 ms 间隔持续最多 60 秒，不播放铃声。点击“关闭”只结束本次提醒，不把日程标记为完成；点击“稍后提醒”会立即停振，并在 10 分钟后以新代次再次提醒。60 秒无人处理时页面自动收起，同时保留一条未处理通知。

全屏日程通知与前台服务的低重要性“提醒运行状态”通知分开发送。每个新批次只发布一次新的全屏通知，同批次更新不会再次唤醒；关闭、稍后、删除与超时同步清除弹窗通知。提醒页声明锁屏显示与亮屏，并在页面复用时更新当前批次。此链路仍遵守系统全屏通知与厂商后台弹出权限。

新建事项的提醒默认选择“到点提醒”。任务若没有设置具体时间，保存时不会创建提醒；已有事项在编辑时继续保留原来的提醒选择。

新建页面默认选择“日程”，开始时间取当前时间之后的下一个 15 分钟整点，结束时间默认晚一小时；从计划页选择其他日期新建时默认使用当天 09:00～10:00。

多个日程在同一次强提醒期间到达时会合并显示，“全部关闭／全部稍后提醒”统一处理，原有 60 秒截止时间不会延长。任务仍使用普通通知，可从通知标记完成或稍后提醒，不加入日程批次。

在 **设置 → 日程强提醒、锁屏弹出提醒、准时提醒** 检查系统状态。Android 14 及以上可能需要单独允许全屏提醒；没有权限时仍保留通知，但不能保证锁屏页面自动弹出。勿扰、系统振动强度、通知类别和厂商后台策略仍会影响实际效果，需在真机上确认。

vivo S9 / OriginOS 3 若“亮屏正常，锁屏后无通知、无振动”，还需检查厂商后台限制：在系统 **设置 → 应用与权限 → 权限管理 → 自启动** 允许 TimeFlow，在 **设置 → 电池 → 后台耗电管理** 允许后台运行／后台高耗电。参考 [vivo 官方后台设置说明](https://kefu.vivo.com.cn/robot/imgmsgData/2616a9cd7cd64a5083a264d16e5767da/index_1.html)。App 设置新增“vivo 锁屏后台运行”入口，打开系统电池优化列表；它不能读取或代替 vivo 专属授权。

“锁屏弹出提醒”在 Android 14+ 打开全屏提醒特殊权限设置；较早系统打开“日程强提醒”通知类别，检查锁屏显示与悬浮通知，不会出现独立的全屏权限申请弹框。系统入口不可用时逐级回退至通知设置、应用信息。vivo / iQOO 另有“vivo 后台弹出界面”入口，进入应用信息后检查权限，或在系统设置搜索“后台弹出界面”。厂商权限无法可靠读取，不再笼统显示“已允许”。完成设置后重新打开 App，新建两分钟后的**日程**并锁屏测试；无具体时间任务不会提醒。


日程到点使用 Android 的用户可见闹钟调度；获得“准时提醒”权限后，系统不会因 Doze 调整触发时间。首页会显示当前缺少的第一项提醒权限，点击可直接进入对应系统授权页。此次升级使用修正后的“日程强提醒”通知类别，默认高重要度、开启振动且无铃声，用于修复旧类别已经静音或重要度过低时无法由应用更新的问题。

## Mac 一键演示（无需编译）

在 Finder 中双击根目录的 **`演示TimeFlow.command`**，或在终端运行：

```sh
./演示TimeFlow.command
```

脚本自动定位项目目录，使用 `artifacts/TimeFlow-1.0.0-test.apk` 和已有的 `Medium_Phone_API_36.1` 模拟器。默认 SDK 路径为 `~/Library/Android/sdk`，也读取 `ANDROID_SDK_ROOT` / `ANDROID_HOME`。

- 有可见窗口时直接复用；目标模拟器无窗口运行时，只重启该实例并打开窗口。
- 保留模拟器原有 CPU / 内存配置，关闭音频和退出时保存快照；不下载依赖、不启动 Android Studio、不重新编译。
- 等待安卓启动最多 180 秒，再覆盖安装并打开 App；不会卸载应用或清空已有数据。
- 中文显示进度；日志位于 `build/timeflow-demo/`。双击运行时按回车结束脚本，模拟器继续运行；关闭模拟器窗口即可结束演示。
- 同时重复运行会被阻止；启动失败时查看日志，其他手机和模拟器不会被操作。

可选覆盖配置（一般不需要）：

```sh
TIMEFLOW_ANDROID_SDK="/path/to/android-sdk" \
TIMEFLOW_AVD="Your_AVD_Name" \
TIMEFLOW_APK="/absolute/path/to/TimeFlow.apk" \
./演示TimeFlow.command
```

首次演示建议在 App 设置中开启通知、日程强提醒、锁屏弹出提醒和准时提醒，再新建两分钟后的日程。模拟器可验证调度和页面链路，无法验证真实振动手感。若 macOS 阻止双击执行，可使用上述终端命令运行；无需修改系统安全设置。

## 真机调试：一键打包 APK

双击根目录 **`打包APK.command`**，默认构建 Debug 通用安装包；也可在终端运行：

```sh
./打包APK.command                 # Debug：便于真机调试
./打包APK.command --release       # Release：体积更小，用于体验与性能测试
```

输出分别为 `artifacts/TimeFlow-debug.apk` 和 `artifacts/TimeFlow-release.apk`，各附带 `.sha256` 校验文件。两种包目前都使用开发测试签名。脚本不启动模拟器、不自动安装到手机；构建失败不会替换旧安装包，成功后会打印 USB 安装命令。

Flutter 优先使用 `TIMEFLOW_FLUTTER` 指定的可执行文件，其次使用 PATH，再读取 `android/local.properties` 中的 SDK 路径。本机已有的临时 Flutter SDK 可直接使用；若已被清理，需重新安装 `.flutter-version` 指定版本。Android SDK 支持 `TIMEFLOW_ANDROID_SDK`、`ANDROID_SDK_ROOT`、`ANDROID_HOME` 或 `android/local.properties`。需要 JDK 17；首次构建可能联网下载依赖。

```sh
# 如果 Flutter 没有加入 PATH，可显式指定
TIMEFLOW_FLUTTER="/path/to/flutter/bin/flutter" ./打包APK.command

# 手机连接 USB、开启 USB 调试并允许电脑后
"$HOME/Library/Android/sdk/platform-tools/adb" devices -l
"$HOME/Library/Android/sdk/platform-tools/adb" -s 手机序列号 install -r \
  artifacts/TimeFlow-debug.apk
```

请用实际手机序列号替换占位符，避免选中模拟器。`install -r` 保留已有应用数据；签名不一致时安装会失败，请先备份，不要直接卸载。打包日志位于 `build/timeflow-package/`；请勿在打包期间同时运行其他 Flutter 构建或测试。

演示脚本默认使用已同步更新的 `TimeFlow-1.0.0-test.apk`。若要临时演示 Debug 包，可运行：

```sh
TIMEFLOW_APK="$PWD/artifacts/TimeFlow-debug.apk" ./演示TimeFlow.command
```

## 构建与运行

验证使用 Flutter **3.47.5**、Dart **3.13.4**、Java **17**。Flutter 版本记录在 `.flutter-version`；Dart 依赖锁定在 `pubspec.lock`，Gradle wrapper 及安卓插件版本随工程提交。

```sh
flutter pub get
flutter analyze
flutter test test
flutter run -d <android-device-id>
flutter build apk --release
```

本次环境的 Flutter SDK 在 `/private/tmp/timeflow-flutter`，属于临时安装。后续建议自行将同版本 SDK 安装到持久目录，并加入 PATH。Android SDK、Flutter SDK 的本机路径由忽略提交的 `android/local.properties` 保存。

Release 构建当前使用 **开发测试签名**，仅供内部安装试用，不作为商店正式发布包。正式发布需替换为团队管理的签名密钥。默认新安装不注入示例数据，截图中的事项来自隔离模拟器测试。

## 测试

```sh
# 领域规则、备份、ViewModel、界面及小屏大字体
flutter test test

# 仅在可清空的模拟器运行：会清空并写入测试数据
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d <emulator-id>

# 原生 SQLite / AlarmManager / 通知动作测试，仅在模拟器运行
cd android
./gradlew :app:connectedDebugAndroidTest -Ptarget="$PWD/../lib/main.dart"
```

集成截图输出到 `docs/screenshots/`，数据往返测量输出到 `build/integration_response_data.json`。实际验证结果和未完成的设备验收见 [测试记录](docs/TESTING.md)。

## 架构

- `lib/domain`：任务/日程判别模型、日历规则、实例、备份校验。日期保存为本地 `YYYY-MM-DD` 和分钟数，不写入 UTC 偏移。
- `lib/data`：AppModel 驱动界面，Repository 隔离平台调用。SQL 不进入页面。新增 iOS 时实现 Repository 和原生提醒适配，不复用安卓 API。
- `lib/ui`：四个主页面与事项编辑器，列表每批展示 50 项。
- `android/app/src/main/kotlin/app/timeflow/timeflow`：SQLite 事务、系统文件选择器、日历规则、AlarmManager、通知、强提醒前台服务、锁屏页面和恢复接收器。

SQLite v1 使用 `entries`、`exceptions`、`completions`、`settings`、`reminders` 五张表，稳定主键和 JSON 行。备份包含前四张表，提醒配置在事项中；待触发的系统闹钟从数据重建，临时延后状态不跨备份恢复。未来升级必须添加非破坏性数据库迁移。

重复实例键为 `seriesId@YYYY-MM-DD`；单次事项使用自身 ID。单次改期保留实例键；拆分后续重复时保留旧系列截止日前的历史。补做只更新原计划日期的统计，明确改期则归属新的计划日期。

提醒日志保存代次 token、事项指纹、强提醒活动状态和单调时钟截止时间。修改、删除或完成时取消旧代次；重复操作、旧通知按钮及过期广播不会二次处理。日程强提醒由原生前台服务控制，不等待 Flutter 启动；进程终止或重启后不会重新播放已开始的振动，只恢复未来及已保存的稍后提醒。

## 边界

- iOS 仅保留接口边界，未提供可发布的 iOS 工程。
- 通知提醒遵从系统权限、通知渠道、勿扰及厂商后台策略；没有权限时会展示不可用或可能延迟。
- 强行停止 App 会受安卓系统限制，重新打开后恢复未来提醒。错过的已登记提醒在首页汇总，不补发。
- 支持 2000–2100 年日期范围，跨天日程最多 365 天；备份导入上限 32 MB。
- 首版全量载入本地记录，列表分批显示；超大规模多年重复历史仍需进一步性能评估。
- 无云同步、自动系统日历同步、番茄钟、打卡或小组件。

## 隐私

Release 清单不声明网络权限，也不使用广告或分析 SDK。关闭安卓自动应用数据备份。手动备份为明文 JSON，保存位置由用户选择。卸载 App 会删除本机数据，请提前导出需要保留的记录。
