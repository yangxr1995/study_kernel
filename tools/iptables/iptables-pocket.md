# 介绍
Linux 网络报文处理子系统被称为 netfilter，iptables是用于配置它的命令。

iptables 组织网络数据包处理规则到表中，按照规则的功能（过滤，地址转换，数据包修改）。这些表都有有序规则链。规则由match（用于决定本规则用于哪种数据包）和targets(决定会对匹配的数据包做什么)

iptables工作于 L3层，对于L2层，使用ebtables (Ether-net Bridge tables)


```shell
iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.3:8080

-t nat     工作于NAT表
-A PREROUTING  将改规则追加到PREROUTING链
-i eth1    匹配从eth1入栈的数据包
-p tcp     该数据包使用tcp协议
--dport 80 该数据包目的端口为80
-j DNAT    跳转到DNAT target
--to-destination 192.168.1.3:8080 DNAT改变目的地址为192.168.1.3:8080
```

## 概念

netfilter 定义了5个hook点在内核协议栈处理数据包的路线上： PREROUTING, INPUT, FORWARD, POSTROUTING, OUTPUT
内置链被链接到这些hook点，你可以添加一系列规则对每个hook点，每个规则表示一个机会用于影响或监控数据流。

注意：
通常会说，nat表的PREROUTING链，暗示了链属于表，但是链和表只有部分关联，两者都不会真正属于哪一方，chain表示hook点在数据流。table表示hook点上可能发生的处理类型。
下面的图展示了所有的合法组合，和他们遇到数据包的顺序。

下图展示NAT工作时，数据包如何遍历。
这些是用于NAT表的各种链
![](./pic/4.jpg)

这些是用于filter表的各种链
![](./pic/5.jpg)

这些是用于mangle表的各种链
![](./pic/6.jpg)


你选择链应该基于需要在数据流的哪里应用你的规则，如你希望过滤输出数据包，最好在OUTPUT链，因为POSTROUTING链不和filter表关联。

### tables

iptables有三个内建的表：filter, mangle, nat，他们都被预配置了chains，对应这一个或多个hook点，

nat : 用于配合连接跟踪以重定向连接以实现地址转换；典型的基于源地址或目标地址，内置链是 OUTPUT, POSTROUTING, PREROUTING

filter : 用于设置策略，以实现数据流的允许入栈，转发，出栈，除非你明确指定不同的表，否则iptables默认基于FORWARD, INPUT, OUTPUT 进行工作。

mangle : 用于专门的数据包改造，如剥离IP选项。它的内置链是 FORWARD INPUT OUTPUT POSTROUTING PREROUTING

注意：默认表是filter，如果你不显示指定表在iptables命令行中, filter会被假设

### chains

默认情况下，每个表都有链，链表初始化为空，用于一些或所有hook点。
另外，你可以创建自定义链用于组织你的规则。
chain's policy 决定了数据包的命运，这些数据包指通过其他规则，到达链的末尾。只有内置 targets ACCEPT 和 DROP 可以被用于作为内置链的 policy, 并且默认是 ACCEPT，所有自定义链有一个隐式policy是 RETURN，

如果你想一个更复杂的policy用于内置链或一个 policy（不是RETURN）用于自定义链，你可以添加一个规则到链的结尾，这个规则匹配所有的数据包，可以带任何你想要的target。

### packet flow
数据包遍历链，同一时间被呈现给链的一个规则按照顺序。如果数据包不匹配链的标准，包会被移动到此链的下一个规则。如果包到达了链的最后一个规则也不匹配，链的policy会被应用给它。(本质上，policy就是链的默认target)

### Rules
一个规则包含一个或多个匹配标准，标准决定了规则影响哪种数据包，所有的匹配项都要被满足，target设置规则如何影响数据包。
系统维护数据包和字节计数器为所有规则。每当一个数据包达到一个规则且匹配该规则的标准时，数据包计数器被增加，字节数计数器被增加。

规则的 match 和 target 都是可选的，如果没有match标准，所有的数据包都会被当作匹配。如果没有target，不对数据包做任何事(就像规则不存在一样，数据包继续流动，只有计数器更新).你可以添加一个null规则到FORWARD链 filter表，使用下面命令
```shell
iptables -t filter -A FORWARD
```

### Matches
有一系列可用的matches，虽然有些matche必须kernel开启了某些特征。IP协议的matches(如协议，源地址，目的地址)可以被应用到任何IP包的匹配，不需要任何扩展。

itpables可以动态加载扩展（使用 iptables -m 或 --match 选项 以告诉iptables你想使用哪个扩展）

使用mac匹配扩展可以基于MAC地址实现访问控制。

### targets
targets 用于设置规则匹配时的动作和chain的 policy。有4个内置targets，扩展模块提供了其他targets。

ACCEPT : 让包到下阶段。停止遍历本chain，从下一个chain头开始遍历

DROP : 完全停止处理包。不再检查它和其他规则，链，表 是否匹配，如果你想提供一些响应给发送方，使用 REJECT target 扩展

QUEUE :  发送包到用户空间，查看 libipq 获得更多信息

RETURN : 如果从自定义链使用RETURN，停止处理这个链，并返回遍历调用链（调用链的一个规则的目标时自定义链的名称）。如果是内置链使用RETURN，则停止匹配数据包，直接使用链的policy。

# 应用
下面提供了包处理技术的简介和一些应用

Packet filtering
涉及一些hook点，检查数据包是否通过内核
决定包应该如何处理，入栈，丢弃，REJECT

Accounting
涉及使用字节/包计数器结合包匹配标准，以监控流量

Connection tracking
根据已知协议设计匹配规则以识别报文。

Packet managling
改变数据包的头部或payload

NAT
有SNAT DNAT

Masquerading
Masquerading 是特殊的SNAT。



