// Fake chien: 延遲 4 個 clock 後拉 done，err_vec 可由 TB override
module chien
#(
    parameter integer N_MAX = 1023,
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                       clk,
    input  wire                       rstn,
    input  wire                       start,
    input  wire [9:0]                 n,
    input  wire [3:0]                 m,
    input  wire [3:0]                 degree,
    input  wire [(T_MAX+1)*M_MAX-1:0] sigma,

    output reg                        done,
    output reg [N_MAX-1:0]            err_vec
);

    // ================================================
    // TB override error vector（額外加入）
    // ================================================
    reg [N_MAX-1:0] err_override;

    // TB 呼叫此 task 來設定 err_vec
    task tb_set_chien(input [N_MAX-1:0] val);
    begin
        err_override = val;
    end
    endtask

    // ================================================
    // 你的原本延遲 4 個 clock 的流程（完全保留）
    // ================================================
    reg [2:0] cnt;

    always @(posedge clk) begin
        if (!rstn) begin
            cnt       <= 3'd0;
            done      <= 1'b0;
            err_vec   <= {N_MAX{1'b0}};
            err_override <= {N_MAX{1'b0}};   // reset
        end else begin
            if (start) begin
                cnt     <= 3'd4;             // 你原本的計數方式
                done    <= 1'b0;
                err_vec <= {N_MAX{1'b0}};    // 開始時清空
            end 
            else if (cnt != 3'd0) begin
                cnt <= cnt - 3'd1;

                if (cnt == 3'd1) begin
                    done    <= 1'b1;
                    err_vec <= err_override; // ★ TB 控制的 erro_vec ★
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
