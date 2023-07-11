# 介绍
网络设备驱动程序是网络设备和内核之间桥梁，完成网络设备缓冲区和内核空间之间的数据传递。
网络设备驱动程序至少需要完成的功能：
* 接受和发送数据包，注意这些操作都是异步的
* 支持管理任务，如修改网络地址，发送参数等

# 网络驱动程序的构成
## 初始化，探测
如果驱动程序作为模块，在加载模块时init函数构造网络设备的实例 net_device，并注册到内核。

如果驱动程序链接到内核，内核会根据启动参数探测设备，如果匹配，则调用驱动程序的 probe函数
实例化 net_device，并注册到内核。

## 设备活动
net_device创建并注册后，由用户激活就可以进行数据的收发，这些收发都是异步的，所以通常用
中断实现。描述设备活动的函数：
* 激活/停止设备(xx_open/xx_close)
* 收发数据(xx_tx/xx_rx)
* 中断处理程序(xx_interrupt)

## 管理设备
网络设备收发数据时可能出错，需要有出错函数，另外需要对设备工作状态进行统计，方便用户查看，
最后还需要支持用户配置网络参数，如硬件地址，MTU等
* 错误处理/状态统计(xx_tx_timeout/xx_get_state)
* 支持组发送功能的函数(set_muticast_list/set_muticast_address)
* 改变设备配置(change_xxx)

## 总结
![](./pic/16.jpg)
网络驱动程序的结构如上，最重要的是数据的收发，由于是异步的，所以内核和网络设备的交互很重要：
当网络设备收到数据时如何通知内核？
当内核发送数据时如何调度网络设备活动？

# 网络设备与内核的交互
网络设备与内核的交互有两个难点：
1. 主机每秒会收到大量的数据包，如何优化中断
2. SMP环境下如何充分利用CPU

## 交互方式概述
### 轮询
CPU周期性查看网络设备寄存器，如果有数据到了，就读取数据。

### 中断
中断在低负载环境可以很好工作，但是高负载情况有如下问题：
1. 网络设备对每个数据包都产生中断，导致中断切换消耗大量时间
2. 中断处理分为两个阶段，阶段一将数据从网络设备复制到内核，阶段二内核协议栈处理数据包，阶段一
的优先级更高，它可以抢占数据处理CPU调度，当网络流量高峰时，网络数据包大量加入入栈队列，导致队
列满了，但是由于处理数据包优先级低，一直没有机会获得CPU将数据包移出队列，导致系统崩溃。
所以Linux网络体系必须对中断做进一步扩展。

### 中断加轮询
当数据包中断发生后，中断下半部禁止网络数据包的中断，以轮询方式读取数据包一段时间，或者入栈队列满了，然后再开启中断，
这种方式就是NAPI模式。


## 中断
### 硬件中断
![](./pic/17.jpg)
现代嵌入式环境有个中断控制器，他接受外部设备的各路中断请求信号，将他们放到中断请求寄存器中，
未被CPU屏蔽的中断请求会送入优先级电路，中断控制器产生一个公共中断请求信号INT，CPU收到信号后
发出响应INTA，中断控制器将最高优先级中断号传输给CPU，CPU根据中断号找到中断的入口地址。

一旦硬件设计完成，中断控制器对外的引脚数有限所以中断资源有限，且中断号对应的硬件固定，有时
多个设备可以公用一个硬件中断号。在处理中断请求时，会屏蔽其他中断信号，如果这时其他中断产生，
不能得到CPU响应，所以中断处理程序的执行时间需要尽可能短。

### 网络设备中断事件
* 收到数据包，这是最常见的中断事件
* 发送失败，比如数据包发送超时，响应错误等
* DMA发送结束

驱动发送数据：
同步方式（非DMA）：驱动程序将数据包放到网络设备缓存，就认为发送成功，释放socket buffer
异步方式（DMA）：驱动程序开启DMA发送后，并不知道什么时候发送完成，需要由硬件产生中断通知驱动程序发送操作结束。

