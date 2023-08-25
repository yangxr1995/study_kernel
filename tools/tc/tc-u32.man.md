# 语法
```
       tc filter ... [ handle HANDLE ] u32 OPTION_LIST [ offset OFFSET ] [ hashkey HASHKEY ] [ classid CLASSID ] [ divisor uint_value ] [ order u32_value ]
               [ ht HANDLE ] [ sample SELECTOR [ divisor uint_value ] ] [ link HANDLE ] [ indev ifname ] [ skip_hw | skip_sw ] [ help ]

       HANDLE := { u12_hex_htid:[u8_hex_hash:[u12_hex_nodeid] | 0xu32_hex_value }

       OPTION_LIST := [ OPTION_LIST ] OPTION

       HASHKEY := [ mask u32_hex_value ] [ at 4*int_value ]

       CLASSID := { root | none | [u16_major]:u16_minor | u32_hex_value }

       OFFSET := [ plus int_value ] [ at 2*int_value ] [ mask u16_hex_value ] [ shift int_value ] [ eat ]

       OPTION := { match SELECTOR | action ACTION }

       SELECTOR := { u32 VAL_MASK_32 | u16 VAL_MASK_16 | u8 VAL_MASK_8 | ip IP | ip6 IP6 | { tcp | udp } TCPUDP | icmp ICMP  |  mark  VAL_MASK_32  |  ether
               ETHER }

       IP  := { { src | dst } { default | any | all | ip_address [ / { prefixlen | netmask } ] } AT | { dsfield | ihl | protocol | precedence | icmp_type |
               icmp_code } VAL_MASK_8 | { sport | dport } VAL_MASK_16 | nofrag | firstfrag | df | mf }

       IP6 := { { src | dst } { default | any | all | ip6_address [/prefixlen ] } AT |  priority  VAL_MASK_8  |  {  protocol  |  icmp_type  |  icmp_code  }
               VAL_MASK_8 | flowlabel VAL_MASK_32 | { sport | dport } VAL_MASK_16 }

       TCPUDP := { src | dst } VAL_MASK_16

       ICMP := { type VAL_MASK_8 | code VAL_MASK_8 }

       ETHER := { src | dst } ether_address AT

       VAL_MASK_32 := u32_value u32_hex_mask [ AT ]

       VAL_MASK_16 := u16_value u16_hex_mask [ AT ]

       VAL_MASK_8 := u8_value u8_hex_mask [ AT ]

       AT := [ at [ nexthdr+ ] int_value ]
```
# 描述

32位过滤器允许匹配数据包中的任意位字段。它将所有内容都分解为值、掩码和偏移量，
此外存在许多抽象指令，可以在更高层次上定义规则，因此在许多情况下，用户无需手动处理位和掩码。

有两种使用方法：
第一，创建一个新的过滤器，以将数据包派给不同的目标。除了明显的功能，如通过指定一个CLASSID或调用一个动作来分类数据包，
第二，将一个过滤器链接到另一个（或甚至一组）过滤器，有效地将过滤器组织成树状层次结构。

通常，过滤器的委派数据包是基于哈希表完成的，这导致了第二种调用模式：它仅用于设置这些哈希表。过滤器可以选择一个哈希表，并提供一个哈希键值生成器，根据数据包指定bit域计算出一个哈希值，并用作查找表的桶的键，该桶包含用于进一步处理的过滤器。如果使用了大量的过滤器，这是效率很高的，因为执行哈希操作和表查找的开销在这种情况下可以忽略不计。使用u32的哈希表基本上涉及以下模式：

(1) 创建一个新的哈希表，使用 divisor 指定其大小，并最好提供一个句柄来识别该表。如果没有给出后者，内核会自己选择一个，稍后需要猜测。
```shell
//  tc filter add dev eth1 parent 1:0 prio 5 protocol ip u32
tc filter add dev eth1 parent 1:0 prio 5 handle 2: protocol ip u32 divisor 256
```

(2) 创建链接到（1）中创建的表的过滤器，使用link参数，并定义内核将用于计算哈希键的数据包数据。
```shell
tc filter add dev eth1 protocol ip parent 1:0 prio 5 u32 ht 800:: \
 match ip src 1.2.0.0/16 \
 hashkey mask 0x000000ff at 12 \
 link 2:
```

(3) 将过滤器添加到（1）中的哈希表的桶中。为了避免需要知道内核如何精确创建哈希键，有一个sample参数，它提供用于哈希的样本数据，从而定义应添加过滤器的表桶。

