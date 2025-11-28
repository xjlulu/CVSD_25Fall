// Fake syn_calc: 延遲 4 個 clock 後拉 done，一拍 pulse
// 允許 testbench override syndrome
module syn_calc
#(
    parameter integer N_MAX = 1023,
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     start,
    input  wire [9:0]               n,
    input  wire [3:0]               t,
    input  wire [3:0]               m,
    input  wire [N_MAX-1:0]         hard_bits,

    output reg                      done,
    output reg [2*T_MAX*M_MAX-1:0]  syndromes
);

    reg [2:0] cnt;

    // ======================================================
    // ★ TB override register ★
    // ======================================================
    reg [2*T_MAX*M_MAX-1:0] syndrome_override;

    // TB 設定 syndrome 用
    task tb_set_syndrome(input [2*T_MAX*M_MAX-1:0] val);
    begin
        syndrome_override = val;
    end
    endtask

    // ======================================================
    // Reset + 延遲流程（完全保留你的寫法）
    // ======================================================
    always @(posedge clk) begin
        if (!rstn) begin
            cnt              <= 3'd0;
            done             <= 1'b0;
            syndromes        <= {2*T_MAX*M_MAX{1'b0}};
            syndrome_override<= {2*T_MAX*M_MAX{1'b0}};  // default
        end else begin

            if (start) begin
                cnt       <= 3'd4;    // 你原本的 latency
                done      <= 1'b0;
            end 

            else if (cnt != 3'd0) begin
                cnt <= cnt - 3'd1;

                if (cnt == 3'd1) begin
                    done      <= 1'b1;
                    syndromes <= syndrome_override;  // ★ TB 控制輸出 ★
                end else begin
                    done <= 1'b0;
                end
            end 

            else begin
                done <= 1'b0;
            end

        end
    end

endmodule
