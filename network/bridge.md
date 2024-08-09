
# vlan filter

```shell
bridge vlan add dev eth0 vid 2 pvid untagged master
```

``
int br_setlink(struct net_device *dev, struct nlmsghdr *nlh, u16 flags)
    // eth0 -> br0
	struct net_bridge *br = (struct net_bridge *)netdev_priv(dev);
	struct net_bridge_port *p;

    // net_device -> net_bridge_port
	p = br_port_get_rtnl(dev);

    err = br_afspec(br, p, afspec, RTM_SETLINK, &changed);
```

```
static int br_afspec(struct net_bridge *br,
		     struct net_bridge_port *p,
		     struct nlattr *af_spec,
		     int cmd, bool *changed)
	struct bridge_vlan_info *vinfo_curr = NULL;
	struct bridge_vlan_info *vinfo_last = NULL;

		case IFLA_BRIDGE_VLAN_INFO:
			vinfo_curr = nla_data(attr); // af_spec -> vinfo_curr 
			err = br_process_vlan_info(br, p, cmd, vinfo_curr,
						   &vinfo_last, changed);
```

```
static int br_process_vlan_info(struct net_bridge *br,
				struct net_bridge_port *p, int cmd,
				struct bridge_vlan_info *vinfo_curr,
				struct bridge_vlan_info **vinfo_last,
				bool *changed)

    err = br_vlan_info(br, p, cmd, &tmp_vinfo, changed);
        case RTM_SETLINK:
			err = nbp_vlan_add(p, vinfo->vid, vinfo->flags,
					   &curr_change);
