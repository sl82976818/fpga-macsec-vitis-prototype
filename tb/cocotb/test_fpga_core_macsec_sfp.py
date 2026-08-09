# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2020-2023 The Regents of the University of California

# Modified by Le Sun, 2026 for the FPGA AES-GCM / experimental MACsec prototype.
# Modifications Copyright (c) 2026 Le Sun.
# Changes: MACsec TX/RX loopback integration test on fpga_core with AES-GCM HLS IP.
#
import logging
import os
import struct
import sys
import traceback
import glob
import shutil
from collections import Counter

import scapy.utils
from scapy.layers.l2 import Ether, ARP
from scapy.layers.inet import IP, UDP

import cocotb_test.simulator

import cocotb
from cocotb.result import SimTimeoutError
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, with_timeout

from cocotbext.axi import AxiStreamBus
from cocotbext.eth import XgmiiSource, XgmiiSink, XgmiiFrame
from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.xilinx.us import UltraScalePlusPcieDevice

try:
    import mqnic
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        import mqnic
    finally:
        del sys.path[0]


class TB(object):
    def __init__(self, dut, msix_count=32):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        tb_log_level = os.getenv("MACSEC_TB_LOG_LEVEL", "INFO").upper()
        self.log.setLevel(getattr(logging, tb_log_level, logging.INFO))
        # Keep third-party model logs low by default; test-specific diagnostics
        # are emitted by cocotb.tb and explicit MACsec debug snapshots.
        for noisy_log in ("cocotb.mqnic", "cocotb.pcie", "cocotb.fpga_core"):
            SimLog(noisy_log).setLevel(logging.WARNING)

        # PCIe
        self.rc = RootComplex()

        self.rc.max_payload_size = 0x1  # 256 bytes
        self.rc.max_read_request_size = 0x2  # 512 bytes

        self.dev = UltraScalePlusPcieDevice(
            # configuration options
            pcie_generation=3,
            pcie_link_width=8,
            user_clk_frequency=250e6,
            alignment="dword",
            cq_straddle=len(dut.core_inst.pcie_if_inst.pcie_us_if_cq_inst.rx_req_tlp_valid_reg) > 1,
            cc_straddle=len(dut.core_inst.pcie_if_inst.pcie_us_if_cc_inst.out_tlp_valid) > 1,
            rq_straddle=len(dut.core_inst.pcie_if_inst.pcie_us_if_rq_inst.out_tlp_valid) > 1,
            rc_straddle=len(dut.core_inst.pcie_if_inst.pcie_us_if_rc_inst.rx_cpl_tlp_valid_reg) > 1,
            rc_4tlp_straddle=len(dut.core_inst.pcie_if_inst.pcie_us_if_rc_inst.rx_cpl_tlp_valid_reg) > 2,
            pf_count=1,
            max_payload_size=1024,
            enable_client_tag=True,
            enable_extended_tag=True,
            enable_parity=False,
            enable_rx_msg_interface=False,
            enable_sriov=False,
            enable_extended_configuration=False,

            pf0_msi_enable=False,
            pf0_msi_count=32,
            pf1_msi_enable=False,
            pf1_msi_count=1,
            pf2_msi_enable=False,
            pf2_msi_count=1,
            pf3_msi_enable=False,
            pf3_msi_count=1,
            pf0_msix_enable=True,
            pf0_msix_table_size=msix_count-1,
            pf0_msix_table_bir=0,
            pf0_msix_table_offset=0x00010000,
            pf0_msix_pba_bir=0,
            pf0_msix_pba_offset=0x00018000,
            pf1_msix_enable=False,
            pf1_msix_table_size=0,
            pf1_msix_table_bir=0,
            pf1_msix_table_offset=0x00000000,
            pf1_msix_pba_bir=0,
            pf1_msix_pba_offset=0x00000000,
            pf2_msix_enable=False,
            pf2_msix_table_size=0,
            pf2_msix_table_bir=0,
            pf2_msix_table_offset=0x00000000,
            pf2_msix_pba_bir=0,
            pf2_msix_pba_offset=0x00000000,
            pf3_msix_enable=False,
            pf3_msix_table_size=0,
            pf3_msix_table_bir=0,
            pf3_msix_table_offset=0x00000000,
            pf3_msix_pba_bir=0,
            pf3_msix_pba_offset=0x00000000,

            # signals
            # Clock and Reset Interface
            user_clk=dut.clk_250mhz,
            user_reset=dut.rst_250mhz,
            # user_lnk_up
            # sys_clk
            # sys_clk_gt
            # sys_reset
            # phy_rdy_out

            # Requester reQuest Interface
            rq_bus=AxiStreamBus.from_prefix(dut, "m_axis_rq"),
            pcie_rq_seq_num0=dut.s_axis_rq_seq_num_0,
            pcie_rq_seq_num_vld0=dut.s_axis_rq_seq_num_valid_0,
            pcie_rq_seq_num1=dut.s_axis_rq_seq_num_1,
            pcie_rq_seq_num_vld1=dut.s_axis_rq_seq_num_valid_1,
            # pcie_rq_tag0
            # pcie_rq_tag1
            # pcie_rq_tag_av
            # pcie_rq_tag_vld0
            # pcie_rq_tag_vld1

            # Requester Completion Interface
            rc_bus=AxiStreamBus.from_prefix(dut, "s_axis_rc"),

            # Completer reQuest Interface
            cq_bus=AxiStreamBus.from_prefix(dut, "s_axis_cq"),
            # pcie_cq_np_req
            # pcie_cq_np_req_count

            # Completer Completion Interface
            cc_bus=AxiStreamBus.from_prefix(dut, "m_axis_cc"),

            # Transmit Flow Control Interface
            # pcie_tfc_nph_av=dut.pcie_tfc_nph_av,
            # pcie_tfc_npd_av=dut.pcie_tfc_npd_av,

            # Configuration Management Interface
            cfg_mgmt_addr=dut.cfg_mgmt_addr,
            cfg_mgmt_function_number=dut.cfg_mgmt_function_number,
            cfg_mgmt_write=dut.cfg_mgmt_write,
            cfg_mgmt_write_data=dut.cfg_mgmt_write_data,
            cfg_mgmt_byte_enable=dut.cfg_mgmt_byte_enable,
            cfg_mgmt_read=dut.cfg_mgmt_read,
            cfg_mgmt_read_data=dut.cfg_mgmt_read_data,
            cfg_mgmt_read_write_done=dut.cfg_mgmt_read_write_done,
            # cfg_mgmt_debug_access

            # Configuration Status Interface
            # cfg_phy_link_down
            # cfg_phy_link_status
            # cfg_negotiated_width
            # cfg_current_speed
            cfg_max_payload=dut.cfg_max_payload,
            cfg_max_read_req=dut.cfg_max_read_req,
            # cfg_function_status
            # cfg_vf_status
            # cfg_function_power_state
            # cfg_vf_power_state
            # cfg_link_power_state
            # cfg_err_cor_out
            # cfg_err_nonfatal_out
            # cfg_err_fatal_out
            # cfg_local_error_out
            # cfg_local_error_valid
            # cfg_rx_pm_state
            # cfg_tx_pm_state
            # cfg_ltssm_state
            cfg_rcb_status=dut.cfg_rcb_status,
            # cfg_obff_enable
            # cfg_pl_status_change
            # cfg_tph_requester_enable
            # cfg_tph_st_mode
            # cfg_vf_tph_requester_enable
            # cfg_vf_tph_st_mode

            # Configuration Received Message Interface
            # cfg_msg_received
            # cfg_msg_received_data
            # cfg_msg_received_type

            # Configuration Transmit Message Interface
            # cfg_msg_transmit
            # cfg_msg_transmit_type
            # cfg_msg_transmit_data
            # cfg_msg_transmit_done

            # Configuration Flow Control Interface
            cfg_fc_ph=dut.cfg_fc_ph,
            cfg_fc_pd=dut.cfg_fc_pd,
            cfg_fc_nph=dut.cfg_fc_nph,
            cfg_fc_npd=dut.cfg_fc_npd,
            cfg_fc_cplh=dut.cfg_fc_cplh,
            cfg_fc_cpld=dut.cfg_fc_cpld,
            cfg_fc_sel=dut.cfg_fc_sel,

            # Configuration Control Interface
            # cfg_hot_reset_in
            # cfg_hot_reset_out
            # cfg_config_space_enable
            # cfg_dsn
            # cfg_bus_number
            # cfg_ds_port_number
            # cfg_ds_bus_number
            # cfg_ds_device_number
            # cfg_ds_function_number
            # cfg_power_state_change_ack
            # cfg_power_state_change_interrupt
            cfg_err_cor_in=dut.status_error_cor,
            cfg_err_uncor_in=dut.status_error_uncor,
            # cfg_flr_in_process
            # cfg_flr_done
            # cfg_vf_flr_in_process
            # cfg_vf_flr_func_num
            # cfg_vf_flr_done
            # cfg_pm_aspm_l1_entry_reject
            # cfg_pm_aspm_tx_l0s_entry_disable
            # cfg_req_pm_transition_l23_ready
            # cfg_link_training_enable

            # Configuration Interrupt Controller Interface
            # cfg_interrupt_int
            # cfg_interrupt_sent
            # cfg_interrupt_pending
            # cfg_interrupt_msi_enable
            # cfg_interrupt_msi_mmenable
            # cfg_interrupt_msi_mask_update
            # cfg_interrupt_msi_data
            # cfg_interrupt_msi_select
            # cfg_interrupt_msi_int
            # cfg_interrupt_msi_pending_status
            # cfg_interrupt_msi_pending_status_data_enable
            # cfg_interrupt_msi_pending_status_function_num
            # cfg_interrupt_msi_sent
            # cfg_interrupt_msi_fail
            cfg_interrupt_msix_enable=dut.cfg_interrupt_msix_enable,
            cfg_interrupt_msix_mask=dut.cfg_interrupt_msix_mask,
            cfg_interrupt_msix_vf_enable=dut.cfg_interrupt_msix_vf_enable,
            cfg_interrupt_msix_vf_mask=dut.cfg_interrupt_msix_vf_mask,
            cfg_interrupt_msix_address=dut.cfg_interrupt_msix_address,
            cfg_interrupt_msix_data=dut.cfg_interrupt_msix_data,
            cfg_interrupt_msix_int=dut.cfg_interrupt_msix_int,
            cfg_interrupt_msix_vec_pending=dut.cfg_interrupt_msix_vec_pending,
            cfg_interrupt_msix_vec_pending_status=dut.cfg_interrupt_msix_vec_pending_status,
            cfg_interrupt_msix_sent=dut.cfg_interrupt_msix_sent,
            cfg_interrupt_msix_fail=dut.cfg_interrupt_msix_fail,
            # cfg_interrupt_msi_attr
            # cfg_interrupt_msi_tph_present
            # cfg_interrupt_msi_tph_type
            # cfg_interrupt_msi_tph_st_tag
            cfg_interrupt_msi_function_number=dut.cfg_interrupt_msi_function_number,

            # Configuration Extend Interface
            # cfg_ext_read_received
            # cfg_ext_write_received
            # cfg_ext_register_number
            # cfg_ext_function_number
            # cfg_ext_write_data
            # cfg_ext_write_byte_enable
            # cfg_ext_read_data
            # cfg_ext_read_data_valid
        )

        # self.dev.log.setLevel(logging.DEBUG)

        self.rc.make_port().connect(self.dev)

        self.driver = mqnic.Driver()

        self.dev.functions[0].configure_bar(0, 2**len(dut.core_inst.core_pcie_inst.axil_ctrl_araddr), ext=True, prefetch=True)
        if hasattr(dut.core_inst.core_pcie_inst, 'pcie_app_ctrl'):
            self.dev.functions[0].configure_bar(2, 2**len(dut.core_inst.core_pcie_inst.axil_app_ctrl_araddr), ext=True, prefetch=True)

        cocotb.start_soon(Clock(dut.ptp_clk, 4, units="ns").start())
        dut.ptp_rst.setimmediatevalue(0)
        cocotb.start_soon(Clock(dut.ptp_sample_clk, 8, units="ns").start())
        if hasattr(dut, "hls_clk"):
            cocotb.start_soon(Clock(dut.hls_clk, 4, units="ns").start())
        if hasattr(dut, "hls_rst"):
            dut.hls_rst.setimmediatevalue(0)

        # Ethernet
        self.sfp_source = []
        self.sfp_sink = []

        for k in range(2):
            cocotb.start_soon(Clock(self._get_sfp_sig(k, "rx_clk"), 2.56, units="ns").start())
            source = XgmiiSource(
                self._get_sfp_sig(k, "rxd"),
                self._get_sfp_sig(k, "rxc"),
                self._get_sfp_sig(k, "rx_clk"),
                self._get_sfp_sig(k, "rx_rst"),
            )
            self.sfp_source.append(source)
            cocotb.start_soon(Clock(self._get_sfp_sig(k, "tx_clk"), 2.56, units="ns").start())
            sink = XgmiiSink(
                self._get_sfp_sig(k, "txd"),
                self._get_sfp_sig(k, "txc"),
                self._get_sfp_sig(k, "tx_clk"),
                self._get_sfp_sig(k, "tx_rst"),
            )
            self.sfp_sink.append(sink)
            self._get_sfp_sig(k, "rx_status").setimmediatevalue(1)
            self._get_sfp_sig(k, "rx_error_count").setimmediatevalue(0)
            if self._has_sfp_sig(k, "npres"):
                self._get_sfp_sig(k, "npres").setimmediatevalue(0)
            if self._has_sfp_sig(k, "los"):
                self._get_sfp_sig(k, "los").setimmediatevalue(0)

        cocotb.start_soon(Clock(dut.sfp_drp_clk, 8, units="ns").start())
        dut.sfp_drp_rst.setimmediatevalue(0)
        dut.sfp_drp_do.setimmediatevalue(0)
        dut.sfp_drp_rdy.setimmediatevalue(0)

        if hasattr(dut, "sma_in"):
            dut.sma_in.setimmediatevalue(0)

        if hasattr(dut, "sfp_i2c_scl_i"):
            dut.sfp_i2c_scl_i.setimmediatevalue(1)
        if hasattr(dut, "sfp_1_i2c_sda_i"):
            dut.sfp_1_i2c_sda_i.setimmediatevalue(1)
        if hasattr(dut, "sfp_2_i2c_sda_i"):
            dut.sfp_2_i2c_sda_i.setimmediatevalue(1)

        if hasattr(dut, "eeprom_i2c_scl_i"):
            dut.eeprom_i2c_scl_i.setimmediatevalue(1)
        if hasattr(dut, "eeprom_i2c_sda_i"):
            dut.eeprom_i2c_sda_i.setimmediatevalue(1)

        if hasattr(dut, "flash_dq_i"):
            dut.flash_dq_i.setimmediatevalue(0)

        self.loopback_enable = False
        cocotb.start_soon(self._run_loopback())

    def _get_sfp_sig(self, index, suffix):
        name_candidates = (
            f"sfp_{index}_{suffix}",
            f"sfp{index}_{suffix}",
            f"sfp_{index+1}_{suffix}",
            f"sfp{index+1}_{suffix}",
        )
        for name in name_candidates:
            if hasattr(self.dut, name):
                return getattr(self.dut, name)
        raise AttributeError(f"Missing SFP signal for index={index}, suffix={suffix}, candidates={name_candidates}")

    def _has_sfp_sig(self, index, suffix):
        name_candidates = (
            f"sfp_{index}_{suffix}",
            f"sfp{index}_{suffix}",
            f"sfp_{index+1}_{suffix}",
            f"sfp{index+1}_{suffix}",
        )
        return any(hasattr(self.dut, name) for name in name_candidates)

    async def init(self):

        self.dut.ptp_rst.setimmediatevalue(0)
        if hasattr(self.dut, "hls_rst"):
            self.dut.hls_rst.setimmediatevalue(0)
        for k in range(2):
            self._get_sfp_sig(k, "rx_rst").setimmediatevalue(0)
            self._get_sfp_sig(k, "tx_rst").setimmediatevalue(0)

        await RisingEdge(self.dut.clk_250mhz)
        await RisingEdge(self.dut.clk_250mhz)

        self.dut.ptp_rst.setimmediatevalue(1)
        if hasattr(self.dut, "hls_rst"):
            self.dut.hls_rst.setimmediatevalue(1)
        for k in range(2):
            self._get_sfp_sig(k, "rx_rst").setimmediatevalue(1)
            self._get_sfp_sig(k, "tx_rst").setimmediatevalue(1)

        await FallingEdge(self.dut.rst_250mhz)
        await Timer(100, 'ns')

        await RisingEdge(self.dut.clk_250mhz)
        await RisingEdge(self.dut.clk_250mhz)

        self.dut.ptp_rst.setimmediatevalue(0)
        if hasattr(self.dut, "hls_rst"):
            self.dut.hls_rst.setimmediatevalue(0)
        for k in range(2):
            self._get_sfp_sig(k, "rx_rst").setimmediatevalue(0)
            self._get_sfp_sig(k, "tx_rst").setimmediatevalue(0)

        await self.rc.enumerate()

    async def _run_loopback(self):
        while True:
            await RisingEdge(self.dut.clk_250mhz)

            if self.loopback_enable:
                for x in range(len(self.sfp_sink)):
                        if not self.sfp_sink[x].empty():
                            await self.sfp_source[x].send(await self.sfp_sink[x].recv())


