# Codex 变更记录

> 标注：以下为 **Codex 记录**（人工维护），用于追踪本仓库关键改动与仿真结果。

## 2026-04-16T15:41:48+02:00（Codex 记录）

### 本轮人工修改文件

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 修复 testbench 语法兼容问题（去除不兼容写法）。
- 增加 MACsec 集成路径注入与回环验证逻辑（TX 注入、RX 比对、PASS/FAIL/timeout）。
- 增加调试计数与关键内部信号打印，覆盖 `TX/RX MAC`、`tag_strip`、decrypt 交互路径。
- 调整 timeout（用于更快闭环定位）。
- 试验并回退了部分复位强制策略；保留当前可稳定复现实验现象的版本。

2. `mqnic_pciex8.srcs/sim_1/new/tb_top_batch.tcl`
- 将仿真运行时间从 `6000ns` 扩展到 `25000ns`，确保 testbench timeout/诊断信息可完整输出。

### 本轮关键仿真产物（自动生成，未手工编辑）

1. `mqnic_pciex8.sim/sim_1/behav/xsim/compile.log`
2. `mqnic_pciex8.sim/sim_1/behav/xsim/elaborate_axsim.log`
3. `mqnic_pciex8.sim/sim_1/behav/xsim/xsim.log`
4. `mqnic_pciex8.sim/sim_1/behav/xsim/frame_data_e2_rbt_out.txt`

### 仿真结论（最新一次）

- 命令链路：`compile.sh` -> `xelab -a` -> `axsim.sh -tclbatch tb_top_batch.tcl`
- 结果：`FAIL: timeout waiting for MACsec integration result`
- 证据摘要：
- `TX MAC` 与 `RX MAC` 均观测到 4 个 beat（含 `last`）。
- `rx_plain_beats=0`，`tag_v=0`，`tag_fifo_empty=1`。
- `macsec_tag_strip` 侧计数为 0（未进入有效 payload/tag 流）。
- 当前阻塞点：`macsec_rx_wrapper` 接收后未触发 tag/payload 进入解密链路。

## 2026-04-16T16:00:18+02:00（Codex 记录）

### 当前人工维护文件清单

1. `CODEX_CHANGELOG.md`
- 追加本条时间戳记录（Codex 维护）。

2. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 保持当前调试版本：包含 decrypt 路径关键观测点（`DBG_DEC_*`、`DBG_RX_PLAIN`）与 PASS/FAIL 判定。

3. `mqnic_pciex8.srcs/sim_1/new/tb_top_batch.tcl`
- 保持 `25000ns` 批处理仿真时长，用于覆盖 timeout 与完整诊断日志。

4. `security/macsec_engine/rtl/axis_to_ap_fifo_bridge.v`
- 当前为“首拍进高64、次拍进低64”的实验版本（待回归验证/可能回退）。
- 保留 `%m` 调试打印，便于区分 TX/RX bridge 实例。

5. `security/macsec_engine/rtl/ap_fifo_to_axis_bridge.v`
- 当前为“先发高64、后发低64”的实验版本（待回归验证/可能回退）。

### 当前问题状态（仿真结论）

- 集成仿真已从“无输出 timeout”推进到“有输出但明文半块异常”：
- decrypt 侧观测到 `len=128` 且密文块被读取；
- 但 `DBG_DEC_PLAIN` 仅半块有效，后半为 `0`，最终 `FAIL`。
- 下一步：先按指南核对并修正 decrypt `end_length/ciphertext_length` 语义与 128/64 字节序，再执行 xsim 项目模式复测。

## 2026-04-16T16:09:30+02:00（Codex 记录）

### 本次文件清单与改动说明

1. `CODEX_CHANGELOG.md`
- 追加本条时间戳记录（按用户要求记录文件列表与改动说明）。

2. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 当前保留“直接驱动 `u_macsec_tx.s_axis_*`”注入方案与 `DBG_TX_IN/DBG_DEC/DBG_RX_PLAIN` 观测点。
- 下一步将围绕“`u_in_bridge` 实际看到单拍帧尾”问题继续收敛注入/观测点。

3. `security/macsec_engine/rtl/axis_to_ap_fifo_bridge.v`
- 当前为低64先入（首拍低64，次拍高64）版本，保留 `%m` 状态机调试打印。

4. `security/macsec_engine/rtl/ap_fifo_to_axis_bridge.v`
- 当前为低64先出（先发 `block_data[63:0]`，后发 `block_data[127:64]`）版本。

### 当前阶段结论（进入下一步前）