当硬件没有足够的缓冲区时，驱动停止内核中该设备发送队列，这样内核就不能发送新的数据包了。
随着数据的不断发送，硬件缓冲区有空，硬件将产生一个中断重启发送队列。

这个过程的逻辑通常是：在数据包发送前，停止内核中对该设备的发送队列，查看设备是否有足够的空间接受新的数据包，
如果有，则重启发送队列，否则在以后以中断方式重启发送队列。
```c

static int
el3_start_xmit(struct sk_buff *skb, struct net_device *dev)
	// 禁止发送队列
	netif_stop_queue (dev);

	...

	// 如果硬件缓存有足够的空间，就重启发送队列
	// 否则些设备寄存器让硬件有足够缓存时通过中断通知内核
	if (inw(ioaddr + TX_FREE) > 1536)
		netif_start_queue(dev);
	else
		/* Interrupt us when the FIFO has room for max-sized packet. */
		outw(SetTxThreshold + 1536, ioaddr + EL3_CMD);
```

### 网络子系统的软中断
网络子系统使用软中断 NET_TX_SOFTIRQ, NET_RX_SOFTIRQ, 都是在 net_dev_init初始化。
因为同一个软中断处理程序可以在不同CPU同时执行，所以网络代码的延迟很小，两个软中断的优先级都比tasklet一般优先级 TASKLET_SOFTIRQ 高，但低于最高优先级 HI_SOFTIRQ, 保证在网络流量高峰时其他任务也能得到响应。

# 网络驱动程序的实现
## 初始化
驱动程序需要提供xx_probe函数负责探测匹配自己的设备，并构造并注册设备的net_device
```c
// 内核总线会在初始化时调用此函数
struct net_device * __init netcard_probe(int unit)
{
	// 创建 netdev
	struct net_device *dev = alloc_etherdev(sizeof(struct net_local));
	int err;

	// 根据启动参数等给netdev赋值
	sprintf(dev->name, "eth%d", unit);
	netdev_boot_setup_check(dev);

	// 探测设备
	err = do_netcard_probe(dev);
	if (err)
		goto out;
	return dev;
out:
	free_netdev(dev);
	return ERR_PTR(err);
}

// 探测函数的包装函数
static int __init do_netcard_probe(struct net_device *dev)
{
	int i;
	int base_addr = dev->base_addr;
	int irq = dev->irq;

	// 指定了IO端口，则从指定地址探测设备
	if (base_addr > 0x1ff)    /* Check a single specified location. */
		return netcard_probe1(dev, base_addr);
	else if (base_addr != 0)  /* Don't probe at all. */
		return -ENXIO;

	// 没有指定IO端口,遍历可能的IO端口,进行探测
	for (i = 0; netcard_portlist[i]; i++) {
		int ioaddr = netcard_portlist[i];
		if (netcard_probe1(dev, ioaddr) == 0)
			return 0;
		dev->irq = irq;
	}

	return -ENODEV;
}

// 真实的探测函数
static int __init netcard_probe1(struct net_device *dev, int ioaddr)
{
	struct net_local *np;
	static unsigned version_printed;
	int i;
	int err = -ENODEV;

	// 检查IO端口的空间是否已经被占用，如果没有则占用它
	if (!request_region(ioaddr, NETCARD_IO_EXTENT, cardname))
		return -EBUSY;

	// 检查网络设备是否时驱动支持的
	// 检查方法是查看MAC地址前3字节为厂商
	if (inb(ioaddr + 0) != SA_ADDR0
		||	 inb(ioaddr + 1) != SA_ADDR1
		||	 inb(ioaddr + 2) != SA_ADDR2)
		goto out;

	// 设备匹配

	// 记录IO地址
	dev->base_addr = ioaddr;

	// 记录MAC地址
	for (i = 0; i < 6; i++)
		dev->dev_addr[i] = inb(ioaddr + i);

	err = -EAGAIN;
#ifdef jumpered_dma
	//  如果支持DMA，申请DMA
	...
	request_dma(dev->dma, cardname);
	...
#endif	/* jumpered DMA */

	// 初始化设备私有数据结构
	np = netdev_priv(dev);
	spin_lock_init(&np->lock);

	// 初始化驱动函数指针
	dev->open		= net_open;
	dev->stop		= net_close;
	dev->hard_start_xmit	= net_send_packet;
	dev->get_stats		= net_get_stats;
	dev->set_multicast_list = &set_multicast_list;

        dev->tx_timeout		= &net_tx_timeout;
        dev->watchdog_timeo	= MY_TX_TIMEOUT;

	// 注册网络设备
	register_netdev(dev);

	return 0;
	...
}
```

