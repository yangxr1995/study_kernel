# 查看和修改
info args   查看函数参数
info locals 查看局部变量
print 变量名
set print null-stop
set print pretty
set print array on
gdb内嵌函数 : sizeof() strlen() strcmp()

x /选项 内存地址
x /s str
x /b  变量内存地址
x /4b 变量内存地址

p test.age=20
set var test.age=20

查看所有寄存器
info registers
查看指定寄存器
info registers rdi

p $pc=xxx
set var $pc=xxx

获得code地址
info line 16

# 设置源码目录
-g 只是加文件名和行和函数名记录到elf文件，即只是携带源文件索引，源文件有gdb会自动添加
查找源代码的目录
show directories
默认源代码的是当前目录和程序工作目录

添加源文件搜索目录
directories path

# 栈
bt 查看栈回溯信息
frame n 切换栈帧
info f n 查看栈帧信息

# 观察点
watch 写观察点    
rwatch 读观察点
awatch 读写观察点
info watch
delete/disable/enable 删除/禁用/启用观察点

watch var thread 2 只对2号线程设置观察点

watch var1 + var2 > 10 当表达式成立时，暂停程序

# 捕获点
当指定异常抛出时，暂停程序
catch event

catch assert
catch exec
catch fork
catch signal
catch syscall number
catch throw

# 断点
设置断点执行操作
commands 断点号
printf "prev node is %p" cur
p *prev
end

保存断点
save breakpoints file
加载文件
source file

# 查看类型信息 
查看变量的类型
whatis var
查看函数原型
whatis func
查看对象方法的原型
whatis var.func

ptype /r /o /m /t
查看对象的类型的详细原型，包括成员属性和方法
ptype var
查看对象的类型的详细原型，只看属性
ptype /m var
开启继承分析
set print object on

查看成员的内存布局
ptype /o var

不显示typedef
ptype /t var

搜索变量count的定义
i var count

# 线程
info threads 查看所有线程
thread find 查找线程
thread num 切换线程
thread name 设置线程名字
break thread id 为线程设置断点

thread apply id cmd 为线程执行命令
thread apply 2 bt  查看2号线程的调用栈
thread apply 1 2 2 bt  查看1,2,3号线程的调用栈

set scheduler-locking off|on|step 锁定线程

set print thread-event off|on 是否打印创建线程和线程退出的事件

# shell
执行shell命令
shell  cat file
!cat file

# 日志
set logging on/off  启用日志输出
set logging file filename 修改日志名称
set logging overwrite  默认追加，启用覆盖写

# 跳转执行
根据参数,修改pc寄存器

jump 行号
jump label

# 反向执行
撤销对内存和寄存器数据的修改

首先执行 record
然后正常单步调试 n
反向单步执行 rn
       
反向执行函数 reverse-finish
其他反向执行指令
rs
rc

record-stop

# 父子进程
set follow-fork-mode parent/child

查看当前调试进程的进程号
cat (int)getpid()

调试多个进程
set detach-on-fork off/on
默认detach-on-fork 是on，导致跟随子进程时，父进程会执行到退出，
所以将其改为 off,
并设置子进程和父进程的断点，并开启调试子进程

查看当前多个进程
info inferiors

inferiors 1
切换到1号父进程


# 同时调试多进程
info inferiors
add inferiors 
attach 2314
bt
inferiors 2
attach 2341

设置所有 inferiors 的进程可同时执行
默认只有当前进程可以执行
set scheduler-multiple on|off

detach inferiors 2

remove-inferiors 2


# call
调用函数，包括 C库函数，

p 表达式
求表达式的值，并显示结果，表达式可以是程序中的函数的调用，即使返回void，也会显示

call 表达式 
求表达式的值，并显示结果，表达式可以是程序中的函数的调用，若返回void，不显示

# skip
某些函数单步调试时不希望被调试
skip function
skip test_c::get_number()

test.cpp内所有函数都被跳过
skip file filename
skip file test.cpp

将common下所有文件的函数都跳过 
skip -gfi 通配符
skip -gfi common/*.*

# 调试发行版
制作release版

方法1：修改Makefile，编译出带g和不带g的版本
方法1：不修改Makefile，编译出带g的版本，使用strip生成不带g的版本 

gdb调试release版

方法1：
gdb --symbol=被调试的debug版本--exec=被调试的release版本

方法2：

生成符号文件
objcopy --only-keep-debug debug-elf debug.sym
gdb --symbol=debug.sym --exec=被调试的release版本

# 检查内存泄漏
malloc_stats() 是 malloc.h 中定义的

call malloc_stats()

# gcc 检查内存

编译 和 链接 都加上
-fsanitize=address

检查内存泄露
检查堆溢出
检查栈溢出
检查全局内存溢出
检查野指针


# 远程调试 
gdbserver 192.168.3.33:111 --attach 1234

gdb
target remote 192.168.3.33:111


# 多线程死锁
当进程发生死锁，gdb attach上

查看堆栈
i threads

结合bt 和 切换栈帧找到导致死锁的线程
threads apply 1 bt
threads apply 2 bt

打印mutex对象，确定锁被谁占用，其中有 Owner ID成员记录 LWP

切换占用锁的线程

确定导致死锁的逻辑

# coredump
coredump包含进程/系统在某个时刻所有内存信息和寄存器信息。

coredump可以给死的进程/系统生成，也可以给活的进程/系统生成

给活的生成的好处是，客户系统出现异常，但程序没有崩溃，可以用gdb生成coredump，进行分析

gdb生成coredump :
generate-core-file/gcore

死的生成
ulimit -c unlimited
修改coredump的名称
echo -e "%e-%p-%t" > /proc/sys/kernel/core_pattern

gdb分析coredump
gdb ./程序 ./coredump文件

# 分析无symbol的coredump
这种coredump是能进行栈回溯的，
但是不能查看args locals，所以只能使用切换栈帧和查看寄存器和反汇编方式判断问题







