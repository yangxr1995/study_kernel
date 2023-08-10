# 1. 设计
## 什么是 socket buffer
socket buffer 是网络数据包的数据结构。
对socket buffer 的读写操作贯穿TCP/IP各层，为了避免TCP/IP各层都对socket buffer直接修改，而导致程序混乱，
和socket buffer一旦改变TCP/IP各层都需要修改，
所以skbuff 实现了操作接口。对skbuff的读写必须通过他的接口。

## socket buffer的结构
Linux内核网络子系统设计的目的是使网络子系统的实现独立于特定网络协议，
各种网络协议不需要做大改动就能直接加入到TCP/IP协议栈的任何层次中。

skbuff 定义在 skbuff.h 中
![](./pic/55.jpg)
如上所示，一个完整的socket buffer 由两部分组成：
* 数据缓冲区：存放实际要在网络中传送的数据缓存区
* 管理数据结构（struct sk_buff）：当内核处理数据包时，内核需要其他数据来管理和操作数据包，如数据接受、发送事件，状态等。

## socketbuffer 穿越TCP/IP协议栈
下图显示 socket buffer 穿越TCP/IP协议栈的过程

![](./pic/56.jpg)

可见使用 socket buffer 传输数据只需要复制两次，
一次是从应用程序的用户空间复制到内核空间，
一次是从内核空间复制到网络适配器的硬件缓存。

### 发送数据包
当应用数据从用户空间拷贝到内核空间，内核套接字层创建 socket buffer，将数据放到数据缓冲区，将数据缓冲区的地址，数据长度等信息
记录到 sk_buff,随着 socket buffer 从上到下穿越TCP/IP协议栈时，各层期间会发生如下事件：
* 各层协议头数据会依次插入到数据缓冲区
* 随着数据缓冲区的更新，sk_buff 中描述协议头数据的地址指针会被赋值。
所以 socket buffer 在创建时，应该一次分配足够空间，用于存放后期增加的协议头数据。

### 接受数据包
当网络适配器接收到发送给本机的数据包后，产生中断通知内核收到了网络数据帧 ，
网卡驱动程序的中断处理程序会调用 dev_alloc_skb 向系统申请一个 socket buffer，
从网卡缓存区复制网络数据帧到 socket buffer的数据缓存区，并设置 sk_buff 各个域：地址，时间，协议等。
当 socket buffer 从下到上穿越TCP/IP协议栈时，会发生如下事件
* sk_buff 各层协议头指针会被依次复位，sk_buff->data 指针会指向有效数据


# 2. socket buffer 结构详解
sk_buff域从功能上大致可以分为：
* 结构管理
* 常规数据
* 网络功能配置相关

## 结构管理域
```c
struct sk_buff {

	// 按照 sk_buff 不同的状态会被组织到不同的队列
	// 如此当 sk_buff 状态变化时，只需要出队列和入队列操作，
	// 避免复制和释放操作
	struct sk_buff		*next;
	struct sk_buff		*prev;

	...

	// 相关的套接字，
	// 如果 sk_buff 是入栈，则 sk 指向接受报文的套接字
	// 如果 sk_buff 是出战，则 sk 指向发送报文的套接字
	// 如果 sk_buff 是转发，则 sk 为 NULL
	struct sock		*sk;

	....

	// 析构函数，通常为NULL
	void		(*destructor)(struct sk_buff *skb);

	...

	// len : 数据包的总长度
	// data_len : 本sk_buff对应数据包（分片）的长度
	// mac_len : MAC层头信息的长度
	// hdr_len : 数据包的头部长度
	unsigned int		len,
				data_len;
	__u16			mac_len,
				hdr_len;
	...

	// 使用本 sk_buff 的进程的引用计数
	refcount_t		users;

	// 整个socket buffer 的大小，包括 sk_buff 和 数据缓冲区的长度
	unsigned int		truesize;

	// head, end : 分别指向数据缓冲区的首尾
	// data, tail : 分配指向 有效负荷（包括协议头和用户数据）的首尾
	sk_buff_data_t		tail;
	sk_buff_data_t		end;
	unsigned char		*head,
				*data;
```

1. next prev
socket buffer 会根据其状态和类型（接受，发送，已处理完成）存放在不同的队列，队列使用双向链表实现，
队列的头部定义如下
```c
struct sk_buff_head {
	struct sk_buff	*next;
	struct sk_buff	*prev;

	__u32		qlen; // 本队列元素数量
	spinlock_t	lock;

};
```
![](./pic/4.jpg)

