# 1. 简介
## 什么是skbuff
如果说TCP/IP协议栈是写信，则skbuff是信的纸张，
TCP/IP协议栈是写信方法，不同于一般方法，TCP/IP协议栈将写信划分成了多个阶段，而skbuff贯穿其中。

## 如何理解和应用skbuff
如果TCP/IP各层都对skbuff的数据域直接修改，会导致程序混乱，因为一旦skbuff数据结构改变，则整个协议栈的代码都需要修改，所以内核实现了一系列方法操作skbuff数据域的方法，供TCP/IP各层使用，这些方法构成了skbuff对外交流的统一接口。
理解这些方法和实现流程是理解和应用linux内核网络协议栈的重要基础

## skbuff 的构成
Linux内核网络子系统设计的目的是使网络子系统的实现独立于特定网络协议，各种网络协议不需要做大改动就能直接加入到TCP/IP协议栈的任何层次中。

skbuff 定义在 skbuff.h 中

```txt
     #==================#
     H     sk_buff      H
     #==================#
     '       next       '
     + - - - - - - - - -+
     '       prev       '
     + - - - - - - - - -+
     '        sk        '
     + - - - - - - - - -+
     '      tstamp      '
     + - - - - - - - - -+
     '       dev        '
     + - - - - - - - - -+
     '       ...        '
     + - - - - - - - - -+
     '                  '
     ' transport_header ' -------------------------+
     + - - - - - - - - -+                          |
     '                  '                          |
     '  network_header  ' -------------------------+----+
     + - - - - - - - - -+                          |    |
     '                  '                          |    |
     '    mac_header    ' --------------------+    |    |
     + - - - - - - - - -+                     |    |    |
     '                  '     #============#  |    |    |
     '       head       ' -+  H   packet   H  |    |    |
     + - - - - - - - - -+  +> #============#  |    |    |
     '                  '     '            '  |    |    |
     '       data       ' -+  '     ..     '  |    |    |
     + - - - - - - - - -+  +> + - - - - - -+ <+    |    |
     '                  '     '            '       |    |
  +- '       tail       '     ' MAC header '       |    |
  |  + - - - - - - - - -+     + - - - - - -+ <-----+----+
  |  '                  '     '            '       |
  |  '       end        '     ' IP header  '       |
  |  + - - - - - - - - -+     + - - - - - -+ <-----+
  |    |                      '            '
  |    |                      ' UDP header '
  |    |                      + - - - - - -+
  |    |                      '            '
  |    |                      '  UDP data  '
  +----+--------------------> + - - - - - -+
       |                      '            '
       |                      '     ..     '
       +--------------------> + - - - - - -+
                              ' dataref:1  '
                              + - - - - - -+
```
如上所示，一个完整的socket buffer 由两部分组成：
* 数据包：存放实际要在网络中传送的数据缓存区
* 管理数据结构（struct sk_buff）：当内核处理数据包时，内核需要其他数据来管理和操作数据包，如数据接受、发送事件，状态等。

## socketbuffer 穿越TCP/IP协议栈
下图显示 socket buffer 穿越TCP/IP协议栈的过程
![](./pic/1.jpg)

可见使用 socket buffer 传输数据只需要复制两次，一次是从应用程序的用户空间复制到内核空间，一次是从内核空间复制到网络适配器的硬件缓存。

# 2. socket buffer 结构详解
## sk_buff的设计和含义
socket buffer穿越TCP/IP协议栈时，数据内容通常不会被修改，只有数据包缓冲区中的协议头会发生变化，大量操作是在sk_buff数据结构中进行。

sk_buff的数据域经过多次添加和重新组织，
设计目标要尽可能的清晰，还要考虑传送的高效性，如cache line大小对齐。
另外随着网络功能的增强，sk_buff中也增加了新的数据域来标识对这些新功能的支持，如包过滤等。

sk_buff域从功能上大致可以分为：
* 结构管理
* 常规数据
* 网络功能配置相关

