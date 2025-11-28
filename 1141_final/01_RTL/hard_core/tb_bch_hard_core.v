`timescale 1ns/1ps

module tb_bch_hard_core;

    // 減小一點 N_MAX，波形比較好看（也可以直接用 1023）
    localparam integer N_MAX_TB = 63;
    localparam integer T_MAX_TB = 4;
    localparam integer M_MAX_TB = 10;

    reg                     clk;
    reg                     rstn;
    reg                     start;
    reg  [9:0]              n;
    reg  [3:0]              t;
    reg  [3:0]              m;
    reg  [N_MAX_TB-1:0]     hard_bits;

    wire                    done;
    wire                    success;
    wire [N_MAX_TB-1:0]     err_vec;

    // Device Under Test
    bch_hard_core #(
        .N_MAX (N_MAX_TB),
        .T_MAX (T_MAX_TB),
        .M_MAX (M_MAX_TB)
    ) dut (
        .clk       (clk),
        .rstn      (rstn),
        .start     (start),
        .n         (n),
        .t         (t),
        .m         (m),
        .hard_bits (hard_bits),
        .done      (done),
        .success   (success),
        .err_vec   (err_vec)
    );

    // Clock: 10ns period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Stimulus
    initial begin
        // 初始
        rstn      = 1'b0;
        start     = 1'b0;
        n         = 10'd63;
        t         = 4'd2;
        m         = 4'd6;
        hard_bits = {N_MAX_TB{1'b0}};

        // 產生 dump 檔（若你的 simulator 支援）
        $dumpfile("tb_bch_hard_core.vcd");
        $dumpvars(0, tb_bch_hard_core);

        // 釋放 reset
        #20;
        rstn = 1'b1;

        // 再等幾拍
        #20;

        // 第一次 decode
        hard_bits = {N_MAX_TB{1'b1}};   // 隨便給
        start_pulse();

        // 等待 done
        wait (done == 1'b1);
        @(posedge clk);  // 再多等一拍

        // 第二次 decode
        hard_bits = {N_MAX_TB{1'b0}};   // 再換一組
        start_pulse();

        // 再等 done
        wait (done == 1'b1);
        @(posedge clk);

        #50;
        $finish;
    end

    // 產生一拍 start pulse 的 task
    task start_pulse;
    begin
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
    end
    endtask

    // 每拍印出 state & handshake 狀態
    // 注意：這裡用的是 hierarchical reference，方便你在 console 看到流程
    always @(posedge clk) begin
        $display("[%0t] state=%0d start=%b syn_start=%b syn_done=%b ber_start=%b ber_done=%b chien_start=%b chien_done=%b done=%b success=%b",
                 $time,
                 dut.state,
                 start,
                 dut.syn_start,
                 dut.syn_done,
                 dut.ber_start,
                 dut.ber_done,
                 dut.chien_start,
                 dut.chien_done,
                 done,
                 success);
    end

endmodule
