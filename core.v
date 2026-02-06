`timescale 1ns / 1ps
`default_nettype none

module processor_top (
    input  wire clk,
    input  wire rst,
    output wire zero_flag
);

    //--------------------------------------------------
    // Internal wires
    //--------------------------------------------------
    wire [31:0] instruction;
    wire [31:0] pc;

    wire [3:0]  alu_control;
    wire        regwrite;

    wire [31:0] alu_result;

    //--------------------------------------------------
    // Instruction Fetch Unit
    //--------------------------------------------------
    ifu IFU (
        .clk(clk),
        .rst(rst),
        .instruction(instruction),
        .pc(pc)
    );

    //--------------------------------------------------
    // Control Unit
    //--------------------------------------------------
    control CONTROL (
        .funct7   (instruction[31:25]),
        .funct3   (instruction[14:12]),
        .opcode   (instruction[6:0]),
        .alu_ctrl (alu_control),
        .reg_write(regwrite)
    );

    //--------------------------------------------------
    // Datapath
    //--------------------------------------------------
    datapath DATAPATH (
        .clk(clk),
        .rst(rst),

        .rs1_addr(instruction[19:15]),
        .rs2_addr(instruction[24:20]),
        .rd_addr (instruction[11:7]),

        .alu_ctrl(alu_control),
        .reg_write(regwrite),

        .alu_result(alu_result),
        .zero_flag(zero_flag)
    );

endmodule

`default_nettype wire
