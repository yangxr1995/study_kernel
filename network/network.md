基于 linux-2.6.26

# 1. 网络文件系统

## 网络文件系统的注册
```c
static struct file_system_type sock_fs_type = {
	.name =		"sockfs",
	.get_sb =	sockfs_get_sb,
	.kill_sb =	kill_anon_super,
};

static int __init sock_init(void)
{
	/*
	 *      Initialize sock SLAB cache.
	 */

	sk_init();

	/*
	 *      Initialize skbuff SLAB cache
	 */
	skb_init();

	/*
	 *      Initialize the protocols module.
	 */

	init_inodecache();
	register_filesystem(&sock_fs_type); // 注册网络文件系统
	sock_mnt = kern_mount(&sock_fs_type); // 安装文件系统

	/* The real protocol initialization is performed in later initcalls.
	 */

#ifdef CONFIG_NETFILTER
	netfilter_init();
#endif

	return 0;
}
```

### 分析 kern_mount

```c
#define kern_mount(type) kern_mount_data(type, NULL)

struct vfsmount *kern_mount_data(struct file_system_type *type, void *data)
{
	return vfs_kern_mount(type, MS_KERNMOUNT, type->name, data);
}

struct vfsmount *
vfs_kern_mount(struct file_system_type *type, int flags, const char *name, void *data)
{
	struct vfsmount *mnt;
	char *secdata = NULL;
	int error;

	mnt = alloc_vfsmnt(name);
	

	// 创建super_block, 根dentry 和 根inode
	// super_block->s_root = dentry; dentry->d_inode = inode;
	type->get_sb(type, flags, name, data, mnt);
		sockfs_get_sb(struct file_system_type *fs_type,
					 int flags, const char *dev_name, void *data,
					 struct vfsmount *mnt)
			return get_sb_pseudo(fs_type, "socket:", &sockfs_ops, SOCKFS_MAGIC,
						 mnt);
				struct super_block *s = sget(fs_type, NULL, set_anon_super, NULL);
				s->s_op = ops ? ops : &simple_super_operations; // sockfs_ops
				// 创建根inode
				root = new_inode(s);
					inode = alloc_inode(sb);
						if (sb->s_op->alloc_inode)
							inode = sb->s_op->alloc_inode(sb); // sock_alloc_inode
						else
							inode = (struct inode *) kmem_cache_alloc(inode_cachep, GFP_KERNEL);

				// 创建根dentry
				dentry = d_alloc(NULL, &d_name);
				// 建立 dentry inode super_block vfsmount 关系
				d_instantiate(dentry, root);
				s->s_root = dentry;
				return simple_set_mnt(struct vfsmount mnt, struct super_block *sb);
					mnt->mnt_sb = sb;
					mnt->mnt_root = dget(sb->s_root);

	mnt->mnt_mountpoint = mnt->mnt_root; // 他挂载在自己的根目录
	mnt->mnt_parent = mnt;
	return mnt;
}
```
需要注意sockfs实现的ops
```c
static struct super_operations sockfs_ops = {
	.alloc_inode =	sock_alloc_inode,
	.destroy_inode =sock_destroy_inode,
	.statfs =	simple_statfs,
};
```

# socket的创建

