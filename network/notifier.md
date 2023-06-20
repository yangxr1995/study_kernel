# 简介
为了及时响应事件，采用通知链的方式来指向指定函数，每个事件都对应一个通知链节点。
通知链节点定义如下：
```c
struct notifier_block {
	notifier_fn_t notifier_call; // 回调函数
	struct notifier_block __rcu *next; // 所有通知链构成一个链表
	int priority; // 优先级
};
```
由于优先级的存在，通知链会按照一定顺序执行。

# 挂入 设备通知链节点

inet_init -> ... -> devinet_init -> register_netdevice_notifier
```c
devinet_init(void)
	register_netdevice_notifier(&ip_netdev_notifier);

// 将 节点 ip_netdev_notifier 加入 通知链 netdev_chain
register_netdevice_notifier(struct notifier_block *nb)
	raw_notifier_chain_register(&netdev_chain, nb);
		notifier_chain_register(&nh->head, n);
	// 
	for_each_net(net)
		call_netdevice_register_net_notifiers(nb, net);
			for_each_netdev(net, dev) {
				call_netdevice_register_notifiers(nb, dev);

					err = call_netdevice_notifier(nb, NETDEV_REGISTER, dev);
						struct netdev_notifier_info info = {
							.dev = dev,
						};

						return nb->notifier_call(nb, val, &info);

				call_netdevice_notifier(nb, NETDEV_UP, dev);




```
