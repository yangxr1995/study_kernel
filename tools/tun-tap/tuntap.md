# 介绍

Tun/tap 接口是由 Linux 提供的一项功能（可能也被其他类 UNIX 操作系统支持），它可以实现用户空间网络，

即让用户空间程序能够查看原始网络流量（以太网或 IP 层级）并自行处理。本文尝试解释在 Linux 下 tun/tap 接口的工作原理，并提供一些示例代码来演示它们的用法。

# 工作原理

## 发送和接受
Tun/tap 接口是仅存在于内核中的软件接口，意味着与常规网络接口不同，它们没有物理硬件组件（因此没有物理的“连接线”与其相连）。

您可以将 tun/tap 接口视为一个常规网络接口，当内核决定发送数据“到网络”时，实际上是将数据发送到连接到该接口的某个用户空间程序（使用特定过程，见下文）。

当程序连接到 tun/tap 接口时，它会获得一个特殊的文件描述符，从中读取数据将得到接口正在发送的数据。

同样地，程序也可以向这个特殊描述符写入数据，这些数据（必须被正确格式化，如下所示）将被看作是 tun/tap 接口的输入。

对于内核而言，看起来就好像 tun/tap 接口正在接收来自“网络”的数据。


## tun 和 tap 的区别

tap 接口和 tun 接口之间的差异在于 tap 接口输出（并必须给定）完整的以太网帧，而 tun 接口输出（并必须给定）原始 IP 数据包（内核不会添加以太网标头）。

在创建接口时，指定接口是像 tun 接口一样工作还是像 tap 接口一样工作是有一个标志来区分的。

## 如何使用

接口可以是瞬态的，这意味着它由同一程序创建、使用并销毁；当程序终止时，即使它没有显式地销毁接口，接口也会停止存在。

另一种选项（我更喜欢的选项）是将接口设置为持久的；在这种情况下，可以使用专用实用程序（如 tunctl 或 openvpn --mktun）创建接口，然后正常程序可以连接到它；

当它们连接时，必须使用与最初创建接口时相同类型（tun 或 tap），否则它们将无法连接。我们将在代码中看到如何实现这一点。

一旦建立了一个 tun/tap 接口，它可以像任何其他接口一样使用，这意味着可以分配 IP 地址、分析流量、创建防火墙规则、建立指向它的路由等。

有了这些知识，让我们尝试看看如何使用 tun/tap 接口以及可以对其执行哪些操作。


# 创建接口 

创建一个全新接口或重新连接到一个持久接口的代码基本上是相同的；不同之处在于前者必须由 root 运行（更准确地说，必须由具有 CAP_NET_ADMIN 权限的用户运行），

而后者可以由普通用户运行，如果满足一定条件的话。让我们从创建一个新接口开始。

首先，无论你做什么，设备 /dev/net/tun 必须以读/写方式打开。该设备也称为克隆设备，因为它用作创建任何 tun/tap 虚拟接口的起点。

操作（与任何 open() 调用一样）会返回一个文件描述符。但这仅仅是不足以开始使用它与接口进行通信的。

创建接口的下一步是发出一个特殊的 ioctl() 系统调用，它的参数是前一步获得的描述符、TUNSETIFF 常量和一个指向包含描述虚拟接口参数的数据结构的指针

（基本上是接口的名称和所需的操作模式 - tun 或 tap）。做为一个变种，虚拟接口的名称可以不指定，在这种情况下，

内核会尝试通过分配相同类型的“下一个”设备来选择名称（例如，如果 tap2 已经存在，内核将尝试分配 tap3，依此类推）。

所有这些必须由 root（或具有 CAP_NET_ADMIN 权限的用户）执行（在我说“必须由 root 执行”时，假设这适用于所有情况）。

如果 ioctl() 调用成功，虚拟接口就会被创建，并且先前获得的文件描述符现在与其关联，并可用于通信。

在这一点上，有两种情况可能发生。程序可以立即开始使用接口（可能在之前至少配置一个IP地址），当完成后终止并销毁该接口。

另一种选择是发出另外几个特殊的 ioctl() 调用，使接口变为持久，然后终止，使其保留在那里供其他程序连接。

例如，像 tunctl 或 openvpn --mktun 这样的程序就是这样做的。这些程序通常也可以选择将虚拟接口的所有权设置为非 root 用户和/或组，

以便以非 root 用户但具有适当权限的程序可以稍后连接到接口。我们将在下面继续讨论这一点。