- 下一步目标：确认 `u_macsec_tx -> u_in_bridge` 的真实两拍握手是否成立；若不成立，优先修正 testbench 注入绑定点，再进行下一轮项目模式 xsim 验证。

## 2026-04-16T16:45:25+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 修正 TX 注入握手时序（避免 `posedge` 竞争），改为在 `negedge` 驱动、在 `posedge` 等待握手。
- 注入点改为直接驱动 `u_macsec_tx.u_in_bridge.s_axis_*`，并等待 `u_in_bridge.s_axis_tready`。
- 增加 `DBG_TX_BRIDGE_PRE` 空闲状态确认；`DBG_TX_BR_IN` 增加时间戳打印，便于判定两拍是否同帧进入 bridge。

2. `security/macsec_engine/rtl/axis_to_ap_fifo_bridge.v`
- 保持本轮前已加入的长度修正与调试输出（`BRIDGE LWR2`、`PARAM MAC_DATA_BYTES`），本轮未再改动逻辑。

3. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 更新非增量仿真产物：`compile_nonincr.log`、`elaborate_nonincr_axsim.log`、`xsim_nonincr.log`。

### 仿真结果（xsim 项目模式，非增量）

- 命令链路：`xvlog --relax -prj tb_top_vlog.prj` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh -tclbatch tb_top_batch.tcl`
- 关键证据（`xsim_nonincr.log`）：
- `DBG_TX_BRIDGE_PRE state=0 pending=0 flush=0`
- `TX bridge length=0x80 frame_bytes=16`
- `RX bridge length=0x80 frame_bytes=16`
- `DBG_DEC_LEN read len_bits=128`
- `DBG_RX_PLAIN beat0=1122334455667788, beat1=99aabbccddeeff00`
- `PASS: fpga_core MACsec integration tx/rx plaintext match`

### 下一步

- 从“直接驱动 `u_in_bridge`”切回“驱动 `fpga_core axis_eth_tx_*` 源总线”的系统级注入方式，保持同样握手纪律，再跑 xsim 项目模式确认端到端链路仍然 PASS。

## 2026-04-16T16:48:13+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 注入点从 `u_macsec_tx.u_in_bridge.s_axis_*` 切回 `fpga_core axis_eth_tx_*` 源总线（系统级路径）。
- 保留 `negedge` 驱动 + `tready` 握手节拍控制，避免采样竞争。
- 保留 `DBG_TX_BRIDGE_PRE` 与时间戳化 `DBG_TX_BR_IN`，用于确认 bridge 状态与两拍握手时序。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 更新本轮仿真产物：`compile_nonincr.log`、`elaborate_nonincr_axsim.log`、`xsim_nonincr.log`。

### 仿真结果（xsim 项目模式，非增量）

- 命令链路：`xvlog --relax -prj tb_top_vlog.prj` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh -tclbatch tb_top_batch.tcl`
- 关键证据（`xsim_nonincr.log`）：
- `DBG_TX_BRIDGE_PRE state=0 pending=0 flush=0`
- `TX bridge length=0x80 frame_bytes=16`
- `RX bridge length=0x80 frame_bytes=16`
- `DBG_DEC_LEN read len_bits=128`
- `DBG_RX_PLAIN beat0=1122334455667788, beat1=99aabbccddeeff00`
- `PASS: fpga_core MACsec integration tx/rx plaintext match`

### 下一步

- 在保持当前系统级注入 PASS 的前提下，收敛/移除冗余调试打印，补充“tag 必须随帧传递”的稳定性用例（多帧连续、tag/length 对齐检查），每加一项用例即跑一轮 xsim 项目模式验证。

## 2026-04-16T17:02:40+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 尝试加入“连续两帧”验证（不同 payload）以覆盖“tag 随帧传递”。
- 通过多轮 xsim 观察到：TX bridge 能写出两帧 `length=0x80`，但当前回环/链路仅产生 1 次 `DBG_TAG_WR`，第二帧未完成解密回传（timeout）。
- 为保证主线可用，已将 testbench 回退到“系统级源总线注入 + 单帧验证”稳定版本（可 PASS）。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 更新本轮反复验证产生的 `compile_nonincr.log`、`elaborate_nonincr_axsim.log`、`xsim_nonincr.log`。

### 仿真结果（当前有效基线）