2. struct sock \*sk
指向拥有该socket buffer的套接字(所谓套接字就是地址加端口，用于唯一识别网络应用程序)，
当向外发送，或从网络来的数据的目标地址是本机应用程序时，会设置此项。
当转发数据包时，此项为NULL。
sk_buff->sk 表示最终应该传输给哪个应用程序，或是哪个程序发送的。

3. len
sk_buff->len 指 socket buffer 中数据包的总长度，
包括：
主缓冲区的数据长度（由sk_buff->head指向）、
各个分片数据的长度（当数据包长度大于网络适配器一次能传输的最大传输单元MTU时，数据包会被分成更小的断）
协议头数据的长度(可见socket buffer穿越TCP/IP时会修改 len)

4. data_len
分片的数据块长度

5. mac_len
链路层协议头的长度

6. hdr_len
hdr_len 用于克隆数据包，表明克隆数据包的头长度。
当克隆数据包时，只做纯数据的克隆（即不克隆数据包的协议头信息），这时需要从 hdr_len获得头长度。

7. users
对所有正在使用该sk_buff的进程数量的引用计数。
另外对 socket buffer 的数据缓存区的引用计数是dataref

使用引用计数是为了避免一个进程还在使用socket buffer时，被另一个进程释放掉。

8. truesize
整个socket buffer的大小，即sk_buff和数据包的长度和。
```c
truesize = data_len + sizeof(struct sk_buff)
alloc_skb(truesize);
```

9. tail end head data
![](./pic/5.jpg)
socket buffer数据包缓冲区包括：TCP/IP协议头和尾部检验信息，负载数据。
head end 指向整个数据包缓冲区的首尾。
data tail 负载数据
head data 之间用于添加协议头
tail end 协议包尾部

10. destructor
指向Socket buffer的析构函数，当sk_buff不属于任何套接字时，析构函数通常不需要初始化。

## 常规数据域
```c
struct sk_buff {
	...
	// 入栈时间
	ktime_t		tstamp;
	..
	// 相关网络适配器
	struct net_device	*dev;
	// 网络适配器的索引号
	int			skb_iif;
	...
	// 控制缓存，存放私有变量或数据的地方
	char			cb[48] __aligned(8);
	...
	__u8			ip_summed:2;
	union {
		__wsum		csum;
		struct {
			__u16	csum_start;
			__u16	csum_offset;
		};
	};
	...
	__u32			priority;
	...
	__be16			protocol;
	...
	__u16			queue_mapping;
	...
	unsigned long	_skb_refdst;
	...
	__u32		mark;
	...
	__u16			vlan_tci;
	...
	__u16			transport_header;
	__u16			network_header;
	__u16			mac_header;
```
1. tstamp
数据包到达内核的时间，
网卡驱动将数据包从网卡缓存拷贝到内核时进行赋值。

2. dev skb_iif
dev 指向net_device，net_device就是网络适配器在内核中的实例，此处说明此 sk_buff 由哪个网口输入或输出
skb_iif 网络适配器的索引号，Linux中某种类型的网络设备的命名方式是设备名加顺序索引号，如 Ethernet 设备： eth0 eth1

3. dst rtable
当数据包入栈，出栈，转发，都需要查询路由表，将查询的结果保存到 sk_buff 中，
方便后续操作直接使用，避免再次查询。

4. cb
控制缓冲区（control buffer），是各个协议处理数据包时，存放私有变量或数据的地方。
如udp的cb 为 udp_skb_cb
```c
struct udp_skb_cb {
	union {
		struct inet_skb_parm	h4;
#if IS_ENABLED(CONFIG_IPV6)
		struct inet6_skb_parm	h6;
#endif
	} header;
	__u16		cscov;
	__u8		partial_cov;
};
#define UDP_SKB_CB(__skb)	((struct udp_skb_cb *)((__skb)->cb))
```
使用cb
```c
udp6_csum_init(struct sk_buff *skb, struct udphdr *uh, int proto)
	UDP_SKB_CB(skb)->partial_cov = 0;
	UDP_SKB_CB(skb)->cscov = skb->len;
```

5. csum
存放校验和，
当发送数据包时，网络子系统计算校验和，存放到 csum.
当接受数据包时，由硬件网络计算校验和，存放到 csum.

