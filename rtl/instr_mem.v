module instr_mem (
    input  wire [31:0] addr,
    output wire [31:0] inst
);

    reg [31:0] memory [0:255];

    wire [7:0] word_addr = addr[9:2];

//    assign inst = memory[word_addr];
assign inst = (addr[31:2] === 30'bx) ? 32'h00000013 :
              memory[word_addr];
    initial begin
        $display("Loading firmware.hex...");
        $readmemh("firmware.hex", memory);
    end

endmodule
