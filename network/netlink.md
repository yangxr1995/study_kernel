# 简介
netlink 是IP服务协议，一种socket通信方式，用于内核和用户空间双向通信。

# netlink的创建
```c
inet_init
	ip_init
		ip_rt_init
			....
				nl_fib_lookup_init
					struct netlink_kernel_cfg cfg = {
						.input	= nl_fib_input,
					};
					netlink_kernel_create(net, NETLINK_FIB_LOOKUP, &cfg);
```

## netlink_kernel_create
```c
static struct proto netlink_proto = {
	.name	  = "NETLINK",
	.owner	  = THIS_MODULE,
	.obj_size = sizeof(struct netlink_sock),
};


// unit : NETLINK_FIB_LOOKUP
struct sock *
netlink_kernel_create(struct net *net, int unit, struct netlink_kernel_cfg *cfg)
	__netlink_kernel_create(net, unit, THIS_MODULE, cfg);
		// 创建 socket *sock
		sock_create_lite(PF_NETLINK, SOCK_DGRAM, unit, &sock);
		// 创建 netlink_sock
		__netlink_create(net, sock, cb_mutex, unit, 1);
			sock->ops = &netlink_ops;
			// 创建 netlink_sock 大小的空间，作为 sock
			sk = sk_alloc(net, PF_NETLINK, GFP_KERNEL, &netlink_proto, kern);
				sk = sk_prot_alloc(prot, priority | __GFP_ZERO, family);
					sk = kmalloc(prot->obj_size, priority);

			// 初始化并建立 socket 和 sock的关系
			sock_init_data(sock, sk);
				sk->sk_socket = sock;
				sock->sk	=	sk;

			nlk = nlk_sk(sk);
					container_of(sk, struct netlink_sock, sk);
			sk->sk_destruct = netlink_sock_destruct;
			sk->sk_protocol = protocol; // netlink_proto
		
		sk = sock->sk;
		listeners = kzalloc(sizeof(*listeners) + NLGRPSZ(groups), GFP_KERNEL);

		...

		netlink_insert(sk, 0);
			struct netlink_table *table = &nl_table[sk->sk_protocol];
			__netlink_insert(table, sk);
```

## netlink_sock
```c
struct netlink_sock {
	/* struct sock has to be the first member of netlink_sock */
	struct sock		sk;
	u32			portid;
	u32			dst_portid;
	u32			dst_group;
	u32			flags;
	u32			subscriptions;
	u32			ngroups;
	unsigned long		*groups;
	unsigned long		state;
	size_t			max_recvmsg_len;
	wait_queue_head_t	wait;
	bool			bound;
	bool			cb_running;
	int			dump_done_errno;
	struct netlink_callback	cb;
	struct mutex		*cb_mutex;
	struct mutex		cb_def_mutex;
	void			(*netlink_rcv)(struct sk_buff *skb);
	int			(*netlink_bind)(struct net *net, int group);
	void			(*netlink_unbind)(struct net *net, int group);
	struct module		*module;

	struct rhash_head	node;
	struct rcu_head		rcu;
	struct work_struct	work;
};
```

# 注册路由的netlink
路由的通知链是另一种结构， rtnl_link
```c
devinet_init
	rtnl_register(PF_INET, RTM_NEWADDR, inet_rtm_newaddr, NULL, 0);
	rtnl_register(PF_INET, RTM_DELADDR, inet_rtm_deladdr, NULL, 0);
	rtnl_register(PF_INET, RTM_GETADDR, NULL, inet_dump_ifaddr, 0);
	rtnl_register(PF_INET, RTM_GETNETCONF, inet_netconf_get_devconf,
		      inet_netconf_dump_devconf, 0);

		rtnl_register(int protocol, int msgtype,
				   rtnl_doit_func doit, rtnl_dumpit_func dumpit,
				   unsigned int flags)

			rtnl_register_internal(NULL, protocol, msgtype, doit, dumpit, flags);
								 
				rtnl_register_internal(struct module *owner,
								  int protocol, int msgtype,
								  rtnl_doit_func doit, rtnl_dumpit_func dumpit,
								  unsigned int flags)

					struct rtnl_link *link, *old;
					struct rtnl_link __rcu **tab;

					msgindex = rtm_msgindex(msgtype);
						return msgtype - RTM_BASE;

					// rtnl_msg_handlers 是全局二维数组
					// 先查看释放已经存在 PF_INET 对应的 rtnl_link 数组是否存在
					// 不存在，则分配，元素为void *，长度为 RTM_NR_MSGTYPES 的数组
					tab = rtnl_msg_handlers[protocol];
					if (tab == NULL)
						tab = kcalloc(RTM_NR_MSGTYPES, sizeof(void *), GFP_KERNEL);
						rcu_assign_pointer(rtnl_msg_handlers[protocol], tab);

					// 获得以前的 节点 old
					// 分配新节点link
					old = rtnl_dereference(tab[msgindex]);
					if (old)
						link = kmemdup(old, sizeof(*old), GFP_KERNEL);
					else
						link = kzalloc(sizeof(*link), GFP_KERNEL);


					link->owner = owner;
					link->flags |= flags;

					// 设置 doit 和 dumpit 回调
					if (doit)
						link->doit = doit;
					if (dumpit)
						link->dumpit = dumpit;

					// 设置对应link元素
					rcu_assign_pointer(tab[msgindex], link);

					// 释放老节点
					if (old)
						kfree_rcu(old, rcu);
```

