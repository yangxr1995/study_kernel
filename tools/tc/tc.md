# 无类型排队规则
不分类（或称无类别）排队规则（classless queueing disciplines）可以对某个网络 接口（interface）上的所有流量进行无差别整形。包括对数据进行：
* 重新调度（reschedule）
* 增加延迟（delay）
* 丢弃（drop）

目前最常用的 classless qdisc 是 pfifo_fast，这也是很多系统上的 默认排队规则。

## pfifo_fast 
![](./pic/1.jpg)

## prio
创建如下树
```
          1:   root qdisc
         / | \
        /  |  \
       /   |   \
     1:1  1:2  1:3    classes
      |    |    |
     10:  20:  30:    qdiscs    qdiscs
     sfq  tbf  sfq
band  0    1    2
```
高吞吐流量（Bulk traffic）将送到 30:，交互式流量（interactive traffic）将送到 20: 或 10:

```shell
# tc qdisc : 设置qdisc 队列调度器
# add : 添加队列调度器
# dev eth0 : 目标网口eth0
# root : 添加的调度器放在树的根部
# handle 1: : 此节点的句柄为 1:，也就是别名
# prio : qdisc 的类型为 prio 类型，优先级功能的qdisc
$ tc qdisc add dev eth0 root handle 1: prio # This *instantly* creates classes 1:1, 1:2, 1:3

# 执行这条命令时会立即创建 3个class节点 1:1 1:2 1:3
/root # ./tc qdisc add dev eth0 root handle 1: prio
/root # ./tc class show dev eth0
class prio 1:1 parent 1:
class prio 1:2 parent 1:
class prio 1:3 parent 1:
# 当数据包包到达时，会被放入哪个band呢？
# 可以看到 prio 有个priomap ，一共16个数字，0,1,2分别表示放入对应band
# 怎么映射呢？
# 数据包的tos字段一共4bit，能表示16
#     0     1     2     3     4     5     6     7
#  +-----+-----+-----+-----+-----+-----+-----+-----+
#  |                 |                       |     |
#  |   PRECEDENCE    |          TOS          | MBZ |
#  |                 |                       |     |
#  +-----+-----+-----+-----+-----+-----+-----+-----+
#
#  Binary Decimcal  Meaning
#  -----------------------------------------
#  1000   8         Minimize delay (md)
#  0100   4         Maximize throughput (mt)
#  0010   2         Maximize reliability (mr)
#  0001   1         Minimize monetary cost (mmc)
#  0000   0         Normal Service
#
#  TOS     Bits  Means                    Linux Priority    Band
#  ------------------------------------------------------------
#  0x0     0     Normal Service           0 Best Effort     1
#  0x2     1     Minimize Monetary Cost   1 Filler          2
#  0x4     2     Maximize Reliability     0 Best Effort     2
#  0x6     3     mmc+mr                   0 Best Effort     2
#  0x8     4     Maximize Throughput      2 Bulk            1
#  0xa     5     mmc+mt                   2 Bulk            2
#  0xc     6     mr+mt                    2 Bulk            0
#  0xe     7     mmc+mr+mt                2 Bulk            0
#  0x10    8     Minimize Delay           6 Interactive     1
#  0x12    9     mmc+md                   6 Interactive     1
#  0x14    10    mr+md                    6 Interactive     1
#  0x16    11    mmc+mr+md                6 Interactive     1
#  0x18    12    mt+md                    4 Int. Bulk       1
#  0x1a    13    mmc+mt+md                4 Int. Bulk       1
#  0x1c    14    mr+mt+md                 4 Int. Bulk       1
#  0x1e    15    mmc+mr+mt+md             4 Int. Bulk       1
#
/root # ./tc qdisc show dev eth0
qdisc prio 1: root refcnt 2 bands 3 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1

不同的协议，会设置不同的tos
#  TELNET                   1000           (minimize delay)
#  FTP     Control          1000           (minimize delay)
#          Data             0100           (maximize throughput)
#
#  TFTP                     1000           (minimize delay)
#
#  SMTP    Command phase    1000           (minimize delay)
#          DATA phase       0100           (maximize throughput)
#
#  DNS     UDP Query        1000           (minimize delay)
#          TCP Query        0000
#          Zone Transfer    0100           (maximize throughput)
#
#  NNTP                     0001           (minimize monetary cost)
#
#  ICMP    Errors           0000
#          Requests         0000 (mostly)
#          Responses        <same as request> (mostly)
#

# parent 1:1 此节点的父节点为 1:1 ，也就是class节点 
# handle 10: : 节点的别名为 10:
# sfq : 节点使用 sfq qdisc
$ tc qdisc add dev eth0 parent 1:1 handle 10: sfq

# rate 20kbit buffer 1600 limit 3000 : 为 tbf 的参数
$ tc qdisc add dev eth0 parent 1:2 handle 20: tbf rate 20kbit buffer 1600 limit 3000
$ tc qdisc add dev eth0 parent 1:3 handle 30: sfq
```

