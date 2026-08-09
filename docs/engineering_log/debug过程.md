基于现在现象，PHY 已经起来、sfp_1_led 亮，问题基本从“物理链路不通”转到“MAC 以上数据面某一级断了”。我看了当前工程和基准工程的差异，当前版本的关键改动是：在 mqnic_gcm_codex.srcs/sources_1/imports/
  fpga_25g/rtl/fpga_core.v:789 里把 macsec_tx_wrapper 和 macsec_rx_wrapper 插在 mqnic 与 eth_mac_10g 之间，而且 TX/RX 都硬连 enable(1'b1)。

  我建议按下面顺序排查，不要一开始猜加密算法错。先把路径切成几段，看包死在哪一级。

  第一步：先用软件统计判断主机侧有没有发包
  在两台主机上跑：

  ip -s link show <iface>
  ethtool -S <iface>

  然后清 ARP 或换目标 IP 后执行：

  ping -c 3 <peer-ip>
  arp -n
  ethtool -S <iface>

  重点看本机 TX packet 计数有没有涨、对端 RX packet 计数有没有涨。

  判断：

  | 结果 | 说明 |
  | --- | --- |
  | 本机 TX 不涨 | 驱动/接口/路由/端口配置问题，不是 FPGA 数据面 |
  | 本机 TX 涨，对端 RX 完全不涨 | FPGA TX 发不出，或对端 RX/MACsec 丢掉 |
  | 对端硬件 RX 涨但 Wireshark 看不到 | 包进了板卡但没有进入 host DMA，重点查解密/RX wrapper |
  | 对端 Wireshark 能看到异常 EtherType/乱码 | TX 发出了，但 RX 没解或包格式不符合普通以太网栈 |

  第二步：临时做一个 bypass bitstream
  这是最快的 sanity check。把当前工程里的 MACsec wrapper 保留，但 enable 暂时改成 1'b0，也就是：

  mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:813

  .enable(1'b0)

  mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:834

  .enable(1'b0)

  如果 bypass 后 ping 通，说明 PCIe、driver、MAC、PHY 都没问题，问题就在 MACsec 这条新链路。

  如果 bypass 后也不通，那就不是 GCM 算法本身，优先查当前工程相对基准的非 MACsec 改动，比如 PCIe lane 宽度、RAM_PIPELINE=3、约束和 IP 配置。

  第三步：ILA 抓 4 个断点
  不要只抓 eth_mac_inst，要同时抓 wrapper 两侧。端口 0 先够用。

  TX 方向：

  1. axis_eth_tx_tvalid/tready/tlast/tkeep/tdata
     位置：mqnic -> MACsec TX 输入，见 mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:795
  2. axis_eth_tx_mac_tvalid/tready/tlast/tkeep/tdata
     位置：MACsec TX 输出 -> eth_mac_10g，见 mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:867

  RX 方向：

  3. axis_eth_rx_mac_tvalid/tlast/tkeep/tdata
     位置：eth_mac_10g RX 输出 -> MACsec RX 输入，见 mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:874
  4. axis_eth_rx_tvalid/tready/tlast/tkeep/tdata
     位置：MACsec RX 输出 -> mqnic，见 mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:824

  触发方式：本机执行 arping 或 ping 时，触发 axis_eth_tx_tvalid 或 axis_eth_rx_mac_tvalid 上升沿。

  判断很直接：

  | ILA 现象 | 结论 |
  | --- | --- |
  | axis_eth_tx_tvalid 有，axis_eth_tx_mac_tvalid 没有 | TX wrapper/HLS 加密链路卡住 |
  | axis_eth_tx_mac_tvalid 有，但对端 axis_eth_rx_mac_tvalid 没有 | 发出到 MAC/PHY 之后有问题，查 XGMII/MAC/FCS/对端链路 |
  | 对端 axis_eth_rx_mac_tvalid 有，axis_eth_rx_tvalid 没有 | RX tag strip / decrypt / HLS 输出卡住 |
  | axis_eth_rx_tvalid 有，但 host Wireshark 没有 | mqnic RX DMA/sideband/tuser/driver 方向问题 |

  第四步：我最怀疑的两个点
  第一，RX wrapper 的输入没有真正 backpressure 到 eth_mac_10g。eth_mac_10g 的 RX AXIS 没有 tready，但 mqnic_gcm_codex.srcs/sources_1/imports/rtl/macsec_rx_wrapper.v:17 内部有 s_axis_tready，在
  mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:822 被悬空了。也就是说 MAC 会继续吐包，而 RX wrapper 如果忙着整帧缓存、strip tag、等 HLS，就可能丢后续帧。这个结构不适合直接接一个不可反
  压的 MAC RX 源。

  第二，RX sideband 被强制清零：

  mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:786

  assign axis_eth_rx_tuser[...] = {AXIS_ETH_RX_USER_WIDTH{1'b0}};

  如果原始 eth_mac_10g 的 rx_axis_tuser 携带 bad frame / bad FCS / PTP sideband，而 mqnic 依赖其中某些位，这里会改变 RX 行为。它不一定是 ping 完全不通的根因，但属于必须验证的差异点。

  第五步：最低成本定位实验
  我建议生成三个 bitstream，逐个上板：

  1. bypass：TX/RX MACsec 都 enable=0。目标是证明当前工程除 MACsec 外仍通。
  2. tx_debug：MACsec 开启，但 ILA 只抓 TX 四级信号。目标是确认本机包是否加密后送到 eth_mac_10g。
  3. rx_debug：MACsec 开启，ILA 抓 RX 四级信号和 u_macsec_rx 内部 strip_tag_valid、decrypt_tag_read、ip_plaintext_write。目标是确认是收不到、strip 不出 tag，还是 HLS decrypt 没输出。

  当前最有信息量的下一步是做 bypass bitstream。它能马上把问题分成“集成破坏了基础工程”还是“MACsec 数据通路本身有 bug”。

