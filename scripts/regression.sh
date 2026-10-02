#!/bin/zsh
# =============================================================================
# FlowTakt v1.3 一键回归脚本
# 用法:
#   ./scripts/regression.sh            # 完整回归: 构建 + 单元 + UI + 版本
#   ./scripts/regression.sh -u         # 快速回归: 跳过 UI 测试（省 ~2.5 分钟）
#   ./scripts/regression.sh -v 1.3     # 指定期望版本号（默认 1.3）
#   ./scripts/regression.sh -b 1       # 指定期望 build（默认 1）
#
# 退出码: 0 = 全部通过; 1 = 任一环节失败
# 报告: /tmp/flowtakt-regression-report.txt
# =============================================================================

set -uo pipefail

PROJECT="/Volumes/csr/FlowTakt流刻/FlowTakt"
UDID="348FBE0A-1158-41D4-AE9B-BAF5F60F119A"          # iPhone 17 Pro Max 模拟器
DERIVED="/tmp/FlowTaktSimDD"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/FlowTakt.app"
REPORT="/tmp/flowtakt-regression-report.txt"
EXPECT_VERSION="1.3"
EXPECT_BUILD="1"
RUN_UI=1

# ---- 参数解析 ----
while getopts "uv:b:h" opt; do
  case $opt in
    u) RUN_UI=0 ;;
    v) EXPECT_VERSION="$OPTARG" ;;
    b) EXPECT_BUILD="$OPTARG" ;;
    h) grep '^#' "$0" | head -12 | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "用法见脚本头部注释"; exit 1 ;;
  esac
done

cd "$PROJECT" || { echo "❌ 项目目录不存在"; exit 1; }

: > "$REPORT"
echo "===== FlowTakt 回归 $(date '+%Y-%m-%d %H:%M:%S') =====" | tee -a "$REPORT"
FAIL=0
START_TS=$(date +%s)

# ---- 0) 模拟器就绪 ----
echo "" | tee -a "$REPORT"
echo "[0/4] 检查模拟器..." | tee -a "$REPORT"
if ! xcrun simctl list devices | grep -q "$UDID.*Booted"; then
  echo "  ⚠️ 模拟器未启动，尝试启动..." | tee -a "$REPORT"
  xcrun simctl boot "$UDID" 2>/dev/null
  xcrun simctl bootstatus "$UDID" -b 2>/dev/null
fi

# ---- 1) Debug 构建 + 0 警告 ----
echo "" | tee -a "$REPORT"
echo "[1/4] Debug 构建（要求 0 警告 0 错误）..." | tee -a "$REPORT"
BUILD_LOG=$(xcodebuild -project FlowTakt.xcodeproj -scheme FlowTakt \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug -derivedDataPath "$DERIVED" build 2>&1)
WARNINGS=$(echo "$BUILD_LOG" | grep -c "warning:" || true)
ERRORS=$(echo "$BUILD_LOG" | grep -c "error:" || true)
if echo "$BUILD_LOG" | grep -q "BUILD SUCCEEDED" && [ "$WARNINGS" -eq 0 ] && [ "$ERRORS" -eq 0 ]; then
  echo "  ✅ 构建成功，警告 $WARNINGS，错误 $ERRORS" | tee -a "$REPORT"
else
  echo "  ❌ 构建失败或存在告警: warnings=$WARNINGS errors=$ERRORS" | tee -a "$REPORT"
  echo "$BUILD_LOG" | grep -E "warning:|error:" | head -20 >> "$REPORT"
  FAIL=1
fi

# ---- 2) 版本号断言 ----
echo "" | tee -a "$REPORT"
echo "[2/4] 版本号断言..." | tee -a "$REPORT"
if [ -f "$APP/Info.plist" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist" 2>/dev/null)
  BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist" 2>/dev/null)
  if [ "$VERSION" = "$EXPECT_VERSION" ] && [ "$BUILD" = "$EXPECT_BUILD" ]; then
    echo "  ✅ 版本 $VERSION ($BUILD)" | tee -a "$REPORT"
  else
    echo "  ❌ 版本不匹配: 期望 $EXPECT_VERSION ($EXPECT_BUILD)，实际 $VERSION ($BUILD)" | tee -a "$REPORT"
    FAIL=1
  fi
else
  echo "  ❌ 未找到 App（构建产物缺失）" | tee -a "$REPORT"
  FAIL=1
fi

# ---- 3) 单元测试 ----
echo "" | tee -a "$REPORT"
echo "[3/4] 单元测试..." | tee -a "$REPORT"
UNIT_LOG=$(xcodebuild -project FlowTakt.xcodeproj -scheme FlowTakt \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug -derivedDataPath "$DERIVED" test \
  -only-testing:FlowTaktTests 2>&1)
UNIT_RESULT=$(echo "$UNIT_LOG" | grep -oE "Executed [0-9]+ tests, with [0-9]+ failures" | tail -1)
if echo "$UNIT_LOG" | grep -q "TEST SUCCEEDED"; then
  echo "  ✅ $UNIT_RESULT" | tee -a "$REPORT"
else
  echo "  ❌ 单元测试失败: $UNIT_RESULT" | tee -a "$REPORT"
  echo "$UNIT_LOG" | grep -E "error:|failed \(" | head -20 >> "$REPORT"
  FAIL=1
fi

# ---- 4) UI 测试（可选） ----
if [ "$RUN_UI" -eq 1 ]; then
  echo "" | tee -a "$REPORT"
  echo "[4/4] UI 测试（约 2.5 分钟）..." | tee -a "$REPORT"
  UI_LOG=$(xcodebuild -project FlowTakt.xcodeproj -scheme FlowTakt \
    -destination "platform=iOS Simulator,id=$UDID" \
    -configuration Debug -derivedDataPath "$DERIVED" test \
    -only-testing:FlowTaktUITests 2>&1)
  UI_RESULT=$(echo "$UI_LOG" | grep -oE "Executed [0-9]+ tests, with [0-9]+ failures" | tail -1)
  if echo "$UI_LOG" | grep -q "TEST SUCCEEDED"; then
    echo "  ✅ $UI_RESULT" | tee -a "$REPORT"
  else
    echo "  ❌ UI 测试失败: $UI_RESULT" | tee -a "$REPORT"
    echo "$UI_LOG" | grep -E "error: -\[|failed \(" | head -20 >> "$REPORT"
    FAIL=1
  fi
else
  echo "" | tee -a "$REPORT"
  echo "[4/4] 跳过 UI 测试（-u 模式）" | tee -a "$REPORT"
fi

# ---- 汇总 ----
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo "" | tee -a "$REPORT"
if [ "$FAIL" -eq 0 ]; then
  echo "✅✅ 回归全部通过（耗时 ${DURATION}s）✅✅" | tee -a "$REPORT"
else
  echo "❌❌ 回归存在失败项（耗时 ${DURATION}s），详见上方 ❌❌" | tee -a "$REPORT"
fi
echo "完整报告: $REPORT"
exit $FAIL
