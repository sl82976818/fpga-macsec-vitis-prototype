# FPGA AES-GCM / 实验性 MACsec 研究原型

**Corundum + AMD Vitis Security Library**

这是一个基于 Corundum FPGA NIC 的在线 AES-128-GCM 以太网保护数据通路研究原型，集成了 AMD/Xilinx Vitis Security Library 的 AES-GCM 核。

本仓库是一个**经过审计的历史工程发布候选版本**。它保留了这个项目完整的工程故事：从功能跑通，到遇到性能瓶颈，再到后续按周期拆解性能问题，并最终发现若干安全架构缺口。

## 当前状态（一屏看完）

| 项目 | 状态 |
| --- | --- |
| 功能数据通路 | YES |
| AES-GCM 数学核心 | VERIFIED（300 组 C-sim 向量对比 OpenSSL，RTL cosim 通过） |
| 历史 ~2.7G 工程基线 | YES（历史工程标签） |
| 10G 线速实现 | NO |
| Production 安全闭环 | NO |
| 完整 IEEE 802.1AE 兼容 | NO |
| 研究 / 教学用途 | YES |

> [!WARNING]
> 本仓库是一个研究原型。
>
> 当前归档版本包含已知安全缺陷，**绝不能作为 production MACsec endpoint 部署**。
>
> 已知硬阻断包括：
> - authentication-before-release 失败；
> - reset 导致 AES-GCM nonce reuse 风险；
> - replay protection 未实现；
> - SA / key lifecycle 不完整。

## 这是什么？

