# 网络层攻击与防御
## 网络层攻击的定义
* 首部滥用 : 包含恶意构造，损坏或非法改装的网络层首部数据包，如带有伪造的源地址或恶意偏移值的IP包
* 带宽饱和攻击 : 如ICMP发送的分布式DDos

对于DDoS攻击，由于DDoS代理可以伪造源IP，所以对DDoS攻击流量的检查几乎是徒劳，更好的做法是检查 DDoS 主控给代理的指令数据包，以移除DDoS代理点。

# 传输层攻击

## 传输层攻击的定义
* 耗尽连接资源 : 如 SYN攻击
* 首部滥用 : 如 RST 攻击


