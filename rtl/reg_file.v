`timescale 1ns / 1ps
`default_nettype none

module reg_file (
    input  wire        clk,
    input  wire        rst,

    // read port 1
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    // read port 2
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // write port
    input  wire        rd_we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    // --------------------------------------------------
    // Register storage
    // --------------------------------------------------
    reg [31:0] regs [0:31];

    integer i;

    // --------------------------------------------------
    // Reset logic
    // --------------------------------------------------
    // synchronous reset (recommended for FPGA)
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end
        else begin
            // write operation
            if (rd_we && (rd_addr != 5'd0))
                regs[rd_addr] <= rd_data;
        end
    end
    
    always @(posedge clk) begin
    if (rst) begin
        regs[0]  <= 32'd0;
        regs[1]  <= 32'd5;   // test value
        regs[2]  <= 32'd7;   // test value
        regs[3]  <= 32'd0;
        regs[4]  <= 32'd0;
        regs[5]  <= 32'd0;
        regs[6]  <= 32'd0;
        regs[7]  <= 32'd0;
        regs[8]  <= 32'd0;
        regs[9]  <= 32'd0;
        regs[10] <= 32'd0;
        regs[11] <= 32'd0;
        regs[12] <= 32'd0;
        regs[13] <= 32'd0;
        regs[14] <= 32'd0;
        regs[15] <= 32'd0;
        regs[16] <= 32'd0;
        regs[17] <= 32'd0;
        regs[18] <= 32'd0;
        regs[19] <= 32'd0;
        regs[20] <= 32'd0;
        regs[21] <= 32'd0;
        regs[22] <= 32'd0;
        regs[23] <= 32'd0;
        regs[24] <= 32'd0;
        regs[25] <= 32'd0;
        regs[26] <= 32'd0;
        regs[27] <= 32'd0;
        regs[28] <= 32'd0;
        regs[29] <= 32'd0;
        regs[30] <= 32'd0;
        regs[31] <= 32'd0;
    end
    else begin
        if (rd_we && (rd_addr != 5'd0))
            regs[rd_addr] <= rd_data;
    end
end
    // --------------------------------------------------
    // Read ports (combinational)
    // --------------------------------------------------
    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

endmodule

`default_nettype wire
