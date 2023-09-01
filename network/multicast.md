# IGMP协议
IGMP（Internet Group Management Protocol）即互联网组管理协议，主要用于实现主机向任意网络设备报告其多播组成员资格的需求。主要有三种类型的IGMP报文：查询（Query）
  报告（Report）和离开（Leave）。

1. 查询报文（Query）：IGMP查询报文是由多播路由器发送的，用以发现网络中哪些主机属于哪些多播组。查询报文有两种形式：一种是通用查询（General Query），用于查询网络
  所有的多播组；另一种是特定查询（Group-Specific Query），用于查询特定的多播组。查询报文会被发送到所有系统的预定多播地址（224.0.0.1）。

2. 报告报文（Report）：当主机加入一个新的多播组时，或者收到路由器的查询报文后，主机会发送IGMP报告报文。报告报文是单播发送给查询报文的发送者的。报告报文的目的是
  诉路由器，有主机想要接收特定多播组的数据。 特定目的地址 224.0.0.22，报文的Group record 包含要加入的组播地址

3. 离开报文（Leave）：当主机不再想接收某个多播组的数据时，它会发送IGMP离开报文。离开报文是单播发送给最近的路由器的。离开报文的目的是告诉路由器，没有主机想要接
  特定多播组的数据了。目的地址为已加入并要退出的组播地址

在IGMP协议中，有三种重要的角色：组播组的源（Source）、组播组的接收者（Receiver）和路由器（Router）。当一个主机想要加入一个组播组时，它会发送一个IGMP报文给所连接的路由器，表明它想要加入该组播组。路由器收到这个报文后，会更新自己的组播组成员表，并将组播数据转发到相应的接口。


## 完整的主机发送IGMP report 到主机发送 IGMP leave 的过程
以下是主机发送IGMP报告（IGMP Report）到主机发送IGMP离开（IGMP Leave）的完整过程：

1. 主机加入组播组：
   - 主机决定要加入一个特定的组播组。
   - 主机发送IGMP报告（IGMP Report）给所连接的路由器，表明它想要加入该组播组。
   - IGMP报告中包含组播组的组播地址和相关的信息。

2. 路由器处理IGMP报告：
   - 路由器接收到主机发送的IGMP报告。
   - 路由器更新自己的组播组成员表，记录该主机加入了该组播组。
   - 路由器根据需要更新组播转发表，以便将组播数据转发到相应的接口。

3. 主机接收组播数据：
   - 主机成功加入组播组后，它可以接收到发送到该组播组的组播数据。

4. 主机发送IGMP离开请求：
   - 主机决定离开组播组，不再接收组播数据。
   - 主机发送IGMP离开（IGMP Leave）报文给所连接的路由器，表明它要离开该组播组。
   - IGMP离开报文中包含组播组的组播地址和相关的信息。

5. 路由器处理IGMP离开请求：
   - 路由器接收到主机发送的IGMP离开报文。
   - 路由器更新自己的组播组成员表，将该主机从该组播组的成员列表中移除。
   - 路由器根据需要更新组播转发表，停止将组播数据转发到该主机的接口（如果没有其他成员在该接口上）。

6. 主机不再接收组播数据：
   - 主机成功发送IGMP离开报文后，它将不再接收发送到该组播组的组播数据。

需要注意的是，IGMP离开报文不是必需的，主机可以直接从组播组中离开而不发送离开报文。路由器会通过超时机制检测到主机不再发送IGMP报告，并将其从组播组成员表中移除。发送IGMP离开报文只是一种显式的通知方式，可以更快地通知路由器主机的离开意图。

## 当发送IGMP report  后需要接受什么报文，然后还需要继续发送什么报文？
当发送IGMP报告（IGMP Report）后，接收方需要发送IGMP报告确认（IGMP Report Acknowledgment）报文作为响应。这个报文是用来确认接收到IGMP报告的，并且指示发送方的IGMP报告已被成功接收。

