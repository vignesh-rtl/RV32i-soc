`timescale 1ns / 1ps
`default_nettype none

module data_mem (
    input  wire        clk,

    input  wire        mem_we,      // store enable
    input  wire        mem_re,      // load enable

    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    //--------------------------------------------------
    // 4KB RAM (1024 x 32)
    //--------------------------------------------------
    reg [31:0] mem [0:1023];

    wire [9:0] word_addr;
    assign word_addr = addr[11:2];

    //--------------------------------------------------
    // WRITE
    //--------------------------------------------------
    always @(posedge clk) begin
        if (mem_we)
            mem[word_addr] <= wdata;
    end

    //--------------------------------------------------
    // READ
    //--------------------------------------------------
    assign rdata = mem_re ? mem[word_addr] : 32'b0;

endmodule

`default_nettype wire
