// Fake chien: 延遲 4 個 clock 後拉 done，err_vec 全 0
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

    reg [2:0] cnt;

    always @(posedge clk) begin
        if (!rstn) begin
            cnt     <= 3'd0;
            done    <= 1'b0;
            err_vec <= {N_MAX{1'b0}};
        end else begin
            if (start) begin
                cnt     <= 3'd4;
                done    <= 1'b0;
                err_vec <= {N_MAX{1'b0}};
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
