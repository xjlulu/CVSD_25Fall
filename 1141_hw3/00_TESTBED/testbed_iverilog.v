`timescale 1ns/1ps
`define CYCLE       5.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   20000
`define RST_DELAY   2

`ifndef TB_PAT
  `define TB_PAT "../00_TESTBED/PATTERNS"
`endif

`ifdef tb1
    // `define INFILE `TB_PAT "/img1_030101_00.dat"
    `define INFILE {`TB_PAT, "/img1_030101_00.dat"}
    // `define WFILE  `TB_PAT "/weight_img1_030101_00.dat"
    `define WFILE  {`TB_PAT, "/weight_img1_030101_00.dat"}
    // `define GOLDEN `TB_PAT "/golden_img1_030101_00.dat"
    `define GOLDEN {`TB_PAT, "/golden_img1_030101_00.dat"}
    `define K_SIZE 3
    `define S_SIZE 1
    `define D_SIZE 1
    `define VALID_OP 1
    `define OUTPUTSIZE 4096
`elsif tb2
    `define INFILE `TB_PAT "/img1_030102_053.dat"
    `define WFILE  `TB_PAT "/weight_img1_030102_053.dat"
    `define GOLDEN `TB_PAT "/golden_img1_030102_053.dat"
    `define K_SIZE 3
    `define S_SIZE 1
    `define D_SIZE 2
    `define VALID_OP 1
    `define OUTPUTSIZE 4096
`elsif tb3
    `define INFILE `TB_PAT "/img1_030201_70.dat"
    `define WFILE  `TB_PAT "/weight_img1_030201_70.dat"
    `define GOLDEN `TB_PAT "/golden_img1_030201_70.dat"
    `define K_SIZE 3
    `define S_SIZE 2
    `define D_SIZE 1
    `define VALID_OP 1
    `define OUTPUTSIZE 1024
`elsif tb4
    `define INFILE `TB_PAT "/img1_030202_753.dat"
    `define WFILE  `TB_PAT "/weight_img1_030202_753.dat"
    `define GOLDEN `TB_PAT "/golden_img1_030202_753.dat"
    `define K_SIZE 3
    `define S_SIZE 2
    `define D_SIZE 2
    `define VALID_OP 1
    `define OUTPUTSIZE 1024
`else
    `define INFILE `TB_PAT "/img1_050102_514.dat"
    `define WFILE  `TB_PAT "/weight_img1_050102_514.dat"
    `define GOLDEN `TB_PAT "/golden_img1_050102_514.dat"
    `define K_SIZE 0
    `define S_SIZE 0
    `define D_SIZE 0
    `define VALID_OP 0
    `define OUTPUTSIZE 0
`endif

`define SDFFILE "../02_SYN/Netlist/core_syn.sdf"

module testbed_iverilog;

    reg         clk, rst_n;
    reg         in_valid;
    reg [31:0]  in_data;
    wire        in_ready;

    wire        out_valid1, out_valid2, out_valid3, out_valid4;
    wire [11:0] out_addr1,  out_addr2,  out_addr3,  out_addr4;
    wire [7:0]  out_data1,  out_data2,  out_data3,  out_data4;
    wire        exe_finish;

    reg  [7:0]  indata_mem [0:4096-1];
    reg  [7:0]  weight_mem [0:25-1];
    reg  [7:0]  golden_mem [0:4096-1];
    reg  [7:0]  out_mem    [0:4096-1];

    reg         stage1_finish;

    integer cnt1, cnt3, cntw;
    integer error, error_spec, error_spec2;

    `ifdef SDF
        initial $sdf_annotate(`SDFFILE, u_core);
        initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
    `endif

    // VCD
    initial begin
        $dumpfile("core.vcd");
        $dumpvars(0, testbed_iverilog); // ← 模組名要對
    end

    core u_core (
        .i_clk       (clk),
        .i_rst_n     (rst_n),
        .i_in_valid  (in_valid),
        .i_in_data   (in_data),

        .o_in_ready  (in_ready),

        .o_out_data1 (out_data1),
        .o_out_data2 (out_data2),
        .o_out_data3 (out_data3),
        .o_out_data4 (out_data4),

        .o_out_addr1 (out_addr1),
        .o_out_addr2 (out_addr2),
        .o_out_addr3 (out_addr3),
        .o_out_addr4 (out_addr4),

        .o_out_valid1 (out_valid1),
        .o_out_valid2 (out_valid2),
        .o_out_valid3 (out_valid3),
        .o_out_valid4 (out_valid4),

        .o_exe_finish (exe_finish)
    );

    // 讀入測資（明確指定範圍，避免 iverilog 警告）
    localparam integer IMG_CNT    = 4096;                 // 64*64
    localparam integer WEIGHT_CNT = (`K_SIZE*`K_SIZE);    // tb1=9, tb2=9, tb3/4=9（依 K_SIZE）
    localparam integer GOLD_CNT   = `OUTPUTSIZE;          // 4096 或 1024（依案例）

    // 讀入測資
    initial $readmemh(`INFILE,  indata_mem,  0, IMG_CNT-1);
    initial $readmemh(`WFILE,   weight_mem,  0, WEIGHT_CNT-1);
    initial $readmemh(`GOLDEN,  golden_mem,  0, GOLD_CNT-1);

    // clock
    initial clk = 1'b0;
    always #(`CYCLE/2) clk = ~clk;

    // reset & timeout
    initial begin
        rst_n = 1; # (0.25 * `CYCLE);
        rst_n = 0; # ((`RST_DELAY + 0.7) * `CYCLE);
        rst_n = 1; # (`MAX_CYCLE * `CYCLE);
        $display("Error! Runtime exceeded!");
        $finish;
    end

    // 資料輸入
    initial begin
        cnt1 = 0;
        cntw = 0;
        in_valid = 0;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);

        // start
        @(negedge clk);
        @(negedge clk);
        in_valid = 1;
        in_data  = {indata_mem[cnt1*4],indata_mem[cnt1*4 + 1],indata_mem[cnt1*4 + 2],indata_mem[cnt1*4 + 3]};

        // data_input
        wait (in_ready === 1);
        while (cnt1 < 1023) begin
            @(negedge clk);
            if (in_ready) begin
                cnt1   = cnt1 + 1;
                in_data = {indata_mem[cnt1*4],indata_mem[cnt1*4 + 1],indata_mem[cnt1*4 + 2],indata_mem[cnt1*4 + 3]};
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_data  = 32'b0;

        // weight_input
        if (`VALID_OP) begin
            wait (stage1_finish);
            @(negedge clk);
            in_valid = 1;
            in_data  = {weight_mem[cntw*4],weight_mem[cntw*4 + 1],weight_mem[cntw*4 + 2],weight_mem[cntw*4 + 3]}; 

            while (cntw <= ((`K_SIZE*`K_SIZE) >> 2)) begin
                @(negedge clk);
                if (in_ready) begin
                    cntw   = cntw + 1;
                    in_data = {weight_mem[cntw*4],weight_mem[cntw*4 + 1],weight_mem[cntw*4 + 2],weight_mem[cntw*4 + 3]};
                end
            end
            in_valid = 0;
        end
    end

    // SPEC：in_valid 與 out_valid* 不可同拍為 1
    initial begin
        error_spec = 0;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        
        while (!exe_finish) begin
            @(negedge clk);
            if (in_valid === 1 && out_valid1 === 1) begin
                $display("Time %t: SPEC Error! i_in_valid and o_out_valid1 can't be HIGH in the same time", $time);
                error_spec = error_spec + 1;
            end
            if (in_valid === 1 && out_valid2 === 1) begin
                $display("Time %t: SPEC Error! i_in_valid and o_out_valid2 can't be HIGH in the same time", $time);
                error_spec = error_spec + 1;
            end
            if (in_valid === 1 && out_valid3 === 1) begin
                $display("Time %t: SPEC Error! i_in_valid and o_out_valid3 can't be HIGH in the same time", $time);
                error_spec = error_spec + 1;
            end
            if (in_valid === 1 && out_valid4 === 1) begin
                $display("Time %t: SPEC Error! i_in_valid and o_out_valid4 can't be HIGH in the same time", $time);
                error_spec = error_spec + 1;
            end
        end
    end

    // 檢查 barcode 與輸出
    initial begin
        error         = 0;
        error_spec2   = 0;
        cnt3          = 0;
        stage1_finish = 0;

        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);

        $display("----------------------------------------------");
        $display("          STAGE 1:  BARCODE DECODING          ");
        $display("----------------------------------------------");

        wait ((out_valid1 === 1) && (out_valid2 === 1) && (out_valid3 === 1));

        @(negedge clk);
        if ((out_valid1 === 1) && (out_valid2 === 1) && (out_valid3 === 1)) begin
            if (out_data1 !== `K_SIZE) $display("Error! Kernel size should be =%0d, Yours=%0d" , `K_SIZE , out_data1);
            if (out_data2 !== `S_SIZE) $display("Error! Stride size should be =%0d, Yours=%0d" , `S_SIZE , out_data2);
            if (out_data3 !== `D_SIZE) $display("Error! Dilation size should be =%0d, Yours=%0d" , `D_SIZE , out_data3);
            if (out_data1 === `K_SIZE && out_data2 === `S_SIZE && out_data3 === `D_SIZE) begin
                if (`VALID_OP) $display("All Configurations Correct! Permission Granted to Enter STAGE 2");
                else           $display("All Configurations Correct! CONGRATULATIONS!!!");
                stage1_finish = 1;
            end
        end

        if (`VALID_OP) begin
            $display("----------------------------------------------");
            $display("             STAGE 2:  CONVOLUTION            ");
            $display("----------------------------------------------");

            while (!exe_finish) begin
                @(negedge clk);
                if (out_valid1) begin
                    out_mem[out_addr1] = out_data1;
                    if (out_valid2 && (out_addr1 === out_addr2)) begin
                        $display("Time %t: SPEC Error! out_data1 and out_data2 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                    if (out_valid3 && (out_addr1 === out_addr3)) begin
                        $display("Time %t: SPEC Error! out_data1 and out_data3 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                    if (out_valid4 && (out_addr1 === out_addr4)) begin
                        $display("Time %t: SPEC Error! out_data1 and out_data4 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                end
                if (out_valid2) begin
                    out_mem[out_addr2] = out_data2;
                    if (out_valid3 && (out_addr2 === out_addr3)) begin
                        $display("Time %t: SPEC Error! out_data2 and out_data3 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                    if (out_valid4 && (out_addr2 === out_addr4)) begin
                        $display("Time %t: SPEC Error! out_data2 and out_data4 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                end
                if (out_valid3) begin
                    out_mem[out_addr3] = out_data3;
                    if (out_valid4 && (out_addr3 === out_addr4)) begin
                        $display("Time %t: SPEC Error! out_data3 and out_data4 written to the same address", $time);
                        error_spec2 = error_spec2 + 1;
                    end
                end
                if (out_valid4) begin
                    out_mem[out_addr4] = out_data4;
                end
            end

            @(negedge clk);
            while (cnt3 < `OUTPUTSIZE) begin
                if (golden_mem[cnt3] !== out_mem[cnt3]) begin
                    $display("[ADDR %0d] Error: golden=[%0d], your=[%0d]", cnt3, golden_mem[cnt3], out_mem[cnt3]);
                    error = error + 1;
                end
                cnt3 = cnt3 + 1;
            end

            $display("\n=== OVERALL COMPARISON RESULTS ===");
            if (error === 0) begin
                $display("PASS: All data match.");
            end else begin
                $display("FAIL: Total data mismatches = %0d", error);
            end
        end

        wait (exe_finish);
        $display("------------   Total SPEC Error: %0d    ---------------", error_spec + error_spec2);

        # (2 * `CYCLE);
        $finish;
    end

endmodule
