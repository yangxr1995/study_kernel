[[toc]]

# Man

## SYNOPSIS
```shell

       ipset [ OPTIONS ] COMMAND [ COMMAND-OPTIONS ]

       COMMANDS := { create | add | del | test | destroy | list | save | restore | flush | rename | swap | help | version | - }

       OPTIONS := { -exist | -output { plain | save | xml } | -quiet | -resolve | -sorted | -name | -terse | -file filename }

       ipset create SETNAME TYPENAME [ CREATE-OPTIONS ]

       ipset add SETNAME ADD-ENTRY [ ADD-OPTIONS ]

       ipset del SETNAME DEL-ENTRY [ DEL-OPTIONS ]

       ipset test SETNAME TEST-ENTRY [ TEST-OPTIONS ]

       ipset destroy [ SETNAME ]

       ipset list [ SETNAME ]

       ipset save [ SETNAME ]

       ipset restore

       ipset flush [ SETNAME ]

       ipset rename SETNAME-FROM SETNAME-TO

       ipset swap SETNAME-FROM SETNAME-TO

       ipset help [ TYPENAME ]

       ipset version

       ipset -
```

## DESCRIPTION
ipset 用于在 Linux 内核中设置、维护和检查所谓的 IP 集合。

根据集合的类型，IP 集合可以存储 IP（v4/v6）地址、（TCP/UDP）端口号、IP 和 MAC 地址对、IP 地址和端口号对等。请参阅下面的集合类型定义。

当 iptables 中的匹配项和目标引用集合时，会创建引用，这会在内核中保护给定的集合。只要有一个引用指向某个集合，该集合就不能被销毁。

简单解释一下，ipset 是一个工具，它允许你在 Linux 内核中创建、管理和查看 IP 相关的集合。

这些集合可以包含各种信息，如 IP 地址、端口号等。当你使用 iptables（一个用于配置 Linux 内核数据包过滤规则的工具）时，你可以引用这些 IP 集合。

这些引用的存在意味着集合在需要时不会被销毁，因为它们正在被使用。

## OPTIONS

ipset 识别选项可以分成几个不同的组。

### COMMANDS
这些选项指定了要执行的操作。除非另有说明，否则在命令行上只能指定其中一个选项。

对于命令名的长版本，你只需要使用足够的字母来确保 `ipset` 能够将其与其他所有命令区分开。`ipset` 解析器在查找长命令名中的最短匹配时会遵循这里的顺序。

* `n` 或 `create SETNAME TYPENAME [ CREATE-OPTIONS ]`：创建一个由 setname 和指定类型标识的集合。类型可能需要特定类型的选项。如果指定了 `-exist` 选项，当相同的集合（setname 和创建参数相同）已经存在时，`ipset` 将忽略由此产生的错误。
* `add SETNAME ADD-ENTRY [ ADD-OPTIONS ]`：向集合中添加一个给定的条目。如果指定了 `-exist` 选项，并且该条目已添加到集合中，`ipset` 将忽略此操作。
* `del SETNAME DEL-ENTRY [ DEL-OPTIONS ]`：从集合中删除一个条目。如果指定了 `-exist` 选项且条目不在集合中（可能已过期），则该命令将被忽略。
* `test SETNAME TEST-ENTRY [ TEST-OPTIONS ]`：测试一个条目是否在一个集合中。如果测试的条目在集合中，则退出状态号为零；如果条目不在集合中，则退出状态号非零。
* `x` 或 `destroy [ SETNAME ]`：销毁指定的集合或（如果未给出）所有集合。如果集合有引用，则什么也不做，不销毁任何集合。
* `list [ SETNAME ] [ OPTIONS ]` : 列出指定集合的头数据和条目，如果未指定集合，则列出所有集合。可以使用 -resolve 选项强制执行名称查找（可能会很慢）。当给定 -sorted 选项时，条目按排序顺序列出（如果给定的集合类型支持该操作）。选项 -output 可用于控制列出的格式：plain、save 或 xml。（默认是 plain。）如果指定了 -name 选项，则仅列出现有集合的名称。如果指定了 -terse 选项，则仅列出集合名称和头。输出打印到标准输出，可以使用 -file 选项来指定文件名而不是标准输出。
* `save [ SETNAME ]`: 将指定集合或所有集合保存到标准输出中，使恢复命令可以读取。可以使用 -file 选项来指定文件名而不是标准输出。
* `restore`: 恢复由 save 命令生成的保存会话。保存的会话可以从标准输入提供，也可以使用 -file 选项指定文件名而不是标准输入。请注意，恢复时不会删除现有的集合和元素，除非在恢复文件中指定。在恢复模式下允许所有命令，除了 list、help、version、交互模式和 restore 本身。
* `flush [ SETNAME ]`: 清空指定集合的所有条目，如果未指定集合，则清空所有集合。
* `e，rename SETNAME-FROM SETNAME-TO`: 重命名集合。由 SETNAME-TO 标识的集合必须不存在。
* `w，swap SETNAME-FROM SETNAME-TO`: 交换两个集合的内容，或者换句话说，交换两个集合的名称。所引用的集合必须存在，并且只有兼容类型的集合才能交换。
* `help [ TYPENAME ]`: 打印帮助信息以及如果指定 TYPENAME，则打印特定类型的帮助信息。
* `version` 打印程序版本。
* `-` 如果指定破折号作为命令，则 ipset 进入简单的交互模式，命令从标准输入读取。通过输入伪命令 quit 可以结束交互模式。

