`timescale 1ns/1ps

module rv32i_fetch_tb;

reg clk;
reg rst_n;

// DUT inputs
reg [31:0] i_inst;
reg i_ack_inst;
reg i_stall;
reg i_flush;

reg i_alu_change_pc;
reg [31:0] i_alu_next_pc;

reg i_writeback_change_pc;
reg [31:0] i_writeback_next_pc;

// DUT outputs
wire [31:0] o_iaddr;
wire [31:0] o_pc;
wire [31:0] o_inst;
wire o_stb_inst;
wire o_ce;

// -----------------------------
// DUT
// -----------------------------
rv32i_fetch DUT (
    .i_clk(clk),
    .i_rst_n(rst_n),

    .o_iaddr(o_iaddr),
    .o_pc(o_pc),
    .i_inst(i_inst),
    .o_inst(o_inst),
    .o_stb_inst(o_stb_inst),
    .i_ack_inst(i_ack_inst),

    .i_writeback_change_pc(i_writeback_change_pc),
    .i_writeback_next_pc(i_writeback_next_pc),

    .i_alu_change_pc(i_alu_change_pc),
    .i_alu_next_pc(i_alu_next_pc),

    .o_ce(o_ce),
    .i_stall(i_stall),
    .i_flush(i_flush)
);

// -----------------------------
// SIMPLE INSTRUCTION MEMORY
// -----------------------------
reg [31:0] imem [0:255];

initial begin
    imem[0] = 32'h00000013;
    imem[1] = 32'h00100093;
    imem[2] = 32'h00200113;
    imem[3] = 32'h00308193;
    imem[4] = 32'h00408213;
end

always @(*) begin
    i_inst = imem[o_iaddr[9:2]];
end

// -----------------------------
// CLOCK
// -----------------------------
always #5 clk = ~clk;

// -----------------------------
// TEST SEQUENCE
// -----------------------------
initial begin
    clk = 0;
    rst_n = 0;

    i_ack_inst = 0;
    i_stall = 0;
    i_flush = 0;
    i_alu_change_pc = 0;
    i_writeback_change_pc = 0;

    #20;
    rst_n = 1;

    // -------------------------
    // CASE 1: NORMAL EXECUTION
    // -------------------------
    repeat(5) begin
        i_ack_inst = 1;
        #10;
    end

    // -------------------------
    // CASE 2: MEMORY STALL
    // -------------------------
    $display("Memory stall test");
    i_ack_inst = 0;
    #40;
    i_ack_inst = 1;
    #40;

    // -------------------------
    // CASE 3: PIPELINE STALL
    // -------------------------
    $display("Pipeline stall test");
    i_stall = 1;
    #40;
    i_stall = 0;
    #40;

    // -------------------------
    // CASE 4: ALU BRANCH
    // -------------------------
    $display("Branch test");
    i_alu_next_pc = 32'd16;
    i_alu_change_pc = 1;
    #10;
    i_alu_change_pc = 0;
    #60;

    // -------------------------
    // CASE 5: WRITEBACK PC CHANGE
    // -------------------------
    $display("Trap PC change test");
    i_writeback_next_pc = 32'd32;
    i_writeback_change_pc = 1;
    #10;
    i_writeback_change_pc = 0;
    #60;

    // -------------------------
    // CASE 6: FLUSH
    // -------------------------
    $display("Flush test");
    i_flush = 1;
    #10;
    i_flush = 0;
    #40;

    $finish;
end

endmodule
