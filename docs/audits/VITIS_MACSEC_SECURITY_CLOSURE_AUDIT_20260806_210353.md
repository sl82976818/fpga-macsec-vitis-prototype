> **Publication note:** This is a publication-sanitized copy of the original read-only
> engineering audit. Technical conclusions have not been altered. Host-specific
> absolute paths have been normalized to `<project-root>` / `<toolchain-root>`
> / `<experiment-dir>`. Original timestamps and classifications are preserved.

# Vitis AES-128-GCM MACsec — 安全闭环审计

**审计日期**: 2026-08-06 | **工程**: `mqnic_gcm_codex-2-v2-2.75gbps/mqnic_gcm_codex-2` | **FPGA**: xcku040-ffva1156-2-e
**方法**: 只读 RTL/HLS/tb/log/约束分析；未修改 production；未建仿真（仅依据现有证据与静态结构判断）。

> 本报告依据“实际实现的安全合同”逐项给出证据（file:line），不做“假定完整 MACsec”的默认。

---

## 1. 实际安全合同

| 维度 | 实际实现 | 证据 |
|---|---|---|
| key identity | 单一全局 key：`0x00112233445566778899AABBCCDDEEFF`，**TX+RX 共用** | fpga_core localparam `MACSEC_AES_KEY` (fpga_core.v:717) |
| SA identity | 无 SA 管理（无 SA 表 / active / retired / generation） | 无任何 SA reg/logic；仅 SSCI 常量 |
| direction | 无 direction 标识（TX/RX 共用 key/SSCI 前缀） | fpga_core.v:879/949 同钥 |
| SSCI | `MACSEC_SSCI_BASE(0x12345678)+n` (每 port +1) | fpga_core.v:718,801 |
| AN | 无；仅 IV 常量 `0x5C5C5C5C` | aes_encrypt.v:139 |
| PN | TX: 本地 reg 自增；RX: 取帧内 tag 尾部 | aes_encrypt.v:167, aes_decrypt.v:739 |
| IV/nonce | `{SSCI(32bit), PN(32bit), 32'h5C5C5C5C}` (96bit) | aes_encrypt.v:139, 180; aes_decrypt.v:141 |
| AAD | `{80'h0, 16'h0001, SSCI(32)}`；AAD_length=48bit | aes_encrypt.v:140-141 |
| ciphertext | 14B L2 header 明文，其后全密文；wire EtherType=0x88E5 | tx wrapper |
| ICV 长 | 16B tag（尾）+PN；见 tag_append | tag_append / tag_strip |
| replay rule | 无 | （见 §6） |
| key activation/retirement | 无（constant 恒定） | — |
| reset 行为 | 复位→PN 回 PN_INIT；key 复位清 reg 但 a_esk 输入不变 | aes_encrypt:112, wrapper:359 |
| plaintext release rule | 解密后即输出，无认证门 | macsec_rx_wrapper:795 + fpga_core:956 |
| error/drop rule | 仅长度<MIN(24B) 丢；非认证 | macsec_tag_strip:257-261 |

## 2. IV/nonce 构造（证据）

- TX：`iv_reg <= {ssci, tx_pn, 32'h5C5C5C5C}`（macsec_aes_encrypt.v:139）；restart：`{ssci, tx_pn+1, ...}`（:180）。
- RX：`iv_reg <= {ssci, rx_pn, 0x5C5C5C5C}`（macsec_aes_decrypt.v:141），rx_pn 取自帧尾 `tag_fifo_dout[159:128]`（macsec_rx_wrapper.v:739）。
- 96-bit nonce，非 96-bit 独立 IV；SSCI+PN 拼常数。

## 3. Nonce 唯一性 — **BLOCKER**

- **同 key**：TX/RX 用同一 `MACSEC_AES_KEY`。MACsec 惯例 TX/RX 用独立 key（互为不同方向）;这里同 **key**。
- **SSCI 相同网段**：局域网多 FPGA 默认同 `SSCI_BASE=0x12345678` + `n`，无独立唯一分配 → 两个 node 的同 port 可能同 (key,SSCI)。
- **复位回退**：`mac_rst` / `hls_rst` 令 `tx_pn→PN_INIT(1)`（aes_encrypt:112；wrapper:359）、RX `rx_pn` 由输入 tag 定（但发起方 TX reset 回 1）。→ **同 key 重启后 PN 从头** ⇒ nonce 复用。
- **无 wrap fail-close**，无 drop 消耗后持久化，无 retry 保护。