在接收到IGMP报告确认后，发送方不需要继续发送任何报文。IGMP报告确认报文只是一个简单的确认，没有需要进一步的响应或请求。发送方可以根据需要继续发送其他IGMP报告或执行其他操作，但不是必需的。

# IP_ADD_MEMBERSHIP
应用层示例
```c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <net/if.h>

#define GROUP_IP "239.0.0.2"
#define CLNT_PORT 9000

int main(int argc, char **argv)
{
	struct sockaddr_in localaddr;
	int sockfd, n;
	char buf[BUFSIZ];
	struct ip_mreqn group;

	if (argc != 2) {
		printf("usage : %s dev\n", argv[0]);
		return -1;
	}

	sockfd = socket(AF_INET, SOCK_DGRAM, 0);
	localaddr.sin_family = AF_INET;
	localaddr.sin_addr.s_addr = htonl(INADDR_ANY);
	localaddr.sin_port = htons(CLNT_PORT);
	bind(sockfd, (struct sockaddr*)&localaddr, sizeof(localaddr));
	inet_pton(AF_INET, GROUP_IP, &group.imr_multiaddr);
	inet_pton(AF_INET, "0.0.0.0", &group.imr_address);
	group.imr_ifindex = if_nametoindex(argv[1]);

	setsockopt(sockfd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &group, sizeof(group));
	while(1){
		n = recvfrom(sockfd, buf, sizeof(buf), 0, NULL, 0);
		if(n > 0){
			write(STDOUT_FILENO, buf, n);
		}
	}
	close(sockfd);

	return 0;
}
```

