`timescale 1ns/1ps

module tb_bch_hard_core;

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

    // ---------------------------------------------------------
    // DUT
    // ---------------------------------------------------------
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

    // ---------------------------------------------------------
    // Clock
    // ---------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------------------------------------------------
    // Self-Checking Task
    // ---------------------------------------------------------
    task check_result(
        input integer   test_id,
        input           expected_success,
        input [N_MAX_TB-1:0] expected_err
    );
    begin
        if (success !== expected_success) begin
            $display("❌ FAIL (Test %0d): success=%b, expected=%b",
                     test_id, success, expected_success);
        end
        else if (err_vec !== expected_err) begin
            $display("❌ FAIL (Test %0d): err_vec mismatch", test_id);
        end
        else begin
            $display("✔ PASS (Test %0d)", test_id);
        end
    end
    endtask

    // ---------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------
    initial begin
        $dumpfile("tb_bch_hard_core.vcd");
        $dumpvars(0, tb_bch_hard_core);

        rstn = 0; start=0;
        n=63; t=2; m=6;
        hard_bits = 0;
        #20; rstn = 1;
        #20;

        // ======================================================
        // Test 1: syndrome = 0 → success=1, err_vec=0
        // ======================================================
        $display("\n=== Test 1 : syndrome=0 → expect success=1 ===");

        dut.u_syn_calc.tb_set_syndrome(0);
        dut.u_berlekamp.tb_set_ber(0, 1);         
        dut.u_chien.tb_set_chien(63'h123456789ABC);  // won't be used

        start_pulse();
        wait(done); @(posedge clk);

        check_result(1, 1'b1, {N_MAX_TB{1'b0}});

        // ======================================================
        // Test 2: Berlekamp fail → success=0
        // ======================================================
        $display("\n=== Test 2 : ber_failure=1 → expect success=0 ===");

        dut.u_syn_calc.tb_set_syndrome(64'hFFFF);
        dut.u_berlekamp.tb_set_ber(1, 1);          
        dut.u_chien.tb_set_chien(63'h00FF00FF00FF);

        start_pulse();
        wait(done); @(posedge clk);

        check_result(2, 1'b0, {N_MAX_TB{1'b0}});

        // ======================================================
        // Test 3: normal decode → success=1
        // ======================================================
        $display("\n=== Test 3 : good sigma → expect success=1 ===");

        dut.u_syn_calc.tb_set_syndrome(64'hAAAA);
        dut.u_berlekamp.tb_set_ber(0, 2);           
        dut.u_chien.tb_set_chien(63'h0000_0000_FFFF);

        start_pulse();
        wait(done); @(posedge clk);

        check_result(3, 1'b1, 63'h0000_0000_FFFF);

        #50;
        $finish;
    end

    // ---------------------------------------------------------
    // start pulse
    // ---------------------------------------------------------
    task start_pulse();
    begin
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
    end
    endtask

    // ---------------------------------------------------------
    // trace print
    // ---------------------------------------------------------
    always @(posedge clk) begin
        $display("[%0t] state=%0d done=%b success=%b",
                 $time, dut.state, done, success);
    end

endmodule