## 重要数据结构
### socket
socket是公用属性集合，与协议无关
```c
struct socket {
	socket_state		state;
	unsigned long		flags;
	const struct proto_ops	*ops;
	struct fasync_struct	*fasync_list; // 异步唤醒队列
	struct file		*file;
	struct sock		*sk; // sock 代表具体协议内容
	wait_queue_head_t	wait; // 等待队列
	short			type; // socket的类型
};
```
### sock
sock 和协议相关，每种协议的sock都不同
```c
struct sock {
	/*
	 * Now struct inet_timewait_sock also uses sock_common, so please just
	 * don't add nothing before this first member (__sk_common) --acme
	 */
	struct sock_common	__sk_common;
#define sk_family		__sk_common.skc_family
#define sk_state		__sk_common.skc_state
#define sk_reuse		__sk_common.skc_reuse
#define sk_bound_dev_if		__sk_common.skc_bound_dev_if
#define sk_node			__sk_common.skc_node
#define sk_bind_node		__sk_common.skc_bind_node
#define sk_refcnt		__sk_common.skc_refcnt
#define sk_hash			__sk_common.skc_hash
#define sk_prot			__sk_common.skc_prot
#define sk_net			__sk_common.skc_net
	unsigned char		sk_shutdown : 2,
				sk_no_check : 2,
				sk_userlocks : 4;
	unsigned char		sk_protocol;
	unsigned short		sk_type;
	int			sk_rcvbuf;
	socket_lock_t		sk_lock;
	/*
	 * The backlog queue is special, it is always used with
	 * the per-socket spinlock held and requires low latency
	 * access. Therefore we special case it's implementation.
	 */
	struct {
		struct sk_buff *head;
		struct sk_buff *tail;
	} sk_backlog;
	wait_queue_head_t	*sk_sleep;
	struct dst_entry	*sk_dst_cache;
	struct xfrm_policy	*sk_policy[2];
	rwlock_t		sk_dst_lock;
	atomic_t		sk_rmem_alloc;
	atomic_t		sk_wmem_alloc;
	atomic_t		sk_omem_alloc;
	int			sk_sndbuf;
	struct sk_buff_head	sk_receive_queue;
	struct sk_buff_head	sk_write_queue;
	struct sk_buff_head	sk_async_wait_queue;
	int			sk_wmem_queued;
	int			sk_forward_alloc;
	gfp_t			sk_allocation;
	int			sk_route_caps;
	int			sk_gso_type;
	unsigned int		sk_gso_max_size;
	int			sk_rcvlowat;
	unsigned long 		sk_flags;
	unsigned long	        sk_lingertime;
	struct sk_buff_head	sk_error_queue;
	struct proto		*sk_prot_creator;
	rwlock_t		sk_callback_lock;
	int			sk_err,
				sk_err_soft;
	atomic_t		sk_drops;
	unsigned short		sk_ack_backlog;
	unsigned short		sk_max_ack_backlog;
	__u32			sk_priority;
	struct ucred		sk_peercred;
	long			sk_rcvtimeo;
	long			sk_sndtimeo;
	struct sk_filter      	*sk_filter;
	void			*sk_protinfo;
	struct timer_list	sk_timer;
	ktime_t			sk_stamp;
	struct socket		*sk_socket;
	void			*sk_user_data;
	struct page		*sk_sndmsg_page;
	struct sk_buff		*sk_send_head;
	__u32			sk_sndmsg_off;
	int			sk_write_pending;
	void			*sk_security;
	__u32			sk_mark;
	/* XXX 4 bytes hole on 64 bit */
	void			(*sk_state_change)(struct sock *sk);
	void			(*sk_data_ready)(struct sock *sk, int bytes);
	void			(*sk_write_space)(struct sock *sk);
	void			(*sk_error_report)(struct sock *sk);
  	int			(*sk_backlog_rcv)(struct sock *sk,
						  struct sk_buff *skb);  
	void                    (*sk_destruct)(struct sock *sk);
};
```
### sk_buff
每种协议都是对 sk_buff 进行封装，每个数据包都对应一个sk_buff
```c
struct sk_buff {
	/* These two members must be first. */
	struct sk_buff		*next;
	struct sk_buff		*prev;

	struct sock		*sk;
	ktime_t			tstamp;
	struct net_device	*dev;

	union {
		struct  dst_entry	*dst;
		struct  rtable		*rtable;
	};
	struct	sec_path	*sp;

	/*
	 * This is the control buffer. It is free to use for every
	 * layer. Please put your private variables there. If you
	 * want to keep them across layers you have to do a skb_clone()
	 * first. This is owned by whoever has the skb queued ATM.
	 */
	char			cb[48];

	unsigned int		len,
				data_len;
	__u16			mac_len,
				hdr_len;
	union {
		__wsum		csum;
		struct {
			__u16	csum_start;
			__u16	csum_offset;
		};
	};
	__u32			priority;
	__u8			local_df:1,
				cloned:1,
				ip_summed:2,
				nohdr:1,
				nfctinfo:3;
	__u8			pkt_type:3,
				fclone:2,
				ipvs_property:1,
				peeked:1,
				nf_trace:1;
	__be16			protocol;

	void			(*destructor)(struct sk_buff *skb);
#if defined(CONFIG_NF_CONNTRACK) || defined(CONFIG_NF_CONNTRACK_MODULE)
	struct nf_conntrack	*nfct;
	struct sk_buff		*nfct_reasm;
#endif
#ifdef CONFIG_BRIDGE_NETFILTER
	struct nf_bridge_info	*nf_bridge;
#endif

	int			iif;
#ifdef CONFIG_NETDEVICES_MULTIQUEUE
	__u16			queue_mapping;
#endif
#ifdef CONFIG_NET_SCHED
	__u16			tc_index;	/* traffic control index */
#ifdef CONFIG_NET_CLS_ACT
	__u16			tc_verd;	/* traffic control verdict */
#endif
#endif
#ifdef CONFIG_IPV6_NDISC_NODETYPE
	__u8			ndisc_nodetype:2;
#endif
	/* 14 bit hole */

#ifdef CONFIG_NET_DMA
	dma_cookie_t		dma_cookie;
#endif
#ifdef CONFIG_NETWORK_SECMARK
	__u32			secmark;
#endif

	__u32			mark;

	sk_buff_data_t		transport_header;
	sk_buff_data_t		network_header;
	sk_buff_data_t		mac_header;
	/* These elements must be at the end, see alloc_skb() for details.  */
	sk_buff_data_t		tail;
	sk_buff_data_t		end;
	unsigned char		*head,
				*data;
	unsigned int		truesize;
	atomic_t		users;
};
```
## sys_socket
socket系统调用最终由sock_create处理
```c
long sys_socket(int family, int type, int protocol)
	struct socket *sock;
	retval = sock_create(family, type, protocol, &sock); //根据协议创建sock
	retval = sock_map_fd(sock); // 分配file,将sock和file绑定,分配fd，安装file
	return retval; // 返回文件描述符
```

