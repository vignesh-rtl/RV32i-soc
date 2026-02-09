`timescale 1ns / 1ps
`default_nettype none

module datapath (
    input  wire        clk,
    input  wire        rst,

    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,

    input  wire [3:0]  alu_ctrl,
    input  wire        reg_write,

    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        mem_to_reg,

    output wire        zero_flag
);

wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] alu_result;
wire [31:0] mem_rdata;
wire [31:0] writeback_data;

/////////////////////////////////////////////////
// REGISTER FILE
/////////////////////////////////////////////////
reg_file REGFILE (
    .clk(clk),
    .rst(rst),

    .rs1_addr(rs1_addr),
    .rs1_data(rs1_data),

    .rs2_addr(rs2_addr),
    .rs2_data(rs2_data),

    .rd_we(reg_write),
    .rd_addr(rd_addr),
    .rd_data(writeback_data)
);

/////////////////////////////////////////////////
// ALU
/////////////////////////////////////////////////
alu ALU (
    .op_a(rs1_data),
    .op_b(rs2_data),
    .alu_ctrl(alu_ctrl),
    .result(alu_result),
    .zero(zero_flag)
);

/////////////////////////////////////////////////
// DATA MEMORY
/////////////////////////////////////////////////
data_mem DATA_MEM (
    .clk(clk),
    .mem_we(mem_write),
    .mem_re(mem_read),
    .addr(alu_result),
    .wdata(rs2_data),
    .rdata(mem_rdata)
);

/////////////////////////////////////////////////
// WRITEBACK MUX
/////////////////////////////////////////////////
assign writeback_data =
        mem_to_reg ? mem_rdata : alu_result;

endmodule

`default_nettype wire
