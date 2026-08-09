> **Publication note:** This is a publication-sanitized copy of the original read-only
> engineering audit. Technical conclusions have not been altered. Host-specific
> absolute paths have been normalized to `<project-root>` / `<toolchain-root>`
> / `<experiment-dir>`. Original timestamps and classifications are preserved.

# Vitis Security Library AES-128-GCM  MACsec — 10G 恢复性审计报告

**工程**: `mqnic_gcm_codex-2-v2-2.75gbps/mqnic_gcm_codex-2`
**Part**: xcku040-ffva1156-2-e | **顶层**: fpga (fpga_core.v) | **生成日期**: 2026-08-06
**方法**: 只读审计 + 分层周期模型（未改动任何 production RTL/HLS/XCI/XPR/约束）

---

## 0. 结论 (TL;DR)

| 项 | 结论 |
|---|---|
| **决策分类** | `CRYPTO_CAPABLE_INTEGRATION_BOTTLENECK` |
| **2.7G 测量是否有效** | **有效/架构一致**（非 invalid）。模型原版 1518B=2.6Gbps 与 2.7 标签吻合 |
| **crypto 核心 (cached-SA) 是否 10G 级** | **是**（核心单独：1518B≈16Gbps line） |
| **当前集成能否 10G** | **不能**——wrapper 单帧串行 store-and-forward 把一切压到 ~3.9Gbps 上限 |
| **要达到 10G 的必要步骤** | cached-SA（去除每帧 ~186→24 周期固定税）**并** wrapper 加 2+ 帧流水（去单帧串行） |

**一句话**：瓶颈不在 AES-GCM 核心（cached 后足够 10G），而在 `macsec_rx/tx_wrapper + tag_append/strip` 的**单帧在途 store-and-forward** 与**每帧串行 crypto 固定税**。只加 cached-SA 到不了 10G，必须同时做 wrapper 帧级流水。

---

## 1. 工程身份 (已冻结)

- Part `xcku040-ffva1156-2-e`（KU040，~17.1万 LUT / 支撑单核 10G cached-GCM 有余，双核需复核）
- 顶层 `fpga`（fpga_k35 -> fpga_core）；HLS IP：`ip/aes128gcm_enc|dec`（test_aesGcm*_128u_s，Vivado HLS 2022.1）
- HLS 源真实源：`mqnic_pciex8-AES-fromVitisLib/hls_source/aes128{enc,dec}/`，Vitis 库 `security/L1/include/xf_security/{gcm,gmac,aes}.hpp`
- **HLS 时钟 = `sfp0_tx_clk_int` = 156.25 MHz**（`macsec_types.vh` 里 200MHz 的 `MACSEC_HLS_CLK_FREQ_MHZ` 与路由实际不符）

## 2. 时钟与 timing 事实（决定计算依据）

| 域 | 频率 | 状态 |
|---|---|---|
| hls_clk (macsec crypto) | `sfx0_tx_clk_int` = 156.25 | 有效工作域 |
| XGMII eth_mac_10g | 156.25 | 64-bit |
| pcie_user_clk | 250 | algo |
| clk_wiz | 300.03 / 100.01 / 156.266 / 156.266 | — |
| **routed timing** | **WNS −0.206 ns, 172 endpoints, 283960 total** | ⚠️ **未 met** |

> 审计原则：不按 200MHz 估算，统一按 **156.25 MHz** 评估 crypto/MAC 域。

## 3. Crypto 核心（Vitis）行为核验

- `updateKey()` 每帧调用一次（AES-128 十轮，II=1，~13 周期）
- `H = AES_K(0)` 每帧计算；`GF128_prepare()` 每帧 128 次生成 Y[0..127]（~129 周期，串行链）
- `E(K,Y0)` 每帧一次（IV/PN 由 wrapper 传入）
- payload GCTR 循环与 payload GHASH 循环 **II=1**，内部可到 128-bit/cycle（长帧理论 ~20Gbps）

**每帧 crypto 串行固定税**：
- 原始：`updateKey(13) + 2×AES(40) + GF128_prepare(129) + AAD(1) + tail(3) = 186 周期 (~1.19µs)`
- cached-SA：`1×AES(20) + AAD(1) + tail(3) = 24 周期`（H / updateKey / GF128_prepare 移入 SA 配置）

