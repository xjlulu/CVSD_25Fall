
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

// ============================================================
// 內部連線
// ============================================================
// SRAM 三方來源
wire [11:0] sram_addr_in,  sram_addr_bar,  sram_addr_eng;
wire [7:0]  sram_din_in;
wire        sram_cen_in,   sram_wen_in;
wire        sram_cen_bar,  sram_wen_bar;
wire        sram_cen_eng,  sram_wen_eng;

reg  [11:0] sram_addr_mux;
reg  [7:0]  sram_din_mux;
reg         sram_cen_mux, sram_wen_mux;

wire [7:0]  sram_q;

// Input/Decoder
wire 	    in_ready_img;
wire        image_done;
wire        dec_done, dec_valid;
wire [7:0]  kernel_size, stride_size, dilation_size;

// 權重載入/卷積引擎
wire        w_ready, w_done;
wire [71:0] weights72;

wire        eng_done;
wire [7:0]  eng_o1;
wire [11:0] eng_a1;
wire        eng_v1;

// ============================================================
// Phase FSM
// ============================================================
localparam PHASE_LOAD   = 2'd0; // 讀入影像寫 SRAM
localparam PHASE_DECODE = 2'd1; // 解碼 K/S/D
localparam PHASE_CONV   = 2'd2; // 卷積
localparam PHASE_DONE   = 2'd3; // 結束（包含非法參數直接結束）

reg [1:0] phase, nphase;

// 非法參數脈衝（在進 DONE 的第一拍輸出 0 並拉 valid）
reg inv_pulse;

// ============================================================
// SRAM 實例
// ============================================================
sram_4096x8 U_SRAM (
    .Q   (sram_q),
    .CLK (i_clk),
    .CEN (sram_cen_mux),
    .WEN (sram_wen_mux),
    .A   (sram_addr_mux),
    .D   (sram_din_mux)
);

// ============================================================
// Input Controller：只在 PHASE_LOAD 啟用、寫入影像
// ============================================================
Input_Controller U_in_ctrl (
    .i_clk      (i_clk),
    .i_rst_n    (i_rst_n),
    .i_in_valid (i_in_valid),
    .i_in_data  (i_in_data),
    .o_in_ready (in_ready_img),
    .image_done (image_done),

    .sram_addr  (sram_addr_in),
    .sram_din   (sram_din_in),
    .sram_cen   (sram_cen_in),
    .sram_wen   (sram_wen_in)
);

// ============================================================
// Barcode Decoder：只在 PHASE_DECODE 使用 SRAM
// ============================================================
Barcode_Decoder U_barcode (
    .i_clk          (i_clk),
    .i_rst_n        (i_rst_n),
    .i_start        (phase==PHASE_DECODE),  // 進入 decode 階段即開始
    .o_done         (dec_done),
    .o_valid        (dec_valid),

    .sram_addr      (sram_addr_bar),
    .sram_cen       (sram_cen_bar),
    .sram_wen       (sram_wen_bar),
    .sram_q         (sram_q),

    .o_kernel_size  (kernel_size),
    .o_stride_size  (stride_size),
    .o_dilation_size(dilation_size)
);

// ============================================================
// 權重載入（PHASE_CONV 初期收 3×32-bit → 9 bytes）
// ============================================================
Weight_Loader U_wload (
    .i_clk     (i_clk),
    .i_rst_n   (i_rst_n),
    .i_start   (phase==PHASE_CONV),   // 進入 CONV 就開始收
    .i_w_valid (i_in_valid),
    .i_w_data  (i_in_data),
    .o_w_ready (w_ready),
    .o_done    (w_done),
    .o_weights (weights72)
);

// ============================================================
// 卷積引擎（等 weights 準備好才開始運算）
// ============================================================
Conv_Engine U_eng (
    .i_clk          (i_clk),
    .i_rst_n        (i_rst_n),
    .i_start        ( (phase==PHASE_CONV) && w_done ),

    .i_stride_size  (stride_size),
    .i_dilation_size(dilation_size),

    .i_weights      (weights72),

    .sram_addr      (sram_addr_eng),
    .sram_cen       (sram_cen_eng),
    .sram_wen       (sram_wen_eng),
    .sram_q         (sram_q),

    .o_out_data1    (eng_o1),
    .o_out_addr1    (eng_a1),
    .o_out_valid1   (eng_v1),

    .o_done         (eng_done)
);

