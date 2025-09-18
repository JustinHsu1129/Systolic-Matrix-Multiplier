module tb_matrix_multiplier;

    // Parameters for an 8x8 multiplier
    parameter DATA_WIDTH = 8;
    parameter M = 8;
    parameter N = 8;
    parameter P = 8;
    
    // Width for the testbench's internal accumulator
    parameter C_DATA_WIDTH = 2 * DATA_WIDTH + 4;

    // Testbench signals
    reg clk;
    reg rst;
    reg start;

    reg [M*N*DATA_WIDTH-1:0] matrix_a_packed;
    reg [N*P*DATA_WIDTH-1:0] matrix_b_packed;

    wire done;
    wire [M*P*DATA_WIDTH-1:0] result_c_tb;

    reg signed [DATA_WIDTH-1:0] matrix_a_tb [0:M*N-1];
    reg signed [DATA_WIDTH-1:0] matrix_b_tb [0:N*P-1];
    reg signed [DATA_WIDTH-1:0] expected_c [0:M-1][0:P-1];
    
    // Declare integers outside always blocks
    integer pack_i;
    integer i, j, k;
    reg signed [C_DATA_WIDTH-1:0] temp_sum;
    reg signed [DATA_WIDTH-1:0] val_a, val_b;
    integer error_count;
    reg signed [DATA_WIDTH-1:0] dut_val;
    
    // Pack the matrices for the DUT
    always @(*) begin
        for (pack_i = 0; pack_i < M*N; pack_i = pack_i + 1) begin
            matrix_a_packed[pack_i*DATA_WIDTH +: DATA_WIDTH] = matrix_a_tb[pack_i];
        end
        for (pack_i = 0; pack_i < N*P; pack_i = pack_i + 1) begin
            matrix_b_packed[pack_i*DATA_WIDTH +: DATA_WIDTH] = matrix_b_tb[pack_i];
        end
    end
    
    // Instantiate the Unit Under Test (UUT)
    matrix_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .M(M),
        .N(N),
        .P(P)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .matrix_a(matrix_a_packed),
        .matrix_b(matrix_b_packed),
        .done(done),
        .result_c(result_c_tb)
    );

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Main test sequence
    initial begin
        $display("-------------------------------------------");
        $display("Starting 8x8 Matrix Multiplication Testbench");
        $display("-------------------------------------------");

        // Initialize
        rst = 1;
        start = 0;
        
        // Initialize matrices with simple test pattern if files don't exist
        for (i = 0; i < M*N; i = i + 1) begin
            matrix_a_tb[i] = i % 16; // Simple pattern
        end
        for (i = 0; i < N*P; i = i + 1) begin
            matrix_b_tb[i] = (i + 1) % 16; // Simple pattern
        end
        
        // Try to read input matrices from files (if they exist)
        $readmemh("ram_a_init.txt", matrix_a_tb);
        $readmemh("ram_b_init.txt", matrix_b_tb);
        $display("Time: %0t ns | Matrices A and B initialized.", $time);

        // Calculate the expected result
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < P; j = j + 1) begin
                temp_sum = 0;
                for (k = 0; k < N; k = k + 1) begin
                    val_a = matrix_a_tb[i*N + k];
                    val_b = matrix_b_tb[k*P + j];
                    temp_sum = temp_sum + (val_a * val_b);
                end
                expected_c[i][j] = temp_sum[DATA_WIDTH-1:0];
            end
        end
        $display("Time: %0t ns | Expected model calculated the expected result.", $time);

        // Start the DUT
        #10;
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;
        $display("Time: %0t ns | Start pulse sent to DUT. Waiting for completion...", $time);

        // Wait for the DUT to signal it's finished
        wait (done);
        #1;
        $display("Time: %0t ns | DUT finished. 'done' signal received.", $time);

        // Compare the DUT's result with the expected
        error_count = 0;
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < P; j = j + 1) begin
                dut_val = result_c_tb[((i*P + j) * DATA_WIDTH) +: DATA_WIDTH];
                if (dut_val !== expected_c[i][j]) begin
                    $display("ERROR: Mismatch at C[%0d][%0d]!", i, j);
                    $display("  --> Expected: %h (%d), DUT Result: %h (%d)", 
                             expected_c[i][j], expected_c[i][j], dut_val, dut_val);
                    error_count = error_count + 1;
                end
            end
        end

        if (error_count == 0) begin
            $display("\nSUCCESS: All %0d elements match the expected result!", M*P);
        end else begin
            $display("\nFAILURE: Found %0d mismatches.", error_count);
        end
        
        $display("-------------------------------------------");
        $display("Testbench finished.");
        $display("-------------------------------------------");
        $finish;
    end

    // generate VCD file

    initial begin

        $dumpfile("matrix_multiplier.vcd");   // Name of the VCD file to create
        $dumpvars(0, tb_matrix_multiplier);     // Dump all signals from module "testbench"

    end

endmodule