## 4. Wrapper 层（store-and-forward，本次审计的核心瓶颈）

- `macsec_tx` → `frame_fifo`(16k) → `macsec_tx_wrapper` → `macsec_tag_append.v`（ST_CAPTURE→ST_WAITTAG→ST_OUTPUT，等 tag 填满 24B 才输出，FIFO 512×64）
- `macsec_rx_wrapper.v`：`payload_fifo`(2048) 收全帧 → `tag_strip.v`(512×64) → `axis_to_ap_fifo_bridge`(64→128 CDC) → HLS AES dec → `ap_fifo_to_axis_bridge`
- 透传：`macsec_rx_tx` 由 `crypto_enable`(硬连 1) 控制，**一次只有一个帧在途**（capture→crypto→release 全串行叠加）
- `tag` 必须等整帧 payload 处理完才产生 → **replay 无法与下一帧 capture 重叠** → 单帧串行

## 5. 吞吐模型（156.25 MHz, 单位 Gbps line）

| 帧 | 原始(现) | cached-SA | 说明（in total_cyc） |
|---|---|---|---|
| 64 | 0.31 | 0.74 | crypto 固定税 186→24 主导 |
| 512 | 1.55 | 2.53 | |
| 1518 | **2.60** | 3.34 | total cyc 731→569 |
| 9000 | 3.67 | 3.87 | |

**crypto 核心单独（无 wrapper 串行）**：cached 1518B ≈ **16 Gbps line** → 滤波 10G 无问题。

**结论数**：2.7G 标签 = 模型原始 1518B 的 2.60 —— 一致。差异在 wrapper 串行 (capture+crypto+release) 而非核心。

## 6. 要达到 10G 的路径（按成本排序）

1. **cached-SA**（把 H / updateKey / GF128_prepare / E(K,Y0) 中可复用部分在 SA 配置时预计算，每帧只付 ~24 周期）— **必需但不足**（单核 joiner 用完仍 ~3.3–3.9G）
2. **帧级流水（去单帧在途）**：`_tx`/`_rx` wrapper 与 tag 处理改为 **2+ 帧 ping-pong / frame-slot**，使下一个 capture 与当前 release+crypto 重叠 —— 核心必需项
3. **crypto 固定税 AVO 再降**（AXI+linger）+ 若可 200MHz（需先修 routed timing WNS）再提高线速
4. 不在本 audit 范围但应验证：**在 cached-SA + 流水之后**重新做 routed timing met（现 WNS −0.206 必须清）

## 7. 决策标记

- `CRYPTO_CAPABLE_INTEGRATION_BOTTLENECK`：核心可 10G，集成/流水链扣。2.7G 测量与架构一致（**非**)。
- 不采用 `VITIS_MACSEC_10G_CAPABLE`（现集成 holol构整体仍 <10G）——需先做缓存+流水。
- **恢复建议**：cached-SA 为第一步（低成本验证核心可到 10G），随后 wrapper 帧级流水平。
- **封存建议**：若以 2.7G 为交付值且不外推，可归档并保留缓存/流水为 vNext。

## 8. 证据文件要点

- `mqnic_gcm_codex.srcs/.../fpga_core.v:789+` wrapper 插入点；`fpga_k35.v:1271` hls_clk=sfp0_tx_clk_int
- `macsec_tx_wrapper.v` / `macsec_rx_wrapper.v`（不象 OUT_* 状态机、`crypto_enable=1`）
- `macsec_tag_append.v`（ST_WAITTAG，等待 24B tag）
- `mqnic_gcm_codex.runs/impl_1/fpga_timing_summary_routed.rpt`（WNS −0.206ns）
- 模型输出 + JSON（本目录同）
- HLS 固定税证据：`security/L1/include/xf_security/gcm.hpp` `gmac.hpp`（GF128_prepare / updateKey）以及 HLS 日志 `Vivado_HLS` 中 CTR/GHASH 的 II=1

---
*只读审计，未修改任何 RTL/HLS/网表/约束/工程。*