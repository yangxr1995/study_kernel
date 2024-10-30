[[toc]]

# MQTT

专用于 低带宽，高延迟，不可靠的网络协议

## 能力概述
### 发布订阅

```ascii
   使用发布订阅模式，而且请求响应
  ┌──────┐ request  ┌───────┐  
  │client├─────────►│ server│              
  └──────┘◄─────────└───────┘  
           response               msg     ┌──────┐
                                  ┌──────►│client│
  ┌──────┐  msg     ┌──────┐      │       └──────┘
  │client├─────────►│broker│──────┘
  └──────┘          └──────┘─────┐        ┌──────┐
                                 └───────►│client│
                                 msg      └──────┘

    基于发布订阅模式，mqtt可以轻松实现
   一对一(点对点通信)
   一对多(消息广播)
   多对一(数据采集)
  ┌────┐       ┌────┐        ┌────┐        ┌────┐   ┌────┐    ┌────┐
  │cli ├──────►│cli │        │cli ├───────►│cli │   │cli │───►│cli │
  └────┘       └────┘        └────┴────┐   └────┘   └────┘    └────┘
                                       │   ┌────┐   ┌────┐    ▲
                                       └──►│cli │   │cli ├────┘
                                           └────┘   └────┘         
```

### 协议位置
```ascii

                          将mqtt继承其他协议，而从实现安全可靠支持web的协议
                                                 ┌────────────────────────────────────────┐
                                                 │        payload 业务数据                │
                                                 ├────────────────────────────────────────┤
 ┌────────────────────────────┐                  │        mqtt 业务可靠                   │
 │     mqtt 业务可靠          │                  ├────────────────────────────────────────┤
 ├────────────────────────────┤    ───────►      │        websocket 和流量器通信          │
 │      tcp 字节流可靠        │                  ├────────────────────────────────────────┤
 └────────────────────────────┘                  │        ssl 加密                        │
                                                 ├────────────────────────────────────────┤
                                                 │        tcp 字节流可靠                  │
                                                 └────────────────────────────────────────┘
```

### QoS

TCP不保证消息一定到达，只保证当消息丢失时，通知用户

mqtt支持对每个报文设置不同的qos，以实现可靠和效率的平衡，QoS0(消息可能丢失) QoS1(消息不会丢失可能重复) QoS2(消息不会丢失不会重复)

- QoS0 : 消息可能丢失
- QoS1 : 消息不会丢失但可能重复
- QoS2 : 消息不会丢失也不会重复

QoS越高服务越可靠，但性能开销越大

### keepalive

TCP的keepalive太长了，mqtt有keepalive报文，以实现快速检测异常掉线

### 遗嘱消息

当消息发布者异常断开时，无法通知订阅者自己掉线了，所以mqtt提供遗嘱机制，

消息发布者可以在上线时就上报自己的遗嘱，当Broker检测到发布者异常掉线时，就将其遗嘱广播给其订阅者

```ascii


        ┌────────┐           ┌───────┐              ┌────────┐
        │ client │           │ broker│              │ client │
        └────┬───┘           └───┬───┘              └────┬───┘
             │                   │                       │
             ├────────msg ──────►│                       │
             │                   ├───────────msg ───────►│
             │─────── break ─────┤                       │
             │                   ├───────────will───────►│
             │                   │                       │
             │                   │                       │
             │                   │                       │
             ▼                   ▼                       ▼
```

### 保留消息


发布者可以发送保留消息，Broker会持久化保留此消息，当订阅者上线，会立即获得保留消息。

如此发布者可以降低消息的发送周期，以达到低功耗的目的。订阅者可以迅速获得最新消息，不用等待下一个周期

```ascii
       ┌───────┐           ┌───────┐
       │ client│           │ broker│
       └───┬───┘           └───┬───┘
           ├──────msg ────────►│               ┌───────────┐
           │                   │               │ subscriber│
           │                   │               └─────┬─────┘
           │                   ├────retained msg────►│
           │                   │                     │
           │                   │                     │
           │                   │                     │
           │                   │                     │
           ▼                   ▼                     ▼
```

## 报文类型

# 报文格式

分为三部分:

固定报头 | 可变报头 | 有效载荷

固定报头内容：
报文类型 | 标志 | 剩余报文长度

可变报头内容
内容视报文类型而定

有效载荷

# 报文类型
## 连接
### CONNECT

客户端标识符
用户名
密码
遗嘱消息

### CONNACK
### DISCONNECT

## 发布
### PUBLISH

固定报头
报文类型|DUP|QoS|Retain|剩余报文长度 

可能有可变报头
主题|报文标识符

有效载荷
消息内容


主题
QoS
payload

### PUBACK
### PUBREC
### PUBREL
### PUBCOMP

## 订阅
### SUBSCRIBE

主题
QoS

### SUBACK
### UNSUBSCRIBE
### UNSUBACK

## 心跳
### PINGREQ
固定报头(2字节)
报文类型 保留 剩余报文长度 
0xC      0x0  0x00

无可变报头

无有效载荷

### PINGRESP

# 发布订阅

## PUBLISH 推送消息

### 重要字段

#### Topic Name

类型 utf-8 string

home/temperature

#### QoS

类型 int
QoS0 : 消息可能丢失
QoS1 : 消息不会丢失，可能重复
QoS2 : 消息不会丢失，不会重复

#### Retain

指定此消息是否为保留消息

Broker会对保留消息进行持久化，当订阅者上线后，会立即收到保留消息，而不需要等待下次发布周期

#### DUP

有效值 : 0 - 1

说明本消息是否为重传消息

只有当QoS1 和QoS2时，才有防丢包的重传功能，所以只有此时此字段才可能被置一

#### Packet ID

有效值 : 1 - 65535

此消息的标识符

只有当QoS1 和QoS2时，才有防丢包的重传功能，所以只有此时此字段才可能被设置

### payload

类型 : char

可以放 json , 加密文本，二进制字段 

## SUBSCRIBE 订阅消息

Packet ID

Subscription List

### Packet ID

在 SUBSCRIBE 和 SUBACK 被使用，用于防止丢包

有效值 : 1 - 65535

此消息的标识符


### Subscription List

订阅列表可以包含多个订阅

每个订阅由主题过滤器和QoS组成

Topic Filter 1 | QoS
Topic Filter 2 | QoS
Topic Filter 3 | QoS

#### Topic Filter
主题过滤器支持通配符匹配

订阅 a/+

当发布两个主题的消息: a/1 a/2

两个主题的消息都能会被Broker转发给订阅者

#### QoS
订阅的QoS用于设置Broker转发给订阅者时，使用的最大QoS等级

比如 

订阅QoS为1

发布的QoS为 2

Broker使用 QoS1 转发给订阅者

订阅QoS为1

发布的QoS为0

Broker使用 QoS0 转发给订阅者


#### 订阅的覆盖
当Broker已有订阅条目

Topic Filter  QoS
    a/1        0

订阅者再次订阅，且Topic Filter相同，则条目会被覆盖

Topic Filter  QoS
    a/1        2

Broker 的订阅条目

Topic Filter  QoS
    a/1        2

若 Topic Filter 不同，则会添加，如再订阅

Topic Filter  QoS
    a/+        2

Broker 条目

Topic Filter  QoS
    a/1        2
Topic Filter  QoS
    a/+        2

当发布 a/1 时，由于两个订阅条目都匹配，则会发送两条消息给订阅者

## SUBACK

订阅的操作响应

Packet ID

Reason Codes

订阅可能失败，根据 Reason code 说明

### Reason Code

#### 成功
0x00 订阅成功，且最大QoS为0
0x01 订阅成功，且最大QoS为1
0x02 订阅成功，且最大QoS为2

#### 失败
0x80 订阅失败

## UNSUBSCRIBE

取消订阅

Packet ID
Topic Filters

### Topic Filters

主题名称必须完全匹配，不能使用通配符


## UNSUBACK

取消订阅的操作响应

Packet ID
Reason Code (mqtt3没有Reason code, mqtt5 新增了Reason code)

## Topic || Topic Filters

主题是发布订阅的重要字段

mqtt对主题的定义如下

主题同个斜杠进行分层

a/b/c

支持通配符