### sock_map_fd
sock_map_fd 将 socket 映射到 fd
```c
int sock_map_fd(struct socket *sock)
{
	struct file *newfile;
	int fd = sock_alloc_fd(&newfile); // 分配空闲fd, 分配 struct file
		fd = get_unused_fd();
		return fd;

	if (likely(fd >= 0)) {
		int err = sock_attach_fd(sock, newfile);
			struct qstr name = { .name = "" };

			dentry = d_alloc(sock_mnt->mnt_sb->s_root, &name);  // 分配dentry,初始化
																// 设置sb,和parent
				dentry = kmem_cache_alloc(dentry_cache, GFP_KERNEL);
				dentry->d_parent = dget(parent);
				dentry->d_sb = parent->d_sb;
				...

			dentry->d_op = &sockfs_dentry_operations;
			d_instantiate(dentry, SOCK_INODE(sock)); // 将dentry 和 sock相关inode绑定
			sock->file = file;

			init_file(file, sock_mnt, dentry, FMODE_READ | FMODE_WRITE,
				  &socket_file_ops);
				file->f_op = fop; // socket_file_ops

			SOCK_INODE(sock)->i_fop = &socket_file_ops;
			file->f_flags = O_RDWR;
			file->f_pos = 0;
			file->private_data = sock;

		if (unlikely(err < 0)) {
			put_filp(newfile);
			put_unused_fd(fd);
			return err;
		}
		fd_install(fd, newfile); // 将file安装到进程的文件会话数组
	}
	return fd;
}
```

