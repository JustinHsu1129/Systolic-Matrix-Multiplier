module bram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10   
)(
    input clk,
    input we,                             
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] din,
    output reg [DATA_WIDTH-1:0] dout
);
    // Memory array
    reg [DATA_WIDTH-1:0] mem [(1<<ADDR_WIDTH)-1:0];

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;            // write
        end
        dout <= mem[addr];               // read (sync)
    end
endmodule

// Kogge-Stone Adder for efficient addition
module kogge_stone_adder_16bit (
    input [15:0] a,
    input [15:0] b,
    input cin,
    output [15:0] sum,
    output cout
);
    wire [15:0] g, p;
    wire [15:0] g_out, p_out;
    
    // Generate and Propagate
    assign g = a & b;
    assign p = a ^ b;
    
    // Level 1
    wire [15:0] g1, p1;
    assign g1[0] = g[0];
    assign p1[0] = p[0];
    genvar i;
    generate
        for (i = 1; i < 16; i = i + 1) begin : level1
            assign g1[i] = g[i] | (p[i] & g[i-1]);
            assign p1[i] = p[i] & p[i-1];
        end
    endgenerate
    
    // Level 2
    wire [15:0] g2, p2;
    assign g2[1:0] = g1[1:0];
    assign p2[1:0] = p1[1:0];
    generate
        for (i = 2; i < 16; i = i + 1) begin : level2
            assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
            assign p2[i] = p1[i] & p1[i-2];
        end
    endgenerate
    
    // Level 3
    wire [15:0] g3, p3;
    assign g3[3:0] = g2[3:0];
    assign p3[3:0] = p2[3:0];
    generate
        for (i = 4; i < 16; i = i + 1) begin : level3
            assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
            assign p3[i] = p2[i] & p2[i-4];
        end
    endgenerate
    
    // Level 4
    wire [15:0] g4, p4;
    assign g4[7:0] = g3[7:0];
    assign p4[7:0] = p3[7:0];
    generate
        for (i = 8; i < 16; i = i + 1) begin : level4
            assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
            assign p4[i] = p3[i] & p3[i-8];
        end
    endgenerate
    
    // Generate carries
    wire [16:0] carry;
    assign carry[0] = cin;
    assign carry[1] = g4[0] | (p4[0] & cin);
    generate
        for (i = 1; i < 16; i = i + 1) begin : carry_gen
            assign carry[i+1] = g4[i] | (p4[i] & carry[1]);
        end
    endgenerate
    
    // Final sum
    assign sum = p ^ carry[15:0];
    assign cout = carry[16];
endmodule

// Booth Encoder for 2-bit radix-4 encoding
module booth_encoder (
    input [2:0] booth_bits,
    output reg add_a,
    output reg add_2a,
    output reg sub_a,
    output reg sub_2a
);
    always @(*) begin
        case (booth_bits)
            3'b000, 3'b111: begin add_a = 0; add_2a = 0; sub_a = 0; sub_2a = 0; end
            3'b001, 3'b010: begin add_a = 1; add_2a = 0; sub_a = 0; sub_2a = 0; end
            3'b011:         begin add_a = 0; add_2a = 1; sub_a = 0; sub_2a = 0; end
            3'b100:         begin add_a = 0; add_2a = 0; sub_a = 0; sub_2a = 1; end
            3'b101, 3'b110: begin add_a = 0; add_2a = 0; sub_a = 1; sub_2a = 0; end
            default:        begin add_a = 0; add_2a = 0; sub_a = 0; sub_2a = 0; end
        endcase
    end
endmodule

