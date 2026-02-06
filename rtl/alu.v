`timescale 1ns / 1ps
`default_nettype none

module alu (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [3:0]  alu_ctrl,

    output reg  [31:0] result,
    output wire        zero
);

    // --------------------------------------------------
    // ALU Combinational Logic
    // --------------------------------------------------
    always @(*) begin
        case (alu_ctrl)

            4'b0000: result = op_a & op_b;              // AND
            4'b0001: result = op_a | op_b;              // OR
            4'b0010: result = op_a + op_b;              // ADD
            4'b0011: result = op_a ^ op_b;              // XOR
            4'b0100: result = op_a - op_b;              // SUB
            4'b0101: result = op_a << op_b[4:0];        // SLL
            4'b0110: result = op_a >> op_b[4:0];        // SRL
            4'b0111: result = 
                       ($signed(op_a) < $signed(op_b)); // SLT

            default: result = 32'b0;

        endcase
    end

    // --------------------------------------------------
    // Zero flag
    // --------------------------------------------------
    assign zero = (result == 32'b0);

endmodule

`default_nettype wire
