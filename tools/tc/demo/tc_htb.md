本示例实现了对指定主机的上下流量限制，使用tc filter fw 实现

如何使用 filter fw 选择器 ?
如将 fwmark 为 111 的数据包发送到 classid 为 5:5 的类别，可以按照以下步骤进行操作：

使用以下命令添加一个 tc 过滤器：
```shell
tc filter add dev eth0 parent 1: prio 1 handle 111 fw flowid 1:5
```
dev eth0 指定了要添加过滤器的网络接口为 eth0。
parent 1: 指定了过滤器的父类别，这里假设为 1:。
prio 1 指定了过滤器的优先级为 1。
handle 111 指定了过滤器的处理标识（handle），这里设置为 111。
fw 指定了使用防火墙（firewall）作为选择器。
flowid 1:5 指定了将满足过滤条件的数据包发送到 classid 为 5:5 的类别。

```c
	while(cnt<num_str)
	{
		
		memset(split_cfg,0,sizeof(split_cfg));
		split_str(splitstr[cnt],",",split_cfg,&num_cfg);
		strcpy(qos_cfg[cnt].ipaddr,split_cfg[1]);
		strcpy(qos_cfg[cnt].download,split_cfg[2]);
		strcpy(qos_cfg[cnt].upload,split_cfg[3]);
		qos_cfg[cnt].mark=atoi(split_cfg[0]);
	
		cnt++;
	}

	//downlink
	
	// 将流量分为两类，一类为本地http服务器从br0下传的流量
	//                 一类为其他流量
	// 对于本地http服务器的流量需要确保足够的带宽，即使在链路拥堵的情况

	// 删除设备上的tc规则
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc del dev %s root",ifname_lan);//del lan qdisc
	system_cmd_ex(cmd);
		
	// 添加 root节点 htb，默认filter指向 190:，此节点主要用于转发，和下挂class
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s root handle 5:0 htb default 190 r2q 64",ifname_lan);//create qdisc
	system_cmd_ex(cmd);	
	
	// 添加次级节点，这层只有一个节点 5:1，htb，用于限制总流量，和流量借用
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 5:0 classid 5:1 htb rate %dkbit quantum 30000",ifname_lan,sum_link);
	system_cmd_ex(cmd);
	
	// 添加class 5:190 htb，用于限制其他流量的带宽
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 5:1 classid 5:190 htb rate 1kbit ceil %dkbit prio 7 quantum 30000",ifname_lan,tcdownlink);
	system_cmd_ex(cmd);

	// 添加class 5:290 htb，用于限制本机http流量的带宽
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 5:1 classid 5:290 htb rate 1kbit ceil %dkbit prio 7 quantum 30000",ifname_lan,tclocal);
	system_cmd_ex(cmd);
	
	// 将默认的叶子节点由 pfifo 改成 sfq
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s parent 5:190 handle 190: sfq perturb 10",ifname_lan);
	system_cmd_ex(cmd);
	
	// 将默认的叶子节点由 pfifo 改成 sfq
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s parent 5:290 handle 290: sfq perturb 10",ifname_lan);
	system_cmd_ex(cmd);
	
	// 添加filter到根 qdisc 5:0 htb，将本地http流量转发到 5:290
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc filter add dev %s protocol ip parent 5:0 prio 1 u32 match ip src %s/32 match ip sport 80 0xffff flowid 5:290",ifname_lan,lan_gateway);
	system_cmd_ex(cmd);

	// 处理对指定IP的主机限制下行流量
	if(num_str!=0 && num_str <32)
	{
		for(cnt_cfg=0;cnt_cfg<num_str;cnt_cfg++)
		{
			if(qos_cfg[cnt_cfg].download == NULL || 0==strcmp(qos_cfg[cnt_cfg].download,"0"))
			{
	
				continue;
			}

			// 将从br0进入的tcp , udp数据包，且源IP为指定主机，标记他 mark
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A PREROUTING -t mangle -i %s -p tcp -m iprange --src-range %s-%s -j MARK --set-mark %d",ifname_lan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);

			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A PREROUTING -t mangle -i %s -p udp -m iprange --src-range %s-%s -j MARK --set-mark %d",ifname_lan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);

			// 将从br0出去的tcp , udp数据包，且目的IP为指定主机，标记他 mark + mark_len
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A POSTROUTING -t mangle -o %s -p tcp -m iprange --dst-range %s-%s -j MARK --set-mark %d",ifname_lan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,(qos_cfg[cnt_cfg].mark+mark_lan));
			system_cmd_ex(cmd);

			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A POSTROUTING -t mangle -o %s -p udp -m iprange --dst-range %s-%s -j MARK --set-mark %d",ifname_lan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,(qos_cfg[cnt_cfg].mark+mark_lan));
			system_cmd_ex(cmd);

			// 为指定主机添加class分支，用于缓存和限制他的流量
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 5:1 classid 5:%d htb rate 1kbit ceil %skbit prio 2 quantum 30000",ifname_lan,(qos_cfg[cnt_cfg].mark+mark_lan),qos_cfg[cnt_cfg].download);
			system_cmd_ex(cmd);

			// 将所有主机的叶子qdisc都设置为 553: sfq
			// 注意这里没有bug，即使不同的 class 有同名的 qdisc，因为每个class有自己独立的qdisc
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s parent 5:%d handle 553 sfq perturb 10",ifname_lan,(qos_cfg[cnt_cfg].mark+mark_lan));
			system_cmd_ex(cmd);
		
			// 在root qdisc添加filter，将做了下行被标记的数据包转发到相关的class
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc filter add dev %s parent 5:0 protocol all prio 100 handle %d fw classid 5:%d",ifname_lan,(qos_cfg[cnt_cfg].mark+mark_lan),(qos_cfg[cnt_cfg].mark+mark_lan));
			system_cmd_ex(cmd);
			
		}

	//uplink
	
	// 删除WAN口原有tc
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc del dev %s root",ifname_wan);//del wan qdisc
	system_cmd_ex(cmd);

	// 添加root htb ，用于派发，default 270
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s root handle 2: htb default 270 r2q 64",ifname_wan);//create qdisc
	system_cmd_ex(cmd);	
	
	// 创建次级 htb，用于限制总流量
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 2:0 classid 2:1 htb rate %dkbit ceil %dkbit quantum 30000",ifname_wan,tcuplink,tcuplink);
	system_cmd_ex(cmd);
	
	// 为其他流量创建htb，用于控制总上行流量
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 2:1 classid 2:270 htb rate 1kbit ceil %dkbit prio 7 quantum 30000",ifname_wan,tcuplink);
	system_cmd_ex(cmd);

	// 为其他流量class 创建叶子节点
	memset(cmd,0,sizeof(cmd));
	snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s parent 2:270 handle 270: sfq perturb 10",ifname_wan);
	system_cmd_ex(cmd);

	// 限制指定主机的上行流量
	if(num_str!=0 && num_str<32)
	{
		for(cnt_cfg=0;cnt_cfg<num_str;cnt_cfg++)
		{
			if(qos_cfg[cnt_cfg].upload == NULL || 0==strcmp(qos_cfg[cnt_cfg].upload,"0") )
			{
				continue;
			}
			// 对指定主机从WAN口输出的udp，tcp包做标记
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A POSTROUTING -t mangle -o %s -p udp -m iprange --src-range %s-%s -j MARK --set-mark %d",ifname_wan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);

			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"iptables -A POSTROUTING -t mangle -o %s -p udp -m iprange --src-range %s-%s -j MARK --set-mark %d",ifname_wan,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].ipaddr,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);

			// 添加一条分支class，用于限制指定主机的流量
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc class add dev %s parent 2:1 classid 2:%d htb rate 1kbit ceil %skbit prio 2 quantum 30000",ifname_wan,qos_cfg[cnt_cfg].mark,qos_cfg[cnt_cfg].upload);
			system_cmd_ex(cmd);
		
			// 将每个class的qdisc都改成 SFQ类型
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc qdisc add dev %s parent 2:%d handle 213 sfq perturb 10",ifname_wan,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);

			// 在根qdisc添加filter，分发主机的特征的流量到主机分支class
			memset(cmd,0,sizeof(cmd));
			snprintf(cmd,sizeof(cmd),"tc filter add dev %s parent 2:0 protocol all prio 100 handle %d fw classid 2:%d",ifname_wan,qos_cfg[cnt_cfg].mark,qos_cfg[cnt_cfg].mark);
			system_cmd_ex(cmd);
		}
	}
```

tc qdisc add dev eth0 parent 2:1 handle 213 sfq perturb 10
tc qdisc add dev eth0 parent 2:2 handle 213 sfq perturb 10
