#!/usr/bin/env bash
set -e

# -------------------------------------------
# 用法：
#   ./run.sh tb1 | tb2 | tb3 | tb4 [-w]
# 環境變數：
#   TB_PAT=/abs/path/to/00_TESTBED/PATTERNS  # 覆寫 PATTERNS 位置
# 產出：
#   build/sim.vvp   -> vvp 可執行（固定覆蓋）
#   core.vcd        -> 專案根（固定覆蓋）
# -------------------------------------------

if ! command -v iverilog >/dev/null 2>&1; then
  echo "[ERR] iverilog 未安裝，請先安裝 Icarus Verilog。" >&2; exit 1
fi
if ! command -v vvp >/dev/null 2>&1; then
  echo "[ERR] vvp 未安裝，請先安裝 Icarus Verilog。" >&2; exit 1
fi

CASE="$1"
OPEN_WAVE="no"
if [[ -z "$CASE" ]]; then
  echo "用法：$0 {tb1|tb2|tb3|tb4|tb0} [-w]" >&2; exit 1
fi

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--wave) OPEN_WAVE="yes"; shift ;;
    *) echo "[WARN] 未知參數：$1 (忽略)"; shift ;;
  esac
done

if [[ "$CASE" != "tb1" && "$CASE" != "tb2" && "$CASE" != "tb3" && "$CASE" != "tb4" && "$CASE" != "tb0" ]]; then
  echo "[ERR] 測試案例必須是 tb1/tb2/tb3/tb4/tb0 之一" >&2; exit 1
fi

# 取得路徑
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PATTERNS 根目錄（預設：專案根/00_TESTBED/PATTERNS，可用 TB_PAT 覆寫）
TB_PAT_DEFAULT="${PROJ_ROOT}/00_TESTBED/PATTERNS"
TB_PAT_ESCAPED="${TB_PAT:-$TB_PAT_DEFAULT}"

# 輸出目錄（固定）
OUTDIR="build"
mkdir -p "${OUTDIR}"

echo "[INFO] 使用 PATTERNS 目錄：${TB_PAT_ESCAPED}"
echo "[INFO] 建置目錄：${OUTDIR}"

# 可選的檔案存在檢查（常見 tb1/tb2 檔）
echo "[DBG] 檢查常見檔案是否存在："
for f in \
  "${TB_PAT_ESCAPED}/img1_030101_00.dat" \
  "${TB_PAT_ESCAPED}/weight_img1_030101_00.dat" \
  "${TB_PAT_ESCAPED}/golden_img1_030101_00.dat" \
  "${TB_PAT_ESCAPED}/img1_030102_053.dat" \
  "${TB_PAT_ESCAPED}/weight_img1_030102_053.dat" \
  "${TB_PAT_ESCAPED}/golden_img1_030102_053.dat"
do
  if [[ -f "$f" ]]; then echo "  OK  $f"; else echo "  MISS $f"; fi
done

# 編譯（輸出固定為 build/sim.vvp，每次覆蓋）
iverilog -g2012 \
  -s testbed_iverilog \
  -D"${CASE}" \
  -DTB_PAT="\"${TB_PAT_ESCAPED}\"" \
  -o "${OUTDIR}/sim.vvp" \
  -f rtl.f

echo "[INFO] 編譯完成：${OUTDIR}/sim.vvp"

# 模擬：不切換目錄，VCD 固定在專案根 -> core.vcd（每次覆蓋）
vvp "${OUTDIR}/sim.vvp"

VCD="${SCRIPT_DIR}/build/core.vcd"
if [[ -f "${VCD}" ]]; then
  echo "[INFO] 波形產生：${VCD}（新的會覆蓋舊的）"
else
  echo "[WARN] 找不到 core.vcd，請確認 testbed_iverilog.v 內有 \$dumpfile/\$dumpvars 且頂層模組名正確" >&2
fi

# 自動開 GTKWave（選擇性）
if [[ "${OPEN_WAVE}" == "yes" ]]; then
  if command -v gtkwave >/dev/null 2>&1; then
    gtkwave "${VCD}" >/dev/null 2>&1 &
  else
    echo "[WARN] 未發現 gtkwave 指令，略過自動開啟波形。" >&2
  fi
fi

echo "[INFO] 完成！"
