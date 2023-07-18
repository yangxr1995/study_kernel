# TCP简介
TCP的特性是，可靠，面向连接，字节流。

TCP使用肯定回答和重传机制保证可靠。一旦发送数据，发送方要等待对方回答，超时后重传，多次重传后放弃，
另一方面每个TCP数据段都有校验检查数据是否受损，如果数据完整，接受方发送ACK，如果数据损坏，接受方丢弃数据段，一段时间后发送方重传未收到ACK的数据段

TCP协议格式
![](./pic/45.jpg)

TCP层实现的功能
数据收发：IP层，TCP层，套接字层之间数据的传递
连接管理：在数据开始传输前，建立连接，完成传输后，断开连接
流量控制：保证数据按正确的顺序被接受 
回答超时管理

# 关键数据结构

TCP协议头
```c
struct tcphdr {
	__be16	source; // 源端口
	__be16	dest; // 目的端口
	__be32	seq; // 数据段中第一个数据字节的序列号
	__be32	ack_seq; // 如果设置回答控制位，该值表示发送方的下一个序列号
#if defined(__LITTLE_ENDIAN_BITFIELD)
	__u16	res1:4,
		doff:4,
		fin:1,
		syn:1,
		rst:1,
		psh:1,
		ack:1,
		urg:1,
		ece:1,
		cwr:1;
#elif defined(__BIG_ENDIAN_BITFIELD)
	__u16	doff:4,  // 协议长度
		res1:4, // 保留字段
		cwr:1, // 用于网络拥塞和窗口控制, 在原RFC没有定义
		ece:1, // 用于网络拥塞和窗口控制, 在原RFC没有定义
		urg:1, // 接下来传输重要数据
		ack:1, // 本数据段是ACK
		psh:1, // TCP层应立即将数据传送给上次应用
		rst:1, // 本数据段是RST，要求复位连接
		syn:1, // 本数据段是SYN
		fin:1; // 本数据段是FIN
#else
#error	"Adjust your <asm/byteorder.h> defines"
#endif	
	__be16	window; // 当我做接收方时还剩余多少缓存空间用于接受数据
	__sum16	check; // 包含TCP协议头和数据所作的检验和
	__be16	urg_ptr; // 指向重要数据的最后一个字节的地址
};

```

TCP的控制缓存
socket buffer用于存放负载数据，控制缓存存放用户控制管理数据包的信息
```c
struct tcp_skb_cb {
	// 存放数据包使用的IP协议
	union {
		struct inet_skb_parm	h4;
#if defined(CONFIG_IPV6) || defined (CONFIG_IPV6_MODULE)
		struct inet6_skb_parm	h6;
#endif
	} header;	/* For incoming frames		*/

	// 数据段的起始序列号
	__u32		seq;		/* Starting sequence number	*/
	// 最后一个输出数据段列号
	__u32		end_seq;	/* SEQ + FIN + SYN + datalen	*/
	// 用于计算RTT
	__u32		when;		/* used to compute rtt's	*/
	// 与tcphdr->flags 相同
	__u8		flags;		/* TCP header flags.		*/

	/* NOTE: These must match up to the flags byte in a
	 *       real TCP header.
	 */
#define TCPCB_FLAG_FIN		0x01
#define TCPCB_FLAG_SYN		0x02
#define TCPCB_FLAG_RST		0x04
#define TCPCB_FLAG_PSH		0x08
#define TCPCB_FLAG_ACK		0x10
#define TCPCB_FLAG_URG		0x20
#define TCPCB_FLAG_ECE		0x40
#define TCPCB_FLAG_CWR		0x80

	// 保存了选择回答SACK,转发回答FACK的状态标志
	__u8		sacked;		/* State flags for SACK/FACK.	*/
#define TCPCB_SACKED_ACKED	0x01	/* SKB ACK'd by a SACK block	*/
#define TCPCB_SACKED_RETRANS	0x02	/* SKB retransmitted		*/
#define TCPCB_LOST		0x04	/* SKB is lost			*/
#define TCPCB_TAGBITS		0x07	/* All tag bits			*/

#define TCPCB_EVER_RETRANS	0x80	/* Ever retransmitted frame	*/
#define TCPCB_RETRANS		(TCPCB_SACKED_RETRANS|TCPCB_EVER_RETRANS)

	// 与TCP协议头中的ack数据域相同
	__u32		ack_seq;	/* Sequence number ACK'd	*/
};
```

TCP套接字
```c
struct tcp_sock {
	...
};
```

TCP协议选项
1. TCP_CORK/ nonagle
不立即发送数据段，直到数据段大小到达最大长度MSS，MSS应该小于MTU，这个选项和TCP_NODELAY是互斥的
该选项存放在 tcp_sock->nonagle

2. TCP_DEFER_ACCEPT
当接收到第一个数据之后，才会创建连接，这是为防止空连接的攻击.
服务端完成握手后，不会建立将此套接字当成已连接套接字 ，只有有真实数据到达后才会建立连接。
如果 val 秒后仍然没有收到数据，则丢弃此连接请求。
这个选项就是用于设置此val值
该选项存放在 tcp_sock->defer_accept

3. TCP_INFO
应用程序使用此选项可以获得大部分套接字配置信息。返回到 struct tcp_info中

4. TCP_KEEPCNT
定义了keepalive的阈值，超过后断开连接
该选项存放在 tcp_sock->keepalive_probes
如果要让该选项生效，还必须设置套接字层 SO_KEEPALIVE

5. TCP_KEEPIDLE
定义心跳包的间隔时间戳,单位秒