### sock_create
1. 分配并建立关系file fd inode
2. 分配并建立关系socket sock prot
最终建立关系
![](./pic/1.jpg)
```c
int sock_create(int family, int type, int protocol, struct socket **res)
	return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);

struct socket_alloc {
	struct socket socket;
	struct inode vfs_inode;
};

static int __sock_create(struct net *net, int family, int type, int protocol,
			 struct socket **res, int kern)
{
	int err;
	struct socket *sock;
	const struct net_proto_family *pf;

	// 检查协议合法
	if (family < 0 || family >= NPROTO)
		return -EAFNOSUPPORT;
	if (type < 0 || type >= SOCK_MAX)
		return -EINVAL;

	...

	sock = sock_alloc(); // 创建socket
		struct inode *inode;
		struct socket *sock;

		inode = new_inode(sock_mnt->mnt_sb);
			struct inode *sock_alloc_inode(struct super_block *sb)
				struct socket_alloc *ei;
				...
				ei = kmem_cache_alloc(sock_inode_cachep, GFP_KERNEL);
				ei->socket.state = SS_UNCONNECTED;
				return &ei->vfs_inode;

		sock = SOCKET_I(inode);
		inode->i_mode = S_IFSOCK | S_IRWXUGO; // S_IFSOCK极可能用于上层操作的路由
		inode->i_uid = current->fsuid;
		inode->i_gid = current->fsgid;
		return sock;


	sock->type = type; // 记录sock类型

	pf = rcu_dereference(net_families[family]); // 获得协议族操作函数表

	err = pf->create(net, sock, protocol); 	// 执行协议族创建
											// 如果 family为 AF_INET
											// 则调用 inet_create
											// 完成创建 sock, 找到 prot
											// 绑定 socket的sock，sock 的 prot
											// 初始化 socket , sock

	*res = sock; // 返回socket

	return 0;
}
```

那么 net_families[] 在哪里添加呢
```c
int sock_register(const struct net_proto_family *ops)
{
	int err;

	if (net_families[ops->family])
		err = -EEXIST;
	else {
		net_families[ops->family] = ops;
		err = 0;
	}

	return err;
}
```

在每个协议都调用 sock_register，如 AF_INET
```c
// AF_INET
static struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,
	.owner	= THIS_MODULE,
};

static int __init inet_init(void)
	(void)sock_register(&inet_family_ops);

// AF_UNIX
static struct net_proto_family unix_family_ops = {
	.family = PF_UNIX,
	.create = unix_create,
	.owner	= THIS_MODULE,
};

static int __init af_unix_init(void)
	sock_register(&unix_family_ops);
```

