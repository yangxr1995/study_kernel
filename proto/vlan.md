# VLAN数据帧

![](./pic/71.jpg)

802.1Qtag 中最重要的是vlan id

vlan id 取值 : 0-4095, 

实际可用 1-4094, 

1为缺省ID，

新建ID必须从2开始

# VLAN的实现

![](./pic/72.jpg)

## 端口接受数据帧

需要考虑
* 数据帧的 vlan id, 可能没有
* 端口允许的 vlan id，可能是单个，或多个
* 端口自己的 PVID

### 接受无tag的数据帧
端口接受所有无tag的数据帧，并根据自己的PVID，给数据帧添加 tag

### 接受有tag的数据帧
端口只接受数据帧的vlan id 和 自己的vlan id匹配的数据帧（端口可能加入多个vlan id）

## 端口发送数据帧
### 发送无tag的数据帧
宿主机发送的数据帧不带tag，端口直接发送。

给数据帧加上tag的操作只在端口接受数据帧时

### 发送带tag的数据帧
只有数据帧的tag和port加入的id匹配时才发送

## access接口

![](./pic/73.jpg)

access接口特点：
* 支持一个PVID
* 只支持一个VLANID, vlanid == pvid
* 只发送数据帧的id和vlanid相同时才发送数据帧，对于没有tag 的数据帧直接发送
* 由于发送的数据帧的id和 pvid相等，所以对所有发送的数据帧进行untag操作

## trunk接口

![](./pic/74.jpg)

trunk的特点：
* 支持多个VlanID, 接受数据帧时，支持接受多种vlanid的数据帧或无tag的数据帧
* 支持一个 PVID, 对于无tag的数据帧，使用pvid给数据帧加上tag
* 当数据帧id和vlanid列表中相等时，允许发送, 对于没有tag 的数据帧直接发送
* 只有当发送帧的id为pvid时才进行untag操作

# 典型应用
![](./pic/75.jpg)

