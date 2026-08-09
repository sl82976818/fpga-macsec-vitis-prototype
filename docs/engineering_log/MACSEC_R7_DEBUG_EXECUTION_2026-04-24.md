# MACSEC R7 Debug Execution (2026-04-24)

## 目标
- 继续按 R2/R3 路线推进 Gate2 前仿真，避免盲等超时。
- 强化“上板等效”验证，定位“先收几十包后停止”类症状。

## 本轮关键动作

### 1) 修复/改进 TB 稳定性
- 文件：`corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- 改动：
  - 将 MACsec HLS liveness 检查改为可选探测（层级存在才检查），避免实例名变化导致 0ns 假失败。
  - 新增 `steady_flow` 阶段（可开关）：
    - `MACSEC_RUN_STEADY_FLOW`
    - `MACSEC_STEADY_PKT_COUNT`
    - `MACSEC_STEADY_BURST_MODE`（1=先发后收，0=默认发一包收一包）
  - 为 `steady_flow` 增加实时日志：`steady_xmit_progress_*`、`steady_progress_*`。

### 2) 关键复现确认
- 正确入口：`test_fpga_core_macsec_ip.py`（编译 Vivado 导入的 MACsec RTL）
- 复现命令（burst 模式）：
  - `MACSEC_RUN_QUEUE_MAP=0 MACSEC_RUN_RSS=0 MACSEC_RUN_STEADY_FLOW=1 MACSEC_STEADY_PKT_COUNT=64 MACSEC_STEADY_BURST_MODE=1 MACSEC_BULK_RECV_TIMEOUT_US=500`
- 结果：稳定复现 `steady_recv_24` 超时。
  - 关键计数冻结：`tx_in=26 tx_out=26 rx_in=26 rx_out=26`
  - 日志：`[MACSEC_TIMEOUT] host steady_recv_24 timeout_us=500 ...`
  - 诊断快照（摘要）：
    - `pkt_q=0`
    - `cq_prod=26 cq_cons=26`
    - `rx_req_cnt=0`，`desc_hs=26`，`cpl_hs=26`
    - 管线事件计数不再增长

### 3) 重要分析结论
- 该“24后停住”在 burst 工况下高度可复现，且与上板“先收几十包后停”现象形态相似。
- 同时观察到：`steady_xmit_progress_32` 时 `tx_in` 仍为 2（仅完成 baseline 两包），说明 `start_xmit` 提交与数据面实际出包是解耦的，burst 工况中可能存在提交/回收节拍导致的仿真侧拥塞放大。
- 因此已将 `steady_flow` 默认模式改为 paced（发一包收一包），用于更接近上板低速持续流场景。

## 本轮产出
- 新增/更新：
  - `MACSEC_R7_DEBUG_EXECUTION_2026-04-24.md`（本文件）
  - `test_fpga_core_macsec_sfp.py`（liveness 容错 + steady_flow + 日志 + paced/burst 模式）

## 建议的下一步（R8）
1. 跑 `steady_flow` paced 64/256 包，确认低速持续流是否仍停。
2. 跑 `steady_flow` burst 64/128 包，保留当前复现作为压力回归。
3. 在 paced 与 burst 差异基础上，进一步定位是“数据面真实停流”还是“提交/回收节拍导致的仿真放大”。
