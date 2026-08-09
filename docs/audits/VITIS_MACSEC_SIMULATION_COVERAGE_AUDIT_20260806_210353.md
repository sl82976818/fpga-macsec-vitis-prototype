> **Publication note:** This is a publication-sanitized copy of the original read-only
> engineering audit. Technical conclusions have not been altered. Host-specific
> absolute paths have been normalized to `<project-root>` / `<toolchain-root>`
> / `<experiment-dir>`. Original timestamps and classifications are preserved.

# Vitis Security Library AES-128-GCM MACsec — 仿真覆盖与安全闭环审计

**任务类型**: VITIS_MACSEC_SIMULATION_COVERAGE_AND_SECURITY_CLOSURE_AUDIT
**审计日期**: 2026-08-06 | **工程**: `mqnic_gcm_codex-2-v2-2.75gbps/mqnic_gcm_codex-2`
**FPGA**: xcku040-ffva1156-2-e | **工具链**: Vivado / Vivado HLS 2022.1 | **方法**: 只读审计（未修改任何 production RTL/HLS/XCI/约束/日志）

> 依据任务约束：不默认功能/安全正确；未修改 production；所有不足证据均显式标注 UNKNOWN / NOT_TESTED / NOT_IMPLEMENTED / EVIDENCE_INSUFFICIENT。

---

## 1. 仿真覆盖审计

### 1.1 身份冻结（identity freeze）

| 项 | 值 | 备注 |
|---|---|---|
| 工程根目录 | `mqnic_gcm_codex-2-v2-2.75gbps/mqnic_gcm_codex-2` | 无 git（非 repo），版本标识仅目录名/zip（`-tested@2.7gbps`） |
| HLS 源 git | `mqnic_pciex8-AES-fromVitisLib` commit `415a95a`（fix(macsec) Cipher path deadlock） | 关联到源 |
| production top | `fpga`（fpga_k35 → fpga_core） | netlist top= fpga |
| TX/RX MACsec top | `macsec_tx_wrapper` / `macsec_rx_wrapper`（imports/rtl） | |
| encrypt/decrypt IP | `ip/aes128gcm_enc|dec`（Vivado HLS 2022.1, xcku040, HLS_CLOCK 6.4ns） | |
| HLS 源（C） | `hls_source/aes128{enc,dec}/test.{cpp,hpp}` + `xf_security/gcm.hpp/gmac.hpp/aes.hpp` | |
| production fpga_core.v | md5 `25e77892f964d814bd4e391bea7c0570` | 被审计对象 |
| TX wrapper | md5 `389d9f1eceab2fcf9bebeb8415ccec1b32` | |
| RX wrapper | md5 `913b0ee4 78010688bc977a9c39d9ed135` | |
| aes_encrypt/decrypt | md5 `e670f019298d47f1e54193920e6f660` / `688eff24a43a704eaac292e1a25092c6` | |
| TB | md5 `c7dca3a4ef8508f84f499066d5ffe7bd`（tb/fpga_core/test_fpga_core_macsec_sfp.py） | cocotb，单 `@cocotb.test()` |
| Kintex | xcku040-ffva1156-2-e | Routed timing WNS −0.206ns（未 met） |

**身份唯一性判定**:
- 仿真编译的 RTL = production `imports/fpga_25g/rtl + lib` + `imports/rtl/*.v`（macsec wrappers）+ HLS RTL。
- HLS IP 的仿真 RTL（`tb_local/fpga_core/hls_models/enc|dec`）与 production `ip/aes128gcm_enc|dec/hdl/verilog` **逐对一一对应**，唯一差异是**模块名前缀** `test_enc_/test_dec_` 与 `.dat/.vh` 文件前缀（为 enc+dec 连带编译去冲突）；去前缀后逐文件 **IDENTICAL**（已用 `sed` 去前缀 `diff` 验证多个文件）。 **未 mock/replace 任何 production HLS 模块**。
- 仿真默认参数（`IF_COUNT=2, EQN_WIDTH=6, TX_QUEUE_INDEX_WIDTH=13, RAM_PIPELINE=...`）与 production 默认 `fpga_k35` 的 `IF_COUNT=1, EQN_WIDTH=5, TX_QUEUE_INDEX_WIDTH=11` 等 **不一致** → 见 1.3 风险。