### 审计表
| Direction | Endpoint | SA | KeyID | SSCI | PN 范围 | Reset | 唯一性 |
|---|---|---|---|---|---|---|---|
| TX port0 | FPGA | (无) | 0x0011..FF | 0x12345678. | roll over | 回 PN_INIT=1 | ✗ 复位复用 |
| RX port0  | FPGA | (无) | 0x0011..FF | 0x12345678. | 帧内 PN | — | ✗ 同 key 复用 |
| TX/RX port1 | FPGA | (无) | 0x0011..FF | 0x12345679. | | 回 1 | ✗ |
| peer（可能） | 第二台 | — | 相同 | 相同 | — | — | ✗ 无跨节点唯一 |

**分类**: `NONCE_REUSE_STRUCTURAL_RISK`（已 structured 论证，未见 runtime 证据 → 比 conditional 更严峻；按任务 double-vous 确认同 key、复位回退 ⇒ 上升为**structural risk/possible reuse**）。

## 4. SA/Key 生命周期 — **GAP / NOT_IMPLEMENTED**

- key 硬接 localparam 端口，**明文寄存器**（key_reg）与互联；无 zeroization（reset 只清 reg，`aes_key` 输入端常量不变，仍有效）。
- 无 key activation/retirement/generation；无 DSA active/inactive。
- 无 key 切换原子性；cached-SA 未来方案存在 **H/Y 表与 key 错配、bank 提前切换** 的架构风险（本任务仅记录 RDF 需求，不实现）。

## 5. Auth-before-release — **BLOCKER**

- `macsec_rx_wrapper` `OUT_DEC` 状态把 `dec_payload_tdata` 直接输出（macsec_rx_wrapper.v:795-813），输出与 `computed_icv` 无关。
- `macsec_tag_strip` `ST_CAPTURE` 到帧尾（len≥24）→ `ST_OUTPUT`（输出 payload），`ST_WAITTAG`/`ST_DRAIN` 仅为空转完成，**无 tag 认证比较**；`ST_DROP` 仅在 **len<MIN_FRAME**（macsec_tag_strip.v:257），非 tag 错。
- `fpga_core`：`received_icv=128'd0; icv_check_enable=1'b0`（fpga_core.v:956-957）。**计算所得 tag 从不与实际 tag 比较便放行明文**。
- **结论：tag 错误 / AAD 错 / cipher 位翻转 ⇒ RX 仍输出明文（0 beat 释放未实现）。→ `AUTHENTICATION_BEFORE_RELEASE_VIOLATION`。**

## 6. Replay protection — **NOT_IMPLEMENTED**

- 无 lowest Acceptable PN / replay window / dup drop / old drop / out-of-order / window update / wrap。
- **分类 `REPLAY_PROTECTION_NOT_IMPLEMENTED`**。tag 正确不构成 MACsec 闭环。

## 7. Frame/context 绑定 — **GAP**

- 完成事件（`tag_meta_hs`、`ap_done`）不携带 `{SA,AN,PN,generation}`；单帧在途、串行的设计下同帧内自洽，但：
  - 无 `generation` 计数；
  - PN 由多 reg（`tx_pn`/`pn_sideband_reg`/`tag_fifo`）合成，未证明与完成事件同帧绑定；
  - TB 从不在完成前主动送下一帧；非法提前 reentry 是否被硬件阻止**未证明**。
- **分类 `NOT_IMPLEMENTED`（绑定）**。

## 8. Fail-closed — **GAP**

- 默认对坏 frame：（auth 失败不丢）+仅在长度错时丢（`MIN_FRAME=24`）。
- `enable` 可控 bypass：`PROTECT_ENABLE=1`，但 `enable` 端口亦可 0 ⇒ plaintext 旁路；是否软件显式授权**无证据**。
- key invalid / timeout / cache 超时 / HLS no-response 无 fail-close。
- **分类 `GAP`**。

## 9. Key 处理与 zeroization — **GAP**

- 明文 key 在 RTL 端口/reg；reset 清 reg 非 dynamic KZ；顶层 localparam 恒有密钥 ⇒ 每次 reconfig/herproach 固定明文 key。无 key 生命周期（zeroize on SA off）。
- **分类 `GAP`**（不是 BLOCKER，但不可达 to production closure）。