```

```
int nbp_vlan_add(struct net_bridge_port *port, u16 vid, u16 flags,
		 bool *changed)
	struct net_bridge_vlan *vlan;
	vlan = br_vlan_find(nbp_vlan_group(port), vid);
	if (vlan) {
		*changed = __vlan_add_flags(vlan, flags);
		return 0;

	vlan = kzalloc(sizeof(*vlan), GFP_KERNEL);
	vlan->vid = vid;
	vlan->port = port;
	ret = __vlan_add(vlan, flags);
```


```

/* 这是用于添加 VLAN 的共享函数，它既适用于端口也适用于网桥设备。
 * 根据 VLAN 条目类型，此函数有四种可能的调用方式：
 * 1. 在端口上添加 VLAN（没有主标志，存在全局条目）
 * 2. 在网桥上添加 VLAN（设置了主标志和 brentry 标志）
 * 3. 在端口上添加 VLAN，但全局条目不存在，
 *    目前正在创建（设置了主标志，未设置 brentry 标志），
 *    全局条目用于全局每 VLAN 特性，但不用于过滤
 * 4. 与 3 相同，但是同时设置了主标志和 brentry 标志，
 *    因此该条目将用于端口和网桥的过滤
 */

/* This is the shared VLAN add function which works for both ports and bridge
 * devices. There are four possible calls to this function in terms of the
 * vlan entry type:
 * 1. vlan is being added on a port (no master flags, global entry exists)
 * 2. vlan is being added on a bridge (both master and brentry flags)
 * 3. vlan is being added on a port, but a global entry didn't exist which
 *    is being created right now (master flag set, brentry flag unset), the
 *    global entry is used for global per-vlan features, but not for filtering
 * 4. same as 3 but with both master and brentry flags set so the entry
 *    will be used for filtering in both the port and the bridge
 */

static int __vlan_add(struct net_bridge_vlan *v, u16 flags)
	struct net_bridge_vlan *masterv = NULL;
	struct net_bridge_port *p = NULL;
	struct net_bridge_vlan_group *vg;
	struct net_device *dev;
	struct net_bridge *br;

    // 如果 vlan enty 是 master  则 vg 来自 br
    // 否则 vg 来自 port
	if (br_vlan_is_master(v)) {
		br = v->br;
		dev = br->dev;
		vg = br_vlan_group(br);
	} else {
		p = v->port;
		br = p->br;
		dev = p->dev;
		vg = nbp_vlan_group(p);
	}


	if (p) { // 如果非 master
		err = __vlan_vid_add(dev, br, v->vid, flags);

		if (flags & BRIDGE_VLAN_INFO_MASTER) {
			err = br_vlan_add(br, v->vid,
					  flags | BRIDGE_VLAN_INFO_BRENTRY,
					  &changed);

		masterv = br_vlan_get_master(br, v->vid);

	} else { // master
		err = br_switchdev_port_vlan_add(dev, v->vid, flags);
		if (err && err != -EOPNOTSUPP)
			goto out;
	}

    // 是 master 并且不是 brentry 则返回false
	if (br_vlan_should_use(v)) {
		err = br_fdb_insert(br, p, dev->dev_addr, v->vid);
		vg->num_vlans++;

    // 将 entry 加到对应的 vg 的hashtable
	err = rhashtable_lookup_insert_fast(&vg->vlan_hash, &v->vnode,
					    br_vlan_rht_params);

    // 将 entry 加到对应的 vg 的list
	__vlan_add_list(v);

	__vlan_add_flags(v, flags);
```

```
static bool __vlan_add_flags(struct net_bridge_vlan *v, u16 flags)
	struct net_bridge_vlan_group *vg;
	u16 old_flags = v->flags;

	if (br_vlan_is_master(v))
		vg = br_vlan_group(v->br);
	else
		vg = nbp_vlan_group(v->port);

	if (flags & BRIDGE_VLAN_INFO_PVID)
		ret = __vlan_add_pvid(vg, v->vid);
            vg->pvid = vid;
	else
		ret = __vlan_delete_pvid(vg, v->vid);
            vg->pvid = 0;

	if (flags & BRIDGE_VLAN_INFO_UNTAGGED)
		v->flags |= BRIDGE_VLAN_INFO_UNTAGGED;
	else
		v->flags &= ~BRIDGE_VLAN_INFO_UNTAGGED;

```


# 发送 

```
// 数据包 br 层转发或出栈
netdev_tx_t br_dev_xmit(struct sk_buff *skb, struct net_device *dev)
	struct net_bridge *br = netdev_priv(dev);
	struct net_bridge_fdb_entry *dst;
	u16 vid = 0;

    // br_netfilter
	nf_ops = rcu_dereference(nf_br_ops);
	if (nf_ops && nf_ops->br_dev_xmit_hook(skb)) {
		return NETDEV_TX_OK;

	brstats->tx_packets++;
	brstats->tx_bytes += skb->len;

	BR_INPUT_SKB_CB(skb)->brdev = dev; // dev 为 br

	skb_reset_mac_header(skb);
	eth = eth_hdr(skb);
	skb_pull(skb, ETH_HLEN);

	if (br_bl_extend_hook && br_bl_extend_hook(skb) == 2) goto out;

    // vlan filter
	if (!br_allowed_ingress(br, br_vlan_group_rcu(br), skb, &vid))
		goto out;

    // ipv4 ARP proxy 和 ipv6 NR proxy
	if (IS_ENABLED(CONFIG_INET) &&
	    (eth->h_proto == htons(ETH_P_ARP) ||
	     eth->h_proto == htons(ETH_P_RARP)) &&
	    br->neigh_suppress_enabled) {
		br_do_proxy_suppress_arp(skb, br, vid, NULL);
	} else if (IS_ENABLED(CONFIG_IPV6) &&
		   skb->protocol == htons(ETH_P_IPV6) &&
		   br->neigh_suppress_enabled &&
		   pskb_may_pull(skb, sizeof(struct ipv6hdr) +
				 sizeof(struct nd_msg)) &&
		   ipv6_hdr(skb)->nexthdr == IPPROTO_ICMPV6) {
			struct nd_msg *msg, _msg;

			msg = br_is_nd_neigh_msg(skb, &_msg);
			if (msg)
				br_do_suppress_nd(skb, br, vid, NULL, msg);
	}

	dest = eth_hdr(skb)->h_dest;
	if (is_broadcast_ether_addr(dest)) {
		br_flood(br, skb, BR_PKT_BROADCAST, false, true);
	} else if (is_multicast_ether_addr(dest)) {
        // 如果本机要接受此组播，则接受并不会再传递
		if (br_multicast_rcv(br, NULL, skb, vid)) {
			kfree_skb(skb);
			goto out;

        // 若不是本机接受，则查询多播路由
		mdst = br_mdb_get(br, skb, vid);
		if ((mdst || BR_INPUT_SKB_CB_MROUTERS_ONLY(skb)) &&
		    br_multicast_querier_exists(br, eth_hdr(skb)))
			br_multicast_flood(mdst, skb, false, true);
		else
			br_flood(br, skb, BR_PKT_MULTICAST, false, true);

	} else if ((dst = br_fdb_find_rcu(br, dest, vid)) != NULL) {
        // 找 fdb表，进行转发
		br_forward(dst->dst, skb, false, true);
	} else {
        // fdb没有合适项，所有端口转发
		br_flood(br, skb, BR_PKT_UNICAST, false, true);
    }

	return NETDEV_TX_OK;
```

```
// vg : br_vlan_group_rcu(br)
bool br_allowed_ingress(const struct net_bridge *br,
			struct net_bridge_vlan_group *vg, struct sk_buff *skb,
			u16 *vid)

    // ip link set br0 type bridge vlan_filtering 1
	if (!br->vlan_enabled) {
		BR_INPUT_SKB_CB(skb)->vlan_filtered = false;
		return true;
	}

	return __allowed_ingress(br, vg, skb, vid);
```

```
static bool __allowed_ingress(const struct net_bridge *br,
			      struct net_bridge_vlan_group *vg,
			      struct sk_buff *skb, u16 *vid)
	struct net_bridge_vlan *v;

    // 如果skb->data是vlan包，则提取tag到skb
	if (unlikely(!skb_vlan_tag_present(skb) &&
		     skb->protocol == br->vlan_proto)) {
		skb = skb_vlan_untag(skb);

	if (!br_vlan_get_tag(skb, vid)) {
        // 发送的数据包是 tagged frame, 获得vid

		if (skb->vlan_proto != br->vlan_proto) {
			/* Protocol-mismatch, empty out vlan_tci for new tag */
			*vid = 0;
			tagged = false;
        }

        tagged = true;
	} else {
        // 发送的数据包是 untagged frame
		tagged = false;
    }

	if (!*vid) {
        // untagged

        // 获得 vlan group 的 pvid
		u16 pvid = br_get_pvid(vg);

        // 流量没有tagged 或 vid为0，则看端口的没有pvid
        // pvid能告诉我们流量属于哪里
		if (!pvid)
			goto drop;

        // 任何没有tagged的入栈帧，属于pvid 的vlan
		*vid = pvid;
		if (likely(!tagged))
			__vlan_hwaccel_put_tag(skb, br->vlan_proto, pvid);
                skb->vlan_proto = vlan_proto;
                skb->vlan_tci = VLAN_TAG_PRESENT | vlan_tci;
        else
            // 优先级标记帧
            // skb->vlan_tci 的 VLAN_TAG_PRESENT已经设置，
            // 但 VID是0，所以只需要更新 VID
			skb->vlan_tci |= pvid;

        // 如果不更新vlan接口状态，则直接返回
		if (!br->vlan_stats_enabled)
			return true;

	}

	v = br_vlan_find(vg, *vid);
    // 找到 vlan entry, 但是 entry 是 master 且不是 brentry 
    // 则只作为上下文，为无效vlan entry
	if (!v || !br_vlan_should_use(v))
		goto drop;

	if (br->vlan_stats_enabled) {
		stats->rx_bytes += skb->len;
		stats->rx_packets++;

	return true;

```

```
struct net_bridge_vlan *br_vlan_find(struct net_bridge_vlan_group *vg, u16 vid)
	return br_vlan_lookup(&vg->vlan_hash, vid);
```

# init


```
static int br_dev_init(struct net_device *dev)
	struct net_bridge *br = netdev_priv(dev);

	err = br_fdb_hash_init(br);
	err = br_vlan_init(br);
	err = br_multicast_init_stats(br);

```

```
int br_vlan_init(struct net_bridge *br)
	struct net_bridge_vlan_group *vg;
	vg = kzalloc(sizeof(*vg), GFP_KERNEL);
	ret = rhashtable_init(&vg->vlan_hash, &br_vlan_rht_params);
	ret = vlan_tunnel_init(vg);
	INIT_LIST_HEAD(&vg->vlan_list);
	br->vlan_proto = htons(ETH_P_8021Q);
	br->default_pvid = 1;
	rcu_assign_pointer(br->vlgrp, vg);
	ret = br_vlan_add(br, 1,
			  BRIDGE_VLAN_INFO_PVID | BRIDGE_VLAN_INFO_UNTAGGED |
			  BRIDGE_VLAN_INFO_BRENTRY, &changed);
```

```
// 给br 添加/设置 vlan entry
int br_vlan_add(struct net_bridge *br, u16 vid, u16 flags, bool *changed)
	struct net_bridge_vlan_group *vg;
	struct net_bridge_vlan *vlan;

	vg = br_vlan_group(br);
	vlan = br_vlan_find(vg, vid);
	if (vlan)
		return br_vlan_add_existing(br, vg, vlan, flags, changed);

	vlan = kzalloc(sizeof(*vlan), GFP_KERNEL);
	vlan->stats = netdev_alloc_pcpu_stats(struct br_vlan_stats);
	vlan->vid = vid;
	vlan->flags = flags | BRIDGE_VLAN_INFO_MASTER;
	vlan->flags &= ~BRIDGE_VLAN_INFO_PVID;
	vlan->br = br;
	if (flags & BRIDGE_VLAN_INFO_BRENTRY) // true
		refcount_set(&vlan->refcnt, 1);
	ret = __vlan_add(vlan, flags);

```

```
int br_add_if(struct net_bridge *br, struct net_device *dev,
	      struct netlink_ext_ack *extack)
	struct net_bridge_port *p;
	p = new_nbp(br, dev);
	err = netdev_rx_handler_register(dev, br_handle_frame, p);
	err = nbp_vlan_init(p);

int netdev_rx_handler_register(struct net_device *dev,
			       rx_handler_func_t *rx_handler,
			       void *rx_handler_data)
	rcu_assign_pointer(dev->rx_handler_data, rx_handler_data);
	rcu_assign_pointer(dev->rx_handler, rx_handler);
```

```
int nbp_vlan_init(struct net_bridge_port *p)
	struct switchdev_attr attr = {
		.orig_dev = p->br->dev,  // eth0
		.id = SWITCHDEV_ATTR_ID_BRIDGE_VLAN_FILTERING,
		.flags = SWITCHDEV_F_SKIP_EOPNOTSUPP,
		.u.vlan_filtering = p->br->vlan_enabled, // 默认0
	};
	struct net_bridge_vlan_group *vg;
	int ret = -ENOMEM;

	vg = kzalloc(sizeof(struct net_bridge_vlan_group), GFP_KERNEL);

    // 如果开启了 switchdev ，则退出
	ret = switchdev_port_attr_set(p->dev, &attr);
	if (ret && ret != -EOPNOTSUPP)
		goto err_vlan_enabled;

	ret = rhashtable_init(&vg->vlan_hash, &br_vlan_rht_params);
	ret = vlan_tunnel_init(vg);
	INIT_LIST_HEAD(&vg->vlan_list);
	rcu_assign_pointer(p->vlgrp, vg);

	if (p->br->default_pvid) { // 默认为1
		ret = nbp_vlan_add(p, p->br->default_pvid,
				   BRIDGE_VLAN_INFO_PVID |
				   BRIDGE_VLAN_INFO_UNTAGGED,
				   &changed);

```

```
int nbp_vlan_add(struct net_bridge_port *port, u16 vid, u16 flags,
		 bool *changed)
	struct net_bridge_vlan *vlan;
	vlan = br_vlan_find(nbp_vlan_group(port), vid);
	if (vlan) {
		*changed = __vlan_add_flags(vlan, flags);
		return 0;

	vlan = kzalloc(sizeof(*vlan), GFP_KERNEL);
	vlan->vid = vid;
	vlan->port = port;
	ret = __vlan_add(vlan, flags);
```

# recv

```

static int __netif_receive_skb_core(struct sk_buff **pskb, bool pfmemalloc,
				    struct packet_type **ppt_prev)
	struct packet_type *ptype, *pt_prev;
	rx_handler_func_t *rx_handler;
	struct sk_buff *skb = *pskb;
	struct net_device *orig_dev;


another_round:
	skb->skb_iif = skb->dev->ifindex;

	if (skb->protocol == cpu_to_be16(ETH_P_8021Q) ||
	    skb->protocol == cpu_to_be16(ETH_P_8021AD)) {
		skb = skb_vlan_untag(skb);

    // 抓包
	list_for_each_entry_rcu(ptype, &ptype_all, list) {
		if (pt_prev)
			ret = deliver_skb(skb, pt_prev, orig_dev);
		pt_prev = ptype;
	}
	list_for_each_entry_rcu(ptype, &skb->dev->ptype_all, list) {
		if (pt_prev)
			ret = deliver_skb(skb, pt_prev, orig_dev);
		pt_prev = ptype;
	}

    // 如果是tagged，则根据vid先找real_dev的vlan_dev
    // 如果没有找到vlan_dev返回false, skb 不变
    // 如果找到了并正确处理返回true，
    // 如果找到了但处理失败，如vlan_dev down，则返回false, skb为NULL
	if (skb_vlan_tag_present(skb)) {
		if (vlan_do_receive(&skb))
			goto another_round; // 正确处理，skb变为802.3 , 输入设备为vlan dev
		else if (unlikely(!skb))
			goto out;

    // 若为桥端口, rx_handler为 br_handle_frame
	rx_handler = rcu_dereference(skb->dev->rx_handler);
	if (rx_handler) {
		switch (rx_handler(&skb)) {

```

```
// Return NULL if skb is handled
rx_handler_result_t br_handle_frame(struct sk_buff **pskb)
	struct net_bridge_port *p;
	struct sk_buff *skb = *pskb;
	const unsigned char *dest = eth_hdr(skb)->h_dest;

    // 非法源MAC丢弃，如 FF:FF:FF:FF:FF:FF
	if (!is_valid_ether_addr(eth_hdr(skb)->h_source))
		goto drop;

	p = br_port_get_rcu(skb->dev); // real_dev

	if (p->flags & BR_VLAN_TUNNEL) {
		if (br_handle_ingress_vlan_tunnel(skb, p,
						  nbp_vlan_group_rcu(p)))
			goto drop;

    // 数据包是否是本地链路地址，即链路协议使用的，而非通用数据包
		/*
		 * See IEEE 802.1D Table 7-10 Reserved addresses
		 *
		 * Assignment		 		Value
		 * Bridge Group Address		01-80-C2-00-00-00
		 * (MAC Control) 802.3		01-80-C2-00-00-01
		 * (Link Aggregation) 802.3	01-80-C2-00-00-02
		 * 802.1X PAE address		01-80-C2-00-00-03
		 *
		 * 802.1AB LLDP 		01-80-C2-00-00-0E
		 *
		 * Others reserved for future standardization
		 */
	if (unlikely(is_link_local_ether_addr(dest))) {
        ...
    }

forward:
    // 端口学习完毕，则进入转发状态
	switch (p->state) {
	case BR_STATE_FORWARDING:
	case BR_STATE_LEARNING:
        // 目的MAC == 本端口的MAC，是发给本机的包
		if (ether_addr_equal(p->br->dev->dev_addr, dest))
			skb->pkt_type = PACKET_HOST;
		NF_HOOK(NFPROTO_BRIDGE, NF_BR_PRE_ROUTING,
			dev_net(skb->dev), NULL, skb, skb->dev, NULL,
			br_handle_frame_finish);
		break;
	default:
drop:
		kfree_skb(skb);

	return RX_HANDLER_CONSUMED;
```

```
int br_handle_frame_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
	struct net_bridge_port *p = br_port_get_rcu(skb->dev);
	enum br_pkt_type pkt_type = BR_PKT_UNICAST;
	struct net_bridge_fdb_entry *dst = NULL;
	struct net_bridge_mdb_entry *mdst;
	bool local_rcv, mcast_hit = false;
	struct net_bridge *br;
	u16 vid = 0;

	if (!br_allowed_ingress(p->br, nbp_vlan_group_rcu(p), skb, &vid))
		goto out;

    // 通过vlan filter后更新转发表
	br = p->br;
	if (p->flags & BR_LEARNING)
		br_fdb_update(br, p, eth_hdr(skb)->h_source, vid, false);

	if (is_multicast_ether_addr(eth_hdr(skb)->h_dest)) {
		if (is_broadcast_ether_addr(eth_hdr(skb)->h_dest)) {
			pkt_type = BR_PKT_BROADCAST;
			local_rcv = true;
		} else {
			pkt_type = BR_PKT_MULTICAST;
			if (br_multicast_rcv(br, p, skb, vid))
				goto drop;

	if (p->state == BR_STATE_LEARNING)
		goto drop;

    // ipv4 ARP proxy 和 ipv6 NR proxy
	if (IS_ENABLED(CONFIG_INET) &&
	    (skb->protocol == htons(ETH_P_ARP) ||
	     skb->protocol == htons(ETH_P_RARP))) {
		br_do_proxy_suppress_arp(skb, br, vid, p);
	} else if (IS_ENABLED(CONFIG_IPV6) &&
		   skb->protocol == htons(ETH_P_IPV6) &&
		   br->neigh_suppress_enabled &&
		   pskb_may_pull(skb, sizeof(struct ipv6hdr) +
				 sizeof(struct nd_msg)) &&
		   ipv6_hdr(skb)->nexthdr == IPPROTO_ICMPV6) {
			struct nd_msg *msg, _msg;

			msg = br_is_nd_neigh_msg(skb, &_msg);
			if (msg)
				br_do_suppress_nd(skb, br, vid, p, msg);
	}

	switch (pkt_type) {
	case BR_PKT_MULTICAST:
		mdst = br_mdb_get(br, skb, vid);
		if ((mdst || BR_INPUT_SKB_CB_MROUTERS_ONLY(skb)) &&
		    br_multicast_querier_exists(br, eth_hdr(skb))) {
			if ((mdst && mdst->host_joined) ||
			    br_multicast_is_router(br)) {
				local_rcv = true;
				br->dev->stats.multicast++;
			mcast_hit = true;
		} else {
			local_rcv = true;
			br->dev->stats.multicast++;
		break;
	case BR_PKT_UNICAST:
		dst = br_fdb_find_rcu(br, eth_hdr(skb)->h_dest, vid);
	default:
		break;

	if (dst) {
		unsigned long now = jiffies;
		if (dst->is_local)
			return br_pass_frame_up(skb); // 本地接受
		if (now != dst->used)
			dst->used = now; // 更新转发条目时间
		br_forward(dst->dst, skb, local_rcv, false); //转发
	} else {
		if (!mcast_hit)
			br_flood(br, skb, pkt_type, local_rcv, false);
		else
			br_multicast_flood(mdst, skb, local_rcv, false);

	if (local_rcv) // 广播或多播时自己也会接受
		return br_pass_frame_up(skb);

```

```
static int br_pass_frame_up(struct sk_buff *skb)
	struct net_device *indev, *brdev = BR_INPUT_SKB_CB(skb)->brdev;
	struct net_bridge *br = netdev_priv(brdev); // 从real_dev 到 br
	struct net_bridge_vlan_group *vg;

	brstats->rx_packets++;
	brstats->rx_bytes += skb->len;

	vg = br_vlan_group_rcu(br); // 得到 br 的 vlan group

    // 除非开启混淆模式（方便抓包）
    // 否则若没通过vlan filter，就丢弃包
	if (!(brdev->flags & IFF_PROMISC) &&
	    !br_allowed_egress(vg, skb)) { // 使用br的 vg进行检测
		kfree_skb(skb);
		return NET_RX_DROP;

	indev = skb->dev; // 输入设备为real_dev
	skb->dev = brdev; // 当前设备改为br

    // BRIDGE_VLAN_INFO_UNTAGGED 则 skb->vlan_tci = 0
    // TODO BR_VLAN_TUNNEL 
	skb = br_handle_vlan(br, NULL, vg, skb); 
	if (!skb)
		return NET_RX_DROP;

    // 如果packet是 IGMP/MLD 则更新组播状态 
	br_multicast_count(br, NULL, skb, br_multicast_igmp_type(skb),
			   BR_MCAST_DIR_TX);

    // 进入 br_nf NF_BR_LOCAL_IN
	return NF_HOOK(NFPROTO_BRIDGE, NF_BR_LOCAL_IN,
		       dev_net(indev), NULL, skb, indev, NULL,
		       br_netif_receive_skb);
```


```
// 若packet untagged, 返回false
// 若packet tagged ，且找到有效的vlan entry ，则返回true
bool br_allowed_egress(struct net_bridge_vlan_group *vg,
		       const struct sk_buff *skb)
	const struct net_bridge_vlan *v;
	u16 vid;

    // 若没开启 vlan_filtered
	if (!BR_INPUT_SKB_CB(skb)->vlan_filtered)
		return true;

    // 若packet untagged, vid为0
    // 若packet tagged ，得到vid
	br_vlan_get_tag(skb, &vid);
        if (skb_vlan_tag_present(skb)) {
            *vid = skb_vlan_tag_get(skb) & VLAN_VID_MASK;
        } else {
            *vid = 0;
            err = -EINVAL;
        return err;

    // 若vid为0，v为NULL
	v = br_vlan_find(vg, vid);
        if (!vg)
            return NULL;
        return br_vlan_lookup(&vg->vlan_hash, vid);

    // 若v存在，并且有效，则返回 true
	if (v && br_vlan_should_use(v))
            if (br_vlan_is_master(v)) {
                if (br_vlan_is_brentry(v))
                    return true;
                else
                    return false;
		return true;

	return false;
```

```
struct sk_buff *br_handle_vlan(struct net_bridge *br,
			       const struct net_bridge_port *p,
			       struct net_bridge_vlan_group *vg,
			       struct sk_buff *skb)
	struct br_vlan_stats *stats;
	struct net_bridge_vlan *v;
	u16 vid;

	if (!BR_INPUT_SKB_CB(skb)->vlan_filtered)
		goto out;

	br_vlan_get_tag(skb, &vid);
	v = br_vlan_find(vg, vid);

    // 到这一点时，VLAN 条目必须已经配置好了。
    // 唯一的例外是网桥设置在混杂模式下，并且数据包是发往网桥设备的。
    // 在这种情况下，按原样传递数据包。

	if (!v || !br_vlan_should_use(v)) {
		if ((br->dev->flags & IFF_PROMISC) && skb->dev == br->dev) {
			goto out;
		} else {
			kfree_skb(skb);
			return NULL;

	if (br->vlan_stats_enabled) {
		stats = this_cpu_ptr(v->stats);
		stats->tx_bytes += skb->len;
		stats->tx_packets++;

	if (v->flags & BRIDGE_VLAN_INFO_UNTAGGED)
		skb->vlan_tci = 0;

	if (p && (p->flags & BR_VLAN_TUNNEL) &&
	    br_handle_egress_vlan_tunnel(skb, v)) {
		kfree_skb(skb);
		return NULL;

out:
	return skb;

```


```
/**
 * br_forward - 将数据包转发到特定端口
 * @to: 目标端口
 * @skb: 被转发的数据包
 * @local_rcv: 数据包在转发后将被本地接收
 * @local_orig: 数据包是本地产生的
 *
 * 调用时应持有 rcu_read_lock 锁。
 */
void br_forward(const struct net_bridge_port *to,
		struct sk_buff *skb, bool local_rcv, bool local_orig)
    // 如果发送端口无法使用，并且有备用端口，则使用备用端口发送
	if (rcu_access_pointer(to->backup_port) && !netif_carrier_ok(to->dev)) {
		struct net_bridge_port *backup_port;
		backup_port = rcu_dereference(to->backup_port);
		to = backup_port;

	if (should_deliver(to, skb)) {
		if (local_rcv)
			deliver_clone(to, skb, local_orig);
		else
			__br_forward(to, skb, local_orig);
```

```
// 不转发packet 到原始端口，或者转发端口被禁止
static inline int should_deliver(const struct net_bridge_port *p,
				 const struct sk_buff *skb)
	struct net_bridge_vlan_group *vg;
	vg = nbp_vlan_group_rcu(p);

    // skb->dev != p->dev : 输入设备不等于输出设备
	return ((p->flags & BR_HAIRPIN_MODE) || skb->dev != p->dev) &&
    // forward : skb->dev 为 real_dev
    // skb必须为tagged，并且vid的entry存在于输入设备的vg中
		br_allowed_egress(vg, skb) && p->state == BR_STATE_FORWARDING &&
		nbp_switchdev_allowed_egress(p, skb) &&
		!br_skb_isolated(p, skb);
```


```
static void __br_forward(const struct net_bridge_port *to,
			 struct sk_buff *skb, bool local_orig)
	struct net_bridge_vlan_group *vg;
	struct net_device *indev;
	struct net *net;

    // 用输出设备的vlan group 去处理skb
	vg = nbp_vlan_group_rcu(to);
	skb = br_handle_vlan(to->br, to, vg, skb);
	if (!skb)
		return;

	indev = skb->dev;
	skb->dev = to->dev; // 当前设备修改为输出设备

	if (!local_orig) { // 不是本地生成的包, 走NF_BR_FORWARD
		br_hook = NF_BR_FORWARD;
		skb_forward_csum(skb);
		net = dev_net(indev);
	} else { // 本地生成的包，走NF_BR_LOCAL_OUT
		br_hook = NF_BR_LOCAL_OUT;
		net = dev_net(skb->dev);
		indev = NULL;

	NF_HOOK(NFPROTO_BRIDGE, br_hook,
		net, NULL, skb, indev, skb->dev,
		br_forward_finish);
```

```
int br_forward_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
	skb->tstamp = 0;
	return NF_HOOK(NFPROTO_BRIDGE, NF_BR_POST_ROUTING,
		       net, sk, skb, NULL, skb->dev,
		       br_dev_queue_push_xmit);


int br_dev_queue_push_xmit(struct net *net, struct sock *sk, struct sk_buff *skb)
	skb_push(skb, ETH_HLEN);
    // 如果dev发送，如数据包长度超过MTU
	if (!is_skb_forwardable(skb->dev, skb))
		goto drop;

    // 将数据包加入dev的发送qdisc
	dev_queue_xmit(skb);
        return __dev_queue_xmit(skb, NULL);
            txq = netdev_pick_tx(dev, skb, sb_dev);
            q = rcu_dereference_bh(txq->qdisc);
            if (q->enqueue) {
                rc = __dev_xmit_skb(skb, q, dev, txq);
```

