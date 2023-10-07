# 网桥

# 核心概念 
## 转发表

| MAC address       | port | age |
| ----------------- | ---- | --- |
| a0:11:22:33:44:55 | 1    | 10  |
| b1:22:22:33:44:55 | 2    | 20  |

- 转发表
 - 每个网桥维护一个MAC转发表
 - 转发表和路由表类似，转发表根据数据包的目的MAC查询转发表，如果匹配，根据转发表的port发送数据包
 - 转发表每一项包含 MAC地址，part , age, 其中 port表示索引号，如eth0 ,eth1

- 地址学习
 - 从某个port入栈的数据包的源MAC域，说明使用此MAC的主机可以从此port访问
 - 每个帧被接受时，根据他的源MAC和port更新转发表
 - 转发表所有项在一段时间后自动删除，15秒

## STP


## VLAN


# 桥接受skb代码分析
![](./pic/61.jpg)

## br_init
```c
static int __init br_init(void)
	// 注册STP协议
	err = stp_proto_register(&br_stp_proto);

	// 初始化转发数据库
	err = br_fdb_init();

	// 初始化桥 netfilter
	err = br_nf_core_init();

	// 初始化事件通知
	err = register_netdevice_notifier(&br_device_notifier);
	err = register_switchdev_notifier(&br_switchdev_notifier);

	// 初始化桥netlink
	err = br_netlink_init();

	// 初始化桥ioctl
	brioctl_set(br_ioctl_deviceless_stub);
```

# 核心数据结构
### net_bridge
```c
struct net_bridge {
	spinlock_t			lock;
	spinlock_t			hash_lock;
	struct list_head		port_list; // 端口链表
	struct net_device		*dev;    // 桥设备，这是虚拟设备
	struct pcpu_sw_netstats		__percpu *stats;
	unsigned long			options;
	/* These fields are accessed on each packet */
#ifdef CONFIG_BRIDGE_VLAN_FILTERING
	__be16				vlan_proto;
	u16				default_pvid;
	struct net_bridge_vlan_group	__rcu *vlgrp;
#endif

	struct rhashtable		fdb_hash_tbl;
#if IS_ENABLED(CONFIG_BRIDGE_NETFILTER)
	union {
		struct rtable		fake_rtable;
		struct rt6_info		fake_rt6_info;
	};
#endif
	u16				group_fwd_mask;
	u16				group_fwd_mask_required;

	/* STP */
	bridge_id			designated_root;
	bridge_id			bridge_id;
	unsigned char			topology_change;
	unsigned char			topology_change_detected;
	u16				root_port;
	unsigned long			max_age;
	unsigned long			hello_time;
	unsigned long			forward_delay;
	unsigned long			ageing_time;
	unsigned long			bridge_max_age;
	unsigned long			bridge_hello_time;
	unsigned long			bridge_forward_delay;
	unsigned long			bridge_ageing_time;
	u32				root_path_cost;

	u8				group_addr[ETH_ALEN];

	enum {
		BR_NO_STP, 		/* no spanning tree */
		BR_KERNEL_STP,		/* old STP in kernel */
		BR_USER_STP,		/* new RSTP in userspace */
	} stp_enabled;

#ifdef CONFIG_BRIDGE_IGMP_SNOOPING

	u32				hash_max;

	u32				multicast_last_member_count;
	u32				multicast_startup_query_count;

	u8				multicast_igmp_version;
	u8				multicast_router;
#if IS_ENABLED(CONFIG_IPV6)
	u8				multicast_mld_version;
#endif
	spinlock_t			multicast_lock;
	unsigned long			multicast_last_member_interval;
	unsigned long			multicast_membership_interval;
	unsigned long			multicast_querier_interval;
	unsigned long			multicast_query_interval;
	unsigned long			multicast_query_response_interval;
	unsigned long			multicast_startup_query_interval;

	struct rhashtable		mdb_hash_tbl;
	struct rhashtable		sg_port_tbl;

	struct hlist_head		mcast_gc_list;
	struct hlist_head		mdb_list;
	struct hlist_head		router_list;

	struct timer_list		multicast_router_timer;
	struct bridge_mcast_other_query	ip4_other_query;
	struct bridge_mcast_own_query	ip4_own_query;
	struct bridge_mcast_querier	ip4_querier;
	struct bridge_mcast_stats	__percpu *mcast_stats;
#if IS_ENABLED(CONFIG_IPV6)
	struct bridge_mcast_other_query	ip6_other_query;
	struct bridge_mcast_own_query	ip6_own_query;
	struct bridge_mcast_querier	ip6_querier;
#endif /* IS_ENABLED(CONFIG_IPV6) */
	struct work_struct		mcast_gc_work;
#endif

	struct timer_list		hello_timer;
	struct timer_list		tcn_timer;
	struct timer_list		topology_change_timer;
	struct delayed_work		gc_work;
	struct kobject			*ifobj;
	u32				auto_cnt;

#ifdef CONFIG_NET_SWITCHDEV
	int offload_fwd_mark;
#endif
	struct hlist_head		fdb_list;

#if IS_ENABLED(CONFIG_BRIDGE_MRP)
	struct list_head		mrp_list;
#endif
};

```