```
#include <linux /if.h>
#include <linux /if_tun.h>

int tun_alloc(char *dev, int flags) {

  struct ifreq ifr;
  int fd, err;
  char *clonedev = "/dev/net/tun";

  /* Arguments taken by the function:
   *
   * char *dev: the name of an interface (or '\0'). MUST have enough
   *   space to hold the interface name if '\0' is passed
   * int flags: interface flags (eg, IFF_TUN etc.)
   */

   /* open the clone device */
   if( (fd = open(clonedev, O_RDWR)) < 0 ) {
     return fd;
   }

   /* preparation of the struct ifr, of type "struct ifreq" */
   memset(&ifr, 0, sizeof(ifr));

   ifr.ifr_flags = flags;   /* IFF_TUN or IFF_TAP, plus maybe IFF_NO_PI */

   if (*dev) {
     /* if a device name was specified, put it in the structure; otherwise,
      * the kernel will try to allocate the "next" device of the
      * specified type */
     strncpy(ifr.ifr_name, dev, IFNAMSIZ);
   }

   /* try to create the device */
   if( (err = ioctl(fd, TUNSETIFF, (void *) &ifr)) < 0 ) {
     close(fd);
     return err;
   }

  /* if the operation was successful, write back the name of the
   * interface to the variable "dev", so the caller can know
   * it. Note that the caller MUST reserve space in *dev (see calling
   * code below) */
  strcpy(dev, ifr.ifr_name);

  /* this is the special file descriptor that the caller will use to talk
   * with the virtual interface */
  return fd;
}
```

函数tun_alloc()接受两个参数：

1. `char *dev` 包含接口的名称（例如，tap0，tun2等）。可以使用任何名称，但最好选择一个能表明接口类型的名称。

实际上，通常会使用类似tunX或tapX的名称。如果`*dev`为'\0'，内核将尝试创建请求类型的“第一个”可用接口（例如，tap0，但如果该接口已存在，则为tap1等）。

2. int flags 包含告知内核我们需要哪种类型接口（tun或tap）的标志。

基本上，它可以取值IFF_TUN以指示TUN设备（数据包中没有以太网头部），或者取值IFF_TAP以指示TAP设备（数据包中包含以太网头部）。

此外，还可以使用另一个标志IFF_NO_PI与基本数值进行OR操作。IFF_NO_PI告诉内核不提供数据包信息。

IFF_NO_PI的目的是告知内核数据包将是“纯”IP数据包，而无附加字节。

否则（如果IFF_NO_PI未设置），每个数据包的开头将添加额外的4个字节（2个标志字节和2个协议字节）。

IFF_NO_PI在接口创建和重新连接时不需要匹配。此外，需要注意的是，使用Wireshark捕获接口流量时，这4个字节是不会显示的。

```
  char tun_name[IFNAMSIZ];
  char tap_name[IFNAMSIZ];
  char *a_name;

  ...

  strcpy(tun_name, "tun1");
  tunfd = tun_alloc(tun_name, IFF_TUN);  /* tun interface */

  strcpy(tap_name, "tap44");
  tapfd = tun_alloc(tap_name, IFF_TAP);  /* tap interface */

  a_name = malloc(IFNAMSIZ);
  a_name[0]='\0';
  tapfd = tun_alloc(a_name, IFF_TAP);    /* let the kernel pick a name */
```

此时，正如之前所述，程序可以直接使用接口来完成其任务，或者可以将其设置为持久化（并可选择将其所有权赋予特定用户/组）。

如果选择前者，就没有太多需要说明的了。但如果选择后者，以下是会发生的事情。

有两个额外的ioctl()可用，通常一起使用。第一个系统调用可以在接口上设置（或移除）持久化状态。第二个允许将接口的所有权分配给普通（非root）用户。

这两个功能在程序tunctl（UML实用程序的一部分）和openvpn --mktun（以及可能其他程序）中实现。

让我们看一下tunctl的代码，因为它更简单，要记住它只创建tap接口，因为用户模式Linux使用的就是这种接口（为了清晰起见，稍作编辑和简化代码）:


```
...
  /* "delete" is set if the user wants to delete (ie, make nonpersistent)
     an existing interface; otherwise, the user is creating a new
     interface */
  if(delete) {
    /* remove persistent status */
    if(ioctl(tap_fd, TUNSETPERSIST, 0) < 0){
      perror("disabling TUNSETPERSIST");
      exit(1);
    }
    printf("Set '%s' nonpersistent\n", ifr.ifr_name);
  }
  else {
    /* emulate behaviour prior to TUNSETGROUP */
    if(owner == -1 && group == -1) {
      owner = geteuid();
    }

    if(owner != -1) {
      if(ioctl(tap_fd, TUNSETOWNER, owner) < 0){
        perror("TUNSETOWNER");
        exit(1);
      }
    }
    if(group != -1) {
      if(ioctl(tap_fd, TUNSETGROUP, group) < 0){
        perror("TUNSETGROUP");
        exit(1);
      }
    }

    if(ioctl(tap_fd, TUNSETPERSIST, 1) < 0){
      perror("enabling TUNSETPERSIST");
      exit(1);
    }

    if(brief)
      printf("%s\n", ifr.ifr_name);
    else {
      printf("Set '%s' persistent and owned by", ifr.ifr_name);
      if(owner != -1)
          printf(" uid %d", owner);
      if(group != -1)
          printf(" gid %d", group);
      printf("\n");
    }
  }
  ...
```

这些额外的ioctl()仍然必须由root用户运行。但现在我们拥有一个归属于特定用户的持久化接口，因此以该用户身份运行的进程可以成功连接到它。

正如之前所述，事实证明重新连接到现有的tun/tap接口的代码与用于创建接口的代码是相同的；换句话说，可以再次使用tun_alloc()。在这样做时，为了成功，必须做到以下三点：

1. 接口必须已经存在，并且归属于试图连接的相同用户（很可能是持久化的）

2. 用户必须对/dev/net/tun具有读写权限

3. 提供的标志必须与用于创建接口的标志匹配（例如，如果是使用IFF_TUN创建的，则重新连接时必须使用相同的标志）

这种情况是可能的，因为内核允许在发出该请求的用户指定已存在接口的名称且是该接口的所有者时，TUNSETIFF ioctl()会成功。

在这种情况下，无需创建新接口，因此普通用户可以成功执行此操作。

因此，这是一种尝试解释当调用ioctl(TUNSETIFF)时发生的情况，以及内核如何区分请求分配新接口和请求连接到现有接口之间的方式：

1. 如果指定了不存在的或没有接口名称，这意味着用户正在请求分配新接口。因此，内核将使用给定名称创建一个新接口（如果提供了空名称，则选择下一个可用名称）。
这仅当由root执行时才有效。

2. 如果指定了现有接口的名称，则表示用户希望连接到先前分配的接口。这可以由普通用户执行，前提是：用户在克隆设备上具有适当的权限，并且是接口的所有者（在创建时设置），
且指定的模式（tun或tap）与创建时设置的模式匹配。


您可以查看内核源代码中drivers/net/tun.c文件中实现上述步骤的代码；关键函数包括tun_attach()、tun_net_init()、tun_set_iff()、tun_chr_ioctl()；
最后一个函数还实现了各种可用的ioctl()，包括TUNSETIFF、TUNSETPERSIST、TUNSETOWNER、TUNSETGROUP等等。

无论如何，不允许非root用户配置接口（即分配IP地址并激活接口），但这对于任何常规接口也是适用的。如果非root用户需要执行需要root权限的某些操作，
可以使用常规的方法（如suid二进制包装器、sudo等）。

这是一个可能的使用场景（我经常使用的一种）：

1. 虚拟接口由root创建，设置为持久化，分配给用户，并由root进行配置（例如，通过在启动时使用tunctl或等效工具的init脚本）。

2. 然后普通用户可以随时attach和detach他们拥有的虚拟接口。

3. 虚拟接口由root销毁，例如在关机时运行的脚本中，也许使用tunctl -d或等效工具。

# 尝试使用
在这个详尽的介绍之后，现在是时候继续进行实际操作了。由于这是一个标准接口，您可以像对待其他常规接口一样处理它。
对于我们的目的，tun和tap接口之间没有区别；重要的是创建或连接到它的程序必须知道它的类型，并相应地处理数据。

让我们创建一个持久化接口并为其分配一个IP地址：

```
# openvpn --mktun --dev tun2
Fri Mar 26 10:29:29 2010 TUN/TAP device tun2 opened
Fri Mar 26 10:29:29 2010 Persist state set to: ON
# ip link set tun2 up
# ip addr add 10.0.0.1/24 dev tun2
```

让我们启动一个网络分析器，看看数据流量：

```
# tshark -i tun2
Running as user "root" and group "root". This could be dangerous.
Capturing on tun2

# On another console
# ping 10.0.0.1
PING 10.0.0.1 (10.0.0.1) 56(84) bytes of data.
64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=0.115 ms
64 bytes from 10.0.0.1: icmp_seq=2 ttl=64 time=0.105 ms
...
```