如果使用AF_INET调用 socket，则 sock_create -> inet_create
### inet_create
大致完成下述功能
0. 根据protocol 找到 struct prot prot
1. 分配struct sock sk, 绑定 sock  prot socket
2. 初始化 socket sock
```c
static int inet_create(struct net *net, struct socket *sock, int protocol)
{
	struct sock *sk;
	struct list_head *p;
	struct inet_protosw *answer;
	struct inet_sock *inet;
	struct proto *answer_prot;
	unsigned char answer_flags;
	char answer_no_check;
	int try_loading_module = 0;
	int err;

	if (sock->type != SOCK_RAW &&
	    sock->type != SOCK_DGRAM &&
	    !inet_ehash_secret)
		build_ehash_secret();

	sock->state = SS_UNCONNECTED;

	/* Look for the requested type/protocol pair. */
	answer = NULL;
lookup_protocol:
	err = -ESOCKTNOSUPPORT;
	rcu_read_lock();

	// protocol 有三种 
	// 	IPPROTO_IP :  虚拟IP类型，和SOCK_RAW 使用，表示原始套接字
	//	IPPROTO_TCP : 和 SOCK_STREAM 使用，表示TCP
	//	IPPROTO_UDP : 和 SOCK_DGRAM 使用，表示UDP
	//
	// static struct list_head inetsw[SOCK_MAX]; 预先注册好的 struct inet_protosw
	// inet_init -> inet_register_protosw 完成注册
	list_for_each_rcu(p, &inetsw[sock->type]) {
		answer = list_entry(p, struct inet_protosw, list);

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
		answer = NULL;
	}

	if (unlikely(answer == NULL)) {
		if (try_loading_module < 2) {
			rcu_read_unlock();
			/*
			 * Be more specific, e.g. net-pf-2-proto-132-type-1
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP-type-SOCK_STREAM)
			 */
			if (++try_loading_module == 1)
				request_module("net-pf-%d-proto-%d-type-%d",
					       PF_INET, protocol, sock->type);
			/*
			 * Fall back to generic, e.g. net-pf-2-proto-132
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP)
			 */
			else
				request_module("net-pf-%d-proto-%d",
					       PF_INET, protocol);
			goto lookup_protocol;
		} else
			goto out_rcu_unlock;
	}

	err = -EPERM;
	if (answer->capability > 0 && !capable(answer->capability))
		goto out_rcu_unlock;

	err = -EAFNOSUPPORT;
	if (!inet_netns_ok(net, protocol))
		goto out_rcu_unlock;

	// 如果protocol 为 IPPROTO_TCP , 则 answer 为 inetsw_array[0]
	// 则下面的值为

	sock->ops = answer->ops;			// inet_stream_ops
	answer_prot = answer->prot;			// tcp_prot
	answer_no_check = answer->no_check;	// 0
	answer_flags = answer->flags;		// INET_PROTOSW_PERMANENT | INET_PROTOSW_ICSK
	rcu_read_unlock();

	BUG_TRAP(answer_prot->slab != NULL);

	err = -ENOBUFS;
	sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot);
			struct sock *sk_alloc(struct net *net, int family, gfp_t priority,
					  struct proto *prot)
			struct sock *sk;
			sk = sk_prot_alloc(prot, priority | __GFP_ZERO, family);
			sk->sk_family = family;
			sk->sk_prot = sk->sk_prot_creator = prot; // 建立struct sock和 struct proto 关系
														// 此处 sk->sk_prot为 tcp_prot
			sock_net_set(sk, get_net(net)); // sk->sk_net = net;

	err = 0;
	sk->sk_no_check = answer_no_check;
	if (INET_PROTOSW_REUSE & answer_flags)
		sk->sk_reuse = 1;

	inet = inet_sk(sk);
	inet->is_icsk = (INET_PROTOSW_ICSK & answer_flags) != 0;

	if (SOCK_RAW == sock->type) {
		inet->num = protocol;
		if (IPPROTO_RAW == protocol)
			inet->hdrincl = 1;
	}

	if (ipv4_config.no_pmtu_disc)
		inet->pmtudisc = IP_PMTUDISC_DONT;
	else
		inet->pmtudisc = IP_PMTUDISC_WANT;

	inet->id = 0;

	sock_init_data(sock, sk); // 绑定 struct socket  和 struct sock
		void sock_init_data(struct socket *sock, struct sock *sk)
		sock->sk	=	sk;
		...

	sk->sk_destruct	   = inet_sock_destruct;
	sk->sk_family	   = PF_INET;
	sk->sk_protocol	   = protocol;
	sk->sk_backlog_rcv = sk->sk_prot->backlog_rcv;

	inet->uc_ttl	= -1;
	inet->mc_loop	= 1;
	inet->mc_ttl	= 1;
	inet->mc_index	= 0;
	inet->mc_list	= NULL;

	sk_refcnt_debug_inc(sk);

	if (inet->num) {
		/* It assumes that any protocol which allows
		 * the user to assign a number at socket
		 * creation time automatically
		 * shares.
		 */
		inet->sport = htons(inet->num);
		/* Add to protocol hash chains. */
		sk->sk_prot->hash(sk);
	}

	if (sk->sk_prot->init) {
		err = sk->sk_prot->init(sk); // tcp_v4_init_sock
		if (err)
			sk_common_release(sk);
	}
out:
	return err;
out_rcu_unlock:
	rcu_read_unlock();
	goto out;
}
```

#### tcp_v4_init_sock
```c
static int tcp_v4_init_sock(struct sock *sk)
	struct inet_connection_sock *icsk = inet_csk(sk);
	struct tcp_sock *tp = tcp_sk(sk);

	skb_queue_head_init(&tp->out_of_order_queue);
	tcp_init_xmit_timers(sk);
	tcp_prequeue_init(tp);

	icsk->icsk_rto = TCP_TIMEOUT_INIT;
	tp->mdev = TCP_TIMEOUT_INIT;

	tp->snd_cwnd = 2;

	tp->snd_ssthresh = 0x7fffffff;	/* Infinity */
	tp->snd_cwnd_clamp = ~0;
	tp->mss_cache = 536;

	tp->reordering = sysctl_tcp_reordering;
	icsk->icsk_ca_ops = &tcp_init_congestion_ops;

	sk->sk_state = TCP_CLOSE;

	sk->sk_write_space = sk_stream_write_space;
	sock_set_flag(sk, SOCK_USE_WRITE_QUEUE);

	icsk->icsk_af_ops = &ipv4_specific;
	icsk->icsk_sync_mss = tcp_sync_mss;

	sk->sk_sndbuf = sysctl_tcp_wmem[1];
	sk->sk_rcvbuf = sysctl_tcp_rmem[1];
```
##### sock inet_sock inet_connection_sock tcp_sock 的关系
```c
struct sock {
	/*
	 * Now struct inet_timewait_sock also uses sock_common, so please just
	 * don't add nothing before this first member (__sk_common) --acme
	 */
	struct sock_common	__sk_common;
	...

struct inet_sock {
	/* sk and pinet6 has to be the first two members of inet_sock */
	struct sock		sk;
	...

struct inet_connection_sock {
	/* inet_sock has to be the first member! */
	struct inet_sock	  icsk_inet;
	...

struct tcp_sock {
	/* inet_connection_sock has to be the first member of tcp_sock */
	struct inet_connection_sock	inet_conn;
	...

```
sock 派生 inet_sock 派生 inet_connection_sock 派生 tcp_sock
他们的关系
![](./pic/2.jpg)