## net_bridge_port
```c
struct net_bridge_port {
	struct net_bridge		*br; // 端口所属的桥
	struct net_device		*dev; // 端口的设备
	struct list_head		list;

	unsigned long			flags;
#ifdef CONFIG_BRIDGE_VLAN_FILTERING
	struct net_bridge_vlan_group	__rcu *vlgrp;
#endif
	struct net_bridge_port		__rcu *backup_port; // 备用端口

	/* STP */
	u8				priority;
	u8				state;
	u16				port_no;
	unsigned char			topology_change_ack;
	unsigned char			config_pending;
	port_id				port_id;
	port_id				designated_port;
	bridge_id			designated_root;
	bridge_id			designated_bridge;
	u32				path_cost;
	u32				designated_cost;
	unsigned long			designated_age;

	struct timer_list		forward_delay_timer;
	struct timer_list		hold_timer;
	struct timer_list		message_age_timer;
	struct kobject			kobj;
	struct rcu_head			rcu;

#ifdef CONFIG_BRIDGE_IGMP_SNOOPING
	struct bridge_mcast_own_query	ip4_own_query;
#if IS_ENABLED(CONFIG_IPV6)
	struct bridge_mcast_own_query	ip6_own_query;
#endif /* IS_ENABLED(CONFIG_IPV6) */
	unsigned char			multicast_router;
	struct bridge_mcast_stats	__percpu *mcast_stats;
	struct timer_list		multicast_router_timer;
	struct hlist_head		mglist;
	struct hlist_node		rlist;
#endif

#ifdef CONFIG_SYSFS
	char				sysfs_name[IFNAMSIZ];
#endif

#ifdef CONFIG_NET_POLL_CONTROLLER
	struct netpoll			*np;
#endif
#ifdef CONFIG_NET_SWITCHDEV
	int				offload_fwd_mark;
#endif
	u16				group_fwd_mask;
	u16				backup_redirected_cnt;

	struct bridge_stp_xstats	stp_xstats;
}
```

## recv data
在L2层接受skb时，如果skb->dev已经加入了桥(skb->dev->rx_handler不为空)，

则说明此设备作为桥端口使用，

则数据包首先交给桥处理，如果没有加入桥才上传给上层协议

```c
// 网卡驱动调用 netif_receive_skb 传递skb
int netif_receive_skb(struct sk_buff *skb)
	ret = netif_receive_skb_internal(skb);
		ret = __netif_receive_skb(skb);

			... // 给所有嗅探器发送skb的拷贝

			// 处理桥
			rx_handler = rcu_dereference(skb->dev->rx_handler);
			rx_handler(&skb); //  skb->dev->rx_handler 是多少呢？

			... // 给所有匹配的上层协议发送skb的拷贝
```

### dev->rx_handler

当设备加入桥时，dev->rx_handler 通常被设置为为 br_handle_frame

```c
int br_add_if(struct net_bridge *br, struct net_device *dev,
	      struct netlink_ext_ack *extack)
	err = netdev_rx_handler_register(dev, br_get_rx_handler(dev), p);

rx_handler_func_t *br_get_rx_handler(const struct net_device *dev)
	if (netdev_uses_dsa(dev))
		return br_handle_frame_dummy;
	return br_handle_frame;

int netdev_rx_handler_register(struct net_device *dev,
			       rx_handler_func_t *rx_handler,
			       void *rx_handler_data)
		rcu_assign_pointer(dev->rx_handler_data, rx_handler_data);
		rcu_assign_pointer(dev->rx_handler, rx_handler);
```

