# MACSEC R5 Debug Execution (2026-04-23)

## 1) 现场证据复核结论

- 对 `wiresharkCap/4.pcapng` 的 sudo 解析确认：坏包表现为
  - L2 头可见，但后续字段错位/密文化，典型 `Malformed ARP`。
- 与仿真 live log 对齐：
  - 修复前 `tx_out` 头 16B 出现 `...0c0d0000`（第 15/16 字节空洞化）。

## 2) 根因拆解

本轮明确存在两个串联问题：

1. **14B header 后的 AXIS 帧内空洞**
   - `HEADER_BYTES=14` 后，wrapper 原实现仍输出两拍 header，再从下一拍 lane0 发密文。
   - 导致拍间 2-byte hole，被 MAC/XGMII 侧体现在线包错位。

2. **输入桥不支持非满拍首拍 payload**
   - `axis_to_ap_fifo_bridge` 仅按 64b 拍拼 128b，不按 `tkeep` 压实数据。
   - 当 payload 首拍只有 2B（14B header 场景）时，后续被零填充/错位，导致“前两字节正常、后续全错”。

## 3) RTL 修改

### A. `macsec_tx_wrapper.v`

- 保持 `HEADER_BYTES=14`。
- 新增输入侧压实：`split_payload_*` -> `axis_keep_compactor_tx` -> `axis_to_ap_fifo_bridge`。
- 新增输出侧压实：`out_t*` -> `axis_keep_compactor_tx` -> `m_axis_t*`。
- 将 `out_axis_hs` 改为使用 compactor 输入 ready。
- 文件内内联 `axis_keep_compactor_tx` 模块（避免仿真源列表漏收新文件）。

### B. `macsec_rx_wrapper.v`

- 保持 `HEADER_BYTES=14` 与此前 `MIN_FRAME_BYTES(24 + (60-HEADER_BYTES))`。
- 新增输入侧压实：`strip_payload_*` -> `axis_keep_compactor_rx` -> `axis_to_ap_fifo_bridge`。
- 新增输出侧压实：`out_t*` -> `axis_keep_compactor_rx` -> `m_axis_t*`。
- 将 `out_axis_hs` 改为使用 compactor 输入 ready。
- 文件内内联 `axis_keep_compactor_rx` 模块。

## 4) 仿真结果

### 已通过

1. `macsec_tx_wrapper` 头部测试
   - 命令：
     - `pytest -q -s .../tb/macsec_tx_wrapper/test_macsec_tx_header.py`
   - 结果：`2 passed`

2. `macsec_loopback`（encrypt+decrypt）
   - 命令：
     - `pytest -q -s .../tb/macsec_loopback/test_macsec_loopback.py`
   - 结果：`2 passed`

3. Gate2.5 peer interop（仅该阶段）
   - 命令：
     - `MACSEC_TEST_STAGE=peer_interop ... pytest -q -s .../test_fpga_core_macsec_ip.py::test_fpga_core_macsec_ip`
   - 结果：`1 passed`
   - live 关键现象：`hdr_out` 不再出现 `...0000` hole。

### 仍需处理

4. Gate2 全流程脚本（Step2）
   - 命令：
     - `run_macsec_gate2_preboard.sh`
   - 结果：在 Step2 (`small_pkts` with `pre_stage=rss`) 失败于 `rss_recv_8` host recv timeout。
   - 失败时计数：`tx_in=14 tx_out=14 rx_in=14 rx_out=14`。
   - 说明：MACsec 包处理计数对齐，但 host 队列在 RSS 预阶段出现收包停滞（测试流程层面仍需继续收敛）。

## 5) 备注

- 本轮已删去未使用的独立 `axis_keep_compactor.v`，采用 wrapper 内联模块，避免仿真/工程收集差异。
