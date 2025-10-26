`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000

`ifdef p0
    `define Inst "../00_TB/PATTERN/p0/inst.dat"
	`define ExpectedData "../00_TB/PATTERN/p0/data.dat"
	`define ExpectedStatus "../00_TB/PATTERN/p0/status.dat"
`elsif p1
    `define Inst "../00_TB/PATTERN/p1/inst.dat"
	`define ExpectedData "../00_TB/PATTERN/p1/data.dat"
	`define ExpectedStatus "../00_TB/PATTERN/p1/status.dat"
`elsif p2
	`define Inst "../00_TB/PATTERN/p2/inst.dat"
	`define ExpectedData "../00_TB/PATTERN/p2/data.dat"
	`define ExpectedStatus "../00_TB/PATTERN/p2/status.dat"
`elsif p3
	`define Inst "../00_TB/PATTERN/p3/inst.dat"
	`define ExpectedData "../00_TB/PATTERN/p3/data.dat"
	`define ExpectedStatus "../00_TB/PATTERN/p3/status.dat"
`else
	`define Inst "../00_TB/PATTERN/p0/inst.dat"
	`define ExpectedData "../00_TB/PATTERN/p0/data.dat"
	`define ExpectedStatus "../00_TB/PATTERN/p0/status.dat"
`endif

module testbed;

	reg  rst_n;
	reg  clk = 0;
	wire            dmem_we;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  2 : 0 ] mips_status;
	wire            mips_status_valid;

	integer cyc;
	initial cyc = 0;
	always @(posedge clk) cyc <= cyc + 1;

	reg        dut_valid_d1;
	reg [2:0]  dut_status_d1;
	always @(posedge clk) begin
  		dut_valid_d1  <= mips_status_valid;
  		dut_status_d1 <= mips_status;
	end

	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_status(mips_status),
		.o_status_valid(mips_status_valid),
		.o_we(dmem_we),
		.o_addr(dmem_addr),
		.o_wdata(dmem_wdata),
		.i_rdata(dmem_rdata)
	);

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_we(dmem_we),
		.i_addr(dmem_addr),
		.i_wdata(dmem_wdata),
		.o_rdata(dmem_rdata)
	);

	localparam integer INST_WORDS  = 1024;
	localparam integer DATA_WORDS  = 2048;

	always #(`HCYCLE) begin
		clk = ~clk;
	end

	// load data memory
	initial begin 
		rst_n = 1;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		$readmemb (`Inst, u_data_mem.mem_r);
	end

	integer cycle_cnt;
	always @(posedge clk or negedge rst_n) begin
    	if (!rst_n) begin
			cycle_cnt <= 0;
		end
    	else begin
			cycle_cnt <= cycle_cnt + 1;
		end
	end

	always @(posedge clk) begin
    	if (cycle_cnt > `MAX_CYCLE) begin
        	$display("[TB] ERROR: exceed MAX_CYCLE = %0d", `MAX_CYCLE);
        	$finish;
    	end
	end

	`ifdef FSDB
	initial begin
    	$fsdbDumpfile("wave.fsdb");
    	$fsdbDumpvars(0, testbed);
	end
	`else
	initial begin
    	$dumpfile("wave.vcd");
    	$dumpvars(0, testbed);
	end
	`endif

	integer                 sfid_cnt, sfid;
	integer                 status_lines;
	reg     [          2:0] exp_status;
	integer                 rcode;
	integer                 status_seen;
	reg     [8 * 256 - 1:0] dummy_line;

	initial begin : COUNT_STATUS_LINES
    	status_lines = 0;
    	sfid_cnt = $fopen(`ExpectedStatus, "r");
    	if (sfid_cnt == 0) begin
        	$display("[TB] WARNING: cannot open %s, skip status checking.", `ExpectedStatus);
    	end
		else begin
        	while (!$feof(sfid_cnt)) begin
            	rcode = $fscanf(sfid_cnt, "%b\n", exp_status);
            	if (rcode == 1) status_lines = status_lines + 1;
            	else begin
                	rcode = $fgets(dummy_line, sfid_cnt);
            	end
        	end
        	$fclose(sfid_cnt);
    	end
	end

	reg status_check_enable;
	initial begin
    	status_check_enable = 1'b0;
    	status_seen = 0;
    	@(posedge rst_n);
    	@(posedge clk);
    	sfid = $fopen(`ExpectedStatus, "r");
    	if (sfid == 0) begin
        	$display("[TB] WARNING: cannot open %s, status check disabled.", `ExpectedStatus);
        	status_check_enable = 1'b0;
    	end else begin
        	if (status_lines == 0)
            	$display("[TB] WARNING: %s is empty, status check disabled.", `ExpectedStatus);
        	status_check_enable = (status_lines > 0);
    	end
	end

	always @(negedge clk) if (status_check_enable) begin
    	if (dut_valid_d1) begin
        	rcode = $fscanf(sfid, "%b\n", exp_status);
        	if (rcode != 1) begin
            	$display("[TB] ERROR: STATUS file EOF or bad format at line %0d.", status_seen + 1);
            	$finish;
        	end

        	$display("[TRACE][C%0d][line %0d] DUT = %03b  EXP = %03b  valid = %0d  time = %0t",
                	 cyc, status_seen + 1, dut_status_d1, exp_status, dut_valid_d1, $time);

        	if (dut_status_d1 !== exp_status) begin
            	$display("[TB] STATUS MISMATCH @line %0d: DUT = %03b, EXP = %03b",
                    	 status_seen + 1, dut_status_d1, exp_status);
            	$finish;
        	end

        	status_seen = status_seen + 1;
        	if (status_seen == status_lines) begin
            	$display("[TB] STATUS CHECK PASS. total = %0d", status_lines);
            	status_check_enable = 1'b0;
            	$fclose(sfid);
        	end
    	end
	end

	reg     [31:0] golden_data [0:DATA_WORDS - 1];
	integer        i_dat, err_cnt;
	reg            data_loaded, compared;

	initial begin
    	data_loaded = 1'b0;
    	compared    = 1'b0;
    	$readmemb(`ExpectedData, golden_data);
    	data_loaded = 1'b1;
	end

	always @(posedge clk) begin
    	if (!compared && (status_lines>0) && (status_seen == status_lines) && data_loaded) begin
        	err_cnt = 0;
        	for (i_dat = 0; i_dat < DATA_WORDS; i_dat = i_dat + 1) begin
            	if (u_data_mem.mem_r[i_dat] !== golden_data[i_dat]) begin
                	$display("[TB] DATA MISMATCH @word %0d (addr = %0d): DUT = 0x%08x EXP = 0x%08x",
                         	i_dat, (i_dat << 2), u_data_mem.mem_r[i_dat], golden_data[i_dat]);
                	err_cnt = err_cnt + 1;
            	end
        	end
        	if (err_cnt == 0) $display("[TB] DATA CHECK PASS.");
        	else              $display("[TB] DATA CHECK FAIL. errors = %0d", err_cnt);

        	compared = 1'b1;
        	$display("[TB] FINISH. cycles = %0d", cycle_cnt);
        	$finish;
    	end
	end

endmodule
