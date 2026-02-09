`timescale 1ns / 1ps
`default_nettype none

module ifu (
    input  wire        clk,
    input  wire        rst,

    output wire [31:0] instruction,
    output reg [31:0] pc = 32'd0
);

    //--------------------------------------------------
    // Program Counter
    //--------------------------------------------------
    always @(posedge clk) begin
    if (rst)
        pc <= 32'd0;
    else
        pc <= pc + 4;
    end

    //--------------------------------------------------
    // Instruction Memory
    //--------------------------------------------------
    instr_mem imem (
        .addr(pc),
        .inst(instruction)
    );

endmodule

`default_nettype wire