### 结构管理域
```c
struct sk_buff {

	struct sk_buff		*next;
	struct sk_buff		*prev;

	...

	struct sock		*sk;

	....

	void		(*destructor)(struct sk_buff *skb);

	...

	unsigned int		len,
				data_len;
	__u16			mac_len,
				hdr_len;
	...
	refcount_t		users;
	unsigned int		truesize;

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
指向拥有该socket buffer的套接字，当向外发送，或从网络来的数据的目标地址是本机应用程序时，会设置此项。
当转发数据包时，此项为NULL。
所谓套接字就是地址加端口，用于唯一识别网络应用程序。
sk_buff->sk 表示最终应该传输给哪个应用程序。

3. len
sk_buff->len 指 socket buffer 中数据包的总长度，包括：主缓冲区的数据长度（由sk_buff->head指向）、各个分片数据的长度（当数据包长度大于网络适配器一次能传输的最大传输单元MTU时，数据包会被分成更小的断）

4. data_len
分片的数据块长度

5. mac_len
链路层协议头的长度

6. hdr_len
hdr_len 用于克隆数据包，表明克隆数据包的头长度。
当克隆数据包时，只做纯数据的克隆（即不克隆数据包的协议头信息），这时需要从 hdr_len获得头长度。

7. users
引用计数，所有正在使用该sk_buff缓冲区的进程数。

8. truesize
整个socket buffer的大小，即sk_buff和数据包的长度和。
```c
truesize = data_len + sizeof(struct sk_buff)
alloc_skb(truesize);
```

9. tail end head data
![](./pic/5.jpg)
socket buffer数据包缓冲区包括：TCP/IP协议头和尾部检验信息， 负载数据。
head end 指向整个数据包缓冲区的首尾。
data tail 指向负载数据的首尾
head data 之间用于添加协议头
tail end 之间用于添加新数据，如检验和

10. destructor
指向Socket buffer的析构函数，当sk_buff不属于任何套接字时，析构函数通常不需要初始化。

### 常规数据域
```c
struct sk_buff {
	...
	ktime_t		tstamp;
	..
	struct net_device	*dev;
	int			skb_iif;
	...
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
数据包到达内核的时间

2. dev skb_iif
dev 指向网络设备，说明数据包是由哪个设备接受或发送。
skb_iif 网络设备的索引号，Linux中某种类型的网络设备的命名方式是设备名加顺序索引号，如 Ethernet 设备： eth0 eth1

3. cb
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

4. csum
csum :  存放数据包的校验和。


5. priority
用于实现QoS功能特性。

6. protocol
接受数据包的网络层协议。标志了网络数据包应该交给TCP/IP协议栈网络层的哪个协议处理函数

相关 protocol定义在
include/linux/if_ether.h

7. queue_mapping
具备多个缓冲队列的网络设备的队列映射关系。
早期网络设备只有一个数据发送缓冲区，现在很多网络设备有多个发送缓冲区来存放待发送的网络数据包。
queue_mapping 描述了本网络数据所在的队列和设备硬件发送队列的映射关系

8. unsigned long \_skb_refdst 
由路由子系统使用，当接受的数据包目的地址不为本地，需要转发时，
则这个域包含信息指明应该如何将数据包转发，
这个域可能是 struct dst_entry \*, 指向一条路由表记录，
可能是 rtable, 指明在系统哪个路由表中查找数据包发送地址。
```c
struct dst_entry *skb_dst(const struct sk_buff *skb)
	return (struct dst_entry *)(skb->_skb_refdst & SKB_DST_PTRMASK);

struct rtable *skb_rtable(const struct sk_buff *skb)
	return (struct rtable *)skb_dst(skb);
```

9. mark
数据包为常规数据包的标志

10. vlan_tci
VLAN Tag 控制信息

11. transport_header network_header mac_header
指向协议栈中各层协议头在网络数据包的位置
![](./pic/6.jpg)

### 网络功能配置域
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
当内核由多个数据包向外发送时，内核必须决定谁先送，谁后送，谁丢弃，
内核实现了多种算法来选择数据包，如果没有选择此功能，内核发送数据包时就使用FIFO策略。
```c
#ifdef CONFIG_NET_SCHED
	__u16			tc_index;	/* traffic control index */
#endif
```
## 操作sk_buff的函数
封装sk_buff和函数让操作sk_buff和协议栈独立，之后要添加新的操作sk_buff功能，只需要添加对应函数，不会影响原有代码。
按照功能，函数可以分为：
* 创建，释放，复制 socket buffer
* 操作 sk_buff的属性
* 管理 socket buffer 队列
函数集中实现在
skbuff.c 和 skbuff.h 中


### 创建和释放 socket buffer
创建socket buffer 比常规内存分配复制，因为网络环境下，每秒有数千个数据包被接受发送，需要频繁的创建释放socket buffer，如果socket buffer的创建释放过程不合理，则会大大降低整个系统的性能。尤其内存分配是系统中最耗时的操作。

为此内核在系统初始化时已创建了两个 sk_buff 内存池。
```c
struct kmem_cache *skbuff_head_cache __ro_after_init;
static struct kmem_cache *skbuff_fclone_cache __ro_after_init;
```
这两个内存池由 skb_init 创建。每当需要分配 sk_buff 时，根据所需的sk_buff 是克隆还是非克隆的，分别从对应cache中获得内存对象，释放 sk_buff时，就将对象放回以上cache.

#### 创建 socket buffer
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

#### 释放 socket buffer
```c

kfree_skb

kfree_release_all

kfree_release_data

kfree_skbmem

dst_release
```