// ============================================================
// Phase 轉移與非法參數一拍脈衝
// ============================================================
always @(*) begin
    nphase = phase;
    case (phase)
        PHASE_LOAD:   if (image_done)                 nphase = PHASE_DECODE;
        PHASE_DECODE: if (dec_done &&  dec_valid)     nphase = PHASE_CONV;
                      else if (dec_done && !dec_valid) nphase = PHASE_DONE;
        PHASE_CONV:   if (eng_done)                   nphase = PHASE_DONE;
        PHASE_DONE:   nphase = PHASE_DONE;
        default:      nphase = PHASE_LOAD;
    endcase
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        phase     <= PHASE_LOAD;
        inv_pulse <= 1'b0;
    end else begin
        phase <= nphase;
        // 進入 DONE 的第一拍，如果是非法配置，發出一拍脈衝
        if ( (phase==PHASE_DECODE) && (nphase==PHASE_DONE) && (dec_done && !dec_valid) )
            inv_pulse <= 1'b1;
        else
            inv_pulse <= 1'b0;
    end
end

// ============================================================
// SRAM 仲裁
// ============================================================
always @(*) begin
    case (phase)
        PHASE_LOAD: begin
            sram_addr_mux = sram_addr_in;
            sram_din_mux  = sram_din_in;
            sram_cen_mux  = sram_cen_in;
            sram_wen_mux  = sram_wen_in;
        end
        PHASE_DECODE: begin
            sram_addr_mux = sram_addr_bar;
            sram_din_mux  = 8'd0;
            sram_cen_mux  = sram_cen_bar;
            sram_wen_mux  = sram_wen_bar;
        end
        PHASE_CONV: begin
            sram_addr_mux = sram_addr_eng;
            sram_din_mux  = 8'd0;
            sram_cen_mux  = sram_cen_eng;
            sram_wen_mux  = sram_wen_eng; // 讀：通常為 1
        end
        default: begin // DONE
            sram_addr_mux = 12'd0;
            sram_din_mux  = 8'd0;
            sram_cen_mux  = 1'b1;
            sram_wen_mux  = 1'b1;
        end
    endcase
end

// ============================================================
// o_in_ready 多工
//  - LOAD  階段：來自 Input_Controller
//  - CONV  階段：來自 Weight_Loader（收 3×32-bit 權重）
//  - 其他階段：0
// ============================================================
assign o_in_ready =
    (phase==PHASE_LOAD) ? in_ready_img :
    (phase==PHASE_CONV) ? w_ready      :
                          1'b0;

// ============================================================
// 輸出多工
//  - PHASE_DECODE：在 dec_done & dec_valid 的那一拍輸出 K/S/D 與三個 valid=1
//  - PHASE_CONV ：直接透穿 Conv_Engine 的通道1（其餘通道固定 0）
//  - PHASE_DONE 且非法：以 inv_pulse 送出一拍 0 並拉三個 valid=1
//  - o_exe_finish：在 DONE 階段為 1（不放下）
// ============================================================

// 預設
assign o_out_addr2  = 12'd0;
assign o_out_addr3  = 12'd0;
assign o_out_addr4  = 12'd0;
assign o_out_data4  = 8'd0;
assign o_out_valid4 = 1'b0;

// DECODE 階段：一拍脈衝（用 dec_done & dec_valid）
wire dec_pulse = (phase==PHASE_DECODE) && dec_done && dec_valid;

// 非法：一拍脈衝（進 DONE 第一拍）
wire inv_out_pulse = (phase==PHASE_DONE) && inv_pulse;

// CONV 階段：引擎輸出直通（其它通道固定 0）
wire use_conv = (phase==PHASE_CONV);

assign o_out_valid1 = dec_pulse | inv_out_pulse | (use_conv ? eng_v1 : 1'b0);
assign o_out_valid2 = dec_pulse | inv_out_pulse; // 只在 Stage1 或非法一拍會拉
assign o_out_valid3 = dec_pulse | inv_out_pulse;

assign o_out_data1  = inv_out_pulse ? 8'd0 :
                      dec_pulse     ? kernel_size :
                      use_conv      ? eng_o1 :
                                      8'd0;

assign o_out_data2  = inv_out_pulse ? 8'd0 :
                      dec_pulse     ? stride_size : 8'd0;

assign o_out_data3  = inv_out_pulse ? 8'd0 :
                      dec_pulse     ? dilation_size : 8'd0;

assign o_out_addr1  = use_conv ? eng_a1 : 12'd0;

// 結束旗標：一旦進入 DONE 就維持 1
assign o_exe_finish = (phase==PHASE_DONE);

endmodule
