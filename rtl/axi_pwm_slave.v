`timescale 1ns / 1ps

module axi_pwm_slave (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    
    // AXI4-Lite Slave Interface
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    
    // Physical LED Output
    output reg         pwm_out 
);

    // ==========================================
    // BULLETPROOF INTERNAL RESET 
    // ==========================================
    reg [3:0] por_counter = 0;
    wire internal_aresetn = (por_counter == 15);
    always @(posedge s_axi_aclk) begin
        if (por_counter < 15) por_counter <= por_counter + 1;
    end

    // ==========================================
    // REGISTERS
    // ==========================================
    reg [31:0] pwm_period = 32'd12000; // Default 1kHz at 12MHz
    reg [31:0] pwm_duty   = 32'd0;     // Default OFF
    reg [31:0] counter    = 32'd0;
    
    // PWM Generator
    always @(posedge s_axi_aclk) begin
        if (~internal_aresetn) begin
            counter <= 0;
            pwm_out <= 0;
        end else begin
            if (counter >= pwm_period - 1) begin
                counter <= 0;
            end else begin
                counter <= counter + 1;
            end
            
            // LED is active-high, so 1 = ON, 0 = OFF
            if (counter < pwm_duty) begin
                pwm_out <= 1'b1;
            end else begin
                pwm_out <= 1'b0;
            end
        end
    end

    // ==========================================
    // AXI LITE HANDSHAKE LOGIC
    // ==========================================
    reg aw_en = 1;
    reg [31:0] awaddr = 0;

    always @(posedge s_axi_aclk) begin
        // AW Channel
        if (~internal_aresetn) begin
            s_axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                awaddr <= s_axi_awaddr;
                aw_en <= 1'b0;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_awready <= 1'b0;
                aw_en <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
            end
        end

        // W Channel & Write to Registers
        if (~internal_aresetn) begin
            s_axi_wready <= 1'b0;
            pwm_period <= 32'd12000;
            pwm_duty <= 32'd0;
        end else begin
            if (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                s_axi_wready <= 1'b1;
                // Address decoding based on bits 3:2
                case (s_axi_awaddr[3:2])
                    2'b00: pwm_period <= s_axi_wdata; // 0x0
                    2'b01: pwm_duty   <= s_axi_wdata; // 0x4
                endcase
            end else begin
                s_axi_wready <= 1'b0;
            end
        end

        // B Channel
        if (~internal_aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
        end else begin
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end

        // AR Channel
        if (~internal_aresetn) begin
            s_axi_arready <= 1'b0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end
        end

        // R Channel
        if (~internal_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
        end else begin
            if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                case (s_axi_araddr[3:2])
                    2'b00: s_axi_rdata <= pwm_period;
                    2'b01: s_axi_rdata <= pwm_duty;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