单层通配符 +

多层通配符 #

Broker 的Topic 以 $开头，用于发布系统信息

# 会话

会话是mqtt client和 server的通信时的概念，和 发布者 订阅者 无关。

会话用于实现跨connection业务通信。

## 会话的常见应用场景

在网络环境糟糕的环境下。

当 A 和 B 通信时，B掉线了，A会继续向Broker发布消息，但消息会因为没有订阅者而被丢弃。

当B再次上线时，需要重新订阅。

如果使用了会话，

B掉线后，B的订阅要求会被server存储，

当A继续发布消息时，由于有对应的订阅，会发送给订阅者，此时订阅者不在线，则会存储要发送的消息。

当B重新上线后，沿用上次会话，不需要重新订阅，即可获得上次的消息.

要实现这个功能，mqtt的客户端和服务端需要存储一些信息 

## 如何实现会话

对于server端，需要存储 

1. 客户端的订阅信息，如此当订阅者掉线后，仍然可以为其保存消息，而且当客户端在会话过期时间内重连，都不需要重新订阅 

2. 已发送给客户端，但还未完成确认的 QoS1 和 QoS2 消息，和等待发送给客户端的 QoS0 QoS1 QoS2 消息 

3. 从客户端收到的，还没有完成确认的QoS2消息

4. 遗嘱消息和遗嘱延迟间隔(mqtt3中遗嘱消息会立即下发)

5. 会话本身，当客户端重新连接时，服务端会根据client id 查询获得会话，并用 CONNACK( Session Present 字段) 询问客户端是否复用上次会话

对于client，需要存储 

1. 已发送给server，但未完成确认的QoS1 和 QoS2消息

2. 等待发送给server的 QoS0 QoS1 QoS2 消息


## 相关字段

### clean start

是否删除上次会话 

有效值 0 - 1

0 : server会根据client id 查询是否有存在的session，若已存在，则使用上次的session，若session不存在，则创建新的session

1 : 会存在上次会话，则丢弃，并创建新会话

典型应用

1. 当client重启后发现自己的会话状态已丢失，则指定 clean start 已使用新会话

### session expiry interval

会话在未连接状态下，多少秒后过期

0 : 会话在断开连接后立即过期

n : 断开连接后n秒过期

0xFFFFFFFF : 会话永不过期

2. 希望client在业务未完成时，不受网络波动影响，则在会话开始时设置 session expiry interval > 0 ，以异常的网络断开，

当业务完成主动断开连接时，设置 session expiry interval = 0，以立即删除会话


## 使用会话场景分析

### 使用持久会话的场景

1. 不希望错过离线时的消息

2. 不希望QoS1 QoS2消息丢失

3. 不希望每次连接都需要重新订阅

4. 设备定期休眠，不希望长时间维护连接 

### 不需要持久会话

1. 只对外发布QoS0 消息，不会接受任何消息

2. 只订阅QoS0 消息，不关心离线期间的消息 


# QoS

QoS0 : 消息可能丢失
QoS1 : 消息不会丢失，可能重复
QoS2 : 消息不会丢失，不会重复

随着QoS的增加，靠靠性增加，复杂度增加，传输性能下降

## QoS0

发送端只发送一次。

发送可能丢失


## QoS1

引入重传机制

接收端必须对每个发送进行响应

若没有收到响应，发送端会重传消息

为了实现重传机制，会使用字段 Packet ID , DUP

QoS1 导致消息重复，只能同个业务进行去重，比如给消息增加时间戳或递增的计数

涉及报文

PUBLISH

PUBACK

## QoS2

涉及报文

PUBLISH

PUBREC (PUBLISH recevie) : 接收到了PUBLISH报文

PUBREL (PUBLISH release) : 释放了PUBLISH报文

PUBCOMP (PUBLISH complate) : 这一次的消息发布即将完成


sender ---- PUBLISH PacketID(10) DUP(0)----> recevier |            新消息
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息          
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息
                                                      |
    PUBREC 之前 sender可以发送重复报文                |
                                                      |
sender <--- PUBREC PacketID(10) ------------ recevier |
                                                      |
