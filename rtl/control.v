`timescale 1ns / 1ps
`default_nettype none

module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    output reg mem_read,
    output reg mem_write,
    output reg mem_to_reg,

    output reg  [3:0] alu_ctrl,
    output reg        reg_write
);

    // ALU operation encoding
    localparam ALU_AND = 4'b0000;
    localparam ALU_OR  = 4'b0001;
    localparam ALU_ADD = 4'b0010;
    localparam ALU_SUB = 4'b0100;
    localparam ALU_SLT = 4'b1000;
    localparam ALU_SLL = 4'b0011;
    localparam ALU_SRL = 4'b0101;
    localparam ALU_XOR = 4'b0111;

    always @(*) begin
        // defaults
        alu_ctrl  = ALU_ADD;
        reg_write = 1'b0;

        // Only R-type for now
        if (opcode == 7'b0110011) begin
            reg_write = 1'b1;

            case (funct3)

                3'b000: begin
                    if (funct7 == 7'b0000000)
                        alu_ctrl = ALU_ADD;
                    else if (funct7 == 7'b0100000)
                        alu_ctrl = ALU_SUB;
                end

                3'b111: alu_ctrl = ALU_AND;
                3'b110: alu_ctrl = ALU_OR;
                3'b100: alu_ctrl = ALU_XOR;
                3'b001: alu_ctrl = ALU_SLL;
                3'b101: alu_ctrl = ALU_SRL;
                3'b010: alu_ctrl = ALU_SLT;

                default: alu_ctrl = ALU_ADD;
            endcase
        end
    end

endmodule

`default_nettype wire
