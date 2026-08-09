// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
# E1 result artifact
# iverilog (tb3) of production macsec_tag_strip.v + xpm_fifo_sync_sim.v
# = observed FSM trace = (captured corrupt-tag 24B-tail frame):
#   C7, t=65000 st=0 (CAPTURE) ... captures 8,16,24 bytes
#   t=95000 st=1 (OUTPUT)  : decided release (NOT ST_DROP)
#   t=105000 st=2 (DRAIN)
#   t=125000 st=4 (WAITTAG)
#   t=135000 st=0 (CAPTURE, next frame ready)
# tag emitted = 0xFFEEDDCCBBAA9988... (the corrupt tag), never compared, never dropped.
# Conclusion:
#   (1) A frame whose trailing 16-byte ICV is CORRUPTED is STRIPPED of tag/pn
#       and RELEASED as plaintext (ST_OUTPUT reached).
#   (2) m_tag/pn/ethertype therefore carry attacker-controlled bytes with
#       NO integrity rejection - no auth gate BEFORE release.
#   (3) The ONLY drop path is frame_byte_count < MIN_FRAME_BYTES(24) (line 257),
#       independent of tag correctness.
# => AUTHENTICATION_BEFORE_RELEASE_VIOLATION: RX emits plaintext for invalid-tag frames.
# Note: full-integration plaintext beat emission not measured here (cocotb/TB timing);
#       but FSM release-path reachability for a corrupted tag is DEMONSTRATED.
# Production files byte-identical; only test code added in /tmp (not committed).
