#!/bin/bash
# 簡單 iverilog 測試腳本
# 用法：
#   ./run_iverilog.sh [rtl|syn] [F1|F2|F3|F4]
#
# 範例：
#   ./run_iverilog.sh rtl F1   # RTL + F1
#   ./run_iverilog.sh syn F2   # Gate-level netlist + F2（不含 SDF）

# ========= 設定區：請依你的專案目錄修改 =========

TB="../00_TESTBED/testfixture_v2_iverilog.v"          # 測試檔（剛剛那個 patched 版本）
RTL_DIR="../01_RTL"                     # RTL 檔案路徑
GLS="../02_SYN/Netlist/IOTDF_syn.v"     # 綜合後 netlist 檔案路徑

OUT="simv"                              # 輸出執行檔名稱

# ========= 參數處理 =========

MODE=${1:-rtl}      # 預設跑 RTL
FUNC=${2:-F1}       # 預設 F1

if [[ "$MODE" != "rtl" && "$MODE" != "syn" ]]; then
  echo "模式錯誤：請輸入 rtl 或 syn"
  echo "用法：$0 [rtl|syn] [F1|F2|F3|F4]"
  exit 1
fi

if [[ "$FUNC" != "F1" && "$FUNC" != "F2" && "$FUNC" != "F3" && "$FUNC" != "F4" ]]; then
  echo "功能錯誤：請輸入 F1 / F2 / F3 / F4"
  echo "用法：$0 [rtl|syn] [F1|F2|F3|F4]"
  exit 1
fi

# 定義給 testbench 用的巨集：
# -D vcd  讓它走 VCD 分支（$dumpfile/$dumpvars）
# -D F?   選功能
DEFINES="-D vcd -D ${FUNC}"

# 根據模式決定要編哪些檔
if [[ "$MODE" == "rtl" ]]; then
  FILES="$TB $RTL_DIR/*.v"
  echo "[INFO] RTL 模式：包含 $RTL_DIR 下所有 .v 檔"
else
  FILES="$TB $GLS"
  echo "[INFO] 使用 SYN (gate-level) 模式（不含 SDF）：$GLS"
fi

# ========= 編譯 =========

echo "[INFO] 編譯中..."
iverilog -g2012 -o "$OUT" $DEFINES $FILES
if [[ $? -ne 0 ]]; then
  echo "[ERROR] iverilog 編譯失敗，請檢查檔案路徑與錯誤訊息。"
  exit 1
fi

# ========= 執行 =========

echo "[INFO] 執行模擬..."
vvp "$OUT"
RET=$?

if [[ $RET -ne 0 ]]; then
  echo "[ERROR] vvp 執行失敗（exit code = $RET）。"
  exit $RET
fi

echo "[INFO] 模擬完成。若有開啟 vcd，請用 GTKWave 查看產生的 .vcd 檔案。"
