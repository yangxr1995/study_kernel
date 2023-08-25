#!/bin/sh
# ===========================================================
# usage: tc_control.sh
# traffic control by tc_uplink and tc_downlink
#目前送样是RJ45单口的样品，单网口可以作为WAN/LAN自适应。硬件反馈：作为LTE CPE，RJ45单口应该作为LAN口比较常用， LTE作为WAN口。
#采用多网口时，中兴微设备名称eth0.100对应lan1,lan2和lan3多个lan口，即目前中兴微SDK从设备名称无法区分lan1,lan2和lan3。所以目前单独对某个lan进行限速有困难。
#目前采用网桥限速对单网口lan进行限速。
#第二个参数是lte的cid，这个脚本没用到
#

if [$1 != "down" -a $1 != "up"]; then
    echo "Info: tc_tbf $1 is down or up"
    echo "Info: tc_tbf $2 is default 0"
fi

path_sh=`nv get path_sh`
. $path_sh/global.sh

echo "Info: tc_tbf $1 $2 start "
echo "Info: tc_tbf $1 $2 start" >> $test_log

#流控上下行阀值，为空或为0表示不进行流控，暂时只实现上行的tc，下行将来根据实际需要再扩展实现
UPLINK=`nv get tc_uplink`
DOWNLINK=`nv get tc_downlink`
def_cid=`nv get default_cid`
tc_enable=`nv get tc_enable`

#tc_enable=0，流量控制功能关闭，直接退出
if [ "$tc_enable" == "0" ]; then
	echo "tc_enable=0" 
	echo "tc_enable=0" >> $test_log
	exit 0
fi

#上下行的出口dev需要根据实际情况选择
need_jilian=`nv get need_jilian`
lanEnable=`nv get LanEnable`
if [ "$need_jilian" == "1" ]; then
    if [ "$lanEnable" == "1" ]; then
        IN=`nv get lan_name`
    elif [ "$lanEnable" == "0" ]; then
        IN=`nv get "ps_ext"$def_cid`
    fi
elif [ "$need_jilian" == "0" ]; then
    IN=`nv get lan_name`
fi

#双栈时，ipv4和ipv6的默认外网口可能不一致，虽然短期内都不会有实际场景
OUT4=$defwan_rel  # "eth0"
OUT6=$defwan6_rel # ""

if [ "$lanEnable" == "1" ]; then
    GATEWAY=`nv get lan_ipaddr`
fi

echo "IN=$IN, OUT4=$OUT4, OUT6=$OUT6, GATEWAY=$GATEWAY, DOWNLINK=$DOWNLINK, UPLINK=$UPLINK"
echo "IN=$IN, OUT4=$OUT4, OUT6=$OUT6, GATEWAY=$GATEWAY, DOWNLINK=$DOWNLINK, UPLINK=$UPLINK" >> $test_log

#清空原先的流程规则
tc qdisc del dev $IN root
if [ "$OUT4" != "" ]; then
    tc qdisc del dev $OUT4 root
fi
if [ "$OUT6" != "" -a "$OUT6" != "$OUT4" ]; then
    echo "clear tc for $OUT6"
    tc qdisc del dev $OUT6 root
fi

#给内核恢复快速转发级别
fastnat_level=`nv get fastnat_level`
echo "Info: fastnat_level restore to：$fastnat_level" >> $test_log
echo $fastnat_level > /proc/net/fastnat_level

ifconfig $IN txqueuelen 10
if [ "$OUT4" != "" ]; then
    ifconfig $OUT4 txqueuelen 10
fi
if [ "$OUT6" != "" -a "$OUT6" != "$OUT4" ]; then
    ifconfig $OUT6 txqueuelen 10
fi

#适配之前的客户：如果$1不等于down/DOWN，就按up/UP处理
if [ "$1" == "down" -o "$1" == "DOWN" ]; then
	echo "traffic control down" 
	echo "traffic control down" >> $test_log
	exit 0
fi

if [ "$DOWNLINK" == "" -o "$DOWNLINK" == "0" ] && [ "$UPLINK" == "" -o "$UPLINK" == "0" ]; then
    echo "no need to traffic control"
    echo "no need to traffic control" >> $test_log
    exit 0
fi

#暂定uc/v2都需要关闭快速转发

echo 0 > /proc/net/fastnat_level

