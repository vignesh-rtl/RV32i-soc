//`timescale 1ns / 1ps
//`default_nettype none

//module instr_mem (
//    input  wire [31:0] addr,
//    output wire [31:0] inst
//);

//    // 32 instructions max (for now)
//    reg [31:0] memory [0:31];

//    // word aligned access
//    wire [4:0] word_addr = addr[6:2];

//    assign inst = memory[word_addr];

//    //--------------------------------------------------
//    // Example instructions (R-type only)
//    //--------------------------------------------------
//    initial begin
//        // add x6, x8, x9
//        memory[0] = 32'h00940333;

//        // sub x7, x18, x19
//        memory[1] = 32'h413903b3;

//        // xor x28, x22, x23
//        memory[2] = 32'h017b4e33;

//        // and x31, x12, x13
//        memory[3] = 32'h00d67fb3;
//    end

//endmodule

//`default_nettype wire

`timescale 1ns / 1ps
`default_nettype none

module instr_mem (
    input  wire [31:0] addr,
    output reg  [31:0] inst
);

always @(*) begin
    case(addr)

        32'd0: inst = 32'h002081B3; // add x3,x1,x2

        default: inst = 32'h00000013; // nop
    endcase
end

endmodule

`default_nettype wire
