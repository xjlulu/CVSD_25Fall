// Fake syn_calc: 延遲 4 個 clock 後拉 done，一次一拍
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

    always @(posedge clk) begin
        if (!rstn) begin
            cnt       <= 3'd0;
            done      <= 1'b0;
            syndromes <= {2*T_MAX*M_MAX{1'b0}};
        end else begin
            if (start) begin
                cnt  <= 3'd4;   // 假設 latency = 4 cycles
                done <= 1'b0;
            end else if (cnt != 3'd0) begin
                cnt <= cnt - 3'd1;
                if (cnt == 3'd1) begin
                    done <= 1'b1;  // 拉一拍 done
                end else begin
                    done <= 1'b0;
                end
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
