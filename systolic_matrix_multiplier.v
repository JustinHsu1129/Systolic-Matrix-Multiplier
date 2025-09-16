module bram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10   // depth = 2^ADDR_WIDTH
)(
    input clk,
    input we,                             // write enable
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

module processing_element (
    input clk,
    input rst,
    input signed [7:0] a_in,
    input signed [7:0] b_in,
    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,
    output signed [15:0] c_sum_out // Output the internal sum
);
    // Each PE has its own internal accumulator
    reg signed [15:0] c_sum;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            c_sum <= 16'sd0; // Reset internal sum
        end else begin
            // Pass A and B values through
            a_out <= a_in;
            b_out <= b_in;
            // Accumulate the product INTERNALLY
            c_sum <= c_sum + (a_in * b_in);
        end
    end

    // Continuously output the current sum
    assign c_sum_out = c_sum;

endmodule

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

    // Systolic array interconnections
    wire signed [DATA_WIDTH-1:0] a_h [0:M-1][0:P];
    wire signed [DATA_WIDTH-1:0] b_v [0:M][0:P-1];
    // Wire array to capture final results from each PE
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
                // MODIFICATION: Instantiate the new PE
                processing_element pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .a_in(a_h[row][col]),
                    .b_in(b_v[row][col]),
                    .a_out(a_h[row][col+1]),
                    .b_out(b_v[row+1][col]),
                    // Connect the PE's result directly to a result wire
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

    // Unpack flattened input vectors into 2D wire arrays
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
            // Wait for all data to pass through the array
            S_COMPUTE: if (cycle_count >= (M + N + P - 2)) next_state = S_DONE;
            S_DONE: begin
                done = 1'b1;
                next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // Control logic and data feeding
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

    // Pack results from PE outputs to the final flattened output vector
    genvar pack_i, pack_j;
    generate
        for (pack_i = 0; pack_i < M; pack_i = pack_i + 1) begin
            for (pack_j = 0; pack_j < P; pack_j = pack_j + 1) begin
                assign result_c[((pack_i*P + pack_j)*DATA_WIDTH + DATA_WIDTH-1) : (pack_i*P + pack_j)*DATA_WIDTH] = c_result_wires[pack_i][pack_j][DATA_WIDTH-1:0];
            end
        end
    endgenerate

endmodule