module sort16_desc (
    input              clk,
    input              rst,
    input              start,
    input  [127:0]     data_in,    // 16 bytes
    output reg         done,
    output reg [127:0] data_out
);

reg        running;
reg        out_phase;             // 新增：專門用來在下一拍打包輸出
reg [3:0]  i, j;
reg [7:0]  arr [0:15];
integer k;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        running   <= 1'b0;
        out_phase <= 1'b0;
        done      <= 1'b0;
        i         <= 4'd0;
        j         <= 4'd0;
        data_out  <= 128'd0;
    end else begin
        done <= 1'b0;  // 預設

        // 第一優先：輸出階段
        if (out_phase) begin
            // 這一拍 arr 已經是完全排序好的結果
            data_out[127:120] <= arr[0];
            data_out[119:112] <= arr[1];
            data_out[111:104] <= arr[2];
            data_out[103:96]  <= arr[3];
            data_out[95:88]   <= arr[4];
            data_out[87:80]   <= arr[5];
            data_out[79:72]   <= arr[6];
            data_out[71:64]   <= arr[7];
            data_out[63:56]   <= arr[8];
            data_out[55:48]   <= arr[9];
            data_out[47:40]   <= arr[10];
            data_out[39:32]   <= arr[11];
            data_out[31:24]   <= arr[12];
            data_out[23:16]   <= arr[13];
            data_out[15:8]    <= arr[14];
            data_out[7:0]     <= arr[15];

            done      <= 1'b1;   // 拉 1 拍
            out_phase <= 1'b0;
        end
        // 接著：起始載入
        else if (start && !running) begin
            // 把 16 個 byte 讀進來：MSB -> LSB
            arr[0]  <= data_in[127:120];
            arr[1]  <= data_in[119:112];
            arr[2]  <= data_in[111:104];
            arr[3]  <= data_in[103:96];
            arr[4]  <= data_in[95:88];
            arr[5]  <= data_in[87:80];
            arr[6]  <= data_in[79:72];
            arr[7]  <= data_in[71:64];
            arr[8]  <= data_in[63:56];
            arr[9]  <= data_in[55:48];
            arr[10] <= data_in[47:40];
            arr[11] <= data_in[39:32];
            arr[12] <= data_in[31:24];
            arr[13] <= data_in[23:16];
            arr[14] <= data_in[15:8];
            arr[15] <= data_in[7:0];

            i       <= 4'd0;
            j       <= 4'd0;
            running <= 1'b1;
        end
        // 排序中
        else if (running) begin
            // bubble sort: 每 cycle 比較 arr[j] 與 arr[j+1]
            if (arr[j] < arr[j+1]) begin
                // descending: 大的往前
                {arr[j], arr[j+1]} <= {arr[j+1], arr[j]};
            end

            if (j == (4'd14 - i)) begin
                j <= 4'd0;
                if (i == 4'd14) begin
                    // 排完所有 pass，下一拍進入 out_phase
                    running   <= 1'b0;
                    out_phase <= 1'b1;
                end else begin
                    i <= i + 4'd1;
                end
            end else begin
                j <= j + 4'd1;
            end
        end
    end
end

endmodule