## 内核分析
```c

static int do_ip_setsockopt(struct sock *sk, int level,
			    int optname, char __user *optval, unsigned int optlen)
	switch (optname) {
	...
	case IP_ADD_MEMBERSHIP:
	case IP_DROP_MEMBERSHIP:
	{
		struct ip_mreqn mreq;

		err = -EPROTO;
		if (inet_sk(sk)->is_icsk)
			break;

		// 确保输入参数正确，并从用户空间拷贝输入参数
		if (optlen < sizeof(struct ip_mreq))
			goto e_inval;
		err = -EFAULT;
		if (optlen >= sizeof(struct ip_mreqn)) {
			if (copy_from_user(&mreq, optval, sizeof(mreq)))
				break;
		} else {
			memset(&mreq, 0, sizeof(mreq));
			if (copy_from_user(&mreq, optval, sizeof(struct ip_mreq)))
				break;
		}

		if (optname == IP_ADD_MEMBERSHIP)
			err = ip_mc_join_group(sk, &mreq);
		else
			err = ip_mc_leave_group(sk, &mreq);
		break;
	...


struct ip_mreqn {
	struct in_addr	imr_multiaddr;		/* IP multicast address of group */
	struct in_addr	imr_address;		/* local IP address of interface */
	int		imr_ifindex;		/* Interface index */
};


int ip_mc_join_group(struct sock *sk , struct ip_mreqn *imr)
	struct inet_sock *inet = inet_sk(sk);

	// 确保输入参数 imr->imr_multiaddr 是组播地址
	__be32 addr = imr->imr_multiaddr.s_addr;
	
	if (!ipv4_is_multicast(addr))
		return -EINVAL;

	// 根据输入参数找到 组播包的输入设备
	in_dev = ip_mc_find_dev(net, imr);
		// 如果指定设备索引号，则根据设备索引号找到输入设备
		if (imr->imr_ifindex)
			idev = inetdev_by_index(net, imr->imr_ifindex);
			return idev;

		// 如果没有指定设备索引号，则根据本地IP地址找到相关的设备，做输入设备
		if (imr->imr_address.s_addr)
			dev = __ip_dev_find(net, imr->imr_address.s_addr, false);
			// 如果指定了本地IP地址，但没有相关的输入设备，则报错
			if (!dev)
				return NULL;
				
		// 如果没有指定设备索引号，没有指定本地IP
		// 则根据组播地址做目的地址，查询路由，已查询到的输出设备做输入设备
		if (!dev) {
			struct rtable *rt = ip_route_output(net,
								imr->imr_multiaddr.s_addr,
								0, 0, 0);
			if (!IS_ERR(rt)) {
				dev = rt->dst.dev;
				ip_rt_put(rt);
			}
		}
		// 如果找到输入设备，则记录到 imr->imr_ifindex 的设备索引号
		if (dev) {
			imr->imr_ifindex = dev->ifindex;
			idev = __in_dev_get_rtnl(dev);
		}
		return idev;


	// 查询sock 的 mc_list 已经加入的组播地址链表
	// 比较链表和新加入的组播地址，如果已经加入就 goto done
	ifindex = imr->imr_ifindex;
	for_each_pmc_rtnl(inet, i) {
		if (i->multi.imr_multiaddr.s_addr == addr &&
		    i->multi.imr_ifindex == ifindex)
			goto done;
		count++;
	}

	// 如果满了，则退出
	if (count >= sysctl_igmp_max_memberships)
		goto done;

	// 分配组播节点, 记录新的组播信息，sock 的 mc_list
	struct ip_mc_socklist *iml = NULL, *i;
	iml = sock_kmalloc(sk, sizeof(*iml), GFP_KERNEL);
	memcpy(&iml->multi, imr, sizeof(*imr));
	iml->next_rcu = inet->mc_list;
	iml->sflist = NULL;
	iml->sfmode = MCAST_EXCLUDE;

	// 将新组播地址加入设备
	ip_mc_inc_group(in_dev, addr);
		
		// 如果已经加入，就增加引用计数，并确保组播地址加入了设备的过滤列表
		for_each_pmc_rtnl(in_dev, im) {
			if (im->multiaddr == addr) {
				im->users++;
				ip_mc_add_src(in_dev, &addr, MCAST_EXCLUDE, 0, NULL, 0);
				goto out;
			}
		}

		// 如果设备未加入此组播地址，则加入

		// 创建新组播节点, im ，并用 addr 设置他
		im = kzalloc(sizeof(*im), GFP_KERNEL);
		if (!im)
			goto out;

		im->users = 1;
		im->interface = in_dev;
		in_dev_hold(in_dev);
		im->multiaddr = addr;
		/* initial mode is (EX, empty) */
		im->sfmode = MCAST_EXCLUDE;
		im->sfcount[MCAST_EXCLUDE] = 1;
		atomic_set(&im->refcnt, 1);
		spin_lock_init(&im->lock);
	#ifdef CONFIG_IP_MULTICAST
		setup_timer(&im->timer, &igmp_timer_expire, (unsigned long)im); // 注意这里 igmp_timer_expire
		im->unsolicit_count = IGMP_Unsolicited_Report_Count;
	#endif

		// 将新节点 im 加入  in_dev->mc_list
		im->next_rcu = in_dev->mc_list;
		in_dev->mc_count++;
		rcu_assign_pointer(in_dev->mc_list, im);

	#ifdef CONFIG_IP_MULTICAST
		igmpv3_del_delrec(in_dev, im->multiaddr);
	#endif
		// 应该是发 IGMP report
		igmp_group_added(im);
		if (!in_dev->dead)
			ip_rt_multicast_event(in_dev);
	out:
		return;
```

