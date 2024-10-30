
# 网络结构
CWMP网络元素主要有：
- ACS：自动配置服务器，网络中的管理设备。
- CPE：用户端设备，网络中的被管理设备。
- DNS server：域名服务器。CWMP协议规定ACS和CPE使用URL地址来互相识别和访问，DNS用于帮助解析URL参数。
- DHCP server：动态主机配置协议服务器。给ACS和CPE分配IP地址，使用DHCP报文中的option字段给CPE配置参数。

# CWMP的方法
ACS对CPE的管理和监控是通过一系列的操作来实现的，这些操作在CWMP协议里称为RPC方法。主要方法的描述如下：
- Get：ACS使用该方法可以获取CPE上参数的值。
- Set：ACS使用该方法可以设置CPE上参数的值。
- Inform：当CPE与ACS建立连接时，或者底层配置发生改变时，或者CPE周期性发送本地信息到ACS时，CPE都要通过该方法向ACS发起通告信息。
- Download：为了保证CPE端硬件的升级以及厂商配置文件的自动下载，ACS使用该方法可以要求CPE到指定的URL下载指定的文件来更新CPE的本地文件。
- Upload：为了方便ACS对CPE端的管理，ACS使用该方法可以要求CPE将指定的文件上传到ACS指定的位置。
- Reboot：当CPE故障或者需要软件升级的时候，ACS使用该方法可以对CPE进行远程重启

# 实例

场景如下：区域内有主、备两台ACS，主ACS系统升级，需要重启。为了连续监控，主ACS需要将区域内的CPE都连接到备用ACS上，处理流程如下：

CPE ------------ TCP               -----------> ACS
建立TCP连接。

CPE ------------ SSL               -----------> ACS
SSL初始化，建立安全机制。

CPE ------------ HTTP post(Inform) -----------> ACS
CPE发送Inform报文，开始建立CWMP连接。Inform报文使用Eventcode字段描述发送Inform报文的原因，该举例为“6 CONNECTION REQUEST”，表示ACS要求建立连接。

CPE <------------ HTTP response(Inform response) ----------- ACS
如果CPE通过ACS的认证，ACS将返回Inform响应报文，连接建立。

CPE ------------ HTTP post(empty) -----------> ACS
如果CPE没有别的请求，就会发送一个空报文，以满足HTTP报文请求/响应报文交互规则（CWMP是基于HTTP协议的，CWMP报文作为HTTP报文的数据部分封装在HTTP报文中）。

CPE <------------ HTTP response(GetParameterValues request) ----------- ACS
ACS查询CPE上设置的ACS URL的值。

CPE ------------ HTTP post(GetParameterValues response) -----------> ACS
CPE把获取到的ACS URL的值回复给ACS。

CPE <------------ HTTP response(SetParameterValues request) ----------- ACS
ACS发现CPE的ACS URL是本机URL的值，于是发起Set请求，要求将CPE的ACS URL设置为备用ACS的URL的值。

CPE ------------ HTTP post(SetParameterValues response) -----------> ACS
设置成功，CPE发送响应报文。

CPE <------------ HTTP response(empty) ----------- ACS
ACS发送空报文通知CPE没有别的请求了。

CPE ------------ Close               -----------> ACS
CPE关闭连接。

CPE将向备用ACS发起连接。