### sock的构造和协议的注册
以 family 为 AF_INET 为例
```c
static int __init inet_init(void)
	// 注册AF_INET支持的协议
	// struct proto 类型
	// proto_register 将 prot 加入 proto_list 全局变量
	rc = proto_register(&tcp_prot, 1);
	rc = proto_register(&udp_prot, 1);
	rc = proto_register(&raw_prot, 1);

	// 安装协议族的ops到 net_families
	(void)sock_register(&inet_family_ops);

	// 安装基础协议
	// struct net_protocol 类型
	// 将 net_protocol 注册到 inet_protos[]
	if (inet_add_protocol(&icmp_protocol, IPPROTO_ICMP) < 0)
		printk(KERN_CRIT "inet_init: Cannot add ICMP protocol\n");
	if (inet_add_protocol(&udp_protocol, IPPROTO_UDP) < 0)
		printk(KERN_CRIT "inet_init: Cannot add UDP protocol\n");
	if (inet_add_protocol(&tcp_protocol, IPPROTO_TCP) < 0)
		printk(KERN_CRIT "inet_init: Cannot add TCP protocol\n");

	/* Register the socket-side information for inet_create. */
	// static struct list_head inetsw[SOCK_MAX];
	struct list_head *r;
	for (r = &inetsw[0]; r < &inetsw[SOCK_MAX]; ++r)
		INIT_LIST_HEAD(r);

	struct inet_protosw *q;
	for (q = inetsw_array; q < &inetsw_array[INETSW_ARRAY_LEN]; ++q)
		inet_register_protosw(q); // 将 inetsw_array[] 元素 安装到 inetsw[p->type] 链表

			void inet_register_protosw(struct inet_protosw *p)
			// 找到链表最后节点 last_perm
			last_perm = &inetsw[p->type];
			list_for_each(lh, &inetsw[p->type]) {
				answer = list_entry(lh, struct inet_protosw, list);
				if (INET_PROTOSW_PERMANENT & answer->flags) {
					if (protocol == answer->protocol)
						break;
					last_perm = lh;
				}

				answer = NULL;
			}
			if (answer)
				goto out_permanent;
			// 将新的协议 struct inet_protosw 添加到链表尾部
			list_add_rcu(&p->list, last_perm);

	....

```

#### inetsw_array
```c
static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.capability = -1,
		.no_check =   0,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},

	{
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_UDP,
		.prot =       &udp_prot,
		.ops =        &inet_dgram_ops,
		.capability = -1,
		.no_check =   UDP_CSUM_DEFAULT,
		.flags =      INET_PROTOSW_PERMANENT,
       },


       {
	       .type =       SOCK_RAW,
	       .protocol =   IPPROTO_IP,	/* wild card */
	       .prot =       &raw_prot,
	       .ops =        &inet_sockraw_ops,
	       .capability = CAP_NET_RAW,
	       .no_check =   UDP_CSUM_DEFAULT,
	       .flags =      INET_PROTOSW_REUSE,
       }
};
```


