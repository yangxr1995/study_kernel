
# 防火墙 内网 eth1 192.168.10.1
#        外网 eth0 77.77.77.x

INET_NET="192.168.10.0/24"

# 刷新规则，并设置策略为DROP
$IPTABLES -F
$IPTABLES -F -t nat
$IPTABLES -X
$IPTABLES -P INPUT DROP
$IPTABLES -P FORWARD DROP
$IPTABLES -P OUTPUT DROP

# INPUT 链
## 能进入防火墙主机的数据包只能是局域网主机的ssh连接和icmp
## 或者又防火墙发起的连接的数据包
## 状态追踪
$IPTABLES -A INPUT -m state --state INVALID -j LOG --log-prefix "DROP INVALID"
$IPTABLES -A INPUT -m state --state INVALID -j DROP
$IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

## 确保从内网口来的数据源IP必须为局域网
$IPTABLES -A INPUT -i eth1 -s ! $INET_NET -j LOG --log-prefix "SPOOFED PKT"
$IPTABLES -A INPUT -i eth1 -s ! $INET_NET -j DROP

## ACCEPT rule
$IPTABLES -A INPUT -i eth1 -p tcp -s $INET_NET --dport 22 --syn -m state --sate NEW -j ACCEPT
$IPTABLES -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

## default INPUT LOG rule
$IPTABLES -A INPUT -i ! lo -j LOG --log-prefix "DROP " --log-ip-options --log-tcp-options

# OUTPUT
$IPTABLES -A OUTPUT -m state --state INVALID -j LOG --log-prefix "DROP INVALID" --log-ip-options --log-tcp-options
$IPTABLES -A OUTPUT -m state --state INVALID -j DROP
$IPTABLES -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

## 允许防火墙发起如下连接
## 方便防火墙下载升级文件，查询DNS等
$IPTABLES -A OUTPUT -p tcp --dport 21 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A OUTPUT -p tcp --dport 22 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A OUTPUT -p tcp --dport 25 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A OUTPUT -p tcp --dport 80 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A OUTPUT -p tcp --dport 443 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A OUTPUT -p udp --dport 53 --syn -m state --state NEW -j ACCEPT

## default OUTPUT LOG rule
$IPTABLES -A INPUT -i ! lo -j LOG --log-prefix "DROP " --log-ip-options --log-tcp-options


# FORWARD
$IPTABLES -A FORWARD -m state --state INVALID -j LOG --log-prefix "DROP INVALID" --log-ip-options --log-tcp-options
$IPTABLES -A FORWARD -m state --state INVALID -j DROP
$IPTABLES -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

## 确保从内网口来的数据源IP必须为局域网
$IPTABLES -A FORWARD -i eth1 -s ! $INET_NET -j LOG --log-prefix "SPOOFED PKT"
$IPTABLES -A FORWARD -i eth1 -s ! $INET_NET -j DROP

## ACCEPT rule
## 安全度要求高的应用，如 ssh ftp，只转发来自内网主机的数据包
## 如 http https 的数据包，可以转发来自任何源的数据包
$IPTABLES -A FORWARD -i eth1 -p tcp --dport 21 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A FORWARD -i eth1 -p tcp --dport 22 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A FORWARD -i eth1 -p tcp --dport 25 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A FORWARD -p tcp --dport 80 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A FORWARD -p tcp --dport 443 --syn -m state --state NEW -j ACCEPT

$IPTABLES -A FORWARD -p udp --dport 53 --syn -m state --state NEW -j ACCEPT
$IPTABLES -A FORWARD -p icmp --icmp-type echo-request -j ACCEPT

## default OUTPUT LOG rule
$IPTABLES -A FORWARD -i ! lo -j LOG --log-prefix "DROP " --log-ip-options --log-tcp-options


# NAT
## 来自外网回复的数据包需要DNAT
## 来自内网发送给外网的数据包需要 SNAT
## DNAT 一定实在 PREROUTING ，因为查询路由主要根据目标地址
## 同理，SNAT一定再 POSTROUTING ，如此才不影响 routing
$IPTABLES -t nat -A PREROUTING -p tcp --dport 80 -i eth0 -j DNAT --to 192.168.10.3:80
$IPTABLES -t nat -A PREROUTING -p tcp --dport 443 -i eth0 -j DNAT --to 192.168.10.3:443
$IPTABLES -t nat -A POSTROUTING -s $INET_NET -o eth0 -j MASQUERADE