实际上，即使没有明确请求，u32也会为每个添加过滤器的优先级创建一个哈希表。但是表的大小是1，所以它实际上只是一个链表。

# VALUES
选项和选择器需要以特定格式指定值，这往往不直观。因此，概述中的术语已被赋予描述性名称，以指示所需的格式和/或允许的最大数值：
前缀u32、u16和u8分别表示四字节、两字节和单字节的无符号值。例如，u16表示范围在0到65535（0xFFFF）之间的两字节大小的值。
前缀int表示四字节有符号值。中部的_hex_部分表示该值以十六进制格式解析。否则，将自动检测值的基数，即以0x为前缀的值被视为十六进制，以0为前导的值表示八进制格式，否则为十进制格式。还有一些值具有特殊的格式：ip_address和netmask通常以IPv4地址的点分四位格式表示。ip6_address以常见的冒号分隔的十六进制格式指定。最后，prefixlen是一个无符号的十进制整数，范围从0到地址位宽（IPv4为32，IPv6为128）。

有时，值需要能够被某个特定数字除尽。在这种情况下，选择了形如N\*val的名称，表示val必须能被N整除。或者反过来说，结果值必须是N的倍数。

# 选项
U32识别以下选项：
*  handle HANDLE
handle用于引用过滤器，因此必须唯一。它由哈希表标识符htid和可选的哈希（识别哈希表的存储桶）以及nodeid组成。所有这些值都被解析为无符号的，十六进制的数字，长度为12位（htid和nodeid）或8位（hash）。另外，也可以指定一个单一的，32位长的十六进制数，该数包含了三个字段位的连续形式。除了字段本身，它必须以0x为前缀。

* offset OFFSET
设置一个偏移量，定义后续过滤器的匹配位置。因此，这个选项只在与link或ht和sample的组合时有用。偏移量可以通过使用+关键字明确给出，或者从包数据中提取出来。可以使用mask和/或shift关键字来改变后者。默认情况下，这个偏移量被记录下来，但并不隐式应用。它只用于替代nexthdr+语句。但使用关键字eat可以反转这种行为：偏移量总是被应用，nexthdr+将回退到零。


* hashkey HASHKEY
指定用于计算存储桶查找的哈希键的包数据。内核根据哈希表的大小调整值。要使此工作，必须给出link选项。

* classid CLASSID
将匹配的包分类到给定的CLASSID中，CLASSID由16位主要和次要数字组成，或者由一个单一的32位值组合两者。

* divisor u32_value
指定一个模数值。在创建哈希表以定义它们的大小或声明一个样本以从中计算哈希表键时使用。必须是不超过八的二的幂。

* order u32_value
一个用于按升序排列过滤器的值。与handle冲突，后者具有相同的目的。

* sample SELECTOR
与ht一起使用，以指定将此过滤器添加到哪个存储桶中。这允许你避免必须知道内核如何精确计算哈希值。额外的除数默认为256，因此必须为不同大小的哈希表给出。

* link HANDLE
将匹配的数据包委托给哈希表中的过滤器处理。HANDLE 仅用于指定哈希表，因此只能给出 htid，必须省略 hash 和 nodeid。默认情况下，将使用桶号 0，可以通过 hashkey 选项进行覆盖。

* indev ifname
根据数据包的输入接口进行过滤。显然，这只适用于转发的流量。

* skip_sw
不通过软件处理过滤器。如果硬件没有对此过滤器的卸载支持，或者没有为接口启用 TC 卸载，操作将失败。

* skip_hw
不通过硬件处理过滤器。

# 选择器
Basically the only real selector is u32 .  All others merely provide a higher level syntax and are internally translated into u32 .

