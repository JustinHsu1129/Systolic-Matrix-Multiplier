module systolic_top (
    input clk,
    input rst,
    input start,

    input        we_a, we_b, we_c,
    input  [9:0] addr_a, addr_b, addr_c,
    input  [DATA_WIDTH-1:0] din_a, din_b,
    output [DATA_WIDTH-1:0] dout_a, dout_b,
    output [DATA_WIDTH-1:0] dout_c,

    output done
);
    parameter DATA_WIDTH = 8;
    parameter M = 8;
    parameter N = 8;
    parameter P = 8;

    
    wire [DATA_WIDTH-1:0] result_c_wire;

    // Instantiate BRAMs
    bram #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(10)) bram_a (
        .clk(clk), .we(we_a), .addr(addr_a), .din(din_a), .dout(dout_a)
    );

    bram #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(10)) bram_b (
        .clk(clk), .we(we_b), .addr(addr_b), .din(din_b), .dout(dout_b)
    );

    bram #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(10)) bram_c (
        .clk(clk), .we(we_c), .addr(addr_c), .din(result_c_wire), .dout(dout_c)
    );

    // Instantiate multiplier
    systolic_matrix_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .M(M),
        .N(N),
        .P(P)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .matrix_a(dout_a),
        .matrix_b(dout_b),
        .done(done),
        .result_c(result_c_wire)
    );

endmodule