- 命令链路：`xvlog --relax -prj tb_top_vlog.prj` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh -tclbatch tb_top_batch.tcl`
- 关键证据（`xsim_nonincr.log`）：
- `DBG_TX_BRIDGE_PRE state=0 pending=0 flush=0`
- `TX/RX bridge length=0x80 frame_bytes=16`
- `DBG_DEC_LEN read len_bits=128`
- `DBG_RX_PLAIN beat0=1122334455667788, beat1=99aabbccddeeff00`
- `PASS: fpga_core MACsec integration tx/rx plaintext match`

### 下一步

- 单开一个“多帧连续”专项调试分支：先解耦 testbench 回环背压路径（避免 tag/data 循环依赖），再恢复两帧/多帧用例，并坚持每一步 xsim 项目模式验收后再前进。

## 2026-04-16T21:53:33+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `security/macsec_engine/rtl/macsec_tag_append.v`
- 简化 MACsec 帧尾格式升级为：`payload + PN(64b槽位低32有效) + TAG(128b)`。
- 新增 `s_pn` 输入，按帧与 `s_tag` 同步采样，输出时先发 PN 再发 TAG。

2. `security/macsec_engine/rtl/macsec_tag_strip.v`
- 与 append 对齐：从帧尾解析 `PN + TAG`，并将 payload 去尾后输出。
- 新增 `m_pn/m_pn_valid/m_pn_ready` 接口。

3. `security/macsec_engine/rtl/macsec_tx_wrapper.v`
- 新增 `pn_sideband_reg`（mac_clk 域）并在 tag 握手时递增。
- 将 `pn_sideband_reg` 送入 `macsec_tag_append`，实现 PN 随帧传输。

4. `security/macsec_engine/rtl/macsec_rx_wrapper.v`
- `tag_cdc_fifo` 由 128b 扩展至 160b，承载 `{pn, tag}`。
- 解密输入 `rx_pn` 改为来自帧内解析出的 PN（而非固定常量），完成“随帧 PN”闭环。

5. `security/macsec_engine/rtl/axis_to_ap_fifo_bridge.v`
- 修复 `ST_FRAME_END` 重复写 FIFO 的状态机缺陷（此前每帧同一 128b block 被写两次）。
- 该修复直接消除了多帧场景下“第二帧解密读到第一帧密文”的问题。

6. `security/macsec_engine/rtl/macsec_aes_decrypt.v`
- 增加 `ST_PRIME` 过渡态（`ap_start` 后延一拍再读 ciphertext），并保留调试打印用于当前阶段定位。

7. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 扩展为“两帧连续”系统级回环用例（验证 2 帧明文顺序与 `last` 边界）。
- 增加了阶段性调试打印（TX/RX tag+pn、decrypt 启动/读出等）。

8. `mqnic_pciex8.srcs/sim_1/new/tb_top_batch.tcl`
- 批处理时长扩到 `50000ns`，覆盖两帧连续场景。

### 仿真结果（xsim 项目模式，非增量）

- 命令链路：`xvlog --relax -prj tb_top_vlog.prj` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh -tclbatch tb_top_batch.tcl`
- 关键证据（`xsim_nonincr.log`）：
- RX bridge 每帧仅单次 `BRIDGE DATA_WR`（重复写已修复）。
- `DBG_DEC_CIPHER rd=0/1` 为两个不同密文块。
- `DBG_DEC_PLAIN write=0/1` 对应恢复：
  - `99aabbccddeeff001122334455667788`
  - `a1a2a3a4a5a6a7a80102030405060708`
- 最终：`PASS: fpga_core MACsec integration 2-frame tx/rx plaintext match`

### 下一步

- 在当前 2 帧 PASS 基线上，收敛调试打印并增加“多帧随机序列 + 连续 PN 检查 + tag/length 对齐检查”回归集，继续按“每步 xsim 通过再前进”执行。

## 2026-04-17T00:09:33+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 将长度 sweep 上限由 `82` 扩展到 `1520`（目标覆盖常见 MTU 区间 `64..1520`）。
- 将测试台总超时由 `50us` 扩展到 `5ms`，避免长 sweep 被测试台超时提前终止。
- 将 `TX_MAC_CLK_STALL_TIMEOUT` 由 `2us` 放宽到 `20us`，避免长帧场景误报时钟停滞。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 重新生成本轮增量编译/展开产物（`compile.log`、`elaborate_tb_top_sa_current.log`）。
- 执行 `axsim` 冒烟回归，确认修复后 `64..82` 全通过。

### 仿真结果（当前关卡）

