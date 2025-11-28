// Fake berlekamp: 延遲 4 clock 後拉 done
// 允許 TB override failure / degree / sigma
module berlekamp
#(
    parameter integer T_MAX = 4,
    parameter integer M_MAX = 10
)
(
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     start,
    input  wire [3:0]               t,
    input  wire [3:0]               m,
    input  wire [2*T_MAX*M_MAX-1:0] syndromes,

    output reg                      done,
    output reg                      failure,
    output reg [3:0]                degree,
    output reg [(T_MAX+1)*M_MAX-1:0] sigma
);

    reg [2:0] cnt;

    // ============================================================
    // ★★★ TB override registers ★★★
    // ============================================================
    reg fail_override;
    reg [3:0] degree_override;
    reg [(T_MAX+1)*M_MAX-1:0] sigma_override;

    // testbench 設定 override 用的 task
    task tb_set_ber(input in_fail, input [3:0] in_degree);
    begin
        fail_override   = in_fail;
        degree_override = in_degree;
    end
    endtask

    task tb_set_sigma(input [(T_MAX+1)*M_MAX-1:0] in_sigma);
    begin
        sigma_override = in_sigma;
    end
    endtask

    // ============================================================
    // Reset + 延遲 4 拍流程保持不變
    // ============================================================
    always @(posedge clk) begin
        if (!rstn) begin
            cnt     <= 3'd0;
            done    <= 1'b0;
            failure <= 1'b0;
            degree  <= 4'd0;
            sigma   <= {((T_MAX+1)*M_MAX){1'b0}};

            // default override
            fail_override   <= 1'b0;
            degree_override <= 4'd0;
            sigma_override  <= {{((T_MAX+1)*M_MAX-1){1'b0}},1'b1}; // 預設 sigma_0 = 1
        end 
        else begin

            if (start) begin
                // 重新開始計時
                cnt     <= 3'd4;
                done    <= 1'b0;

                // 每次 start 時讀取 override 值
                failure <= fail_override;
                degree  <= degree_override;
                sigma   <= sigma_override;
            end 

            else if (cnt != 3'd0) begin
                cnt <= cnt - 3'd1;

                if (cnt == 3'd1) begin
                    done <= 1'b1;  // 第 4 拍輸出
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
