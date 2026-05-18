`include "pam_mul_bf16.v"

module tb_pam_mul_bf16;

    reg  [15:0] a, b;
    wire [31:0] out;
    integer pass_count, fail_count;

    pam_mul_bf16 uut (.a(a), .b(b), .out(out));

    task check(
        input [15:0] in_a,
        input [15:0] in_b,
        input [31:0] expected,
        input [8*32-1:0] label   // string label
    );
        begin
            a = in_a;
            b = in_b;
            #10;
            if (out === expected) begin
                $display("  PASS  %-24s  a=%h b=%h  out=%h", label, in_a, in_b, out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-24s  a=%h b=%h  out=%h (expected %h)", label, in_a, in_b, out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // bf16 encodings for reference:
    //   0.5  = 0x3F00    1.0 = 0x3F80    1.5 = 0x3FC0
    //   2.0  = 0x4000    3.0 = 0x4040    4.0 = 0x4080
    //  -1.0  = 0xBF80   -2.0 = 0xC000
    //   0.0  = 0x0000
    //
    // fp32 encodings:
    //   1.0  = 0x3F80_0000   2.0 = 0x4000_0000   4.0 = 0x4080_0000
    //   6.0  = 0x40C0_0000   8.0 = 0x4100_0000
    //  -2.0  = 0xC000_0000   0.0 = 0x0000_0000

    initial begin
        pass_count = 0;
        fail_count = 0;
        $display("=== PAM MUL BF16 Testbench ===");
        $display("");

        // --- Exact cases (powers of 2 are exact in PAM) ---
        check(16'h3F80, 16'h3F80, 32'h3F80_0000, "1.0 * 1.0 = 1.0");
        check(16'h4000, 16'h4000, 32'h4080_0000, "2.0 * 2.0 = 4.0");
        check(16'h3F00, 16'h4000, 32'h3F80_0000, "0.5 * 2.0 = 1.0");
        check(16'h4000, 16'h4040, 32'h40C0_0000, "2.0 * 3.0 = 6.0");

        // --- Sign handling ---
        check(16'hBF80, 16'h4000, 32'hC000_0000, "-1.0 * 2.0 = -2.0");
        check(16'hBF80, 16'hBF80, 32'h3F80_0000, "-1.0 * -1.0 = 1.0");

        // --- PAM approximate case ---
        // 3.0 * 3.0: PAM gives 8.0 (actual 9.0)
        // 0x4040 + 0x4040 - 0x3F80 = 0x4100 → bf16 8.0
        check(16'h4040, 16'h4040, 32'h4100_0000, "3.0 * 3.0 ~ 8.0");

        // --- Fractional cases ---
        // bf16 encodings:
        //   0.25 = 0x3E80   0.75 = 0x3F40   0.125 = 0x3E00
        //   1.25 = 0x3FA0   1.75 = 0x3FE0

        // 0.25 * 0.5: PAM = 0.125 (exact, both power-of-2)
        check(16'h3E80, 16'h3F00, 32'h3E00_0000, "0.25 * 0.5 = 0.125");

        // 0.75 * 0.75: PAM = 0.5 (true = 0.5625, ~11% err)
        check(16'h3F40, 16'h3F40, 32'h3F00_0000, "0.75*0.75 ~0.5");

        // 1.25 * 1.5: PAM = 1.75 (true = 1.875, ~6.7% err)
        check(16'h3FA0, 16'h3FC0, 32'h3FE0_0000, "1.25*1.5 ~1.75");

        // 0.75 * 1.25: PAM = 0.875 (true = 0.9375, ~6.7% err)
        check(16'h3F40, 16'h3FA0, 32'h3F60_0000, "0.75*1.25 ~0.875");

        // 1.25 * 1.25: PAM = 1.5 (true = 1.5625, ~4% err)
        check(16'h3FA0, 16'h3FA0, 32'h3FC0_0000, "1.25*1.25 ~1.5");

        // 1.75 * 0.25: PAM = 0.4375 (exact! mantissa bits carry cleanly)
        check(16'h3FE0, 16'h3E80, 32'h3EE0_0000, "1.75*0.25 =0.4375");

        // -0.75 * 2.0: PAM = -1.5 (exact, one operand is power-of-2)
        check(16'hBF40, 16'h4000, 32'hBFC0_0000, "-0.75*2.0 =-1.5");

        // --- Zero cases ---
        check(16'h0000, 16'h4000, 32'h0000_0000, "0.0 * 2.0 = 0.0");
        check(16'h4000, 16'h0000, 32'h0000_0000, "2.0 * 0.0 = 0.0");
        check(16'h0000, 16'h0000, 32'h0000_0000, "0.0 * 0.0 = 0.0");

        $display("");
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end

endmodule