### OTHER OPTIONS
这些选项是 `ipset` 命令的其他可选参数。它们允许用户以不同的方式操作和管理 IP 集合。

* `-!, -exist`: 当要创建的集合完全相同或已存在的条目被添加或缺失的条目被删除时，忽略错误。
* `-o, -output { plain | save | xml }`: 选择 `list` 命令的输出格式。可以是普通文本 (`plain`)、保存格式 (`save`) 或 XML 格式 (`xml`)。
* `-q, -quiet`: 抑制任何输出到标准输出和标准错误。但如果 `ipset` 无法继续执行，它仍然会退出并显示错误。
* `-r, -resolve`: 在列出集合时强制名称查找。程序将尝试显示解析为主机名的 IP 条目，这需要缓慢的 DNS 查找。
* `-s, -sorted`: 有序输出。当列出集合时，条目将按序列出。但当前还不支持此选项。
* `-n, -name`: 仅列出现有集合的名称，即抑制集合标题和成员的列表。
* `-t, -terse`: 列出集合的名称和标题，即抑制集合成员的列表。
* `-f, -file filename`: 指定一个文件名以替代标准输出进行打印（用于 `list` 或 `save` 命令），或替代标准输入进行读取（用于 `restore` 命令）。

这些选项提供了更多的灵活性和控制力，让用户能够根据特定的需求使用 `ipset` 命令。

## 简介
这一部分描述了在创建IP集合时如何使用不同的集合类型和数据类型来定义集合的存储方式和数据类型。当我们想要创建集合时，必须定义如何存储数据和存储在集合中的数据类型是什么。这是通过创建命令的TYPENAME参数来实现的，它遵循特定的语法格式。

TYPENAME遵循这样的格式：`method:datatype[,datatype[,datatype]]。`
其中，当前支持的存储方法有bitmap（位图）、hash（哈希）和list（列表）。可能的数据类型有ip（IP地址）、net（网络）、mac（MAC地址）、port（端口号）和iface（接口）。集合的维度等于其类型名称中的数据类型数量。

当在集合中添加、删除或测试条目时，必须使用逗号分隔的数据语法作为命令的entry参数。
例如：
`ipset add foo ipaddr,portnum,ipaddr`

如果使用主机名或带短横线的服务名称代替IP地址或服务编号，则必须在方括号内包含主机名或服务名称。例如：
`ipset add foo [test-hostname],[ftp-data]`
对于主机名的情况，ipset内部会调用DNS解析器，但如果DNS返回多个IP地址，它只会使用第一个IP地址。
Bitmap和list类型使用固定大小的存储区来保存元素数据。而hash类型则使用哈希表来存储元素数据以避免哈希冲突。为了避免哈希冲突和达到一定数量的元素连接数耗尽，当使用ipset命令添加条目时，哈希的大小会加倍。当使用iptables/ip6tables的SET目标添加条目时，哈希的大小是固定的，即使新的条目无法添加到集合中，集合也不会重复出现重复的条目。

## GENERIC CREATE AND ADD OPTIONS

这段文本描述了 `ipset` 创建和添加集合时的通用选项。以下是这些选项的简要解释：

1. **timeout**
所有集合类型在创建集合和添加条目时都支持可选的 `timeout` 参数。创建集合时设置的 `timeout` 值默认为新条目的超时时间（以秒为单位）。
如果为集合启用了超时支持，则在添加条目时可以指定非默认的超时值。超时值为零表示条目永久添加到集合中。
已添加元素的超时值可以通过使用 `-exist` 选项重新添加元素来更改。
```shell
ipset create test hash:ip timeout 300
ipset add test 192.168.0.1 timeout 60
ipset -exist add test 192.168.0.1 timeout 600
```
2. **counters, packets, bytes**
所有集合类型在创建集合时都支持可选的 `counters` 选项。如果指定此选项，则创建集合时支持每个元素的包和字节计数器。
当元素（重新）添加到集合中时，包和字节计数器初始化为零，除非通过 `packets` 和 `bytes` 选项明确指定了计数器值。
```shell
ipset create foo hash:ip counters
ipset add foo 192.168.1.1 packets 42 bytes 1024
```