```
u32 VAL_MASK_32
u16 VAL_MASK_16
u8 VAL_MASK_8
  将数据包数据与给定值匹配。选择器名称定义了要提取的样本长度（u32 对应 32 位，u16 对应 16 位，u8 对应 8 位）。
  在比较之前，样本将与给定的掩码进行二进制与运算。这样，可以在比较之前清除不感兴趣的位。样本的位置由 at 中指定的偏移量定义。

ip IP
ip6 IP6
  假设数据包以IPv4（ip）或IPv6（ip6）头开始。IP/IP6允许匹配各种头字段：

    src ADDR
    dst ADDR
       将源地址或目标地址字段与ADDR的值进行比较。保留字default、any和all实际上匹配任何地址。否则，需要特定协议的IP地址，可选地后缀为前缀长度以匹配整个子网。对于IPv4，还可以提供网络掩码。

	dsfield VAL_MASK_8
		仅适用于IPv4。匹配数据包头的DSCP/ECN字段。它的同义词是tos和precedence。

	ihl VAL_MASK_8
		仅适用于IPv4。匹配Internet头长度字段。请注意，值的单位是32位，因此要匹配具有24字节头长度的数据包，u8_value必须为6。

	protocol VAL_MASK_8
		匹配协议（IPv4）或下一个头部（IPv6）字段的值，例如6表示TCP。

	icmp_type VAL_MASK_8
	icmp_code VAL_MASK_8
		假设下一个头部协议为icmp或ipv6-icmp，并匹配类型或代码字段的值。这是危险的，因为该代码假设IPv4的最小头部大小和IPv6的缺乏扩展头。

	sport VAL_MASK_16
	dport VAL_MASK_16
		匹配第四层的源端口或目标端口。这也是危险的，因为它假设适当的第四层协议存在（其源端口和目标端口字段位于头部的开头，并且大小为16位）。还假设了IPv4的最小头部大小和缺乏IPv6扩展头。

	nofrag
	firstfrag
	df
	mf     仅适用于IPv4，检查特定的标志和片段偏移值。如果数据包不是片段（nofrag），是分段数据包的第一个片段（firstfrag），设置了不分段（df）或更多片段（mf）位，则匹配。

	priority VAL_MASK_8
		仅适用于IPv6。匹配头部的流量类别字段，该字段具有与IPv4的TOS字段相同的目的和语义，自RFC 3168以来：前六位是DSCP，后两位是ECN。

	flowlabel VAL_MASK_32
		仅适用于IPv6。匹配流标签字段的值。请注意，流标签本身只有20字节长，这些是最低有效位。剩余的上12字节匹配版本和流量类别字段。

tcp TCPUDP
udp TCPUDP
    匹配下一层协议为TCP或UDP的字段。TCPUDP的可能取值为：

    src VAL_MASK_16
        匹配源端口字段的值。

    dst VALMASK_16
        匹配目标端口字段的值。

icmp ICMP
    匹配下一层协议为ICMP的字段。ICMP的可能取值为：

    type VAL_MASK_8
        匹配ICMP类型字段。

    code VAL_MASK_8
        匹配ICMP代码字段。

mark VAL_MASK_32
    匹配netfilter fwmark值。

ether ETHER
    匹配以太网头字段。ETHER的可能取值为：

    src ether_address AT
    dst ether_address AT
        匹配源或目标以太网地址。这种方式存在风险：它假设以太网头在数据包的开头。如果与三层接口（如tun或ppp）一起使用，可能会导致意外结果。
```
# 示例
```shell
 tc filter add dev eth0 parent 999:0 prio 99 protocol ip u32 \
			match ip src 192.168.8.0/24 classid 1:1
```

这个命令将一个过滤器附加到由999:0标识的qdisc。它的优先级是99，这影响了多个附加到同一父级的过滤器的查询顺序（数值越低，越早查询）。该过滤器处理的是ip协议类型的数据包，并且只有当IP报头的源地址在192.168.8.0/24子网内时才匹配。匹配的数据包被归类为1:1类。

这个命令的效果一开始可能会让人感到惊讶：

```shell
tc filter add parent 1: protocol ip pref 99 u32
tc filter add parent 1: protocol ip pref 99 u32 \
		fh 800: ht divisor 1
tc filter add parent 1: protocol ip pref 99 u32 \
		fh 800::800 order 2048 key ht 800 bkt 0 flowid 1:1 \
		match c0a80800/ffffff00 at 12

# 以上命令合并写为：
# 这条命令在root（parent 1:）下创建了一个u32类型的过滤器，
# 其优先级（pref）是99，过滤器的句柄（handle）是800:，
# 并设置了散列表的除数（divisor）为1。散列表除数决定了散列表的大小，即能够存储多少条过滤规则。
tc filter add parent 1: protocol ip pref 99 u32 \
		fh 800: ht divisor 1

# 这条命令在上一条命令创建的过滤器下添加了一条过滤规则，
# fh 800::800   filter handle 800::800 ，此过滤器的句柄为 800::800，前一个800为主句柄，后为子句柄，主句柄800说明加入上面创建的 fh 800:的哈希表
# order 2048    此过滤器的优先级为2048，值越小优先级越高
# key ht 800 bkt 0  key is hash table 800 bucket 0 , 这个过滤条目在的在哈希表中唯一标识符为 ht 800 bkt 0，位于800表的0桶
# 流标识符（flowid）是1:1，
# 并且这条规则会匹配IP地址在12字节位置的c0a80800/ffffff00，也就是匹配源IP地址为192.168.8.0/24的所有流量。
tc filter add parent 1: protocol ip pref 99 u32 \
		fh 800::800 order 2048 key ht 800 bkt 0 flowid 1:1 \
		match c0a80800/ffffff00 at 12
```

