# tbf
场景，主机的上级设备速度很慢，并且有很大的发送队列，当主机上传大文件时，会导致上级设备的发送队列被填满，而影响交互数据的传输。
为此使用 tbf 限制本机的输出速率。
```shell
tc qdisc add dev eth0 root tbf rate 220kbit latency 50ms burst 1600

# 创建了一个qdisc ，handle 名为 8001:
# rate 为 token的生成速率
# burst ：桶能存放多少token，单位字节
# latency : 等待获得token的数据包最长等待时间
/root # ./tc qdisc show dev eth0
qdisc tbf 8001: root refcnt 2 rate 220Kbit burst 1599b lat 50ms

/root # ./iperf3 -c 192.168.3.2
Connecting to host 192.168.3.2, port 5201
[  4] local 192.168.3.10 port 57536 connected to 192.168.3.2 port 5201
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-1.00   sec  82.0 KBytes   670 Kbits/sec    5   2.83 KBytes
[  4]   1.00-2.01   sec  31.1 KBytes   253 Kbits/sec    0   2.83 KBytes
[  4]   2.01-3.00   sec  0.00 Bytes  0.00 bits/sec    0   1.41 KBytes
[  4]   3.00-4.01   sec  36.8 KBytes   300 Kbits/sec    0   1.41 KBytes
[  4]   4.01-5.01   sec  32.5 KBytes   267 Kbits/sec    0   2.83 KBytes
```



