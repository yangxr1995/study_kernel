# Linux Advanced Routing & Traffic Control HOWTO
https://lartc.org/howto/index.html

## iproute2
为什么用iproute2 ?
古老的arp ifconfig route 命令虽然能工作，但linux2.2之后对网络子系统进行了重新设计和实现，添加了很多新功能，
为了新功能和更好的效率，需要 iproute2

### 显示链路
```shell
# ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
    link/ether 00:0c:29:89:30:6d brd ff:ff:ff:ff:ff:ff
    altname enp2s1
```
iproute 切断了 链路 和 IP地址 的直接联系。

### 显示IP
```shell
root@u22:/# ip addr show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:0c:29:89:30:6d brd ff:ff:ff:ff:ff:ff
    altname enp2s1
    inet 192.168.3.2/24 brd 192.168.3.255 scope global noprefixroute ens33
       valid_lft forever preferred_lft forever
    inet6 fe80::da3a:e4d2:87f2:80f0/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
```
需要注意的子网掩码，以127.0.0.1 IP地址为例
255.0.0.0 -> 127.0.0.1/8
255.255.0.0 -> 127.0.0.1/16
255.255.255.0 -> 127.0.0.1/24
255.255.255.255 -> 127.0.0.1/32
显然 8，16，24，32表示为1的bit位数量

还需注意 qdisc

### 显示路由
```shell
root@u22:/# ip route show
default via 192.168.4.2 dev ens38 proto dhcp metric 101
default via 192.168.3.1 dev ens33 proto static metric 20100
169.254.0.0/16 dev ens33 scope link metric 1000
192.168.3.0/24 dev ens33 proto kernel scope link src 192.168.3.2 metric 100
192.168.4.0/24 dev ens38 proto kernel scope link src 192.168.4.128 metric 101
```
第一项用于比较目的地址

带 via 192... 指网关，也就是下一跳的MAC地址为此主机的MAC

dev ensxx 指输出设备

proto dhcp/static 指这条路由项怎么被设置的

metric 表示路由的度量值（metric）。度量值用于确定路由选择的优先级，较低的度量值表示更优先的路由。
当存在多个匹配的路由时，系统会选择度量值最低的路由进行数据包转发。

### ARP
```shell
root@u22:/# ip neigh show
192.168.4.254 dev ens38 lladdr 00:50:56:ef:b6:3d STALE
192.168.4.2 dev ens38 lladdr 00:50:56:e3:4b:0d STALE
192.168.3.1 dev ens33 lladdr 00:50:56:c0:00:01 REACHABLE

```
删除ARP项
```shell
ip neigh delete <MAC> dev <dev_name>
 ```

### 策略路由

#### 查看策略
```shell
root@u22:/mnt/share/study_kernel/network# ip rule list
0:      from all lookup local
220:    from all lookup 220
32766:  from all lookup main
32767:  from all lookup default
```
其中 main 表就是 ip route 默认操作的表




