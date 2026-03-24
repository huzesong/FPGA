# FPGA
这是跟FPGA相关的所有工程的仓库

---

## 项目：B码与GNSS时间提取系统

### 功能概述

本项目实现了一个完整的 FPGA Verilog 工程，能够：

1. **解码 IRIG-B 时间码**（B码）：从外部输入的 B 码串行信号中提取秒、分、时、年积日及年份，并自动换算为公历日期（含闰年判断）；
2. **解析 GNSS NMEA 报文**：支持 GPS（GP 前缀）、北斗（GB 前缀）、伽利略（GA 前缀）三种星座，从 UART 串口接收 NMEA 0183 语句，对每种星座分别输出原始报文及解析后的时间/日期字段（含闰年判断）。

---

### 文件结构

```
src/
  leap_year.v        - 闰年判断模块（2位年份 0-99，对应2000-2099年）
  day_to_date.v      - 年积日转公历月/日模块（含闰年处理）
  b_code_decoder.v   - IRIG-B 时间码解码模块
  uart_rx.v          - 串行 UART 接收模块（8N1，可配置波特率）
  nmea_parser.v      - GNSS NMEA 0183 报文解析模块（GP/GB/GA + RMC/GGA）
  top.v              - 顶层集成模块

tb/
  tb_b_code_decoder.v - IRIG-B 解码器仿真测试台
  tb_nmea_parser.v    - NMEA 解析器仿真测试台
  tb_top.v            - 顶层集成仿真测试台
```

---

### 各模块说明

#### `src/leap_year.v` — 闰年判断

| 端口 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `year_2digit` | 输入 | 7 | 2位年份（0=2000, 24=2024 …） |
| `is_leap` | 输出 | 1 | 1 = 闰年 |

判断规则（针对 2000–2099 年）：
- 年份 00（即 2000 年）：是闰年（能被 400 整除）；
- 年份 25、50、75（不能被 4 整除但被 25 整除的）：非闰年；
- 其余能被 4 整除的年份：是闰年。

---

#### `src/day_to_date.v` — 年积日→公历日期

| 端口 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `day_of_year` | 输入 | 9 | 年积日（1–366） |
| `is_leap` | 输入 | 1 | 闰年标志 |
| `month` | 输出 | 4 | 月（1–12） |
| `day` | 输出 | 5 | 日（1–31） |

---

#### `src/b_code_decoder.v` — IRIG-B 解码

**参数**：`CLK_FREQ`（默认 50 MHz）

| 端口 | 说明 |
|------|------|
| `b_code_in` | IRIG-B 数字信号输入（空闲低，高电平为脉冲） |
| `second[5:0]` | 秒（0–59） |
| `minute[5:0]` | 分（0–59） |
| `hour[4:0]` | 时（0–23） |
| `day_of_year[8:0]` | 年积日（1–366） |
| `year[6:0]` | 2 位年份（0–99） |
| `month[3:0]` | 月（1–12，由年积日转换） |
| `day[4:0]` | 日（1–31，由年积日转换） |
| `is_leap` | 闰年标志 |
| `time_valid` | 时间有效标志（连续 6 帧同步后置 1） |
| `pps_out` | 1 PPS 脉冲（每帧首位下降沿触发） |

**IRIG-B 帧结构（100 bits/帧，100 bps）：**

| 位 | 内容 |
|----|------|
| 0 | P0（参考标志） |
| 1–4 | 秒个位 BCD（权值 1,2,4,8） |
| 5 | 未使用 |
| 6–7 | 秒十位 BCD（权值 10,20） |
| 8 | 未使用 |
| 9 | P1（参考标志） |
| 10–13 | 分个位 BCD |
| 15–17 | 分十位 BCD（权值 10,20,40） |
| 19 | P2 |
| 20–23 | 时个位 BCD |
| 25–26 | 时十位 BCD（权值 10,20） |
| 29 | P3 |
| 30–33 | 年积日个位 BCD |
| 35–38 | 年积日十位 BCD |
| 39 | P4 |
| 40–41 | 年积日百位 BCD（权值 100,200） |
| 49 | P5 |
| 59 | P6 |
| 60–63 | 年个位 BCD |
| 64–67 | 年十位 BCD |
| 68 | 闰秒/控制 |
| 69 | P7 |
| 70–78 | DST 标志/控制功能 |
| 79 | P8 |
| 80–98 | 控制功能/质量 |
| 99 | P9（帧结束） |

