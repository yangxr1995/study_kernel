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

我们简单的认为代码的执行顺序是源代码的编写顺序，但实际上编译器和CPU为了提供效率，可能对顺序进行调整。

对于编译器可以查看反汇编，获知真实的执行顺序，

对于CPU，程序员却无法获悉实际的执行顺序，因为代码的执行分为取指，译码，执行，CPU会同时加载多条指令，同时进行上述操作，谁最先完成译码，谁最先执行，

这导致执行顺序是无法准确预测的，这种特性在多线程场景下可能导致语义异常，为此硬件提供了内存屏障，屏障前的指令必须在屏障后的指令之前执行。

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