if [ "$DOWNLINK" != "0" -a "$DOWNLINK" != "" ]; then
    echo "traffic control for down"
    echo "traffic control for down" >> $test_log
    
    #tc_local是给内网有个速率防止限制后登录不了webui
    LOCAL=`nv get tc_local`
    #SUM=`expr ${DOWNLINK} + ${LOCAL}`
    if ["$DOWNLINK" -gt "$LOCAL"];then
        SUM=$DOWNLINK
        echo "DOWNLINK gt LOCAL then SUM is DOWNLINK"        
    else
        SUM=$LOCAL
        echo "DOWNLINK lt LOCAL then SUM is LOCAL"
    fi
    echo "LOCAL=$LOCAL, SUM=$SUM"
    echo "LOCAL=$LOCAL, SUM=$SUM" >> $test_log
    
    ifconfig $IN txqueuelen 1000

    #限速的大小单位虽然是bps，但实际是字节
    tc qdisc add dev $IN root handle 1: htb default 20
    tc class add dev $IN parent 1: classid 1:1 htb rate ${SUM}kbit
    tc class add dev $IN parent 1:1 classid 1:20 htb rate ${DOWNLINK}kbit
    tc class add dev $IN parent 1:1 classid 1:10 htb rate ${LOCAL}kbit
    tc qdisc add dev $IN parent 1:10 handle 10: sfq perturb 10
    tc qdisc add dev $IN parent 1:20 handle 20: sfq perturb 10
    tc filter add dev $IN protocol ip parent 1:0 prio 1 u32 match ip src ${GATEWAY}/32 match ip sport 80 0xffff flowid 1:10
fi

if [ "$UPLINK" != "0" -a "$UPLINK" != "" ]; then
    if [ "$OUT4" != "" ]; then
        echo "traffic control for up - ipv4"
        echo "traffic control for up - ipv4" >> $test_log
        ifconfig $OUT4 txqueuelen 1000
        tc qdisc add dev $OUT4 root handle 1: htb default 1
        tc class add dev $OUT4 parent 1: classid 1:1 htb rate ${UPLINK}kbit
    fi

    if [ "$OUT6" != "" -a "$OUT6" != "$OUT4" ]; then
        echo "traffic control for up - ipv6"
        echo "traffic control for up - ipv6" >> $test_log
        ifconfig $OUT6 txqueuelen 1000
        tc qdisc add dev $OUT6 root handle 1: htb default 1
        tc class add dev $OUT6 parent 1: classid 1:1 htb rate ${UPLINK}kbit
    fi
fi

总结：
此脚本用于限制路由器上下行流量，
上行流量：目标网络为外网，即从WAN口发出

清空原来的规则
tc qdisc del dev $OUT4 root
ifconfig $OUT4 txqueuelen 1000
尽管可以使用无class的，但他还是使用htb
tc qdisc add dev $OUT4 root handle 1: htb default 1
只有一个class 限制从WAN口的所有输出流量, class htb 默认的叶子节点 qdisc 为 pfifo，所以不需要设置
tc class add dev $OUT4 parent 1: classid 1:1 htb rate ${UPLINK}kbit

下行流量：目标网络为内网，即从LAN口发出
对于下行流量，考虑了从本机发出的http流量给足带宽，避免本机web无法访问
总的来说需要分两种流量分别限速，对于本机http流量限速 ${LOCAL}kbit
                                对于其他流量限速${DOWNLINK}kbit
								总流量 ${SUM}kbit
清空原来的规则
tc qdisc del dev $IN root
将 br0 根qdisc定义为 htb，方便挂class 和 filter，默认filter目标为 20:
tc qdisc add dev $IN root handle 1: htb default 20
挂 1:1 ，限制总流量
tc class add dev $IN parent 1: classid 1:1 htb rate ${SUM}kbit
挂 1:20 限制其他流量
tc class add dev $IN parent 1:1 classid 1:20 htb rate ${DOWNLINK}kbit
挂 1:10 限制本机http流量
tc class add dev $IN parent 1:1 classid 1:10 htb rate ${LOCAL}kbit
挂 qdisc 使用sfq
tc qdisc add dev $IN parent 1:10 handle 10: sfq perturb 10
挂 qdisc 使用sfq
tc qdisc add dev $IN parent 1:20 handle 20: sfq perturb 10
设置 filter 挂到 1: ，匹配源IP为 192.168.0.1/32 源地址为 80 的数据包转发到 1:10 即本地http流量处理
tc filter add dev $IN protocol ip parent 1:0 prio 1 u32 match ip src ${GATEWAY}/32 match ip sport 80 0xffff flowid 1:10



IN=eth0
tc qdisc add dev $IN root handle 1: htb default 20
tc class add dev $IN parent 1: classid 1:1 htb rate 10000kbit
tc class add dev $IN parent 1:1 classid 1:20 htb rate 1000kbit
tc class add dev $IN parent 1:1 classid 1:10 htb rate 90000kbit
tc qdisc add dev $IN parent 1:10 handle 10: sfq perturb 10
tc qdisc add dev $IN parent 1:20 handle 20: sfq perturb 10
tc filter add dev $IN protocol ip parent 1:0 prio 1 u32 match ip src ${GATEWAY}/32 match ip sport 80 0xffff flowid 1:10

