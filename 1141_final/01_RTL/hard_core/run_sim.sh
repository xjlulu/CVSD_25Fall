#!/usr/bin/env bash
set -e

# === 設定變數 ===
TOP_TB="tb_bch_hard_core.v"
OUT_FILE="sim.out"
VCD_FILE="tb_bch_hard_core.vcd"

echo "==[ Step 0 ] 檢查 iverilog 是否存在 =="
if ! command -v iverilog >/dev/null 2>&1; then
    echo "錯誤：找不到 iverilog，請先安裝 Icarus Verilog（brew install icarus-verilog）"
    exit 1
fi

echo "==[ Step 1 ] 編譯所有 Verilog 檔 (*.v) =="
# 如果你想精準指定檔案，也可以改成：
# iverilog -g2012 -o "$OUT_FILE" bch_hard_core.v tb_bch_hard_core.v
iverilog -g2012 -o "$OUT_FILE" *.v

echo "==[ Step 2 ] 執行模擬 =="
vvp "$OUT_FILE"

echo "==[ Step 3 ] 檢查是否有產生 VCD 波形檔 ($VCD_FILE) =="
if [ -f "$VCD_FILE" ]; then
    echo "已產生波形檔：$VCD_FILE"
    # 若有安裝 gtkwave，順便開波形（沒裝會噴 warning，但不影響）
    if command -v gtkwave >/dev/null 2>&1; then
        echo "開啟 GTKWave 看波形..."
        gtkwave "$VCD_FILE" &
    else
        echo "提示：未找到 gtkwave，如需看波形可安裝：brew install gtkwave"
    fi
else
    echo "警告：找不到 $VCD_FILE，請確認 testbench 有呼叫 \$dumpfile / \$dumpvars"
fi

echo "== All done =="