3. **comment**
所有集合类型都支持可选的 `comment` 扩展。启用此扩展后，你可以使用任意字符串注释 ipset 条目。
这个字符串被内核和 ipset 本身完全忽略，仅用于方便地记录条目存在的原因。注释中不能包含引号，并且通常的转义字符（\）没有意义。

```shell
ipset create foo hash:ip comment
ipset add foo 192.168.1.1/24 comment "allow access to SMB share on \\\\fileserv\\"
the above would appear as: "allow access to SMB share on \\fileserv\"
```

4. **skbinfo, skbmark, skbprio, skbqueue**
所有集合类型都支持可选的 `skbinfo` 扩展。这个扩展允许你在每个条目中存储元信息（防火墙标记、tc 类和硬件队列），并使用 `--map-set` 选项通过 SET netfilter 目标将其映射到数据包上。

* `skbmark` 选项格式：`MARK` 或 `MARK/MASK`，其中 `MARK` 和 `MASK` 是带有 `0x` 前缀的 32 位十六进制数。如果只指定了 `mark`，则使用 `mask 0xffffffff`。
* `skbprio` 选项具有 tc 类格式：`MAJOR:MINOR`，其中主要和次要数字是十六进制格式，不带 `0x` 前缀。
* `skbqueue` 选项是一个简单的十进制数字。

例如，创建和添加集合的命令如下：

```sh
ipset create foo hash:ip skbinfo
ipset add foo skbmark 0x1111/0xff00ffff skbprio 1:10 skbqueue 10
```
5. **hashsize**

这个参数适用于所有哈希类型集合的创建命令。它定义了集合的初始哈希大小，默认值为 1024。哈希大小必须是 2 的幂，如果给定的大小不是 2 的幂，内核会自动四舍五入到最接近的正确值。例如：

```sh
ipset create test hash:ip hashsize 1536
```
6. **maxelem**

这个参数对于所有哈希类型集合的创建命令都是有效的。它定义了可以存储在集合中的元素的最大数量，默认值为 65536。例如：

```sh
ipset create test hash:ip maxelem 2048
```
7. **family { inet | inet6 }**

这个参数对于除 `hash:mac` 外的所有哈希类型集合的创建命令都是有效的。它定义了要存储在集合中的 IP 地址的协议族。默认是 `inet`，即 IPv4。对于 `inet` 族，可以通过指定范围或 IPv4 地址的网络来添加或删除多个条目。例如：

```sh
ipset create test hash:ip family inet6
```

这条命令创建了一个只接受 IPv6 地址的哈希集合。

8. **nomatch**:
当使用哈希集合类型（能够存储网络类型数据，例如 `hash:*net*`）添加条目时，支持可选的 `nomatch` 选项。
在集合中匹配元素时，标记为 `nomatch` 的条目将被跳过，就好像这些条目没有被添加到集合中一样。这使得建立带有例外的集合成为可能。
当使用 `ipset` 测试元素时，会考虑 `nomatch` 标志。如果要测试集合中标记为 `nomatch` 的元素是否存在，则必须指定该标志。

9. **forceadd**:
所有哈希集合类型在创建集合时都支持可选的 `forceadd` 参数。
当使用这个选项创建的集合已满时，下一次的添加操作可能会成功，并随机剔除集合中的一个现有条目，从而为新条目腾出空间。
示例命令：`ipset create foo hash:ip forceadd`。这条命令创建一个名为 `foo` 的哈希 IP 集合，并启用 `forceadd` 选项。

## SET 类型

### bitmap:ip

bitmap:ip 集合类型使用内存范围来存储 IPv4 主机（默认为）或 IPv4 网络地址。bitmap:ip 类型的集合可以存储最多 65536 个条目。

**创建选项（CREATE-OPTIONS）**
:= 范围 fromip-toip|ip/cidr [ 网关掩码 cidr ] [ 超时值 ] [ 计数器 ] [ 注释 ] [ skbinfo ]

* **范围 fromip-toip|ip/cidr**：从指定的 IPv4 地址范围或网络中创建一个集合。集合的大小（条目数）不能超过最大限制 65536 个元素。

```shell
       CREATE-OPTIONS := range fromip-toip|ip/cidr [ netmask cidr ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := { ip | fromip-toip | ip/cidr }

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := { ip | fromip-toip | ip/cidr }

       TEST-ENTRY := ip
```

