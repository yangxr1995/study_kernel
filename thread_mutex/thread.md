# 原子操作 

## 什么是原子操作

源代码中一条语句，即使是汇编代码，经过cpu解码后，实际执行的是多条代码，当多个cpu并发执行时，语义就可能异常，

比如 ++i，一条语句，cpu会分为三个步骤完成。

1. 加载i的值到寄存器

2. 增加寄存器中i的值

3. 根据寄存器中的值写回到i的内存

若两个线程同时执行++i，当线程1修改i内存前，线程2开始++i的工作时，语义就错误。

为了解决这个问题，硬件必须提供指令隔离两个操作，这就是原子指令。

当使用原子指令执行 ++i，

CPU1开始执行时，会让其他CPU对i的操作暂停

可见原子操作本质上是最小粒度的自旋锁

# 缓存一致性

CPU直接操作内存的是自己的缓存，在SMP场景下，内存中的变量i，会在每个CPU缓存中有一个副本。

当一个CPU修改i时，需要将i的修改值同步给其他CPU缓存，

这是由硬件实现的，当进行同步时，其他CPU的工作也会被暂停。

为了避免缓存一致性导致的性能损耗，高性能程序会使用per cpu解决

# 内存屏障

## 硬件基础

![](./pic/4.jpg)

### cache

cache是一定大小的高速内存，并使用硬件实现哈希表，根据目标地址求哈希获得操作的位置

cache未命中是软件开发者要关注

### 写操作缓存

当cpu进行写操作时，若发生cache未命中，通常cpu需要等待加载，但现代cpu增加了写操作缓存，将未执行的写操作记录到写操作缓存中，cpu便可以继续执行，

当变量加载到cache后，变量的值将根据写操作缓存的内容被立即覆盖。

![](./pic/5.jpg)

### 消息队列

在SMP场景下，同一个变量，每个cpu的cache中一个变量的副本.

为保持cache中变量的同步，使用MESI协议，

比如当某个cpu0执行a = 1后，cpu0不仅会修改自己a的值，还会发送"使a无效"消息，

消息会存放到消息队列，当cpu1有空时，会处理消息，如读到 "使a无效" 消息，则会将缓存a标记为无效。

当cpu1读取a时，由于缓存无效，会发送 "读a" 消息，并从cpu1中获得a的最新值.

## 为什么需要内存屏障

在SMP多线程环境下，很容易出现cache中变量未及时同步的问题，所以需要内存屏障

### 为什么会有cache变量未及时同步

cpu0
    a = 1;
    b = 1;

cpu1
    while (b == 0) continue;
    assert(a == 1);

有如上代码，并假设 cpu0 cache已缓存b，cpu1 cache已缓存a

1. cpu0 : a = 1; 缓存未命中，a=1操作存放到写缓存，并发送 "读使无效" 消息

2. cpu1 : while(b == 0) 缓存未命中，发送 "读"消息

3. cpu0 : b = 1; 缓存命中，修改缓存中b的值

4. cpu0 : 处理 "读b" 消息，发送响应

5. cpu1 : while(b == 0) 缓存命中，且b为 1，退出循环

6. cpu1 : assert(a == 1) ，a为0，触发错误

7. cpu1 ：处理 "读使无效"，将 a标记为无效，并回复响应

可见导致异常的原因为
1. cpu0并没有确认执行完 a = 1，而是将a = 1放到写操作缓存，然后就执行b=1，完成了b的更新，而a的更新被延后了
2. cpu1没有及时处理 "使a无效" 的消息，可能在执行完 assert(a == 1)后再处理消息

简单说就是 使无效队列 或 写操作缓冲区 没有及时处理

## smp_mb

cpu0
    a = 1;
    smp_mb(); 
    b = 1;

cpu1
    while (b == 0) continue;
    smp_mb(); 
    assert(a == 1);

1. cpu0 : a = 1; 缓存未命中，a=1操作存放到写缓存，并发送 "读a使a无效" 消息

2. cpu1 : while(b == 0) 缓存未命中，发送 "读b"消息

3. cpu0 : smp_mb(); 读写内存屏障，标记 使无效队列 和 写操作缓存区

4. cpu0 : b = 1; 缓存命中，由于标记了 写操作缓存区，写操作缓冲区中已有操作必须先执行，所以将 b = 1的操作存入写操作缓存，并发送 "使b无效"

5. cpu1 : 处理 "读a" 消息，发送响应

6. cpu0 : 处理响应消息，缓存中写入a = 0

7. cpu0 : 由于缓存中a存在，执行 写操作缓存 a = 1，b = 1

8. cpu0 : 发送 "读b" 消息的响应

9. cpu1 : while(b == 0) 退出循环

10. cpu1 : smp_mb(), 读写内存屏障，标记 使无效队列 和 写操作缓存区

11. cpu1 : 由于标记了 使无效队列，必须处理完消息队列中的 "使无效" 消息，所以标记a无效

12. cpu1 : 发送 "读a" 消息

13. cpu0 : 响应 "读a"

