`include "pam_mul_bf16.v"
`include "fp32_adder.v"
`include "pam_mac_pe.v"
`include "pam_systolic_array.v"

module tb_pam_systolic_array;

    // ================================================================
    // 2x2 test instance
    // ================================================================
    localparam N2 = 2;

    reg         clk, rst;
    reg         ld_w;
    reg  [15:0] w_data;
    reg  [0:0]  w_row, w_col;           // $clog2(2) = 1 bit
    reg  [N2*16-1:0] act_in;
    wire [N2*32-1:0] psum_out;

    pam_systolic_array #(.N(N2)) u_2x2 (
        .clk          (clk),
        .rst          (rst),
        .load_weight  (ld_w),
        .weight_data  (w_data),
        .weight_row   (w_row),
        .weight_col   (w_col),
        .act_in_flat  (act_in),
        .psum_out_flat(psum_out)
    );

    // Clock
    initial clk = 0;
    always #10 clk = ~clk;

    // Helpers to read bottom outputs
    wire [31:0] bot0 = psum_out[31:0];
    wire [31:0] bot1 = psum_out[63:32];

    integer pass_count, fail_count;

    task load_weight_2x2(
        input [0:0] row,
        input [0:0] col,
        input [15:0] wval
    );
        begin
            ld_w = 1; w_row = row; w_col = col; w_data = wval;
            @(posedge clk); #1;
            ld_w = 0;
        end
    endtask

    task check2(
        input [31:0] exp_c0,
        input [31:0] exp_c1,
        input [8*48-1:0] label
    );
        begin
            if (bot0 === exp_c0 && bot1 === exp_c1) begin
                $display("  PASS  %-40s  c0=%h c1=%h", label, bot0, bot1);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-40s", label);
                $display("        c0=%h (exp %h)  c1=%h (exp %h)",
                         bot0, exp_c0, bot1, exp_c1);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // bf16: 1.0=3F80  2.0=4000
    // fp32: 4.0=40800000  5.0=40A00000

    initial begin
        pass_count = 0;
        fail_count = 0;
        $display("=== Systolic Array Testbench ===");
        $display("");

        // ---- Reset ----
        rst = 1; ld_w = 0; w_data = 0; w_row = 0; w_col = 0;
        act_in = 0;
        @(posedge clk); #1;
        rst = 0;

        // ---- 2x2 Test: C = A * W ----
        //   W = [1  2]    A = [2  1]    C = [4  5]
        //       [2  1]        [1  2]        [5  4]
        //
        //   PE[r][c] holds W[r][c].
        //   Row r receives column r of A.
        //   Partial sums drain from bottom.

        $display("  Loading weights W = [[1,2],[2,1]]");
        load_weight_2x2(0, 0, 16'h3F80);  // W[0][0] = 1.0
        load_weight_2x2(0, 1, 16'h4000);  // W[0][1] = 2.0
        load_weight_2x2(1, 0, 16'h4000);  // W[1][0] = 2.0
        load_weight_2x2(1, 1, 16'h3F80);  // W[1][1] = 1.0
        $display("");

        // ---- Feed activations ----
        // t=0: row0 gets A[0][0]=2.0, row1 gets A[0][1]=1.0
        //      (row1 value enters skew register, won't reach PE yet)
        $display("  Feeding activations, A = [[2,1],[1,2]]");

        act_in = {16'h3F80, 16'h4000};    // {row1=1.0, row0=2.0}
        @(posedge clk); #1;
        // t=0 outputs: nothing ready yet
        check2(32'h0, 32'h0,              "t=0: no output yet");

        // t=1: row0 gets A[1][0]=1.0, row1 gets A[1][1]=2.0
        act_in = {16'h4000, 16'h3F80};    // {row1=2.0, row0=1.0}
        @(posedge clk); #1;
        // C[0][0]=4.0 drains from col 0
        check2(32'h40800000, 32'h0,       "t=1: C[0][0]=4.0");

        // t=2: no more data
        act_in = 0;
        @(posedge clk); #1;
        // C[1][0]=5.0 from col 0, C[0][1]=5.0 from col 1
        check2(32'h40A00000, 32'h40A00000, "t=2: C[1][0]=5.0, C[0][1]=5.0");

        // t=3: drain tail
        act_in = 0;
        @(posedge clk); #1;
        // C[1][1]=4.0 from col 1
        check2(32'h0, 32'h40800000,       "t=3: C[1][1]=4.0");

        $display("");
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

endmodule