1. **必选创建选项（Mandatory create options）**:

* range fromip-toip|ip/cidr：从指定的 IPv4 地址范围或网络中创建集合。该范围的大小（以条目计）不能超过 65536 个元素的限制。

2. **可选创建选项（Optional create options）**:

* netmask cidr：当指定了可选的网关掩码参数时，将在集合中存储网络地址而不是 IP 主机地址。cidr 前缀值必须在 1-32 之间。一个 IP 地址将在集合中，如果通过网络地址（通过使用指定的网关掩码对地址进行屏蔽）可以找到在集合中的话。

3. **bitmap:ip 类型支持在一个命令中添加或删除多个条目**。

4. **示例（Examples）**:

1. 创建名为 foo 的 bitmap:ip 类型的 IP 集合，其范围是 192.168.0.0/16。
```
ipset create foo bitmap:ip range 192.168.0.0/16
```

2. 向 foo 集合中添加条目 192.168.1/24。
```
ipset add foo 192.168.1/24
```

3. 对 foo 集合进行测试，检查是否包含 IP 地址 192.168.1.1。
```
ipset test foo 192.168.1.1
```

### bitmap:ip,mac 类型

**bitmap:ip,mac 集合类型**使用内存范围来存储 IPv4 地址和 MAC 地址对。bitmap:ip,mac 类型的集合可以存储最多 65536 个条目。

1. **创建选项（CREATE-OPTIONS）**
```shell
       CREATE-OPTIONS := range fromip-toip|ip/cidr [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := ip[,macaddr]

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := ip[,macaddr]

       TEST-ENTRY := ip[,macaddr]
```
1. **必选创建选项（Mandatory options）**

* range fromip-toip|ip/cidr：从指定的 IPv4 地址范围或网络中创建集合。集合的范围大小不能超过最大 65536 个条目的限制。

2. **bitmap:ip,mac 类型的特殊性**

在于在添加/删除/测试集合中的条目时，MAC 部分可以省略。如果我们添加一个没有指定 MAC 地址的条目，那么当条目第一次与内核匹配时，它会自动用数据包的源 MAC 地址填充缺失的 MAC 地址。如果条目指定了超时值，则当 IP 和 MAC 地址对完整时开始计时器。

这种类型的集合要求集合的匹配和 SET 目标 netfilter 内核模块中的两个源/目标参数，并且在匹配和添加或删除条目时，第二个必须是源，因为集合匹配和 SET 目标只能访问源 MAC 地址。

3. **示例（Examples）**:

1. 创建名为 foo 的 bitmap:ip,mac 类型的 IP 和 MAC 地址集合，其范围是 192.168.0.0/16。
```sh
ipset create foo bitmap:ip,mac range 192.168.0.0/16
```

2. 向 foo 集合中添加条目，IP 地址为 192.168.1.1，MAC 地址为 12:34:56:78:9A:BC。
```sh
ipset add foo 192.168.1.1,12:34:56:78:9A:BC
```

3. 对 foo 集合进行测试，检查是否包含 IP 地址 192.168.1.1。即使未指定 MAC 地址，测试仍然有效。
```sh
ipset test foo 192.168.1.1
```
### bitmap:port 类型

**bitmap:port 集合类型**使用内存范围来存储端口号。这种类型的集合可以存储最多 65536 个端口。

```shell
       CREATE-OPTIONS := range fromport-toport [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := { [proto:]port | [proto:]fromport-toport }

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := { [proto:]port | [proto:]fromport-toport }

       TEST-ENTRY := [proto:]port
```
1. **必选创建选项（Mandatory options）**

* range [proto:]fromport-toport：从指定的端口范围创建集合。这里，“协议”仅在服务名用作端口且该名称不是 TCP 服务时需要指定。

2. **集合匹配和 SET 目标 netfilter 内核模块**

集合匹配和 SET 目标 netfilter 内核模块将存储的数字解释为 TCP 或 UDP 端口号。

3. **示例（Examples）**:

1. 创建名为 foo 的 bitmap:port 类型的集合，范围是 0 到 1024 的端口。
```sh
ipset create foo bitmap:port range 0-1024
```

2. 向 foo 集合中添加 TCP 端口 80。
```sh
ipset add foo 80
```

3. 测试 foo 集合是否包含 TCP 端口 80。
```sh
ipset test foo 80
```
4. 使用服务名作为端口名称删除某个特定的 UDP 服务，如果服务名在 TCP 服务列表中不存在。这里 `[macon-udp]` 和 `[tn-tl-w2]` 是假设的服务名示例。
```sh
ipset del foo udp:[macon-udp]-[tn-tl-w2]
```
这段文本描述了一个名为“hash:ip”的集合类型（set type）及其相关的创建（CREATE-OPTIONS）、添加（ADD-ENTRY/ADD-OPTIONS）、删除（DEL-ENTRY）和测试（TEST-ENTRY）操作。以下是对这段文本的详细解释：