**判定**: `VITIS_MACSEC_VERIFICATION_IDENTITY_INCOMPLETE` 的风险**未触发**（RTL faithful ），但因 **参数非 production 实配 + 无板级 iperf 原始证据**，不能冻结到“正是 2.7/2.75Gb/s 功能版本”这一层；标识具体 `2.7G` 数字的证据缺失。

### 1.2 验证资产盘点

| 资产 | 层级 | DUT 范围 | oracle | 自动判定 | 最近结果 | production 配置? |
|---|---|---|---|---|---|---|
| HLS C-sim (main.cpp) | HLS | test() GCM 核 | OpenSSL golden(gld.dat) | C 比对（return nerror） | **PASS: 300 vectors** | —（ip 内部单元，非集成） |
| HLS RTL cosim (xsim) | HLS RTL | test() RTL | 同 gld.dat | PASS | **PASS (Verilog) 45200 cyc** | — |
| cocotb full fpga_core `run_test_nic` | 集成 | fpga_core 全 TC MACsec 全链 | 仅 loopback 自洽（见 1.4） | 帧数/end 相等 + 部分 payload 回环等值 | **间歇（NOT 可信）**：sim_build XML 统计 full-length 运行 FAIL(04-24×1/04-28×5/04-29×1) 与 PASS(04-28×4/04-30×3) 并存；`lastfailed=true` | **否**（参数不一致） |
| `macsec_tx_header` / `macsec_loopback` unit TB | wrapper 级 | 部分 | 自玩 | 2 passed | PASS（Gate1）— 历史（symlink 已断，源不存在） | 参考 |
| SystemVerilog assertions | 无 | — | — | — | 无 | — |
| scoreboard | axis 级 | 无独立 | — | — | 无 | — |
| Python/OpenSSL golden model（集成层） | 无 | — | — | — | 无 | — |
| NIST AES-GCM 向量 | 无独立引用（HLS 用 OpenSSL 生成 golden） | — | — | — | — |
| MACsec 包向量（外部加密帧注入） | 无 | — | — | — | — |
| post-synthesis / routed / SDF 仿真 | 无 | — | — | — | 无 | — |
| board/网络 loopback | 部分 | 板卡 | — | — | wireshark 捕获显示 **peer ARP/Pv mdns Malformed**（见 debug过程.md） | 非净（2.7G 无线速证据，仅 malformed 捕获） |
| regression runner | test.sh + pytest | — | — | — | 单个测试 | — |
| coverage reports | 无（无 coverage DB） | — | — | — | 无 | — |
| waveform / .dbg | 有（live/dbg 日志） | — | — | — | 有 | — |

