`timescale 1ns/1ps

module test;

// --------------------------
// parameters
parameter CYCLE = 10;
parameter PATTERN = 1;
integer NTEST = 1;

// --------------------------
// signals
reg clk, rstn;
reg mode;
reg [1:0] code;
reg set;
reg [63:0] idata;
wire ready;
wire finish;
wire [9:0] odata;

// --------------------------
// test data
reg [63:0] testdata [0:8191];
reg [9:0] testa [0:511];
integer i1, i2, i3;
integer errcnt;

// --------------------------
// read files and dump files
initial begin
	if (PATTERN == 100) begin
		NTEST = 2;
		$readmemb("testdata/p100.txt", testdata);
		$readmemb("testdata/p100a.txt", testa);
	end
	if (PATTERN == 200) begin
		NTEST = 2;
		$readmemb("testdata/p200.txt", testdata);
		$readmemb("testdata/p200a.txt", testa);
	end
	if (PATTERN == 300) begin
		NTEST = 2;
		$readmemb("testdata/p300.txt", testdata);
		$readmemb("testdata/p300a.txt", testa);
	end
end

initial begin
	$fsdbDumpfile("waveform.fsdb");
	$fsdbDumpvars("+mda");
end

// --------------------------
// modules
bch U_bch(
	.clk(clk),
	.rstn(rstn),
	.mode(mode),
	.code(code),
	.set(set),
	.idata(idata),
	.ready(ready),
	.finish(finish),
	.odata(odata)
);
`ifdef SDF_GATE
	initial $sdf_annotate("../02_SYN/Netlist/bch_syn.sdf", U_bch);
`elsif SDF_POST
	initial $sdf_annotate("../04_APR/Netlist/bch_apr.sdf", U_bch);
`endif

// --------------------------
// clock
initial clk = 1;
always #(CYCLE/2.0) clk = ~clk;

// --------------------------
// test
initial begin
	i1 = 0;
	i2 = 0;
	i3 = 0;
	errcnt = 0;

	rstn = 0;
	mode = 0;
	code = 0;
	set = 0;
	idata = 0;
	#(CYCLE*5);
	@(negedge clk);
	rstn = 1;

	@(negedge clk);
	#(CYCLE*5);
	for (i2 = 0; i2 < NTEST; i2 = i2 + 1) begin
		if (PATTERN <= 100) begin
			code = 1;
			mode = 0;
		end else if (PATTERN <= 200) begin
			code = 2;
			mode = 0;
		end else if (PATTERN <= 300) begin
			code = 3;
			mode = 0;
		end else if (PATTERN <= 400) begin
			code = 1;
			mode = 1;
		end else if (PATTERN <= 500) begin
			code = 2;
			mode = 1;
		end else if (PATTERN <= 600) begin
			code = 3;
			mode = 1;
		end
		set = 1;
		#(CYCLE);
		set = 0;

		wait(finish === 1);
		@(negedge clk);
		#(CYCLE*10);
	end
end
always @(negedge clk) begin
	if (ready === 1) begin
		idata = testdata[i1];
		i1 = i1 + 1;
	end
end
always @(negedge clk) begin
	if (finish === 1 && $time >= CYCLE * 5) begin
		if (odata !== testa[i3]) begin
			errcnt = errcnt + 1;
			$write("design output = %4d, golden output = %4d. Error\n", odata, testa[i3]);
		end else begin
			$write("design output = %4d, golden output = %4d\n", odata, testa[i3]);
		end
		i3 = i3 + 1;
	end
end
initial begin
	wait(i2 == NTEST);
	$write("Error count = %0d\n", errcnt);
	$write("Time = %0d\n", $time - CYCLE * 5);
	#(CYCLE*5);
	$finish;
end
initial begin
	#(CYCLE*1000000);
	$write("Timeout\n");
	$finish;
end

endmodule
