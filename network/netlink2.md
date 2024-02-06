# netlink套接字的创建

用户层 , 推荐使用 libnl

`socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE)`

内核层

`netlink_kernel_create()`

## netlink地址结构
```c
struct sockaddr_nl {
	__kernel_sa_family_t	nl_family;	/* 始终为AF_NETLINK	*/
	unsigned short	nl_pad;		/* 始终为zero	*/
	__u32		nl_pid;		// 发送方的进程号，如果为内核态则为0, 相当于端口号
	__u32		nl_groups;	/* multicast groups mask */
};
```

## 内核如何创建netlink套机字
`socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE)`

协议族为 `AF_NETLINK`

数据包类型 `SOCK_RAW / SOCK_DGRAM`

协议类型 `NETLINK_ROUTE`

netlink 支持很多种协议类型，处理route相关的为 `NETLINK_ROUTE`

netlink也有端口号，用户空间使用bind显示设置，通常设置为进程的进程号，如果没有设置或设置为0，内核会自动设置其为线程的进程号

那么内核态如何创建netlink呢，首先要明确要创建处理什么类型的netlink，如路由相关，则使用 `rtnetlink_net_init`
```c
static int __net_init rtnetlink_net_init(struct net *net)
{
	struct sock *sk;
	struct netlink_kernel_cfg cfg = {
		.groups		= RTNLGRP_MAX,
		.input		= rtnetlink_rcv,
		.cb_mutex	= &rtnl_mutex,
		.flags		= NL_CFG_F_NONROOT_RECV,
		.bind		= rtnetlink_bind,
	};

	sk = netlink_kernel_create(net, NETLINK_ROUTE, &cfg);
	if (!sk)
		return -ENOMEM;
	net->rtnl = sk;
	return 0;
}
```

所有类型的netlink套接字都通过 `netlink_kernel_create`创建，

```c
static inline struct sock *
netlink_kernel_create(struct net *net, int unit, struct netlink_kernel_cfg *cfg);
```

最重要的参数是 `cfg->input`, 和 `unit`，

`cfg->input` 用于设置回调函数，此函数用于处理接收到的数据包，可以设置为NULL，

比如`NETLINK_KOBJECT_UEVENT`类型的`nl_sock`不接受用户的输入，就设置为NULL.

`unit` 决定了协议类型

对于内核态的`nl_sock` 不需要设置端口号，其端口号为0.

## nl_table
`netlink_kernel_create`调用 `netlink_insert` 在 `nl_table`中创建一个表项，保存 `nl_sock`。

在传递`nl`消息时，会设置 `nl_table`的查询，调用 `netlink_lookup`，参数为 协议号和端口号

## 为特定类型的消息注册回调函数

通过协议族，协议号，端口号，可以实现数据包到`nl_sock`的路由.

和一般`sock`不同，`nl_sock`要处理数据包，需要提前注册自己的处理函数。

使用 `rtnl_register`, 为特定消息注册处理函数
```c
void rtnl_register(int protocol, int msgtype,
		   rtnl_doit_func doit, rtnl_dumpit_func dumpit,
		   unsigned int flags);
```
protocol : 协议族，通常设置为 `PF_UNSPEC`
msgtype : 如 `RTM_NEWLINK` ... 
doit : 用于添加，删除，修改操作的回调函数
dumpit : 用于检索操作的回调函数

## 发送消息
不同协议的rt，使用不同的发送函数，比如rtnelink消息使用 `rtmsg_ifinfo()`
如 
```c
dev_open()
	rtmsg_ifinfo(RTM_NEWLINK, dev, IFF_UP|IFF_RUNNING, GFP_KERNEL);
		skb = rtmsg_ifinfo_build_skb(type, dev, change, event, flags, new_nsid,
						 new_ifindex);
		rtnl_notify(skb, net, 0, RTNLGRP_LINK, NULL, flags);
```

# 数据包格式
## 数据包头部
```c
struct nlmsghdr {
	__u32		nlmsg_len;	// 包含头部的数据包总长度
	__u16		nlmsg_type;	// 消息类型
	__u16		nlmsg_flags;	/* Additional flags */
	__u32		nlmsg_seq;	// 序列号，用于排列消息，可以不使用
	__u32		nlmsg_pid;	// 源端口，对于内核态的设置为0，用户态通常设置pid
};
```
## 数据包体
紧跟在hdr后的是payload，格式为 类型-长度-值, TLV。
TLV中类型和长度的内存大小是固定的，而值是可变的。
```c
/*
 *  <------- NLA_HDRLEN ------> <-- NLA_ALIGN(payload)-->
 * +---------------------+- - -+- - - - - - - - - -+- - -+
 * |        Header       | Pad |     Payload       | Pad |
 * |   (struct nlattr)   | ing |                   | ing |
 * +---------------------+- - -+- - - - - - - - - -+- - -+
 *  <-------------- nlattr->nla_len -------------->
 */
struct nlattr {
	__u16           nla_len;
	__u16           nla_type;
};
```

## 消息的接受和解析
`genl_rcv_msg`负责接受消息。
如果不是转存，则调用 `nlmsg_parse`解析消息，并调用 `validate_nla`校验合法性

## NETLINK_ROUTE消息
对于 `NETLINK_ROUTE`消息不用于路由，还有多个消息族
LINK 网络接口
ADDR 网络地址
ROUTE 路由
NEIGH 邻居子系统消息
RULE 路由策略
QDISC 排队设备
TCLASS 流量类别
ACTION 数据包操作
NEIGHTBL 邻居表
ADDRLABEL 地址标记
每个消息族又分为三类： 创建，删除，检索
如
`RTM_NEWROUTE`, `RTM_DELROUTE`, `RTM_GETROUTE`
对于LINK还有一个 `RTM_SETLINK` 由于修改