- 命令链路：`./compile.sh` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh --tclbatch tb_top.tcl --log axsim_run_64_82.log`
- 关键证据：
- `PROGRESS: verified frame_len=82 bytes (19/19)`
- `PASS: fpga_core MACsec integration plaintext sweep 64..82 bytes (19 frames)`

### 下一步

- 继续同一命令链路，执行 `64..1520` 全范围 sweep；仅在拿到 PASS 仿真证据后进入后续集成步骤。

## 2026-04-17T01:56:36+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 将长度覆盖目标扩展为 `MAX_FRAME_LEN=1520`，并将总超时调整为 `5_000_000ns`（避免原常量溢出告警）。
- 进度打印由每 `128` 字节改为每 `32` 字节，并附带 `sim_time`，用于长跑可观测性。
- 尝试加入 `plusarg` 分段控制（`MIN/MAX_FRAME_LEN`）后发现在当前 `axsim` 路径下未生效，已回退该机制。
- 按分步验证策略将当前测试段设为 `257..1520`（第一段 `64..256` 已有通过证据）。

2. `CODEX_CHANGELOG.md`
- 追加本条时间戳记录（文件清单、改动说明、当前仿真进度）。

### 仿真结果（xsim 项目模式，当前进展）

- 命令链路固定为：`./compile.sh` -> `xelab -a ... --snapshot tb_top_sa` -> `./axsim.sh --tclbatch tb_top.tcl`

- 第一段（`64..256`）已通过到段尾：
- `PROGRESS: verified frame_len=64 bytes (1/1457)`
- `PROGRESS: verified frame_len=96 bytes (33/1457)`
- `PROGRESS: verified frame_len=128 bytes (65/1457)`
- `PROGRESS: verified frame_len=160 bytes (97/1457)`
- `PROGRESS: verified frame_len=192 bytes (129/1457)`
- `PROGRESS: verified frame_len=224 bytes (161/1457)`
- `PROGRESS: verified frame_len=256 bytes (193/1457)`

- 第二段（`257..1520`）当前已推进到 `448`：
- `PROGRESS: verified frame_len=257 bytes (1/1264)`
- `PROGRESS: verified frame_len=288 bytes (32/1264)`
- `PROGRESS: verified frame_len=320 bytes (64/1264)`
- `PROGRESS: verified frame_len=352 bytes (96/1264)`
- `PROGRESS: verified frame_len=384 bytes (128/1264)`
- `PROGRESS: verified frame_len=416 bytes (160/1264)`
- `PROGRESS: verified frame_len=448 bytes (192/1264)`

### 下一步

- 继续同一项目模式链路把第二段跑到 `1520` 并拿到段尾 PASS；随后合并第一段+第二段证据，形成完整 `64..1520` 覆盖结论。

## 2026-04-17T14:24:27+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 将长度范围临时切到盲区：`MIN_FRAME_LEN=1409`、`MAX_FRAME_LEN=1443`，用于补齐此前长跑中断后的证据空洞。
- 其余 MACsec 回环验证逻辑保持不变。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 更新本轮仿真产物：`compile.log`、`elaborate_tb_top_sa_current.log`、`xsim.log`（axsim 输出）。

3. `CODEX_CHANGELOG.md`
- 追加本条时间戳记录（按用户要求记录文件列表与改动说明）。

### 仿真结果（xsim 项目模式）

- 命令链路：`./compile.sh` -> `xelab -a --incr --relax --mt 8 ... --snapshot tb_top_sa` -> `./axsim.sh --runall`
- 关键证据（`xsim` 输出）：
- `PROGRESS: verified frame_len=1409 bytes (1/35)`
- `PROGRESS: verified frame_len=1416 bytes (8/35)`
- `PROGRESS: verified frame_len=1424 bytes (16/35)`
- `PROGRESS: verified frame_len=1432 bytes (24/35)`
- `PROGRESS: verified frame_len=1440 bytes (32/35)`
- `PROGRESS: verified frame_len=1443 bytes (35/35)`
- `PASS: fpga_core MACsec integration plaintext sweep 1409..1443 bytes (35 frames)`

### 下一步

- 将 `tb.v` 长度范围切回后续目标段（或全范围 `64..1520`），继续按“每步 xsim PASS 再前进”执行。

## 2026-04-17T23:06:31+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 临时将 `send_frame/check_frame` 日志改为“每帧打印”用于定位 `idx=4` 后是否真实卡死；
- 结论明确后已回退为原稀疏打印条件（`idx<4`、`len%64==0`、负向用例、末帧），避免后续慢仿真。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 执行了本轮编译/展开：`./compile.sh`、`./elaborate.sh`、`xelab --standalone ... --snapshot tb_top_dbg`；
- 生成并更新对应日志：`compile.log`、`elaborate.log`、`elaborate_tb_top_dbg.log`、`xsim.log`。

3. `CODEX_CHANGELOG.md`
- 追加本条时间戳记录（按要求含文件列表、改动说明、仿真证据）。

### 仿真结果（xsim 项目模式）

- 探针段（验证 `idx=4` 后无假卡死）：
- 日志：`<temp-log>`
- 关键证据：
- `PASS: fpga_core MACsec real-path plaintext sweep 1416..1424 bytes (9 frames)`
- `PASS: negative replay test observed PN anomaly`
- `PASS: negative tag tamper test observed ICV mismatch`
- `PASS: negative PN reorder test observed PN anomaly`

- 尾段重跑（你要求从 1412 附近继续，最终覆盖到 1520）：
- 日志：`<temp-log>`
- 关键证据：
- `PROGRESS: verified frame_len=1520 bytes (105/105)`
- `PASS: fpga_core MACsec real-path plaintext sweep 1416..1520 bytes (105 frames)`
- `PASS: negative replay test observed PN anomaly`
- `PASS: negative tag tamper test observed ICV mismatch`
- `PASS: negative PN reorder test observed PN anomaly`
- `PASS: all requested tests completed. sweep=105 frames ...`

- 中段历史完整覆盖证据（此前长跑）：
- 日志：`<temp-log>`
- 关键证据：
- `PASS: fpga_core MACsec real-path plaintext sweep 1156..1520 bytes (365 frames)`
- 同一日志内负向三项均 PASS。

## 2026-04-18T22:35:32+02:00（Codex 记录）

### 本轮文件清单与改动说明

1. `mqnic_pciex8.srcs/sim_1/new/tb.v`
- 新增第 4 点取证用监控计数：`rx_hls_in_count`、`rx_hls_out_count`；
- 增加 `TRACE: rx_hls_in/out` 打印（前 4 拍）；
- 在最终 PASS 摘要增加 `tx_hls_in/out` 与 `rx_hls_in/out` 统计输出；
- 在 RX timeout 失败路径中补充 `rx_hls` 计数打印，便于定位。

2. `mqnic_pciex8.sim/sim_1/behav/xsim/*`
- 重新执行 `./compile.sh` 与 `xelab --standalone ... --snapshot tb_top_dbg`，用于第 4/5 点验收。

3. Python cocotb 运行环境（工作区）
- 新建 `.venv_cocotb17/`，按 `corundum-master/tox.ini` 版本安装：`cocotb==1.7.2`、`cocotb-test==0.2.4`、`cocotbext-axi==0.1.24`、`cocotbext-eth==0.1.22`、`cocotbext-pcie==0.2.14` 等。

### 验收结果（第 4 点：真实 HLS IP 证据）

- 仿真命令（xsim 项目模式）：  
`./xsim.dir/tb_top_dbg/axsim --runall --testplusarg MIN_LEN=64 --testplusarg MAX_LEN=96`
- 日志：`<temp-log>`
- 关键证据：
- `TRACE: tx_hls_in ...` 与 `TRACE: tx_hls_out ...` 同时出现，且同拍数据不同（明文→密文）；
- `TRACE: rx_hls_in ...` 与 `TRACE: rx_hls_out ...` 同时出现，且 `rx_hls_out` 恢复为前述 `tx_hls_in` 明文；
- `PASS: hls handshake counters tx_hls_in=216 tx_hls_out=216 rx_hls_in=252 rx_hls_out=252`
- `PASS: fpga_core MACsec real-path plaintext sweep 64..96 bytes (33 frames)`

### 验收结果（第 5 点：集成边界）

- `compile + elaborate` 成功证据：`elaborate_tb_top_dbg.log` 含 `Built simulation snapshot tb_top_dbg`；
- 当前变更文件：`CODEX_CHANGELOG.md`、`tb.v`、`fpga_k35.v`、`mqnic_pciex8.xpr`、`security/macsec_engine/rtl/*`；
- 与 PCIe 相关的变更仅见：
- `fpga_k35.v`：新增参数 `SFP_COUNT_125US` 并透传到 `eth_xcvr_phy_10g_gty_quad_wrapper`（链路状态等待参数化，不改 PCIe 事务逻辑）；
- `mqnic_pciex8.xpr`：`WTXSimLaunchSim` 计数字段变化（工程元数据）。

### corundum-master cocotb 系统级验证

- 用例：`fpga/common/tb/mqnic_core_pcie_us/test_mqnic_core_pcie_us.py::test_mqnic_core_pcie_us[1-1-256-64-64-1]`
- 命令：`./.venv_cocotb17/bin/python -m pytest -q ...`
- 结果：`1 passed in 209.13s (0:03:29)`
- 结果文件：  
`corundum-master/fpga/common/tb/mqnic_core_pcie_us/sim_build/test_mqnic_core_pcie_us-1-1-256-64-64-1/*_results.xml`（`run_test_nic` 通过）
