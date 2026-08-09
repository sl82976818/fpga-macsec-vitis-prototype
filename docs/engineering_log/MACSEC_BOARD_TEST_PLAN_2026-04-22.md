# MACsec Board Test Plan

Date: 2026-04-22

## Goal

Validate the current MACsec integration before and during board testing. The target workflow is:

```text
Linux ping/ARP -> mqnic TX DMA -> axis_eth_tx_* -> macsec_tx_wrapper
-> eth_mac_10g/XGMII/PHY -> peer RX
-> macsec_rx_wrapper -> mqnic RX DMA -> Linux receives packet
```

The main objective is to avoid guessing from a bitstream alone. Each gate below should answer one specific question and provide a clear next debug direction on failure.

## Gate 0: RTL State Check

Before building a MACsec-enabled bitstream, confirm [fpga_core.v](mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v) is not still in bypass mode.

Current bypass locations:

```verilog
// mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:813
.enable(1'b0)

// mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:834
.enable(1'b0)
```

For MACsec board testing, change both to:

```verilog
.enable(1'b1)
```

Do not synthesize immediately after flipping these. Run the simulation gates first.

## Gate 1: MACsec Unit-Level Cocotb

Purpose: verify that the wrappers no longer encrypt the visible L2 header and that TX->RX can restore complete frames.

Run:

```bash
timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q \
  corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_tx_wrapper/test_macsec_tx_header.py

timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q \
  corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_loopback/test_macsec_loopback.py
```

Expected:

```text
test_macsec_tx_header.py: 2 passed
test_macsec_loopback.py: 2 passed
```

These tests already passed once after the wrapper fixes, but they should be repeated immediately before any synthesis run.

## Gate 2: Full fpga_core Cocotb Flow

Purpose: reproduce the board workflow in simulation as closely as possible: mqnic driver TX, MACsec TX, simulated link, MACsec RX, mqnic driver RX.

Base the K3P_S test on the existing K3P_Q MACsec integration tests:

```text
corundum-master/fpga/mqnic/Nexus_K3P_Q/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py
corundum-master/fpga/mqnic/Nexus_K3P_Q/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py
```

Target K3P_S files:

```text
corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py
corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py
```

The full test should cover:

```text
1. mqnic driver initialization
2. port 0 TX sends a normal Ethernet/IP payload
3. macsec_tx_wrapper input frame count increases
4. macsec_tx_wrapper output frame count increases
5. TX output DA/SA stays visible and unchanged
6. simulated link forwards TX output to RX input
7. macsec_rx_wrapper output restores the original plaintext frame
8. mqnic RX DMA receives the packet
```

Add or monitor these counters/assertions:

```text
tx_in_frames
tx_out_frames
rx_in_frames
rx_out_frames
tx_l2_header_preserved
rx_payload_restored
host_rx_packet_count
```

Pass criteria:

```text
tx_in == tx_out
rx_in == rx_out
TX output DA/SA equals input DA/SA
RX output frame equals the original host-sent frame
driver recv() can receive the frame
```

If this gate fails, do not proceed to board testing. Fix the simulation-visible issue first.

## Gate 3: Vivado Build Checks

After cocotb passes, run Vivado compile/synthesis checks to catch tool, IP, CDC/FIFO, and timing problems.

Suggested synthesis run:

```bash
vivado -mode batch -source mqnic_gcm_codex.runs/synth_1/fpga.tcl
```

For a quicker Vivado behavioral/elaboration check:

```tcl
open_project mqnic_gcm_codex.xpr
update_compile_order -fileset sources_1
launch_simulation -simset sim_1 -mode behavioral
```

Use cocotb as the primary functional datapath check. Use Vivado simulation/elaboration to confirm the Vivado project accepts the RTL and IP setup.

## Gate 4: Board Test Procedure

Do not rely on `ping` alone. Capture counters before and after traffic.

On both hosts, before traffic:

```bash
ip -s link show <iface>
ethtool -S <iface>
```

On the local FPGA host:

```bash
ip neigh flush dev <iface>
ping -c 3 <peer-ip>
ethtool -S <iface>
```

On the peer host:

```bash
ip -s link show <iface>
ethtool -S <iface>
tcpdump -eni <iface> arp or icmp
```

Interpretation:

```text
Local TX increases, peer RX does not:
  Check TX wrapper output to MAC/PHY. Add ILA around TX wrapper output.

Peer RX increases, but tcpdump sees nothing:
  Frame may have bad FCS, bad length, or be dropped before host delivery.

Peer tcpdump sees ARP/ICMP:
  TX path is basically working. Continue with peer reply and local RX debug.

Peer sends reply, local RX does not increase:
  Check local rx_mac -> macsec_rx_wrapper -> mqnic RX DMA.
```

## ILA Plan

If cocotb passes but board traffic still fails, add ILA on port 0 only.

Capture these four breakpoints:

```text
axis_eth_tx_tdata/tkeep/tvalid/tready/tlast
axis_eth_tx_mac_tdata/tkeep/tvalid/tready/tlast
axis_eth_rx_mac_tdata/tkeep/tvalid/tlast
axis_eth_rx_tdata/tkeep/tvalid/tready/tlast
```

Trigger:

```text
axis_eth_tx_tvalid && axis_eth_tx_tready
```

First TX frame check:

```text
TX wrapper output first 16 bytes should still contain:
DA + SA + EtherType + first 2 payload bytes
```

This validates that the peer MAC can still accept the frame and that the previous failure mode, encrypted DA/SA, is not back.

## Recommended Next Step

Implement the K3P_S `fpga_core_macsec` cocotb test first, then switch both `fpga_core.v` wrapper enables to `1'b1`, run synthesis, and only then generate the board bitstream.
