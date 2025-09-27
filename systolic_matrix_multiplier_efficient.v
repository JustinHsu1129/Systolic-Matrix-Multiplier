// Block RAM module
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

// Fixed Kogge-Stone Adder for efficient addition
module kogge_stone_adder_16bit (
    input [15:0] a,
    input [15:0] b,
    input cin,
    output [15:0] sum,
    output cout
);
    wire [15:0] g, p;
    
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
    
    // Fixed carry generation - each carry depends on previous carry
    wire [16:0] carry;
    assign carry[0] = cin;
    assign carry[1] = g4[0] | (p4[0] & cin);
    generate
        for (i = 1; i < 16; i = i + 1) begin : carry_gen
            assign carry[i+1] = g4[i] | (p4[i] & carry[i]); // Fixed: was carry[1]
        end
    endgenerate
    
    // Final sum
    assign sum = p ^ carry[15:0];
    assign cout = carry[16];
endmodule

// Simplified signed multiplier using built-in multiplication
module signed_multiplier_8bit (
    input signed [7:0] a,
    input signed [7:0] b,
    output signed [15:0] product
);
    // Use built-in signed multiplication for reliability
    assign product = a * b;
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
    wire signed [15:0] mult_result;
    wire [15:0] add_result;
    wire cout;
    
    // Simplified signed multiplier
    signed_multiplier_8bit multiplier (
        .a(a),
        .b(b),
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

// Processing Element with MAC unit
module processing_element (
    input clk,
    input rst,
    input signed [7:0] a_in,
    input signed [7:0] b_in,
    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,
    output reg signed [15:0] c_sum_out
);
    wire signed [15:0] mult_result;
    wire signed [15:0] add_result;
    wire cout;
    
    // Direct multiplication
    assign mult_result = a_in * b_in;
    
    // Kogge-Stone adder for accumulation
    kogge_stone_adder_16bit accumulator (
        .a(c_sum_out),
        .b(mult_result),
        .cin(1'b0),
        .sum(add_result),
        .cout(cout)
    );
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            c_sum_out <= 16'sd0;
        end else begin
            // Pass through inputs to outputs (with 1 cycle delay)
            a_out <= a_in;
            b_out <= b_in;
            // Update accumulator
            c_sum_out <= add_result;
        end
    end
endmodule

// Systolic Matrix Multiplier - Top Level Module
module systolic_matrix_multiplier #(
    parameter DATA_WIDTH = 8,
    parameter RESULT_WIDTH = 16,  // Full width for results
    parameter M = 8,
    parameter N = 8,
    parameter P = 8
)(
    input clk,
    input rst,
    input start,
    input [M*N*DATA_WIDTH-1:0] matrix_a,
    input [N*P*DATA_WIDTH-1:0] matrix_b,
    output reg done,
    output [M*P*RESULT_WIDTH-1:0] result_c  // Changed to full width
);

    // States
    localparam S_IDLE = 2'b00;
    localparam S_COMPUTE = 2'b01;
    localparam S_DONE = 2'b10;

    reg [1:0] state, next_state;
    reg [7:0] cycle_count;

    // Unpack input matrices
    wire signed [DATA_WIDTH-1:0] a_mem [0:M-1][0:N-1];
    wire signed [DATA_WIDTH-1:0] b_mem [0:N-1][0:P-1];

    // Systolic array interconnections
    wire signed [DATA_WIDTH-1:0] a_h [0:M-1][0:P];  // Horizontal A flow
    wire signed [DATA_WIDTH-1:0] b_v [0:M][0:P-1];  // Vertical B flow
    
    wire signed [RESULT_WIDTH-1:0] c_result_wires [0:M-1][0:P-1];

    // Input shift registers for proper systolic timing
    reg signed [DATA_WIDTH-1:0] a_shift [0:M-1][0:M-1];  // M stages for each row
    reg signed [DATA_WIDTH-1:0] b_shift [0:P-1][0:P-1];  // P stages for each column
    
    integer i, j, k;

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

    // Connect shift register outputs to systolic array inputs
    generate
        for (row = 0; row < M; row = row + 1) begin
            assign a_h[row][0] = a_shift[row][M-1];  // Output of shift register
        end
        for (col = 0; col < P; col = col + 1) begin
            assign b_v[0][col] = b_shift[col][P-1];  // Output of shift register
        end
    endgenerate

    // Unpack input vectors into 2D arrays
    genvar unpack_i, unpack_j;
    generate
        for (unpack_i = 0; unpack_i < M; unpack_i = unpack_i + 1) begin
            for (unpack_j = 0; unpack_j < N; unpack_j = unpack_j + 1) begin
                assign a_mem[unpack_i][unpack_j] = 
                    matrix_a[((unpack_i*N + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : 
                            (unpack_i*N + unpack_j)*DATA_WIDTH];
            end
        end
        for (unpack_i = 0; unpack_i < N; unpack_i = unpack_i + 1) begin
            for (unpack_j = 0; unpack_j < P; unpack_j = unpack_j + 1) begin
                assign b_mem[unpack_i][unpack_j] = 
                    matrix_b[((unpack_i*P + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : 
                            (unpack_i*P + unpack_j)*DATA_WIDTH];
            end
        end
    endgenerate

    // State machine
    always @(posedge clk or posedge rst) begin
        if (rst) 
            state <= S_IDLE;
        else 
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: 
                if (start) 
                    next_state = S_COMPUTE;
            
            S_COMPUTE: 
                // Need more cycles for proper systolic operation
                if (cycle_count >= (M + N + P + 5)) 
                    next_state = S_DONE;
            
            S_DONE: 
                next_state = S_IDLE;
            
            default: 
                next_state = S_IDLE;
        endcase
    end

    always @(*) begin
        done = (state == S_DONE);
    end

    // Control logic with proper systolic timing
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 0;
            
            // Initialize shift registers
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    a_shift[i][j] <= 8'sd0;
                end
            end
            for (i = 0; i < P; i = i + 1) begin
                for (j = 0; j < P; j = j + 1) begin
                    b_shift[i][j] <= 8'sd0;
                end
            end
            
        end else if (state == S_IDLE && start) begin
            cycle_count <= 0;
            
        end else if (state == S_COMPUTE) begin
            cycle_count <= cycle_count + 1;
            
            // Shift register operation for matrix A (horizontal flow)
            for (i = 0; i < M; i = i + 1) begin
                // Shift existing values right
                for (j = M-1; j > 0; j = j - 1) begin
                    a_shift[i][j] <= a_shift[i][j-1];
                end
                
                // Input new value with proper timing - row i starts at cycle i
                if (cycle_count >= i && cycle_count < (N + i)) begin
                    a_shift[i][0] <= a_mem[i][cycle_count - i];
                end else begin
                    a_shift[i][0] <= 8'sd0;
                end
            end
            
            // Shift register operation for matrix B (vertical flow)  
            for (i = 0; i < P; i = i + 1) begin
                // Shift existing values down
                for (j = P-1; j > 0; j = j - 1) begin
                    b_shift[i][j] <= b_shift[i][j-1];
                end
                
                // Input new value with proper timing - column i starts at cycle i
                if (cycle_count >= i && cycle_count < (N + i)) begin
                    b_shift[i][0] <= b_mem[cycle_count - i][i];
                end else begin
                    b_shift[i][0] <= 8'sd0;
                end
            end
        end
    end

    // Pack results into output vector with full width
    genvar pack_i, pack_j;
    generate
        for (pack_i = 0; pack_i < M; pack_i = pack_i + 1) begin
            for (pack_j = 0; pack_j < P; pack_j = pack_j + 1) begin
                assign result_c[((pack_i*P + pack_j)*RESULT_WIDTH + RESULT_WIDTH-1) : 
                               (pack_i*P + pack_j)*RESULT_WIDTH] = c_result_wires[pack_i][pack_j];
            end
        end
    endgenerate

endmodule