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
## sock_create
socket系统调用最终由sock_create处理
```c
long sys_socket(int family, int type, int protocol)
	struct socket *sock;
	retval = sock_create(family, type, protocol, &sock); //根据协议创建sock
	retval = sock_map_fd(sock); // 分配file,将sock和file绑定,分配fd，安装file
	return retval; // 返回文件描述符
```

sock_map_fd 将 socket 映射到 fd
```c
int sock_map_fd(struct socket *sock)
{
	struct file *newfile;
	int fd = sock_alloc_fd(&newfile);
		fd = get_unused_fd();
		return fd;

	if (likely(fd >= 0)) {
		int err = sock_attach_fd(sock, newfile);
			dentry = d_alloc(sock_mnt->mnt_sb->s_root, &name);
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

sock_create
```c
int sock_create(int family, int type, int protocol, struct socket **res)
	return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);


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

	sock = sock_alloc(); // 创建sock
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

	err = pf->create(net, sock, protocol); // 执行协议族创建

	*res = sock; // 返回sock

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

	sock->ops = answer->ops;
	answer_prot = answer->prot;
	answer_no_check = answer->no_check;
	answer_flags = answer->flags;
	rcu_read_unlock();

	BUG_TRAP(answer_prot->slab != NULL);

	err = -ENOBUFS;
	sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot);
	if (sk == NULL)
		goto out;

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

	sock_init_data(sock, sk);

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
		err = sk->sk_prot->init(sk);
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
