// NOTE: This file is now fully Verilog-compatible (use .v extension)

module matrix_multiplier (
    clk, rst, start, matrix_a, matrix_b, done, result_c
);

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter M = 8; // Rows of matrix A and C
    parameter N = 8; // Cols of matrix A and Rows of matrix B
    parameter P = 8; // Cols of matrix B and C

    input clk;
    input rst;
    input start;
    input [M*N*DATA_WIDTH-1:0] matrix_a;
    input [N*P*DATA_WIDTH-1:0] matrix_b;
    output reg done;
    output reg [M*P*DATA_WIDTH-1:0] result_c;

    // Internal registers and wires
    parameter C_DATA_WIDTH = 2 * DATA_WIDTH + 4; // Using 4 instead of $clog2(N) for simplicity
    reg [C_DATA_WIDTH-1:0] sum;

    // State machine definition
    parameter S_IDLE = 2'b00;
    parameter S_CALC = 2'b01;
    parameter S_DONE = 2'b10;

    reg [1:0] state, next_state;

    // Loop counters
    reg [2:0] i;  // For 8x8, need 3 bits
    reg [2:0] j;
    reg [2:0] k;
    
    // Temporary variables for matrix access
    reg signed [DATA_WIDTH-1:0] a_val, b_val;
    reg signed [DATA_WIDTH-1:0] c_array [0:M*P-1];
    
    // Index calculation wires
    wire [5:0] a_index; // 6 bits for up to 64 elements
    wire [5:0] b_index;
    wire [5:0] c_index;
    
    // Declare integer outside always blocks
    integer init_idx;
    integer pack_idx;
    
    assign a_index = i * N + k;
    assign b_index = k * P + j;
    assign c_index = i * P + j;

    // Extract matrix elements
    always @(*) begin
        a_val = matrix_a[(a_index * DATA_WIDTH) +: DATA_WIDTH];
        b_val = matrix_b[(b_index * DATA_WIDTH) +: DATA_WIDTH];
    end

    // Sequential logic for state transitions
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Combinational logic for state machine
    always @(*) begin
        next_state = state;
        done = 1'b0;
        
        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_CALC;
                end
            end
            S_CALC: begin
                if (i == M-1 && j == P-1 && k == N-1) begin
                    next_state = S_DONE;
                end
            end
            S_DONE: begin
                done = 1'b1;
                next_state = S_IDLE;
            end
        endcase
    end

    // Main calculation logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            i <= 0;
            j <= 0;
            k <= 0;
            sum <= 0;
            // Initialize c_array to 0
            for (init_idx = 0; init_idx < M*P; init_idx = init_idx + 1) begin
                c_array[init_idx] <= 0;
            end
        end else begin
            if (state == S_CALC) begin
                // Update sum first based on current k value
                if (k == 0) begin
                    sum <= $signed(a_val) * $signed(b_val);
                end else begin
                    sum <= sum + $signed(a_val) * $signed(b_val);
                end

                // Store result when we've completed the dot product
                if (k == N-1) begin
                    c_array[c_index] <= sum + $signed(a_val) * $signed(b_val); // Add final term
                end

                // Update counters after calculations
                if (k < N - 1) begin
                    k <= k + 1;
                end else begin
                    k <= 0;
                    if (j < P - 1) begin
                        j <= j + 1;
                    end else begin
                        j <= 0;
                        if (i < M - 1) begin
                            i <= i + 1;
                        end else begin
                            i <= 0;
                        end
                    end
                end
            end else if (state == S_IDLE && start) begin
                i <= 0;
                j <= 0;
                k <= 0;
                sum <= 0;
            end
        end
    end
    
    // Pack the result array back into result_c
    always @(*) begin
        for (pack_idx = 0; pack_idx < M*P; pack_idx = pack_idx + 1) begin
            result_c[(pack_idx * DATA_WIDTH) +: DATA_WIDTH] = c_array[pack_idx];
        end
    end

endmodule