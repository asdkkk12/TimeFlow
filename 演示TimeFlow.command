#!/bin/bash
# Compatible with the Bash 3.2 shipped with macOS. No Flutter/build step needed.
set -u
set -o pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
SDK_DIR="${TIMEFLOW_ANDROID_SDK:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME}/Library/Android/sdk}}}"
AVD_NAME="${TIMEFLOW_AVD:-Medium_Phone_API_36.1}"
APK_PATH="${TIMEFLOW_APK:-${PROJECT_DIR}/artifacts/TimeFlow-1.0.0-test.apk}"
ADB="${SDK_DIR}/platform-tools/adb"
EMULATOR="${SDK_DIR}/emulator/emulator"
LOG_DIR="${PROJECT_DIR}/build/timeflow-demo"
LOCK_DIR="${LOG_DIR}/run.lock"
LOCKED=0
mkdir -p "${LOG_DIR}" || { echo '无法创建日志目录，请检查项目目录写入权限。'; exit 1; }
LOG_FILE="${LOG_DIR}/demo-$(date +%Y%m%d-%H%M%S)-$$.log"
: > "${LOG_FILE}"

say() { printf '%s\n' "$*" | tee -a "${LOG_FILE}"; }
fail() { say "错误：$*"; exit 1; }
finish() {
  local result=$?
  trap - EXIT
  if [ "${LOCKED}" = 1 ] && [ "$(cat "${LOCK_DIR}/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "${LOCK_DIR}/pid"
    rmdir "${LOCK_DIR}" 2>/dev/null || true
  fi
  printf '\n运行日志：%s\n' "${LOG_FILE}"
  if [ -t 0 ] && [ -t 1 ]; then
    printf '按回车退出脚本；已启动的模拟器会继续运行。'
    read -r _reply || true
  fi
  exit "${result}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Bound external commands too: adb wait-for-device alone can wait indefinitely.
# Combined output is retained in the log and returned to the caller.
bounded() {
  local seconds="$1" output pid end status
  shift
  output="$(mktemp "${LOG_DIR}/command.XXXXXX")" || return 1
  "$@" > "${output}" 2>&1 &
  pid=$!
  end=$((SECONDS + seconds))
  while kill -0 "${pid}" 2>/dev/null; do
    if [ "${SECONDS}" -ge "${end}" ]; then
      kill "${pid}" 2>/dev/null || true
      sleep 0.2
      kill -KILL "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      cat "${output}" >> "${LOG_FILE}"
      cat "${output}"
      rm -f "${output}"
      return 124
    fi
    sleep 0.2
  done
  wait "${pid}"
  status=$?
  cat "${output}" >> "${LOG_FILE}"
  cat "${output}"
  rm -f "${output}"
  return "${status}"
}

say 'TimeFlow · Mac 一键演示'
[ "$(uname -s)" = Darwin ] || fail '此脚本适用于 macOS。'
[ -r "${APK_PATH}" ] || fail "找不到可读的 APK：${APK_PATH}。请恢复安装包；脚本不会自动编译。"
[ -x "${ADB}" ] || fail "找不到 ADB：${ADB}。请检查 Android SDK 路径。"
[ -x "${EMULATOR}" ] || fail "找不到模拟器程序：${EMULATOR}。"
[ -x /usr/sbin/lsof ] || fail '找不到系统 lsof，无法安全识别已有模拟器。'

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  lock_pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  case "${lock_pid}" in
    ''|*[!0-9]*) fail '另一个演示脚本正在初始化。请稍后再试；若确认已退出，可删除 build/timeflow-demo/run.lock。' ;;
  esac
  if kill -0 "${lock_pid}" 2>/dev/null; then
    fail '演示脚本已经在运行，请等待它完成，不要重复双击。'
  fi
  # Only reclaim a lock with a recorded, no-longer-running owner.
  rm -f "${LOCK_DIR}/pid"
  rmdir "${LOCK_DIR}" 2>/dev/null || fail '旧运行锁无法清理。'
  mkdir "${LOCK_DIR}" 2>/dev/null || fail '另一个演示脚本已开始运行。'
fi
LOCKED=1
printf '%s\n' "$$" > "${LOCK_DIR}/pid" || fail '无法写入运行锁。'

avds="$(bounded 10 "${EMULATOR}" -list-avds)" || fail '无法读取模拟器列表，请检查日志。'
printf '%s\n' "${avds}" | tr -d '\r' | /usr/bin/grep -Fqx -- "${AVD_NAME}" || fail "未找到模拟器 ${AVD_NAME}。脚本不会自动下载系统镜像。"
bounded 15 "${ADB}" start-server >/dev/null || fail 'ADB 服务未能启动，请检查日志。'
say "正在查找模拟器：${AVD_NAME}"
devices="$(bounded 10 "${ADB}" devices)" || fail '无法读取设备列表。'
TARGET_SERIAL=''
while read -r serial state rest; do
  case "${serial}" in emulator-*) ;; *) continue ;; esac
  [ "${state}" = device ] || continue
  name="$(bounded 5 "${ADB}" -s "${serial}" emu avd name)" || continue
  name="$(printf '%s\n' "${name}" | tr -d '\r' | /usr/bin/head -n 1)"
  if [ "${name}" = "${AVD_NAME}" ]; then
    [ -z "${TARGET_SERIAL}" ] || fail "发现多个 ${AVD_NAME} 实例，请先关闭多余实例。"
    TARGET_SERIAL="${serial}"
  fi
done <<< "${devices}"