## 发送IGMP报文 , 上报身份
IGMP_Initial_Report_Delay不是来自IGMP规范！
IGMP规范要求在加入组后立即报告成员身份，但我们会延迟第一次报告一小段时间。这样做似乎更自然，并且只要延迟足够小，就不会违反规范。
```c
ip_mc_join_group // 做一些检查，和确认相关设备
	ip_mc_inc_group // 加入组
		// 延迟一段时间，上报身份
		setup_timer(&im->timer, &igmp_timer_expire, (unsigned long)im);

// 进行身份上报
static void igmp_timer_expire(unsigned long data)
	struct ip_mc_list *im=(struct ip_mc_list *)data;
	struct in_device *in_dev = im->interface;

	im->tm_running = 0;

	// 如果还没有接受到IGMP ack，过段时间继续上报report
	if (im->unsolicit_count) {
		im->unsolicit_count--;
		igmp_start_timer(im, IGMP_Unsolicited_Report_Interval);
	}
	im->reporter = 1;
	spin_unlock(&im->lock);

	// 发送 IGMP report
	if (IGMP_V1_SEEN(in_dev))
		igmp_send_report(in_dev, im, IGMP_HOST_MEMBERSHIP_REPORT);
	else if (IGMP_V2_SEEN(in_dev))
		igmp_send_report(in_dev, im, IGMPV2_HOST_MEMBERSHIP_REPORT);
	else
		igmp_send_report(in_dev, im, IGMPV3_HOST_MEMBERSHIP_REPORT);

	ip_ma_put(im);
}

// 构造 IGMP skb, 并发送给 output
// IGMP 协议是被包裹在IP协议里
static int igmp_send_report(struct in_device *in_dev, struct ip_mc_list *pmc,

	if (type == IGMPV3_HOST_MEMBERSHIP_REPORT)
		return igmpv3_send_report(in_dev, pmc);
	else if (type == IGMP_HOST_LEAVE_MESSAGE)
		dst = IGMP_ALL_ROUTER;
	else
		dst = group;
	// 以组播地址为目的地址查询路由
	rt = ip_route_output_ports(net, &fl4, NULL, dst, 0,
				   0, 0,
				   IPPROTO_IGMP, 0, dev->ifindex);

	// 分配skb, 并构造IGMP 
	skb = alloc_skb(IGMP_SIZE + hlen + tlen, GFP_ATOMIC);

	skb_dst_set(skb, &rt->dst);

	skb_reserve(skb, hlen);

	skb_reset_network_header(skb); // 没有L4层
	//  从 tail 填充，先填 IP 协议，因为IP协议包裹IGMP
	iph = ip_hdr(skb);
	skb_put(skb, sizeof(struct iphdr) + 4);

	iph->version  = 4;
	iph->ihl      = (sizeof(struct iphdr)+4)>>2;
	iph->tos      = 0xc0;
	iph->frag_off = htons(IP_DF);
	iph->ttl      = 1;
	iph->daddr    = dst;
	iph->saddr    = fl4.saddr;
	iph->protocol = IPPROTO_IGMP;
	ip_select_ident(skb, NULL);
	((u8*)&iph[1])[0] = IPOPT_RA;
	((u8*)&iph[1])[1] = 4;
	((u8*)&iph[1])[2] = 0;
	((u8*)&iph[1])[3] = 0;

	// 从tail填充，填IGMP协议
	ih = (struct igmphdr *)skb_put(skb, sizeof(struct igmphdr));
	ih->type = type;
	ih->code = 0;
	ih->csum = 0;
	ih->group = group;
	ih->csum = ip_compute_csum((void *)ih, sizeof(struct igmphdr));

	return ip_local_out(skb);
		err = __ip_local_out(skb);
			return nf_hook(NFPROTO_IPV4, NF_INET_LOCAL_OUT, skb, NULL,
					   skb_dst(skb)->dev, dst_output);
				// 查路由 组播走 ip_mc_output ,单播走 ip_output
				return skb_dst(skb)->output(skb);
```

# 路由器如何转发IGMP
关键是组播路由，组播路由不能使用 ip-route 设置，因为他是动态变化的，可以使用 igmpproxy 程序
其配置文件如下
```
# /etc/igmpproxy.conf
quickleave

# 设置 ppp0 网口，
# upstream : 此网口做上行，即组播包从这里进入
# ratelimit 0 不限制速率
# threshold 1 设置ttl 至少为1
# altnet 允许的IP为所有IP
phyint ppp0 upstream ratelimit 0 threshold 1
  altnet 0.0.0.0/0

phyint eth0 upstream ratelimit 0 threshold 1
  altnet 0.0.0.0/0

# br0为下行口，即组播包转发到这里
phyint br0 downstream ratelimit 0 threshold 1
  altnet 0.0.0.0/0

```
igmpproxy会监听 ppp0, eth0 ,br0，当收到br0的IGMPreport 会设置组播路由

