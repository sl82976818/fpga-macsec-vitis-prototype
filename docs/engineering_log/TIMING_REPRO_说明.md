



# 时序结果与复现步骤（mqnic_gcm_codex-2）

## 1. 当前已保存结果（本目录）

- `result_timing_routed_default.rpt`
  - 来源：仅跑到 `impl_1` 默认 route 完成后的报告
  - 典型结果：`WNS=-0.175ns`，`TNS=-2.073ns`

- `result_timing_postroute_physopt_seedA.rpt`
  - 来源：route 后执行 `phys_opt_design -directive AggressiveExplore`
  - 结果：`WNS=-0.016ns`，`TNS=-0.016ns`，Failing Endpoints=1

- `result_timing_postroute_physopt_seedB.rpt`
  - 来源：再次执行同样 post-route phys_opt
  - 结果：`WNS=-0.016ns`，`TNS=-0.016ns`，Failing Endpoints=1

说明：`-0.016ns` 结果不是默认 `impl_1` 报告，而是 post-route phys_opt 后单独导出的报告。

## 2. 一键复现脚本（本目录）

- 脚本：`reproduce_timing_physopt.tcl`
- 运行命令：

```bash
cd <workspace>/mqnic_gcm_codex-2
vivado -mode batch -source <workspace>/mqnic_gcm_codex-2/reproduce_timing_physopt.tcl
```

脚本会执行：
1. `reset_run synth_1` + `reset_run impl_1`
2. `synth_1` 全跑
3. `impl_1` 跑到 `route_design`
4. `open_run impl_1` 后执行 `phys_opt_design -directive AggressiveExplore`
5. 在本目录输出：
   - `result_timing_postroute_physopt.rpt`
   - `result_timing_postroute_physopt_top20.rpt`
   - `result_postroute_physopt.dcp`
   - `result_util_postroute_physopt.rpt`

## 3. 结论（按当前源码）

- 只跑“综合+实现（默认route结束）”：通常不会接近 `-0.016ns`。
- 跑“综合+实现+post-route phys_opt(AggressiveExplore)”：可接近 `-0.016ns`（可能有几ps抖动）。

## 4. 基于该结果生成 bit（关键）

如果你已经在 post-route phys_opt 后看到 `WNS=-0.016ns / TNS=-0.016ns`，要确保 bit 与该状态一致，建议在同一已打开设计中按下列步骤执行：

```tcl
open_run impl_1
report_timing_summary -file <workspace>/mqnic_gcm_codex-2/result_timing_before_bit.rpt
write_checkpoint -force <workspace>/mqnic_gcm_codex-2/result_postroute_physopt_pass.dcp
write_bitstream -force <workspace>/mqnic_gcm_codex-2/result_postroute_physopt_pass.bit
```

说明：
- 若直接在这次 post-route 状态下 `write_bitstream`，生成的 bit 就对应这份 timing。
- 若重新启动/重跑实现后再出 bit，则不保证仍是这组 `-0.016ns` 结果。

## 5. 本次涉及源码改动（供追溯）

- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v`
  - 增加 HLS 时钟端口 `hls_clk/hls_rst`
  - `RAM_PIPELINE` 调整为 `3`

- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_k35.v`
  - `fpga_core` 连接 `.hls_clk(clk_125mhz_int)` `.hls_rst(rst_125mhz_int)`
  - `RAM_PIPELINE` 调整为 `3`

- `mqnic_gcm_codex.srcs/constrs_1/imports/fpga/mqnic/Nexus_K3P_S/fpga_25g/fpga_k35.xdc`
  - 新增 `pblock_macsec_gmac`（soft pblock）
  - 新增 `set_clock_groups -asynchronous`（`pcie_user_clk` 与 `sfp0_rx_clk/sfp0_tx_clk`）
  - 注意：`pblock_1 IS_SOFT true` 已回退，不在当前最终约束中。

## 6. 进一步吸收 -0.016ns 的实测结果

在同一基线 `fpga_routed.dcp` 上做独立后路由优化扫点（不改 RTL），已实测到过零：

- `sweep_default_physopt.rpt`
  - 命令：`phys_opt_design`（不加 directive）
  - 结果：`WNS=0.002ns`，`TNS=0.000ns`（setup 全过）
  - 对应 checkpoint：`sweep_default_physopt.dcp`

- `sweep_explore.rpt`
  - 命令：`phys_opt_design -directive Explore`
  - 结果：`WNS=-0.016ns`，`TNS=-0.016ns`
  - 对应 checkpoint：`sweep_explore.dcp`

推荐你优先使用 `sweep_default_physopt.dcp` 出 bit：

```tcl
open_checkpoint <workspace>/mqnic_gcm_codex-2/sweep_default_physopt.dcp
report_timing_summary -file <workspace>/mqnic_gcm_codex-2/result_timing_before_bit_from_sweep_default.rpt
write_bitstream -force <workspace>/mqnic_gcm_codex-2/result_postroute_physopt_wns_pos_0p002.bit
```

---

## 2026-04-21 PHY 排查补充

针对上板 `sfp_1_led` 不亮问题，已对比 `mqnic_pciex8` 可用工程并执行以下回退：

1. `fpga_k35.v`：回退 `sfp_1_tx_disable/sfp_2_tx_disable` 顶层输出及驱动逻辑。
2. `fpga_k35.xdc`：回退 `sfp_1_tx_disable/sfp_2_tx_disable` 约束为注释。
3. `fpga_k35.v`：回退 `sfp_2_led` 诊断映射，恢复为 `sfp1_rx_status`。

新增详细记录文件：`PHY_LAYER_DIAGNOSIS_2026-04-21.md`。