// Wallace Tree for partial product reduction
module wallace_tree_8x8 (
    input signed [7:0] multiplicand,
    input signed [7:0] multiplier,
    output [15:0] product
);
    wire [15:0] pp[4:0]; // 5 partial products for radix-4 booth
    wire [2:0] booth_bits[4:0];
    wire add_a[4:0], add_2a[4:0], sub_a[4:0], sub_2a[4:0];
    
    // Booth encoding setup
    assign booth_bits[0] = {multiplier[1:0], 1'b0};
    assign booth_bits[1] = multiplier[3:1];
    assign booth_bits[2] = multiplier[5:3];
    assign booth_bits[3] = multiplier[7:5];
    assign booth_bits[4] = {2'b00, multiplier[7]}; // Sign extension
    
    // Generate booth encoders
    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : booth_enc
            booth_encoder be (
                .booth_bits(booth_bits[i]),
                .add_a(add_a[i]),
                .add_2a(add_2a[i]),
                .sub_a(sub_a[i]),
                .sub_2a(sub_2a[i])
            );
        end
    endgenerate
    
    // Generate partial products
    wire [15:0] mult_1x_ext = {{8{multiplicand[7]}}, multiplicand};
    wire [15:0] mult_2x_ext = {{7{multiplicand[7]}}, multiplicand, 1'b0};
    
    generate
        for (i = 0; i < 5; i = i + 1) begin : pp_gen
            wire [15:0] pp_pos_1x, pp_pos_2x, pp_neg_1x, pp_neg_2x;
            
            assign pp_pos_1x = mult_1x_ext << (i*2);
            assign pp_pos_2x = mult_2x_ext << (i*2);
            assign pp_neg_1x = (~pp_pos_1x) + (1'b1 << (i*2));
            assign pp_neg_2x = (~pp_pos_2x) + (1'b1 << (i*2));
            
            assign pp[i] = add_a[i] ? pp_pos_1x :
                          add_2a[i] ? pp_pos_2x :
                          sub_a[i] ? pp_neg_1x :
                          sub_2a[i] ? pp_neg_2x :
                          16'b0;
        end
    endgenerate
    
    // Wallace tree reduction (simplified for 5 inputs)
    // Level 1: 5 -> 4 (using 3:2 compressors)
    wire [15:0] s1_1, c1_1, s1_2, c1_2;
    
    // First 3:2 compressor
    assign s1_1 = pp[0] ^ pp[1] ^ pp[2];
    assign c1_1 = (pp[0] & pp[1]) | (pp[0] & pp[2]) | (pp[1] & pp[2]);
    
    // Second 3:2 compressor
    assign s1_2 = pp[3] ^ pp[4] ^ 16'b0;
    assign c1_2 = (pp[3] & pp[4]);
    
    // Level 2: 4 -> 3
    wire [15:0] s2_1, c2_1;
    assign s2_1 = s1_1 ^ s1_2 ^ (c1_1 << 1);
    assign c2_1 = (s1_1 & s1_2) | (s1_1 & (c1_1 << 1)) | (s1_2 & (c1_1 << 1));
    
    // Final addition
    wire [15:0] final_sum;
    wire cout;
    kogge_stone_adder_16bit final_add (
        .a(s2_1),
        .b((c2_1 << 1) | (c1_2 << 1)),
        .cin(1'b0),
        .sum(final_sum),
        .cout(cout)
    );
    
    assign product = final_sum;
endmodule

// Multiply-Accumulate Unit
module mac_unit (
    input clk,
    input rst,
    input signed [7:0] a,
    input signed [7:0] b,
    input signed [15:0] acc_in,
    output reg signed [15:0] acc_out
);
    wire [15:0] mult_result;
    wire [15:0] add_result;
    wire cout;
    
    // Wallace tree multiplier
    wallace_tree_8x8 multiplier (
        .multiplicand(a),
        .multiplier(b),
        .product(mult_result)
    );
    
    // Kogge-Stone adder for accumulation
    kogge_stone_adder_16bit accumulator (
        .a(acc_in),
        .b(mult_result),
        .cin(1'b0),
        .sum(add_result),
        .cout(cout)
    );
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc_out <= 16'sd0;
        end else begin
            acc_out <= add_result;
        end
    end
endmodule

// Updated Processing Element with MAC unit
module processing_element (
    input clk,
    input rst,
    input signed [7:0] a_in,
    input signed [7:0] b_in,
    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,
    output signed [15:0] c_sum_out
);
    // Internal accumulator register
    reg signed [15:0] c_sum;
    wire signed [15:0] mac_result;
    
    // Instantiate MAC unit
    mac_unit mac (
        .clk(clk),
        .rst(rst),
        .a(a_in),
        .b(b_in),
        .acc_in(c_sum),
        .acc_out(mac_result)
    );
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            c_sum <= 16'sd0;
        end else begin
            // Pass through inputs to outputs
            a_out <= a_in;
            b_out <= b_in;
            // Update accumulator with MAC result
            c_sum <= mac_result;
        end
    end
    
    assign c_sum_out = c_sum;
endmodule

/* working
module processing_element (
    input clk,
    input rst,
    input signed [7:0] a_in,
    input signed [7:0] b_in,
    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,
    output signed [15:0] c_sum_out 
);
    // Each PE has its own internal accumulator
    reg signed [15:0] c_sum;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            c_sum <= 16'sd0; 
        end else begin
            
            a_out <= a_in;
            b_out <= b_in;
            
            c_sum <= c_sum + (a_in * b_in);
        end
    end

    assign c_sum_out = c_sum;

endmodule
*/

module systolic_matrix_multiplier #(
    parameter DATA_WIDTH = 8,
    parameter M = 8,
    parameter N = 8,
    parameter P = 8
)(
    clk, rst, start, matrix_a, matrix_b, done, result_c
);
    input clk;
    input rst;
    input start;
    input [M*N*DATA_WIDTH-1:0] matrix_a;
    input [N*P*DATA_WIDTH-1:0] matrix_b;
    output reg done;
    output [M*P*DATA_WIDTH-1:0] result_c;

    wire [M*P*DATA_WIDTH-1:0] result_c;

    // Simplified state machine
    localparam S_IDLE = 2'b00;
    localparam S_COMPUTE = 2'b01;
    localparam S_DONE = 2'b10;

    reg [1:0] state, next_state;
    reg [7:0] cycle_count;

    wire signed [DATA_WIDTH-1:0] a_mem [0:M-1][0:N-1];
    wire signed [DATA_WIDTH-1:0] b_mem [0:N-1][0:P-1];

    // Interconnections
    wire signed [DATA_WIDTH-1:0] a_h [0:M-1][0:P];
    wire signed [DATA_WIDTH-1:0] b_v [0:M][0:P-1];
    
    wire signed [15:0] c_result_wires [0:M-1][0:P-1];

    reg signed [DATA_WIDTH-1:0] a_input [0:M-1];
    reg signed [DATA_WIDTH-1:0] b_input [0:P-1];
    reg [7:0] input_cycle;
    integer init_i, init_j;

    // Generate the M x P systolic array
    genvar row, col;
    generate
        for (row = 0; row < M; row = row + 1) begin : pe_rows
            for (col = 0; col < P; col = col + 1) begin : pe_cols
               
                processing_element pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .a_in(a_h[row][col]),
                    .b_in(b_v[row][col]),
                    .a_out(a_h[row][col+1]),
                    .b_out(b_v[row+1][col]),
                    
                    .c_sum_out(c_result_wires[row][col])
                );
            end
        end
    endgenerate

    // Connect inputs to the systolic array's edges
    generate
        for (row = 0; row < M; row = row + 1) assign a_h[row][0] = a_input[row];
        for (col = 0; col < P; col = col + 1) assign b_v[0][col] = b_input[col];
    endgenerate

    // Put vectors into 2D arrays
    genvar unpack_i, unpack_j;
    generate
        for (unpack_i = 0; unpack_i < M; unpack_i = unpack_i + 1) begin
            for (unpack_j = 0; unpack_j < N; unpack_j = unpack_j + 1) begin
                assign a_mem[unpack_i][unpack_j] = matrix_a[((unpack_i*N + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : (unpack_i*N + unpack_j)*DATA_WIDTH];
            end
        end
        for (unpack_i = 0; unpack_i < N; unpack_i = unpack_i + 1) begin
            for (unpack_j = 0; unpack_j < P; unpack_j = unpack_j + 1) begin
                assign b_mem[unpack_i][unpack_j] = matrix_b[((unpack_i*P + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : (unpack_i*P + unpack_j)*DATA_WIDTH];
            end
        end
    endgenerate

    // State machine logic
    always @(posedge clk or posedge rst) begin
        if (rst) state <= S_IDLE;
        else state <= next_state;
    end

    always @(state or start or cycle_count) begin
        next_state = state;
        done = 1'b0;
        case (state)
            S_IDLE: if (start) next_state = S_COMPUTE;
            
            S_COMPUTE: if (cycle_count >= (M + N + P - 2)) next_state = S_DONE;
            S_DONE: begin
                done = 1'b1;
                next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // Control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 0;
            input_cycle <= 0;
            for (init_i = 0; init_i < M; init_i = init_i + 1) a_input[init_i] <= 8'sd0;
            for (init_j = 0; init_j < P; init_j = init_j + 1) b_input[init_j] <= 8'sd0;
        end else begin
            if (state == S_IDLE && start) begin
                cycle_count <= 0;
                input_cycle <= 0;
            end else if (state == S_COMPUTE) begin
                cycle_count <= cycle_count + 1;
                input_cycle <= input_cycle + 1;
                for (init_i = 0; init_i < M; init_i = init_i + 1) begin
                    if (input_cycle >= init_i && input_cycle < N + init_i) a_input[init_i] <= a_mem[init_i][input_cycle - init_i];
                    else a_input[init_i] <= 8'sd0;
                end
                for (init_j = 0; init_j < P; init_j = init_j + 1) begin
                    if (input_cycle >= init_j && input_cycle < N + init_j) b_input[init_j] <= b_mem[input_cycle - init_j][init_j];
                    else b_input[init_j] <= 8'sd0;
                end
            end
        end
    end

    // Put results into output vector
    genvar pack_i, pack_j;
    generate
        for (pack_i = 0; pack_i < M; pack_i = pack_i + 1) begin
            for (pack_j = 0; pack_j < P; pack_j = pack_j + 1) begin
                assign result_c[((pack_i*P + pack_j)*DATA_WIDTH + DATA_WIDTH-1) : (pack_i*P + pack_j)*DATA_WIDTH] = c_result_wires[pack_i][pack_j][DATA_WIDTH-1:0];
            end
        end
    endgenerate

endmodule