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
    wire signed [15:0] mult_result;
    wire signed [15:0] add_result;
    wire cout;
    
    // Instantiate Wallace tree multiplier
    wallace_tree_8x8 multiplier (
        .multiplicand(a_in),
        .multiplier(b_in),
        .product(mult_result)
    );
    
    // Instantiate Kogge-Stone adder for accumulation
    kogge_stone_adder_16bit accumulator (
        .a(c_sum),
        .b(mult_result),
        .cin(1'b0),
        .sum(add_result),
        .cout(cout)
    );
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            c_sum <= 16'sd0;
        end else begin
            // Pass through inputs to outputs (for systolic data flow)
            a_out <= a_in;
            b_out <= b_in;
            // Update accumulator
            c_sum <= add_result;
        end
    end
    
    assign c_sum_out = c_sum;
endmodule

module systolic_matrix_multiplier #(
    parameter DATA_WIDTH = 8,
    parameter RESULT_WIDTH = 16,  // Added parameter for result width
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
    output [M*P*RESULT_WIDTH-1:0] result_c  // Fixed: removed duplicate declaration and changed width
);

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

    // Generate the M x P systolic array with structural MAC units
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
        for (row = 0; row < M; row = row + 1) begin : connect_a
            assign a_h[row][0] = a_input[row];
        end
        for (col = 0; col < P; col = col + 1) begin : connect_b
            assign b_v[0][col] = b_input[col];
        end
    endgenerate

    // Unpack input vectors into 2D arrays
    genvar unpack_i, unpack_j;
    generate
        for (unpack_i = 0; unpack_i < M; unpack_i = unpack_i + 1) begin : unpack_a_rows
            for (unpack_j = 0; unpack_j < N; unpack_j = unpack_j + 1) begin : unpack_a_cols
                assign a_mem[unpack_i][unpack_j] = matrix_a[((unpack_i*N + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : (unpack_i*N + unpack_j)*DATA_WIDTH];
            end
        end
        for (unpack_i = 0; unpack_i < N; unpack_i = unpack_i + 1) begin : unpack_b_rows
            for (unpack_j = 0; unpack_j < P; unpack_j = unpack_j + 1) begin : unpack_b_cols
                assign b_mem[unpack_i][unpack_j] = matrix_b[((unpack_i*P + unpack_j)*DATA_WIDTH + DATA_WIDTH-1) : (unpack_i*P + unpack_j)*DATA_WIDTH];
            end
        end
    endgenerate

    // State machine - sequential logic
    always @(posedge clk or posedge rst) begin
        if (rst) 
            state <= S_IDLE;
        else 
            state <= next_state;
    end

    // State machine - combinational logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start) 
                    next_state = S_COMPUTE;
            end
            
            S_COMPUTE: begin
                if (cycle_count >= (M + N + P - 2)) 
                    next_state = S_DONE;
            end
            
            S_DONE: begin
                next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // Done signal generation
    always @(posedge clk or posedge rst) begin
        if (rst)
            done <= 1'b0;
        else if (state == S_DONE)
            done <= 1'b1;
        else
            done <= 1'b0;
    end

    // Control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 0;
            input_cycle <= 0;
            for (init_i = 0; init_i < M; init_i = init_i + 1) 
                a_input[init_i] <= 8'sd0;
            for (init_j = 0; init_j < P; init_j = init_j + 1) 
                b_input[init_j] <= 8'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        cycle_count <= 0;
                        input_cycle <= 0;
                    end
                end
                
                S_COMPUTE: begin
                    cycle_count <= cycle_count + 1;
                    
                    // Feed data into systolic array with proper skewing
                    for (init_i = 0; init_i < M; init_i = init_i + 1) begin
                        if (input_cycle >= init_i && input_cycle < N + init_i) 
                            a_input[init_i] <= a_mem[init_i][input_cycle - init_i];
                        else 
                            a_input[init_i] <= 8'sd0;
                    end
                    
                    for (init_j = 0; init_j < P; init_j = init_j + 1) begin
                        if (input_cycle >= init_j && input_cycle < N + init_j) 
                            b_input[init_j] <= b_mem[input_cycle - init_j][init_j];
                        else 
                            b_input[init_j] <= 8'sd0;
                    end
                    
                    input_cycle <= input_cycle + 1;
                end
                
                S_DONE: begin
                    // Hold final values
                    cycle_count <= 0;
                    input_cycle <= 0;
                end
            endcase
        end
    end

    // Pack results into output vector (full 16-bit results)
    genvar pack_i, pack_j;
    generate
        for (pack_i = 0; pack_i < M; pack_i = pack_i + 1) begin : pack_rows
            for (pack_j = 0; pack_j < P; pack_j = pack_j + 1) begin : pack_cols
                assign result_c[((pack_i*P + pack_j)*RESULT_WIDTH + RESULT_WIDTH-1) : (pack_i*P + pack_j)*RESULT_WIDTH] = c_result_wires[pack_i][pack_j];
            end
        end
    endgenerate

endmodule