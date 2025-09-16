module mux2x1 (
    input [18:0] a, b,
    input sel,
    output [18:0] muxout
);

assign muxout = sel ? b : a; //result = condition ? value_if_true : value_if_false;

endmodule

module MAC (
    input [7:0] inA, inB,
    input macc_clear, clk,
    output reg [18:0] out
);

wire [18:0] mult_out; 
wire [18:0] add_out; 
wire [18:0] mux_out;

assign mult_out = inA * inB;
assign add_out = mult_out + out;

mux2x1 mux0 (.a(add_out), .b(mult_out), .sel(macc_clear), .muxout(mux_out));

always @(posedge clk) begin
    if (macc_clear) begin
        out <= 0;
    end else begin
        out <= mux_out;
    end
end

endmodule

module MAC_tb;

    // Testbench signals
    reg [7:0] inA, inB;
    reg macc_clear, clk;
    wire [18:0] out;
    
    // Instantiate MAC module
    MAC uut (
        .inA(inA),
        .inB(inB),
        .macc_clear(macc_clear),
        .clk(clk),
        .out(out)
    );

    // Clock generation
    always #5 clk = ~clk;  // 10 ns clock period

    // Test variables
    integer i;
    reg [18:0] expected_out; // Expected accumulator value

    initial begin
        // Initialize signals
        clk = 0;
        macc_clear = 1;
        inA = 0;
        inB = 0;
        expected_out = 0;

        // Reset the MAC
        #10;
        macc_clear = 0;  // Release reset
        
        // Apply test cases
        for (i = 1; i <= 5; i = i + 1) begin
            inA = i;  
            inB = i + 1;  // Different values for multiplication
            
            #10;  // Wait for clock edge
            
            expected_out = expected_out + (inA * inB); // Expected accumulation
            
            // Self-checking assertion
            if (out !== expected_out) begin
                $display("ERROR Expected %d, Got %d", expected_out, out);
            end else begin
                $display("MAC input %d, %d, MAC output correct (%d)", inA, inB,out);
            end
        end
        
        // Test Reset Functionality
        #10;
        macc_clear = 1; // Reset
        #10;
        
        if (out !== 0) begin
            $display("ERROR: Reset failed! Expected 0, Got %d", out);
        end else begin
            $display("PASS: Reset successful, output is 0");
        end

        #10;
        $finish;  // End simulation
    end

endmodule