### hash:ip 集合类型

这是一个使用哈希来存储IP主机地址（默认为此）或网络地址的集合类型。在hash:ip类型的集合中，无法存储值为零的IP地址。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ netmask cidr ] [ timeout value ] [ counters ] [ comment ]  [
       skbinfo ]

       ADD-ENTRY := ipaddr

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := ipaddr

       TEST-ENTRY := ipaddr
```

1. **可选的创建选项 netmask cidr**：

当指定了可选的netmask参数时，集合将存储网络地址而不是IP主机地址。CIDR前缀值对于IPv4必须在1到32之间，对于IPv6则在1到128之间。如果一个IP地址的网络地址（通过使用netmask对地址进行掩码操作得到的结果）能在集合中找到，那么这个IP地址就存在于集合中。
```shell

ipset create foo hash:ip netmask 30
ipset add foo 192.168.1.0/24
ipset test foo 192.168.1.2
```
### hash:mac 集合类型

这是一种使用哈希来存储MAC地址的集合类型。值为零的MAC地址不能存储在`hash:mac`类型的集合中。

```shell
       CREATE-OPTIONS := [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := macaddr

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := macaddr

       TEST-ENTRY := macaddr
```

1. **示例**：

```shell
ipset create foo hash:mac # 创建一个名为`foo`的`hash:mac`类型集合。
ipset add foo 01:02:03:04:05:06 # 向名为`foo`的集合中添加MAC地址`01:02:03:04:05:06`。
ipset test foo 01:02:03:04:05:06 # 测试名为`foo`的集合是否包含MAC地址`01:02:03:04:05:06`。
```
### hash:net 类型
`hash:net`类型使用哈希表来存储不同大小的IP网络地址。
这种类型的集合不能存储前缀大小为0的网络地址。

```shell
CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]
ADD-ENTRY := netaddr
ADD-OPTIONS := [ timeout value ] [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value  ]  [  skbqueue
value ]
DEL-ENTRY := netaddr
TEST-ENTRY := netaddr
where netaddr := ip[/cidr]
```
在添加、删除或测试条目时，如果没有指定CIDR前缀参数，则假定主机前缀值。在添加或删除条目时，会添加或删除精确元素，并且内核不会检查重叠元素。在测试条目时，如果测试了主机地址，则内核会尝试匹配添加到集合中的网络主机地址，并相应地报告结果。
从netfilter匹配点的视角来看，搜索匹配总是从集合中的最小网块大小（最特定的前缀）开始，到最大的一个（最不特定的前缀）结束。当通过SET netfilter目标向集合添加或删除IP地址时，它将被添加到集合中可以找到的最特定的前缀，或者在集合为空时通过主机前缀值进行添加或删除。
查找时间随添加到集合中的不同前缀值的数量而线性增长。

```shell
ipset create foo hash:net
ipset add foo 192.168.0.0/24
ipset add foo 10.1.0.0/16
ipset add foo 192.168.0/24
ipset add foo 192.168.0/30 nomatch
```

### hash:net,net
hash:net,net类型集使用哈希来存储不同大小的IP网络地址对。请注意，第一个参数优先于第二个参数，因此如果存在更具体的第一个参数和合适的第二个参数，不匹配条目可能会无效。具有零前缀大小的网络地址不能存储在这种类型的集合中。

```shell
CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]
ADD-ENTRY := netaddr,netaddr
ADD-OPTIONS := [ timeout value ] [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value  ]  [  skbqueue
value ]
DEL-ENTRY := netaddr,netaddr
TEST-ENTRY := netaddr,netaddr
where netaddr := ip[/cidr]
```
在添加、删除或测试条目时，如果没有指定cidr前缀参数，则假定主机前缀值。在添加或删除条目时，精确的元素会被添加或删除，并且内核不会检查重叠元素。在测试条目时，如果测试了主机地址，则内核会尝试匹配添加到集合中的网络并相应地报告结果。

从集合netfilter匹配的角度来看，搜索匹配总是从最小的网块大小（最具体的前缀）开始，到最大的一个（最不具体的前缀）结束，且第一个参数具有优先权。通过SET netfilter目标向集合添加或删除IP地址时，它将被添加到集合中可以找到的最具体的前缀，或者在集合为空时通过主机前缀值进行添加或删除。查找时间随着添加到集合中的不同前缀值的数量而线性增长。第一参数中的不同前缀值数量进一步增加了这一点，因为每个主要前缀都会遍历次要前缀列表。

示例：

```shell
ipset create foo hash:net,net
ipset add foo 192.168.0.0/24,10.0.1.0/24
ipset add foo 10.1.0.0/16,10.255.0.0/24
ipset add foo 192.168.0/24,192.168.54.0-192.168.54.255
ipset add foo 192.168.0/30,192.168.64/30 nomatch
```
在匹配上述集合中的元素时，所有IP地址将从网络192.168.0.0/24<->10.0.1.0/24、10.1.0.0/16<->10.255.0.0/24和192.168.0/24<->192.168.54.0/24匹配，但来自192.168.0/30<->192.168.64/30的除外。

### hash:ip,port
`hash:ip,port`类型使用哈希来存储IP地址和端口号的配对。端口号与协议一起解释（默认为TCP），并且不能使用零协议编号。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := ipaddr,[proto:]port

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := ipaddr,[proto:]port

       TEST-ENTRY := ipaddr,[proto:]port
```

