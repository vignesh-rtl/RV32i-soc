`timescale 1ns / 1ps

module processor_tb;

reg clk;
reg rst;
wire zero_flag;

processor_top DUT (
    .clk(clk),
    .rst(rst),
    .zero_flag(zero_flag)
);

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, processor_tb);
end

// clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;   // 100 MHz sim clock
end

// reset sequence
initial begin
    rst = 1;
    #20;
    rst = 0;
end

initial begin
    #200;
    $finish;
end

endmodule
