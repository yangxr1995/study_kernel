# 链路套接字
## 创建

```c
int __sys_socket(int family, int type, int protocol)
    return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);
        struct socket *sock;
        const struct net_proto_family *pf;

        if (family == PF_INET && type == SOCK_PACKET) {
            pr_info_once("%s uses obsolete (PF_INET,SOCK_PACKET)\n",
                     current->comm);
            family = PF_PACKET;
        }
        // 创建 socket
        sock = sock_alloc();
        sock->type = type;
        // 根据 协议族确定 ops
        pf = rcu_dereference(net_families[family]);
        // 处理化 socket
        err = pf->create(net, sock, protocol, kern);
        // 返回 socket
        *res = sock;
        return 0;
```


PF_PACKET 的 packet_family_ops

```c
static int __init packet_init(void)
	rc = sock_register(&packet_family_ops);
    int sock_register(const struct net_proto_family *ops)

static const struct net_proto_family packet_family_ops = {
	.family =	PF_PACKET
    .create = packer_create,
	.owner	=	THIS_MODULE,
};
```

packet_sock 就是 sock 的派生类，
socket 是和用户态沟通的桥梁，sock是套接字在网络层的实例， packet_sock 是链路套接字

```c
static int packet_create(struct net *net, struct socket *sock, int protocol,
			 int kern)
{
	struct sock *sk;
	struct packet_sock *po;
	__be16 proto = (__force __be16)protocol; /* weird, but documented */
	int err;

	if (sock->type != SOCK_DGRAM && sock->type != SOCK_RAW &&
	    sock->type != SOCK_PACKET)
		return -ESOCKTNOSUPPORT;

	sock->state = SS_UNCONNECTED;

	sk = sk_alloc(net, PF_PACKET, GFP_KERNEL, &packet_proto, kern);

	sock->ops = &packet_ops; // SOCK_RAW
	if (sock->type == SOCK_PACKET)
		sock->ops = &packet_ops_spkt; // SOCK_PACKET

	sock_init_data(sock, sk);

	po = pkt_sk(sk);
	init_completion(&po->skb_completion);
	sk->sk_family = PF_PACKET;
	po->num = proto;
	po->xmit = dev_queue_xmit;

	po->rollover = NULL;
	po->prot_hook.func = packet_rcv;

	if (sock->type == SOCK_PACKET)
		po->prot_hook.func = packet_rcv_spkt;

	po->prot_hook.af_packet_priv = sk;

	if (proto) {
		po->prot_hook.type = proto;
		__register_prot_hook(sk);
	}

	mutex_lock(&net->packet.sklist_lock);
	sk_add_node_tail_rcu(sk, &net->packet.sklist);
	mutex_unlock(&net->packet.sklist_lock);

	preempt_disable();
	sock_prot_inuse_add(net, &packet_proto, 1);
	preempt_enable();

	return 0;
}
```

## recvfrom

```c
int __sys_recvfrom(int fd, void __user *ubuf, size_t size, unsigned int flags,
		   struct sockaddr __user *addr, int __user *addr_len)
	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	err = sock_recvmsg(sock, &msg, flags);
        return sock->ops->recvmsg(sock, msg, msg_data_left(msg), flags);
```

### type == SOCK_RAW

```c
static int packet_recvmsg(struct socket *sock, struct msghdr *msg, size_t len,
			  int flags)
    // 只支持如下 flags
	if (flags & ~(MSG_PEEK|MSG_DONTWAIT|MSG_TRUNC|MSG_CMSG_COMPAT|MSG_ERRQUEUE))
		goto out;

    // 从sk 的 	sk->sk_receive_queue 或取出一个 skb
	skb = skb_recv_datagram(sk, flags, flags & MSG_DONTWAIT, &err);
```

### vlan tag

setsockopt

```c
	case PACKET_AUXDATA:
	{
		int val;

		if (optlen < sizeof(val))
			return -EINVAL;
		if (copy_from_user(&val, optval, sizeof(val)))
			return -EFAULT;

		lock_sock(sk);
		po->auxdata = !!val;
		release_sock(sk);
		return 0;
	}
```


recvmsg

```c
	if (pkt_sk(sk)->auxdata) {
		struct tpacket_auxdata aux;

		aux.tp_status = TP_STATUS_USER;
		if (skb->ip_summed == CHECKSUM_PARTIAL)
			aux.tp_status |= TP_STATUS_CSUMNOTREADY;
		else if (skb->pkt_type != PACKET_OUTGOING &&
			 (skb->ip_summed == CHECKSUM_COMPLETE ||
			  skb_csum_unnecessary(skb)))
			aux.tp_status |= TP_STATUS_CSUM_VALID;

		aux.tp_len = origlen;
		aux.tp_snaplen = skb->len;
		aux.tp_mac = 0;
		aux.tp_net = skb_network_offset(skb);
		if (skb_vlan_tag_present(skb)) {
			aux.tp_vlan_tci = skb_vlan_tag_get(skb);
			aux.tp_vlan_tpid = ntohs(skb->vlan_proto);
			aux.tp_status |= TP_STATUS_VLAN_VALID | TP_STATUS_VLAN_TPID_VALID;
		} else {
			aux.tp_vlan_tci = 0;
			aux.tp_vlan_tpid = 0;
		}
		put_cmsg(msg, SOL_PACKET, PACKET_AUXDATA, sizeof(aux), &aux);
	}
```

# 原始套接字

```c
socket(AF_INET, SOCK_RAW, 0)
```

## socket

socket 最终会调用 inet_create

```c
static const struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,
	.owner	= THIS_MODULE,
};

int inet_create(struct net *net, struct socket *sock, int protocol, int kern)
	struct sock *sk;
	struct inet_protosw *answer;
	struct inet_sock *inet;
	struct proto *answer_prot;
	unsigned char answer_flags;
	int try_loading_module = 0;
	int err;

    // 根据 type 找到 proto
lookup_protocol:
	err = -ESOCKTNOSUPPORT;
	rcu_read_lock();
	list_for_each_entry_rcu(answer, &inetsw[sock->type], list) {

		err = 0;
		/* Check the non-wild match. */
		if (protocol == answer->protocol) {
			if (protocol != IPPROTO_IP)
				break;
		} else {
			/* Check for the two wild cases. */
			if (IPPROTO_IP == protocol) {
				protocol = answer->protocol;
				break;
			}
			if (IPPROTO_IP == answer->protocol)
				break;
		}
		err = -EPROTONOSUPPORT;
	}

	sock->ops = answer->ops; // SOCK_RAW -> inet_sockraw_ops
	answer_prot = answer->prot;
	answer_flags = answer->flags;

    // 将 sk->prot = answer_prot
	sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot, kern);

	inet = inet_sk(sk);

    // 进一步初始化
	if (sk->sk_prot->init) {
		err = sk->sk_prot->init(sk);
		if (err) {
			sk_common_release(sk);
			goto out;
		}
	}
	
    // inet的proto定义在 inetsw_array
static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},

	{
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_UDP,
		.prot =       &udp_prot,
		.ops =        &inet_dgram_ops,
		.flags =      INET_PROTOSW_PERMANENT,
       },

       {
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_ICMP,
		.prot =       &ping_prot,
		.ops =        &inet_sockraw_ops,
		.flags =      INET_PROTOSW_REUSE,
       },

       {
	       .type =       SOCK_RAW,
	       .protocol =   IPPROTO_IP,	/* wild card */
	       .prot =       &raw_prot,
	       .ops =        &inet_sockraw_ops,
	       .flags =      INET_PROTOSW_REUSE,
       }
};

struct proto raw_prot = {
	.name		   = "RAW",
	.owner		   = THIS_MODULE,
	.close		   = raw_close,
	.destroy	   = raw_destroy,
	.connect	   = ip4_datagram_connect,
	.disconnect	   = __udp_disconnect,
	.ioctl		   = raw_ioctl,
	.init		   = raw_init,
	.setsockopt	   = raw_setsockopt,
	.getsockopt	   = raw_getsockopt,
	.sendmsg	   = raw_sendmsg,
	.recvmsg	   = raw_recvmsg,
	.bind		   = raw_bind,
	.backlog_rcv	   = raw_rcv_skb,
	.release_cb	   = ip4_datagram_release_cb,
	.hash		   = raw_hash_sk,
	.unhash		   = raw_unhash_sk,
	.obj_size	   = sizeof(struct raw_sock),
	.useroffset	   = offsetof(struct raw_sock, filter),
	.usersize	   = sizeof_field(struct raw_sock, filter),
	.h.raw_hash	   = &raw_v4_hashinfo,
#ifdef CONFIG_COMPAT
	.compat_setsockopt = compat_raw_setsockopt,
	.compat_getsockopt = compat_raw_getsockopt,
	.compat_ioctl	   = compat_raw_ioctl,
#endif
	.diag_destroy	   = raw_abort,
};

static int raw_init(struct sock *sk)
{
	struct raw_sock *rp = raw_sk(sk);

	if (inet_sk(sk)->inet_num == IPPROTO_ICMP)
		memset(&rp->filter, 0, sizeof(rp->filter));
	return 0;
}
```

## recvfrom

recvfrom 最终调用 `ops->recvmsg`

```c
static const struct proto_ops inet_sockraw_ops = {
	.family		   = PF_INET,
	.owner		   = THIS_MODULE,
	.release	   = inet_release,
	.bind		   = inet_bind,
	.connect	   = inet_dgram_connect,
	.socketpair	   = sock_no_socketpair,
	.accept		   = sock_no_accept,
	.getname	   = inet_getname,
	.poll		   = datagram_poll,
	.ioctl		   = inet_ioctl,
	.listen		   = sock_no_listen,
	.shutdown	   = inet_shutdown,
	.setsockopt	   = sock_common_setsockopt,
	.getsockopt	   = sock_common_getsockopt,
	.sendmsg	   = inet_sendmsg,
	.recvmsg	   = inet_recvmsg,
	.mmap		   = sock_no_mmap,
	.sendpage	   = inet_sendpage,
#ifdef CONFIG_COMPAT
	.compat_setsockopt = compat_sock_common_setsockopt,
	.compat_getsockopt = compat_sock_common_getsockopt,
	.compat_ioctl	   = inet_compat_ioctl,
#endif
};

int inet_recvmsg(struct socket *sock, struct msghdr *msg, size_t size,
		 int flags)
{
	struct sock *sk = sock->sk;
	int addr_len = 0;
	int err;

	if (likely(!(flags & MSG_ERRQUEUE)))
		sock_rps_record_flow(sk);

	err = sk->sk_prot->recvmsg(sk, msg, size, flags & MSG_DONTWAIT,
				   flags & ~MSG_DONTWAIT, &addr_len);
	if (err >= 0)
		msg->msg_namelen = addr_len;
	return err;
}

static int raw_recvmsg(struct sock *sk, struct msghdr *msg, size_t len,
		       int noblock, int flags, int *addr_len)

	skb = skb_recv_datagram(sk, flags, noblock, &err);

	err = skb_copy_datagram_msg(skb, 0, msg, copied);

	/* Copy the address. */
	if (sin) {
		sin->sin_family = AF_INET;
		sin->sin_addr.s_addr = ip_hdr(skb)->saddr;
		sin->sin_port = 0;
		memset(&sin->sin_zero, 0, sizeof(sin->sin_zero));
		*addr_len = sizeof(*sin);
	}

recvfrom 获得skb是从 sk->sk_receive_queue 中取一个skb

struct sk_buff *skb_recv_datagram(struct sock *sk, unsigned int flags,
				  int noblock, int *err)
{
	int peeked, off = 0;

	return __skb_recv_datagram(sk, flags | (noblock ? MSG_DONTWAIT : 0),
				   NULL, &peeked, &off, err);

		skb = __skb_try_recv_datagram(sk, flags, destructor, peeked,
					      off, err, &last);
            struct sk_buff_head *queue = &sk->sk_receive_queue;
            skb = __skb_try_recv_from_queue(sk, queue, flags, destructor,
                            peeked, off, &error, last);
}
```

## 入栈skb到 sk->sk_receive_queue

查询路由为入栈包，并且过了 netfilter，最终调用 ip_local_deliver_finish

ip_local_deliver_finish

```c
static int ip_local_deliver_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
{
    // 将 skb->data  指向传输层
	__skb_pull(skb, skb_network_header_len(skb));

    // 获得传输层协议
		int protocol = ip_hdr(skb)->protocol;
		const struct net_protocol *ipprot;
		int raw;

	resubmit:
    // 尝试将 skb 拷贝一份给 协议匹配的传输层sock的接受队列
		raw = raw_local_deliver(skb, protocol);

    // 找传输层对应协议
		ipprot = rcu_dereference(inet_protos[protocol]);
		if (ipprot) {
			int ret;

			if (!ipprot->no_policy) {
				if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb)) {
					kfree_skb(skb);
					goto out;
				}
				nf_reset(skb);
			}
            // 将skb加入对应传输层的sock的接受队列
			ret = ipprot->handler(skb);
			if (ret < 0) {
				protocol = -ret;
				goto resubmit;
			}
			__IP_INC_STATS(net, IPSTATS_MIB_INDELIVERS);



int raw_local_deliver(struct sk_buff *skb, int protocol)
{
	int hash;
	struct sock *raw_sk;

    // 根据proto求hash，找到注册了的sock链表
	hash = protocol & (RAW_HTABLE_SIZE - 1);
	raw_sk = sk_head(&raw_v4_hashinfo.ht[hash]);

	/* If there maybe a raw socket we must check - if not we
	 * don't care less
	 */
    // 尝试将skb拷贝到 raw sock
	if (raw_sk && !raw_v4_input(skb, ip_hdr(skb), hash))
		raw_sk = NULL;

	return raw_sk != NULL;

}

static int raw_v4_input(struct sk_buff *skb, const struct iphdr *iph, int hash)
{
	int sdif = inet_sdif(skb);
	int dif = inet_iif(skb);
	struct sock *sk;
	struct hlist_head *head;
	int delivered = 0;
	struct net *net;

	read_lock(&raw_v4_hashinfo.lock);
    // 找到raw sock链表头
	head = &raw_v4_hashinfo.ht[hash];
	if (hlist_empty(head))
		goto out;

	net = dev_net(skb->dev);
    // 找到 proto 对应的sk
	sk = __raw_v4_lookup(net, __sk_head(head), iph->protocol,
			     iph->saddr, iph->daddr, dif, sdif);

	while (sk) {
		delivered = 1;
        // 如果不是 ICMP ，并且是允许的组播
		if ((iph->protocol != IPPROTO_ICMP || !icmp_filter(sk, skb)) &&
		    ip_mc_sf_allow(sk, iph->daddr, iph->saddr,
				   skb->dev->ifindex, sdif)) {
            // 克隆skb
			struct sk_buff *clone = skb_clone(skb, GFP_ATOMIC);

			/* Not releasing hash table! */
            // skb加入sk
			if (clone)
				raw_rcv(sk, clone);
		}
        // 找另一个sk
		sk = __raw_v4_lookup(net, sk_next(sk), iph->protocol,
				     iph->saddr, iph->daddr,
				     dif, sdif);
	}
out:
	read_unlock(&raw_v4_hashinfo.lock);
	return delivered;
}


int raw_rcv(struct sock *sk, struct sk_buff *skb)
{
	if (!xfrm4_policy_check(sk, XFRM_POLICY_IN, skb)) {
		atomic_inc(&sk->sk_drops);
		kfree_skb(skb);
		return NET_RX_DROP;
	}
	nf_reset(skb);

    // 将skb->data指向IP层
	skb_push(skb, skb->data - skb_network_header(skb));

	raw_rcv_skb(sk, skb);
	return 0;
}

static int raw_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	/* Charge it to the socket. */

	ipv4_pktinfo_prepare(sk, skb);
	if (sock_queue_rcv_skb(sk, skb) < 0) {
		kfree_skb(skb);
		return NET_RX_DROP;
	}

	return NET_RX_SUCCESS;
}

int sock_queue_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	int err;

    // 可以使用 SO_ATTACH_FILTER 添加过滤器,注意skb->data指向IP层
	err = sk_filter(sk, skb);
	if (err)
		return err;

	return __sock_queue_rcv_skb(sk, skb);
}

static inline int sk_filter(struct sock *sk, struct sk_buff *skb)
{
	return sk_filter_trim_cap(sk, skb, 1);
        struct sk_filter *filter;
        filter = rcu_dereference(sk->sk_filter);
        if (filter) {
            struct sock *save_sk = skb->sk;
            unsigned int pkt_len;

#define BPF_PROG_RUN(filter, ctx)  (*(filter)->bpf_func)(ctx, (filter)->insnsi)
            skb->sk = sk;
            pkt_len = bpf_prog_run_save_cb(filter->prog, skb);
                res = BPF_PROG_RUN(prog, skb); //返回0为错误
            skb->sk = save_sk;
            err = pkt_len ? pskb_trim(skb, max(cap, pkt_len)) : -EPERM; //如果pkt_len为0则为错误
        }

	return err;
}
```
