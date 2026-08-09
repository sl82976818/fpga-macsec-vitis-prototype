# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Le Sun
# Author: Le Sun
#
# Part of the FPGA AES-GCM / MACsec research prototype.
#
#!/usr/bin/env bash
set -euo pipefail

TS=$(date +%Y%m%d_%H%M%S)

LOG=./macsec_gate2_full_${TS}.log
DBG=./macsec_gate2_full_dbg_${TS}.log

echo "LOG=$LOG"
echo "DBG=$DBG"

# 先创建 dbg 文件，避免路径/权限问题
: > "$DBG"

  stdbuf -oL -eL env \
    MACSEC_DEBUG_LOG_FILE="$DBG" \
    MACSEC_TB_LOG_LEVEL=INFO \
    MACSEC_COCOTB_LOG_LEVEL=WARNING \
    MACSEC_SMOKE_ONLY=0 \
    MACSEC_STAGE_PRINT=1 \
    MACSEC_LIVE_DEBUG=1 \
    MACSEC_RECV_POLL_US=20 \
    MACSEC_RECV_PROGRESS_EVERY=2 \
    MACSEC_BULK_RECV_TIMEOUT_US=20000 \
    MACSEC_DEBUG_LOG_FILE="$DBG" \
    pytest -s -q tb_local/fpga_core/test_fpga_core_macsec_sfp.py \
    2>&1 | tee "$LOG"

