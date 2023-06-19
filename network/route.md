# 
默认网关 本质是网关，也就是网关主机，是IP地址
在路由选择表中不与其他路由选择条目匹配的数据包都将转发到默认网关。

默认路由 本质是路由条目
在无类域间路由选择(CIDR)表示法时，默认路由用0.0.0.0/0表示。

发送包的路由通过路由表和路由缓存来实现的。

数据包，无论是接收还是发送，都需要查询路由，决定是否转发以及哪个接口发送出去。

FIB : (Forwarding Information Base) 转发信息表，内核将路由翻译成FIB的表项，查询路由就是查询FIB


https://developer.aliyun.com/article/598126#slide-6
https://blog.csdn.net/sinat_20184565/article/details/121238020

# 路由项匹配规则
linux支持255张路由表，默认使用 MAIN 表。

当IP包发出时，默认查询 MAIN 表，
当前 MAIN 表如下：
```shell
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         192.168.3.1     255.255.255.0   UG    0      0        0 eth0
0.0.0.0         192.168.3.1     0.0.0.0         UG    0      0        0 eth0
192.168.3.0     0.0.0.0         255.255.255.0   U     0      0        0 eth0
192.168.5.2     192.168.3.1     255.255.255.255 UGH   0      0        0 eth0

注意删除了127.0.0.0的节点
Main:
  +-- 0.0.0.0/0 3 0 5
     |-- 0.0.0.0
        /24 universe UNICAST
        /0 universe UNICAST
     +-- 192.168.0.0/21 2 0 2
        +-- 192.168.3.0/24 2 0 2
           +-- 192.168.3.0/28 2 0 2
              |-- 192.168.3.0
                 /32 link BROADCAST
                 /24 link UNICAST
              |-- 192.168.3.10
                 /32 host LOCAL
           |-- 192.168.3.255
              /32 link BROADCAST
        |-- 192.168.5.2
           /32 universe UNICAST
```


查找路由条目的算法是：
		最长匹配，比较网络段
	1. 使用遍历前缀树，比如key是192.168.2.2，则会遍历到 192.168.0.0节点
	2. 当一条路径遍历失败后（比如key为192.168.2.2，遍历192.168.0.0节点时，发现没有合适的子节点，则失败），则返回到上级节点（返回到0.0.0.0节点）
	3. 当确定某条路由项是否匹配时，先用key & Genmask , 在和 Destination 比较，如果相等则匹配

示例
	key 为 192.168.2.2, 会尝试比较两个路由项：
		0.0.0.0         192.168.3.1     255.255.255.0   UG    0      0        0 eth0
		0.0.0.0         192.168.3.1     0.0.0.0         UG    0      0        0 eth0
	192.168.2.2 & 255.255.255.0 = 0.0.0.2 != 0.0.0.0  不匹配
	192.168.2.2 & 0.0.0.0 = 0.0.0.0 == 0.0.0.0  匹配
	所以使用
		0.0.0.0         192.168.3.1     0.0.0.0         UG    0      0        0 eth0
	L2层根据邻居表查询192.168.3.1的MAC地址做下一跳。

	key 为 0.0.0.4，会尝试比较两个路由项
		0.0.0.0         192.168.3.1     255.255.255.0   UG    0      0        0 eth0
		0.0.0.0         192.168.3.1     0.0.0.0         UG    0      0        0 eth0
	0.0.0.4 & 255.255.255.0 = 0.0.0.0 == 0.0.0.0 匹配
	所以使用
		0.0.0.0         192.168.3.1     255.255.255.0   UG    0      0        0 eth0

	key 为 192.168.3.6 
		192.168.3.0     0.0.0.0         255.255.255.0   U     0      0        0 eth0
	192.168.3.6 & 255.255.255.0 = 192.168.3.0 == 192.168.3.0 匹配

	key 为 192.168.5.9
		192.168.5.2     192.168.3.1     255.255.255.255 UGH   0      0        0 eth0
	192.168.5.9 & 255.255.255.255 = 192.168.5.9 != 192.168.5.2 不匹配
	回退到上级节点，使用默认路由项比较
		0.0.0.0         192.168.3.1     255.255.255.0   UG    0      0        0 eth0
		0.0.0.0         192.168.3.1     0.0.0.0         UG    0      0        0 eth0 匹配
	
	key 为 192.168.5.2
		192.168.5.2     192.168.3.1     255.255.255.255 UGH   0      0        0 eth0
	192.168.5.2 & 255.255.255.255 = 192.168.5.2 == 192.168.5.2 匹配

