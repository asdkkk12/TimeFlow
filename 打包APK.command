#!/bin/bash
# macOS Bash 3.2; build only, never install or erase device data.
set -u
set -o pipefail

usage() {
  printf '%s\n' \
    'TimeFlow APK 打包' \
    '用法：./打包APK.command [--debug | --release]' \
    '默认：Debug 通用 APK，适合真机调试。' \
    '--release：体积更小、接近实际性能的 Release 测试包（当前仍用测试签名）。' \
    '可选环境变量：TIMEFLOW_FLUTTER（flutter 可执行文件路径）、TIMEFLOW_ANDROID_SDK（安卓 SDK 目录）。'
}
MODE=debug
if [ "$#" -gt 1 ]; then usage; exit 2; fi
case "${1:-}" in
  ''|--debug) ;;
  --release) MODE=release ;;
  --help|-h) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${PROJECT_DIR}" || exit 1
LOG_DIR="${PROJECT_DIR}/build/timeflow-package"
LOCK_DIR="${LOG_DIR}/run.lock"
LOCKED=0
STAGING=''
mkdir -p "${LOG_DIR}" || { echo '无法创建打包日志目录。'; exit 1; }
LOG_FILE="${LOG_DIR}/package-$(date +%Y%m%d-%H%M%S)-$$.log"
: > "${LOG_FILE}"
say() { printf '%s\n' "$*" | tee -a "${LOG_FILE}"; }
fail() { say "错误：$*"; exit 1; }
finish() {
  local result=$?
  trap - EXIT
  if [ -n "${STAGING}" ]; then
    rm -f "${STAGING}/TimeFlow-${MODE}.apk" "${STAGING}/TimeFlow-${MODE}.apk.sha256"
    rmdir "${STAGING}" 2>/dev/null || true
  fi
  if [ "${LOCKED}" = 1 ] && [ "$(cat "${LOCK_DIR}/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "${LOCK_DIR}/pid"
    rmdir "${LOCK_DIR}" 2>/dev/null || true
  fi
  printf '\n打包日志：%s\n' "${LOG_FILE}"
  if [ -t 0 ] && [ -t 1 ]; then
    printf '按回车关闭脚本。'
    read -r _reply || true
  fi
  exit "${result}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

property() {
  [ -f android/local.properties ] || return 0
  # Generated SDK paths in local.properties may contain escaped spaces/colons.
  sed -n "s/^$1=//p" android/local.properties | head -n 1 | sed 's/\\ / /g; s/\\:/:/g' | tr -d '\r'
}

say "TimeFlow · APK 打包（${MODE}）"
[ "$(uname -s)" = Darwin ] || fail '此双击脚本适用于 macOS。'
[ -f pubspec.yaml ] && [ -f lib/main.dart ] || fail '找不到项目入口，请将脚本放在 TimeFlow 项目根目录。'

FLUTTER_BIN="${TIMEFLOW_FLUTTER:-}"
if [ -z "${FLUTTER_BIN}" ]; then FLUTTER_BIN="$(command -v flutter || true)"; fi
if [ -z "${FLUTTER_BIN}" ]; then
  flutter_sdk="$(property 'flutter\.sdk')"
  [ -z "${flutter_sdk}" ] || FLUTTER_BIN="${flutter_sdk}/bin/flutter"
fi
[ -n "${FLUTTER_BIN}" ] && [ -x "${FLUTTER_BIN}" ] || fail '找不到 Flutter。请安装 .flutter-version 指定版本并加入 PATH，或设置 TIMEFLOW_FLUTTER 为其 bin/flutter 路径。本机临时 SDK 可能已被清理。'

SDK_DIR="${TIMEFLOW_ANDROID_SDK:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}}"
if [ -z "${SDK_DIR}" ]; then SDK_DIR="$(property 'sdk\.dir')"; fi
SDK_DIR="${SDK_DIR:-${HOME}/Library/Android/sdk}"
[ -d "${SDK_DIR}/platforms" ] && [ -d "${SDK_DIR}/build-tools" ] || fail "安卓 SDK 不完整：${SDK_DIR}。请先安装 SDK 或设置 TIMEFLOW_ANDROID_SDK。"
export ANDROID_HOME="${SDK_DIR}"
export ANDROID_SDK_ROOT="${SDK_DIR}"
if [ -z "${JAVA_HOME:-}" ]; then
  java_home="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  [ -z "${java_home}" ] || export JAVA_HOME="${java_home}"
fi
JAVA_BIN="${JAVA_HOME:+${JAVA_HOME}/bin/}java"
"${JAVA_BIN}" -version >> "${LOG_FILE}" 2>&1 || fail 'Java 不可用，请配置 JDK 17 的 JAVA_HOME。'

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  lock_pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  case "${lock_pid}" in
    ''|*[!0-9]*) fail '另一个打包脚本正在初始化，请稍后重试。若确认没有运行中的脚本，可删除 build/timeflow-package/run.lock。' ;;
  esac
  if kill -0 "${lock_pid}" 2>/dev/null; then fail '已经有打包脚本在运行，请等待完成。'; fi
  rm -f "${LOCK_DIR}/pid"
  rmdir "${LOCK_DIR}" 2>/dev/null || fail '无法清理旧打包锁。'
  mkdir "${LOCK_DIR}" 2>/dev/null || fail '另一个打包脚本已开始运行。'
fi
LOCKED=1
printf '%s\n' "$$" > "${LOCK_DIR}/pid" || fail '无法写入打包锁。'

say "Flutter：${FLUTTER_BIN}"
say "Android SDK：${SDK_DIR}"
say '正在构建；首次构建可能需要联网下载依赖，请等待。'
say '为避免插件注册文件冲突，请勿同时运行其他 Flutter 构建或测试。'
# Explicit target prevents accidentally packaging integration-test entrypoints.
if ! "${FLUTTER_BIN}" build apk "--${MODE}" --target=lib/main.dart 2>&1 | tee -a "${LOG_FILE}"; then
  fail '构建失败，未更新 artifacts 中的安装包（若有旧包，它仍是旧版本）。请查看日志中的具体错误。'
fi
BUILT_APK="${PROJECT_DIR}/build/app/outputs/flutter-apk/app-${MODE}.apk"
[ -s "${BUILT_APK}" ] || fail '构建未生成有效 APK，请查看日志。'
mkdir -p artifacts || fail '无法创建安装包输出目录。'
STAGING="$(mktemp -d "${PROJECT_DIR}/artifacts/.package.XXXXXX")" || fail '无法创建临时输出目录。'
APK_NAME="TimeFlow-${MODE}.apk"
cp "${BUILT_APK}" "${STAGING}/${APK_NAME}" || fail '复制安装包失败。'
(cd "${STAGING}" && shasum -a 256 "${APK_NAME}" > "${APK_NAME}.sha256") || fail '无法计算安装包校验值。'
mv -f "${STAGING}/${APK_NAME}" "artifacts/${APK_NAME}" || fail '无法更新安装包。'
mv -f "${STAGING}/${APK_NAME}.sha256" "artifacts/${APK_NAME}.sha256" || fail '无法更新校验文件。'

say ''
say '打包成功！'
say "安装包：${PROJECT_DIR}/artifacts/${APK_NAME}"
say "校验文件：${PROJECT_DIR}/artifacts/${APK_NAME}.sha256"
say '此包支持 Android 8.0 及以上，使用开发测试签名。'
say '手机开启 USB 调试并授权电脑后，可执行以下命令（替换 手机序列号）：'
printf '  %q devices -l\n' "${SDK_DIR}/platform-tools/adb" | tee -a "${LOG_FILE}"
printf '  %q -s 手机序列号 install -r %q\n' "${SDK_DIR}/platform-tools/adb" "${PROJECT_DIR}/artifacts/${APK_NAME}" | tee -a "${LOG_FILE}"
say '也可以将 APK 传到手机手动安装。本脚本不会自动连接或安装到手机。'
