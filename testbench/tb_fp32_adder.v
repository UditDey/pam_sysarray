`include "fp32_adder.v"

module tb_fp32_adder;

    reg  [31:0] a, b;
    wire [31:0] out;
    integer pass_count, fail_count;

    fp32_adder uut (.a(a), .b(b), .out(out));

    task check(
        input [31:0] in_a,
        input [31:0] in_b,
        input [31:0] expected,
        input [8*32-1:0] label
    );
        begin
            a = in_a;
            b = in_b;
            #10;
            if (out === expected) begin
                $display("  PASS  %-28s  a=%h b=%h  out=%h", label, in_a, in_b, out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-28s  a=%h b=%h  out=%h (expected %h)", label, in_a, in_b, out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // fp32 cheat sheet:
    //   0.0    = 0x00000000
    //   0.125  = 0x3E000000    0.25 = 0x3E800000    0.5  = 0x3F000000
    //   0.75   = 0x3F400000    1.0  = 0x3F800000    1.5  = 0x3FC00000
    //   2.0    = 0x40000000    2.25 = 0x40100000    2.5  = 0x40200000
    //   3.0    = 0x40400000    4.0  = 0x40800000    5.0  = 0x40A00000
    //  -0.25   = 0xBE800000   -1.0  = 0xBF800000   -1.5  = 0xBFC00000
    //  -2.0    = 0xC0000000   -2.5  = 0xC0200000   -3.0  = 0xC0400000

    initial begin
        pass_count = 0;
        fail_count = 0;
        $display("=== FP32 Adder Testbench ===");
        $display("");

        // ---- Whole number addition ----
        check(32'h3F800000, 32'h3F800000, 32'h40000000, "1.0 + 1.0 = 2.0");
        check(32'h40000000, 32'h3F800000, 32'h40400000, "2.0 + 1.0 = 3.0");
        check(32'h40400000, 32'h3F800000, 32'h40800000, "3.0 + 1.0 = 4.0");

        // ---- Fraction addition ----
        check(32'h3FC00000, 32'h3F400000, 32'h40100000, "1.5 + 0.75 = 2.25");
        check(32'h3F000000, 32'h3E800000, 32'h3F400000, "0.5 + 0.25 = 0.75");
        check(32'h3E000000, 32'h3E000000, 32'h3E800000, "0.125 + 0.125 = 0.25");

        // ---- Subtraction (different signs) ----
        check(32'h40400000, 32'hBF800000, 32'h40000000, "3.0 + (-1.0) = 2.0");
        check(32'h3F800000, 32'hC0400000, 32'hC0000000, "1.0 + (-3.0) = -2.0");
        check(32'h3F400000, 32'hBE800000, 32'h3F000000, "0.75 + (-0.25) = 0.5");

        // ---- Exact cancellation ----
        check(32'h3F800000, 32'hBF800000, 32'h00000000, "1.0 + (-1.0) = 0.0");
        check(32'h40A00000, 32'hC0A00000, 32'h00000000, "5.0 + (-5.0) = 0.0");

        // ---- Negative addition ----
        check(32'hC0200000, 32'hBFC00000, 32'hC0800000, "-2.5 + (-1.5) = -4.0");

        // ---- Zero operand ----
        check(32'h00000000, 32'h40A00000, 32'h40A00000, "0.0 + 5.0 = 5.0");
        check(32'h40A00000, 32'h00000000, 32'h40A00000, "5.0 + 0.0 = 5.0");

        $display("");
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

endmodule