# 添加路由
route add default gw 192.168.3.1 netmask 0.0.0.0
	sock_ioctl -> .. -> ip_rt_ioctl
```c
int ip_rt_ioctl(struct net *net, unsigned int cmd, struct rtentry *rt)
	struct fib_config cfg;
	switch (cmd) {
		case SIOCADDRT:		/* Add a route */
		case SIOCDELRT:		/* Delete a route */
			// 将输入参数转换为 fib_config 格式
			rtentry_to_fib_config(net, cmd, rt, &cfg);
				// 比较重要的
				cfg->fc_dst_len = plen; // 网络位长度，这里是 0
				cfg->fc_dst = addr; // 目标地址，这里是 0.0.0.0
				cfg->fc_gw4 = addr; // 网关， 192.168.3.1

			// 使用默认table id，返回 MAIN table 
			tb = fib_new_table(net, cfg.fc_table);
				if (id == 0)
					id = RT_TABLE_MAIN;
				tb = fib_get_table(net, id);
				if (tb)
					return tb;

			fib_table_insert(net, tb, &cfg, NULL);

				// 使用目标地址做key, 此处为 0.0.0.0
				key = ntohl(cfg->fc_dst);

				// 根据 fib_config 生成 fib_info
				fi = fib_create_info(cfg, extack);

				// 遍历前缀树 t ，找 key 的 node
				struct trie *t = (struct trie *)tb->tb_data; // 获得根节点
				// l : 叶子节点，key 对应的node ，可能为NULL
				// tp : 中间节点，l找到时，tp时l的parent，l为NULL时，tp可用于创建l
				l = fib_find_node(t, &tp, key);
					struct key_vector *pn, *n = t->kv; // 遍历树 t
					unsigned long index = 0;
					do {
						pn = n; // 保存上一级节点
						n = get_child_rcu(n, index); // 遍历树, n 作为游标

						if (!n)
							break;

						index = get_cindex(key, n); // 计算下一个节点的位置
						if (index >= (1ul << n->bits)) { // key对应的node不存在
							n = NULL;
							break;
						}

						/* keep searching until we find a perfect match leaf or NULL */
					} while (IS_TNODE(n)); // n是中间节点时，循环, 是叶子节点时返回

					*tp = pn; // 记录上级节点

					return n;

				// 此时是首次添加 目标为 0.0.0.0 的路由项，所以叶子节点 l  为NULL
				// 所以 fa 也为NULL
				fa = l ? fib_find_alias(&l->leaf, slen, tos, fi->fib_priority,
							tb->tb_id, false) : NULL;

				if (fa) {
					....
				}

				// 新建fa , fa绑定 fi
				new_fa = kmem_cache_alloc(fn_alias_kmem, GFP_KERNEL);
				new_fa->fa_info = fi;
				...

				// l == NULL
				// tp 指向 存放 新节点的中间节点
				// fa == NULL
				fib_insert_alias(t, tp, l, new_fa, fa, key);
					if (!l)
						return fib_insert_node(t, tp, new, key);

							static int fib_insert_node(struct trie *t, struct key_vector *tp,
										   struct fib_alias *new, t_key key)
								// 创建叶子节点
								// 将 fa 加入 叶子节点的链表
								l = leaf_new(key, new);
									kv = kmem_cache_alloc(trie_leaf_kmem, GFP_KERNEL);
									l = kv->kv;
									l->key = key;
									l->pos = 0;
									l->bits = 0;
									l->slen = fa->fa_slen;
									hlist_add_head(&fa->fa_list, &l->leaf);
								
								// 从中间节点tp中，根据key ，找对应的子节点，
								// 这里,没有子节点，n == NULL
								n = get_child(tp, get_index(key, tp));
								if (n) {
									...
								}
									
								node_push_suffix(tp, new->fa_slen);
								// l->parent = tp
								NODE_INIT_PARENT(l, tp);
								// tp->tnode[ get_index(key, tp) ] = n;
								put_child_root(tp, key, l);
								trie_rebalance(t, tp);
```

