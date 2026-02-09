`timescale 1ns / 1ps
`default_nettype none

module processor_top(
    input  wire clk,
    input  wire rst,
    output wire zero_flag
);

wire [31:0] instruction;
wire [31:0] pc;

wire [3:0] alu_ctrl;
wire reg_write;
wire mem_read;
wire mem_write;
wire mem_to_reg;

/////////////////////////////////////////////////
// IFU
/////////////////////////////////////////////////
ifu IFU (
    .clk(clk),
    .rst(rst),
    .instruction(instruction),
    .pc(pc)
);

/////////////////////////////////////////////////
// CONTROL
/////////////////////////////////////////////////
control CONTROL (
    .funct7(instruction[31:25]),
    .funct3(instruction[14:12]),
    .opcode(instruction[6:0]),

    .alu_ctrl(alu_ctrl),
    .reg_write(reg_write),

    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_to_reg(mem_to_reg)
);

/////////////////////////////////////////////////
// DATAPATH
/////////////////////////////////////////////////
datapath DATAPATH (
    .clk(clk),
    .rst(rst),

    .rs1_addr(instruction[19:15]),
    .rs2_addr(instruction[24:20]),
    .rd_addr(instruction[11:7]),

    .alu_ctrl(alu_ctrl),
    .reg_write(reg_write),

    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_to_reg(mem_to_reg),

    .zero_flag(zero_flag)
);

endmodule

`default_nettype wire
