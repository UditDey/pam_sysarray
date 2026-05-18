// ============================================================
// FP32 Adder — Combinational
//   - Round toward zero (truncation)
//   - Flush denormals to zero
//   - No inf/NaN handling
// ============================================================

module fp32_adder (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] out
);

    // ---- Unpack ----
    wire        sign_a  = a[31];
    wire        sign_b  = b[31];
    wire [7:0]  exp_a   = a[30:23];
    wire [7:0]  exp_b   = b[30:23];

    // Mantissa with implicit leading 1 (flush denormals: exp==0 → mant=0)
    wire [23:0] mant_a  = (exp_a == 8'd0) ? 24'd0 : {1'b1, a[22:0]};
    wire [23:0] mant_b  = (exp_b == 8'd0) ? 24'd0 : {1'b1, b[22:0]};

    wire zero_a = (exp_a == 8'd0);
    wire zero_b = (exp_b == 8'd0);

    // ---- Determine larger magnitude ----
    wire a_ge_b = (exp_a > exp_b) ||
                  ((exp_a == exp_b) && (mant_a >= mant_b));

    wire        sign_lg = a_ge_b ? sign_a : sign_b;
    wire        sign_sm = a_ge_b ? sign_b : sign_a;
    wire [7:0]  exp_lg  = a_ge_b ? exp_a  : exp_b;
    wire [7:0]  exp_sm  = a_ge_b ? exp_b  : exp_a;
    wire [23:0] mant_lg = a_ge_b ? mant_a : mant_b;
    wire [23:0] mant_sm = a_ge_b ? mant_b : mant_a;

    // ---- Alignment ----
    wire [7:0]  exp_diff    = exp_lg - exp_sm;
    wire [23:0] mant_sm_al  = (exp_diff > 8'd24) ? 24'd0
                                                  : (mant_sm >> exp_diff);

    // ---- Effective add or subtract ----
    wire eff_sub = sign_lg ^ sign_sm;

    wire [24:0] mant_raw = eff_sub
        ? ({1'b0, mant_lg} - {1'b0, mant_sm_al})
        : ({1'b0, mant_lg} + {1'b0, mant_sm_al});

    // ---- Normalize ----
    reg  [4:0]  lzc;        // leading zero count (bits below bit 23)
    reg  [23:0] norm_mant;
    reg  [7:0]  exp_out;
    integer i;

    always @(*) begin
        if (zero_a & zero_b) begin
            // Both zero
            out = 32'd0;

        end else if (zero_a) begin
            out = b;

        end else if (zero_b) begin
            out = a;

        end else if (mant_raw == 25'd0) begin
            // Exact cancellation (e.g. 1.0 + -1.0)
            out = 32'd0;

        end else if (mant_raw[24]) begin
            // ---- Carry-out from addition: shift right 1, exp + 1 ----
            exp_out  = exp_lg + 8'd1;
            out      = {sign_lg, exp_out, mant_raw[23:1]};  // RTZ: drop LSB

        end else begin
            // ---- Find leading-one position in mant_raw[23:0] ----
            // Scan from LSB upward; last hit = highest set bit.
            // lzc = number of leading zeros above that bit (relative to bit 23).
            lzc = 5'd24;
            for (i = 0; i <= 23; i = i + 1) begin
                if (mant_raw[i])
                    lzc = 23 - i;
            end

            // Shift mantissa left to put leading 1 at bit 23
            norm_mant = mant_raw[23:0] << lzc;

            // Check exponent underflow (result would be denormal → flush)
            if (exp_lg > {3'd0, lzc}) begin
                exp_out = exp_lg - {3'd0, lzc};
                out     = {sign_lg, exp_out, norm_mant[22:0]};
            end else begin
                // Underflow → zero
                out = 32'd0;
            end
        end
    end

endmodule