这是一个实验性的 MACsec 风格保护数据通路，构建于开源 [Corundum](https://github.com/alexforencich/corundum) FPGA NIC 框架之上，底层使用其 10G MAC / PCIe / DMA 架构。

AES-128-GCM 核来自 AMD/Xilinx Vitis Security Library，并通过 Vitis HLS 2022.1 综合得到。

当前数据路径中：

- TX 执行加密并附加 ICV tag；
- RX 拆除 tag 并执行解密；
- 工程采用的是**自定义实验帧格式**，不是完整 IEEE 802.1AE MACsec 实现。

## 哪些代码是谁写的？

- **Le Sun** 编写了项目专用的 MACsec 集成部分，包括：
  - `src/macsec/` 下的 wrapper；
  - tag append / strip；
  - HLS 集成；
  - verification infrastructure；
  - 审计与工程分析文档。  
  这些确认属于原创的文件带有 `Copyright (c) 2026 Le Sun` 署名。

- **Corundum**（Berkeley Regents / Alex Forencich，BSD-2-Clause-Views）提供 `src/fpga/` 下的 FPGA NIC 基础框架。少量文件由 Le Sun 修改，均有明确 modification 标记；精确 diff 位于 `patches/corundum/`。

- **AMD/Xilinx Vitis Libraries**（Apache-2.0）提供 `hls/src/project/` 中使用的 AES-GCM HLS 示例源码，以及构建时依赖的 Security Library headers。

详见：

- `AUTHORS.md`
- `THIRD_PARTY_NOTICES.md`
- `docs/PROVENANCE.md`

## 它有多快？

- 历史工程记录的性能基线约为 **2.7 / 2.75 Gbps**。  
  后续 cycle-level 审计根据实际串行架构重建出的 1518-byte 帧模型约为 **2.60 Gbps**。  
  当前归档工程中**没有恢复出当年的干净板上 iperf 原始证据**。

- 如果采用 cached-SA 模型，AES-GCM crypto core 本身具备 **10G 级计算能力**：1518-byte frame 下，core-only 模型约为 **16 Gbps line-rate 等效能力**。

- 当前整个数据通路无法达到 10G 的根本原因是架构：
  - wrapper 是单帧 store-and-forward；
  - `capture → crypto → release` 完全串行；
  - 每帧还承担额外 crypto setup 开销；
  - 其中包括 `GF128_prepare()` 约 129 cycles/frame，以及每帧执行的 `updateKey()` 等。

- **10G 是已经分析清楚的工程 roadmap，不是当前能力声明。**

完整性能表见 `docs/PERFORMANCE.md`，其中对 64 / 512 / 1518 / 9000-byte frame 的：

- current；
- cached-SA；
- core-only；

进行了区分，并明确标注每个数字属于：

- measured；
- historical-label；
- modeled；
- projected。

## 为什么上限只有 2.7G？（简版）

`block throughput ≠ frame throughput ≠ Ethernet line rate`

GCM 内核内部的 CTR 和 GHASH 均可做到：

```text
II = 1
128 bit / cycle
```

但每一帧都要承担约 **186 cycles** 的串行 setup：

- `updateKey`
- `H` 计算
- `GF128_prepare`
- `E(K,Y0)`

同时 wrapper 只允许**一帧在途**：

```text
capture
  ↓
crypto
  ↓
release
```

三阶段不能重叠。

因此对于 1518-byte frame，完整架构的模型结果约为 **2.6 Gbps line**。

只优化 crypto setup、改成 cached-SA 仍然不够，因为单帧串行 wrapper 仍把性能限制在约 **3.3–3.9 Gbps**。

达到 10G 必须同时完成：

1. **cached-SA**
2. **frame-level pipelining**

详见：

- `docs/PROJECT_HISTORY.md`
- `docs/PERFORMANCE.md`

## 为什么当前版本不安全？

2026-08-06 的安全审计通过行为实验确认了以下问题：

| 安全属性 | 状态 |
| --- | --- |
| AES-GCM 算法核心 | HLS 层已验证（OpenSSL 独立 oracle） |
| Nonce uniqueness | **BLOCKER** — reset 后 PN 在相同 key 下回退 |
| Auth before release | **BLOCKER** — invalid-tag frame 的 plaintext 仍会被 RX 输出 |
| Replay protection | NOT IMPLEMENTED |
| SA lifecycle | NOT IMPLEMENTED |
| Key zeroization | GAP |
| Frame context identity | GAP |
| Fail closed | GAP |
| IEEE 802.1AE 标准兼容 | NOT IMPLEMENTED（自定义 framing） |

其中两个硬阻断已经通过**独立只读行为实验**复现：

- **E1：tag corruption 后仍然释放 plaintext**
- **E2：reset 后 `tx_pn` 在相同 key 下重新回到 1**

详见：

- `docs/SECURITY_STATUS.md`
- `docs/audits/`

## 下一步是什么？

```text
先解决 security
    ↓
cached-SA
    ↓
frame-level pipelining
    ↓
10G verification
```

具体 roadmap 位于 `docs/ROADMAP.md`：

- **v0.3** — security baseline
- **v0.4** — cached-SA refactor
- **v0.5** — datapath pipelining
- **v1.0-candidate** — 必须满足：
  - sustained 10G；
  - timing met；
  - independent oracle；
  - security closure；
  - post-synthesis verification；
  - board verification。

## 如何构建？

见 `docs/BUILD.md`。

当前已知要求：

- Vivado / Vitis HLS 2022.1
- FPGA part：`xcku040-ffva1156-2-e`
- Corundum baseline  
  - 当前精确 upstream commit 尚未完全恢复；
  - 见 `docs/PROVENANCE.md` 中的 `UPSTREAM_BASELINE_UNKNOWN`
- AMD/Xilinx Vitis Libraries 2022.1 作为外部依赖

当前：

```text
CLEAN_REBUILD_NOT_YET_PROVEN
```

也就是说，**从完全干净源码重新构建的流程目前尚未被重新验证**。

历史工程主要通过交互方式构建，其 AMD/Xilinx generated IP 不包含在发布包中。

## 哪些内容没有包含？

以下内容不在发布包中：

- AMD/Xilinx generated IP（`.xci`）
- generated HLS RTL
- `.dcp`
- `.bit`
- `.ltx`
- Vivado cache
- run directories
- build logs
- HLS-generated RTL copies
- simulation build artifacts
- Corundum 完整仓库

当前只包含为了审计和理解项目所需的最小 Corundum 子集；完整 upstream tree 请从 Corundum 官方项目获取。

详见：

- `release_metadata/FILES_EXCLUDED.md`
- `docs/BUILD.md`

## 能不能用于 production？

**不能。**

本仓库是研究和教学性质的工程材料。

它真正的价值不在于“当前版本已经完成”，而在于它完整记录了一个真实 FPGA security datapath 的工程过程：

1. 数据通路首先实现了功能闭环；
2. 随后遇到了真实的性能瓶颈；
3. 后续对整个系统进行了 cycle-by-cycle 拆解；
4. 进一步审计发现了安全架构缺口；
5. 最终形成了一个可以继续向更干净架构演进的、可审计工程起点。

公开这个项目的重点，是它的：

- performance post-mortem；
- security post-mortem；
- verification lessons；
- architecture recovery roadmap；

而不是把历史归档版本包装成一个已经完成的 production MACsec。

## 仓库目录（概要）

```text
src/macsec/           Le Sun 原创 MACsec RTL（BSD-2-Clause）
src/fpga/             Corundum NIC RTL 子集（BSD-2-Clause-Views，部分有修改）
hls/src/project/      Vitis AES-GCM HLS 示例源码（Apache-2.0，未修改）
tb/                   verification（cocotb integration + E1/E2 security regressions）
constraints/          XDC constraints（Corundum + MACsec additions）
patches/corundum/     对 Corundum 修改文件的 diff
docs/                 项目故事、架构、性能、安全、roadmap、审计
release_metadata/     provenance manifest、license/secret scan、SHA256SUMS
```

## License

本仓库是一个 multi-license source tree。

- Le Sun 原创代码：**BSD-2-Clause**
- 第三方源码以及 derivative files：保留各自 upstream license

详见：

- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `LICENSES/`
- `docs/PROVENANCE.md`

## 版本

当前 release candidate 定义为：

```text
v0.2-audited
```

目前尚未创建实际 git tag。

推荐版本规划见 `CHANGELOG.md`。

---

**发布准备状态：**

```text
RELEASE_CANDIDATE_REQUIRES_HUMAN_REVIEW
```

发布前人工检查项见：

`docs/PUBLISH_REVIEW_REQUIRED.md`