if [ -n "${TARGET_SERIAL}" ]; then
  port="${TARGET_SERIAL#emulator-}"
  pids="$(/usr/sbin/lsof -nP -t -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | sort -u)"
  identified=0
  headless=0
  for pid in ${pids}; do
    args="$(/bin/ps -p "${pid}" -o command= 2>/dev/null)"
    case "${args}" in *qemu-system*|*'/emulator '*) identified=1 ;; *) continue ;; esac
    case " ${args} " in *' -no-window '*) headless=1 ;; esac
  done
  [ "${identified}" = 1 ] || fail "无法识别 ${TARGET_SERIAL} 的窗口状态。为避免误关设备，未执行重启。请关闭该模拟器后重试。"
  if [ "${headless}" = 1 ]; then
    say "发现无窗口实例 ${TARGET_SERIAL}，正在切换为可见窗口（保留数据）……"
    bounded 10 "${ADB}" -s "${TARGET_SERIAL}" emu kill >/dev/null || fail '无法关闭目标无窗口模拟器。'
    deadline=$((SECONDS + 30))
    while /usr/sbin/lsof -nP -t -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; do
      [ "${SECONDS}" -lt "${deadline}" ] || fail '目标模拟器未能在 30 秒内退出，请检查日志后重试。'
      sleep 1
    done
    TARGET_SERIAL=''
  else
    say "复用已有窗口：${TARGET_SERIAL}"
  fi
fi

if [ -z "${TARGET_SERIAL}" ]; then
  # An offline/starting target may not answer adb yet. Do not start a second copy.
  processes="$(/bin/ps -axo command=)" || fail '无法读取进程信息。'
  if printf '%s\n' "${processes}" | awk -v avd="${AVD_NAME}" '
    /qemu-system|\/emulator / { for (i=1; i<NF; i++) if ($i=="-avd" && $(i+1)==avd) found=1 }
    END { exit !found }'; then
    fail '目标模拟器仍在启动或退出中，请稍后重新运行；不会创建重复实例。'
  fi
  port=5554
  while [ "${port}" -le 5682 ]; do
    if ! /usr/sbin/lsof -nP -t -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 &&
       ! /usr/sbin/lsof -nP -t -iTCP:"$((port + 1))" -sTCP:LISTEN >/dev/null 2>&1; then
      break
    fi
    port=$((port + 2))
  done
  [ "${port}" -le 5682 ] || fail '找不到可用的模拟器端口。'
  TARGET_SERIAL="emulator-${port}"
  say "正在打开模拟器窗口：${TARGET_SERIAL}（保留 AVD 原有 CPU／内存设置）……"
  # No audio and no snapshot saving; do not wipe user data or launch Android Studio.
  nohup "${EMULATOR}" -avd "${AVD_NAME}" -port "${port}" -no-audio -no-snapshot-save \
    >> "${LOG_FILE}" 2>&1 < /dev/null &
  emulator_pid=$!
  disown "${emulator_pid}" 2>/dev/null || true
else
  emulator_pid=''
fi

say '等待安卓启动完成，最多 180 秒……'
deadline=$((SECONDS + 180))
ready=0
while [ "${SECONDS}" -lt "${deadline}" ]; do
  if [ -n "${emulator_pid}" ] && ! kill -0 "${emulator_pid}" 2>/dev/null; then
    fail '模拟器进程已退出，请查看日志末尾的错误信息。'
  fi
  remaining=$((deadline - SECONDS))
  timeout=5
  [ "${remaining}" -ge "${timeout}" ] || timeout="${remaining}"
  boot="$(bounded "${timeout}" "${ADB}" -s "${TARGET_SERIAL}" shell getprop sys.boot_completed 2>/dev/null || true)"
  boot="$(printf '%s' "${boot}" | tr -d '\r\n')"
  if [ "${boot}" = 1 ]; then ready=1; break; fi
  [ "${SECONDS}" -lt "${deadline}" ] && sleep 1
 done
[ "${ready}" = 1 ] || fail "安卓启动超时（180 秒）。模拟器保留运行，可稍后重试。"
name="$(bounded 5 "${ADB}" -s "${TARGET_SERIAL}" emu avd name)" || fail '无法核对目标模拟器。'
name="$(printf '%s\n' "${name}" | tr -d '\r' | /usr/bin/head -n 1)"
[ "${name}" = "${AVD_NAME}" ] || fail '设备身份发生变化，已停止安装以免影响其他设备。'

say '正在安装 TimeFlow（覆盖安装，保留已有数据）……'
install_output="$(bounded 120 "${ADB}" -s "${TARGET_SERIAL}" install -r "${APK_PATH}")" || fail 'APK 安装失败。可能是签名不一致或空间不足；不会自动卸载现有应用，请查看日志。'
printf '%s\n' "${install_output}" | /usr/bin/grep -q '^Success' || fail '安装器没有返回成功状态，请查看日志。'
say '正在打开 TimeFlow……'
launch_output="$(bounded 20 "${ADB}" -s "${TARGET_SERIAL}" shell am start -W -n app.timeflow.timeflow/.MainActivity)" || fail '应用启动失败，请查看日志。'
printf '%s\n' "${launch_output}" | /usr/bin/grep -q 'Status: ok' || fail '安卓未确认应用成功启动，请查看日志。'
say ''
say '演示已就绪，请在模拟器窗口操作 TimeFlow。'
say '建议：新建任务 → 设置两分钟后的提醒 → 在设置中开启通知及准时提醒 → 查看回顾。'
say '可以关闭本终端窗口；结束演示时关闭模拟器窗口即可。'
