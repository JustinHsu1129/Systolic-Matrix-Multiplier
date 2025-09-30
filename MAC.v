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
    // For 8x8 multiplication, we need 4 partial products with radix-4 Booth
    wire [17:0] pp[3:0]; // Extended to handle sign extension properly
    wire [2:0] booth_bits[3:0];
    wire add_a[3:0], add_2a[3:0], sub_a[3:0], sub_2a[3:0];
    
    // Correct Booth encoding setup for 8-bit multiplier
    assign booth_bits[0] = {multiplier[1:0], 1'b0};
    assign booth_bits[1] = multiplier[3:1];
    assign booth_bits[2] = multiplier[5:3];
    assign booth_bits[3] = multiplier[7:5];
    
    // Generate booth encoders
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : booth_enc
            booth_encoder be (
                .booth_bits(booth_bits[i]),
                .add_a(add_a[i]),
                .add_2a(add_2a[i]),
                .sub_a(sub_a[i]),
                .sub_2a(sub_2a[i])
            );
        end
    endgenerate
    
    // Generate partial products with proper sign extension
    generate
        for (i = 0; i < 4; i = i + 1) begin : pp_gen
            wire [8:0] mult_1x = {multiplicand[7], multiplicand}; // Sign extend to 9 bits
            wire [9:0] mult_2x = {multiplicand[7], multiplicand, 1'b0}; // 2x with sign extend
            wire [17:0] pp_base_1x, pp_base_2x;
            wire [17:0] pp_neg;
            
            // Extend and shift partial products
            assign pp_base_1x = {{9{mult_1x[8]}}, mult_1x} << (i*2);
            assign pp_base_2x = {{8{mult_2x[9]}}, mult_2x} << (i*2);
            
            // Select the correct partial product
            wire [17:0] pp_selected;
            assign pp_selected = add_a[i] ? pp_base_1x :
                                add_2a[i] ? pp_base_2x :
                                (sub_a[i] | sub_2a[i]) ? (sub_a[i] ? pp_base_1x : pp_base_2x) :
                                18'b0;
            
            // Apply two's complement for subtraction
            assign pp_neg = ~pp_selected + 1'b1;
            
            assign pp[i] = (sub_a[i] | sub_2a[i]) ? pp_neg : pp_selected;
        end
    endgenerate
    
    // Wallace tree reduction for 4 inputs
    // Level 1: 4 -> 3 using one 3:2 compressor
    wire [17:0] s1, c1;
    wire [17:0] remaining;
    
    assign s1 = pp[0] ^ pp[1] ^ pp[2];
    assign c1 = (pp[0] & pp[1]) | (pp[0] & pp[2]) | (pp[1] & pp[2]);
    assign remaining = pp[3];
    
    // Level 2: 3 -> 2 using one 3:2 compressor  
    wire [17:0] s2, c2;
    assign s2 = s1 ^ remaining ^ (c1 << 1);
    assign c2 = (s1 & remaining) | (s1 & (c1 << 1)) | (remaining & (c1 << 1));
    
    // Final addition - only use lower 16 bits
    wire [15:0] final_sum;
    wire cout;
    wire [17:0] c2_shifted = c2 << 1;
    kogge_stone_adder_16bit final_add (
        .a(s2[15:0]),
        .b(c2_shifted[15:0]),
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

//tb for testing purposes

/* it works

`timescale 1ns / 1ps

module mac_unit_tb;

    // Parameters
    parameter CLK_PERIOD = 10;
    
    // Testbench signals
    reg clk;
    reg rst;
    reg signed [7:0] a;
    reg signed [7:0] b;
    reg signed [15:0] acc_in;
    wire signed [15:0] acc_out;
    
    // Expected result
    reg signed [15:0] expected;
    integer errors;
    integer test_num;
    
    // Instantiate the MAC unit
    mac_unit uut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .acc_in(acc_in),
        .acc_out(acc_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test task
    task test_mac;
        input signed [7:0] in_a;
        input signed [7:0] in_b;
        input signed [15:0] in_acc;
        input signed [15:0] exp_out;
        begin
            test_num = test_num + 1;
            a = in_a;
            b = in_b;
            acc_in = in_acc;
            expected = exp_out;
            
            @(posedge clk);
            #1; // Small delay for signal propagation
            
            if (acc_out !== expected) begin
                $display("ERROR Test %0d: a=%0d, b=%0d, acc_in=%0d", 
                         test_num, in_a, in_b, in_acc);
                $display("  Expected: %0d, Got: %0d", expected, acc_out);
                errors = errors + 1;
            end else begin
                $display("PASS Test %0d: a=%0d, b=%0d, acc_in=%0d -> acc_out=%0d", 
                         test_num, in_a, in_b, in_acc, acc_out);
            end
        end
    endtask
    
    // Main test procedure
    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        a = 0;
        b = 0;
        acc_in = 0;
        errors = 0;
        test_num = 0;
        
        $display("\n========================================");
        $display("MAC Unit Testbench Starting");
        $display("========================================\n");
        
        // Hold reset for a few cycles
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        $display("--- Basic Multiplication Tests ---");
        // Test 1: Simple positive multiplication
        test_mac(8'd5, 8'd3, 16'd0, 16'd15);
        
        // Test 2: Multiply by zero
        test_mac(8'd10, 8'd0, 16'd0, 16'd0);
        
        // Test 3: Multiply by one
        test_mac(8'd7, 8'd1, 16'd0, 16'd7);
        
        // Test 4: Negative × Positive
        test_mac(-8'd4, 8'd5, 16'd0, -16'd20);
        
        // Test 5: Positive × Negative
        test_mac(8'd6, -8'd3, 16'd0, -16'd18);
        
        // Test 6: Negative × Negative
        test_mac(-8'd7, -8'd2, 16'd0, 16'd14);
        
        $display("\n--- Accumulation Tests ---");
        // Test 7: Simple accumulation
        test_mac(8'd2, 8'd3, 16'd10, 16'd16);
        
        // Test 8: Multiple accumulations
        test_mac(8'd4, 8'd5, 16'd20, 16'd40);
        
        // Test 9: Accumulate with negative product
        test_mac(-8'd3, 8'd2, 16'd15, 16'd9);
        
        // Test 10: Accumulate with negative accumulator
        test_mac(8'd5, 8'd2, -16'd5, 16'd5);
        
        $display("\n--- Edge Case Tests ---");
        // Test 11: Maximum positive values
        test_mac(8'd127, 8'd127, 16'd0, 16'd16129);
        
        // Test 12: Maximum negative value
        test_mac(-8'd128, 8'd1, 16'd0, -16'd128);
        
        // Test 13: Maximum negative × Maximum negative
        test_mac(-8'd128, -8'd128, 16'd0, 16'd16384);
        
        // Test 14: Large accumulation
        test_mac(8'd100, 8'd100, 16'd10000, 16'd20000);
        
        $display("\n--- Sequential MAC Operations (Dot Product) ---");
        // Simulate a dot product: [2, 3, 4] · [5, 6, 7]
        // = 2*5 + 3*6 + 4*7 = 10 + 18 + 28 = 56
        
        // Reset accumulator
        rst = 1;
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        $display("Computing dot product: [2,3,4] · [5,6,7]");
        test_mac(8'd2, 8'd5, 16'd0, 16'd10);    // 2*5 = 10
        test_mac(8'd3, 8'd6, 16'd10, 16'd28);   // 10 + 3*6 = 28
        test_mac(8'd4, 8'd7, 16'd28, 16'd56);   // 28 + 4*7 = 56
        
        $display("\n--- Reset Test ---");
        // Test 15: Reset clears accumulator
        rst = 1;
        @(posedge clk);
        #1;
        if (acc_out !== 16'd0) begin
            $display("ERROR: Reset failed, acc_out = %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("PASS: Reset correctly clears accumulator");
        end
        rst = 0;
        @(posedge clk);
        
        $display("\n--- Overflow Tests ---");
        // Test 16: Positive overflow scenario
        test_mac(8'd127, 8'd127, 16'd16000, 16'd32129);
        
        // Test 17: Negative overflow scenario  
        test_mac(-8'd127, 8'd127, -16'd16000, -16'd32129);
        
        $display("\n========================================");
        $display("MAC Unit Testbench Complete");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Errors: %0d", errors);
        
        if (errors == 0) begin
            $display("\n*** ALL TESTS PASSED! ***\n");
        end else begin
            $display("\n*** TESTS FAILED! ***\n");
        end
        
        #100;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000;
        $display("\nERROR: Testbench timeout!");
        $finish;
    end
    
    // Optional: Dump waveforms
    initial begin
        $dumpfile("mac_unit_tb.vcd");
        $dumpvars(0, mac_unit_tb);
    end

endmodule

*/