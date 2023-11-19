# task_struct

## Linux0.11
从Linux.0.11定义了进程基础属性
```c
struct task_struct {

/* these are hardcoded - don't touch */
	// 1. 调度相关
	// 进程状态
	long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	// 调度时间片 和 优先级
	long counter;
	long priority;

	// 2. 信号相关
	// 抵达的信号
	long signal;
	// 处理信号的方法
	struct sigaction sigaction[32];
	// 信号屏蔽字
	long blocked;	/* bitmap of masked signals */

/* various fields */
	// 进程退出原因
	int exit_code;

	// 3. 虚拟内存
	// 虚拟空间代码段，数据段，堆栈范围
	unsigned long start_code,end_code,end_data,brk,start_stack;

	// 4. 进程间关系
	// 进程号，父进程号，组进程号，会话号，组长
	long pid,father,pgrp,session,leader;
	// 进程所属的权限
	unsigned short uid,euid,suid;
	// 进程组所属的权限
	unsigned short gid,egid,sgid;

	// 5. 定时器
	// 定时器计数器，当为0时标记 SIGALRM
	long alarm;

	// 6. 运行时间 
	// 运行时间等
	long utime,stime,cutime,cstime,start_time;

	unsigned short used_math;

/* file system info */
	// 7. 文件相关
	// 绑定的终端
	int tty;		/* -1 if no tty, so it must be signed */
	// 创建文件使用的umask
	unsigned short umask;
	// 进程当前目录
	struct m_inode * pwd;
	// 初始目录
	struct m_inode * root;
	struct m_inode * executable;
	// fork时，子进程是否关闭已打开文件
	unsigned long close_on_exec;
	// 文件会话
	struct file * filp[NR_OPEN];

/* ldt for this task 0 - zero 1 - cs 2 - ds&ss */
	// 8. 内存管理相关
	// 页表
	struct desc_struct ldt[3];

/* tss for this task */
	// 9. 进程上下文
	struct tss_struct tss;
};
```
大致可以分为以下几类
- 进程管理: 
 - 调度 : state counter priority
 - 进程间关系 : pid father pgrp session leader
 - 杂项

- 资源
 - 定时器 : alarm
 - 信号资源 : signal sigaction blocked
 - 文件资源 : umask pwd root close_on_exec filp
 - 内存资源 : ldt

## Linux5.10
### 进程属性相关
* state
* pid
* flag
* exit_code 进程终止值
* exit_signal  终止信号
* pdeath_signal 父进程死亡时发出的信号
* comm 程序名
* real_cred cred  进程认证信息

## 调度相关
prio : 进程动态优先级，调度类优先考虑
static_prio : 静态优先级，内存不存储 nice值，而是 static_prio
normal_prio :  基于 static_prio 和调度策略计算出的优先级
rt_priority : 实时进程的优先级
sched_class : 调度类
se : 普通进程调度实体
rt : 实时进程调度实体
dl : deadline 进程调度实体
prolicy : 进程类型，如普通进程还是实时进程


# 进程的运行状态
```c
/* Used in tsk->state: */
// 进程正在运行，或进程在就绪队列
#define TASK_RUNNING			0x0000
// 进程因等待资源被挂起，但可以被信号打断挂起状态
#define TASK_INTERRUPTIBLE		0x0001
// 进程因等待资源被挂起，但不可以被信号打断
#define TASK_UNINTERRUPTIBLE		0x0002
// 进程暂停
#define __TASK_STOPPED			0x0004
#define __TASK_TRACED			0x0008
/* Used in tsk->exit_state: */
// 进程退出
#define EXIT_DEAD			0x0010
// 进程退出，但task_struct没有被回收
#define EXIT_ZOMBIE			0x0020
```

## 设置进程状态
```c
#define set_current_state(state_value)				\
	do {							\
		WARN_ON_ONCE(is_special_task_state(state_value));\
		current->task_state_change = _THIS_IP_;		\
		smp_store_mb(current->state, (state_value));	\
	} while (0)
```

# 进程的PID
* pid是进程的唯一编号
* pid的类型是int，默认最大32768
* 内核使用bitmap机制管理已分配的PID和空闲的PID,以循环使用pid
* 线程组使用组长的pid为自己pid

# init_task的初始化
```c

```


# 进程的调度

# PID
## 线程组的PID

# INIT_TASK

# current 和内核栈
## thread_info