```c
doit 节点被请求操作时，被调用
dumpit 节点被释放操作时，被调用
struct rtnl_link {
	rtnl_doit_func		doit;
	rtnl_dumpit_func	dumpit;
	struct module		*owner;
	unsigned int		flags;
	struct rcu_head		rcu;
};

一共执行4次 rtnl_register


		doit : inet_rtm_newaddr
		dumpit : NULL
	rtnl_register(PF_INET, RTM_NEWADDR, inet_rtm_newaddr, NULL, 0);

		doit : inet_rtm_deladdr
		dumpit : NULL
	rtnl_register(PF_INET, RTM_DELADDR, inet_rtm_deladdr, NULL, 0);

		doit : NULL
		dumpit : inet_dump_ifaddr
	rtnl_register(PF_INET, RTM_GETADDR, NULL, inet_dump_ifaddr, 0);

		doit : inet_netconf_get_devconf
		dumpit : inet_netconf_dump_devconf
	rtnl_register(PF_INET, RTM_GETNETCONF, inet_netconf_get_devconf,
		      inet_netconf_dump_devconf, 0);

iproute2 使用 RTM_NEWADDR RTM_DELADDR
```

# netlink的通信
```c
fib_table_insert

	key = ntohl(cfg->fc_dst); // 使用新增路由项的目标地址做key

	l = fib_find_node(t, &tp, key); // 根据key找到前缀树的节点 l

	... // 根据cfg构造 fib_alias fa

	fib_insert_alias(t, tp, l, new_fa, fa, key); // 将fa插入节点l的fib_alias链表

	// 调用路由的netlink 事件为 RTM_NEWROUTE
	rtmsg_fib(RTM_NEWROUTE, htonl(key), new_fa, plen, new_fa->tb_id,
		  &cfg->fc_nlinfo, nlflags);

		void rtmsg_fib(int event, __be32 key, struct fib_alias *fa,
				   int dst_len, u32 tb_id, const struct nl_info *info,
				   unsigned int nlm_flags)
	struct fib_rt_info fri;
	struct sk_buff *skb;

	// 创建一个新的 netlink 消息
	skb = nlmsg_new(fib_nlmsg_size(fa->fa_info), GFP_KERNEL);

	// 用fib_alias 初始化 fib_rt_info
	fri.fi = fa->fa_info;
	fri.tb_id = tb_id;
	fri.dst = key;
	fri.dst_len = dst_len;
	fri.tos = fa->fa_tos;
	fri.type = fa->fa_type;
	fri.offload = fa->offload;
	fri.trap = fa->trap;
	
	// 将要传递的路由信息(在fri中) 记录到 skb中
	err = fib_dump_info(skb, info->portid, seq, event, &fri, nlm_flags);
		struct nlmsghdr *nlh;
		struct rtmsg *rtm;
		// 在skb的内存空间尾部添加一段内存的使用（大小为 sizeof(*rtm)）
		nlh = nlmsg_put(skb, portid, seq, event, sizeof(*rtm), flags);
		// 用 rtm 指向新增的内存空间
		rtm = nlmsg_data(nlh);

		// 以fri做输入，初始化 rtm，记录路由信息
		rtm->rtm_type = fri->type;
		rtm->rtm_flags = fi->fib_flags;
		...

	rtnl_notify(skb, info->nl_net, info->portid, RTNLGRP_IPV4_ROUTE,
		    info->nlh, GFP_KERNEL);
		// 发送 netlink 消息
		nlmsg_notify(rtnl, skb, pid, group, report, flags);
			if (group) // 此时为 RTNLGRP_IPV4_ROUTE
				int exclude_portid = 0;
				if (report)
					refcount_inc(&skb->users);
					exclude_portid = portid;
				// 发送组播
				nlmsg_multicast(sk, skb, exclude_portid, group, flags);
					netlink_broadcast(sk, skb, portid, group, flags);
						netlink_broadcast_filtered(ssk, skb, portid, group, allocation,
							NULL, NULL);

			// 发送单播
			if (report)
				nlmsg_unicast(sk, skb, portid);
					netlink_unicast(sk, skb, portid, MSG_DONTWAIT);


// 组播详解
netlink_broadcast_filtered(struct sock *ssk, struct sk_buff *skb, u32 portid,
	u32 group, gfp_t allocation,
	int (*filter)(struct sock *dsk, struct sk_buff *skb, void *data),
	void *filter_data)

	struct netlink_broadcast_data info;

	// 根据要传递skb和其他参数构造  info
	info.exclude_sk = ssk;
	info.net = net;
	info.skb = skb;
	...

	// 遍历	nl_table[ssk->sk_protocol].mc_list 的所有节点，节点为 sock
	sk_for_each_bound(sk, &nl_table[ssk->sk_protocol].mc_list)
		do_one_broadcast(sk, &info);
			netlink_broadcast_deliver(sk, p->skb2);
				__netlink_sendskb(sk, skb);
					// 将报文 skb 加入 sock 的接受队列
					skb_queue_tail(&sk->sk_receive_queue, skb);
					// sock有已经到达数据
					sk->sk_data_ready(sk);

// 单播详解
netlink_unicast(struct sock *ssk, struct sk_buff *skb,
		    u32 portid, int nonblock)

retry:
	// 按照优先级获得监听的sock
	sk = netlink_getsockbyportid(ssk, portid);
	if (IS_ERR(sk))
		kfree_skb(skb);
		return PTR_ERR(sk);

	// 如果监听的sock是内核空间
	if (netlink_is_kernel(sk))
		return netlink_unicast_kernel(sk, skb, ssk);

	// 如果监听的sock是用户空间

	// sock是否被过滤 
	if (sk_filter(sk, skb))
		kfree_skb(skb);
		sock_put(sk);
		return err;

	// 绑定skb到 sock
	netlink_attachskb(sk, skb, &timeo, ssk);

	netlink_sendskb(sk, skb);
		__netlink_sendskb(sk, skb);
			skb_queue_tail(&sk->sk_receive_queue, skb);
			sk->sk_data_ready(sk);

```