#### proto_register
```c
static LIST_HEAD(proto_list);

int proto_register(struct proto *prot, int alloc_slab)
	if (alloc_slab) {
		// 构造slab
		prot->slab = kmem_cache_create(prot->name, prot->obj_size, 0,
					       SLAB_HWCACHE_ALIGN, NULL);
						   ...
		prot->rsk_prot->slab = kmem_cache_create(request_sock_slab_name,
							 prot->rsk_prot->obj_size, 0,
							 SLAB_HWCACHE_ALIGN, NULL);
		prot->twsk_prot->twsk_slab =
			kmem_cache_create(timewait_sock_slab_name,
					  prot->twsk_prot->twsk_obj_size,
					  0, SLAB_HWCACHE_ALIGN,
					  NULL);
	}

	list_add(&prot->node, &proto_list);
```

#### inet_add_protocol
```c
int inet_add_protocol(struct net_protocol *prot, unsigned char protocol)
	hash = protocol & (MAX_INET_PROTOS - 1);
	inet_protos[hash] = prot;

```

#### struct proto
```c
struct proto {
	void			(*close)(struct sock *sk, 
					long timeout);
	int			(*connect)(struct sock *sk,
				        struct sockaddr *uaddr, 
					int addr_len);
	int			(*disconnect)(struct sock *sk, int flags);

	struct sock *		(*accept) (struct sock *sk, int flags, int *err);

	int			(*ioctl)(struct sock *sk, int cmd,
					 unsigned long arg);
	int			(*init)(struct sock *sk);
	int			(*destroy)(struct sock *sk);
	void			(*shutdown)(struct sock *sk, int how);
	int			(*setsockopt)(struct sock *sk, int level, 
					int optname, char __user *optval,
					int optlen);
	int			(*getsockopt)(struct sock *sk, int level, 
					int optname, char __user *optval, 
					int __user *option);  	 
	int			(*compat_setsockopt)(struct sock *sk,
					int level,
					int optname, char __user *optval,
					int optlen);
	int			(*compat_getsockopt)(struct sock *sk,
					int level,
					int optname, char __user *optval,
					int __user *option);
	int			(*sendmsg)(struct kiocb *iocb, struct sock *sk,
					   struct msghdr *msg, size_t len);
	int			(*recvmsg)(struct kiocb *iocb, struct sock *sk,
					   struct msghdr *msg,
					size_t len, int noblock, int flags, 
					int *addr_len);
	int			(*sendpage)(struct sock *sk, struct page *page,
					int offset, size_t size, int flags);
	int			(*bind)(struct sock *sk, 
					struct sockaddr *uaddr, int addr_len);

	int			(*backlog_rcv) (struct sock *sk, 
						struct sk_buff *skb);

	/* Keeping track of sk's, looking them up, and port selection methods. */
	void			(*hash)(struct sock *sk);
	void			(*unhash)(struct sock *sk);
	int			(*get_port)(struct sock *sk, unsigned short snum);

	/* Keeping track of sockets in use */
#ifdef CONFIG_PROC_FS
	unsigned int		inuse_idx;
#endif

	/* Memory pressure */
	void			(*enter_memory_pressure)(void);
	atomic_t		*memory_allocated;	/* Current allocated memory. */
	atomic_t		*sockets_allocated;	/* Current number of sockets. */
	/*
	 * Pressure flag: try to collapse.
	 * Technical note: it is used by multiple contexts non atomically.
	 * All the __sk_mem_schedule() is of this nature: accounting
	 * is strict, actions are advisory and have some latency.
	 */
	int			*memory_pressure;
	int			*sysctl_mem;
	int			*sysctl_wmem;
	int			*sysctl_rmem;
	int			max_header;

	struct kmem_cache		*slab;
	unsigned int		obj_size;

	atomic_t		*orphan_count;

	struct request_sock_ops	*rsk_prot;
	struct timewait_sock_ops *twsk_prot;

	union {
		struct inet_hashinfo	*hashinfo;
		struct hlist_head	*udp_hash;
		struct raw_hashinfo	*raw_hash;
	} h;

	struct module		*owner;

	char			name[32];

	struct list_head	node;
#ifdef SOCK_REFCNT_DEBUG
	atomic_t		socks;
#endif
};
```
# 地址设置
从bind出发
## sys_bind
```c
asmlinkage long sys_bind(int fd, struct sockaddr __user *umyaddr, int addrlen)
{
	struct socket *sock;
	char address[MAX_SOCK_ADDR];
	int err, fput_needed;

	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	if (sock) {

		err = move_addr_to_kernel(umyaddr, addrlen, address);
			int move_addr_to_kernel(void __user *uaddr, int ulen, void *kaddr)
				if (copy_from_user(kaddr, uaddr, ulen))
					return -EFAULT;
				return audit_sockaddr(ulen, kaddr);

		if (err >= 0) {
			err = security_socket_bind(sock,
						   (struct sockaddr *)address,
						   addrlen);
			if (!err)
				// sock->ops = inet_stream_ops; // set in inet_create
				err = sock->ops->bind(sock,
						      (struct sockaddr *)
						      address, addrlen); // inet_bind
		}
		fput_light(sock->file, fput_needed);
	}
	return err;
}
```

