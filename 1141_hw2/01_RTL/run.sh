#!/bin/bash

# --- 測試 ALU 模組 ---
echo "--- Compiling and simulating ALU ---"
# 編譯 ALU 設計和測試平台，輸出到 alu_sim
iverilog -o alu_sim alu.v tb_alu.v

# 檢查編譯是否成功 ($? 是上一條指令的退出狀態碼)
if [ $? -eq 0 ]; then
    echo "ALU Compilation successful. Running simulation..."
    # 執行模擬檔
    vvp alu_sim
else
    echo "ALU Compilation failed."
fi


echo 
echo "-------------------------------------"
echo

# --- 測試 regfile_int 模組 ---
echo "--- Compiling and simulating RegFile ---"
# 編譯 regfile_int 設計和測試平台，輸出到 regfile_int_sim
iverilog -o regfile_int_sim regfile_int.v tb_regfile_int.v

# 檢查編譯是否成功
if [ $? -eq 0 ]; then
    echo "RegFile Compilation successful. Running simulation..."
    # 執行模擬檔
    vvp regfile_int_sim
else
    echo "RegFile Compilation failed."
fi

# (選用) 提示查看波形
echo
echo "Simulations complete. Check for .vcd files to view waveforms with gtkwave."