csum_start : skb->head 为起始地址的偏移量，指出校验数据从哪里开始计算。
csum_offset : 以 csum_start 为起始的偏移量，指出校验和存放的位置： csum_start + csum_offset

6. priority
用于实现QoS功能特性，QoS描述了数据包的发送优先级。
如果发送本地产生的数据包，priority 的值由 socket层填写。
如果是转发的数据包， priority的值由路由子系统根据包中IP协议头的 ToS域来填写。

7. protocol
接受数据包的网络层协议。标志了网络数据包应该交给TCP/IP协议栈网络层的哪个协议处理函数
由网卡驱动程序填写。

相关 protocol定义在
include/linux/if_ether.h

8. queue_mapping
具备多个缓冲队列的网络设备的队列映射关系。
早期网络设备只有一个数据发送缓冲区，现在很多网络设备有多个发送缓冲区来存放待发送的网络数据包。
queue_mapping 描述了本网络数据所在的队列和设备硬件发送队列的映射关系

9. mark
数据包为常规数据包的标志

10. vlan_tci
VLAN Tag 控制信息

11. transport_header network_header mac_header
指向协议栈中各层协议头在网络数据包的位置
![](./pic/6.jpg)

## 网络功能配置域
Linux网络子系统实现了大量功能，这些功能是模块化的。

1. 连接追踪 
连接追踪可以记录什么数据包经过了你的主机，以及他们是如何进入网络连接的。
sk_buff 相关域
```c
#if defined(CONFIG_NF_CONNTRACK) || defined(CONFIG_NF_CONNTRACK_MODULE)
	unsigned long		 _nfct;
#endif
```

2. 桥防火墙 CONFIG_BRIDGE_NETFILTER

3. 流量控制 CONFIG_NET_SCHED
当内核有多个数据包向外发送时，内核必须决定谁先送，谁后送，谁丢弃，
内核实现了多种算法来选择数据包，如果没有选择此功能，内核发送数据包时就使用FIFO策略。
```c
#ifdef CONFIG_NET_SCHED
	__u16			tc_index;	/* traffic control index */
#endif
```
# 3. 操作sk_buff的函数
为sk_buff实现控制函数，让对sk_buff操作的代码和协议栈解耦合，
之后要添加新的操作sk_buff功能，只需要添加对应函数，不会影响原有代码。

按照功能，这些函数可以分为：
* 创建，释放，复制 socket buffer
* 操作 sk_buff的属性
* 管理 socket buffer 队列
函数集中实现在
skbuff.c 和 skbuff.h 中

## 创建和释放 socket buffer
由于 socket buffer 会频繁的创建释放，
内核在系统初始化时已创建了两个 sk_buff 内存池。
```c
struct kmem_cache *skbuff_head_cache __ro_after_init;
static struct kmem_cache *skbuff_fclone_cache __ro_after_init;
```
这两个内存池由 skb_init 创建。
每当需要分配 sk_buff 时，根据所需的sk_buff 是克隆还是非克隆的，分别从对应cache中获得内存对象，
释放 sk_buff时，就将对象放回以上cache.

### 创建 socket buffer
```c
/*
 * size : 存放数据包需要的内存空间大小
 * gfp_mask : 
 *           GFP_ATOMIC : 在中断处理程序中申请内存，gfp_mask 必须为该值，因为中断不能休眠
 *           GFP_KERNEL : 常规内核函数申请内存分配
 *           其他值
 * fclone : 是否对该 sk_buff 克隆，决定了从哪个sk_buff内存对象池中获取sk_buff所需的空间
 *          0 : skbuff_head_cache
 *          1 : skbuff_fclone_cache
 */
struct sk_buff *__alloc_skb(unsigned int size, gfp_t gfp_mask, int flags, int node)

/*
 * 在调用 __alloc_skb 时，应该调用他的包装函数
 * alloc_skb , alloc_skb_fclone
 */
struct sk_buff *alloc_skb(unsigned int size, gfp_t priority);
	return __alloc_skb(size, priority, 0, NUMA_NO_NODE);
			    
struct sk_buff *alloc_skb_fclone(unsigned int size, gfp_t priority)
	return __alloc_skb(size, priority, SKB_ALLOC_FCLONE/*0x01*/, NUMA_NO_NODE /*-1*/);
```