sender ---- PUBREL PacketID(10) -----------> recevier ------------ recevier以PUBREL为界限, 
                                                      |            PUBREL之前收到的消息都当成重复的消息(一个消息)
    PacketID(10)  释放中                              |            之后收到的消息才是新消息
    sender 既不能重传也不能发送新的信息               |
                                                      |
sender <--- PUBCOMP PacketID(10) ------------ recevier|
                                                      |
    可以发布新的信息                                  |
                                                      |
sender ---- PUBLISH PacketID(10) DUP(0)----> recevier |            新消息

合适分发QoS2消息

由于sender发送的消息必须在收到PUBCOMP后,导致影响实时性，所以recevier应该尽快分发消息，即在第一次收到PUBLISH时就分发消息

sender ---- PUBLISH PacketID(10) DUP(0)----> recevier |            新消息   : 向后分发
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息 : 忽略
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息 : 忽略
sender ---- PUBLISH PacketID(10) DUP(1)----> recevier |            重复消息 : 忽略
                                                      |
    PUBREC 之前 sender可以发送重复报文                |
                                                      |
sender <--- PUBREC PacketID(10) ------------ recevier |
                                                      |
sender ---- PUBREL PacketID(10) -----------> recevier ------------ recevier以PUBREL为界限, 
                                                      |            PUBREL之前收到的消息都当成重复的消息(一个消息)
    PacketID(10)  释放中                              |            之后收到的消息才是新消息
    sender 既不能重传也不能发送新的信息               |
                                                      |
sender <--- PUBCOMP PacketID(10) ------------ recevier|
                                                      |
    可以发布新的信息                                  |
                                                      |
sender ---- PUBLISH PacketID(10) DUP(0)----> recevier |            新消息  : 向后分发




对于QoS1 QoS2都有重传，何时重传未收到响应的响应?

在tcp未断开时，tcp负责重传，在tcp负责重传时进行消息重传是没有好处的，

所以mqtt定义，QoS1 QoS2的消息重传必须在上次tcp连接断开后，进行新的tcp连接，并重传上次未响应的消息.

## 不同QoS的应用场景 

QoS0 ：传输不重要可丢失的数据，如传感器
QoS1 ：传输可重复的数据,或应用完成了去重
QoS2 ：传输重要数据 


# 保留消息
## 为什么需要保留消息
没有保留消息时，订阅者若后启动，是无法收到发布者的消息。

## 保留消息的构成
PUBLISH
 Retain    1
 TopicName demo
 Qos       0
 payload   hello

## 不属于会话
保留消息不属于会话，即使发布端下线，保留消息依旧会存储在Broker.

若要删除保留消息需要发布一个同TopicName的普通消息（Retain 为 0）

PUBLISH
 Retain    0
 TopicName demo
 Qos       2
 payload   null

需要注意的是，这个普通消息的payload通常为null，而普通消息也会转发给订阅者，所以需要确保订阅者不会把此消息视为错误 

## message expiry interval
mqtt5支持给保留消息设置过期时间

PUBLISH
 Retain    1
 TopicName demo
 Qos       0
 payload   hello
 message expiry interval  5000s

## Retain As Published

默认情况下，Broker转发保留消息，Retain会被修改为0，若接收者是订阅者，这没有问题

但是，接收者是Broker ，则会导致 业务希望桥接保留消息，实际桥接得到普通消息。

若希望桥Broker也收到保留消息，这需要使用 Retain As Published 

PUBLISH
 Retain    1
 TopicName demo
 Qos       0
 payload   hello
 Retain As Published 1

## Retain Handling

Retain Handling = 0
订阅建立时发送保留消息

Retain Handling = 1
订阅建立时，若该订阅当前不存在则发送保留消息

Retain Handling = 0
订阅建立时不发送保留消息

## 保留消息容易重复

保留消息在订阅者订阅前发布
                                                | <- Retain 1  payload(hello)
client ---- Connect and SUBSCRIBE------> server |            
client <--- Retain 1 payload(hello) ---- server | 订阅建立时，转发保留消息
                 .....
client ---- Connect and SUBSCRIBE------> server | 由于网络波动，订阅者断开连接后重新订阅
client <--- Retain 1 payload(hello) ---- server | 订阅建立时，转发保留消息，保留消息未改变，订阅者收到重复消息