@cocotb.test()
async def run_test_nic(dut):
    recv_timeout_us = int(os.getenv("MACSEC_RECV_TIMEOUT_US", "300"))
    bulk_recv_timeout_us = int(os.getenv("MACSEC_BULK_RECV_TIMEOUT_US", "20000"))
    recv_poll_us = int(os.getenv("MACSEC_RECV_POLL_US", "50"))
    recv_progress_every = int(os.getenv("MACSEC_RECV_PROGRESS_EVERY", "10"))
    host_diag_timeout_us = int(os.getenv("MACSEC_HOST_DIAG_TIMEOUT_US", "50"))
    xmit_timeout_us = int(os.getenv("MACSEC_XMIT_TIMEOUT_US", "2000"))
    late_grace_us = int(os.getenv("MACSEC_LATE_GRACE_US", "0"))
    allow_late = os.getenv("MACSEC_ALLOW_LATE", "0") == "1"
    test_stage = os.getenv("MACSEC_TEST_STAGE", "full").strip().lower()
    small_pkts_pre_stage = os.getenv("MACSEC_SMALL_PKTS_PRE_STAGE", "rss").strip().lower()
    small_pkts_count = int(os.getenv("MACSEC_SMALL_PKTS_COUNT", "64"))
    small_pkts_rounds = int(os.getenv("MACSEC_SMALL_PKTS_ROUNDS", "1"))
    rss_pkt_count = int(os.getenv("MACSEC_RSS_PKT_COUNT", "64"))
    rss_min_queues = int(os.getenv("MACSEC_RSS_MIN_QUEUES", "4"))
    live_debug = os.getenv("MACSEC_LIVE_DEBUG", "0") == "1"
    checkpoint_lag_warn = int(os.getenv("MACSEC_CHECKPOINT_LAG_WARN", "8"))
    checkpoint_lag_max = int(os.getenv("MACSEC_CHECKPOINT_LAG_MAX", "64"))
    small_step_check = int(os.getenv("MACSEC_SMALL_PKTS_CHECK_EVERY", "8"))
    steady_pkt_count = int(os.getenv("MACSEC_STEADY_PKT_COUNT", "64"))
    steady_burst_mode = os.getenv("MACSEC_STEADY_BURST_MODE", "0") == "1"
    stage_print = os.getenv("MACSEC_STAGE_PRINT", "1") == "1"
    require_final_strict = os.getenv("MACSEC_REQUIRE_FINAL_STRICT", "1") == "1"
    lfc_pkt_count = int(os.getenv("MACSEC_LFC_PKT_COUNT", "16"))
    lfc_step_timeout_us = int(os.getenv("MACSEC_LFC_RECV_TIMEOUT_US", str(bulk_recv_timeout_us)))
    lfc_pause_assert_timeout_us = int(os.getenv("MACSEC_LFC_PAUSE_ASSERT_TIMEOUT_US", "200"))
    lfc_pause_release_timeout_us = int(os.getenv("MACSEC_LFC_PAUSE_RELEASE_TIMEOUT_US", "400"))
    lfc_pause_assert_cycles = int(os.getenv("MACSEC_LFC_PAUSE_ASSERT_CYCLES", "4096"))
    lfc_pause_release_cycles = int(os.getenv("MACSEC_LFC_PAUSE_RELEASE_CYCLES", "8192"))
    lfc_expect_pause = os.getenv("MACSEC_LFC_EXPECT_PAUSE", "1") == "1"
    lfc_send_xoff = os.getenv("MACSEC_LFC_SEND_XOFF", "1") == "1"
    arp_mix_pairs = int(os.getenv("MACSEC_ARP_MIX_PAIRS", "8"))
    lfc_ctrl_mask_raw = os.getenv("MACSEC_LFC_CTRL_MASK", "").strip()
    debug_log_file = os.getenv("MACSEC_DEBUG_LOG_FILE", "").strip()
    heartbeat_sec = float(os.getenv("MACSEC_HEARTBEAT_SEC", "5.0"))
    macsec_frame_counts = {}
    macsec_frame_bytes = {}
    macsec_tuser_stats = {}
    macsec_tx_continuity = {}
    macsec_eth_underflow = {"count": 0}
    macsec_frame_heads = {}
    macsec_rx_pause_frames = {"count": 0}
    current_stage = {"name": "init"}
    rx_pipe_events = {
        "s_rx_frame_hs": 0,
        "s_rx1_frame_hs": 0,
        "port_in_frame_hs": 0,
        "port_out_frame_hs": 0,
        "if_fifo_in_frame_hs": 0,
        "if_fifo_out_frame_hs": 0,
        "if_axis_frame_hs": 0,
        "rx_req_hs": 0,
        "rx1_req_hs": 0,
        "dma_desc_hs": 0,
        "dma_desc_status": 0,
        "cpl_req_hs": 0,
        "cpl_req_valid_cycles": 0,
        "port_out_bad_or_last": 0,
        "if_fifo_out_bad_or_last": 0,
        "if_axis_bad_or_last": 0,
    }
    tx_pipe_events = {
        "if_tx_hs": 0,
        "if_tx_last_hs": 0,
        "if_tx_cpl_hs": 0,
        "if_tx_cpl_last_tag": None,
        "split_pre_last_hs": 0,
        "split_pre_in_last_hs": 0,
        "split_comp_last_hs": 0,
        "inb_last_hs": 0,
        "txw_in_frame_end_hs": 0,
        "last_gap_reported": -1,
    }

    def live(msg):
        if live_debug:
            line = f"[MACSEC_LIVE] {msg}"
            print(line, flush=True)
            if debug_log_file:
                with open(debug_log_file, "a", encoding="utf-8") as f:
                    f.write(line + "\n")
                    f.flush()

    def stage(msg):
        current_stage["name"] = msg
        if stage_print:
            line = f"[MACSEC_STAGE] {msg}"
            print(line, flush=True)
            if debug_log_file:
                with open(debug_log_file, "a", encoding="utf-8") as f:
                    f.write(line + "\n")
                    f.flush()

    def dbg(msg):
        if debug_log_file:
            with open(debug_log_file, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
                f.flush()

    async def heartbeat_task():
        # Periodic liveness marker so long-running sims are distinguishable
        # from true deadlocks in quiet stdout modes.
        if heartbeat_sec <= 0:
            return
        while True:
            await Timer(int(heartbeat_sec * 1e9), units='ns')
            live(
                "heartbeat "
                f"stage={current_stage.get('name', 'unknown')} "
                f"tx_in={macsec_frame_counts.get('tx_in', 0)} "
                f"tx_out={macsec_frame_counts.get('tx_out', 0)} "
                f"rx_in={macsec_frame_counts.get('rx_in', 0)} "
                f"rx_out={macsec_frame_counts.get('rx_out', 0)}"
            )

    def _env_bool(name):
        raw = os.getenv(name)
        if raw is None:
            return None
        val = raw.strip().lower()
        if val in ("1", "true", "yes", "on"):
            return True
        if val in ("0", "false", "no", "off"):
            return False
        raise ValueError(f"{name} expects boolean-like value, got {raw!r}")

    def _safe_int(obj):
        try:
            return int(obj.value)
        except Exception:
            return None

    def _safe_sig(sig):
        try:
            return int(sig.value)
        except Exception:
            return None

    def _safe_bit(sig, bit=0):
        val = _safe_sig(sig)
        if val is None:
            return None
        return (val >> bit) & 0x1

    def _is_pause_ctrl_head(head16):
        if len(head16) < 16:
            return False
        return (
            head16[0:6] == b"\x01\x80\xc2\x00\x00\x01" and
            head16[12:14] == b"\x88\x08" and
            head16[14:16] == b"\x00\x01"
        )

    def _try_get_sig(path):
        cur = dut
        for token in path:
            if isinstance(token, int):
                try:
                    cur = cur[token]
                except Exception:
                    return None
            else:
                if not hasattr(cur, token):
                    return None
                cur = getattr(cur, token)
        return cur

    def _log_macsec_debug(stage):
        try:
            tx = dut.mac[0].u_macsec_tx
            rx = dut.mac[0].u_macsec_rx
            tb.log.warning(
                "DBG %s TX: en=%s out_state=%s hdr_cnt=%s split_present=%s s_vr_l=%s/%s/%s m_vr_l=%s/%s/%s enc_vr_l=%s/%s/%s frame_vr_l=%s/%s/%s hold(c/t/l/e)=%s/%s/%s/%s len_cnt=%s payload_vr_l=%s/%s/%s frame_vr2_l=%s/%s/%s bridge_r(c/t/l/e)=%s/%s/%s/%s",
                stage,
                _safe_int(tx.enable),
                _safe_int(tx.out_state_reg),
                _safe_int(tx.header_fifo_count_reg),
                _safe_int(tx.split_payload_present),
                _safe_int(tx.s_axis_tvalid),
                _safe_int(tx.s_axis_tready),
                _safe_int(tx.s_axis_tlast),
                _safe_int(tx.m_axis_tvalid),
                _safe_int(tx.m_axis_tready),
                _safe_int(tx.m_axis_tlast),
                _safe_int(tx.enc_payload_tvalid),
                _safe_int(tx.enc_payload_tready),
                _safe_int(tx.enc_payload_tlast),
                _safe_int(tx.enc_frame_tvalid),
                _safe_int(tx.enc_frame_tready),
                _safe_int(tx.enc_frame_tlast),
                _safe_int(tx.cipher_hold_valid_reg),
                _safe_int(tx.tag_hold_valid_reg),
                _safe_int(getattr(tx, "len_hold_valid_reg", None)),
                _safe_int(tx.end_hold_valid_reg),
                _safe_int(tx.len_hold_count_reg),
                _safe_int(tx.enc_payload_tvalid),
                _safe_int(tx.enc_payload_tready),
                _safe_int(tx.enc_payload_tlast),
                _safe_int(tx.enc_frame_tvalid),
                _safe_int(tx.enc_frame_tready),
                _safe_int(tx.enc_frame_tlast),
                _safe_int(tx.bridge_out_cipher_read),
                _safe_int(tx.bridge_out_tag_read),
                _safe_int(tx.bridge_out_len_read),
                _safe_int(tx.bridge_out_end_read),
            )
            tb.log.warning(
                "DBG %s RX: en=%s out_state=%s hdr_cnt=%s tag_empty/full=%s/%s strip_tag_v=%s strip_p_vr_l=%s/%s/%s s_vr_l=%s/%s/%s m_vr_l=%s/%s/%s dec_vr_l=%s/%s/%s hold(p/c/l/e)=%s/%s/%s/%s dec_tag_read=%s",
                stage,
                _safe_int(rx.enable),
                _safe_int(rx.out_state_reg),
                _safe_int(rx.header_fifo_count_reg),
                _safe_int(rx.tag_fifo_empty),
                _safe_int(rx.tag_fifo_full),
                _safe_int(rx.strip_tag_valid),
                _safe_int(rx.strip_payload_tvalid),
                _safe_int(rx.strip_payload_tready),
                _safe_int(rx.strip_payload_tlast),
                _safe_int(rx.s_axis_tvalid),
                _safe_int(rx.s_axis_tready),
                _safe_int(rx.s_axis_tlast),
                _safe_int(rx.m_axis_tvalid),
                _safe_int(rx.m_axis_tready),
                _safe_int(rx.m_axis_tlast),
                _safe_int(rx.dec_payload_tvalid),
                _safe_int(rx.dec_payload_tready),
                _safe_int(rx.dec_payload_tlast),
                _safe_int(rx.plain_hold_valid_reg),
                _safe_int(rx.ctag_hold_valid_reg),
                _safe_int(rx.plen_hold_valid_reg),
                _safe_int(rx.pend_hold_valid_reg),
                _safe_int(rx.decrypt_tag_read),
            )
            for key in ("tx_in", "tx_out", "rx_in", "rx_out"):
                tb.log.warning("DBG %s lens[%s]=%s", stage, key, macsec_frame_bytes.get(key, [])[-8:])
            for key in ("tx_in", "tx_out", "rx_in", "rx_out"):
                tail = macsec_frame_heads.get(key, [])[-4:]
                tb.log.warning("DBG %s heads[%s]=%s", stage, key, [x.hex() for x in tail])
            for key in ("tx_in", "tx_out", "rx_in", "rx_out"):
                tb.log.warning("DBG %s tuser[%s]=%s", stage, key, macsec_tuser_stats.get(key, [])[-4:])
            tb.log.warning(
                "DBG %s continuity tx_out=%s underflow_count=%d underflow_now=%s",
                stage,
                macsec_tx_continuity.get("tx_out", [])[-4:],
                macsec_eth_underflow.get("count", 0),
                _safe_int(dut.mac[0].eth_mac_inst.tx_error_underflow),
            )
        except Exception as ex:
            tb.log.warning("DBG %s snapshot failed: %r", stage, ex)

    def _counter_snapshot():
        return (
            macsec_frame_counts.get("tx_in", 0),
            macsec_frame_counts.get("tx_out", 0),
            macsec_frame_counts.get("rx_in", 0),
            macsec_frame_counts.get("rx_out", 0),
        )

    async def _log_host_rx_diag(stage):
        try:
            iface = tb.driver.interfaces[0]
            qlen = len(iface.pkt_rx_queue)

            if not iface.rxq:
                tb.log.warning("DBG %s host_rx: pkt_q=%d rxq=none", stage, qlen)
                return

            rxq = iface.rxq[0]
            cq = rxq.cq

            try:
                await with_timeout(rxq.read_cons_ptr(), host_diag_timeout_us, "us")
            except SimTimeoutError:
                tb.log.warning(
                    "DBG %s host_rx: read_cons_ptr timeout_us=%d",
                    stage,
                    host_diag_timeout_us,
                )

            try:
                await with_timeout(cq.read_prod_ptr(), host_diag_timeout_us, "us")
            except SimTimeoutError:
                tb.log.warning(
                    "DBG %s host_rx: read_prod_ptr timeout_us=%d",
                    stage,
                    host_diag_timeout_us,
                )

            tb.log.warning(
                "DBG %s host_rx: pkt_q=%d rxq_prod=%d rxq_cons=%d rxq_pkts=%d rxq_bytes=%d cq_prod=%d cq_cons=%d",
                stage,
                qlen,
                int(rxq.prod_ptr),
                int(rxq.cons_ptr),
                int(rxq.packets),
                int(rxq.bytes),
                int(cq.prod_ptr),
                int(cq.cons_ptr),
            )
            dbg(
                f"[MACSEC_HOST_RX] {stage} pkt_q={qlen} rxq_prod={int(rxq.prod_ptr)} rxq_cons={int(rxq.cons_ptr)} "
                f"rxq_pkts={int(rxq.packets)} rxq_bytes={int(rxq.bytes)} cq_prod={int(cq.prod_ptr)} cq_cons={int(cq.cons_ptr)}"
            )
        except Exception as ex:
            tb.log.warning("DBG %s host_rx snapshot failed: %r", stage, ex)
            dbg(f"[MACSEC_HOST_RX] {stage} snapshot_failed={ex!r}")

    async def _log_host_tx_diag(stage):
        try:
            iface = tb.driver.interfaces[0]
            tx_swq = len(getattr(iface, "pkt_tx_queue", []))

            if not iface.txq:
                tb.log.warning("DBG %s host_tx: pkt_q=%d txq=none", stage, tx_swq)
                return

            txq = iface.txq[0]
            cq = txq.cq

            try:
                await with_timeout(txq.read_cons_ptr(), host_diag_timeout_us, "us")
            except SimTimeoutError:
                tb.log.warning(
                    "DBG %s host_tx: read_cons_ptr timeout_us=%d",
                    stage,
                    host_diag_timeout_us,
                )

            try:
                await with_timeout(cq.read_prod_ptr(), host_diag_timeout_us, "us")
            except SimTimeoutError:
                tb.log.warning(
                    "DBG %s host_tx: read_prod_ptr timeout_us=%d",
                    stage,
                    host_diag_timeout_us,
                )

            tb.log.warning(
                "DBG %s host_tx: pkt_q=%d txq_prod=%d txq_cons=%d txq_pkts=%d txq_bytes=%d cq_prod=%d cq_cons=%d",
                stage,
                tx_swq,
                int(txq.prod_ptr),
                int(txq.cons_ptr),
                int(txq.packets),
                int(txq.bytes),
                int(cq.prod_ptr),
                int(cq.cons_ptr),
            )
            dbg(
                f"[MACSEC_HOST_TX] {stage} pkt_q={tx_swq} txq_prod={int(txq.prod_ptr)} txq_cons={int(txq.cons_ptr)} "
                f"txq_pkts={int(txq.packets)} txq_bytes={int(txq.bytes)} cq_prod={int(cq.prod_ptr)} cq_cons={int(cq.cons_ptr)}"
            )
        except Exception as ex:
            tb.log.warning("DBG %s host_tx snapshot failed: %r", stage, ex)
            dbg(f"[MACSEC_HOST_TX] {stage} snapshot_failed={ex!r}")

    def _diag_sig(path):
        sig = _try_get_sig(path)
        if sig is None:
            return None
        return _safe_sig(sig)

    def _log_rx_pipeline_diag(stage):
        try:
            base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "interface_rx_inst")
            base1 = ("core_inst", "core_pcie_inst", "core_inst", "iface", 1, "interface_inst", "interface_rx_inst")
            if_base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst")
            vals = {
                "rx_req_cnt": _diag_sig(base + ("rx_req_cnt_reg",)),
                "rx_req_valid": _diag_sig(base + ("rx_req_valid",)),
                "rx_req_ready": _diag_sig(base + ("rx_req_ready",)),
                "dma_rx_desc_valid": _diag_sig(base + ("dma_rx_desc_valid",)),
                "dma_rx_desc_ready": _diag_sig(base + ("dma_rx_desc_ready",)),
                "dma_rx_desc_status_valid": _diag_sig(base + ("dma_rx_desc_status_valid",)),
                "m_axis_cpl_req_valid": _diag_sig(base + ("m_axis_cpl_req_valid",)),
                "m_axis_cpl_req_ready": _diag_sig(base + ("m_axis_cpl_req_ready",)),
                "s_axis_rx_tvalid": _diag_sig(base + ("s_axis_rx_tvalid",)),
                "s_axis_rx_tready": _diag_sig(base + ("s_axis_rx_tready",)),
                "s_axis_rx_tlast": _diag_sig(base + ("s_axis_rx_tlast",)),
                "rx_axis_tvalid_int": _diag_sig(base + ("rx_axis_tvalid_int",)),
                "rx_axis_tready_int": _diag_sig(base + ("rx_axis_tready_int",)),
                "rx_axis_tlast_int": _diag_sig(base + ("rx_axis_tlast_int",)),
                "s1_axis_rx_tvalid": _diag_sig(base1 + ("s_axis_rx_tvalid",)),
                "s1_axis_rx_tready": _diag_sig(base1 + ("s_axis_rx_tready",)),
                "s1_axis_rx_tlast": _diag_sig(base1 + ("s_axis_rx_tlast",)),
                "port_in_v": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tvalid")),
                "port_in_r": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tready")),
                "port_in_l": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tlast")),
                "port_out_v": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tvalid")),
                "port_out_r": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tready")),
                "port_out_l": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tlast")),
                "port_out_user": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tuser")),
                "if_fifo_in_v0": _safe_bit(_try_get_sig(if_base + ("axis_if_rx_fifo_tvalid",))),
                "if_fifo_in_r0": _safe_bit(_try_get_sig(if_base + ("axis_if_rx_fifo_tready",))),
                "if_fifo_in_l0": _safe_bit(_try_get_sig(if_base + ("axis_if_rx_fifo_tlast",))),
                "if_fifo_out_v": _diag_sig(if_base + ("axis_if_rx_tvalid",)),
                "if_fifo_out_r": _diag_sig(if_base + ("axis_if_rx_tready",)),
                "if_fifo_out_l": _diag_sig(if_base + ("axis_if_rx_tlast",)),
                "if_fifo_out_u": _diag_sig(if_base + ("axis_if_rx_tuser",)),
                "if_axis_v": _diag_sig(if_base + ("if_rx_axis_tvalid",)),
                "if_axis_r": _diag_sig(if_base + ("if_rx_axis_tready",)),
                "if_axis_l": _diag_sig(if_base + ("if_rx_axis_tlast",)),
                "if_axis_u": _diag_sig(if_base + ("if_rx_axis_tuser",)),
                "rx_fifo_depth0": _diag_sig(if_base + ("rx_fifo_status_depth",)),
                "rx_fifo_ovf0": _safe_bit(_try_get_sig(if_base + ("rx_fifo_status_overflow",))),
                "rx_fifo_bad0": _safe_bit(_try_get_sig(if_base + ("rx_fifo_status_bad_frame",))),
                "rx_fifo_good0": _safe_bit(_try_get_sig(if_base + ("rx_fifo_status_good_frame",))),
                "macsec_dec_cycles_last": _diag_sig(("core_inst", "mac", 0, "u_macsec_rx", "u_decrypt", "perf_run_cycles_last_reg")),
                "macsec_dec_blocks_last": _diag_sig(("core_inst", "mac", 0, "u_macsec_rx", "u_decrypt", "perf_blocks_read_last_reg")),
                "macsec_dec_frames_done": _diag_sig(("core_inst", "mac", 0, "u_macsec_rx", "u_decrypt", "perf_frames_done_reg")),
            }
            tb.log.warning(
                "DBG %s rx_pipe: rx_req_cnt=%s req_v/r=%s/%s dma_desc_v/r=%s/%s dma_desc_st_v=%s cpl_v/r=%s/%s "
                "s0_rx_v/r/l=%s/%s/%s s1_rx_v/r/l=%s/%s/%s "
                "port_in_v/r/l=%s/%s/%s port_out_v/r/l/u=%s/%s/%s/%s "
                "if_fifo_in0_v/r/l=%s/%s/%s if_fifo_out_v/r/l/u=%s/%s/%s/%s if_axis_v/r/l/u=%s/%s/%s/%s "
                "rx_fifo_st(depth/ovf/bad/good)=%s/%s/%s/%s "
                "dma_in_v/r/l=%s/%s/%s "
                "ev(s0_frame=%d s1_frame=%d port_in=%d port_out=%d if_fifo_in=%d if_fifo_out=%d if_axis=%d "
                "port_bad_or=%d if_fifo_bad_or=%d if_axis_bad_or=%d s0_req=%d s1_req=%d desc_hs=%d desc_st=%d cpl_hs=%d cpl_vcy=%d)",
                stage,
                vals["rx_req_cnt"],
                vals["rx_req_valid"],
                vals["rx_req_ready"],
                vals["dma_rx_desc_valid"],
                vals["dma_rx_desc_ready"],
                vals["dma_rx_desc_status_valid"],
                vals["m_axis_cpl_req_valid"],
                vals["m_axis_cpl_req_ready"],
                vals["s_axis_rx_tvalid"],
                vals["s_axis_rx_tready"],
                vals["s_axis_rx_tlast"],
                vals["s1_axis_rx_tvalid"],
                vals["s1_axis_rx_tready"],
                vals["s1_axis_rx_tlast"],
                vals["port_in_v"],
                vals["port_in_r"],
                vals["port_in_l"],
                vals["port_out_v"],
                vals["port_out_r"],
                vals["port_out_l"],
                vals["port_out_user"],
                vals["if_fifo_in_v0"],
                vals["if_fifo_in_r0"],
                vals["if_fifo_in_l0"],
                vals["if_fifo_out_v"],
                vals["if_fifo_out_r"],
                vals["if_fifo_out_l"],
                vals["if_fifo_out_u"],
                vals["if_axis_v"],
                vals["if_axis_r"],
                vals["if_axis_l"],
                vals["if_axis_u"],
                vals["rx_fifo_depth0"],
                vals["rx_fifo_ovf0"],
                vals["rx_fifo_bad0"],
                vals["rx_fifo_good0"],
                vals["rx_axis_tvalid_int"],
                vals["rx_axis_tready_int"],
                vals["rx_axis_tlast_int"],
                rx_pipe_events.get("s_rx_frame_hs", 0),
                rx_pipe_events.get("s_rx1_frame_hs", 0),
                rx_pipe_events.get("port_in_frame_hs", 0),
                rx_pipe_events.get("port_out_frame_hs", 0),
                rx_pipe_events.get("if_fifo_in_frame_hs", 0),
                rx_pipe_events.get("if_fifo_out_frame_hs", 0),
                rx_pipe_events.get("if_axis_frame_hs", 0),
                rx_pipe_events.get("port_out_bad_or_last", 0),
                rx_pipe_events.get("if_fifo_out_bad_or_last", 0),
                rx_pipe_events.get("if_axis_bad_or_last", 0),
                rx_pipe_events.get("rx_req_hs", 0),
                rx_pipe_events.get("rx1_req_hs", 0),
                rx_pipe_events.get("dma_desc_hs", 0),
                rx_pipe_events.get("dma_desc_status", 0),
                rx_pipe_events.get("cpl_req_hs", 0),
                rx_pipe_events.get("cpl_req_valid_cycles", 0),
            )
            dbg(
                f"[MACSEC_RX_PIPE] {stage} req_v/r={vals['rx_req_valid']}/{vals['rx_req_ready']} "
                f"dma_desc_v/r={vals['dma_rx_desc_valid']}/{vals['dma_rx_desc_ready']} "
                f"s0={vals['s_axis_rx_tvalid']}/{vals['s_axis_rx_tready']}/{vals['s_axis_rx_tlast']} "
                f"port_out={vals['port_out_v']}/{vals['port_out_r']}/{vals['port_out_l']}/{vals['port_out_user']} "
                f"if_fifo_out={vals['if_fifo_out_v']}/{vals['if_fifo_out_r']}/{vals['if_fifo_out_l']}/{vals['if_fifo_out_u']} "
                f"if_axis={vals['if_axis_v']}/{vals['if_axis_r']}/{vals['if_axis_l']}/{vals['if_axis_u']} "
                f"dec_perf(cyc/blk/f)={vals['macsec_dec_cycles_last']}/{vals['macsec_dec_blocks_last']}/{vals['macsec_dec_frames_done']} "
                f"ev_port_in={rx_pipe_events.get('port_in_frame_hs', 0)} ev_port_out={rx_pipe_events.get('port_out_frame_hs', 0)} "
                f"ev_if_fifo_out={rx_pipe_events.get('if_fifo_out_frame_hs', 0)} ev_if_axis={rx_pipe_events.get('if_axis_frame_hs', 0)} "
                f"ev_desc_hs={rx_pipe_events.get('dma_desc_hs', 0)} ev_cpl_hs={rx_pipe_events.get('cpl_req_hs', 0)}"
            )
        except Exception as ex:
            tb.log.warning("DBG %s rx_pipe snapshot failed: %r", stage, ex)
            dbg(f"[MACSEC_RX_PIPE] {stage} snapshot_failed={ex!r}")

    def _log_tx_pipeline_diag(stage):
        try:
            if_base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst")
            tx_base = if_base + ("interface_tx_inst",)
            vals = {
                "tx_req_v": _diag_sig(tx_base + ("s_axis_tx_req_valid",)),
                "tx_req_r": _diag_sig(tx_base + ("s_axis_tx_req_ready",)),
                "desc_req_v": _diag_sig(tx_base + ("m_axis_desc_req_valid",)),
                "desc_req_r": _diag_sig(tx_base + ("m_axis_desc_req_ready",)),
                "desc_st_v": _diag_sig(tx_base + ("s_axis_desc_req_status_valid",)),
                "desc_st_e": _diag_sig(tx_base + ("s_axis_desc_req_status_empty",)),
                "cpl_req_v": _diag_sig(tx_base + ("m_axis_cpl_req_valid",)),
                "cpl_req_r": _diag_sig(tx_base + ("m_axis_cpl_req_ready",)),
                "cpl_st_v": _diag_sig(tx_base + ("s_axis_cpl_req_status_valid",)),
                "dma_rd_v": _diag_sig(tx_base + ("m_axis_dma_read_desc_valid",)),
                "dma_rd_r": _diag_sig(tx_base + ("m_axis_dma_read_desc_ready",)),
                "dma_rd_st_v": _diag_sig(tx_base + ("s_axis_dma_read_desc_status_valid",)),
                "tx_v": _diag_sig(tx_base + ("m_axis_tx_tvalid",)),
                "tx_r": _diag_sig(tx_base + ("m_axis_tx_tready",)),
                "tx_l": _diag_sig(tx_base + ("m_axis_tx_tlast",)),
                "act_desc_req": _diag_sig(tx_base + ("tx_engine_inst", "active_desc_req_count_reg")),
                "start_ptr": _diag_sig(tx_base + ("tx_engine_inst", "desc_table_start_ptr_reg")),
                "tx_start_ptr": _diag_sig(tx_base + ("tx_engine_inst", "desc_table_tx_start_ptr_reg")),
                "cpl_ptr": _diag_sig(tx_base + ("tx_engine_inst", "desc_table_cpl_enqueue_start_ptr_reg")),
                "fin_ptr": _diag_sig(tx_base + ("tx_engine_inst", "desc_table_finish_ptr_reg")),
                "active_map": _diag_sig(tx_base + ("tx_engine_inst", "desc_table_active")),
                "if_tx_v": _diag_sig(if_base + ("if_tx_axis_tvalid",)),
                "if_tx_r": _diag_sig(if_base + ("if_tx_axis_tready",)),
                "if_tx_l": _diag_sig(if_base + ("if_tx_axis_tlast",)),
                "if_tx_u": _safe_int(_try_get_sig(if_base + ("if_tx_axis_tuser",))),
                "axis_if_tx_v": _diag_sig(if_base + ("axis_if_tx_tvalid",)),
                "axis_if_tx_r": _diag_sig(if_base + ("axis_if_tx_tready",)),
                "axis_if_tx_l": _diag_sig(if_base + ("axis_if_tx_tlast",)),
                "axis_if_tx_u": _safe_int(_try_get_sig(if_base + ("axis_if_tx_tuser",))),
                "axis_if_tx_fifo_v0": _safe_bit(_try_get_sig(if_base + ("axis_if_tx_fifo_tvalid",))),
                "axis_if_tx_fifo_r0": _safe_bit(_try_get_sig(if_base + ("axis_if_tx_fifo_tready",))),
                "axis_if_tx_fifo_l0": _safe_bit(_try_get_sig(if_base + ("axis_if_tx_fifo_tlast",))),
                "if_tx_cpl_v0": _safe_bit(_try_get_sig(if_base + ("axis_if_tx_cpl_valid",))),
                "if_tx_cpl_r0": _safe_bit(_try_get_sig(if_base + ("axis_if_tx_cpl_ready",))),
                "if_tx_cpl_tag0": _safe_int(_try_get_sig(if_base + ("axis_if_tx_cpl_tag",))),
                "port_tx_v": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_tx_inst", "s_axis_tx_tvalid")),
                "port_tx_r": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_tx_inst", "s_axis_tx_tready")),
                "port_tx_l": _diag_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_tx_inst", "s_axis_tx_tlast")),
                "macsec_enc_cycles_last": _diag_sig(("core_inst", "mac", 0, "u_macsec_tx", "u_encrypt", "perf_run_cycles_last_reg")),
                "macsec_enc_blocks_last": _diag_sig(("core_inst", "mac", 0, "u_macsec_tx", "u_encrypt", "perf_blocks_read_last_reg")),
                "macsec_enc_frames_done": _diag_sig(("core_inst", "mac", 0, "u_macsec_tx", "u_encrypt", "perf_frames_done_reg")),
                "txw_out_state": _diag_sig(("mac", 0, "u_macsec_tx", "out_state_reg")),
                "txw_hdr_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "header_fifo_count_reg")),
                "txw_tuser_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "tuser_fifo_count_reg")),
                "txw_ethertype_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "ethertype_fifo_count_reg")),
                "txw_cipher_empty": _diag_sig(("mac", 0, "u_macsec_tx", "cipher_fifo_empty")),
                "txw_cipher_full": _diag_sig(("mac", 0, "u_macsec_tx", "cipher_fifo_full")),
                "txw_len_full": _diag_sig(("mac", 0, "u_macsec_tx", "len_fifo_full_hls")),
                "txw_len_empty": _diag_sig(("mac", 0, "u_macsec_tx", "len_fifo_empty_hls")),
                "txw_tag_full": _diag_sig(("mac", 0, "u_macsec_tx", "tag_fifo_full_hls")),
                "txw_tag_empty": _diag_sig(("mac", 0, "u_macsec_tx", "tag_fifo_empty_hls")),
                "txw_end_full": _diag_sig(("mac", 0, "u_macsec_tx", "end_fifo_full_hls")),
                "txw_end_empty": _diag_sig(("mac", 0, "u_macsec_tx", "end_fifo_empty_hls")),
                "inb_pt_empty_n": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_plaintext_empty_n")),
                "inb_pt_read": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_plaintext_read")),
                "inb_len_empty_n": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_length_empty_n")),
                "inb_len_read": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_length_read")),
                "inb_end_empty_n": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_end_empty_n")),
                "inb_end_read": _diag_sig(("mac", 0, "u_macsec_tx", "bridge_end_read")),
                "inb_meta_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "meta_count_reg")),
                "inb_meta_deq": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "meta_deq_reg")),
                "inb_len_full": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "length_fifo_full")),
                "inb_end_full": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "end_fifo_full")),
                "inb_state": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "state")),
                "inb_frame_bytes": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "frame_byte_count")),
                "inb_frame_end_reg": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "frame_end_reg")),
                "inb_meta_valid_reg": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "frame_meta_valid_reg")),
                "inb_block_valid": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "block_valid")),
                "inb_first_pending": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "first_beat_pending")),
                "inb_meta_enq_pending": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "meta_enq_pending_reg")),
                "inb_dbg_frame_end_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "dbg_frame_end_pulse_cnt_reg")),
                "inb_dbg_meta_enq_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "dbg_meta_enq_cnt_reg")),
                "inb_dbg_meta_deq_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "dbg_meta_deq_cnt_reg")),
                "inb_dbg_len_wr_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "dbg_len_wr_cnt_reg")),
                "inb_dbg_end_wr_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "dbg_end_wr_cnt_reg")),
                "txw_split_pre_v": _diag_sig(("mac", 0, "u_macsec_tx", "split_pre_tvalid")),
                "txw_split_pre_r": _diag_sig(("mac", 0, "u_macsec_tx", "split_pre_tready")),
                "txw_split_pre_l": _diag_sig(("mac", 0, "u_macsec_tx", "split_pre_tlast")),
                "txw_split_comp_v": _diag_sig(("mac", 0, "u_macsec_tx", "split_compact_tvalid")),
                "txw_split_comp_r": _diag_sig(("mac", 0, "u_macsec_tx", "split_compact_tready")),
                "txw_split_comp_l": _diag_sig(("mac", 0, "u_macsec_tx", "split_compact_tlast")),
                "txw_incomp_count": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_compactor", "count_reg")),
                "txw_incomp_last_pending": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_compactor", "last_pending_reg")),
                "txw_incomp_m_v": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_compactor", "m_axis_tvalid")),
                "txw_incomp_m_l": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_compactor", "m_axis_tlast")),
                "inb_frame_last_hs": _diag_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "frame_last_hs")),
                "outb_state": _diag_sig(("mac", 0, "u_macsec_tx", "u_out_bridge", "state_reg")),
                "outb_frame_active": _diag_sig(("mac", 0, "u_macsec_tx", "u_out_bridge", "frame_active_reg")),
                "outb_len": _diag_sig(("mac", 0, "u_macsec_tx", "u_out_bridge", "frame_length_bytes_reg")),
                "outb_count": _diag_sig(("mac", 0, "u_macsec_tx", "u_out_bridge", "frame_byte_count_reg")),
                "enc_state": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "state_reg")),
                "enc_blocks_rem": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "blocks_remaining_reg")),
                "enc_blocks_exp": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "blocks_expected_reg")),
                "enc_payload_cons": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "payload_consumed_reg")),
                "enc_len_pop": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "length_pop_reg")),
                "enc_end_pop": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "end_pop_reg")),
                "enc_ap_start": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ap_start_reg")),
                "enc_ip_done": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ip_ap_done")),
                "enc_ip_idle": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ip_ap_idle")),
                "enc_ip_ready": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ip_ap_ready")),
                "enc_plain_read": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ip_plaintext_read")),
                "enc_endlen_read": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "ip_end_length_read")),
                "enc_dbg_ap_start_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "dbg_ap_start_cnt_reg")),
                "enc_dbg_len_pop_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "dbg_len_pop_cnt_reg")),
                "enc_dbg_end_pop_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "dbg_end_pop_cnt_reg")),
                "enc_dbg_plain_read_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "dbg_plain_read_cnt_reg")),
                "enc_dbg_ap_done_cnt": _diag_sig(("mac", 0, "u_macsec_tx", "u_encrypt", "dbg_ap_done_cnt_reg")),
                "ev_if_tx_hs": tx_pipe_events["if_tx_hs"],
                "ev_if_tx_last_hs": tx_pipe_events["if_tx_last_hs"],
                "ev_if_tx_cpl_hs": tx_pipe_events["if_tx_cpl_hs"],
                "ev_if_tx_cpl_last_tag": tx_pipe_events["if_tx_cpl_last_tag"],
                "ev_split_pre_last_hs": tx_pipe_events["split_pre_last_hs"],
                "ev_split_pre_in_last_hs": tx_pipe_events["split_pre_in_last_hs"],
                "ev_split_comp_last_hs": tx_pipe_events["split_comp_last_hs"],
                "ev_inb_last_hs": tx_pipe_events["inb_last_hs"],
                "ev_txw_in_frame_end_hs": tx_pipe_events["txw_in_frame_end_hs"],
            }
            tb.log.warning(
                "DBG %s tx_pipe: tx_req_v/r=%s/%s desc_req_v/r=%s/%s desc_st_v/e=%s/%s "
                "cpl_req_v/r=%s/%s cpl_st_v=%s dma_rd_v/r=%s/%s dma_rd_st_v=%s tx_v/r/l=%s/%s/%s if_tx_v/r/l=%s/%s/%s "
                "axis_if_tx_v/r/l=%s/%s/%s axis_if_tx_fifo0_v/r/l=%s/%s/%s port_tx_v/r/l=%s/%s/%s",
                stage,
                vals["tx_req_v"],
                vals["tx_req_r"],
                vals["desc_req_v"],
                vals["desc_req_r"],
                vals["desc_st_v"],
                vals["desc_st_e"],
                vals["cpl_req_v"],
                vals["cpl_req_r"],
                vals["cpl_st_v"],
                vals["dma_rd_v"],
                vals["dma_rd_r"],
                vals["dma_rd_st_v"],
                vals["tx_v"],
                vals["tx_r"],
                vals["tx_l"],
                vals["if_tx_v"],
                vals["if_tx_r"],
                vals["if_tx_l"],
                vals["axis_if_tx_v"],
                vals["axis_if_tx_r"],
                vals["axis_if_tx_l"],
                vals["axis_if_tx_fifo_v0"],
                vals["axis_if_tx_fifo_r0"],
                vals["axis_if_tx_fifo_l0"],
                vals["port_tx_v"],
                vals["port_tx_r"],
                vals["port_tx_l"],
            )
            dbg(
                f"[MACSEC_TX_PIPE] {stage} tx_req={vals['tx_req_v']}/{vals['tx_req_r']} "
                f"desc_req={vals['desc_req_v']}/{vals['desc_req_r']} desc_st={vals['desc_st_v']}/{vals['desc_st_e']} "
                f"cpl_req={vals['cpl_req_v']}/{vals['cpl_req_r']} cpl_st={vals['cpl_st_v']} "
                f"dma_rd={vals['dma_rd_v']}/{vals['dma_rd_r']} dma_rd_st={vals['dma_rd_st_v']} "
                f"act={vals['act_desc_req']} ptrs={vals['start_ptr']}/{vals['tx_start_ptr']}/{vals['cpl_ptr']}/{vals['fin_ptr']} "
                f"active_map={vals['active_map']} "
                f"tx={vals['tx_v']}/{vals['tx_r']}/{vals['tx_l']} if_tx={vals['if_tx_v']}/{vals['if_tx_r']}/{vals['if_tx_l']}/{vals['if_tx_u']} "
                f"axis_if_tx={vals['axis_if_tx_v']}/{vals['axis_if_tx_r']}/{vals['axis_if_tx_l']}/{vals['axis_if_tx_u']} "
                f"fifo0={vals['axis_if_tx_fifo_v0']}/{vals['axis_if_tx_fifo_r0']}/{vals['axis_if_tx_fifo_l0']} "
                f"if_cpl0={vals['if_tx_cpl_v0']}/{vals['if_tx_cpl_r0']} tag0={vals['if_tx_cpl_tag0']} "
                f"port_tx={vals['port_tx_v']}/{vals['port_tx_r']}/{vals['port_tx_l']} "
                f"enc_perf(cyc/blk/f)={vals['macsec_enc_cycles_last']}/{vals['macsec_enc_blocks_last']}/{vals['macsec_enc_frames_done']} "
                f"ev_if_tx={vals['ev_if_tx_hs']}/{vals['ev_if_tx_last_hs']} ev_if_cpl={vals['ev_if_tx_cpl_hs']} last_cpl_tag={vals['ev_if_tx_cpl_last_tag']} "
                f"ev_split_last(pre_in/pre/comp/inb/in)={vals['ev_split_pre_in_last_hs']}/{vals['ev_split_pre_last_hs']}/{vals['ev_split_comp_last_hs']}/{vals['ev_inb_last_hs']}/{vals['ev_txw_in_frame_end_hs']} "
                f"txw(st/hdr/usr/etype)={vals['txw_out_state']}/{vals['txw_hdr_cnt']}/{vals['txw_tuser_cnt']}/{vals['txw_ethertype_cnt']} "
                f"txw_fifo(c/l/t/e)={vals['txw_cipher_empty']}/{vals['txw_len_empty']}/{vals['txw_tag_empty']}/{vals['txw_end_empty']} "
                f"txw_ff(c/l/t/e)={vals['txw_cipher_full']}/{vals['txw_len_full']}/{vals['txw_tag_full']}/{vals['txw_end_full']} "
                f"inb(pt/len/end)={vals['inb_pt_empty_n']}/{vals['inb_pt_read']} {vals['inb_len_empty_n']}/{vals['inb_len_read']} {vals['inb_end_empty_n']}/{vals['inb_end_read']} "
                f"inb_meta(cnt/deq/lf/ef)={vals['inb_meta_cnt']}/{vals['inb_meta_deq']}/{vals['inb_len_full']}/{vals['inb_end_full']} "
                f"inb_fsm(st/bytes/end/meta_v/bv/fp)={vals['inb_state']}/{vals['inb_frame_bytes']}/{vals['inb_frame_end_reg']}/{vals['inb_meta_valid_reg']}/{vals['inb_block_valid']}/{vals['inb_first_pending']} "
                f"inb_dbg(pend/fe/enq/deq/lw/ew)={vals['inb_meta_enq_pending']}/{vals['inb_dbg_frame_end_cnt']}/{vals['inb_dbg_meta_enq_cnt']}/{vals['inb_dbg_meta_deq_cnt']}/{vals['inb_dbg_len_wr_cnt']}/{vals['inb_dbg_end_wr_cnt']} "
                f"split(pre v/r/l)={vals['txw_split_pre_v']}/{vals['txw_split_pre_r']}/{vals['txw_split_pre_l']} "
                f"split(comp v/r/l)={vals['txw_split_comp_v']}/{vals['txw_split_comp_r']}/{vals['txw_split_comp_l']} "
                f"incomp(cnt/lp/mv/ml)={vals['txw_incomp_count']}/{vals['txw_incomp_last_pending']}/{vals['txw_incomp_m_v']}/{vals['txw_incomp_m_l']} "
                f"inb_last_hs={vals['inb_frame_last_hs']} "
                f"outb(st/act/len/cnt)={vals['outb_state']}/{vals['outb_frame_active']}/{vals['outb_len']}/{vals['outb_count']} "
                f"enc(st/rem/exp/cons)={vals['enc_state']}/{vals['enc_blocks_rem']}/{vals['enc_blocks_exp']}/{vals['enc_payload_cons']} "
                f"enc(pop_l/pop_e/ap_s/done/idle/ready/pl_r/el_r)="
                f"{vals['enc_len_pop']}/{vals['enc_end_pop']}/{vals['enc_ap_start']}/{vals['enc_ip_done']}/{vals['enc_ip_idle']}/{vals['enc_ip_ready']}/{vals['enc_plain_read']}/{vals['enc_endlen_read']} "
                f"enc_cnt(st/len/end/pl/done)={vals['enc_dbg_ap_start_cnt']}/{vals['enc_dbg_len_pop_cnt']}/{vals['enc_dbg_end_pop_cnt']}/{vals['enc_dbg_plain_read_cnt']}/{vals['enc_dbg_ap_done_cnt']}"
            )
        except Exception as ex:
            tb.log.warning("DBG %s tx_pipe snapshot failed: %r", stage, ex)
            dbg(f"[MACSEC_TX_PIPE] {stage} snapshot_failed={ex!r}")

    async def monitor_tx_pipe_events(clock):
        if_base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst")
        sig_if_tx_v = _try_get_sig(if_base + ("if_tx_axis_tvalid",))
        sig_if_tx_r = _try_get_sig(if_base + ("if_tx_axis_tready",))
        sig_if_tx_l = _try_get_sig(if_base + ("if_tx_axis_tlast",))
        sig_cpl_v = _try_get_sig(if_base + ("axis_if_tx_cpl_valid",))
        sig_cpl_r = _try_get_sig(if_base + ("axis_if_tx_cpl_ready",))
        sig_cpl_tag = _try_get_sig(if_base + ("axis_if_tx_cpl_tag",))
        sig_pre_v = _try_get_sig(("mac", 0, "u_macsec_tx", "split_pre_tvalid"))
        sig_pre_r = _try_get_sig(("mac", 0, "u_macsec_tx", "split_pre_tready"))
        sig_pre_l = _try_get_sig(("mac", 0, "u_macsec_tx", "split_pre_tlast"))
        sig_pre_in_last_hs = _try_get_sig(("mac", 0, "u_macsec_tx", "split_pre_in_last_hs"))
        sig_comp_v = _try_get_sig(("mac", 0, "u_macsec_tx", "split_compact_tvalid"))
        sig_comp_r = _try_get_sig(("mac", 0, "u_macsec_tx", "split_compact_tready"))
        sig_comp_l = _try_get_sig(("mac", 0, "u_macsec_tx", "split_compact_tlast"))
        sig_inb_last_hs = _try_get_sig(("mac", 0, "u_macsec_tx", "u_in_bridge", "frame_last_hs"))
        sig_txw_in_frame_end_hs = _try_get_sig(("mac", 0, "u_macsec_tx", "s_axis_frame_end_hs"))

        while True:
            await RisingEdge(clock)
            if _safe_bit(sig_if_tx_v) and _safe_bit(sig_if_tx_r):
                tx_pipe_events["if_tx_hs"] += 1
                if _safe_bit(sig_if_tx_l):
                    tx_pipe_events["if_tx_last_hs"] += 1
            if _safe_bit(sig_cpl_v) and _safe_bit(sig_cpl_r):
                tx_pipe_events["if_tx_cpl_hs"] += 1
                tx_pipe_events["if_tx_cpl_last_tag"] = _safe_int(sig_cpl_tag)
            if _safe_bit(sig_pre_v) and _safe_bit(sig_pre_r) and _safe_bit(sig_pre_l):
                tx_pipe_events["split_pre_last_hs"] += 1
            if _safe_bit(sig_pre_in_last_hs):
                tx_pipe_events["split_pre_in_last_hs"] += 1
            if _safe_bit(sig_comp_v) and _safe_bit(sig_comp_r) and _safe_bit(sig_comp_l):
                tx_pipe_events["split_comp_last_hs"] += 1
            if _safe_bit(sig_inb_last_hs):
                tx_pipe_events["inb_last_hs"] += 1
            if _safe_bit(sig_txw_in_frame_end_hs):
                tx_pipe_events["txw_in_frame_end_hs"] += 1

            gap = tx_pipe_events["split_pre_in_last_hs"] - tx_pipe_events["inb_last_hs"]
            if gap > tx_pipe_events["last_gap_reported"]:
                tx_pipe_events["last_gap_reported"] = gap
                dbg(
                    f"[MACSEC_EDGE_GAP] pre_in={tx_pipe_events['split_pre_in_last_hs']} "
                    f"pre={tx_pipe_events['split_pre_last_hs']} "
                    f"comp={tx_pipe_events['split_comp_last_hs']} "
                    f"inb={tx_pipe_events['inb_last_hs']} "
                    f"in={tx_pipe_events['txw_in_frame_end_hs']} gap={gap}"
                )

    async def monitor_rx_pipe_events(clock):
        base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "interface_rx_inst")
        base1 = ("core_inst", "core_pcie_inst", "core_inst", "iface", 1, "interface_inst", "interface_rx_inst")
        if_base = ("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst")
        sig_s_v = _try_get_sig(base + ("s_axis_rx_tvalid",))
        sig_s_r = _try_get_sig(base + ("s_axis_rx_tready",))
        sig_s_l = _try_get_sig(base + ("s_axis_rx_tlast",))
        sig_req_v = _try_get_sig(base + ("rx_req_valid",))
        sig_req_r = _try_get_sig(base + ("rx_req_ready",))
        sig_desc_v = _try_get_sig(base + ("dma_rx_desc_valid",))
        sig_desc_r = _try_get_sig(base + ("dma_rx_desc_ready",))
        sig_desc_st_v = _try_get_sig(base + ("dma_rx_desc_status_valid",))
        sig_cpl_v = _try_get_sig(base + ("m_axis_cpl_req_valid",))
        sig_cpl_r = _try_get_sig(base + ("m_axis_cpl_req_ready",))
        sig1_s_v = _try_get_sig(base1 + ("s_axis_rx_tvalid",))
        sig1_s_r = _try_get_sig(base1 + ("s_axis_rx_tready",))
        sig1_s_l = _try_get_sig(base1 + ("s_axis_rx_tlast",))
        sig1_req_v = _try_get_sig(base1 + ("rx_req_valid",))
        sig1_req_r = _try_get_sig(base1 + ("rx_req_ready",))
        sig_port_in_v = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tvalid"))
        sig_port_in_r = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tready"))
        sig_port_in_l = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "s_axis_rx_tlast"))
        sig_port_out_v = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tvalid"))
        sig_port_out_r = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tready"))
        sig_port_out_l = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tlast"))
        sig_port_out_u = _try_get_sig(("core_inst", "core_pcie_inst", "core_inst", "iface", 0, "interface_inst", "port", 0, "port_inst", "port_rx_inst", "m_axis_if_rx_tuser"))
        sig_if_fifo_in_v = _try_get_sig(if_base + ("axis_if_rx_fifo_tvalid",))
        sig_if_fifo_in_r = _try_get_sig(if_base + ("axis_if_rx_fifo_tready",))
        sig_if_fifo_in_l = _try_get_sig(if_base + ("axis_if_rx_fifo_tlast",))
        sig_if_fifo_out_v = _try_get_sig(if_base + ("axis_if_rx_tvalid",))
        sig_if_fifo_out_r = _try_get_sig(if_base + ("axis_if_rx_tready",))
        sig_if_fifo_out_l = _try_get_sig(if_base + ("axis_if_rx_tlast",))
        sig_if_fifo_out_u = _try_get_sig(if_base + ("axis_if_rx_tuser",))
        sig_if_axis_v = _try_get_sig(if_base + ("if_rx_axis_tvalid",))
        sig_if_axis_r = _try_get_sig(if_base + ("if_rx_axis_tready",))
        sig_if_axis_l = _try_get_sig(if_base + ("if_rx_axis_tlast",))
        sig_if_axis_u = _try_get_sig(if_base + ("if_rx_axis_tuser",))
        port_out_bad_or = 0
        if_fifo_out_bad_or = 0
        if_axis_bad_or = 0

        while True:
            await RisingEdge(clock)
            if sig_s_v is not None and sig_s_r is not None and sig_s_l is not None:
                if sig_s_v.value and sig_s_r.value and sig_s_l.value:
                    rx_pipe_events["s_rx_frame_hs"] = rx_pipe_events.get("s_rx_frame_hs", 0) + 1
            if sig1_s_v is not None and sig1_s_r is not None and sig1_s_l is not None:
                if sig1_s_v.value and sig1_s_r.value and sig1_s_l.value:
                    rx_pipe_events["s_rx1_frame_hs"] = rx_pipe_events.get("s_rx1_frame_hs", 0) + 1
            if sig_req_v is not None and sig_req_r is not None:
                if sig_req_v.value and sig_req_r.value:
                    rx_pipe_events["rx_req_hs"] = rx_pipe_events.get("rx_req_hs", 0) + 1
            if sig1_req_v is not None and sig1_req_r is not None:
                if sig1_req_v.value and sig1_req_r.value:
                    rx_pipe_events["rx1_req_hs"] = rx_pipe_events.get("rx1_req_hs", 0) + 1
            if sig_port_in_v is not None and sig_port_in_r is not None and sig_port_in_l is not None:
                if sig_port_in_v.value and sig_port_in_r.value and sig_port_in_l.value:
                    rx_pipe_events["port_in_frame_hs"] = rx_pipe_events.get("port_in_frame_hs", 0) + 1
            if sig_port_out_v is not None and sig_port_out_r is not None and sig_port_out_l is not None:
                if sig_port_out_v.value and sig_port_out_r.value and sig_port_out_l.value:
                    rx_pipe_events["port_out_frame_hs"] = rx_pipe_events.get("port_out_frame_hs", 0) + 1
                    rx_pipe_events["port_out_bad_or_last"] = port_out_bad_or
                    port_out_bad_or = 0
                elif sig_port_out_v.value and sig_port_out_r.value and sig_port_out_u is not None:
                    try:
                        port_out_bad_or |= (int(sig_port_out_u.value) & 0x1)
                    except Exception:
                        pass
            if sig_if_fifo_in_v is not None and sig_if_fifo_in_r is not None and sig_if_fifo_in_l is not None:
                fifo_in_v = _safe_bit(sig_if_fifo_in_v)
                fifo_in_r = _safe_bit(sig_if_fifo_in_r)
                fifo_in_l = _safe_bit(sig_if_fifo_in_l)
                if fifo_in_v == 1 and fifo_in_r == 1 and fifo_in_l == 1:
                    rx_pipe_events["if_fifo_in_frame_hs"] = rx_pipe_events.get("if_fifo_in_frame_hs", 0) + 1
            if sig_if_fifo_out_v is not None and sig_if_fifo_out_r is not None and sig_if_fifo_out_l is not None:
                fifo_out_v = _safe_bit(sig_if_fifo_out_v)
                fifo_out_r = _safe_bit(sig_if_fifo_out_r)
                fifo_out_l = _safe_bit(sig_if_fifo_out_l)
                if fifo_out_v == 1 and fifo_out_r == 1 and fifo_out_l == 1:
                    rx_pipe_events["if_fifo_out_frame_hs"] = rx_pipe_events.get("if_fifo_out_frame_hs", 0) + 1
                    rx_pipe_events["if_fifo_out_bad_or_last"] = if_fifo_out_bad_or
                    if_fifo_out_bad_or = 0
                elif fifo_out_v == 1 and fifo_out_r == 1 and sig_if_fifo_out_u is not None:
                    try:
                        if_fifo_out_bad_or |= (int(sig_if_fifo_out_u.value) & 0x1)
                    except Exception:
                        pass
            if sig_if_axis_v is not None and sig_if_axis_r is not None and sig_if_axis_l is not None:
                if_axis_v = _safe_bit(sig_if_axis_v)
                if_axis_r = _safe_bit(sig_if_axis_r)
                if_axis_l = _safe_bit(sig_if_axis_l)
                if if_axis_v == 1 and if_axis_r == 1 and if_axis_l == 1:
                    rx_pipe_events["if_axis_frame_hs"] = rx_pipe_events.get("if_axis_frame_hs", 0) + 1
                    rx_pipe_events["if_axis_bad_or_last"] = if_axis_bad_or
                    if_axis_bad_or = 0
                elif if_axis_v == 1 and if_axis_r == 1 and sig_if_axis_u is not None:
                    try:
                        if_axis_bad_or |= (int(sig_if_axis_u.value) & 0x1)
                    except Exception:
                        pass
            if sig_desc_v is not None and sig_desc_r is not None:
                if sig_desc_v.value and sig_desc_r.value:
                    rx_pipe_events["dma_desc_hs"] = rx_pipe_events.get("dma_desc_hs", 0) + 1
            if sig_desc_st_v is not None and sig_desc_st_v.value:
                rx_pipe_events["dma_desc_status"] = rx_pipe_events.get("dma_desc_status", 0) + 1
            if sig_cpl_v is not None and sig_cpl_v.value:
                rx_pipe_events["cpl_req_valid_cycles"] = rx_pipe_events.get("cpl_req_valid_cycles", 0) + 1
                if sig_cpl_r is not None and sig_cpl_r.value:
                    rx_pipe_events["cpl_req_hs"] = rx_pipe_events.get("cpl_req_hs", 0) + 1

    async def _wait_pause_level(sig, want_high, max_cycles, clock, name):
        if sig is None:
            tb.log.warning("LFC debug signal %s unavailable; skip level check", name)
            return False

        cur = _safe_sig(sig)
        if cur is None:
            tb.log.warning("LFC debug signal %s unreadable; skip level check", name)
            return False

        if bool(cur) == bool(want_high):
            return True

        for _ in range(max_cycles):
            await RisingEdge(clock)
            cur = _safe_sig(sig)
            if cur is not None and bool(cur) == bool(want_high):
                return True

        tb.log.warning(
            "Timeout waiting %s level=%d within %d cycles (now=%s)",
            name,
            int(want_high),
            max_cycles,
            _safe_sig(sig),
        )
        return False

    def _check_stage(stage, strict=False):
        tx_in, tx_out, rx_in, rx_out = _counter_snapshot()
        lag_tx = tx_in - tx_out
        lag_rx = rx_in - rx_out
        tb.log.info(
            "CHK %s counters tx_in=%d tx_out=%d rx_in=%d rx_out=%d lag_tx=%d lag_rx=%d",
            stage, tx_in, tx_out, rx_in, rx_out, lag_tx, lag_rx
        )
        dbg(
            f"[MACSEC_CHK] {stage} tx_in={tx_in} tx_out={tx_out} rx_in={rx_in} rx_out={rx_out} "
            f"lag_tx={lag_tx} lag_rx={lag_rx}"
        )
        if lag_tx > checkpoint_lag_warn or lag_rx > checkpoint_lag_warn:
            tb.log.warning(
                "CHK %s lag warning: lag_tx=%d lag_rx=%d warn=%d",
                stage,
                lag_tx,
                lag_rx,
                checkpoint_lag_warn,
            )

        if live_debug:
            live(
                f"chk {stage} tx_in={tx_in} tx_out={tx_out} rx_in={rx_in} rx_out={rx_out} "
                f"lag_tx={lag_tx} lag_rx={lag_rx}"
            )

        # Direction sanity
        assert tx_out <= tx_in, f"{stage}: tx_out({tx_out}) > tx_in({tx_in})"
        assert rx_out <= rx_in, f"{stage}: rx_out({rx_out}) > rx_in({rx_in})"

        # Bounded lag check to fail early in long runs.
        assert lag_tx <= checkpoint_lag_max, (
            f"{stage}: tx lag too large ({lag_tx}>{checkpoint_lag_max}) "
            f"tx_in={tx_in} tx_out={tx_out}"
        )
        assert lag_rx <= checkpoint_lag_max, (
            f"{stage}: rx lag too large ({lag_rx}>{checkpoint_lag_max}) "
            f"rx_in={rx_in} rx_out={rx_out}"
        )

        if strict:
            assert tx_in == tx_out, f"{stage}: strict mismatch tx_in={tx_in} tx_out={tx_out}"
            rx_pause = macsec_rx_pause_frames.get("count", 0)
            # Depending on instrumentation, rx_in may or may not include pause
            # control frames. Accept both accounting conventions.
            assert rx_in == rx_out or rx_in == rx_out + rx_pause, (
                f"{stage}: strict mismatch rx_in={rx_in} rx_out={rx_out} "
                f"rx_pause_frames={rx_pause}"
            )

    async def start_xmit_checked(data, queue=0, csum_start=None, csum_offset=None, stage="xmit"):
        xmit = tb.driver.interfaces[0].start_xmit(data, queue, csum_start, csum_offset)
        try:
            await with_timeout(xmit, xmit_timeout_us, "us")
        except SimTimeoutError as ex:
            tb.log.warning(
                "Timeout at %s: start_xmit timeout_us=%d len=%d queue=%d tx_in=%d tx_out=%d rx_in=%d rx_out=%d",
                stage,
                xmit_timeout_us,
                len(data),
                queue,
                macsec_frame_counts.get("tx_in", 0),
                macsec_frame_counts.get("tx_out", 0),
                macsec_frame_counts.get("rx_in", 0),
                macsec_frame_counts.get("rx_out", 0),
            )
            dbg(
                f"[MACSEC_TIMEOUT] xmit {stage} timeout_us={xmit_timeout_us} len={len(data)} queue={queue} "
                f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
            )
            _log_macsec_debug(stage)
            raise ex

    async def _recv_with_progress(coro_factory, timeout_us=8000, stage="recv", is_host=True):
        elapsed = 0
        poll_cnt = 0

        while elapsed < timeout_us:
            step_us = min(max(1, recv_poll_us), timeout_us - elapsed)
            try:
                return await with_timeout(coro_factory(), step_us, "us")
            except SimTimeoutError:
                elapsed += step_us
                poll_cnt += 1
                if live_debug and (poll_cnt % max(1, recv_progress_every) == 0):
                    live(
                        f"wait_{'host' if is_host else 'wire'} {stage} elapsed_us={elapsed}/{timeout_us} "
                        f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                        f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                    )
                    if is_host:
                        await _log_host_rx_diag(f"{stage}_progress")
                        _log_rx_pipeline_diag(f"{stage}_progress")

        tb.log.warning(
            "Timeout at %s: %s recv timeout_us=%d counters tx_in=%d tx_out=%d rx_in=%d rx_out=%d",
            stage,
            "host" if is_host else "wire",
            timeout_us,
            macsec_frame_counts.get("tx_in", 0),
            macsec_frame_counts.get("tx_out", 0),
            macsec_frame_counts.get("rx_in", 0),
            macsec_frame_counts.get("rx_out", 0),
        )
        dbg(
            f"[MACSEC_TIMEOUT] {'host' if is_host else 'wire'} {stage} timeout_us={timeout_us} "
            f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
            f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
        )
        if is_host:
            await _log_host_rx_diag(stage)
            _log_rx_pipeline_diag(stage)
        _log_macsec_debug(stage)
        raise SimTimeoutError

    async def recv_host(timeout_us=8000, stage="host"):
        # Use explicit polling on recv_nowait() to guarantee simulation time
        # progress and deterministic timeout behavior under heavy debug loads.
        elapsed = 0
        poll_cnt = 0

        while elapsed < timeout_us:
            pkt = tb.driver.interfaces[0].recv_nowait()
            if pkt is not None:
                return pkt

            step_us = min(max(1, recv_poll_us), timeout_us - elapsed)
            await Timer(step_us, "us")
            elapsed += step_us
            poll_cnt += 1

            if live_debug and (poll_cnt % max(1, recv_progress_every) == 0):
                live(
                    f"wait_host {stage} elapsed_us={elapsed}/{timeout_us} "
                    f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                    f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                )
                # Keep progress logging non-blocking. Deep host queue reads can
                # themselves stall under heavy backpressure and hide true test
                # timeout behavior.
                _log_rx_pipeline_diag(f"{stage}_progress")
                _log_tx_pipeline_diag(f"{stage}_progress")

        tb.log.warning(
            "Timeout at %s: host recv timeout_us=%d counters tx_in=%d tx_out=%d rx_in=%d rx_out=%d",
            stage,
            timeout_us,
            macsec_frame_counts.get("tx_in", 0),
            macsec_frame_counts.get("tx_out", 0),
            macsec_frame_counts.get("rx_in", 0),
            macsec_frame_counts.get("rx_out", 0),
        )
        dbg(
            f"[MACSEC_TIMEOUT] host {stage} timeout_us={timeout_us} "
            f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
            f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
        )
        await _log_host_rx_diag(stage)
        await _log_host_tx_diag(stage)
        _log_rx_pipeline_diag(stage)
        _log_macsec_debug(stage)

        # Diagnostic probe: check if traffic is landing on interface 1 instead.
        if len(tb.driver.interfaces) > 1:
            alt_pkt = tb.driver.interfaces[1].recv_nowait()
            if alt_pkt is not None:
                tb.log.warning(
                    "Timeout at %s on iface0, but iface1 received len=%d queue=%d",
                    stage,
                    len(alt_pkt.data),
                    int(getattr(alt_pkt, "queue", -1)),
                )

        if late_grace_us > 0:
            late_elapsed = 0
            while late_elapsed < late_grace_us:
                late_pkt = tb.driver.interfaces[0].recv_nowait()
                if late_pkt is not None:
                    tb.log.warning(
                        "Late host packet at %s within grace_us=%d: len=%d queue=%d",
                        stage,
                        late_grace_us,
                        len(late_pkt.data),
                        int(getattr(late_pkt, "queue", -1)),
                    )
                    if allow_late:
                        return late_pkt
                    break
                step_us = min(max(1, recv_poll_us), late_grace_us - late_elapsed)
                await Timer(step_us, "us")
                late_elapsed += step_us
            else:
                tb.log.warning("No late host packet at %s within grace_us=%d", stage, late_grace_us)

        raise SimTimeoutError

    async def recv_wire(timeout_us=8000, stage="wire"):
        return await _recv_with_progress(
            lambda: tb.sfp_sink[0].recv(),
            timeout_us=timeout_us,
            stage=stage,
            is_host=False,
        )

    async def monitor_axis_frames(clock, tvalid, tready, tkeep, tlast, counter, frame_bytes, key):
        byte_count = 0
        while True:
            await RisingEdge(clock)
            if tvalid.value and tready.value:
                try:
                    byte_count += int(tkeep.value).bit_count()
                except Exception:
                    pass
                if tlast.value:
                    counter[key] = counter.get(key, 0) + 1
                    frame_bytes.setdefault(key, []).append(byte_count)
                    if live_debug:
                        live(f"frame_done {key}[{counter[key]-1}] bytes={byte_count}")
                    byte_count = 0

    async def monitor_axis_frame_heads(clock, tdata, tkeep, tvalid, tready, tlast, heads, key):
        frame = bytearray()
        while True:
            await RisingEdge(clock)
            if tvalid.value and tready.value:
                try:
                    cur_data = int(tdata.value)
                    cur_keep = int(tkeep.value)
                except Exception:
                    # Some models can drive X/Z transiently around reset or CDC
                    # boundaries; ignore these beats in debug-only monitors.
                    continue
                for i in range(8):
                    if cur_keep & (1 << i):
                        if len(frame) < 32:
                            frame.append((cur_data >> (8 * i)) & 0xFF)
                if tlast.value:
                    head = bytes(frame[:16])
                    heads.setdefault(key, []).append(head)
                    if key == "rx_in" and _is_pause_ctrl_head(head):
                        macsec_rx_pause_frames["count"] = macsec_rx_pause_frames.get("count", 0) + 1
                        if live_debug:
                            live(
                                f"rx_in_pause_frame idx={macsec_rx_pause_frames['count']-1} "
                                f"head16={head.hex()}"
                            )
                    if live_debug:
                        live(f"frame_head {key}[{len(heads.get(key, [])) - 1}] len={len(frame)} head16={head.hex()}")
                    frame.clear()

    async def monitor_tuser(clock, tvalid, tready, tlast, tuser, stats, key):
        in_frame = False
        first_val = 0
        last_val = 0
        bad_or = 0
        while True:
            await RisingEdge(clock)
            if tvalid.value and tready.value:
                try:
                    cur = int(tuser.value)
                except Exception:
                    cur = 0
                if not in_frame:
                    first_val = cur
                    bad_or = 0
                    in_frame = True
                last_val = cur
                bad_or |= (cur & 0x1)
                if tlast.value:
                    stats.setdefault(key, []).append(
                        {"first": first_val, "last": last_val, "bad_or": bad_or}
                    )
                    in_frame = False

    async def monitor_tx_continuity_stats(clock, tvalid, tready, tlast, stats, key):
        in_frame = False
        beats = 0
        stall_cur = 0
        stall_max = 0
        while True:
            await RisingEdge(clock)
            hs = bool(tvalid.value and tready.value)
            if not in_frame:
                if hs:
                    in_frame = True
                    beats = 1
                    stall_cur = 0
                    stall_max = 0
                    if tlast.value:
                        stats.setdefault(key, []).append({"beats": beats, "max_gap": stall_max})
                        in_frame = False
            else:
                if hs:
                    beats += 1
                    stall_cur = 0
                    if tlast.value:
                        stats.setdefault(key, []).append({"beats": beats, "max_gap": stall_max})
                        in_frame = False
                else:
                    stall_cur += 1
                    if stall_cur > stall_max:
                        stall_max = stall_cur

    async def monitor_underflow(clock, sig, stats):
        while True:
            await RisingEdge(clock)
            if sig.value:
                stats["count"] = stats.get("count", 0) + 1

    tb = TB(dut, msix_count=2**len(dut.core_inst.core_pcie_inst.irq_index))
    smoke_only = os.getenv("MACSEC_SMOKE_ONLY", "0") == "1"

    if test_stage not in ("full", "small_pkts", "peer_interop", "arp_mix"):
        raise ValueError(
            f"Unsupported MACSEC_TEST_STAGE={test_stage!r}, expected 'full', 'small_pkts', 'peer_interop', or 'arp_mix'"
        )
    if small_pkts_pre_stage not in ("none", "queue_map", "rss"):
        raise ValueError(
            f"Unsupported MACSEC_SMALL_PKTS_PRE_STAGE={small_pkts_pre_stage!r}, expected 'none', 'queue_map', or 'rss'"
        )
    if small_pkts_count <= 0:
        raise ValueError(f"MACSEC_SMALL_PKTS_COUNT must be > 0, got {small_pkts_count}")
    if small_pkts_rounds <= 0:
        raise ValueError(f"MACSEC_SMALL_PKTS_ROUNDS must be > 0, got {small_pkts_rounds}")
    if steady_pkt_count <= 0:
        raise ValueError(f"MACSEC_STEADY_PKT_COUNT must be > 0, got {steady_pkt_count}")
    if rss_pkt_count <= 0:
        raise ValueError(f"MACSEC_RSS_PKT_COUNT must be > 0, got {rss_pkt_count}")
    if rss_min_queues <= 0:
        raise ValueError(f"MACSEC_RSS_MIN_QUEUES must be > 0, got {rss_min_queues}")

    await tb.init()

    # Basic liveness checks for MACsec HLS domain before traffic.
    tx_hls_clk_sig = _try_get_sig(["mac", 0, "u_macsec_tx", "hls_clk"])
    rx_hls_clk_sig = _try_get_sig(["mac", 0, "u_macsec_rx", "hls_clk"])
    tx_hls_rst_sig = _try_get_sig(["mac", 0, "u_macsec_tx", "hls_rst"])
    rx_hls_rst_sig = _try_get_sig(["mac", 0, "u_macsec_rx", "hls_rst"])

    if tx_hls_clk_sig is not None and rx_hls_clk_sig is not None:
        await with_timeout(RisingEdge(tx_hls_clk_sig), 10, "us")
        await with_timeout(RisingEdge(rx_hls_clk_sig), 10, "us")
        if tx_hls_rst_sig is not None and int(tx_hls_rst_sig.value):
            await with_timeout(FallingEdge(tx_hls_rst_sig), 200, "us")
        if rx_hls_rst_sig is not None and int(rx_hls_rst_sig.value):
            await with_timeout(FallingEdge(rx_hls_rst_sig), 200, "us")
        tb.log.info(
            "MACsec HLS domain alive: tx_hls_rst=%s rx_hls_rst=%s",
            int(tx_hls_rst_sig.value) if tx_hls_rst_sig is not None else -1,
            int(rx_hls_rst_sig.value) if rx_hls_rst_sig is not None else -1,
        )
    else:
        tb.log.warning(
            "Skip MACsec HLS liveness check: u_macsec_tx/u_macsec_rx hierarchy not found in DUT"
        )
    tb.log.info(
        "MACsec test config: stage=%s smoke_only=%d small_pre=%s rss_count=%d rss_min_queues=%d small_count=%d small_rounds=%d recv_timeout_us=%d bulk_recv_timeout_us=%d late_grace_us=%d allow_late=%d live_debug=%d lag_warn=%d lag_max=%d small_step_check=%d lfc_pkt_count=%d lfc_step_timeout_us=%d lfc_expect_pause=%d lfc_assert_cycles=%d lfc_release_cycles=%d",
        test_stage,
        int(smoke_only),
        small_pkts_pre_stage,
        rss_pkt_count,
        rss_min_queues,
        small_pkts_count,
        small_pkts_rounds,
        recv_timeout_us,
        bulk_recv_timeout_us,
        late_grace_us,
        int(allow_late),
        int(live_debug),
        checkpoint_lag_warn,
        checkpoint_lag_max,
        small_step_check,
        lfc_pkt_count,
        lfc_step_timeout_us,
        int(lfc_expect_pause),
        lfc_pause_assert_cycles,
        lfc_pause_release_cycles,
    )

    try:
        cocotb.start_soon(heartbeat_task())
        cocotb.start_soon(
            monitor_axis_frames(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.s_axis_tvalid,
                dut.mac[0].u_macsec_tx.s_axis_tready,
                dut.mac[0].u_macsec_tx.s_axis_tkeep,
                dut.mac[0].u_macsec_tx.s_axis_tlast,
                macsec_frame_counts,
                macsec_frame_bytes,
                "tx_in",
            )
        )
        cocotb.start_soon(
            monitor_tx_continuity_stats(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.m_axis_tvalid,
                dut.mac[0].u_macsec_tx.m_axis_tready,
                dut.mac[0].u_macsec_tx.m_axis_tlast,
                macsec_tx_continuity,
                "tx_out",
            )
        )
        cocotb.start_soon(
            monitor_axis_frame_heads(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.s_axis_tdata,
                dut.mac[0].u_macsec_tx.s_axis_tkeep,
                dut.mac[0].u_macsec_tx.s_axis_tvalid,
                dut.mac[0].u_macsec_tx.s_axis_tready,
                dut.mac[0].u_macsec_tx.s_axis_tlast,
                macsec_frame_heads,
                "tx_in",
            )
        )
        cocotb.start_soon(
            monitor_axis_frame_heads(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.m_axis_tdata,
                dut.mac[0].u_macsec_tx.m_axis_tkeep,
                dut.mac[0].u_macsec_tx.m_axis_tvalid,
                dut.mac[0].u_macsec_tx.m_axis_tready,
                dut.mac[0].u_macsec_tx.m_axis_tlast,
                macsec_frame_heads,
                "tx_out",
            )
        )
        cocotb.start_soon(
            monitor_underflow(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].eth_mac_inst.tx_error_underflow,
                macsec_eth_underflow,
            )
        )
        cocotb.start_soon(
            monitor_tuser(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.s_axis_tvalid,
                dut.mac[0].u_macsec_tx.s_axis_tready,
                dut.mac[0].u_macsec_tx.s_axis_tlast,
                dut.mac[0].u_macsec_tx.s_axis_tuser,
                macsec_tuser_stats,
                "tx_in",
            )
        )
        cocotb.start_soon(
            monitor_axis_frames(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.m_axis_tvalid,
                dut.mac[0].u_macsec_tx.m_axis_tready,
                dut.mac[0].u_macsec_tx.m_axis_tkeep,
                dut.mac[0].u_macsec_tx.m_axis_tlast,
                macsec_frame_counts,
                macsec_frame_bytes,
                "tx_out",
            )
        )
        cocotb.start_soon(
            monitor_tuser(
                dut.mac[0].u_macsec_tx.mac_clk,
                dut.mac[0].u_macsec_tx.m_axis_tvalid,
                dut.mac[0].u_macsec_tx.m_axis_tready,
                dut.mac[0].u_macsec_tx.m_axis_tlast,
                dut.mac[0].u_macsec_tx.m_axis_tuser,
                macsec_tuser_stats,
                "tx_out",
            )
        )
        cocotb.start_soon(
            monitor_axis_frames(
                dut.mac[0].u_macsec_rx.mac_clk,
                dut.mac[0].u_macsec_rx.s_axis_tvalid,
                dut.mac[0].u_macsec_rx.s_axis_tready,
                dut.mac[0].u_macsec_rx.s_axis_tkeep,
                dut.mac[0].u_macsec_rx.s_axis_tlast,
                macsec_frame_counts,
                macsec_frame_bytes,
                "rx_in",
            )
        )
        cocotb.start_soon(
            monitor_axis_frame_heads(
                dut.mac[0].u_macsec_rx.mac_clk,
                dut.mac[0].u_macsec_rx.s_axis_tdata,
                dut.mac[0].u_macsec_rx.s_axis_tkeep,
                dut.mac[0].u_macsec_rx.s_axis_tvalid,
                dut.mac[0].u_macsec_rx.s_axis_tready,
                dut.mac[0].u_macsec_rx.s_axis_tlast,
                macsec_frame_heads,
                "rx_in",
            )
        )
        if hasattr(dut.mac[0].u_macsec_rx, "s_axis_tuser"):
            cocotb.start_soon(
                monitor_tuser(
                    dut.mac[0].u_macsec_rx.mac_clk,
                    dut.mac[0].u_macsec_rx.s_axis_tvalid,
                    dut.mac[0].u_macsec_rx.s_axis_tready,
                    dut.mac[0].u_macsec_rx.s_axis_tlast,
                    dut.mac[0].u_macsec_rx.s_axis_tuser,
                    macsec_tuser_stats,
                    "rx_in",
                )
            )
        cocotb.start_soon(
            monitor_axis_frames(
                dut.mac[0].u_macsec_rx.mac_clk,
                dut.mac[0].u_macsec_rx.m_axis_tvalid,
                dut.mac[0].u_macsec_rx.m_axis_tready,
                dut.mac[0].u_macsec_rx.m_axis_tkeep,
                dut.mac[0].u_macsec_rx.m_axis_tlast,
                macsec_frame_counts,
                macsec_frame_bytes,
                "rx_out",
            )
        )
        cocotb.start_soon(
            monitor_axis_frame_heads(
                dut.mac[0].u_macsec_rx.mac_clk,
                dut.mac[0].u_macsec_rx.m_axis_tdata,
                dut.mac[0].u_macsec_rx.m_axis_tkeep,
                dut.mac[0].u_macsec_rx.m_axis_tvalid,
                dut.mac[0].u_macsec_rx.m_axis_tready,
                dut.mac[0].u_macsec_rx.m_axis_tlast,
                macsec_frame_heads,
                "rx_out",
            )
        )
        if hasattr(dut.mac[0].u_macsec_rx, "m_axis_tuser"):
            cocotb.start_soon(
                monitor_tuser(
                    dut.mac[0].u_macsec_rx.mac_clk,
                    dut.mac[0].u_macsec_rx.m_axis_tvalid,
                    dut.mac[0].u_macsec_rx.m_axis_tready,
                    dut.mac[0].u_macsec_rx.m_axis_tlast,
                    dut.mac[0].u_macsec_rx.m_axis_tuser,
                    macsec_tuser_stats,
                    "rx_out",
                )
            )
        cocotb.start_soon(
            monitor_rx_pipe_events(tb._get_sfp_sig(0, "tx_clk"))
        )
        cocotb.start_soon(
            monitor_tx_pipe_events(tb._get_sfp_sig(0, "tx_clk"))
        )
    except Exception:
        pass

    tb.log.info("Init driver")
    await tb.driver.init_pcie_dev(tb.rc.find_device(tb.dev.functions[0].pcie_id))
    await tb.driver.interfaces[0].open()
    # await tb.driver.interfaces[1].open()

    # enable queues
    tb.log.info("Enable queues")
    await tb.driver.interfaces[0].sched_blocks[0].schedulers[0].rb.write_dword(mqnic.MQNIC_RB_SCHED_RR_REG_CTRL, 0x00000001)
    for k in range(len(tb.driver.interfaces[0].txq)):
        await tb.driver.interfaces[0].sched_blocks[0].schedulers[0].hw_regs.write_dword(4*k, 0x00000003)

    # wait for all writes to complete
    await tb.driver.hw_regs.read_dword(0)
    tb.log.info("Init complete")

    tb.log.info("Send and receive single packet")

    data = bytearray([x % 256 for x in range(1024)])

    if live_debug:
        live("single_pkt_xmit_req")
    await start_xmit_checked(data, 0, stage="single_pkt_xmit")
    if live_debug:
        live("single_pkt_xmit_done")

    pkt = await recv_wire(stage="single_pkt_wire", timeout_us=recv_timeout_us)
    tb.log.info("Packet: %s", pkt)
    tx_frame = bytes(pkt.get_payload())
    assert tx_frame[:12] == bytes(data[:12])
    if live_debug:
        live(
            "single_pkt "
            f"hdr_in={bytes(data[:16]).hex()} "
            f"hdr_out={tx_frame[:16].hex()} "
            f"counters tx_in={macsec_frame_counts.get('tx_in', 0)} "
            f"tx_out={macsec_frame_counts.get('tx_out', 0)} "
            f"rx_in={macsec_frame_counts.get('rx_in', 0)} "
            f"rx_out={macsec_frame_counts.get('rx_out', 0)}"
        )

    await tb.sfp_source[0].send(pkt)

    pkt = await recv_host(stage="single_pkt_host", timeout_us=recv_timeout_us)

    tb.log.info("Packet: %s", pkt)
    assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
    _check_stage("after_single_pkt", strict=False)

    # await tb.driver.interfaces[1].start_xmit(data, 0)

    # pkt = await tb.sfp_sink[1].recv()
    # tb.log.info("Packet: %s", pkt)

    # await tb.sfp_source[1].send(pkt)

    # pkt = await tb.driver.interfaces[1].recv()

    # tb.log.info("Packet: %s", pkt)
    # assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff

    tb.log.info("RX and TX checksum tests")

    payload = bytes([x % 256 for x in range(256)])
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
    ip = IP(src='192.168.1.100', dst='192.168.1.101')
    udp = UDP(sport=1, dport=2)
    test_pkt = eth / ip / udp / payload

    test_pkt2 = test_pkt.copy()
    test_pkt2[UDP].chksum = scapy.utils.checksum(bytes(test_pkt2[UDP]))

    if live_debug:
        live("checksum_xmit_req")
    await start_xmit_checked(test_pkt2.build(), 0, 34, 6, stage="checksum_xmit")
    if live_debug:
        live(
            f"checksum_xmit_done tx_in={macsec_frame_counts.get('tx_in', 0)} "
            f"tx_out={macsec_frame_counts.get('tx_out', 0)}"
        )

    if live_debug:
        live("checksum_wait_wire")
    pkt = await recv_wire(stage="checksum_wire", timeout_us=recv_timeout_us)
    tb.log.info("Packet: %s", pkt)
    tx_frame = bytes(pkt.get_payload())
    assert tx_frame[:12] == test_pkt2.build()[:12]
    assert tx_frame[12:14] == b"\x88\xe5"
    if live_debug:
        live(
            "checksum "
            f"hdr_in={test_pkt2.build()[:16].hex()} "
            f"hdr_out={tx_frame[:16].hex()} "
            f"counters tx_in={macsec_frame_counts.get('tx_in', 0)} "
            f"tx_out={macsec_frame_counts.get('tx_out', 0)} "
            f"rx_in={macsec_frame_counts.get('rx_in', 0)} "
            f"rx_out={macsec_frame_counts.get('rx_out', 0)}"
        )

    await tb.sfp_source[0].send(pkt)
    if live_debug:
        live("checksum_wire_reflected_to_rx")

    if live_debug:
        live("checksum_wait_host")
    pkt = await recv_host(stage="checksum_host", timeout_us=recv_timeout_us)

    tb.log.info("Packet: %s", pkt)
    if live_debug:
        live("checksum_host_pre_assert")
    calc_rx_csum = ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
    assert pkt.rx_checksum == calc_rx_csum, (
        f"checksum_host rx_checksum mismatch got=0x{int(pkt.rx_checksum):04x} expected=0x{int(calc_rx_csum):04x}"
    )
    if live_debug:
        live("checksum_host_csum_ok")
    expected_pkt = test_pkt.build()
    got_pkt = Ether(pkt.data).build()
    if live_debug and got_pkt != expected_pkt:
        mismatch_idx = next((i for i, (a, b) in enumerate(zip(got_pkt, expected_pkt)) if a != b), -1)
        live(
            "checksum_host_payload_mismatch "
            f"got_len={len(got_pkt)} exp_len={len(expected_pkt)} "
            f"mismatch_idx={mismatch_idx} "
            f"got_head32={got_pkt[:32].hex()} exp_head32={expected_pkt[:32].hex()} "
            f"got_tail32={got_pkt[-32:].hex()} exp_tail32={expected_pkt[-32:].hex()}"
        )
    assert got_pkt == expected_pkt, (
        f"checksum_host payload mismatch got_len={len(got_pkt)} exp_len={len(expected_pkt)} "
        f"got_head32={got_pkt[:32].hex()} exp_head32={expected_pkt[:32].hex()} "
        f"got_tail32={got_pkt[-32:].hex()} exp_tail32={expected_pkt[-32:].hex()}"
    )
    if live_debug:
        live("checksum_host_payload_ok")
    _check_stage("after_checksum", strict=False)

    if smoke_only:
        tb.log.info("MACSEC_SMOKE_ONLY=1, stop after checksum path")
        if live_debug:
            live("smoke_only_enter")
        assert macsec_frame_counts.get("tx_in", 0) > 0
        assert macsec_frame_counts.get("tx_out", 0) > 0
        assert macsec_frame_counts.get("rx_in", 0) > 0
        assert macsec_frame_counts.get("rx_out", 0) > 0
        assert macsec_frame_counts.get("tx_in", 0) == macsec_frame_counts.get("tx_out", 0)
        assert macsec_frame_counts.get("rx_in", 0) == macsec_frame_counts.get("rx_out", 0)
        if live_debug:
            live("smoke_only_ready_to_return")
        await RisingEdge(dut.clk_250mhz)
        await RisingEdge(dut.clk_250mhz)
        if live_debug:
            live("smoke_only_return")
        return

    run_peer_interop = False
    run_queue_map = True
    run_rss = True
    run_small_pkts = True
    run_large_pkts = True
    run_lfc = True
    run_steady_flow = True
    run_arp_mix = True

    if test_stage == "peer_interop":
        run_peer_interop = True
        run_queue_map = False
        run_rss = False
        run_small_pkts = False
        run_large_pkts = False
        run_lfc = False
        run_steady_flow = False
        run_arp_mix = False
    elif test_stage == "small_pkts":
        run_large_pkts = False
        run_lfc = False
        run_steady_flow = False
        run_arp_mix = False
        if small_pkts_pre_stage == "none":
            run_queue_map = False
            run_rss = False
        elif small_pkts_pre_stage == "queue_map":
            run_queue_map = True
            run_rss = False
        else:
            run_queue_map = True
            run_rss = True
    elif test_stage == "arp_mix":
        run_peer_interop = False
        run_queue_map = False
        run_rss = False
        run_small_pkts = False
        run_large_pkts = False
        run_lfc = False
        run_steady_flow = False
        run_arp_mix = True

    # Optional explicit stage overrides for fast and focused diagnosis.
    ov_queue_map = _env_bool("MACSEC_RUN_QUEUE_MAP")
    ov_rss = _env_bool("MACSEC_RUN_RSS")
    ov_small = _env_bool("MACSEC_RUN_SMALL_PKTS")
    ov_large = _env_bool("MACSEC_RUN_LARGE_PKTS")
    ov_lfc = _env_bool("MACSEC_RUN_LFC")
    ov_steady_flow = _env_bool("MACSEC_RUN_STEADY_FLOW")
    ov_peer_interop = _env_bool("MACSEC_RUN_PEER_INTEROP")
    ov_arp_mix = _env_bool("MACSEC_RUN_ARP_MIX")

    if ov_queue_map is not None:
        run_queue_map = ov_queue_map
    if ov_rss is not None:
        run_rss = ov_rss
    if ov_small is not None:
        run_small_pkts = ov_small
    if ov_large is not None:
        run_large_pkts = ov_large
    if ov_lfc is not None:
        run_lfc = ov_lfc
    if ov_steady_flow is not None:
        run_steady_flow = ov_steady_flow
    if ov_peer_interop is not None:
        run_peer_interop = ov_peer_interop
    if ov_arp_mix is not None:
        run_arp_mix = ov_arp_mix

    stage(
        f"plan peer_interop={int(run_peer_interop)} arp_mix={int(run_arp_mix)} queue_map={int(run_queue_map)} rss={int(run_rss)} "
        f"steady={int(run_steady_flow)} small={int(run_small_pkts)} large={int(run_large_pkts)} "
        f"lfc={int(run_lfc)} strict_final={int(require_final_strict)}"
    )

    if run_peer_interop:
        stage("begin peer_interop")
        tb.log.info("MACsec peer interop check (L2 header cleartext, payload protected on wire)")

        payload = bytes([x % 256 for x in range(128)])
        eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
        ip = IP(src='10.10.0.1', dst='10.10.0.2')
        udp = UDP(sport=1111, dport=2222)
        test_pkt = eth / ip / udp / payload
        tx_bytes = test_pkt.build()

        await start_xmit_checked(tx_bytes, 0, stage="peer_interop_xmit")

        wire_pkt = await recv_wire(stage="peer_interop_wire", timeout_us=bulk_recv_timeout_us)
        wire_bytes = bytes(wire_pkt.get_payload())

        # Gate2.5 requirement under MACsec:
        # - DA/SA remain visible on wire
        # - EtherType on wire is MACsec (0x88E5)
        # - Payload/body is transformed and frame grows by security overhead
        # - Reflecting the protected frame back into RX recovers original host payload
        assert wire_bytes[:12] == tx_bytes[:12], (
            "Gate2.5 failed: DA/SA must remain cleartext on wire; "
            f"tx_head12={tx_bytes[:12].hex()} wire_head12={wire_bytes[:12].hex()}"
        )
        assert wire_bytes[12:14] == b"\x88\xe5", (
            "Gate2.5 failed: wire EtherType must be 0x88E5; "
            f"wire_ethertype=0x{wire_bytes[12:14].hex()}"
        )
        assert wire_bytes != tx_bytes, (
            "Gate2.5 failed: protected wire frame unexpectedly equals host plaintext frame"
        )
        assert len(wire_bytes) > len(tx_bytes), (
            "Gate2.5 failed: protected wire frame did not include expected security overhead; "
            f"tx_len={len(tx_bytes)} wire_len={len(wire_bytes)}"
        )

        # Keep RX datapath active in this stage by reflecting captured wire frame.
        await tb.sfp_source[0].send(wire_pkt)
        host_pkt = await recv_host(stage="peer_interop_host", timeout_us=bulk_recv_timeout_us)
        assert bytes(host_pkt.data) == tx_bytes
        _check_stage("after_peer_interop", strict=False)
        stage("done peer_interop")

    if run_arp_mix:
        stage("begin arp_mix")
        tb.log.info("ARP+IP mixed short-frame stress (header/payload pairing)")

        seq_tx = []
        for k in range(arp_mix_pairs):
            arp_pkt = (
                Ether(dst="ff:ff:ff:ff:ff:ff", src="5a:51:52:53:54:55")
                / ARP(
                    hwsrc="5a:51:52:53:54:55",
                    psrc=f"10.0.0.{(k % 10) + 1}",
                    hwdst="00:00:00:00:00:00",
                    pdst=f"10.0.0.{((k + 1) % 10) + 1}",
                    op=1,
                )
            )
            mdns_like = (
                Ether(dst="01:00:5e:00:00:fb", src="5a:51:52:53:54:55")
                / IP(src="10.0.0.4", dst="224.0.0.251")
                / UDP(sport=5353, dport=5353)
                / bytes([x & 0xFF for x in range(45 + (k % 2) * 20)])
            )
            seq_tx.append(arp_pkt.build())
            seq_tx.append(mdns_like.build())

        for idx, tx_bytes in enumerate(seq_tx):
            await start_xmit_checked(tx_bytes, 0, stage=f"arp_mix_xmit_{idx}")

        wire_pkts = []
        for idx, tx_bytes in enumerate(seq_tx):
            wire_pkt = await recv_wire(stage=f"arp_mix_wire_{idx}", timeout_us=bulk_recv_timeout_us)
            wire_bytes = bytes(wire_pkt.get_payload())
            wire_pkts.append(wire_pkt)

            if live_debug:
                live(
                    f"arp_mix wire_idx={idx} tx_head14={tx_bytes[:14].hex()} "
                    f"wire_head14={wire_bytes[:14].hex()} tx_len={len(tx_bytes)} wire_len={len(wire_bytes)}"
                )

            assert wire_bytes[:12] == tx_bytes[:12], (
                f"arp_mix wire DA/SA mismatch idx={idx} "
                f"tx_head12={tx_bytes[:12].hex()} wire_head12={wire_bytes[:12].hex()}"
            )
            assert wire_bytes[12:14] == b"\x88\xe5", (
                f"arp_mix wire EtherType mismatch idx={idx} "
                f"wire_ethertype=0x{wire_bytes[12:14].hex()} expected=0x88e5"
            )
            assert wire_bytes[14:] != tx_bytes[14:], (
                f"arp_mix wire payload not protected idx={idx} "
                f"wire_tail16={wire_bytes[-16:].hex()} tx_tail16={tx_bytes[-16:].hex()}"
            )
            assert len(wire_bytes) > len(tx_bytes), (
                f"arp_mix security overhead missing idx={idx} tx_len={len(tx_bytes)} wire_len={len(wire_bytes)}"
            )

        for idx, wire_pkt in enumerate(wire_pkts):
            await tb.sfp_source[0].send(wire_pkt)
            host_pkt = await recv_host(stage=f"arp_mix_host_{idx}", timeout_us=bulk_recv_timeout_us)
            if live_debug:
                live(
                    f"arp_mix host_idx={idx} host_head14={bytes(host_pkt.data)[:14].hex()} "
                    f"exp_head14={seq_tx[idx][:14].hex()} host_len={len(host_pkt.data)} exp_len={len(seq_tx[idx])}"
                )
            assert bytes(host_pkt.data) == seq_tx[idx], (
                f"arp_mix host payload mismatch idx={idx}"
            )

        _check_stage("after_arp_mix", strict=False)
        stage("done arp_mix")

    if run_queue_map:
        stage("begin queue_map")
        tb.log.info("Queue mapping offset test")

        data = bytearray([x % 256 for x in range(1024)])

        tb.loopback_enable = True

        for k in range(4):
            await tb.driver.interfaces[0].set_rx_queue_map_indir_table(0, 0, k)

            await start_xmit_checked(data, 0, stage=f"queue_map_xmit_{k}")

            pkt = await recv_host(stage=f"queue_map_offset_{k}")

            tb.log.info("Packet: %s", pkt)
            assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
            assert pkt.queue == k
            _check_stage(f"queue_map_recv_{k}", strict=False)

        tb.loopback_enable = False

        await tb.driver.interfaces[0].set_rx_queue_map_indir_table(0, 0, 0)
        _check_stage("after_queue_map", strict=False)
        stage("done queue_map")

    if run_rss:
        stage("begin rss")
        tb.log.info("Queue mapping RSS mask test")

        await tb.driver.interfaces[0].set_rx_queue_map_rss_mask(0, 0x00000003)

        for k in range(4):
            await tb.driver.interfaces[0].set_rx_queue_map_indir_table(0, k, k)

        tb.loopback_enable = True

        queues = set()

        for k in range(rss_pkt_count):
            payload = bytes([x % 256 for x in range(256)])
            eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
            ip = IP(src='192.168.1.100', dst='192.168.1.101')
            udp = UDP(sport=1, dport=k+0)
            test_pkt = eth / ip / udp / payload

            test_pkt2 = test_pkt.copy()
            test_pkt2[UDP].chksum = scapy.utils.checksum(bytes(test_pkt2[UDP]))

            await start_xmit_checked(test_pkt2.build(), 0, 34, 6, stage=f"rss_xmit_{k}")

        for k in range(rss_pkt_count):
            pkt = await recv_host(stage=f"rss_recv_{k}", timeout_us=bulk_recv_timeout_us)

            tb.log.info("Packet: %s", pkt)
            assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff

            queues.add(pkt.queue)
            if (k + 1) % max(1, small_step_check) == 0:
                _check_stage(f"rss_progress_{k+1}", strict=False)

        assert len(queues) >= rss_min_queues

        tb.loopback_enable = False

        await tb.driver.interfaces[0].set_rx_queue_map_rss_mask(0, 0)
        _check_stage("after_rss", strict=False)
        stage("done rss")

    if run_steady_flow:
        stage("begin steady_flow")
        tb.log.info(
            "Steady-flow receive continuity test (count=%d, burst_mode=%d)",
            steady_pkt_count,
            int(steady_burst_mode),
        )

        tb.loopback_enable = True
        queues = Counter()

        payload = bytes([x & 0xFF for x in range(256)])
        eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
        ip = IP(src='192.168.1.100', dst='192.168.1.101')
        udp = UDP(sport=9000, dport=9001)
        test_pkt = eth / ip / udp / payload
        test_pkt = test_pkt.copy()
        test_pkt[UDP].chksum = scapy.utils.checksum(bytes(test_pkt[UDP]))
        tx_bytes = test_pkt.build()

        if steady_burst_mode:
            for k in range(steady_pkt_count):
                await start_xmit_checked(tx_bytes, 0, 34, 6, stage=f"steady_xmit_{k}")
                if live_debug and (((k + 1) % max(1, small_step_check) == 0) or (k + 1) == steady_pkt_count):
                    live(
                        f"steady_xmit_progress_{k+1} "
                        f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                        f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                    )

            for k in range(steady_pkt_count):
                pkt = await recv_host(stage=f"steady_recv_{k}", timeout_us=bulk_recv_timeout_us)
                assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
                queues[int(pkt.queue)] += 1
                if (k + 1) % max(1, small_step_check) == 0 or (k + 1) == steady_pkt_count:
                    _check_stage(f"steady_progress_{k+1}", strict=False)
        else:
            for k in range(steady_pkt_count):
                if live_debug:
                    live(
                        f"steady_iter_{k}_before_xmit "
                        f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                        f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                    )
                await start_xmit_checked(tx_bytes, 0, 34, 6, stage=f"steady_xmit_{k}")
                if live_debug:
                    await _log_host_tx_diag(f"steady_iter_{k}_after_xmit")
                    live(
                        f"steady_iter_{k}_before_recv "
                        f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                        f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                    )
                pkt = await recv_host(stage=f"steady_recv_{k}", timeout_us=bulk_recv_timeout_us)
                assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
                queues[int(pkt.queue)] += 1
                if live_debug:
                    live(
                        f"steady_iter_{k}_after_recv q={int(pkt.queue)} "
                        f"tx_in={macsec_frame_counts.get('tx_in', 0)} tx_out={macsec_frame_counts.get('tx_out', 0)} "
                        f"rx_in={macsec_frame_counts.get('rx_in', 0)} rx_out={macsec_frame_counts.get('rx_out', 0)}"
                    )
                if (k + 1) % max(1, small_step_check) == 0 or (k + 1) == steady_pkt_count:
                    _check_stage(f"steady_progress_{k+1}", strict=False)

        tb.loopback_enable = False
        tb.log.info("Steady-flow queue distribution: %s", dict(sorted(queues.items())))
        _check_stage("after_steady_flow", strict=False)
        stage("done steady_flow")

    if run_small_pkts:
        stage("begin small_pkts")
        tb.log.info("Multiple small packets")

        tb.loopback_enable = True

        for round_idx in range(small_pkts_rounds):
            pkts = [bytearray([(x+k) % 256 for x in range(60)]) for k in range(small_pkts_count)]

            for p in pkts:
                await start_xmit_checked(p, 0, stage=f"small_pkts_r{round_idx}_xmit_{len(p)}")

            for k in range(small_pkts_count):
                pkt = await recv_host(stage=f"small_pkts_r{round_idx}_{k}", timeout_us=bulk_recv_timeout_us)

                tb.log.info("Packet: %s", pkt)
                assert pkt.data == pkts[k]
                assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
                if (k + 1) % max(1, small_step_check) == 0 or (k + 1) == small_pkts_count:
                    _check_stage(f"small_r{round_idx}_progress_{k+1}", strict=False)

        tb.loopback_enable = False
        _check_stage("after_small_pkts", strict=False)
        stage("done small_pkts")

    if run_large_pkts:
        stage("begin large_pkts")
        tb.log.info("Multiple large packets")

        count = 64

        pkts = [bytearray([(x+k) % 256 for x in range(1514)]) for k in range(count)]

        tb.loopback_enable = True

        for p in pkts:
            await start_xmit_checked(p, 0, stage=f"large_pkts_xmit_{k}")

        for k in range(count):
            pkt = await recv_host(stage=f"large_pkts_{k}", timeout_us=bulk_recv_timeout_us)

            tb.log.info("Packet: %s", pkt)
            assert pkt.data == pkts[k]
            assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
            if (k + 1) % max(1, small_step_check) == 0:
                _check_stage(f"large_progress_{k+1}", strict=False)

        tb.loopback_enable = False
        _check_stage("after_large_pkts", strict=False)
        stage("done large_pkts")

    if run_lfc and tb.driver.interfaces[0].if_feature_lfc:
        try:
            stage("begin lfc")
            tb.log.info("Test LFC pause frame RX")

            if lfc_ctrl_mask_raw:
                lfc_ctrl_mask = int(lfc_ctrl_mask_raw, 0)
            else:
                # Default to RX-only LFC in sim: enabling TX_LFC produces local
                # pause frames that can fragment loopback traffic and hide MACsec
                # data-path regressions.
                lfc_ctrl_mask = mqnic.MQNIC_PORT_LFC_CTRL_RX_LFC_EN

            await tb.driver.interfaces[0].ports[0].set_lfc_ctrl(lfc_ctrl_mask)
            await tb.driver.hw_regs.read_dword(0)
            lfc_ctrl = await tb.driver.interfaces[0].ports[0].get_lfc_ctrl()
            tb.log.info("LFC ctrl after enable: 0x%08x", lfc_ctrl)
            check_tx_pause = bool(lfc_ctrl & mqnic.MQNIC_PORT_LFC_CTRL_TX_LFC_EN)
            check_rx_pause = bool(lfc_ctrl & mqnic.MQNIC_PORT_LFC_CTRL_RX_LFC_EN)
            if live_debug:
                live(f"lfc_ctrl=0x{lfc_ctrl:08x}")
                live(
                    f"lfc_pause_check tx={int(check_tx_pause)} rx={int(check_rx_pause)} "
                    f"expect_pause={int(lfc_expect_pause)}"
                )

            lfc_xoff = Ether(src='DA:D1:D2:D3:D4:D5', dst='01:80:C2:00:00:01', type=0x8808) / struct.pack('!HH', 0x0001, 2000)

            if lfc_send_xoff:
                await tb.sfp_source[0].send(XgmiiFrame.from_payload(bytes(lfc_xoff)))
                if live_debug:
                    live(f"lfc_xoff_sent={bytes(lfc_xoff).hex()}")
            elif live_debug:
                live("lfc_xoff_skipped")

            tx_lfc_paused_sig = None
            rx_lfc_paused_sig = None
        # Use a known-alive top-level clock for bounded pause polling; avoids
        # stalling on inaccessible internal clock handles.
            lfc_obs_clk = dut.clk_250mhz
            if lfc_expect_pause:
                tx_lfc_paused_sig = _try_get_sig(("mac", 0, "eth_mac_inst", "stat_tx_lfc_paused"))
                rx_lfc_paused_sig = _try_get_sig(("mac", 0, "eth_mac_inst", "stat_rx_lfc_paused"))
                tx_paused_ok = True
                rx_paused_ok = True
                observed_pause = False
                if check_tx_pause:
                    tx_paused_ok = await _wait_pause_level(
                        tx_lfc_paused_sig,
                        True,
                        lfc_pause_assert_cycles,
                        lfc_obs_clk,
                        "eth_mac_inst.stat_tx_lfc_paused"
                    )
                    observed_pause = observed_pause or tx_paused_ok
                if check_rx_pause:
                    rx_paused_ok = await _wait_pause_level(
                        rx_lfc_paused_sig,
                        True,
                        lfc_pause_assert_cycles,
                        lfc_obs_clk,
                        "eth_mac_inst.stat_rx_lfc_paused"
                    )
                    observed_pause = observed_pause or rx_paused_ok
                if not observed_pause:
                    _log_macsec_debug("lfc_pause_assert_timeout")
                    raise AssertionError(
                        "LFC pause assert not observed; pause frame may not be recognized or frame structure is invalid"
                    )

            count = lfc_pkt_count

            pkts = [bytearray([(x+k) % 256 for x in range(1514)]) for k in range(count)]

            tb.loopback_enable = True

            for idx, p in enumerate(pkts):
                if live_debug:
                    live(f"lfc_xmit_req {idx}")
                await start_xmit_checked(p, 0, stage=f"lfc_xmit_{idx}")
                if live_debug:
                    live(
                        f"lfc_xmit_done {idx} tx_in={macsec_frame_counts.get('tx_in', 0)} "
                        f"tx_out={macsec_frame_counts.get('tx_out', 0)}"
                    )

            for k in range(count):
                while True:
                    pkt = await recv_host(stage=f"lfc_{k}", timeout_us=lfc_step_timeout_us)
                    # MAC control (pause) frames can appear on the host RX path during
                    # LFC exercises; they are control-plane artifacts, not payload data.
                    if len(pkt.data) >= 6 and bytes(pkt.data[0:6]) == b"\x01\x80\xc2\x00\x00\x01":
                        tb.log.info("Skip LFC control frame on host RX: %s", pkt)
                        if live_debug:
                            live(f"lfc_skip_ctrl k={k} len={len(pkt.data)}")
                        continue
                    break

                tb.log.info("Packet: %s", pkt)
                assert pkt.data == pkts[k]
                if tb.driver.interfaces[0].if_feature_rx_csum:
                    assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xffff
                if (k + 1) % max(1, small_step_check) == 0:
                    _check_stage(f"lfc_progress_{k+1}", strict=False)
                    if live_debug:
                        live(
                            f"lfc_progress {k+1}/{count} tx_lfc_paused={_safe_sig(tx_lfc_paused_sig)} "
                            f"rx_lfc_paused={_safe_sig(rx_lfc_paused_sig)}"
                        )

            if lfc_expect_pause:
                release_ok = True
                if check_tx_pause:
                    tx_release_ok = await _wait_pause_level(
                        tx_lfc_paused_sig,
                        False,
                        lfc_pause_release_cycles,
                        lfc_obs_clk,
                        "eth_mac_inst.stat_tx_lfc_paused"
                    )
                    release_ok = release_ok and tx_release_ok
                if check_rx_pause:
                    rx_release_ok = await _wait_pause_level(
                        rx_lfc_paused_sig,
                        False,
                        lfc_pause_release_cycles,
                        lfc_obs_clk,
                        "eth_mac_inst.stat_rx_lfc_paused"
                    )
                    release_ok = release_ok and rx_release_ok
                if not release_ok:
                    _log_macsec_debug("lfc_pause_release_timeout")
                    raise AssertionError("LFC pause did not release in expected time")

            tb.loopback_enable = False
            _check_stage("after_lfc", strict=False)
            stage("done lfc")
        except Exception as ex:
            dbg(f"[MACSEC_LFC_EXC] {ex!r}")
            dbg(traceback.format_exc())
            _log_macsec_debug("lfc_exception")
            raise

    # Gate 2 MACsec invariants
    assert macsec_frame_counts.get("tx_in", 0) > 0
    assert macsec_frame_counts.get("tx_out", 0) > 0
    assert macsec_frame_counts.get("rx_in", 0) > 0
    assert macsec_frame_counts.get("rx_out", 0) > 0
    _check_stage("final", strict=require_final_strict)

    await RisingEdge(dut.clk_250mhz)
    await RisingEdge(dut.clk_250mhz)


