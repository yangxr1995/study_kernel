# 1. iptables

iptables 工作在IP层，TC工作在IP层和MAC层之间。

常见场景

* 做防火墙（filter表的INPUT链）
* 局域网共享上网(nat表的POSTROUTING链)，NAT功能
* 端口及IP映射(nat表的PREROUTING链)
* 实现IP一对一映射(DMZ)

工作流程：

1. 防火墙是一层一层过滤的，按照配置规则的顺序，从上到下，从前到后进行过滤。
2. 如果匹配了规则，明确说明是阻止还是通过，此时数据包就不在向下进行匹配新规则
3. 如果所有规则没有明确表明是阻止还是通过此数据包，将匹配默认规则，默认规则一定会给出明确的去向。

4表5链
表，同类功能规则的集合
    filter (做防火墙), 默认的表
    nat (端口或IP映射)
    mangle (配置路由标记 ttl tos mark)
    raw

链，作用于相同路径数据流的规则集合
    filter : INPUT, OUTPUT, FORWARD 
    NAT : POSTROUTING, PREROUTING, OUPUT 
    mangle : INPUT, OUTPUT, FORWARD, POSTROUTING. PREROUTING
    raw

INPUT : 流入主机的数据包 
OUPUT : 流出主机的数据包
FORWARD : 流经主机的
PREROUTING : 进入主机时，最先经过的链，位于路由表之前
POSTROUTING : 流出主机时，最后经过的链，位于路由表之后
![](./pic/1.jpg)

netfilter对包的处理流程
![](./pic/2.jpg)

做主机防火墙：
    Filter:INPUT

做网关：
    NAT:PREROUTING Filter:FORWARD NAT:POSTROUTING

相关内核模块
modprobe ip_tables
modprobe iptable_filter
modprobe iptable_nat
modprobe ip_conntrack
modprobe ip_conntrack_ftp
modprobe ip_nat_ftp
modprobe ipt_state

实践
清零表

封22端口
iptables -t filter -A INPUT -p tcp --dport 22 -j DROP
-p (tcp, udp, icmp, all)
--dport 目的端口
--sport 源端口
-j jump到处理方法ACCEPT DROP REJECT SNAT/DNAT
    DROP : 丢弃不响应
    REJECT : 丢弃，要响应
    SNAT 源地址转换，DNAT 目的地址转换

查看filter表规则
iptables -nL --line-numbers

删除filter表INPUT链1规则
iptalbes -D INPUT 1

# NAT

NAT主要有两种：SNAT(source network address translation) 和 DNAT
使用iptables可以实现。

## SNAT

如，多个PC使用ADSL路由器共享上网。
发包时需要将每个PC的源IP替换成路由器的IP，

## DNAT

如，web服务器放在内网，使用内网IP，前端有个防火墙使用公网IP，
客户访问的数据包使用防火墙公网IP，防火墙需要将包的目的IP修改成web服务器的内网IP，再发给web服务器。

## MASQUERADE

地址伪装。属于SNAT的特列，实现自动化SNAT。

下面说明MASQUERADE 和 SNAT 的差别，
使用SNAT，需要修改成的IP可以是一个也可以是多个，但必须要明确指定要SNAT成的IP。

把所有10.8.0.0网段的数据包SNAT成192.168.5.3发出去。
iptables -t nat -A POSTROUTING -s 10.8.0.0/255.255.255.0 -o eth0 -j snat --to-source 192.168.5.3

把所有10.8.0.0网段的数据包SNAT成192.168.5.3 或 192.168.5.4 或 192.168.5.5多个IP 
iptables -t nat -A POSTROUTING -s 10.8.0.0/255.255.255.0 -o eth0 -j snat --to-source 192.168.5.3-192.168.5.5

但是使用ADSL动态拨号时，网关获得出口IP会变化，很可能超出SNAT预定的地址。
总不能每次地址改变都重新设置SNAT吧。

MASQUERADE就是为了解决上述场景的问题。
MASQUERADE会从指定的网卡获得当前IP，做SNAT。

iptables -t nat -A POSTROUTING -s 10.8.0.0/255.255.255.0 -o eth0 -j MASQUERADE

如此，不论eth0获得什么IP，MASQUERADE都会自动读取eth0的IP，然后做SNAT。

# 扩展

## 网卡如何发送数据

网卡驱动将IP包封装成MAC包，将MAC包拷贝到网卡芯片内部缓冲区。
网卡芯片对MAC包再次封装，得到物理帧，添加头部不同信息和CRC校验，丢到网线上。
所有挂在同网线的网卡都看到此物理帧。

## 网卡如何接受数据

### 正常情况

网卡获得物理帧，检查CRC，确保完整性，
网卡将物理帧头去掉得到MAC包，
网卡检查MAC包的目的地址是否匹配，不一致就丢弃，一致则拷贝到网卡内缓冲区，触发中断。
驱动程序，处理中断，将帧拷贝到系统中，构建sk_buff，告诉上层。
上层去掉帧头，获得IP包

### 不正常模式（混淆）

网卡获得物理帧，检查CRC，确保完整性，
网卡将物理帧头去掉得到MAC包，
网卡发现自己是混淆模式，不对MAC地址进行过滤，将帧拷贝到网卡内部缓冲区，触发中断。
驱动程序，处理中断，将帧拷贝到系统中，构建sk_buff，告诉上层。
上层去掉帧头，获得IP包.
显然这里的IP包不一定是发给自己的。

### 总结

如果程序希望检查网线上所有报文，通常需要让网卡开启混淆模式，但这会加大CPU的负荷，
某些程序可以直接访问网卡，可能是dpdk.