保留消息在订阅者订阅后发布

client ---- Connect and SUBSCRIBE------> server |            
                                                | <- Retain 1  payload(hello)
client <--- Retain 0 payload(hello) ---- server | 订阅建立时，转发普通消息
                 .....
client ---- Connect and SUBSCRIBE------> server | 由于网络波动，订阅者断开连接后重新订阅
client <--- Retain 1 payload(hello) ---- server | 订阅建立时，转发保留消息，保留消息未改变，订阅者收到重复消息

如果消息内容是可重复的，如数据采集，则重复的保留消息没有副作用。

但消息若不可重复，如金额消费，则会导致业务异常。

重复的保留消息无法通过删除消息解决，因为有别的订阅者需要此保留消息。

所以只能通过业务解决：常用方法是给保留消息一个生成时间戳，订阅者收到重复TopicName的保留消息时，需要根据时间错判断是否是重复的消息。


## 保留消息减少设备发布次数
利用保留消息，只需要在数据改变时，才发布


# 遗嘱消息
## 为什么要遗嘱消息
由于Broker的存在，订阅者无法知道对端的情况，所以需要遗嘱消息，让发布者意外断线时有发布遗嘱的能力

## 如何设置遗嘱消息

client在连接时可以指定遗嘱消息

CONNECT
    ClientID                123
    CleanStart              true
    Will Topic              will
    Will QoS                0
    Will Retain             false
    Will Properties
        Will Delay interval 300s
    Will payload I          died

## 客户端异常断开的情况
1. 服务端检测到IO故障或网络故障
2. 客户端在keepalive时间内未能通信
3. 客户端在没有发送Reason code 为0的DISCONNECT报文的情况下关闭了网络
4. 服务端在没有收到DISCONNECT报文的情况下主动关闭了网络

## Will Delay interval
mqtt3中没有此字段，当服务端检测到客户端异常断开后，会立即发送遗嘱给订阅者

mqtt5中有此字段，当服务端检测到客户端异常断开后，会等待一段时间，若连接依旧没有恢复，则发送遗嘱

## 遗嘱消息和会话
遗嘱消息是会话的一部分，所以即使 
Will Delay interval > Session expiry interval
但当会话超时，遗嘱消息也会被视为超时而被发送

这是很有用的，因为当使用持久会话时，会话的超时才是业务连接的断开，所以可以故意将 Will Delay interval 设置为大于 session expiry interval 。
并在client发送DISCONNECT时，Reason code设置为 0x04 , 这表示client是正常断开连接，但仍然希望server发送遗嘱消息

## 遗嘱消息和保留消息

遗嘱消息一旦被转发，server就会删除对应的遗嘱消息，但无法保证订阅者一定在线。

为了确保所有的订阅者可以收到遗嘱消息，可以使用 Will Retain字段，将遗嘱消息设置为保留消息。

如此订阅了相关Topic的client，无论何时上线都能收到该Topic发布方离线通知

## 场景用法

client(发布方)
连接时设置遗嘱
    CONNECT
        ClientID      a
        Will Topic    client/a/status
        Will Retain   true
        Will payload  i'm offline

当连接成功,发送保留消息
    PUBLISH
        ClientID      a
        Topic         client/a/status
        Retain        true
        payload       i'm online

client(订阅方)
    SUBSCRIBE
        Topic        client/a/status



# mqtt Broker 的使用
## mosquitto

mosquitto [-c config file] [-d | --daemon] [-p port number] [-v]

mosquitto is a broker for the MQTT protocol version 5.0/3.1.1/3.1.


OPTIONS
       -c, --config-file
           Load configuration from a file. If not given, then the broker will listen on port 1883 bound to the loopback interface, and the default values as described
           in mosquitto.conf(5) are used.

               Important
               See the -p option for a description of changes in behaviour from 1.6.x to 2.0.

       -d, --daemon
           Run mosquitto in the background as a daemon. All other behaviour remains the same.

       -p, --port
            监听指定的端口。可以指定多达10次，以打开多个监听不同端口的套接字。