14. cpu1 : 程序正常


## 更小粒度的内存屏障

很多CPU体系结构提供更弱的内存屏障指令，这些指令仅仅做其中一项或者几项工作。

不准确的说，

读内存屏障 : 仅仅标记它的使无效队列

写内存屏障 : 仅仅标记它的存储缓冲区

完整的内存屏障 : 同时标记无效队列及存储缓冲区。

这样的效果是，

读内存屏障仅仅保证执行该指令的CPU上面的装载顺序，因此所有在读内存屏障之前的装载，将在所有随后的装载前完成。

写内存屏障仅仅保证写之间的顺序，所有在内存屏障之前的存储操作，将在其后的存储操作完成之前完成。

完整的内存屏障同时保证写和读之间的顺序，这也仅仅针对执行该内存屏障的CPU来说的。


cpu0
    a = 1;
    smp_wmb(); 
    b = 1;

cpu1
    while (b == 0) continue;
    smp_rmb(); 
    assert(a == 1);

# 多线程和编译器优化导致的bug

编译器的视角是局部单线程的，所以对于栈上的数据，编译器能较好的理解语义，并优化代码，

但对于堆上和静态数据，编译器只能片面的理解语义，特别是无法考虑中断，多线程的情况，

有些代码是需要结合多处语句，才能得到正确语义，这导致编译器无法理解这些语句存在的意义，进行代码优化，最终导致程序异常。

要解决这个问题，需要用 volatile 。

## XXX_ONCE

XXX_ONCE 是对volatile 局部使用的封装

```c
#define ACCESS_ONCE(x) (*(volatile typeof(x) *)&(x))
#define READ_ONCE(x) \
                ({ typeof(x) ___x = ACCESS_ONCE(x); ___x; })
#define WRITE_ONCE(x, val) \
                do { ACCESS_ONCE(x) = (val); } while (0)
```

下面示例说明其作用

比如下面的场景
```c
static int should_continue;
static void do_something(void);

while (should_continue)
do_something();
```

若do_something中没有修改should_continue，则编译器可以优化代码为

```c
if (should_continue)
for (;;)
do_something();
```

再单线程中没有问题，但若是多线程环境，另一个线程修改了should_continue，则程序语义完全改变。

正确的做法是
```c
static int should_continue;
static void do_something(void);

while (READ_ONCE(should_continue))
do_something();
```

再比如

```c
p = global_ptr;
if (p && p->s && p->s->func)
p->s->func();
```

编译器可以优化为

```c
if (global_ptr && global_ptr->s && global_ptr->s->func)
global_ptr->s->func();
```

可是另一个线程修改global_ptr为NULL，则会导致段错误

正确的做法是

```c
p = READ_ONCE(global_ptr);
if (p && p->s && p->s->func)
p->s->func();
```

再比如

```c
for (;;) {
still_working = 1;
do_something();
}
```

建设do_something的实现是可见的，且没有修改still_working，则编译器会优化代码为

```c
still_working = 1;
for (;;) {
do_something();
}
```

若其他线程执行了

```c
for (;;) {
still_working = 0;
sleep(10);
if (!still_working)
panic();
}
```

则会导致其他线程panic

正确的做法为

```c
for (;;) {
WRITE_ONCE(still_working, 1);
do_something();
}
```
## atomic_xxx 是否还需要 volatile

原子变量不需要volatile，因为编译器不会优化原子变量的相关操作

比如下面的代码

```c
void func1()
{
    atomic_uint a;
    atomic_init(&a, 1);

    atomic_store(&a, 2);
}

void func2()
{
    unsigned int a = 1;
    a = 2;
}
```

arm-linux-gcc -O2

```asm
func1:
        sub     sp, sp, #16
        mov     w1, 1
        add     x0, sp, 12
        str     w1, [x0]
        mov     w1, 2
        stlr    w1, [x0]
        add     sp, sp, 16
        ret
func2:
        ret
```

如果func2使用XXX_ONCE

```c
void func2()
{
    unsigned int a;
    WRITE_ONCE(a, 1);
    WRITE_ONCE(a, 2);
}
```

```asm
func1:
        sub     sp, sp, #16
        mov     w1, 1
        add     x0, sp, 12
        str     w1, [x0]
        mov     w1, 2
        stlr    w1, [x0]
        add     sp, sp, 16
        ret
func2:
        sub     sp, sp, #16
        mov     w0, 1
        str     w0, [sp, 12]
        mov     w0, 2
        str     w0, [sp, 12]
        add     sp, sp, 16
        ret
```

## 原子变量和 volatile 的对比

原子变量相当于volatile的升级版，不仅不会被gcc优化，而且使用原子指令

volatile 虽然使用一般指令，但是由于原子指令会导致cpu性能下降，所以当对数据的更新值获取不严格时，可以使用volatile


# 工具
## gcc 对thread的支持
### per thread

使用 __thread 修饰的符号会被编译为per thread

int __thread a;
void *do_work()
{
    ++a; // a 全部是1
    return NULL;
}