### br_handle_frame
```c
static rx_handler_result_t br_handle_frame(struct sk_buff **pskb)

	struct net_bridge_port *p;
	struct sk_buff *skb = *pskb;
	const unsigned char *dest = eth_hdr(skb)->h_dest;

	// 如果skb是回环数据包，不处理
	if (unlikely(skb->pkt_type == PACKET_LOOPBACK))
		return RX_HANDLER_PASS;

	// 获得目的MAC
	const unsigned char *dest = eth_hdr(skb)->h_dest;

	// 丢弃非法源MAC的包，比如源MAC为 广播地址
	if (!is_valid_ether_addr(eth_hdr(skb)->h_source))
		goto drop;

	// net_bridge_port 为描述桥的数据结构
	p = br_port_get_rcu(skb->dev);

	// 如果 当前skb被共享 skb->users != 1
	// 则克隆skb，并返回新的skb
	skb = skb_share_check(skb, GFP_ATOMIC);

	memset(skb->cb, 0, sizeof(struct br_input_skb_cb));

	// 获得桥端口
	p = br_port_get_rcu(skb->dev);

	// 如果是link local数据包，比如 STP包
	if (unlikely(is_link_local_ether_addr(dest))) {
		...
		return ...;
	}

	// 一般数据包

forward:
	switch (p->state) {
	// 只有当桥处于学习或转发状态才接受数据包
	case BR_STATE_FORWARDING:
	case BR_STATE_LEARNING:
		// 判断是否是发送给本桥的数据包
		if (ether_addr_equal(p->br->dev->dev_addr, dest))
			skb->pkt_type = PACKET_HOST;
	
		// 交给nf处理
		return nf_hook_bridge_pre(skb, pskb);
	default:
drop:
		kfree_skb(skb);
	}
	return RX_HANDLER_CONSUMED;

```

## Forward data
###  nf_hook_bridge_pre
```c
// 如果没有开启 CONFIG_NETFILTER_FAMILY_BRIDGE 则非常简单
static int nf_hook_bridge_pre(struct sk_buff *skb, struct sk_buff **pskb)
	br_handle_frame_finish(net, NULL, skb);
```

### br_handle_frame_finish
```c
int br_handle_frame_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
	struct net_bridge_port *p = br_port_get_rcu(skb->dev);
	enum br_pkt_type pkt_type = BR_PKT_UNICAST;
	struct net_bridge_fdb_entry *dst = NULL;
	struct net_bridge_mdb_entry *mdst;
	bool local_rcv, mcast_hit = false;
	struct net_bridge *br;
	u16 vid = 0;
	u8 state;

	// 没有端口或端口状态为禁用，丢弃包
	if (!p || p->state == BR_STATE_DISABLED)
		goto drop;

	// 更新转发表
	br = p->br;
	if (p->flags & BR_LEARNING)
		br_fdb_update(br, p, eth_hdr(skb)->h_source, vid, 0);

	// 如果开启混淆模式，则桥一定接受
	local_rcv = !!(br->dev->flags & IFF_PROMISC);

	// 确定pkt_type，如果是广播，则桥一定接受
	if (is_multicast_ether_addr(eth_hdr(skb)->h_dest)) {
		/* by definition the broadcast is also a multicast address */
		if (is_broadcast_ether_addr(eth_hdr(skb)->h_dest)) {
			pkt_type = BR_PKT_BROADCAST;
			local_rcv = true; 
		} else {
			pkt_type = BR_PKT_MULTICAST;
			if (br_multicast_rcv(br, p, skb, vid))
				goto drop;
		}
	}

	// 如果只是学习状态，则到此为止
	if (state == BR_STATE_LEARNING)
		goto drop;

	// br->dev ，比如 br0，
	// br0不可能加入其他桥，所以其 rx_handler为NULL。
	// 而其他网口可以加入桥，如果加入了桥，则rx_handler不为NULL
	// 这决定了接受到数据包后如何处理，
	// 如果rx_handler为NULL，则做普通设备处理，
	// 否则，做桥设备处理
	BR_INPUT_SKB_CB(skb)->brdev = br->dev; // 注意br->dev->rx_handler为NULL
	BR_INPUT_SKB_CB(skb)->src_port_isolated = !!(p->flags & BR_ISOLATED);

	// 处理邻居协议的数据包
	// 如果开启了IPv4，则会处理ARP协议
	// 否则若开启IPv6，则会处理ipv6的邻居协议 
	if (IS_ENABLED(CONFIG_INET) &&
	    (skb->protocol == htons(ETH_P_ARP) ||
	     skb->protocol == htons(ETH_P_RARP))) {
		br_do_proxy_suppress_arp(skb, br, vid, p);

	} else if (IS_ENABLED(CONFIG_IPV6) &&
		   skb->protocol == htons(ETH_P_IPV6) &&
		   br_opt_get(br, BROPT_NEIGH_SUPPRESS_ENABLED) &&
		   pskb_may_pull(skb, sizeof(struct ipv6hdr) +
				 sizeof(struct nd_msg)) &&
		   ipv6_hdr(skb)->nexthdr == IPPROTO_ICMPV6) {
			struct nd_msg *msg, _msg;

			msg = br_is_nd_neigh_msg(skb, &_msg);
			if (msg)
				br_do_suppress_nd(skb, br, vid, p, msg);
	}

	// 根据数据包类型和目的地址查询转发表，获得转发端口
	switch (pkt_type) {
	case BR_PKT_MULTICAST:
		mdst = br_mdb_get(br, skb, vid);
		if ((mdst || BR_INPUT_SKB_CB_MROUTERS_ONLY(skb)) &&
		    br_multicast_querier_exists(br, eth_hdr(skb))) {
			if ((mdst && mdst->host_joined) ||
			    br_multicast_is_router(br)) {
				local_rcv = true;
				br->dev->stats.multicast++;
			}
			mcast_hit = true;
		} else {
			local_rcv = true;
			br->dev->stats.multicast++;
		}
		break;
	case BR_PKT_UNICAST:
		dst = br_fdb_find_rcu(br, eth_hdr(skb)->h_dest, vid);
	default:
		// BR_PKT_BROADCAST, dst 为NULL，对所有端口进行转发（除了源端口）
		break;
	}

	if (dst) {
		// 单播的情况，dst不为NULL

		unsigned long now = jiffies;

		// 如果查询转发表发现是本地接受，则调用 br_pass_frame_up 接受数据包
		if (test_bit(BR_FDB_LOCAL, &dst->flags))
			return br_pass_frame_up(skb);

		// 桥转发数据包

		if (now != dst->used)
			dst->used = now;
		br_forward(dst->dst, skb, local_rcv, false);

	} else {
		// 广播或组播
		// 如果是广播，则遍历br->port_list，向每个端口发送一个skb
		// 如果是组播，对所有加入组播的端口发送一个skb

		if (!mcast_hit)
			// 不是组播，则当广播处理
			br_flood(br, skb, pkt_type, local_rcv, false);
		else
			// 组播
			br_multicast_flood(mdst, skb, local_rcv, false);
	}

	// 组播，本桥也要接受skb
	if (local_rcv)
		return br_pass_frame_up(skb);
```