脉冲宽度分类：
- `< 3.5 ms` → 逻辑 0
- `3.5–6.5 ms` → 逻辑 1
- `> 6.5 ms` → 参考标志

---

#### `src/uart_rx.v` — UART 接收

**参数**：`CLK_FREQ`（默认 50 MHz），`BAUD_RATE`（默认 9600）

格式：8 数据位，无奇偶，1 停止位（8N1）。在每个位周期的中点采样。

---

#### `src/nmea_parser.v` — NMEA 报文解析

**参数**：`CLK_FREQ`（默认 50 MHz），`BAUD_RATE`（默认 9600），`MAX_SENTENCE_LEN`（默认 96）

支持的语句：

| 语句前缀 | 星座 | 语句类型 |
|---------|------|---------|
| `$GP` | GPS | RMC（时间+日期+状态）、GGA（时间+定位质量） |
| `$GB` | 北斗 | RMC、GGA |
| `$GA` | 伽利略 | RMC、GGA |

每种星座的输出端口：

| 端口组 | 说明 |
|--------|------|
| `xxx_sentence_type` | 0=RMC, 1=GGA, 2=GLL, 3=VTG |
| `xxx_sentence_raw` | 原始语句字节（最新有效句） |
| `xxx_sentence_valid` | 新语句解析成功脉冲（1 个时钟周期） |
| `xxx_hour/minute/second` | UTC 时间 |
| `xxx_time_valid` | UTC 时间已更新 |
| `xxx_day/month/year` | UTC 日期（仅 RMC） |
| `xxx_date_valid` | 日期已更新 |
| `xxx_is_leap` | 当前年份是否为闰年 |
| `xxx_status` | 定位状态（1=有效 A，0=无效 V） |

校验：对 `$` 和 `*` 之间所有字节做异或运算，与接收到的十六进制校验码比对，不匹配则丢弃。

---

#### `src/top.v` — 顶层集成

将以上所有模块集成：UART 接收 → NMEA 解析；B 码输入 → IRIG-B 解码。所有解析结果通过顶层端口输出。

---

### 仿真

使用 [Icarus Verilog](https://github.com/steveicarus/iverilog) 进行仿真：

```bash
# IRIG-B 解码器
iverilog -g2001 -o sim_bcode \
  src/leap_year.v src/day_to_date.v src/b_code_decoder.v \
  tb/tb_b_code_decoder.v && vvp sim_bcode

# NMEA 解析器
iverilog -g2001 -o sim_nmea \
  src/leap_year.v src/nmea_parser.v \
  tb/tb_nmea_parser.v && vvp sim_nmea

# 顶层集成
iverilog -g2001 -o sim_top \
  src/leap_year.v src/day_to_date.v src/b_code_decoder.v \
  src/uart_rx.v src/nmea_parser.v src/top.v \
  tb/tb_top.v && vvp sim_top
```

仿真测试台使用小时钟频率参数（`CLK_FREQ=1000`）以加快仿真速度，同时保持与真实设计完全相同的逻辑行为。

**测试结果：共 71 项测试，全部通过。**

| 测试台 | 测试项数 | 覆盖内容 |
|--------|---------|---------|
| `tb_nmea_parser` | 42 | GPS/北斗/伽利略 RMC+GGA；坏校验拒绝；闰年边界（2000、2024） |
| `tb_b_code_decoder` | 9 | sec/min/hr/doy/yr 解码；闰年；公历月日换算（5月2日） |
| `tb_top` | 20 | IRIG-B 集成（doy=60/2024 = 2月29日）；GPS UART 集成 |

---

### 综合说明

- 所有模块可直接使用 Quartus、Vivado 等工具综合。
- 修改 `top.v` 中的 `CLK_FREQ` 和 `BAUD_RATE` 参数以匹配目标硬件。
- IRIG-B 输入需要外部施密特触发器整形，以确保干净的数字边沿。
- GNSS UART 输入应连接至接收机的 TX 引脚（9600 baud 8N1，TTL 电平）。