### 网络设备的活动功能
#### open close
注册网络设备后，不能用于发送数据包，还需要分配IP，激活设备。这两个操作在用户空间使用ifconfig执行，ifconfig调用ioctl完成任务：
* ioctl SIOCSIFADDR, 设置IP地址
* ioctl SIOCSIFFLAGS, 设置 dev->flags 的 IFFUP，激活设备
驱动程序没有ioctl，内核会在执行 ioctl SIOCSIFFLAGS时调用驱动的open，或close

1. open
open 完成分配资源，写设备寄存器以激活设备。
```c
static int
net_open(struct net_device *dev)
{
	struct net_local *np = netdev_priv(dev);
	int ioaddr = dev->base_addr;

	// 申请中断DMA资源
	if (request_irq(dev->irq, &net_interrupt, 0, cardname, dev)) {
		return -EAGAIN;
	}
	if (request_dma(dev->dma, cardname)) {
		free_irq(dev->irq, dev);
		return -EAGAIN;
	}

	// 复位硬件，设置网络设备IO端口地址
	chipset_init(dev, 1);
	outb(0x00, ioaddr);
	np->open_time = jiffies;

	// 启动网络设备发送队列
	netif_start_queue(dev);

	return 0;
}
```

2. stop
```c
static int
net_close(struct net_device *dev)
{
	struct net_local *lp = netdev_priv(dev);
	int ioaddr = dev->base_addr;

	lp->open_time = 0;

	// 停止设备发送队列
	netif_stop_queue(dev);

	// 将发送队列剩余数据包全部发出，释放DMA，中断
	disable_dma(dev->dma);
	outw(0x00, ioaddr+0);
	free_irq(dev->irq, dev);
	free_dma(dev->dma);

	return 0;
}
```
### 数据传输
当内核要发送数据时调用netdev->hard_start_xmit.
hard_start_xmit会尽可能保证发送成功，如果成功返回0，内核会释放socket buffer, 如果返回非0，发送失败，内核会过一段时间后重新发送，这时驱动程序应该停止发送队列，直到错误恢复。
```c
	dev->hard_start_xmit	= net_send_packet;
```

```c
static int net_send_packet(struct sk_buff *skb, struct net_device *dev)
{
	struct net_local *np = netdev_priv(dev);
	int ioaddr = dev->base_addr;
	short length = ETH_ZLEN < skb->len ? skb->len : ETH_ZLEN;
	unsigned char *buf = skb->data;

#if TX_RING
	// 用np->lock保证SMP不冲突
	spin_lock_irq(&np->lock);

	// 将数据包加入网络设备的循环发送队列，记录发送起始时间
	// 加入队列并没有真正放到硬件缓冲区
	add_to_tx_ring(np, skb, length);
	dev->trans_start = jiffies;

	// 如果发送队列满了，告诉内核停止使用该设备发送数据包，即停止发送队列
	if (tx_full(dev))
		netif_stop_queue(dev);

	spin_unlock_irq(&np->lock);
#else
	// 以下是老版本代码，一次发送一个数据包，数据包写入硬件IO端口，更新统计信息，记录起始发送时间
	hardware_send_packet(ioaddr, buf, length);
	np->stats.tx_bytes += skb->len;

	dev->trans_start = jiffies;

	// 如果出错，复位硬件，更新错误统计信息，释放 socket buffer
	if (inw(ioaddr) == /*RU*/81)
		np->stats.tx_aborted_errors++;
	dev_kfree_skb (skb);
#endif

	return 0;
}
```

