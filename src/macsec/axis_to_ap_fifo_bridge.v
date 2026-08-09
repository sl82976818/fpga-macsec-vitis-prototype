// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// ==============================================================
// AXI-Stream to AP_FIFO Bridge
// ==============================================================
// Converts AXI-Stream (64-bit) to AP_FIFO (128-bit) format
// with clock domain crossing from MAC domain to HLS domain
//
// Aggregation: 2 x 64-bit beats → 1 x 128-bit block
// ==============================================================

`timescale 1ns / 1ps

`include "macsec_types.vh"

module axis_to_ap_fifo_bridge #
(
    parameter integer MAC_DATA_BYTES  = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer BLOCK_SIZE_BYTES = `MACSEC_BLOCK_SIZE_BYTES,
    parameter integer SAME_CLK = 0
)
(


    input  wire                           mac_clk,
    input  wire                           mac_rst,


    input  wire [`MACSEC_MAC_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [MAC_DATA_BYTES-1:0]            s_axis_tkeep,
    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire                                s_axis_tlast,


    input  wire                           hls_clk,
    input  wire                           hls_rst,


    output wire [`MACSEC_HLS_DATA_WIDTH-1:0]   m_plaintext_dout,
    output wire                                m_plaintext_empty_n,
    input  wire                                m_plaintext_read,


    output wire [63:0]                         m_length_dout,
    output wire                                m_length_empty_n,
    input  wire                                m_length_read,


    output wire                                m_end_dout,
    output wire                                m_end_empty_n,
    input  wire                                m_end_read,


    output wire                                frame_start,
    output wire                                frame_end
);


    localparam [2:0]
        ST_IDLE        = 3'd0,
        ST_FIRST_BEAT  = 3'd1,
        ST_HOLD        = 3'd2,
        ST_FRAME_END   = 3'd3;
    localparam DEBUG_LOG = 1'b0;


    reg [2:0] state, state_next;
    reg [1:0] beat_count;


    reg [`MACSEC_HLS_DATA_WIDTH-1:0] block_data;
    reg block_valid;
    reg first_beat_pending;
    reg flush_in_progress;


    reg [31:0] frame_byte_count;
    reg frame_start_reg;
    reg frame_end_reg;
    reg frame_meta_valid_reg;
    reg [63:0] frame_meta_length_bits_reg;
    localparam integer META_QUEUE_DEPTH = 16;
    localparam integer META_QUEUE_PTR_W = 4;
    reg [63:0] meta_len_mem [0:META_QUEUE_DEPTH-1];
    reg [META_QUEUE_PTR_W-1:0] meta_wr_ptr_reg = {META_QUEUE_PTR_W{1'b0}};
    reg [META_QUEUE_PTR_W-1:0] meta_rd_ptr_reg = {META_QUEUE_PTR_W{1'b0}};
    reg [META_QUEUE_PTR_W:0] meta_count_reg = {META_QUEUE_PTR_W+1{1'b0}};
    reg meta_deq_reg = 1'b0;
    reg meta_enq_pending_reg = 1'b0;
    reg [63:0] meta_enq_len_reg = 64'd0;

    (* keep = "true" *) reg [31:0] dbg_frame_end_pulse_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_meta_enq_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_meta_deq_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_len_wr_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_end_wr_cnt_reg = 32'd0;
    reg meta_can_enq_reg;
    reg meta_can_deq_reg;
    reg [META_QUEUE_PTR_W:0] meta_next_count_reg;
    reg [META_QUEUE_PTR_W-1:0] meta_next_wr_ptr_reg;
    reg [META_QUEUE_PTR_W-1:0] meta_next_rd_ptr_reg;


    wire [63:0] output_length_bits;
    reg length_fifo_wr_en_reg;

    reg [63:0] length_store;


    wire [`MACSEC_HLS_DATA_WIDTH-1:0] fifo_din;
    wire fifo_wr_en;
    wire fifo_full;
    wire [`MACSEC_HLS_DATA_WIDTH-1:0] fifo_dout;
    wire fifo_empty;
    wire fifo_rd_en;

    wire length_fifo_din;
    wire length_fifo_wr_en;
    wire length_fifo_full;
    wire [63:0] length_fifo_dout;
    wire length_fifo_empty;
    wire length_fifo_rd_en;

    wire end_fifo_din;
    wire end_fifo_wr_en;
    wire end_fifo_full;
    wire end_fifo_dout;
    wire end_fifo_empty;
    wire end_fifo_rd_en;


    reg mac_rst_sync_hls;
    reg hls_rst_sync_mac;


    always @(posedge hls_clk or posedge mac_rst) begin
        if (mac_rst) begin
            mac_rst_sync_hls <= 1'b1;
        end else begin
            mac_rst_sync_hls <= 1'b0;
        end
    end


    always @(posedge mac_clk or posedge hls_rst) begin
        if (hls_rst) begin
            hls_rst_sync_mac <= 1'b1;
        end else begin
            hls_rst_sync_mac <= 1'b0;
        end
    end


    wire wr_rst;
    wire rd_rst;
    assign wr_rst = mac_rst;
    assign rd_rst = mac_rst_sync_hls || hls_rst;

    function [7:0] keep_byte_count;
        input [MAC_DATA_BYTES-1:0] keep;
        integer i;
        begin
            keep_byte_count = 8'd0;
            for (i = 0; i < MAC_DATA_BYTES; i = i + 1) begin
                keep_byte_count = keep_byte_count + keep[i];
            end
        end
    endfunction

    initial begin
        $display("[%t] %m PARAM MAC_DATA_BYTES=%0d", $time, MAC_DATA_BYTES);
    end


    assign s_axis_tready = (state == ST_IDLE || state == ST_FIRST_BEAT || state == ST_HOLD) &&
        !fifo_full && !block_valid && (meta_count_reg < META_QUEUE_DEPTH);


    reg [2:0] dbg_state_prev;
    always @(posedge mac_clk) begin
        dbg_state_prev <= state;
        if (DEBUG_LOG && state != dbg_state_prev) begin
            $display("[%t] %m BRIDGE FSM: %s -> %s, beat_count=%d, tlast=%b, first_pending=%b, flush=%b",
                $time,
                (dbg_state_prev==ST_IDLE)?"IDLE":
                (dbg_state_prev==ST_FIRST_BEAT)?"FIRST_BEAT":
                (dbg_state_prev==ST_HOLD)?"HOLD":
                (dbg_state_prev==ST_FRAME_END)?"FRAME_END":"UNKNOWN",
                (state==ST_IDLE)?"IDLE":
                (state==ST_FIRST_BEAT)?"FIRST_BEAT":
                (state==ST_HOLD)?"HOLD":
                (state==ST_FRAME_END)?"FRAME_END":"UNKNOWN",
                beat_count, s_axis_tlast, first_beat_pending, flush_in_progress);
        end
    end


    always @(posedge mac_clk) begin
        if (mac_rst) begin
            state <= ST_IDLE;
            beat_count <= 2'b0;
            block_data <= `MACSEC_HLS_DATA_WIDTH'h0;
            block_valid <= 1'b0;
            first_beat_pending <= 1'b0;
            frame_byte_count <= 32'h0;
            frame_start_reg <= 1'b0;
            frame_end_reg <= 1'b0;
            frame_meta_valid_reg <= 1'b0;
            frame_meta_length_bits_reg <= 64'd0;
            flush_in_progress <= 1'b0;
            dbg_frame_end_pulse_cnt_reg <= 32'd0;
            dbg_meta_enq_cnt_reg <= 32'd0;
            dbg_meta_deq_cnt_reg <= 32'd0;
            dbg_len_wr_cnt_reg <= 32'd0;
            dbg_end_wr_cnt_reg <= 32'd0;
        end else begin
            frame_start_reg <= 1'b0;
            frame_end_reg <= 1'b0;
            frame_meta_valid_reg <= 1'b0;

            if (block_valid && !fifo_full) begin
                block_valid <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin

                        frame_byte_count <= keep_byte_count(s_axis_tkeep);
                        if (DEBUG_LOG) begin
                            $display("[%t] %m BRIDGE IN: keep=%h bytes=%0d last=%b data=%h",
                                $time, s_axis_tkeep, keep_byte_count(s_axis_tkeep), s_axis_tlast, s_axis_tdata);
                        end
                        if (keep_byte_count(s_axis_tkeep) != 0) begin
                            beat_count <= 2'b1;

                            block_data[63:0] <= s_axis_tdata;
                            block_valid <= 1'b0;
                            first_beat_pending <= 1'b1;
                        end else begin
                            beat_count <= 2'b0;
                            block_valid <= 1'b0;
                            first_beat_pending <= 1'b0;
                        end
                        frame_start_reg <= 1'b1;

                        if (s_axis_tlast) begin

                            state <= ST_FRAME_END;
                        end else begin
                            state <= ST_HOLD;
                        end
                    end
                end

                ST_FIRST_BEAT: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        frame_byte_count <= frame_byte_count + keep_byte_count(s_axis_tkeep);
                        if (keep_byte_count(s_axis_tkeep) != 0) begin
                            beat_count <= 2'b1;
                            block_data[63:0] <= s_axis_tdata;
                            first_beat_pending <= 1'b1;
                        end else begin
                            beat_count <= 2'b0;
                            first_beat_pending <= 1'b0;
                        end

                        if (s_axis_tlast) begin
                            state <= ST_FRAME_END;
                        end else begin
                            state <= ST_HOLD;
                        end
                    end
                end

                ST_HOLD: begin

                    if (s_axis_tvalid && s_axis_tready) begin

                        block_data[127:64] <= s_axis_tdata;
                        block_valid <= 1'b1;
                        first_beat_pending <= 1'b0;
                        beat_count <= 2'b0;
                        frame_byte_count <= frame_byte_count + keep_byte_count(s_axis_tkeep);

                        if (s_axis_tlast) begin
                            state <= ST_FRAME_END;
                        end else begin
                            state <= ST_FIRST_BEAT;
                        end
                    end
                    flush_in_progress <= 1'b0;
                end

                ST_FRAME_END: begin


                    if (!flush_in_progress) begin
                        flush_in_progress <= 1'b1;
                        frame_end_reg <= 1'b1;
                        frame_meta_valid_reg <= (frame_byte_count != 0);
                        frame_meta_length_bits_reg <= ({32'h0, frame_byte_count} << 3);
                        if (frame_byte_count != 0) begin
                            dbg_frame_end_pulse_cnt_reg <= dbg_frame_end_pulse_cnt_reg + 32'd1;
                        end
                        if (first_beat_pending) begin
                            block_valid <= 1'b1;
                            first_beat_pending <= 1'b0;
                        end
                    end else begin
                        if (!block_valid) begin
                            flush_in_progress <= 1'b0;
                            state <= ST_IDLE;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end


    assign output_length_bits = {32'h0, frame_byte_count} << 3;
    wire axis_hs = s_axis_tvalid && s_axis_tready;
    wire frame_last_hs = axis_hs && s_axis_tlast;


    reg dbg_length_wr_en;
    initial dbg_length_wr_en = 0;
    always @(posedge mac_clk) begin
        if (DEBUG_LOG && length_fifo_wr_en_reg) begin
            dbg_length_wr_en <= 1'b1;
            $display("[%t] %m BRIDGE LWR2: length=0x%h frame_bytes=%0d fifo_full=%b",
                $time, length_store, frame_byte_count, length_fifo_full);
        end else begin
            dbg_length_wr_en <= 1'b0;
        end
    end


    assign fifo_din = block_data;
    assign fifo_wr_en = block_valid && !fifo_full;
    always @(posedge mac_clk) begin
        if (DEBUG_LOG && fifo_wr_en) begin
            $display("[%t] %m BRIDGE DATA_WR fifo_din=%h", $time, fifo_din);
        end
    end

    generate if (SAME_CLK) begin : g_plaintext_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(`MACSEC_CDC_FIFO_DEPTH),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(10),
        .USE_ADV_FEATURES("0000")
    ) u_plaintext_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_en(fifo_wr_en),
        .din(fifo_din),
        .full(fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(fifo_rd_en),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_plaintext_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(`MACSEC_CDC_FIFO_DEPTH),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(10),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_plaintext_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_clk(mac_clk),
        .wr_en(fifo_wr_en),
        .din(fifo_din),
        .full(fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(hls_clk),
        .rd_en(fifo_rd_en),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    assign m_plaintext_dout = fifo_dout;
    assign m_plaintext_empty_n = !fifo_empty;
    assign fifo_rd_en = m_plaintext_read && !fifo_empty;


    always @(posedge mac_clk) begin
        if (mac_rst) begin
            length_store <= 64'h0;
            length_fifo_wr_en_reg <= 1'b0;
            meta_wr_ptr_reg <= {META_QUEUE_PTR_W{1'b0}};
            meta_rd_ptr_reg <= {META_QUEUE_PTR_W{1'b0}};
            meta_count_reg <= {META_QUEUE_PTR_W+1{1'b0}};
            meta_deq_reg <= 1'b0;
            meta_enq_pending_reg <= 1'b0;
            meta_enq_len_reg <= 64'd0;
        end else begin

            length_fifo_wr_en_reg <= 1'b0;
            meta_deq_reg <= 1'b0;


            if (frame_meta_valid_reg) begin
                meta_enq_pending_reg <= 1'b1;
                meta_enq_len_reg <= frame_meta_length_bits_reg;
            end


            begin
                meta_can_enq_reg = meta_enq_pending_reg && (meta_count_reg < META_QUEUE_DEPTH);


                meta_can_deq_reg = (meta_count_reg != 0) && !length_fifo_full && !end_fifo_full;

                meta_next_count_reg = meta_count_reg;
                meta_next_wr_ptr_reg = meta_wr_ptr_reg;
                meta_next_rd_ptr_reg = meta_rd_ptr_reg;

                if (meta_can_enq_reg) begin
                    meta_len_mem[meta_wr_ptr_reg] <= meta_enq_len_reg;
                    meta_next_wr_ptr_reg = meta_wr_ptr_reg + 1'b1;
                    meta_next_count_reg = meta_next_count_reg + 1'b1;
                    meta_enq_pending_reg <= 1'b0;
                    dbg_meta_enq_cnt_reg <= dbg_meta_enq_cnt_reg + 32'd1;
                end


                if (meta_can_deq_reg) begin


                    length_store <= meta_len_mem[meta_rd_ptr_reg];
                    length_fifo_wr_en_reg <= 1'b1;
                    meta_deq_reg <= 1'b1;
                    meta_next_rd_ptr_reg = meta_rd_ptr_reg + 1'b1;
                    meta_next_count_reg = meta_next_count_reg - 1'b1;
                    dbg_meta_deq_cnt_reg <= dbg_meta_deq_cnt_reg + 32'd1;
                end

                meta_wr_ptr_reg <= meta_next_wr_ptr_reg;
                meta_rd_ptr_reg <= meta_next_rd_ptr_reg;
                meta_count_reg <= meta_next_count_reg;
            end
            if (length_fifo_wr_en_reg) begin
                dbg_len_wr_cnt_reg <= dbg_len_wr_cnt_reg + 32'd1;
            end
            if (end_fifo_wr_en) begin
                dbg_end_wr_cnt_reg <= dbg_end_wr_cnt_reg + 32'd1;
            end
        end
    end

    assign length_fifo_din = meta_len_mem[meta_rd_ptr_reg];
    assign length_fifo_wr_en = length_fifo_wr_en_reg;

    generate if (SAME_CLK) begin : g_length_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(256),
        .READ_DATA_WIDTH(64),
        .WRITE_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(240),
        .PROG_EMPTY_THRESH(8),
        .USE_ADV_FEATURES("0000")
    ) u_length_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_en(length_fifo_wr_en),
        .din(length_store),
        .full(length_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(length_fifo_rd_en),
        .dout(length_fifo_dout),
        .empty(length_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_length_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(256),
        .READ_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(64),
        .PROG_FULL_THRESH(240),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(8),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_length_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_clk(mac_clk),
        .wr_en(length_fifo_wr_en),
        .din(length_store),
        .full(length_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(hls_clk),
        .rd_en(length_fifo_rd_en),
        .dout(length_fifo_dout),
        .empty(length_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate


    assign m_length_dout = length_fifo_dout;
    assign m_length_empty_n = !length_fifo_empty;
    assign length_fifo_rd_en = m_length_read && !length_fifo_empty;


    assign end_fifo_din = 1'b1;


    assign end_fifo_wr_en = meta_deq_reg;

    generate if (SAME_CLK) begin : g_end_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(256),
        .READ_DATA_WIDTH(1),
        .WRITE_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(240),
        .PROG_EMPTY_THRESH(8),
        .USE_ADV_FEATURES("0000")
    ) u_end_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_en(end_fifo_wr_en),
        .din(end_fifo_din),
        .full(end_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(end_fifo_rd_en),
        .dout(end_fifo_dout),
        .empty(end_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_end_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(256),
        .READ_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(1),
        .PROG_FULL_THRESH(240),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(8),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_end_fifo (
        .sleep(1'b0),
        .rst(wr_rst),
        .wr_clk(mac_clk),
        .wr_en(end_fifo_wr_en),
        .din(1'b1),
        .full(end_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(hls_clk),
        .rd_en(end_fifo_rd_en),
        .dout(end_fifo_dout),
        .empty(end_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    assign m_end_dout = end_fifo_dout;
    assign m_end_empty_n = !end_fifo_empty;
    assign end_fifo_rd_en = m_end_read && !end_fifo_empty;


    assign frame_start = frame_start_reg;
    assign frame_end = frame_end_reg;

endmodule
