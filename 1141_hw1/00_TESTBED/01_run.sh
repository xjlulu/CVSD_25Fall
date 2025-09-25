#vcs -full64 -R -f rtl.f +v2k -sverilog -debug_access+all +define+$1 | tee sim.log
#!/bin/bash

# 腳本說明：自動化編譯和模擬 ALU 測試

# 1. 檢查參數是否存在
if [ -z "$1" ]; then
    echo "錯誤：請指定要測試的指令編號（例如：./run.sh I0）"
    exit 1
fi

# 2. 定義變數
TEST_INST=$1             # 接收第一個參數 (例如 I0, I1, I2...)
RTL_FILE="../01_RTL/alu.v"
TB_FILE="testbench.v"
SIM_OUTPUT="alu_sim"
VCD_OUTPUT="alu.vcd"

echo "================================================="
echo "開始測試指令：$TEST_INST"
echo "================================================="

# 3. 清理舊檔案 (可選，但推薦)
# 移除上一次模擬產生的檔案
rm -f $SIM_OUTPUT $VCD_OUTPUT


# 4. 編譯 (使用 -D 參數傳遞指令宏)
echo "--- 正在編譯 ---"
iverilog -o $SIM_OUTPUT -D $TEST_INST $RTL_FILE $TB_FILE

# 檢查編譯是否成功
if [ $? -ne 0 ]; then
    echo "編譯失敗！"
    exit 1
fi

# 5. 執行模擬
echo "--- 正在模擬 ---"
./$SIM_OUTPUT

# 6. 完成
echo "--- 模擬完成 ---"
echo "結果已顯示於上方，波形檔已儲存為：$VCD_OUTPUT"

# 7. 啟動 GTKWave
# gtkwave $VCD_OUTPUT &