### br_forward
```c
// br_forward - forward a packet to a specific port

// br_handle_frame_finish
// 		br_forward(dst->dst, skb, local_rcv, false);

// local_rcv ： true/false
// local_orig : false
void br_forward(const struct net_bridge_port *to,
		struct sk_buff *skb, bool local_rcv, bool local_orig)

	if (unlikely(!to))
		goto out;

	/* redirect to backup link if the destination port is down */
	// 如果转发端口无法使用，则使用备用的端口
	if (rcu_access_pointer(to->backup_port) && !netif_carrier_ok(to->dev)) {
		struct net_bridge_port *backup_port;

		backup_port = rcu_dereference(to->backup_port);
		if (unlikely(!backup_port))
			goto out;
		to = backup_port;
	}

	// 过滤掉不应该转发的情况，
	// 如 数据包源端口和转发端口一样
	//    端口不是转发状态
	if (should_deliver(to, skb)) {

		// 不论是本地接受还是转发，最终都调用 __br_forward
		// 区别是本地接受会对skb进行克隆
		if (local_rcv)
			deliver_clone(to, skb, local_orig);
		else
			__br_forward(to, skb, local_orig);
		return;
	}
```

### deliver_clone
```c
static int deliver_clone(const struct net_bridge_port *prev,
			 struct sk_buff *skb, bool local_orig)
{
	struct net_device *dev = BR_INPUT_SKB_CB(skb)->brdev;

	skb = skb_clone(skb, GFP_ATOMIC);
	if (!skb) {
		dev->stats.tx_dropped++;
		return -ENOMEM;
	}

	__br_forward(prev, skb, local_orig);
	return 0;
}
```

