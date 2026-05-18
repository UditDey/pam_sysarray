// ============================================================
// PAM Systolic Array (NxN, weight-stationary)
//
// Computes C = A × W  where W is preloaded into PEs.
//   PE[k][n] holds W[k][n]
//   Row k receives column k of A (skewed by k cycles)
//   Partial sums flow top→bottom in each column
//   Result C[m][n] drains from bottom of column n
//
// Activation skew: row i input is delayed by i cycles so
// the diagonal wavefront aligns A[m][k] with W[k][n].
//
// Weight loading: addressed by (weight_row, weight_col).
// ============================================================

module pam_systolic_array #(
    parameter N = 4
)(
    input  wire        clk,
    input  wire        rst,

    // ---- Weight loading (one PE at a time) ----
    input  wire        load_weight,
    input  wire [15:0] weight_data,
    input  wire [$clog2(N)-1:0] weight_row,
    input  wire [$clog2(N)-1:0] weight_col,

    // ---- Activation inputs (one bf16 per row, before skew) ----
    input  wire [N*16-1:0] act_in_flat,

    // ---- Partial-sum outputs (one fp32 per column, from bottom row) ----
    output wire [N*32-1:0] psum_out_flat
);

    // ================================================================
    // Internal wiring
    // ================================================================
    //   act_h[row][col]  : horizontal activation between PEs
    //                      act_h[row][0] = skewed input, act_h[row][N] = unused tail
    //   psum_v[row][col] : vertical partial sum between PEs
    //                      psum_v[0][col] = 0 (top), psum_v[N][col] = output (bottom)
    // ================================================================

    wire [15:0] act_skewed [0:N-1];
    wire [15:0] act_h      [0:N-1][0:N];
    wire [31:0] psum_v     [0:N]  [0:N-1];

    // ================================================================
    // Activation skew registers
    //   Row 0: 0 delay (straight through)
    //   Row i: i-stage shift register
    // ================================================================

    genvar r;
    generate
        for (r = 0; r < N; r = r + 1) begin : skew_gen
            if (r == 0) begin : no_skew
                assign act_skewed[0] = act_in_flat[15:0];
            end else begin : do_skew
                reg [15:0] sr [0:r-1];
                integer s;

                always @(posedge clk) begin
                    if (rst) begin
                        for (s = 0; s < r; s = s + 1)
                            sr[s] <= 16'd0;
                    end else begin
                        sr[0] <= act_in_flat[r*16 +: 16];
                        for (s = 1; s < r; s = s + 1)
                            sr[s] <= sr[s-1];
                    end
                end

                assign act_skewed[r] = sr[r-1];
            end
        end
    endgenerate

    // ================================================================
    // Top-row partial sums = 0, left-column activations = skewed inputs
    // ================================================================

    genvar c;
    generate
        for (c = 0; c < N; c = c + 1) begin : top_psum
            assign psum_v[0][c] = 32'd0;
        end
        for (r = 0; r < N; r = r + 1) begin : left_act
            assign act_h[r][0] = act_skewed[r];
        end
    endgenerate

    // ================================================================
    // NxN PE grid
    // ================================================================

    generate
        for (r = 0; r < N; r = r + 1) begin : pe_row
            for (c = 0; c < N; c = c + 1) begin : pe_col

                wire pe_load = load_weight
                             & (weight_row == r[$clog2(N)-1:0])
                             & (weight_col == c[$clog2(N)-1:0]);

                pam_mac_pe u_pe (
                    .clk         (clk),
                    .rst         (rst),
                    .load_weight (pe_load),
                    .weight_in   (weight_data),
                    .act_in      (act_h[r][c]),
                    .psum_in     (psum_v[r][c]),
                    .act_out     (act_h[r][c+1]),
                    .psum_out    (psum_v[r+1][c])
                );

            end
        end
    endgenerate

    // ================================================================
    // Bottom-row outputs → flat output bus
    // ================================================================

    generate
        for (c = 0; c < N; c = c + 1) begin : bot_out
            assign psum_out_flat[c*32 +: 32] = psum_v[N][c];
        end
    endgenerate

endmodule