# cocotb-test

tests_dir = os.path.dirname(__file__)
repo_root = os.path.abspath(os.path.join(tests_dir, "..", ".."))
imports_root = os.path.join(repo_root, "mqnic_gcm_codex.srcs", "sources_1", "imports")
rtl_dir = os.path.join(imports_root, "fpga_25g", "rtl")
lib_dir = os.path.join(imports_root, "fpga_25g", "lib")
macsec_rtl_dir = os.path.join(imports_root, "rtl")
axi_rtl_dir = os.path.join(lib_dir, "axi", "rtl")
axis_rtl_dir = os.path.join(lib_dir, "axis", "rtl")
eth_rtl_dir = os.path.join(lib_dir, "eth", "rtl")
pcie_rtl_dir = os.path.join(lib_dir, "pcie", "rtl")
hls_model_dir = os.path.join(tests_dir, "hls_models")


def test_fpga_core(request):
    dut = "fpga_core"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = sorted(glob.glob(os.path.join(rtl_dir, "**", "*.v"), recursive=True))
    verilog_sources += sorted(glob.glob(os.path.join(lib_dir, "**", "*.v"), recursive=True))
    verilog_sources += sorted(glob.glob(os.path.join(macsec_rtl_dir, "*.v")))
    verilog_sources += [
        os.path.join(hls_model_dir, "hls_aes128gcm_enc_model.v"),
        os.path.join(hls_model_dir, "hls_aes128gcm_dec_model.v"),
        os.path.join(tests_dir, "xpm_fifo_sync_sim.v"),
        os.path.join(tests_dir, "xpm_fifo_async_sim.v"),
    ]
    verilog_sources += sorted(glob.glob(os.path.join(hls_model_dir, "enc", "*.v")))
    verilog_sources += sorted(glob.glob(os.path.join(hls_model_dir, "dec", "*.v")))

    parameters = {}

    # Structural configuration
    parameters['IF_COUNT'] = 2
    parameters['PORTS_PER_IF'] = 1
    parameters['SCHED_PER_IF'] = parameters['PORTS_PER_IF']
    parameters['PORT_MASK'] = 0

    # Clock configuration
    parameters['CLK_PERIOD_NS_NUM'] = 4
    parameters['CLK_PERIOD_NS_DENOM'] = 1

    # PTP configuration
    parameters['PTP_CLK_PERIOD_NS_NUM'] = 1024
    parameters['PTP_CLK_PERIOD_NS_DENOM'] = 165
    parameters['PTP_CLOCK_PIPELINE'] = 0
    parameters['PTP_CLOCK_CDC_PIPELINE'] = 0
    parameters['PTP_PORT_CDC_PIPELINE'] = 0
    parameters['PTP_PEROUT_ENABLE'] = 1
    parameters['PTP_PEROUT_COUNT'] = 1

    # Queue manager configuration
    parameters['EVENT_QUEUE_OP_TABLE_SIZE'] = 32
    parameters['TX_QUEUE_OP_TABLE_SIZE'] = 32
    parameters['RX_QUEUE_OP_TABLE_SIZE'] = 32
    parameters['CQ_OP_TABLE_SIZE'] = 32
    parameters['EQN_WIDTH'] = 6
    parameters['TX_QUEUE_INDEX_WIDTH'] = 13
    parameters['RX_QUEUE_INDEX_WIDTH'] = 8
    parameters['CQN_WIDTH'] = max(parameters['TX_QUEUE_INDEX_WIDTH'], parameters['RX_QUEUE_INDEX_WIDTH']) + 1
    parameters['EQ_PIPELINE'] = 3
    parameters['TX_QUEUE_PIPELINE'] = 3 + max(parameters['TX_QUEUE_INDEX_WIDTH']-12, 0)
    parameters['RX_QUEUE_PIPELINE'] = 3 + max(parameters['RX_QUEUE_INDEX_WIDTH']-12, 0)
    parameters['CQ_PIPELINE'] = 3 + max(parameters['CQN_WIDTH']-12, 0)

    # TX and RX engine configuration
    parameters['TX_DESC_TABLE_SIZE'] = 32
    parameters['RX_DESC_TABLE_SIZE'] = 32
    parameters['RX_INDIR_TBL_ADDR_WIDTH'] = min(parameters['RX_QUEUE_INDEX_WIDTH'], 8)

    # Scheduler configuration
    parameters['TX_SCHEDULER_OP_TABLE_SIZE'] = parameters['TX_DESC_TABLE_SIZE']
    parameters['TX_SCHEDULER_PIPELINE'] = parameters['TX_QUEUE_PIPELINE']
    parameters['TDMA_INDEX_WIDTH'] = 6

    # Interface configuration
    parameters['PTP_TS_ENABLE'] = 1
    parameters['TX_CPL_FIFO_DEPTH'] = 32
    parameters['TX_CHECKSUM_ENABLE'] = 1
    parameters['RX_HASH_ENABLE'] = 1
    parameters['RX_CHECKSUM_ENABLE'] = 1
    parameters['LFC_ENABLE'] = 1
    parameters['PFC_ENABLE'] = parameters['LFC_ENABLE']
    parameters['TX_FIFO_DEPTH'] = 32768
    parameters['RX_FIFO_DEPTH'] = 32768
    parameters['MAX_TX_SIZE'] = 9214
    parameters['MAX_RX_SIZE'] = 9214
    parameters['TX_RAM_SIZE'] = 32768
    parameters['RX_RAM_SIZE'] = 131072

    # Application block configuration
    parameters['APP_ID'] = 0x00000000
    parameters['APP_ENABLE'] = 0
    parameters['APP_CTRL_ENABLE'] = 1
    parameters['APP_DMA_ENABLE'] = 1
    parameters['APP_AXIS_DIRECT_ENABLE'] = 1
    parameters['APP_AXIS_SYNC_ENABLE'] = 1
    parameters['APP_AXIS_IF_ENABLE'] = 1
    parameters['APP_STAT_ENABLE'] = 1

    # DMA interface configuration
    parameters['DMA_IMM_ENABLE'] = 0
    parameters['DMA_IMM_WIDTH'] = 32
    parameters['DMA_LEN_WIDTH'] = 16
    parameters['DMA_TAG_WIDTH'] = 16
    parameters['RAM_ADDR_WIDTH'] = (max(parameters['TX_RAM_SIZE'], parameters['RX_RAM_SIZE'])-1).bit_length()
    parameters['RAM_PIPELINE'] = 2

    # PCIe interface configuration
    parameters['AXIS_PCIE_DATA_WIDTH'] = 256
    parameters['PF_COUNT'] = 1
    parameters['VF_COUNT'] = 0

    # Interrupt configuration
    parameters['IRQ_INDEX_WIDTH'] = parameters['EQN_WIDTH']

    # AXI lite interface configuration (control)
    parameters['AXIL_CTRL_DATA_WIDTH'] = 32
    parameters['AXIL_CTRL_ADDR_WIDTH'] = 24

    # AXI lite interface configuration (application control)
    parameters['AXIL_APP_CTRL_DATA_WIDTH'] = parameters['AXIL_CTRL_DATA_WIDTH']
    parameters['AXIL_APP_CTRL_ADDR_WIDTH'] = 24

    # Ethernet interface configuration
    parameters['AXIS_ETH_TX_PIPELINE'] = 0
    parameters['AXIS_ETH_TX_FIFO_PIPELINE'] = 2
    parameters['AXIS_ETH_TX_TS_PIPELINE'] = 0
    parameters['AXIS_ETH_RX_PIPELINE'] = 0
    parameters['AXIS_ETH_RX_FIFO_PIPELINE'] = 2

    # Statistics counter subsystem
    parameters['STAT_ENABLE'] = 1
    parameters['STAT_DMA_ENABLE'] = 1
    parameters['STAT_PCIE_ENABLE'] = 1
    parameters['STAT_INC_WIDTH'] = 24
    parameters['STAT_ID_WIDTH'] = 12

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    extra_env.setdefault("COCOTB_LOG_LEVEL", os.getenv("MACSEC_COCOTB_LOG_LEVEL", "WARNING"))
    extra_env.setdefault("COCOTB_REDUCED_LOG_FMT", "1")

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))
    os.makedirs(sim_build, exist_ok=True)
    for dat_file in sorted(glob.glob(os.path.join(hls_model_dir, "enc", "*.dat")) +
                           glob.glob(os.path.join(hls_model_dir, "dec", "*.dat"))):
        shutil.copy(dat_file, os.path.join(sim_build, os.path.basename(dat_file)))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        includes=[macsec_rtl_dir, os.path.join(hls_model_dir, "enc"), os.path.join(hls_model_dir, "dec")],
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )
