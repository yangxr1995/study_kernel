# 链路套接字
## 创建


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


PF_PACKET 的 packet_family_ops

static int __init packet_init(void)
	rc = sock_register(&packet_family_ops);

static const struct net_proto_family packet_family_ops = {
	.family =	PF_PACKET,
	.create =	packet_create,
	.owner	=	THIS_MODULE,
};

packet_sock 就是 sock 的派生类，
socket 是和用户态沟通的桥梁，sock是套接字在网络层的实例， packet_sock 是链路套接字

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

## recvfrom

int __sys_recvfrom(int fd, void __user *ubuf, size_t size, unsigned int flags,
		   struct sockaddr __user *addr, int __user *addr_len)
	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	err = sock_recvmsg(sock, &msg, flags);
        return sock->ops->recvmsg(sock, msg, msg_data_left(msg), flags);

### type == SOCK_RAW

static int packet_recvmsg(struct socket *sock, struct msghdr *msg, size_t len,
			  int flags)
    // 只支持如下 flags
	if (flags & ~(MSG_PEEK|MSG_DONTWAIT|MSG_TRUNC|MSG_CMSG_COMPAT|MSG_ERRQUEUE))
		goto out;

    // 从sk 的 	sk->sk_receive_queue 或取出一个 skb
	skb = skb_recv_datagram(sk, flags, flags & MSG_DONTWAIT, &err);

### vlan tag

setsockopt

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


recvmsg

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

