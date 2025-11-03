
module core (                       //Don't modify interface
	input      		i_clk,
	input      		i_rst_n,
	input    	  	i_in_valid,
	input 	[31: 0] i_in_data,

	output			o_in_ready,

	output	[ 7: 0]	o_out_data1,
	output	[ 7: 0]	o_out_data2,
	output	[ 7: 0]	o_out_data3,
	output	[ 7: 0]	o_out_data4,

	output	[11: 0] o_out_addr1,
	output	[11: 0] o_out_addr2,
	output	[11: 0] o_out_addr3,
	output	[11: 0] o_out_addr4,

	output 			o_out_valid1,
	output 			o_out_valid2,
	output 			o_out_valid3,
	output 			o_out_valid4,

	output 			o_exe_finish
);

// ------------------------------------------------------------
// Internal wire declaration
// ------------------------------------------------------------
wire [11:0] sram_addr_in, sram_addr_bar;
wire [7:0]  sram_din_in, sram_din_bar;  // Add din from both modules (Barcode may not write, but for completeness)
wire        sram_cen_in, sram_wen_in;
wire        sram_cen_bar, sram_wen_bar;

wire        image_done;
wire        barcode_done, barcode_valid;
wire [7:0]  kernel_size, stride_size, dilation_size;

// Muxed signals for SRAM
reg [11:0] sram_addr_mux;
reg [7:0]  sram_din_mux;
reg        sram_cen_mux;
reg        sram_wen_mux;

wire [7:0] sram_din;
wire [7:0] sram_q;

// Phase selector: 0 for input load, 1 for barcode decode
reg        decode_phase;  // Latched based on image_done

// ------------------------------------------------------------
// SRAM Instance
// ------------------------------------------------------------
sram_4096x8 U_SRAM (
    .Q   (sram_q),
    .CLK (i_clk),
    .CEN (sram_cen_mux),  // Use muxed signals
    .WEN (sram_wen_mux),
    .A   (sram_addr_mux),
    .D   (sram_din_mux)
);

// ------------------------------------------------------------
// Input Controller : load 64x64 grayscale image
// ------------------------------------------------------------
Input_Controller U_in_ctrl (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_in_valid(i_in_valid),
    .i_in_data(i_in_data),
    .o_in_ready(o_in_ready),
    .image_done(image_done),

    .sram_addr(sram_addr_in),
    .sram_din(sram_din_in),  // Renamed for clarity
    .sram_cen(sram_cen_in),
    .sram_wen(sram_wen_in),
    .sram_q(sram_q)
);

// ------------------------------------------------------------
// Barcode Decoder : read SRAM LSB and extract K, S, D
// ------------------------------------------------------------
Barcode_Decoder U_barcode (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_start(image_done),       // Trigger after image load
    .o_done(barcode_done),
    .o_valid(barcode_valid),
    .sram_addr(sram_addr_bar),
    .sram_cen(sram_cen_bar),
    .sram_wen(sram_wen_bar),
    .sram_q(sram_q),
    .o_kernel_size(kernel_size),
    .o_stride_size(stride_size),
    .o_dilation_size(dilation_size)
);

// ------------------------------------------------------------
// Arbitration Logic: Mux for SRAM signals
// ------------------------------------------------------------
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        decode_phase <= 1'b0;  // Start in input phase
    end else if (image_done) begin
        decode_phase <= 1'b1;  // Latch to decode phase once image is done
    end
end

always @(*) begin
    if (!decode_phase) begin  // Input load phase
        sram_addr_mux = sram_addr_in;
        sram_din_mux  = sram_din_in;
        sram_cen_mux  = sram_cen_in;
        sram_wen_mux  = sram_wen_in;
    end else begin  // Barcode decode phase
        sram_addr_mux = sram_addr_bar;
        sram_din_mux  = 8'd0;  // Barcode is read-only, so din irrelevant
        sram_cen_mux  = sram_cen_bar;
        sram_wen_mux  = sram_wen_bar;
    end
end

// ------------------------------------------------------------
// Output control logic (unchanged)
// ------------------------------------------------------------
assign o_out_addr1 = 12'd0;
assign o_out_addr2 = 12'd0;
assign o_out_addr3 = 12'd0;
assign o_out_addr4 = 12'd0;

assign o_out_data1 = kernel_size;     // kernel
assign o_out_data2 = stride_size;     // stride
assign o_out_data3 = dilation_size;   // dilation
assign o_out_data4 = 8'd0;            // reserved for convolution result

assign o_out_valid1 = barcode_valid;
assign o_out_valid2 = barcode_valid;
assign o_out_valid3 = barcode_valid;
assign o_out_valid4 = 1'b0;           // 未使用階段

assign o_exe_finish = barcode_done;

endmodule
