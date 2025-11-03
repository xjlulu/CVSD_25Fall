#!/usr/bin/env bash
set -e

# -------------------------------------------
# 用法：
#   ./run.sh tb1        # 跑 tb1 測資
#   ./run.sh tb2
#   ./run.sh tb3
#   ./run.sh tb4
#
# 選項：
#   環境變數 TB_PAT 可覆寫 PATTERNS 根目錄（預設：專案根/00_TESTBED/PATTERNS）
#   例：TB_PAT=/abs/path/to/00_TESTBED/PATTERNS ./run.sh tb1 -w
#
#   -w  或 --wave ：模擬後自動開啟 GTKWave
# 產出：
#   build/<case>/sim.vvp   -> vvp 可執行
#   build/<case>/core.vcd  -> 波形
# -------------------------------------------

if ! command -v iverilog >/dev/null 2>&1; then
  echo "[ERR] iverilog 未安裝，請先安裝 Icarus Verilog。" >&2
  exit 1
fi

if ! command -v vvp >/dev/null 2>&1; then
  echo "[ERR] vvp 未安裝，請先安裝 Icarus Verilog。" >&2
  exit 1
fi

CASE="$1"
OPEN_WAVE="no"

if [[ -z "$CASE" ]]; then
  echo "用法：$0 {tb1|tb2|tb3|tb4} [-w]" >&2
  exit 1
fi

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--wave) OPEN_WAVE="yes"; shift ;;
    *) echo "[WARN] 未知參數：$1 (忽略)"; shift ;;
  esac
done

# 檢查 case 名稱
if [[ "$CASE" != "tb1" && "$CASE" != "tb2" && "$CASE" != "tb3" && "$CASE" != "tb4" ]]; then
  echo "[ERR] 測試案例必須是 tb1/tb2/tb3/tb4 之一" >&2
  exit 1
fi

# 取得腳本所在目錄（多數情況 run.sh 放在 01_RTL/）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 專案根目錄 = 腳本上層
PROJ_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PATTERNS 根目錄（改成「專案根」下的 00_TESTBED/PATTERNS；可用環境變數 TB_PAT 覆寫）
TB_PAT_DEFAULT="${PROJ_ROOT}/00_TESTBED/PATTERNS"
TB_PAT_ESCAPED="${TB_PAT:-$TB_PAT_DEFAULT}"

# 建置輸出資料夾
OUTDIR="build/${CASE}"
mkdir -p "${OUTDIR}"

echo "[INFO] 使用 PATTERNS 目錄：${TB_PAT_ESCAPED}"
echo "[INFO] 建置目錄：${OUTDIR}"

# 先檢查檔案是否存在（以 tb1 檔名為例；其他 tbX 仍會在 testbench 用巨集切換）
echo "[DBG] 檢查常見檔案是否存在："
for f in \
  "${TB_PAT_ESCAPED}/img1_030101_00.dat" \
  "${TB_PAT_ESCAPED}/weight_img1_030101_00.dat" \
  "${TB_PAT_ESCAPED}/golden_img1_030101_00.dat"
do
  if [[ -f "$f" ]]; then echo "  OK  $f"; else echo "  MISS $f"; fi
done

# 編譯
iverilog -g2012 \
  -s testbed_iverilog \
  -D"${CASE}" \
  -DTB_PAT="\"${TB_PAT_ESCAPED}\"" \
  -o "${OUTDIR}/sim.vvp" \
  -f rtl.f

echo "[INFO] 編譯完成：${OUTDIR}/sim.vvp"

# 模擬（進到 OUTDIR 執行，使輸出 core.vcd 落在 OUTDIR）
(
  cd "${OUTDIR}"
  vvp sim.vvp
)

VCD="${OUTDIR}/core.vcd"
if [[ -f "${VCD}" ]]; then
  echo "[INFO] 波形產生：${VCD}"
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
