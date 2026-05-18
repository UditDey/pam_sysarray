// ============================================================
// PAM Multiplier (bfloat16 × bfloat16 → float32)
// Combinational — no clock needed
//
// PAM trick: IEEE float bits ≈ log2(|x|) in fixed-point.
//   log2(a*b) = log2(a) + log2(b)
//   So: I_c = I_a + I_b - Bias
//   where Bias = 0x3F80 (bf16 encoding of 1.0)
//
// Sign handled separately via XOR.
// No denormals — flush to zero. RTZ.
// ============================================================

module pam_mul_bf16 (
    input  wire [15:0] a,      // bf16 operand A
    input  wire [15:0] b,      // bf16 operand B
    output wire [31:0] out     // fp32 result
);

    // ---- 1. Signs ----
    wire sign_a = a[15];
    wire sign_b = b[15];
    wire sign_c = sign_a ^ sign_b;

    // ---- 2. Magnitudes (exp + mantissa, 15 bits) ----
    wire [14:0] mag_a = a[14:0];
    wire [14:0] mag_b = b[14:0];

    // ---- 3. Zero detection ----
    // If either operand is ±0, result must be 0
    wire zero_a = (mag_a == 15'b0);
    wire zero_b = (mag_b == 15'b0);
    wire either_zero = zero_a | zero_b;

    // ---- 4. PAM core: add magnitudes, subtract bias ----
    // mag_a max = 0x7F80 (inf), so sum max = 0xFF00, fits in 16 bits
    wire [15:0] mag_sum = {1'b0, mag_a} + {1'b0, mag_b};

    // Underflow: sum < bias (0x3F80)
    wire underflow = (mag_sum < 16'h3F80);

    wire [15:0] mag_diff = mag_sum - 16'h3F80;

    // Overflow: result > 0x7F80 (bf16 inf)
    wire overflow = (~underflow) & (mag_diff > 16'h7F80);

    // Flush denormals: if exponent field is 0 (mag < 0x0080) → zero
    wire denormal = (~underflow) & (mag_diff < 16'h0080);

    // ---- 5. Select final magnitude ----
    wire [14:0] mag_c = (either_zero | underflow | denormal) ? 15'b0  :
                         overflow                             ? 15'h7F80 :
                         mag_diff[14:0];

    // ---- 6. Assemble bf16 result ----
    // If magnitude is zero, force sign to 0 (positive zero)
    wire [15:0] result_bf16 = (mag_c == 15'b0) ? 16'h0000
                                                : {sign_c, mag_c};

    // ---- 7. bf16 → fp32 conversion ----
    // bf16 and fp32 share the same sign + 8-bit exponent + same bias (127).
    // bf16 has 7 mantissa bits, fp32 has 23.  Just pad 16 zeros.
    assign out = {result_bf16, 16'b0};

endmodule