```c
/*
 * __dev_alloc_skb 是 alloc_skb 的包裹函数，
 * 给网络设备驱动程序使用，当网络设备从网络上收到一个数据包时，
 * 它调用此函数向系统申请缓冲区来存放数据包。
 *
 */
struct sk_buff *__dev_alloc_skb(unsigned int length, gfp_t gfp_mask)
	return __netdev_alloc_skb(NULL, length, gfp_mask);

struct sk_buff *dev_alloc_skb(unsigned int length)
	return netdev_alloc_skb(NULL, length);
```
为了提高效率为数据链路层在数据包缓冲区前预留16字节的headroom .
避免头信息增长时原空间不够导致重新分配空间。
![](./pic/7.jpg)

```c
/*
 * 和__dev_alloc_skb 类似，他为socket buffer指定了dev，因此返回的
 * sk_buff 的 dev域被初始化后返回。
 */

struct sk_buff *netdev_alloc_skb(struct net_device *dev,
					       unsigned int length)
	return __netdev_alloc_skb(dev, length, GFP_ATOMIC);

struct sk_buff *__netdev_alloc_skb(struct net_device *dev, unsigned int len,
				   gfp_t gfp_mask);
```

### 释放 socket buffer
```c

kfree_skb

kfree_release_all

kfree_release_data

kfree_skbmem

dst_release
```

## 数据空间对齐
```c
// 增加预留空间headroom
// headroom 就是 skb->head 到 skb->data 之间的空间
// 用于存放待添加的协议头部
static inline void skb_reserve(struct sk_buff *skb, int len)
{
	skb->data += len;
	skb->tail += len;
}
```

```c
// 网卡驱动接受数据包
net_rx(struct net_device *dev)
	skb = dev_alloc_skb(length + 2);
		__dev_alloc_skb(length, GFP_ATOMIC);
			struct sk_buff *skb = alloc_skb(length + NET_SKB_PAD, gfp_mask);
				__alloc_skb(size, priority, 0, -1);
					// 分配 skb
					skb = kmem_cache_alloc_node(cache, gfp_mask & ~__GFP_DMA, node);
					// 分配 数据缓冲区
					size = SKB_DATA_ALIGN(size);
					data = kmalloc_node_track_caller(size + sizeof(struct skb_shared_info),

					memset(skb, 0, offsetof(struct sk_buff, tail));
					skb->truesize = size + sizeof(struct sk_buff);
					atomic_set(&skb->users, 1);

					// skb->head = data
					// skb->data = data
					// skb->tail = data
					// skb->end = data + size;
					skb->head = data;
					skb->data = data;
					skb_reset_tail_pointer(skb);
						skb->tail = skb->data;
					skb->end = skb->tail + size;
					/* make sure we initialize shinfo sequentially */
					shinfo = skb_shinfo(skb);
					atomic_set(&shinfo->dataref, 1);
					
			// skb->head = data
			// skb->data = data + NET_SKB_PAD
			// skb->tail = data + NET_SKB_PAD
			// skb->end = data + size;
			skb_reserve(skb, NET_SKB_PAD);

	// 增加 headroom 2字节，因为 网卡知道接受的数据是以太帧，
	// 所以接下来头部为 14字节，预先后移2字节，保证对齐。
	// skb->head = data
	// skb->data = data + NET_SKB_PAD + 2
	// skb->tail = data + NET_SKB_PAD + 2
	// skb->end = data + size;
	skb_reserve(skb, 2);	/* longword align L3 header */

```

```c
// 从数据缓冲区分配 len 字节空间返回
unsigned char *skb_put(struct sk_buff *skb, unsigned int len)
	unsigned char *tmp = skb_tail_pointer(skb);
		return skb->tail;
	skb->tail += len;
	skb->len  += len;
	return tmp;
```

```c
// 减少headroom ，增加payload 空间
unsigned char *skb_push(struct sk_buff *skb, unsigned int len)
	skb->data -= len;
	skb->len  += len;
	return skb->data;
```

```c
// 增加headroom
unsigned char *skb_pull(struct sk_buff *skb, unsigned int len)
	return unlikely(len > skb->len) ? NULL : __skb_pull(skb, len);
		skb->len -= len;
		return skb->data += len;
```

```c
// 当 payload （skb->data 到 skb->tail）的长度大于len
// skb->tail向上移动，当payload减少到len字节大小
void skb_trim(struct sk_buff *skb, unsigned int len)
	if (skb->len > len)
		__skb_trim(skb, len);
			skb->len = len;
			skb->tail = skb->data + len;
```

## 复制和克隆
当多进程操作 socket buffer时，涉及对 sk_buff 或 数据缓冲区 的修改，
这时需要对 socket buffer 进行复制或克隆