元素中的`[proto:]port`部分可以表示为以下形式，其中范围变化在添加或删除条目时有效： 

`portname[-portname]`
TCP端口或以TCP端口标识符表达的端口范围，来自/etc/services 

`portnumber[-portnumber]`
以TCP端口号表达的TCP端口或端口范围 

`tcp|sctp|udp|udplite:portname|portnumber[-portname|portnumber]`
TCP、SCTP、UDP或UDPLITE端口或以端口名称或端口号表达的端口范围 

`icmp:codename|type/code`
ICMP的别名或type/code。可以通过帮助命令列出支持的ICMP别名标识符。 

`icmpv6:codename|type/code`
ICMPv6的别名或type/code。可以通过帮助命令列出支持的ICMPv6别名标识符。 

`proto:0` 
所有其他协议，作为来自/etc/protocols的标识符或编号。伪端口号必须为零。 

hash:ip,port类型的集合需要集合匹配的src/dst参数和目标内核模块的两个SET。 

示例： 
```shell
ipset create foo hash:ip,port 
ipset add foo 192.168.1.0/24,80-82 
ipset add foo 192.168.1.1,udp:53 
ipset add foo 192.168.1.1,vrrp:0 
ipset test foo 192.168.1.1,80 
```

### hash:net,port
   
`hash:net,port`设置类型使用哈希来存储不同大小的IP网络地址和端口对。端口号与协议（默认为TCP）一起解释，不能使用零协议编号。也不接受前缀大小为零的网络地址。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]
       ADD-ENTRY := netaddr,[proto:]port
       ADD-OPTIONS  :=  [ timeout value ]  [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue
       value ]
       DEL-ENTRY := netaddr,[proto:]port
       TEST-ENTRY := netaddr,[proto:]port
       where netaddr := ip[/cidr]
```

对于元素的`netaddr`部分，请参阅`hash:net`设置类型的描述。对于元素的[proto:]port部分，请参阅`hash:ip,port`设置类型的描述。

在添加、删除或测试条目时，如果未指定cidr前缀参数，则假定为主机前缀值。在添加或删除条目时，会添加或删除精确的元素，并且内核不会检查重叠的元素。当测试条目时，如果测试主机地址，则内核会尝试匹配添加到集合中的网络主机地址，并相应地报告结果。
从集合netfilter的匹配点来看，匹配搜索始终从最小的网段大小（最特定的前缀）开始，到添加到集合中的最大的一个（最不特定的前缀）。当通过SET netfilter目标添加或删除IP地址时，它将被添加到通过集合中找到的最特定的前缀，或在集合为空时通过主机前缀值添加或删除。查找时间随着添加到集合中的不同前缀值的数量而线性增长。
示例：
```shell

ipset create foo hash:net,port
ipset add foo 192.168.0/24,25 
ipset add foo 10.1.0.0/16,80 
ipset test foo 192.168.0/24,25 
```

### hash:ip,port,ip
`hash:ip,port,ip`类型使用哈希来存储IP地址、端口号和第二个IP地址的三元组。端口号是与协议一起解释的（默认为TCP），并且不能使用零协议编号。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := ipaddr,[proto:]port,ip

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := ipaddr,[proto:]port,ip

       TEST-ENTRY := ipaddr,[proto:]port,ip
```

对于元素中的第一个ipaddr和[proto:]port部分，请参阅hash:ip,port集合类型的描述。

hash:ip,port,ip类型的集合需要集合匹配的三个src/dst参数和SET目标内核模块。

示例：
```shell
ipset create foo hash:ip,port,ip
ipset add foo 192.168.1.1,80,10.0.0.1
ipset test foo 192.168.1.1,udp:53,10.0.0.1
```

