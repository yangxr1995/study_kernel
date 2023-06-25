数据链路层数据帧的收发

# 关键数据结构
## napi_struct
用于处理输入数据帧，
内核定义了 net_device 描述网络设备，还定义 napi_struct 来管理这类设备的新特性和操作。
但注意，不是所有的驱动都支持 napi 方式
当支持NAPI模式的网络设备收到数据包后，该网络设备的 napi_struct 数据实例会放到 CPU 的 
struct softnet_data 数据结构的链表poll_list中；
网络子系统的接受软件中断 NET_RX_SOFTIRQ 在poll_list链表中的设备的poll方法会被一次调用
执行，一次读入设备硬件缓冲区中的多个输入数据帧.

支持
```c

```

