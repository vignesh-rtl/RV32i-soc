`timescale 1ns / 1ps
`default_nettype none

module datapath (
    input  wire        clk,
    input  wire        rst,

    // Register selection
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,

    // Control signals
    input  wire [3:0]  alu_ctrl,
    input  wire        reg_write,

    // Outputs (for observation/debug)
    output wire [31:0] alu_result,
    output wire        zero_flag
);

    // --------------------------------------------------
    // Internal connections
    // --------------------------------------------------
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] write_data;

    // --------------------------------------------------
    // Register File
    // --------------------------------------------------
    reg_file u_regfile (
        .rs1_addr      (rs1_addr),
        .rs2_addr      (rs2_addr),
        .rd_addr       (rd_addr),
        .rd_data       (write_data),
        .rs1_data      (rs1_data),
        .rs2_data      (rs2_data),
        .rd_we         (reg_write),  
        .clk           (clk),
        .rst           (rst)
    );

    // --------------------------------------------------
    // ALU
    // --------------------------------------------------
    alu u_alu (
        .op_a     (rs1_data),
        .op_b     (rs2_data),
        .alu_ctrl (alu_ctrl),
        .result   (write_data),
        .zero     (zero_flag)
    );

    assign alu_result = write_data;

endmodule

`default_nettype wire