### hash:ip,port,net

`hash:ip,port,net` 集合类型使用哈希来存储IP地址、端口号和IP网络地址三元组。端口号与协议（默认为TCP）一起解释，不能使用零协议号。带有零前缀大小的网络地址也不能存储。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := ipaddr,[proto:]port,netaddr

       ADD-OPTIONS  :=  [ timeout value ]  [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue
       value ]

       DEL-ENTRY := ipaddr,[proto:]port,netaddr

       TEST-ENTRY := ipaddr,[proto:]port,netaddr

       where netaddr := ip[/cidr]
```

对于ipaddr和[proto:]port的部分，请参阅hash:ip,port集合类型的描述。对于元素的netaddr部分，请参阅hash:net集合类型的描述。

从集合netfilter的匹配点来看，查找匹配总是从最小的网络块大小（最特定的cidr）开始，到添加到集合中的最大的一个（最不特定的cidr）。当通过SET netfilter目标添加/删除三元组时，它将被添加到集合中找到的最特定的cidr，如果集合为空，则通过主机cidr值添加/删除。

查找时间随着添加到集合中的不同cidr值的数量而线性增长。

hash:ip,port,net类型的集合需要set match和SET目标内核模块的三个src/dst参数。

示例：

```shell
ipset create foo hash:ip,port,net
ipset add foo 192.168.1,80,10.0.0/24
ipset add foo 192.168.2,25,10.1.0.0/16
ipset test foo 192.168.1,80.10.0.0/24
```
### hash:ip,mark

`hash:ip,mark`该hash:ip,mark集合类型使用哈希来存储IP地址和包标记对。

```shell
       CREATE-OPTIONS  := [ family { inet | inet6 } ] | [ markmask value ] [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ]
       [ skbinfo ]

       ADD-ENTRY := ipaddr,mark

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := ipaddr,mark

       TEST-ENTRY := ipaddr,mark
```

可选创建选项：
`markmask value`
允许您设置您对数据包标记感兴趣的位。此值随后用于执行每个添加的标记的位与操作。标记掩码可以是介于1和4294967295之间的任何值，默认情况下所有32位都被设置。
标记可以是介于0和4294967295之间的任何值。

hash:ip,mark类型的集合需要集合匹配的源/目标参数和目标内核模块SET。
示例：
```shell
ipset create foo hash:ip,mark
ipset add foo 192.168.1.0/24,555
ipset add foo 192.168.1.1,0x63
ipset add foo 192.168.1.1,111236
```

### hash:net,port,net

这段文本是关于某种网络配置或网络规则的描述，涉及到了IP地址、端口号和CIDR值的使用。以下是对这段文本的翻译：

**hash:net,port,net 配置类型说明**

hash:net,port,net 类型的设置与 hash:ip,port,net 类型相似，但它接受第一个和最后一个参数的值作为CIDR值。如果希望匹配所有目的地的端口，可以允许子网使用 /0。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := netaddr,[proto:]port,netaddr

       ADD-OPTIONS := [ timeout value ]  [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ]  [  skbqueue
       value ]

       DEL-ENTRY := netaddr,[proto:]port,netaddr

       TEST-ENTRY := netaddr,[proto:]port,netaddr

       where netaddr := ip[/cidr]
```

从 netfilter 匹配点的角度来看，搜索匹配总是从最小的 netblock 大小（最具体的 CIDR）开始，到添加到集合中的最大的一个（最不具体的 CIDR）。当通过 SET netfilter 目标添加或删除集合中的三元组时，它将被添加到集合中可以找到的最具体的 CIDR，或者在集合为空时由主机 CIDR 值决定。在进行最特定查找时，第一个子网具有优先权，就像 hash:net,net 一样。查找时间会随着添加到集合中的不同 CIDR 值的数量和每个主要次要的 CIDR 值数量而线性增长。hash:net,port,net 类型的集合需要匹配集合和 SET 目标内核模块的三个 src/dst 参数。示例如下：

```shell
              ipset create foo hash:net,port,net
              ipset add foo 192.168.1.0/24,0,10.0.0/24
              ipset add foo 192.168.2.0/24,25,10.1.0.0/16
              ipset test foo 192.168.1.1,80,10.0.0.1
```

### hash:net,iface

`hash:net,iface`集类型使用哈希来存储不同大小的IP网络地址和接口名称对。

```shell
       CREATE-OPTIONS := [ family { inet | inet6 } ] | [ hashsize value ] [ maxelem value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]
       ADD-ENTRY := netaddr,[physdev:]iface
       ADD-OPTIONS := [ timeout value ]  [ nomatch ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ]  [  skbqueue
       value ]
       DEL-ENTRY := netaddr,[physdev:]iface
       TEST-ENTRY := netaddr,[physdev:]iface
       where netaddr := ip[/cidr]
```