因此，parent 1:被分配了一个新的u32过滤器，它包含一个大小为1（如除数所示）的哈希表。表ID为800。第三行显示了上面添加的实际过滤器：它位于800表和0桶，将数据包归类为类ID 1:1，并匹配四字节值的前三字节偏移12处为0xc0a808，这是192，168和8。


下面是一个更复杂的例子，即创建一个自定义的哈希表：
```shell
# u32 divisor 256 ， u32 说明之后参数用u32模块，divisor 256 创建哈希表有256个桶
# handle 1: 哈希表的句柄为 1:
tc filter add dev eth0 prio 99 handle 1: u32 divisor 256
```

这将创建一个大小为256的表，句柄为1:，优先级为99。效果如下：

```shell
filter parent 1: protocol all pref 99 u32
filter parent 1: protocol all pref 99 u32 fh 1: ht divisor 256
filter parent 1: protocol all pref 99 u32 fh 800: ht divisor 1
```

因此，除了请求的哈希表（句柄1:）之外，内核还创建了一个大小为1的表来容纳同一优先级的其他过滤器。

下一步是创建一个链接到创建的哈希表的过滤器：
```shell
tc filter add dev eth0 parent 1: prio 1 u32 \
		link 1: hashkey mask 0x0000ff00 at 12 \
		match ip src 192.168.0.0/16
```
过滤器被赋予比哈希表本身更低的优先级，所以u32在手动遍历哈希表之前会先查询它。链接和哈希键选项决定了重定向到哪个表和桶。在这种情况下，哈希键应该由偏移12处的第二字节构成，这对应于IP数据包源地址字段的第三字节。与匹配语句一起，这有效地将所有位于192.168.0.0/16以下的C类网络映射到哈希表的不同桶。

可以像这样创建特定子网的过滤器：
```shell
tc filter add dev eth0 parent 1: prio 99 u32 \
		ht 1: sample u32 0x00000800 0x0000ff00 at 12 \
		match ip src 192.168.8.0/24 classid 1:1
```

桶是使用sample选项定义的：在这种情况下，偏移12处的第二字节必须精确为0x08。在这种情况下，结果桶ID显然是8，但是一旦sample选择的数据量可能超过除数，就必须知道内核内部算法以推断出目标桶。在这种情况下，这个过滤器的匹配语句是多余的，因为哈希键的熵不超过表大小，因此不会发生冲突。否则，就需要防止匹配到不需要的数据包。

匹配上层字段是有问题的，因为IPv4报头长度是可变的，而IPv6支持扩展报头，这会影响上层报头偏移。为了克服这个问题，有可能在给出偏移时指定nexthdr+，为了简化操作，tcp和udp匹配隐式使用了nexthdr+。这个偏移必须事先计算，唯一的方法就是在一个单独的过滤器中进行，然后链接到想要使用它的过滤器。下面是一个例子：

```shell
tc filter add dev eth0 parent 1:0 protocol ip handle 1: \
		u32 divisor 1
tc filter add dev eth0 parent 1:0 protocol ip \
		u32 ht 1: \
		match tcp src 22 FFFF \
		classid 1:2
tc filter add dev eth0 parent 1:0 protocol ip \
		u32 ht 800: \
		match ip protocol 6 FF \
		match u16 0 1fff at 6 \
		offset at 0 mask 0f00 shift 6 \
		link 1:
```

这是正在执行的操作：在第一次调用中，创建了一个单元素大小的哈希表，这样就有一个地方可以存放链接到的过滤器，以及一个已知的句柄（1:）来引用它。然后第二次调用添加了实际的过滤器，将TCP源端口为22的数据包推入类1:2。使用ht，它被移动到第一次调用创建的哈希表中。第三次调用则执行了实际的魔术：它匹配下一层协议为6（TCP）的IPv4数据包，只有当它是第一个片段时（通常TCP设置DF位，但如果没有设置并且数据包被分片，只有第一个包含TCP报头），然后根据IP报头的IHL字段设置偏移（右移6消除了字段的偏移，并同时将值转换为字节单位）。最后，使用link引用了第一次调用的哈希表，该表包含了第二次调用的过滤器。

# SEE ALSO
tc(8),
cls_u32.txt at http://linux-tc-notes.sourceforge.net/

