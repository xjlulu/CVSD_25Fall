// Fake berlekamp: 延遲 4 個 clock 後拉 done，failure=0, degree=0, sigma=1
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

    always @(posedge clk) begin
        if (!rstn) begin
            cnt     <= 3'd0;
            done    <= 1'b0;
            failure <= 1'b0;
            degree  <= 4'd0;
            sigma   <= {(T_MAX+1)*M_MAX{1'b0}};
        end else begin
            if (start) begin
                cnt     <= 3'd4;
                done    <= 1'b0;
                failure <= 1'b0;
                degree  <= 4'd0;
                sigma   <= {{((T_MAX+1)*M_MAX-1){1'b0}}, 1'b1};  // sigma_0 = 1, 其他 0
            end else if (cnt != 3'd0) begin
                cnt <= cnt - 3'd1;
                if (cnt == 3'd1) begin
                    done <= 1'b1;
                end else begin
                    done <= 1'b0;
                end
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
