# task_struct

## Linux0.11
从Linux.0.11定义了进程基础属性
```c
struct task_struct {

/* these are hardcoded - don't touch */
	// 调度相关
	// 进程状态
	long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	// 调度时间片 和 优先级
	long counter;
	long priority;

	// 信号相关
	// 抵达的信号
	long signal;
	// 处理信号的方法
	struct sigaction sigaction[32];
	// 信号屏蔽字
	long blocked;	/* bitmap of masked signals */

/* various fields */
	// 进程退出原因
	int exit_code;
	unsigned long start_code,end_code,end_data,brk,start_stack;

	// 进程号，父进程号，组进程号，会话号，组长
	long pid,father,pgrp,session,leader;
	// 进程所属的权限
	unsigned short uid,euid,suid;
	// 进程组所属的权限
	unsigned short gid,egid,sgid;

	// 定时器计数器，当为0时标记 SIGALRM
	long alarm;

	// 运行时间等
	long utime,stime,cutime,cstime,start_time;

	unsigned short used_math;

/* file system info */
	// 文件管理相关
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
	// 内存管理相关
	// 页表
	struct desc_struct ldt[3];

/* tss for this task */
	// 进程上下文
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


# 进程的调度

# PID
## 线程组的PID

# INIT_TASK

# current 和内核栈
## thread_info



