`timescale 1ns / 1ps

module processor_tb;

reg clk;
reg rst;

wire zero_flag;

// DUT
processor_top DUT (
    .clk(clk),
    .rst(rst),
    .zero_flag(zero_flag)
);

// ----------------------------
// CLOCK
// ----------------------------
initial begin
    clk = 0;
    forever #5 clk = ~clk;   // 100MHz sim clock
end

// ----------------------------
// RESET
// ----------------------------
initial begin
    rst = 1;
    #20;
    rst = 0;
end

// ----------------------------
// WAVES
// ----------------------------
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, processor_tb);
end

// ----------------------------
// SIM TIME
// ----------------------------
initial begin
    #500;
    $finish;
end

endmodule