**关键点**：
- 仅有 **一个** `@cocotb.test()`（`run_test_nic`）；`.pytest_cache/lastfailed` 记录最近一次 **true (failed)**（该 cache mtime=04-24 16:32）。
- **新增实证（sim_build/test_fpga_core/*_results.xml，04-24 至 04-30）**：计数 **PASS=44 次、FAIL=23 次**；其中 **full-length 全程运行（wall≥1000s）** 出现 **间歇性失败**——
  - FAIL: 04-24(1) / **04-28(5)** / 04-29(1)；
  - PASS: 04-28(4) / **04-30(3)**。
  即同一 DUT 同一 TB 在 04-28 同日存在 5×FAIL 与 4×PASS 并存。**结论：集成分层 cocotb 集成测试当前为"间歇性通过/失败（flaky）"而非确定性 PASS**。因此 GATE/R 文档所述 "1 passed" 仅是众多运行之一，不能代表回归可信度；`lastfailed=true` 是**真实且一致的失败记录**，不应轻视为过滤伪象。
- 该间歇性失败从根本上削弱集成层负熵：即便"计帧数相等"校验也并非每次满足，说明 DUT 或 TB/环境存在未收敛的不确定性。
- 没有负向 `auth` / replay / reset / backpressure / 随机 tvalid-tready / post-synth 的任何测试资产。

### 1.3 假 PASS 风险（runner）

| runner | 主体检测 | 假 PASS 风险 |
|---|---|---|
| HLS C-sim / cosim | 返回码 + `PASS: 300` 计数 | 低（硬比对，且 push OpenSSL golden） |
| cocotb `run_test_nic` | 帧计数相等 + loopback payload 回环 | **高**，见下表 |
| cocotb 无 `execute` 级 FAIL | — | cocotb 抛异常亦会导致 pytest 失败；**基本可靠**，但下方几点构成**功能假 PASS** |

具体功能级假 PASS（非脚本空转，而是“测了什么”的局限）：
- `_check_stage(strict)` 仅比较 `tx_in==tx_out`、`rx_in==rx_out±rx_pause`、`tx_out<=tx_in`、lag 上限。**不校验 payload 内容、不校验 tag 认证、不校验密文质量**。计数相等可能是“把坏帧原样转发”，亦会 PASS。
- 同行 **loopback 自玩**：`run_loopback` 把 `sfp_sink → sfp_source` 反射（`macsec_rx` 输出的帧直接喂回 `macsec_tx`）。这使 TX 和 RX **永远同键同一实现在自洽**，掩盖：
  - 密文/tag 错误在 TX 与 RX 中是“同错同对”，回环相等 ⇒ 假阳性；
  - RX 解密输入就是 TX 输出的 ciphertext，无法证明加密增量与 NIST/OpenSSL 一致（HLS 核 C-sim 已证 core 数学正确，但那只是 core，不是 wrapper 的 IV/AAD 组装）。
- 未注入外部生成/损坏的 MACsec 帧（独立 oracle / negative 缺失）。
- **无 PN 换 key、双端点、重置、非阻塞 backpressure 的专项验证**。
- 只有单 key、单 SSCI、固定 IV（`{SSCI,PN,0x5C5C5C5C}`）、固定 AAD（`{80'd0,16'h0001,SSCI}`）。

**标志：假 PASS（功能层）高，脚本层不高。

### 1.4 oracle 独立性

- 当前集成级 scoreboard 依赖 **DUT 内部计数与 loopback 同源**，**没有独立参考**：
  - 不读取 DUT 内部 / `will_pass` / 内部 tag —— 这点是**满足**（无 lever read internal tag 做 golden）。
  - 也不调用与 DUT 相同的 Vitis `gcm.hpp` 作参考在集成级。
- HLS C-sim 的 oracle 是 **独立的**：OpenSSL EVP AES-128-GCM 生成 gld.dat，比对 ciphertext+tag（300 len 0..255，AAD=5）。**这是全审计中唯一真正的独立 oracle**。
- 集成级没有任何利用 Python `cryptography`/PyCryptodome/OpenSSL/NIST KAT 独立计算 tag / ciphertext / auth 判定。

**判定**: 集成级 worse: 回环非独立（self）. HLS 核内（C-sim）**有独立 oracle**，但**集成（wrapper+frame）层面 oracle 缺失**。全链路由最弱，按任务要求把集成层 classify 为 `COMMON_MODE_ORACLE_RISK`（虽然不存在“共享同一份 gcm.hpp 作为唯一参考”——而是“**imagené，连参考都没有**”，这比 logo 更弱）。标记 `VITIS_MACSEC_TEST_ORACLE_NOT_INDEPENDENT`。

### 1.5 基础 AES-GCM 覆盖（§五）

| case | 现有证据 | 状态 |
|---|---|---|
| all-zero / all-ones key | factory | NOT_TESTED（C-sim 仅单个字母 key） |
| random key | N/A | NOT_TESTED |
| 96-bit IV | C-sim IV=const12B | 仅一个恒定 IV |
| 不同 PN/IV `(SSCI,PN,0x5C..)` | 集成 loopback 隐含，未独立验证 | NOT_TESTED（IV 全来自 wrapper 自组装） |
| AAD 长度 0 / 1..15 /16 /17..31 / MACsec实际(48bit) | C-sim AAD=5；集成 AAD=48bit 固定 | AAD 变化 NOT_TESTED |
| payload 0 / 1..15B /16 /17 /32 /多block /max | C-sim 0..255；集成多种帧长 | 覆盖（C-sim 有；集成 payload=0 无） |
| partial final block带 tkeep | C-sim 有 partial；**集成 loopback 隐含** | PARTIALLY_TESTED |
| tag 正确 | C-sim/loopback (同错同向) | ring |
| tag 单bit错→须drop | **无**（RX 不鉴权） | NOT_TESTED + NOT_IMPLEMENTED |
| ciphertext 单bit错→解密失败 | 无 | NOT_TESTED |
| AAD 错 | 无 | NOT_TESTED |
| IV 错 | 无 | NOT_TESTED |
| key 错 | 无（固定固定 key） | NOT_TESTED |
| 尾块 mask / length block / endian | C-sim 内部已证（core），wrapper 组装未独 litigated | PARTIALLY（core） |
| encrypt/decrypt 互逆 | loopback 回环 host 载荷复用收盘 | YES（自洽） |
| decrypt 失败即 PASS 不处理 | 现 RX 不判 FAIL | **AUTH GAP** |

### 1.6 MACsec 帧格式覆盖（§六）

集成 TB 覆盖的帧长：**42（ARP_MIX）、约 60/64（ARP/small）、65..~128+（arp/mdns/steady 大小包≥）、1518 级（large_pkts）、1522 VLAN（浅覆盖？）**；未见明确 runt/oversize/超 1518 专项。| 状态 |
|---|---|
| 42/46/60/64 | 部分（ARP_MIX/小包） | PARTIAL |
| 65/127/128/129 | mdns+ 65 左右 | PARTIAL |
| 255/256/257 …1024 | 可能覆盖 | NOT_PROVEN |
| 1518 | large_pkts 有 294 帧 | PROVEN（帧数，非认证） |
| 1522 VLAN | 未专项 | NOT_TESTED |
| runt/oversize | 未专项（tag_strip MIN 24 逻辑存在，仅 24B 下限） | NOT_TESTED |
| tag跨 64-bit beat / block | re-flat loopback 隐含 | NOT_TESTED (集成) |
| packet 最后1–15 B | loopback 隐含 | NOT_TESTED |
| SecTAG/payload 边界跨 beat | 隐含 | NOT_TESTED |
| VLAN present/absent | 未专项 | NOT_TESTED |
| bcast/mcast/ucast | 有（Ether bcast/ucast + mdns mcast） | YES |
| EtherType 变化 | 覆盖 | YES |
| SCI present/absent | 未专项 | NOT_TESTED |
| AN 各值 | 未专项 | NOT_TESTED |
| CONFIDENTIALITY_OFFSET | 不支持 | N/A |
| plaintext/受保护/错误帧 | 只测受保护；错误的**不会 drop** | GAP |

**多安全头：** 本工程用**固定非标准 header 布局**：
- 仅保留 L2 header(DA/SA/Type14) 明文；wire EtherType 固定 `0x88E5`；
- 加 SecTAG（6）=SCI+PN 压缩为 `{SSCI(32),PN(32),0x5C5C5C5C}` 于 IV、并在尾部附 ICV 16B + tag append；
- **不是 802.1AE long/SSCI 完整标准布局**。**必须作为：仅内部私有帧格式，不可称为完整 IEEE 802.1AE 兼容**（任务 §六结尾要求明确标记）。

### 1.7 连续帧 / 上下文绑定（§七）

- 现有 TB：**长连续多帧**（steady/small/arp_mix 已 294+ 帧）**通过帧数一致性**；但**每个结果未绑定**事务标识 `{direction,frame_seq,slot/SA,AN,PN,generation}`。无 per-frame 绑定 scoreboard。
- 设计结构（wrapper）单帧在途，串行 store-and-forward；`tag_append` 等 tag 完成才输出，`PC` 递增在 `tag_meta_hs`（ST_WAITTAG 完成后下一帧相关）。
- 现阶段**无 multi-SA/多 key 连续**、无**错误/正确交错、无 RX-drop 后立即合法、无并发 TX+RX stress、无 backpressure / 随机 tvalid-tready 打断、无 FIFO 边界**，因此**上下文绑定未被证明**。`UNKNOWN`/`NOT_TESTED`。

### 1.8 Reset / CDC（§八）

- 测试仅做初使能复位（reset 0→1→0 一次），**无 warm/crypto-only/wrapper-only/MAC-only/HLS-only 复位**；无 reset期间 AAD/payload/tag/release prior。无：复位后第一帧、复位后 PN/key/H 有效性、复位后旧 tag/frame 释放。
- **PN 在 `macsec_aes_encrypt` 复位时回 `PN_INIT=1`；wrapper `pn_sideband_reg` 复位回 `PN_INIT`** → **复位可导致同 key 下 PN 回退 = nonce 复用风险**（见 security）。
- CDC：wrapper 用 `xpm_async`（CDC_SYNC_STAGES=2, `xpm_fifo_async`）跨 MAC→HLS；但测试未验证跨域 pulse、复位同步、`CDC 约束`. 未 library 检查。
- `assign axis_eth_rx_tuser = {WIDTH{0}}`：原始 rx tuser（bad-state/FCS）被清零 —— **可能掩盖 bad-frame 标记；** subset 中 `debug过程.md` 亦点名。

### 1.9 post-synthesis / 实现一致性（1.0）

- 无 post-synth / post-route / SDF 仿真；无门级。
- routed RTL：`Timing constraints are not met`（WNS −0.206ns）。
- **QG `POST_ROUTE_SECURITY_BEHAVIOR_UNPROVEN`**。

### 1.10 未覆盖清单（仿真）

1. 独立 oracle（Python/OpenSSL）在集成层生成 tag/ciphertext；
2. negative: tag 单bit错 / cipher丢位 / AAD bit位错 / IV 错 / key err；
3. replay：dup PN / old PN / out-of-order / window；
4. reset 矩阵（各阶段复位、复位后首帧、PN 行为）；
5. PN wrap / 接近 wrap / drop 消耗 / retry 复用；
6. backpressure（随机 tvalid/tready、tag 通道暂停、FIFO 边界）；
7. SA 生命周期：多 key、双 SSCI、active/inactive、key 切换原子性、零消除；
8. auth-before-release 的明文零拍验证；
9. FIFO/drop/error 计数器读取与断言（虽有 *_bad_or_last 计数但未作为判定）；
10. post-synth/routed 仿真；
11. 外部 MACsec（独立软件/eth 双端）互操作 clean。

### 1.11 仿真覆盖最终分类

**判定：** `VITIS_MACSEC_SIMULATION_COVERAGE_MINIMAL`（集成层）——虽然 HLS 核内 C-sim 300 向量 PASS 且具备独立 oracle，但**集成级 oracle 缺失、negative/reset/nonce/replay/backpressure/post-synth 全缺、production 参数未测**。按 §十九同时标注：
- `VITIS_MACSEC_TEST_ORACLE_NOT_INDEPENDENT`（集成层）
- `VITIS_MACSEC_PRODUCTION_CONFIGURATION_NOT_TESTED`（参数与 production 不一致）
- **不属于 `COMPLETE`**。

---
## 2. 安全合同与闭环

### 2.1 实际实现的安全合同（§十一，以 RTL 证据为准）

| 项 | 当前实际实现 | 证据 |
|---|---|---|
| key identity | 单全局 key `MACSEC_AES_KEY=0x00112233445566778899AABBCCDDEEFF`，TX 和 RX 同用一个 | fpga_core localparam |
| SA identity | 虚拟 SA（无 SA 表、无 active/inactive、无 generation counter） | 无 SA param/logic |
| SSCI | `MACSEC_SSCI_BASE + n`（每个 port +1） | fpga_core:801 |
| AN | 无（IV 用 `0x5C5C5C5C`，即 2 个 AN 常数） | aes_encrypt.v:139/180, dec v:141 |
| IV/nonce | `IV = {SSCI(32), PN(32), 32'h5C5C5C5C}`（96bit） | aes_encrypt.v:139 |
| AAD | `AAD = {80'h0, 16'h0001, SSCI(32)}`，len=48bit | aes_encrypt.v:140 |
| ciphertext bytes | L2 header(14B) 明文 + 其余密文；EtherType 固定 0x88E5 | tx wrapper |
| ICV length | 16B (tag)，尾附；RX 接收 strip 但**不校验** | tag_strip/tag闲 |
| replay rule | **无** | 见 doc |
| key activation / retirement | 无 | 无 |
| reset 行为 | 复位 → PN 回 PN_INIT；key 重新载入（同 KEY） | aes_{enc,dec} |
| plaintext release rule (RX) | **计算后即输出，tag 不落断；`icv_check_enable=0`** | macsec_rx_wrapper:795 + fpga_core:956-957 |
| error/drop rule | 仅按帧长 `MIN_FRAME_BYTES(24)` 丢弃，**不以认证/PN 丢弃** | macsec_tag_strip |

### 2.2 Nonce 唯一性（§十二）— **硬门**

`IV = {SSCI, PN, 0x5C5C5C5C}`，同一 key 绑定同一 SSCI/PN 才唯一。问题：

- **TX 与 RX 使用同一个 key `MACSEC_AES_KEY`**（同一 `0x0011…FF`）。RX 的 PN 取自 incoming tag 里的 PN，TX 的 PN 是本地计数。**没逻辑保证两台机的 TX-PN ≠ RX-PN / 相邻机 PN 不重复**；仅靠**不同 SSCI（本机 port0=0x12345678; peer 可能相同）**——若供应商无独特的 SSCI，`(key,SSCI,PN)` 可重复。
- **复位 ⇒ `mac_rst`/`hls_rst` 令 `tx_pn`（aes_encrypt）与 `pn_sideband_reg`（wrapper）均回 `PN_INIT`**。同一次 CR（重启/重新加载同 key）PN 回到起始 ⇒ **同 key 下 PN 回退 = (key, nonce) 复用**。→ **RESET** 条件命中。
- **PN 由硬件自计数**，drop 帧刷新（`tag_meta_hs`）即为“消耗”，但**retry/重载同 key 无持久化**；四次重启回到 IRA=1。
- **无 PN wrap 抑制**；无 wrap 后 fail-close；二进制结构允许 wrap。
- **多 worker / socket 未实现 PN 仲裁**（未来 slot 有风险）。

**minor unique 结论**：`NONCE_REUSE_STRUCTURAL_RISK`（有论证的复用通道，非单纯“未验证”）：
- key 同源 + 复位回始 + 无独立 SSCI 唯一性 ⇒ **在实际配置下不能证明 (key, IV) 唯一**。
- 不达 `PROVEN`，也不够最终分配正确 `CONDITIONAL`。

### 2.3 关键生命周期（§十三）

- key 通过 **硬件端口** dra 接 localparam，**明文存 FF/interconnect，无 key_reg 之外的 storage 与 zeroization**（reset 清 `key_reg=128'd0`，但 `aes_key` 输入端 `/constant` 不变）。
- 无 active/inactive SA；无 DSA；无 key 切换原子性；无 generation；无旧帧重放绑定。旧/新键混用通道 a：可 create 分支，行为 NEWT。
- key BLN 状态恢复后**仍同 key**（Localparam 不变）⇒ reset 后 key 有效，但 PN 回 1 ⇒ **非零唯一风险**（2.2）。

### 2.4 认证后释放（§十四）— **BLOCKER**

- RX 解密后把 plaintext 写入 `plain_fifo` 并**立即使 `m_axis_tvalid` 输出**（`macsec_rx_wrapper` OUT_DEC 状态直接 `dec_payload_tdata`→`m_axis_tdata`，见 macsec_rx_wrapper.v:795-813）。
- `computed_icv`/`icv_valid` 仅作为**输出**（交给 `fpga_core` ），而 `fpga_core.v:956-957` 把 `received_icv=128'd0`、`icv_check_enable=1'b0`。
- **macsec_tag_strip** 在 `ST_CAPTURE` 结束、长度≥ 24 即 `m_tag_valid=1`, `ST_OUTPUT` 输出 plaintext；**ST_DROP 仅当 length<24B**（即纯 runt），**绝非 tag 认证失败丢弃**。
- 因此 **auth 失败（tag 错、AAD 错、cipher 位翻转）仍会输出全量计算后的 plaintext**（GCM 解密对错 data 也得 outputs 密文变换）。

**判定：`AUTHENTICATION_BEFORE_RELEASE_VIOLATION`（BLOCKER）**——不对称 tag 无法阻断明文释放。

### 2.5 Replay protection（§十五）

- `macsec_tag_strip` 无 lowest PN / window / dup / old / wrap；**未实现 replay protection**。
- 判定：`REPLAY_PROTECTION_NOT_IMPLEMENTED`（非“无法证”，是**真没有**）。

### 2.6 Frame/→context 绑定（§7+）

- wrapper 单帧在途 + 串行，逻辑上**单帧无跨帧复用**（在**同一帧**内不发生上下文串）。但
- completion 事件不携带 `{SA,AN,PN,generation}` 的 end-to-end 唯一；**tag/completion 一对多帧边信号来自实际尝试 `tag_meta_hs`，与下一帧 `pc` 若验证于同拍将可能交织**，源码未见 reg（如 `tag` 可能在第 N 帧 end? 而在第 N+1 帧 meta）。未见显式完成事件绑定。
- 因此 `NOT_IMPLEMENTED`（完整身份绑定）。在同 SA 单流下自洽（loopback pass），但 **非法提前重入阻止** 未证明（TB 不主动送下一帧，架构层面未必阻塞）。

### 2.7 Fail-closed / 可观测性（§16/17）

- 默认**不透传明文**，但**错则释放任意/计算出？(见 2.4)**；`crypto_enable=0` 时 RX/TX 走 bypass（隐含明文旁路）**，若软件显式授权？**（`PROTECT_ENABLE`=1 但 `enable` 总线也可 0 → bypass）。此行 fail-open 依赖 software 显式 settings——**证据不足**。
- 具备 `perf_*`/`dbg` 计数器 / bad_or_last 索引（debug 帧计数），**但**：
- 无区分事件（auth pass/fail、replay、no-SA、PN exhausted、key invalid、buffer overflow）的单型效果 identifier；事件不是 `{direction,frame_seq,SA,AN,PN,generation,error} `。
- 无 key invalid / timeouts / HLS no-response / config-in-flight 处理。**observability gap**。
- tag 非：**auth 失败 frame 不放行**（无 count rule），drop 只能 length rule。

### 2.8 Standard compliance（§20）。

- 内部格式固定，**不是完整 802.1AE**（无 SA 管理、无 replay window、无 XE、纯私有 IV/AAD 构造）；对分 2 号 L2 header 明文 + IV/ANI private。
- **判定：`GAP` / `NOT_IMPLEMENTED`（标准 compliance）**，因工程采用自定义头/IV，不能自称 IEEE 802.1AE 完整。

### 2.9 安全事件分类汇总（subsection）

| subcategory | 判定 |
|---|---|
| nonce_uniqueness | `BLOCKER`（| 复位回 PN + 同 key TX/RX 共用 → 具架构非唯一复用通道） |
| sa_lifecycle | `NOT_IMPLEMENTED` |
| frame_context_binding | `NOT_IMPLEMENTED`（无 generation 绑定；单帧本地内尚可，复核 fin） |
| authentication_before_release | `BLOCKER`（icv_check=0，RX 无认证即输出） |
| replay_protection | `NOT_IMPLEMENTED` |
| fail_closed_behavior | `GAP`（长度错才丢；非认证引导 drop 缺失；错误暴露密码） |
| key_handling | `GAP`（明文寄存器、无 zeroization/atomic switch /generation） |
| reset_security | `BLOCKER`（复位回 PN1 且 key 重载 → 同 key 下 nonce 复用） |
| observability | `GAP`（无事件指纹/PN、混杂计数） |
| standard_compliance | `NOT_IMPLEMENTED`（私有 IV/AAD/无 replay） |

### 2.10 安全闭环最终分类

**`VITIS_MACSEC_SECURITY_BLOCKER_FOUND`**（同时叠加 `VITIS_MACSEC_SECURITY_EVIDENCE_INCOMPLETE` 合法外延）。

（未满足 → 不等同 `PROVEN`/`CONDITIONAL`。）

---
## 3. 硬停止条件（§21，§23）

命中的硬停止条件：
1. **auth 失败仍释放明文** ⇒ `AUTHENTATION_BEFORE_RELEASE_VIOLATION`
2. **reset 导致相同 key 下 PN 回退**（`rx_aes`/wrapper 复位回 PN_INIT） ⇒ nonce 复用 risk/confirm
3. **nonce 唯一性结构性风险/可能复用**（同 key TX/RX + 可能同 SSCI 分） ⇒ BLOCKER
4. **replay protection 缺失**（产品若要求完整 MACsec ⇒ 硬）
5. **集成层 oracle 非独立**（依赖同 key 同实现自洽回环）
6. **production 参数未被测试**（IF_COUNT/Q_is 不一致）

**结论： SECURITY_OR_VERIFICATION_HARD_GATE。** 未授权开始任何 10G 架构重构（cached-SA / frame-slot / ping-pong）。

### 最小修复前置（授权重构前）

1. 加独立 oracle：在 TB 层用 Python `cryptography`/PyCryptodome/OpenSSL 对 **外部构造的 MACsec 帧** 做 autogen/decrypt 独立 tag+Cipher 比对；
2. RX 增加 **auth-before-release 硬门**（`icv_check_enable=1` + `received_icv` 实际比较，认证失败帧 **不释放 plaintext=0beat**）；
3. **replay protection**（lowestPN/window/dup/old drop）；
4. **nonce 固定点**：TX/RX 分 key（或独 SSCI 分段）+ PN/IV 不因 reset 回退（SRAM保持/加非 volatile），PN wrap fail-close；
5. key 生命周期：SA 表现、key zeroization、key 切换原子、generation 计数；
6. SA/context 完成事件带（SA,AN,PN,generation）；
7. 建立 production 参数一致性（或显式校准 TB params），并补 negative/backpressure/reset/post-synth 测试；
8. 修复 routed timing（WNS>0）后再做门级安全。

---

## 2. 独立实验（S1/S2 executed，只读临时目录）

任务要求的独立实验本会话已执行其中 **两个最高价值项**，均在生产文件**零改动**（测试码放 `<experiment-dir>/`）下完成：

### 2.1 E1 — 认证前释放（auth-before-release）

- DUT：production `macsec_tag_strip.v` + `xpm_fifo_sync_sim.v`（字节一致，未 mock/replace）。
- 静态：读取完整 FSM（386 行）。`ST_CAPTURE` 提交分支仅在 `frame_byte_count < MIN_FRAME_BYTES(24)` 时进 `ST_DROP`（macsec_tag_strip.v:257）；**全 FSM 无任何 tag/ICV 比较分支**。`m_tag/m_pn/m_ethertype` 只“抽出上报”，不参与放行判定。
- 行为（iverilog tb3）：对带 corrupt tag(0xDEAD..) 的帧，FSM 走 `CAPTURE→OUTPUT→DRAIN→WAITTAG`，`m_tag` 输出该 corrupt 值，**从未进入 ST_DROP** ⇒ 认证失败帧仍走放行路径。
- **结论：`AUTHENTICATION_BEFORE_RELEASE_VIOLATION` 被行为层确认**（配合顶层 `icv_check_enable=1'b0`、`received_icv=128'd0`）。最小闭环修复：先比较 tag 再放行（认证失败 0-beat）。

### 2.2 E2 — reset 使 PN 回退（nonce 复用）

- DUT：production `macsec_aes_encrypt.v`（仅替换 `hls_aes128gcm_enc` 为 5 行行为 stub：`ap_start→4 周期→ap_done` 脉冲；wrapper 自身状态机零改动）。
- 行为：frame1 期间 `tx_pn` 1→2→…→6；随后 `hls_rst=1` → **`tx_pn=1`（PN_INIT）**；释放 reset 后 frame2 又从 `tx_pn=1` 开始。
- **结论：同 key + reset ⇒ (key, PN) 非重实例重新出现 ⇒ 同一 IV nonce 结构复用（`{ssci, tx_pn, 0x5C5C5C5C}`）被行为确认**。修复：PN 不因 reset 回退（SRAM 保持/非挥发）、wrap fail-close、TX/RX 分 key 或独 SSCI。

### 2.3 未执行项（S3–S8 保留）

- 剩余 S3–S8（replay 行为、negative auth 矩阵、backpressure、随机 tvalid/tready、SA 切换原子、post-synth）在本会话**未跑**——因现有 sim_build XML 已证明集成回归非确定性（§1.2），再叠加 flaky 会污染实验证据；且集成分层需 ~25min/run。若需补齐，须在独立临时目录另建（仍不碰 production）。

---

（本报告由只读审计生成，未修改任何 RTL/HLS/XPR/XCI/DB；E1/E2 仅测试代码在 /tmp，未写入工程。）