## 10. Observability — **GAP**

- 存在 `perf_*`/`dbg` 计数器 / `bad_or_last` signals / live 统计，但**不是**逐事件 `{direction,frame_seq,SA,AN,PN,generation,error}`；多错误共用 req/bit（无 auth-pass/fail/replay/no-SA/PN-exhausted/key-invalid/buffer-overflow/reset/timeout 的独立记录）。
- 集成 TB `_check_stage` 只用计数，不盘点。

## 11. 标准合规 — **NOT_IMPLEMENTED（完整 802.1AE）**

- 私有 96-bit IV `{SSCI,PN,0x5C..}`、私有 AAD、无 replay、无 SA management → **不可称完整 IEEE 802.1AE**。**明确标记为自定义格式（bring-up/mock MACsec）**。

## 12. 安全 BLOCKER 汇总

| # | Blocker | 证据 |
|---|---|---|
| B1 | nonce 唯一性：同 key TX/RX + 复位 PN 回退 + 不唯一 SSCI | fpga_core:717-719,723; aes_encrypt:112,139; wrapper |
| B2 | auth-before-release：RX 无 tone 认证即释放明文 | fpga_core:956-957; rx_wrapper:795; tag_strip |
| B3 | replay protection 缺失（若产品要求完整 MACsec） | tag_queries |
| B4 | 集成 oracle 非独立 + production 参数未测（verification） | §1 本系统 |

## 13. 最小闭环工作（授权 | 重构前）

1. RX auth gate（`icv_check_enable=1` + `received_icv` 比较，认证 fail 释放 0 beat）。
2. TX/RX **拆分 key**（各自 direction key）或唯一 SSCI 分配；**PN 不因 reset 回退**（非挥发生/保持），wrap fail-close。
3. Replay window（lowestPN/dup/old/out-of-order）。
4. SA 生命周期（SA要、active/retired、key 原子切换、zeroization、generation）。
5. 完成/事件绑定 `{SA,AN,PN,generation}`。
6. 集成层独立 oracle（Python/OpenSSL/NIST）+ negative 矩阵 + backpressure/reset/post-synth。

## 14. 最终安全分类

```
主分类: VITIS_MACSEC_SECURITY_BLOCKER_FOUND
（另) VITIS_MACSEC_SECURITY_EVIDENCE_INCOMPLETE 叠加）
```

子分类:
| sub | 判定 |
|---|---|
| nonce_uniqueness | BLOCKER |
| sa_lifecycle | NOT_IMPLEMENTED |
| frame_context_binding | NOT_IMPLEMENTED |
| authentication_before_release | BLOCKER |
| replay_protection | NOT_IMPLEMENTED |
| fail_closed | GAP |
| key_handling | GAP |
| reset_security | BLOCKER |
| observability | GAP |
| standard_compliance | NOT_IMPLEMENTED |

## 15. 独立实验行为确认（E1/E2，只读临时目录）

本会话执行了两个最高价值独立实验（测试码放 `<experiment-dir>/`，production 零改动），行为层确认了上述两个 BLOCKER：

- **E1 — 认证前释放**（production `macsec_tag_strip.v` + `xpm_fifo_sync_sim.v`）：FSM `CAPTURE→OUTPUT→DRAIN→WAITTAG`；对 corrupt tag(0xDEAD..) 帧 **从未进入 ST_DROP**，`m_tag` 输出 corrupt 值。静态确认全 FSM 无 tag 比较，唯一丢帧路径是 `长度<MIN_FRAME(24)`（macsec_tag_strip.v:257）。⇒ 认证失败帧仍放行。
- **E2 — reset 使 PN 回退**：production `macsec_aes_encrypt.v`（仅 stub `hls_aes128gcm_enc` 为 `ap_start→4cyc→ap_done`）：frame1 `tx_pn 1→6`；`hls_rst` → **`tx_pn=1`**；frame2 同 key 从 `tx_pn=1` 重启 ⇒ **(key,PN) 非重实例复用**，IV nonce 结构 `{ssci,pn,0x5C..}` 复用被行为确认。

这两项使 `NONCE_REUSE_STRUCTURAL_RISK` 与 `AUTHENTICATION_BEFORE_RELEASE_VIOLATION` 均从静态推断**升级为行为证据支持**。

---
*只读审计，无 production 改动；E1/E2 仅测试代码在 /tmp，未写入工程。*