// ============================================================
// PAM MAC Processing Element (weight-stationary)
//
//   psum_out = psum_in + PAM(act_in, weight)
//   act_out  = act_in  (delayed 1 cycle, flows right)
//   psum_out registered (flows down)
//
// Multiply is bf16×bf16 via PAM, accumulate in fp32.
// ============================================================

module pam_mac_pe (
    input  wire        clk,
    input  wire        rst,
    input  wire        load_weight,
    input  wire [15:0] weight_in,      // bf16 weight to preload
    input  wire [15:0] act_in,         // bf16 activation (flows right)
    input  wire [31:0] psum_in,        // fp32 partial sum (flows down)
    output reg  [15:0] act_out,        // bf16 activation to next PE
    output reg  [31:0] psum_out        // fp32 partial sum to PE below
);

    // ---- Weight register ----
    reg [15:0] weight;

    always @(posedge clk) begin
        if (rst)
            weight <= 16'd0;
        else if (load_weight)
            weight <= weight_in;
    end

    // ---- PAM multiply: act_in × weight → fp32 product ----
    wire [31:0] product;
    pam_mul_bf16 u_mul (
        .a   (act_in),
        .b   (weight),
        .out (product)
    );

    // ---- FP32 add: psum_in + product → sum ----
    wire [31:0] sum;
    fp32_adder u_add (
        .a   (psum_in),
        .b   (product),
        .out (sum)
    );

    // ---- Register outputs ----
    always @(posedge clk) begin
        if (rst) begin
            act_out  <= 16'd0;
            psum_out <= 32'd0;
        end else begin
            act_out  <= act_in;
            psum_out <= sum;
        end
    end

endmodule
