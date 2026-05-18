`include "pam_mul_bf16.v"
`include "fp32_adder.v"
`include "pam_mac_pe.v"

module tb_pam_mac_pe;

    reg         clk, rst, load_weight;
    reg  [15:0] weight_in, act_in;
    reg  [31:0] psum_in;
    wire [15:0] act_out;
    wire [31:0] psum_out;
    integer pass_count, fail_count;

    pam_mac_pe uut (
        .clk(clk), .rst(rst), .load_weight(load_weight),
        .weight_in(weight_in), .act_in(act_in), .psum_in(psum_in),
        .act_out(act_out), .psum_out(psum_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task check(
        input [31:0] exp_psum,
        input [15:0] exp_act,
        input [8*48-1:0] label
    );
        begin
            if (psum_out === exp_psum && act_out === exp_act) begin
                $display("  PASS  %-40s  psum=%h act=%h", label, psum_out, act_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-40s", label);
                $display("        psum=%h (exp %h)  act=%h (exp %h)",
                         psum_out, exp_psum, act_out, exp_act);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // bf16:  0.5=3F00  1.0=3F80  1.5=3FC0  2.0=4000  3.0=4040
    // fp32:  0.0=00000000  1.0=3F800000  2.0=40000000  3.0=40400000
    //        4.0=40800000  6.0=40C00000

    initial begin
        pass_count = 0;
        fail_count = 0;
        $display("=== PAM MAC PE Testbench ===");
        $display("  Weight = 2.0 (bf16 0x4000)");
        $display("");

        // ---- Reset ----
        rst = 1; load_weight = 0;
        weight_in = 16'h0; act_in = 16'h0; psum_in = 32'h0;
        @(posedge clk); #1;

        // ---- Load weight = 2.0 ----
        rst = 0; load_weight = 1; weight_in = 16'h4000;
        act_in = 16'h0; psum_in = 32'h0;
        @(posedge clk); #1;
        load_weight = 0;

        // ---- Cycle 1: act=3.0, psum_in=0 ----
        //   PAM(3.0, 2.0) = 6.0,  6.0 + 0.0 = 6.0
        act_in = 16'h4040; psum_in = 32'h00000000;
        @(posedge clk); #1;
        check(32'h40C00000, 16'h4040, "PAM(3.0,2.0)+0.0 = 6.0, act=3.0");

        // ---- Cycle 2: act=1.5, psum_in=0 ----
        //   PAM(1.5, 2.0) = 3.0,  3.0 + 0.0 = 3.0
        act_in = 16'h3FC0; psum_in = 32'h00000000;
        @(posedge clk); #1;
        check(32'h40400000, 16'h3FC0, "PAM(1.5,2.0)+0.0 = 3.0, act=1.5");

        // ---- Cycle 3: act=1.0, psum_in=4.0 (from PE above) ----
        //   PAM(1.0, 2.0) = 2.0,  2.0 + 4.0 = 6.0
        act_in = 16'h3F80; psum_in = 32'h40800000;
        @(posedge clk); #1;
        check(32'h40C00000, 16'h3F80, "PAM(1.0,2.0)+4.0 = 6.0, act=1.0");

        // ---- Cycle 4: act=0.5, psum_in=1.0 ----
        //   PAM(0.5, 2.0) = 1.0,  1.0 + 1.0 = 2.0
        act_in = 16'h3F00; psum_in = 32'h3F800000;
        @(posedge clk); #1;
        check(32'h40000000, 16'h3F00, "PAM(0.5,2.0)+1.0 = 2.0, act=0.5");

        // ---- Cycle 5: act=0 (idle), psum_in=0 ----
        //   PAM(0, 2.0) = 0,  0 + 0 = 0
        act_in = 16'h0000; psum_in = 32'h00000000;
        @(posedge clk); #1;
        check(32'h00000000, 16'h0000, "PAM(0,2.0)+0 = 0, act=0 (idle)");

        $display("");
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

endmodule
