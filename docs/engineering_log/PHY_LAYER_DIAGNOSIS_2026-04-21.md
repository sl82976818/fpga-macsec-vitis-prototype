# PHY 层排查记录（2026-04-21）

## 背景
- 可用参考工程：`<baseline-project>`
- 当前工程：`<workspace>/mqnic_gcm_codex-2`
- 现象：上板后 `sfp_1_led` 不亮（接线确认无误）

## 对比方法
- 逐行对比以下文件：
  - `.../rtl/fpga_k35.v`
  - `.../constrs/.../fpga_k35.xdc`

## 发现的关键偏差（已处理）
1. `fpga_k35.v` 中曾新增 `sfp_1_tx_disable/sfp_2_tx_disable` 顶层输出并驱动。
2. `fpga_k35.xdc` 中曾启用 `sfp_1_tx_disable/sfp_2_tx_disable` 引脚约束（AL8/D28）。
3. `fpga_k35.v` 中曾将 `sfp_2_led` 改为 `sfp_gtpowergood` 诊断信号。

## 已回退为“可用工程一致”的状态
1. 删除/回退顶层 `sfp_1_tx_disable/sfp_2_tx_disable` 输出与对应赋值。
2. 将 XDC 中 `sfp_*_tx_disable` 约束恢复为注释状态。
3. 恢复 LED 映射：
   - `sfp_1_led = sfp0_rx_status`
   - `sfp_2_led = sfp1_rx_status`

## 当前结论
- SFP 物理层相关的“主动改动项”已恢复到可用工程基线。
- 若后续重新生成 bit 并下载后仍不亮，优先排查板级 refclk 来源（当前两工程都使用 V6/V5 作为 `sfp_mgt_refclk_0_p/n`）。

## 复现/验证步骤
1. 清理并重新跑综合实现（使用你当前稳定脚本或 Vivado GUI）。
2. 生成 bit 并下载到板卡。
3. 上板检查：
   - `mmcm_locked_led` 应亮。
   - `pcie_lnk_up_led` 应亮。
   - 插入已知可用光模块与对端链路后观察 `sfp_1_led`。
4. 若 `sfp_1_led` 仍不亮，执行 refclk 路径核查：
   - 确认板卡给 V6/V5 提供了有效 156.25MHz 参考。
   - 若硬件实际接的是 SI570（P6/P5），需切换 XDC 对应管脚并重编。