这里的`netaddr`可以是IP地址和网络前缀（CIDR格式）。如果没有指定CIDR前缀参数，则假定为主机前缀值。添加或删除条目时，添加或删除的精确元素不会被内核检查是否有重叠。测试条目时，如果测试主机地址，内核会尝试匹配添加到集合中的网络，并报告相应的结果。

从netfilter匹配的角度来看，搜索匹配总是从最小的网络块大小（最特定的前缀）开始，到添加到集合中的最大的一个（最不特定的前缀）。
向集合中添加或删除IP地址时，它会通过集合中找到的最特定的前缀添加或删除，如果集合为空，则通过主机前缀值。
该集合的第二方向参数对应于入站/出站接口：src对应入站接口（类似于iptables的-i标志），而dst对应出站接口（类似于iptables的-o标志）。
当接口被标记为phys-dev时，该接口被解释为入站/出站的桥接端口。查找时间随着添加到集合中的不同前缀值的数量而线性增长。
该集合的内部限制是，在同一个集合中，不能存储超过64个不同接口的网络前缀。

最后给出了一些示例命令，展示了如何使用这些命令创建集合、添加条目、测试条目等。

```shell
ipset create foo hash:net,iface
ipset add foo 192.168.0/24,eth0
ipset add foo 10.1.0.0/16,eth1
ipset test foo 192.168.0/24,eth0
```
### list:set

它使用一个简单列表，你可以在这个列表中存储集合名称。

```shell
       CREATE-OPTIONS := [ size value ] [ timeout value ] [ counters ] [ comment ] [ skbinfo ]

       ADD-ENTRY := setname [ { before | after } setname ]

       ADD-OPTIONS := [ timeout value ] [ packets value ] [ bytes value ] [ comment string ] [ skbmark value ] [ skbprio value ] [ skbqueue value ]

       DEL-ENTRY := setname [ { before | after } setname ]

       TEST-ENTRY := setname [ { before | after } setname ]
```
可选创建选项：
   `size value`
          列表的大小，默认为8。自ipset版本6.24起，该参数被忽略。

       By the ipset command you  can add, delete and test set names in a list:set type of set.

  通过netfilter的set match或SET目标，您可以在添加到列表的集合中测试、添加或删除条目：集合类型。
  匹配将尝试在集合中找到匹配的条目，而目标将尝试向其可添加的第一个集合中添加条目。匹配和目标的选项方向数量很重要：
  如果指定了比所需参数更多的集合将被跳过，而参数相等或更少的集合将被检查，并添加/删除元素。例如，如果a和b是list:set类型的集合，则在命令中：

`iptables -m set --match-set a src，dst -j SET --add-set b src，dst`

匹配和目标将跳过a和b中存储数据三元的任何集合，但将匹配所有具有单个或双数据存储的集合中的集合，并在第一个成功集合处停止匹配，
并将src添加到b的第一个单数或src，dst添加到b的第一个双数据存储集合中，其中可以添加该条目。您可以想象list:set类型的集合是集合元素的顺序并集。

请注意：通过ipset命令，您可以添加、删除和测试list:set类型的集合中的集合名称，而不是测试集合成员（如IP地址）的存在。
## 一般限制
使用哈希方法时，零值集合条目无法使用。不能使用零协议值和端口。
## 注释
如果您想要存储给定网络中相同大小的子网（例如从/8网络中存储/24块），请使用位图:ip集合类型。如果您想要存储随机相同大小的网段（例如随机/24块），请使用哈希:ip集合类型。如果您拥有随机大小的网段，请使用哈希:net。
向后兼容性得到了保持，旧版ipset语法仍然得到支持。
iptree和iptreemap集合类型已被移除：如果您引用它们，它们将自动被替换为哈希:ip类型的集合。
## 诊断
各种错误消息将打印到标准错误输出。正确的功能退出代码为0。


# ipset和iptables：

在iptables中使用ipset，只要加上-m set --match-set即可。（这里只做简单的介绍）

目的ip使用ipset（ipset集合为bbb）
iptables -I INPUT -s 192.168.100.36 -m set --match-set bbb dst -j DROP

源ip使用ipset（ipset集合为aaa）

iptables -I INPUT -m set --match-set aaa src -d 192.168.100.36 -j DROP

源和目的都使用ipset（源ip集合为aaa，目的ip集合为bbb）

iptables -I INPUT -m set --match-set aaa src -m set --match-set bbb dst -j DROP
