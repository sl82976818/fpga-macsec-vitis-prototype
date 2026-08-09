# MACSEC R4 调试执行记录（2026-04-23）

## 1. 目标与背景
- 日期：2026-04-23
- 当前阶段：在 R2（Gate0~Gate3）之后继续修复，目标是恢复上板前等效仿真有效性，并最终支撑上板互通。
- 已知现场问题：上板 `rx` 在初始化后短暂收少量包后停止；`tx` 继续增长。
- 关键判断：必须避免“等超时再看”，需要通过实时日志尽早定位问题路径。

## 2. 本轮核心思路
1. 先强化观测：让 TB 在运行中持续输出关键计数和帧头，而不是仅在最终超时后看结果。
2. 将“MACsec wrapper 保留 / 仅加解密可关”与“完全旁路”两种模式都做实验，确认哪条路径导致 host 收不到包。
3. 新增 Gate2.5（plain peer interop）作为独立闸门，专门验证线速帧是否被错误改写。
4. 若仍失败，把故障压缩到最小场景（smoke/single_pkt），优先拿到首个可复现分叉点。

## 3. 代码与脚本改动清单

### 3.1 新增/扩展测试流程
- 文件：`corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/run_macsec_gate2_preboard.sh`
- 改动：加入 Step 2.5（`peer_interop`）
  - `MACSEC_TEST_STAGE=peer_interop`
  - 显式关闭 queue_map/rss/small/large/lfc 阶段覆盖

### 3.2 Gate2.5 场景接入 TB
- 文件：`corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- 改动：
  - 支持 `MACSEC_TEST_STAGE=peer_interop`
  - 新增 `run_peer_interop` 流程：
    - host 发确定性 L2/L3/L4 帧
    - wire 收包并与 host 发包做逐字节对比
    - 不一致时输出 `tx_len/wire_len/tx_head/wire_head`
    - 反射回 host，再验证 host 收包

### 3.3 TX wrapper 可分离保护开关
- 文件：`mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_tx_wrapper.v`
- 改动：
  - 新增参数 `PROTECT_ENABLE`
  - 引入 `crypto_enable = enable && PROTECT_ENABLE`
  - 保护相关状态机/握手/输出选择改为 `crypto_enable` 控制

### 3.4 RX wrapper 可分离保护开关 + 多轮旁路实验
- 文件：`mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_rx_wrapper.v`
- 改动（本轮多次迭代，均已记录）：
  - 新增参数 `PROTECT_ENABLE`
  - 引入 `crypto_enable = enable && PROTECT_ENABLE`
  - 尝试过：
    1) `PROTECT_ENABLE=0` 时仍走内部 FIFO/部分重组旁路
    2) `PROTECT_ENABLE=0` 时更硬的直通逻辑（`m_axis<=s_axis`）
    3) `s_axis_tready` 固定高以适配 MAC RX 无背压源

### 3.5 fpga_core 实例化与参数接线调整
- 文件：`mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v`
- 改动（本轮有多次实验）：
  - `macsec_tx_wrapper`/`macsec_rx_wrapper` 接入 `PROTECT_ENABLE(MACSEC_DATA_PROTECT_ENABLE)`
  - `enable` 在实验中尝试过两种接法：
    - 固定 `1'b1`（wrapper 常开，仅保护可关）
    - `enable(MACSEC_DATA_PROTECT_ENABLE)`（保护关时 wrapper 旁路）
  - 保留 `u_macsec_tx -> axis_fifo(FRAME_FIFO=1) -> eth_mac_10g` 路径
  - 一次修正：`axis_eth_rx_tuser` 曾改为跟随 `axis_eth_rx_mac_tuser`（用于排查 host 不收包路径）

### 3.6 TB 诊断能力增强
- 文件：`corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- 新增/增强：
  - `frame_head` 实时打印（`tx_in/tx_out/rx_in/rx_out`）
  - `wait_host/wait_wire` 周期性进度输出（含四向计数）
  - 超时时输出更完整的 debug snapshot（状态机/hold寄存器/tuser/continuity）
  - 额外诊断：`recv_host` 超时时尝试探测 `interface[1]` 是否收到包（用于排除端口错投）

## 4. 关键执行过程与结果

### 4.1 Gate2.5 首次判定（修复前）
- 现象：`peer_interop` 失败
- 关键信息：
  - `Gate2.5 mismatch: tx_len=170 wire_len=194`
  - `tx_head` 与 `wire_head` L2开头相同但后续明显分叉
- 结论：线速帧被改写，不满足 plain peer 互通。

### 4.2 修复后快速回归（多轮）
- 统一现象（smoke/single_pkt）：
  - `single_pkt_host` 超时
  - 同时计数为：`tx_in=1 tx_out=1 rx_in=1 rx_out=1`
  - `frame_head` 在四个观测点一致（如 `000102...0f`）
- 代表性日志特征：
  - `wait_host single_pkt_host elapsed_us=... tx_in=1 tx_out=1 rx_in=1 rx_out=1`
  - 最终 `Timeout at single_pkt_host`
- 结论：
  - 帧确实走到了 `u_macsec_rx.m_axis`（`rx_out` 已计到 1）
  - 但 host `recv()` 未拿到包（completion 未形成或未被正确消费）
  - 问题已从“早期链路”压缩到“RX wrapper 输出之后到 host RX completion 之间”。

### 4.3 超时窗口扩大实验
- 动作：将 `MACSEC_RECV_TIMEOUT_US` 从 `300` 拉到 `5000` 进行验证
- 结果：依旧失败（并非简单超时时间过短）

### 4.4 interface[1] 兜底探测
- 动作：在 `recv_host` 超时后试探 `interface[1].recv()`
- 结果：无证据表明包被投递到 interface1
- 结论：当前更像是 iface0 RX completion 路径内部问题，不是明显端口错投。

## 5. 当前状态评估
- 正向进展：
  - 已建立 Gate2.5 明确约束（wire 字节等价）
  - 已建立高密度实时日志，不再依赖“跑到超时才看”
  - 故障定位范围显著收敛：`rx_out` 有帧、host 无包
- 未闭环项：
  - 仍未恢复 smoke 通过
  - 因此尚不能判定“可上板前通过”

## 6. 建议的后续动作（下一轮执行计划）
1. 在 TB 中新增 `mqnic_interface_rx` / RX desc / RX completion 级别计数探针，拿到“最后一次成功握手”位置。
2. 与基线工程 `<baseline-project>` 对照同一时刻信号，定位首个分叉点。
3. 在分叉点前后最小化改动修复，并先确保 `MACSEC_SMOKE_ONLY=1` 稳定通过。
4. smoke 通过后重跑 Gate2（含 2.5），最后再做上板前验证结论。

## 7. 本轮修改文件汇总
- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v`
- `mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_tx_wrapper.v`
- `mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_rx_wrapper.v`
- `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/run_macsec_gate2_preboard.sh`

## 8. 备注
- 本文档为 2026-04-23 当天 R4 调试记录，覆盖“思路、过程、改动、结果”。
- 后续建议每轮新增 `R4.x` 子记录或在本文件追加“增量章节”，保持可追溯性。
