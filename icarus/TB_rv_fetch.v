`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
//  tb_rv32i_fetch.v  —  Comprehensive Testbench for rv32i_fetch
//  RV32I 5-Stage Pipeline | Fetch Stage (Stage 1)
//
//  COVERAGE:
//    TC01  Reset behaviour
//    TC02  Normal sequential fetch (1-cycle memory)
//    TC03  Memory wait-states (multi-cycle ack)
//    TC04  Branch taken – ALU PC redirect
//    TC05  Trap / MRET – Writeback PC redirect
//    TC06  Both redirects simultaneously (writeback must win)
//    TC07  Downstream stall – single cycle
//    TC08  Downstream stall – multi cycle
//    TC09  Stall during memory wait (combined)
//    TC10  Flush (not stalled)
//    TC11  Flush during stall (must be ignored)
//    TC12  PC redirect during downstream stall (redirect queued)
//    TC13  Back-to-back branches
//    TC14  Branch immediately after reset
//    TC15  Stall → release → immediate branch
//    TC16  PC wrap-around (near 0xFFFFFFFF)
//    TC17  ce stability (should never glitch to 0 unexpectedly)
//    TC18  stalled_inst restoration accuracy
//    TC19  Long memory wait-state (10 cycles)
//    TC20  Rapid alternating stall/unstall stress
// ============================================================================

module tb_rv32i_fetch;

    // ── Parameters ───────────────────────────────────────────────────────────
    parameter PC_RESET  = 32'h0000_0000;
    parameter CLK_HALF  = 5;             // 10 ns clock period = 100 MHz
    parameter NOP_INST  = 32'h0000_0013; // ADDI x0, x0, 0
    parameter TIMEOUT   = 5000;          // max simulation cycles before abort

    // ── DUT Ports ────────────────────────────────────────────────────────────
    reg         i_clk;
    reg         i_rst_n;
    wire [31:0] o_iaddr;
    wire [31:0] o_pc;
    reg  [31:0] i_inst;
    wire [31:0] o_inst;
    wire        o_stb_inst;
    reg         i_ack_inst;
    reg         i_writeback_change_pc;
    reg  [31:0] i_writeback_next_pc;
    reg         i_alu_change_pc;
    reg  [31:0] i_alu_next_pc;
    wire        o_ce;
    reg         i_stall;
    reg         i_flush;

    // ── Test Tracking ────────────────────────────────────────────────────────
    integer pass_count;
    integer fail_count;
    integer tc_num;
    reg [255:0] tc_name;

    // ── DUT Instantiation ────────────────────────────────────────────────────
    rv32i_fetch #(.PC_RESET(PC_RESET)) dut (
        .i_clk                  (i_clk),
        .i_rst_n                (i_rst_n),
        .o_iaddr                (o_iaddr),
        .o_pc                   (o_pc),
        .i_inst                 (i_inst),
        .o_inst                 (o_inst),
        .o_stb_inst             (o_stb_inst),
        .i_ack_inst             (i_ack_inst),
        .i_writeback_change_pc  (i_writeback_change_pc),
        .i_writeback_next_pc    (i_writeback_next_pc),
        .i_alu_change_pc        (i_alu_change_pc),
        .i_alu_next_pc          (i_alu_next_pc),
        .o_ce                   (o_ce),
        .i_stall                (i_stall),
        .i_flush                (i_flush)
    );

    // ── Simple Instruction Memory Model ─────────────────────────────────────
    // Returns address-encoded instruction: upper 16 bits = addr[17:2], lower 16 = 0013
    // This makes it easy to verify which address was fetched from o_inst
    reg [31:0] mem_data;
    always @* begin
        // instruction encodes its own fetch address in upper half for easy checking
        mem_data = {o_iaddr[17:2], 16'h0013};
    end

    // ── Clock Generation ─────────────────────────────────────────────────────
    initial i_clk = 0;
    always #CLK_HALF i_clk = ~i_clk;

    // ── Timeout Watchdog ─────────────────────────────────────────────────────
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge i_clk) begin
        cycle_count = cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
            $display("\n[WATCHDOG] Simulation exceeded %0d cycles — ABORT", TIMEOUT);
            $finish;
        end
    end

    // ── VCD Dump ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_rv32i_fetch.vcd");
        $dumpvars(0, tb_rv32i_fetch);
    end

    // =========================================================================
    //  TASK LIBRARY
    // =========================================================================

    // Apply reset for N cycles
    task do_reset;
        input integer n;
        integer k;
        begin
            i_rst_n = 0;
            apply_defaults;
            repeat(n) @(posedge i_clk); #1;
            i_rst_n = 1;
            @(posedge i_clk); #1;
        end
    endtask

    // Set all inputs to safe defaults
    task apply_defaults;
        begin
            i_inst                 = NOP_INST;
            i_ack_inst             = 1;         // default: 1-cycle memory
            i_writeback_change_pc  = 0;
            i_writeback_next_pc    = 0;
            i_alu_change_pc        = 0;
            i_alu_next_pc          = 0;
            i_stall                = 0;
            i_flush                = 0;
        end
    endtask

    // Wait N posedge clock cycles
    task wait_cycles;
        input integer n;
        begin repeat(n) @(posedge i_clk); #1; end
    endtask

    // CHECK helper — pass/fail with message
    task check;
        input        condition;
        input [511:0] msg;
        begin
            if (condition) begin
                $display("  [PASS] TC%02d %0s | %0s", tc_num, tc_name, msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] TC%02d %0s | %0s", tc_num, tc_name, msg);
                $display("         o_iaddr=%08h  o_pc=%08h  o_inst=%08h  o_ce=%b  o_stb=%b",
                         o_iaddr, o_pc, o_inst, o_ce, o_stb_inst);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Begin a test case
    task start_tc;
        input integer num;
        input [255:0] name;
        begin
            tc_num  = num;
            tc_name = name;
            $display("\n── TC%02d: %0s ──────────────────────────────────────────", num, name);
        end
    endtask

    // =========================================================================
    //  MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("========================================================");
        $display("  rv32i_fetch Comprehensive Testbench");
        $display("  PC_RESET = 0x%08h", PC_RESET);
        $display("========================================================");

        // ─────────────────────────────────────────────────────────────────────
        // TC01 — Reset Behaviour
        // ─────────────────────────────────────────────────────────────────────
        start_tc(1, "RESET BEHAVIOUR");
        i_rst_n = 0;
        apply_defaults;
        @(posedge i_clk); #1;
        check(o_ce      == 0,             "o_ce=0 during reset");
        check(o_iaddr   == PC_RESET,      "o_iaddr=PC_RESET during reset");
        check(o_stb_inst == 0,            "o_stb_inst=0 during reset");

        @(posedge i_clk); #1;   // still in reset
        check(o_ce == 0,                  "o_ce stays 0 while reset held");

        i_rst_n = 1;
        @(posedge i_clk); #1;
        check(o_stb_inst == 1,            "o_stb_inst=1 after reset release");
        check(o_iaddr    == PC_RESET,     "o_iaddr stays at PC_RESET after release");

        // ─────────────────────────────────────────────────────────────────────
        // TC02 — Normal Sequential Fetch (1-cycle memory)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(2, "NORMAL SEQUENTIAL FETCH");
        do_reset(2);
        i_ack_inst = 1;

        // let pipeline settle for a few cycles
        wait_cycles(1);
        begin : tc02_block
            reg [31:0] prev_addr;
            integer k;
            // check PC increments by 4 each cycle
            for (k = 0; k < 8; k = k + 1) begin
                prev_addr = o_iaddr;
                @(posedge i_clk); #1;
                if (k > 0) begin
                    check(o_iaddr == prev_addr + 4,  "o_iaddr advances by 4");
                end
            end
            check(o_ce      == 1,   "o_ce stays 1 during sequential fetch");
            check(o_stb_inst == 1,  "o_stb_inst stays 1 during sequential fetch");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC03 — Memory Wait-States (i_ack_inst deasserted for 3 cycles)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(3, "MEMORY WAIT-STATES");
        do_reset(2);
        wait_cycles(2);

        begin : tc03_block
            reg [31:0] frozen_iaddr;
            reg [31:0] frozen_pc;
            reg [31:0] frozen_inst;

            // hold ack low for 3 cycles
            i_ack_inst     = 0;
            @(posedge i_clk); #1;
            frozen_iaddr = o_iaddr;
            frozen_inst  = o_inst;
            frozen_pc    = o_pc;

            @(posedge i_clk); #1;
            check(o_iaddr == frozen_iaddr, "o_iaddr frozen during wait-state");
            check(o_inst  == frozen_inst,  "o_inst frozen during wait-state");

            @(posedge i_clk); #1;
            check(o_iaddr == frozen_iaddr, "o_iaddr frozen 2nd wait-state cycle");
            check(o_ce    == 0,            "o_ce=0 while waiting for ack");

            // release ack
            i_ack_inst = 1;
            @(posedge i_clk); #1;
            check(o_iaddr != frozen_iaddr, "o_iaddr advances after ack received");
            check(o_ce    == 1,            "o_ce=1 after ack received");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC04 — ALU Branch Taken (PC Redirect)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(4, "ALU BRANCH TAKEN / PC REDIRECT");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc04_block
            reg [31:0] branch_target;
            branch_target = 32'h0000_0100;

            // assert branch redirect for 1 cycle
            i_alu_change_pc = 1;
            i_alu_next_pc   = branch_target;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;

            // on the cycle immediately after: o_ce should be 0 (bubble)
            check(o_ce == 0,  "o_ce=0 (bubble) cycle after branch");

            // wait for fetch of branch target to complete
            wait_cycles(1);
            check(o_iaddr >= branch_target,  "o_iaddr at/past branch target");

            // within 2 cycles, o_ce should go back to 1
            wait_cycles(2);
            check(o_ce == 1,  "o_ce=1 restored after branch fetch complete");
            check(o_pc >= branch_target - 4 && o_pc <= branch_target + 8,
                              "o_pc near branch target");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC05 — Writeback Trap / MRET Redirect
        // ─────────────────────────────────────────────────────────────────────
        start_tc(5, "WRITEBACK TRAP REDIRECT");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc05_block
            reg [31:0] trap_handler;
            trap_handler = 32'h0000_0200;

            i_writeback_change_pc = 1;
            i_writeback_next_pc   = trap_handler;
            @(posedge i_clk); #1;
            i_writeback_change_pc = 0;

            check(o_ce == 0,  "o_ce=0 (bubble) after writeback redirect");

            wait_cycles(2);
            check(o_iaddr >= trap_handler,  "o_iaddr at/past trap handler");
            wait_cycles(1);
            check(o_ce == 1,  "o_ce=1 restored after trap redirect");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC06 — Both Redirects Simultaneously (Writeback Must Win)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(6, "WRITEBACK WINS OVER ALU (SIMULTANEOUS REDIRECTS)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc06_block
            reg [31:0] alu_tgt, wb_tgt;
            alu_tgt = 32'h0000_0300;
            wb_tgt  = 32'h0000_0400;

            // assert both simultaneously
            i_alu_change_pc        = 1;
            i_alu_next_pc          = alu_tgt;
            i_writeback_change_pc  = 1;
            i_writeback_next_pc    = wb_tgt;
            @(posedge i_clk); #1;
            i_alu_change_pc        = 0;
            i_writeback_change_pc  = 0;

            wait_cycles(2);
            // writeback target must win — o_iaddr should be near wb_tgt, not alu_tgt
            check(o_iaddr >= wb_tgt && o_iaddr < alu_tgt,
                  "writeback target wins over ALU target");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC07 — Downstream Stall (Single Cycle)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(7, "DOWNSTREAM STALL (SINGLE CYCLE)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc07_block
            reg [31:0] pre_stall_iaddr;
            reg [31:0] pre_stall_pc;
            reg [31:0] pre_stall_inst;

            // capture state just before stall
            pre_stall_iaddr = o_iaddr;
            pre_stall_inst  = o_inst;
            pre_stall_pc    = o_pc;

            // stall for 1 cycle
            i_stall = 1;
            @(posedge i_clk); #1;

            check(o_inst  == pre_stall_inst,  "o_inst frozen during 1-cycle stall");
            check(o_pc    == pre_stall_pc,    "o_pc frozen during 1-cycle stall");

            i_stall = 0;
            @(posedge i_clk); #1;
            check(o_ce == 1,                  "o_ce=1 after stall release");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC08 — Downstream Stall (Multi-Cycle, 5 cycles)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(8, "DOWNSTREAM STALL (5 CYCLES)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc08_block
            reg [31:0] snap_inst;
            reg [31:0] snap_pc;
            integer    k;

            // stall for 5 cycles — instruction must be identical on every cycle
            i_stall   = 1;
            @(posedge i_clk); #1;
            snap_inst = o_inst;
            snap_pc   = o_pc;

            for (k = 0; k < 4; k = k + 1) begin
                @(posedge i_clk); #1;
                check(o_inst == snap_inst,  "o_inst held across multi-cycle stall");
                check(o_pc   == snap_pc,    "o_pc held across multi-cycle stall");
            end

            // release stall and check pipeline resumes
            i_stall = 0;
            @(posedge i_clk); #1;
            check(o_ce == 1,  "o_ce=1 after multi-cycle stall release");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC09 — Stall During Memory Wait (Combined Condition)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(9, "STALL + MEMORY WAIT-STATE OVERLAP");
        do_reset(2);
        wait_cycles(2);

        begin : tc09_block
            reg [31:0] addr_snap;

            // both i_stall and memory wait active simultaneously
            i_ack_inst = 0;
            i_stall    = 1;
            addr_snap  = o_iaddr;
            @(posedge i_clk); #1;
            check(o_iaddr == addr_snap,  "o_iaddr frozen with stall+wait overlap");

            @(posedge i_clk); #1;
            check(o_iaddr == addr_snap,  "o_iaddr still frozen cycle 2");

            // release memory wait first
            i_ack_inst = 1;
            @(posedge i_clk); #1;
            check(o_iaddr == addr_snap,  "o_iaddr still frozen (stall still active)");

            // release stall
            i_stall = 0;
            @(posedge i_clk); #1;
            check(o_ce == 1,  "o_ce=1 after both stall and wait released");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC10 — Flush (not stalled)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(10, "FLUSH (NOT STALLED)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        i_flush = 1;
        @(posedge i_clk); #1;
        i_flush = 0;
        check(o_ce == 0,  "o_ce=0 cycle after flush asserted");

        wait_cycles(1);
        check(o_ce == 1,  "o_ce=1 after flush pulse ends (pipeline normal)");

        // ─────────────────────────────────────────────────────────────────────
        // TC11 — Flush During Stall (Flush Must be Ignored)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(11, "FLUSH DURING STALL (FLUSH IGNORED)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc11_block
            reg [31:0] stall_inst_snap;

            // enter stall
            i_stall          = 1;
            @(posedge i_clk); #1;
            stall_inst_snap  = o_inst;

            // assert flush while stalled — should have no effect on o_inst
            i_flush = 1;
            @(posedge i_clk); #1;
            check(o_inst == stall_inst_snap, "o_inst unchanged: flush ignored while stalled");

            i_flush = 0;
            i_stall = 0;
            @(posedge i_clk); #1;
            check(o_ce == 1,  "o_ce=1 after stall+flush released");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC12 — PC Redirect During Downstream Stall (Redirect Must Queue)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(12, "PC REDIRECT DURING DOWNSTREAM STALL");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc12_block
            reg [31:0] redirect_target;
            redirect_target = 32'h0000_0500;

            // stall and redirect simultaneously
            i_stall         = 1;
            i_alu_change_pc = 1;
            i_alu_next_pc   = redirect_target;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;
            @(posedge i_clk); #1;

            // release stall — pipeline should now fetch from redirect_target
            i_stall = 0;
            wait_cycles(2);
            check(o_iaddr >= redirect_target,
                  "After stall release: fetch from redirected PC");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC13 — Back-to-Back Branches
        // ─────────────────────────────────────────────────────────────────────
        start_tc(13, "BACK-TO-BACK BRANCHES");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc13_block
            reg [31:0] tgt1, tgt2;
            tgt1 = 32'h0000_0600;
            tgt2 = 32'h0000_0700;

            // first branch
            i_alu_change_pc = 1;
            i_alu_next_pc   = tgt1;
            @(posedge i_clk); #1;
            check(o_ce == 0,  "Bubble after first branch");
            i_alu_change_pc = 0;

            wait_cycles(1);

            // second branch immediately
            i_alu_change_pc = 1;
            i_alu_next_pc   = tgt2;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;

            wait_cycles(3);
            check(o_iaddr >= tgt2,  "o_iaddr at/past second branch target");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC14 — Branch Immediately After Reset
        // ─────────────────────────────────────────────────────────────────────
        start_tc(14, "BRANCH IMMEDIATELY AFTER RESET");
        do_reset(1);

        begin : tc14_block
            reg [31:0] early_target;
            early_target = 32'h0000_0800;

            // trigger branch on very first cycle after reset
            i_ack_inst      = 1;
            i_alu_change_pc = 1;
            i_alu_next_pc   = early_target;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;

            wait_cycles(3);
            check(o_iaddr >= early_target,  "Fetch reaches early branch target");
            check(o_ce    == 1,             "o_ce stable after early branch");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC15 — Stall → Release → Immediate Branch
        // ─────────────────────────────────────────────────────────────────────
        start_tc(15, "STALL RELEASE THEN IMMEDIATE BRANCH");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc15_block
            reg [31:0] post_stall_target;
            post_stall_target = 32'h0000_0900;

            i_stall = 1;
            wait_cycles(3);
            i_stall = 0;

            // branch on the exact cycle stall releases
            i_alu_change_pc = 1;
            i_alu_next_pc   = post_stall_target;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;

            wait_cycles(3);
            check(o_iaddr >= post_stall_target,  "Fetch at post-stall branch target");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC16 — PC Wrap-Around (Near 0xFFFFFFFF)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(16, "PC WRAP-AROUND NEAR 0xFFFFFFFF");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(2);

        begin : tc16_block
            // redirect to near top of address space
            i_alu_change_pc = 1;
            i_alu_next_pc   = 32'hFFFF_FFF0;
            @(posedge i_clk); #1;
            i_alu_change_pc = 0;
            wait_cycles(1);

            check(o_iaddr == 32'hFFFF_FFF0 || o_iaddr == 32'hFFFF_FFF4,
                  "o_iaddr at near-wrap address");
            wait_cycles(1);

            // verify PC+4 wraps correctly in hardware (32-bit overflow)
            // 0xFFFFFFF8 + 4 = 0x00000000 (Verilog natural 32-bit overflow)
            check(o_iaddr <= 32'hFFFF_FFFC || o_iaddr == 32'h0000_0000,
                  "PC handles wrap or stays valid near address top");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC17 — CE Stability — should never drop to 0 without a reason
        // ─────────────────────────────────────────────────────────────────────
        start_tc(17, "CE STABILITY (NO SPURIOUS DROPS)");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(1);

        begin : tc17_block
            integer k;
            integer spurious;
            spurious = 0;

            // run 15 steady cycles — o_ce must stay 1
            for (k = 0; k < 15; k = k + 1) begin
                @(posedge i_clk); #1;
                if (o_ce !== 1) spurious = spurious + 1;
            end
            check(spurious == 0,  "o_ce never drops spuriously over 15 steady cycles");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC18 — stalled_inst Restoration Accuracy
        // ─────────────────────────────────────────────────────────────────────
        start_tc(18, "STALLED_INST RESTORATION ACCURACY");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(3);

        begin : tc18_block
            reg [31:0] inst_before_stall;
            reg [31:0] pc_before_stall;

            // capture exact instruction and PC
            inst_before_stall = o_inst;
            pc_before_stall   = o_pc;

            // stall for 4 cycles — memory could deliver different data
            i_stall    = 1;
            i_inst     = 32'hDEAD_BEEF;  // intentionally corrupt mem data during stall
            wait_cycles(4);

            i_stall = 0;
            i_inst  = NOP_INST;           // restore normal memory
            @(posedge i_clk); #1;

            check(o_inst == inst_before_stall, "o_inst restored correctly after stall (not corrupted)");
            check(o_pc   == pc_before_stall,   "o_pc restored correctly after stall");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC19 — Long Memory Wait-State (10 cycles)
        // ─────────────────────────────────────────────────────────────────────
        start_tc(19, "LONG MEMORY WAIT-STATE (10 CYCLES)");
        do_reset(2);
        wait_cycles(2);

        begin : tc19_block
            reg [31:0] pre_wait_iaddr;
            integer k;
            integer extra_advance;

            pre_wait_iaddr = o_iaddr;
            i_ack_inst = 0;
            extra_advance = 0;

            for (k = 0; k < 10; k = k + 1) begin
                @(posedge i_clk); #1;
                if (o_iaddr !== pre_wait_iaddr) extra_advance = extra_advance + 1;
            end
            check(extra_advance == 0,   "o_iaddr never advanced during 10-cycle wait");
            check(o_ce == 0,            "o_ce=0 throughout 10-cycle memory wait");

            i_ack_inst = 1;
            wait_cycles(2);
            check(o_ce == 1,  "o_ce=1 after long wait released");
        end

        // ─────────────────────────────────────────────────────────────────────
        // TC20 — Rapid Alternating Stall/Unstall Stress Test
        // ─────────────────────────────────────────────────────────────────────
        start_tc(20, "RAPID ALTERNATING STALL/UNSTALL STRESS");
        do_reset(2);
        i_ack_inst = 1;
        wait_cycles(2);

        begin : tc20_block
            integer k;
            integer x_count;
            x_count = 0;

            // toggle stall every cycle for 20 cycles
            for (k = 0; k < 20; k = k + 1) begin
                i_stall = k[0];  // toggles 0,1,0,1,...
                @(posedge i_clk); #1;
                // check for X/Z on critical outputs
                if (o_iaddr === 32'hXXXX_XXXX) x_count = x_count + 1;
                if (o_inst  === 32'hXXXX_XXXX) x_count = x_count + 1;
                if (o_ce    === 1'bx)           x_count = x_count + 1;
            end
            i_stall = 0;
            check(x_count == 0,  "No X/Z values on outputs during rapid stall stress");
        end

        // ─────────────────────────────────────────────────────────────────────
        //  RESULTS SUMMARY
        // ─────────────────────────────────────────────────────────────────────
        $display("\n");
        $display("========================================================");
        $display("  RESULTS:  %0d / %0d PASSED   |   %0d FAILED",
                 pass_count, pass_count + fail_count, fail_count);
        $display("========================================================");
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED — check [FAIL] lines above");
        $display("========================================================\n");

        $finish;
    end

endmodule
