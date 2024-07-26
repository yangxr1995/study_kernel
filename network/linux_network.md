# TAP/TUN设备


TAP/TUN是Linux内核实现的一对虚拟网络设备，TAP工作在二层，TUN工作在三层，Linux内核通
过TAP/TUN设备向绑定该设备的用户空间应用发送数据；反之，用户空间应用也可以像操作硬件网络设
备那样，通过TAP/TUN设备发送数据。