### 克隆
当修改只涉及 sk_buff 时，为了提高效率，只复制sk_buff,
并将dataref计数加一。
保证每个进程有独立的sk_buff，sk_buff 指向相同的数据缓冲区。

```txt
+----------+     +----------+     +------------+
| process1 | --> | sk_buff1 | --> | data cache |
+----------+     +----------+     +------------+
                                    ^
                                    |
                                    |
+----------+     +----------+       |
| process2 | --> | sk_buff2 | ------+
+----------+     +----------+
```

```c
struct sk_buff *skb_clone(struct sk_buff *skb, gfp_t gfp_mask)
```
skb_clone 产生一个skb的克隆，克隆的skb有如下特点：
* 不放入任何skb管理队列
* 不属于任何套接字 
* 两个skb->cloned都设置为1，克隆出来的skb->users为1.
* 当一个skb被克隆后，他的数据包就不应该被修改了，这时访问数据包不需要加锁。

![](./pic/8.jpg)

### 复制
当即要修改skb，又要修改数据包，就需要对socket buffer进行复制。
这时有两个选择：
* 如果既要修改主数据包，又要修改分片，就使用  skb_copy
* 如果只修改主数据包，就使用 pskb_copy
![](./pic/9.jpg)
![](./pic/10.jpg)

## 队列操作函数
socket buffer被组织在不同队列，内核提供了一系列函数在管理，
![](./pic/11.jpg)
需要注意，这些函数的执行必须是原子操作，
在操作队列前，必须首先获得sk_buff_head结构中的spinlock，
否则操作可能被异步事件(如中断)打断。

## 引用计数操作
```c
// 增加 skb 引用计数
static inline struct sk_buff *skb_get(struct sk_buff *skb)
	atomic_inc(&skb->users);

// 分片数据引用计数加一
static void skb_clone_fraglist(struct sk_buff *skb)
	struct sk_buff *list;
	for (list = skb_shinfo(skb)->frag_list; list; list = list->next)
		skb_get(list);
```

## 协议头指针操作
Linux使用指针或偏移指向协议头的起始地址，提供系列操作
![](./pic/11.jpg)

# 4. 数据分片和分段
socket buffer的数据包缓冲区尾部为skb_shared_info，在分配数据包缓冲区空间时，也会分配 skb_shared_info 的空间，并初始化该结构，
skb_shared_info 用于支持IP数据分片，和TCP数据分段。

当数据包超过MTU，需要进行IP数据分片，这些更小的数据片有各自的 skb，而这些 skb 链入主 skb 的 skb_shared_info 链表。

```c
struct skb_shared_info {
	// 对主skb数据包缓冲区的引用计数
	atomic_t	dataref;

	// 数据包被分片的计数，描述数据包被分成多少数据片
	unsigned short	nr_frags;

	// 说明网络硬件是否有硬件实现分片的能力
	unsigned short  gso_type;
	// 给出数据包被分段的数量
	unsigned short	gso_size;
	unsigned short	gso_segs;

	__be32          ip6_frag_id;
	struct sk_buff	*frag_list;
	skb_frag_t	frags[MAX_SKB_FRAGS];
};
```
以前数据分片是CPU完成的，现在是网卡完成，
这种技术称为TSO，或 GSO。


skb_shared_info 紧接在 socket buffer 数据包缓冲区之后，通过 skb->end 指针寻址。
使用 skb_shared_info的目的：
* 支持IP分片
* 支持TCP分段
* 跟踪数据包的引用计数
当用于IP分片时， frag_list 指向包含分片socket buffer的链表。
当用于TCP分段时，frags包含相关页面，其中包含了分段数据。

frags数组的每个元素都是一个管理存放TCP数据段的skb_frag_t 的结构。
```c
/* To allow 64K frame to be packed as single skb without frag_list */
#define MAX_SKB_FRAGS (65536/PAGE_SIZE + 2)

typedef struct skb_frag_struct skb_frag_t;

struct skb_frag_struct {
	struct page *page;
	__u32 page_offset;
	__u32 size;
};
```

操作skb_shared_info的函数
skb_is_nonlinear : 查看socket buffer的数据包是否被分片
skb_linearize : 将分片的小数据包组装成一个完整的大数据包
skb_shinfo : 在skb中并没有指向skb_shared_info的指针，需要用 skb_shinfo 返回该指针