### __br_forward
```c
// local_orig : false
static void __br_forward(const struct net_bridge_port *to,
			 struct sk_buff *skb, bool local_orig)

	struct net_bridge_vlan_group *vg;
	struct net_device *indev;
	struct net *net;
	int br_hook;

	vg = nbp_vlan_group_rcu(to);
	skb = br_handle_vlan(to->br, to, vg, skb);
	if (!skb)
		return;

	indev = skb->dev; // 源设备
	skb->dev = to->dev; // 使用目的端口的设备作为数据包发送的设备

	// 如果是本机发出的包，走 NF_BR_LOCAL_OUT ，
	// 否则走 NF_BR_FORWARD
	if (!local_orig) {
		if (skb_warn_if_lro(skb)) {
			kfree_skb(skb);
			return;
		}
		br_hook = NF_BR_FORWARD;
		skb_forward_csum(skb);
		net = dev_net(indev);
	} else {
		if (unlikely(netpoll_tx_running(to->br->dev))) {
			skb_push(skb, ETH_HLEN);
			if (!is_skb_forwardable(skb->dev, skb))
				kfree_skb(skb);
			else
				br_netpoll_send_skb(to, skb);
			return;
		}
		br_hook = NF_BR_LOCAL_OUT;
		net = dev_net(skb->dev);
		indev = NULL;
	}

	NF_HOOK(NFPROTO_BRIDGE, br_hook,
		net, NULL, skb, indev, skb->dev,
		br_forward_finish);


int br_forward_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
{
	skb->tstamp = 0;
	return NF_HOOK(NFPROTO_BRIDGE, NF_BR_POST_ROUTING,
		       net, sk, skb, NULL, skb->dev,
		       br_dev_queue_push_xmit);

}
```
### br_dev_queue_push_xmit
```c
int br_dev_queue_push_xmit(struct net *net, struct sock *sk, struct sk_buff *skb)
{
	skb_push(skb, ETH_HLEN);

	// 确认设备支持转发
	if (!is_skb_forwardable(skb->dev, skb))
		goto drop;

	br_drop_fake_rtable(skb);

	if (skb->ip_summed == CHECKSUM_PARTIAL &&
	    (skb->protocol == htons(ETH_P_8021Q) ||
	     skb->protocol == htons(ETH_P_8021AD))) {
		int depth;

		if (!vlan_get_protocol_and_depth(skb, skb->protocol, &depth))
			goto drop;

		skb_set_network_header(skb, depth);
	}

	// 发送数据包到 qdisc
	dev_queue_xmit(skb);

	return 0;

drop:
	kfree_skb(skb);
	return 0;
}
```

## local input
```c
static int nf_hook_bridge_pre(struct sk_buff *skb, struct sk_buff **pskb)
	// 接受skb
	return br_pass_frame_up(skb);
```
### br_pass_frame_up
```c
static int br_pass_frame_up(struct sk_buff *skb)

	// 获得桥设备
	struct net_device *indev, *brdev = BR_INPUT_SKB_CB(skb)->brdev;
	// 获得桥
	struct net_bridge *br = netdev_priv(brdev);
	struct net_bridge_vlan_group *vg;
	struct pcpu_sw_netstats *brstats = this_cpu_ptr(br->stats);

	// 更新桥的计数器
	u64_stats_update_begin(&brstats->syncp);
	brstats->rx_packets++;
	brstats->rx_bytes += skb->len;
	u64_stats_update_end(&brstats->syncp);

	vg = br_vlan_group_rcu(br);

	/* Reset the offload_fwd_mark because there could be a stacked
	 * bridge above, and it should not think this bridge it doing
	 * that bridge's work forwarding out its ports.
	 */
	br_switchdev_frame_unmark(skb);

	// 如果没有通过vlan，且桥不是混淆模式，则丢弃skb
	if (!(brdev->flags & IFF_PROMISC) &&
	    !br_allowed_egress(vg, skb)) {
		kfree_skb(skb);
		return NET_RX_DROP;
	}

	indev = skb->dev; // 源设备

	// 使用桥设备作为skb的源设备，
	// 注意brdev->rx_handler为NULL, 因为他没有加入任何桥
	skb->dev = brdev; 

	// 过滤vlan
	skb = br_handle_vlan(br, NULL, vg, skb);
	if (!skb)
		return NET_RX_DROP;

	/* update the multicast stats if the packet is IGMP/MLD */
	br_multicast_count(br, NULL, skb, br_multicast_igmp_type(skb),
			   BR_MCAST_DIR_TX);

	return NF_HOOK(NFPROTO_BRIDGE, NF_BR_LOCAL_IN,
		       dev_net(indev), NULL, skb, indev, NULL,
		       br_netif_receive_skb);
		return netif_receive_skb(skb);

```

### br_netif_receive_skb
```c
static int
br_netif_receive_skb(struct net *net, struct sock *sk, struct sk_buff *skb)
{
	br_drop_fake_rtable(skb);

	// 再次调用 netif_receive_skb ，
	// 由于 skb->dev->rx_handler 此时为NULL，
	// 所以不会进入桥相关，而是传给上层协议
	return netif_receive_skb(skb);
}
```