## 基于输出方向的路由查询
```
#===========#
H fib_table H
#===========#
'           '     #======================#
'  tb_data  ' --> H         trie         H
+ - - - - - +     #======================#
                  '                      '     #======================#
                  '    key_vector kv     ' --> H   key_vector tnode   H
                  + - - - - - - - - - - -+     #======================#
                                               '      t_key key       '
                                               + - - - - - - - - - - -+
                                               '                      '     #======================#
                                               ' key_vector *tnode[0] ' --> H   key_vector tnode   H
                                               + - - - - - - - - - - -+     #======================#
                  #======================#     '                      '     '                      '
                  H   key_vector tnode   H <-- ' key_vector *tnode[1] '     '      t_key key       '
                  #======================#     + - - - - - - - - - - -+     + - - - - - - - - - - -+
                  '      t_key key       '     '         ...          '     ' key_vector *tnode[0] '
                  + - - - - - - - - - - -+     + - - - - - - - - - - -+     + - - - - - - - - - - -+
                  '                      '     '                      '     '                      '     #=================#
                  ' key_vector *tnode[0] '     ' key_vector *tnode[n] '     ' key_vector *tnode[1] ' --> H key_vector leaf H
                  + - - - - - - - - - - -+     + - - - - - - - - - - -+     + - - - - - - - - - - -+     #=================#
                  '                      '                                  '                      '     '                 '     #====================#     #====================#
                  ' key_vector *tnode[1] '                                  '         ...          '     '    t_key key    '     H     fib_alias      H     H     fib_alias      H
                  + - - - - - - - - - - -+                                  + - - - - - - - - - - -+     + - - - - - - - - +     #====================#     #====================#
                  '                      '                                  '                      '     '                 '     '                    '     '                    '
                  '         ...          '                                  ' key_vector *tnode[n] '     ' hlist_head leaf ' --> ' hlist_node fa_list ' --> ' hlist_node fa_list '
                  + - - - - - - - - - - -+                                  + - - - - - - - - - - -+     + - - - - - - - - +     + - - - - - - - - - -+     + - - - - - - - - - -+
                  ' key_vector *tnode[n] '                                                                                       ' fib_info *fa_info  '     ' fib_info *fa_info  '
                  + - - - - - - - - - - -+                                                                                       + - - - - - - - - - -+     + - - - - - - - - - -+
                                                                                                                                 '     u8 fa_slen     '     '     u8 fa_slen     '
                                                                                                                                 + - - - - - - - - - -+     + - - - - - - - - - -+
```
	查询fib_table的逻辑： 根据key 找到 leaf，leaf链表下有一个或多个 fib_alias，这些 fib_alias 都是 key 相同，但是 fa_slen不同（也就是mask不同）
	需要再遍历 leaf->leaf 链表，找到对于的 fib_alias.
	fib_alias->fa_info 有具体的路由信息
	
## connect
connect 127.0.0.1
__sys_connect -> inet_stream_connect -> tcp_v4_connect
```c
tcp_v4_connect(struct sock *sk, struct sockaddr *uaddr, int addr_len)
	nexthop = daddr = usin->sin_addr.s_addr;
	rt = ip_route_connect(fl4, nexthop, inet->inet_saddr,
			      RT_CONN_FLAGS(sk), sk->sk_bound_dev_if,
			      IPPROTO_TCP,
			      orig_sport, orig_dport, sk);
		// 将输入信息整理成  flowi4  结构
		ip_route_connect_init(fl4, dst, src, tos, oif, protocol,
					  sport, dport, sk);

			rt = __ip_route_output_key(net, fl4);
				// 查询 MAIN table
				fib_lookup(net, fl4, res, 0);
				// 成功，得到 fib_info
				// 将 fib_info 转换为 fib_result
				// 将 fib_result 转换为 dst_entry
				// 对 dst_entry 嵌套一层，得到 rtable

	/* Build a SYN and send it off. */
	tcp_connect(sk);
```

# 输入方向的路由查询
接受IP报文后，需要查询路由以判断是否转发，若转发目的地址能否到达，等，都需要查询路由。
```c
skb : 接受到的数据包
dst : IP头记录的目的地址
src : IP头记录的源地址
tos : IP头记录的服务类型
devin : 接受数据包的网络设备
ip_route_input(struct sk_buff *skb, __be32 dst, __be32 src,
				 u8 tos, struct net_device *devin)
	ip_route_input_noref(skb, dst, src, tos, devin);
```