### 从fd找到socket
```c
static struct socket *sockfd_lookup_light(int fd, int *err, int *fput_needed)
{
	struct file *file;
	struct socket *sock;

	*err = -EBADF;
	file = fget_light(fd, fput_needed);
	if (file) {
		sock = sock_from_file(file, err);
			static struct socket *sock_from_file(struct file *file, int *err)
				if (file->f_op == &socket_file_ops)
					return file->private_data;	/* set in sock_map_fd */
		if (sock)
			return sock;
		fput_light(file, *fput_needed);
	}
	return NULL;
}
```

## inet_bind
```c
int inet_bind(struct socket *sock, struct sockaddr *uaddr, int addr_len)
{
	struct sockaddr_in *addr = (struct sockaddr_in *)uaddr;
	struct sock *sk = sock->sk;
	struct inet_sock *inet = inet_sk(sk);
	unsigned short snum;
	int chk_addr_ret;
	int err;

	/* If the socket has its own bind function then use it. (RAW) */
	if (sk->sk_prot->bind) { // tcp_prot 没有自己的的 bind
		err = sk->sk_prot->bind(sk, uaddr, addr_len);
		goto out;
	}
	err = -EINVAL;
	if (addr_len < sizeof(struct sockaddr_in))
		goto out;

	chk_addr_ret = inet_addr_type(sock_net(sk), addr->sin_addr.s_addr);

	err = -EADDRNOTAVAIL;
	if (!sysctl_ip_nonlocal_bind &&
	    !inet->freebind &&
	    addr->sin_addr.s_addr != htonl(INADDR_ANY) &&
	    chk_addr_ret != RTN_LOCAL &&
	    chk_addr_ret != RTN_MULTICAST &&
	    chk_addr_ret != RTN_BROADCAST)
		goto out;

	snum = ntohs(addr->sin_port);
	err = -EACCES;
	if (snum && snum < PROT_SOCK && !capable(CAP_NET_BIND_SERVICE))
		goto out;

	lock_sock(sk);

	/* Check these errors (active socket, double bind). */
	err = -EINVAL;
	// tcp初始化后 sk->sk_state = TCP_CLOSE;
	if (sk->sk_state != TCP_CLOSE || inet->num)
		goto out_release_sock;

	// 设置源地址
	inet->rcv_saddr = inet->saddr = addr->sin_addr.s_addr;
	if (chk_addr_ret == RTN_MULTICAST || chk_addr_ret == RTN_BROADCAST)
		inet->saddr = 0;  /* Use device */

	/* Make sure we are allowed to bind here. */
	// 对于tcp是 inet_csk_get_port,
	if (sk->sk_prot->get_port(sk, snum)) {
		inet->saddr = inet->rcv_saddr = 0;
		err = -EADDRINUSE;
		goto out_release_sock;
	}

	if (inet->rcv_saddr)
		sk->sk_userlocks |= SOCK_BINDADDR_LOCK;
	if (snum)
		sk->sk_userlocks |= SOCK_BINDPORT_LOCK;
	
	// 设置源端口
	inet->sport = htons(inet->num);

	// 初始化目标地址目标端口
	inet->daddr = 0;
	inet->dport = 0;

	sk_dst_reset(sk);
	err = 0;
out_release_sock:
	release_sock(sk);
out:
	return err;
}

```
