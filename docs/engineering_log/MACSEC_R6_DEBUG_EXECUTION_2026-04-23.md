# MACsec R6 Debug Execution (2026-04-23)

## Goal
继续修复“上板 RX 停滞/收不到包”并完成上板前等效仿真收敛。

## Key Findings

1. **TX 输入空洞问题（本轮确认为回归源）**
- 现象：`SMOKE_ONLY` 在 checksum host 回环时报文不等效。
- 证据：payload 在 L3 开头被插入 6 字节 0，后续整体右移 6 字节。
- 根因：此前临时去掉 `macsec_tx_wrapper` 的输入 compactor 后，14-byte 头拆分导致首个 payload beat 只有 2 字节有效，后续 6 字节空洞被当成真实明文送入加密。

2. **RX 短帧被错误丢弃（本轮确认与上板现象高度相关）**
- 现象：`arp_mix` 中 `rx_in` 增长但 `rx_out` 在短帧处停滞，host 无包可收。
- 证据：`arp_mix` 首帧 ARP 保护帧进入 `rx_in`，但 `rx_out` 不出；修改后 `rx_out` 连续增长。
- 根因：`macsec_rx_wrapper` 中 `macsec_tag_strip` 的 `MIN_FRAME_BYTES` 设为 `24 + (60-HEADER_BYTES)=70`，会把 ARP 这类短保护帧（header 去除后 payload+auth 约 52B）误判为 runt 并丢弃。

## Code Changes

1. `mqnic_gcm_codex.srcs/sources_1/imports/rtl/axis_to_ap_fifo_bridge.v`
- 修复 metadata 竞争：
  - 移除 `frame_start_reg` 对 `length_store_valid` 的清零路径（该路径会在 pending write 未落 FIFO 时导致 length 丢失）。
  - 统一为 pending-first，再 arm 当前 frame 的 `length/end`。
  - 修复 `end_pending_reg` 同拍覆盖风险。
- 关闭 bridge 内部强制 debug 打印：`DEBUG_LOG=0`。

2. `mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_tx_wrapper.v`
- 恢复 TX 输入 `axis_keep_compactor_tx u_in_compactor`（撤销“直连 split payload 到 bridge”的临时改动），消除帧内空洞。

3. `mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_rx_wrapper.v`
- `u_tag_strip` 的 `MIN_FRAME_BYTES` 从 `24 + (60-HEADER_BYTES)` 调整为 `24`，允许合法短保护帧通过。

4. `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- 加强 checksum host 断言前后实时日志，定位到 payload 偏移根因。
- 新增 `MACSEC_ARP_MIX_PAIRS`（默认 8）用于快速回归缩短样本。

## Test Results (R6)

1. **SMOKE_ONLY**
- 结果：PASS（修复后恢复）。

2. **arp_mix（缩样：`MACSEC_ARP_MIX_PAIRS=2`）**
- 结果：PASS (`1 passed in 231.18s`)。
- 说明：短 ARP/IP 混合路径可通过，`rx_out` 不再首帧后停滞。

3. **Gate2 Step2（small_pkts 路径，实时日志）**
- 当前状态：仍存在“仿真长时间无退出/卡在 host recv wait 进度点”的执行层问题，非立即的短帧丢弃问题。
- 观察：`queue_map` 全通过，`rss` 中计数持续健康（`tx/rx in/out` 同步增长），但在 `rss_recv_8` 出现 wait 进度后仿真执行层再次卡住。

## Current Assessment

- 功能面（与上板故障最直接相关）已修掉两项关键设计问题：
  - TX 输入空洞导致 payload 错位。
  - RX tag_strip 对短保护帧的错误门限丢弃。
- 仍需继续处理 `small_pkts/rss` 回归中的“执行卡住”问题，才能把 Gate2 全流程稳定跑完。
