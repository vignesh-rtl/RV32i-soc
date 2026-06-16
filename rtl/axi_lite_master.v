`timescale 1ns / 1ps

module axi_lite_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                  aclk,
    input  wire                  aresetn,
    
    // AXI4-LITE MASTER INTERFACE
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [2:0]            m_axi_awprot,
    
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,
    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output reg  [3:0]            m_axi_wstrb,
    
    input  wire                  m_axi_bvalid,
    output reg                   m_axi_bready,
    input  wire [1:0]            m_axi_bresp,
    
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,
    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [2:0]            m_axi_arprot,
    
    input  wire                  m_axi_rvalid,
    output reg                   m_axi_rready,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,

    // USER INTERFACE
    input  wire                  user_wr_req,
    input  wire [ADDR_WIDTH-1:0] user_wr_addr,
    input  wire [DATA_WIDTH-1:0] user_wr_data,
    output reg                   user_wr_done,
    output reg  [1:0]            user_wr_resp,
    
    input  wire                  user_rd_req,
    input  wire [ADDR_WIDTH-1:0] user_rd_addr,
    output reg  [DATA_WIDTH-1:0] user_rd_data,
    output reg                   user_rd_done,
    output reg  [1:0]            user_rd_resp
);

    reg aw_done, w_done, b_done, ar_done, r_done;

    // Timeout Logic
    reg [7:0] timeout_counter;
    wire timeout = (timeout_counter == 8'hFF);
    always @(posedge aclk) begin
        if (!aresetn) begin
            timeout_counter <= 0;
        end else begin
            if (user_wr_req || user_rd_req) begin
                if (!user_wr_done && !user_rd_done) begin
                    if (!timeout) timeout_counter <= timeout_counter + 1;
                end else begin
                    timeout_counter <= 0;
                end
            end else begin
                timeout_counter <= 0;
            end
        end
    end

    // AW Channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= 0;
            aw_done       <= 1'b0;
        end else begin
            if (user_wr_req && !aw_done && !m_axi_awvalid && !user_wr_done) begin
                m_axi_awvalid <= 1'b1;
                m_axi_awaddr  <= user_wr_addr;
            end else if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awvalid <= 1'b0;
                aw_done       <= 1'b1;
            end
            if (b_done || timeout || !user_wr_req) begin
                aw_done <= 1'b0;
                m_axi_awvalid <= 1'b0;
            end
        end
    end

    // W Channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_wvalid <= 1'b0;
            m_axi_wdata  <= 0;
            m_axi_wstrb  <= 0;
            w_done       <= 1'b0;
        end else begin
            if (user_wr_req && !w_done && !m_axi_wvalid && !user_wr_done) begin
                m_axi_wvalid <= 1'b1;
                m_axi_wdata  <= user_wr_data;
                m_axi_wstrb  <= {(DATA_WIDTH/8){1'b1}};
            end else if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wvalid <= 1'b0;
                w_done       <= 1'b1;
            end
            if (b_done || timeout || !user_wr_req) begin
                w_done <= 1'b0;
                m_axi_wvalid <= 1'b0;
            end
        end
    end

    // B Channel & Write Done
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_bready <= 1'b0;
            user_wr_done <= 1'b0;
            b_done       <= 1'b0;
        end else begin
            // Wait for user to drop request before dropping done flag
            if (user_wr_done && !user_wr_req) begin
                user_wr_done <= 1'b0;
            end
            
            b_done <= 1'b0;
            
            if (aw_done && w_done && !m_axi_bready) begin
                m_axi_bready <= 1'b1;
            end else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bready <= 1'b0;
                user_wr_resp <= m_axi_bresp;
                user_wr_done <= 1'b1;
                b_done       <= 1'b1;
            end
            
            if (timeout && user_wr_req && !user_wr_done) begin
                m_axi_bready <= 1'b0;
                user_wr_resp <= 2'b11;
                user_wr_done <= 1'b1;
                b_done       <= 1'b1;
            end
        end
    end

    // AR Channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= 0;
            ar_done       <= 1'b0;
        end else begin
            if (user_rd_req && !ar_done && !m_axi_arvalid && !user_rd_done) begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr  <= user_rd_addr;
            end else if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arvalid <= 1'b0;
                ar_done       <= 1'b1;
            end
            if (r_done || timeout || !user_rd_req) begin
                ar_done <= 1'b0;
                m_axi_arvalid <= 1'b0;
            end
        end
    end

    // R Channel & Read Done
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_rready <= 1'b0;
            user_rd_done <= 1'b0;
            r_done       <= 1'b0;
        end else begin
            if (user_rd_done && !user_rd_req) begin
                user_rd_done <= 1'b0;
            end
            
            r_done <= 1'b0;
            
            if (ar_done && !m_axi_rready) begin
                m_axi_rready <= 1'b1;
            end else if (m_axi_rready && m_axi_rvalid) begin
                m_axi_rready <= 1'b0;
                user_rd_data <= m_axi_rdata;
                user_rd_resp <= m_axi_rresp;
                user_rd_done <= 1'b1;
                r_done       <= 1'b1;
            end
            
            if (timeout && user_rd_req && !user_rd_done) begin
                m_axi_rready <= 1'b0;
                user_rd_data <= 0;
                user_rd_resp <= 2'b11;
                user_rd_done <= 1'b1;
                r_done       <= 1'b1;
            end
        end
    end

endmodule
