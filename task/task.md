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

# task_struct 和内核栈
![](./pic/1.jpg)
struct pt_reg : 用于保存进程上下文
sp : 指向当前栈顶
current : 早期指向task_struct，后来由于task_struct越来越大，为了不占用过多内核栈，则指向thread_info

## 如何从sp找到task_struct
将sp指针按照THREAD_SIZE 8KB对齐，则获得current

```c
#define get_current() (current_thread_info()->task)
#define current get_current()

static inline struct thread_info *current_thread_info(void) __attribute_cons  t__;

static inline struct thread_info *current_thread_info(void)
{
  return (struct thread_info *)
	  (current_stack_pointer & ~(THREAD_SIZE - 1));
}
```

# 进程创建
## fork
```asm
.align 2
_sys_fork:
	call find_empty_process
	testl %eax,%eax
	js 1f
	push %gs
	pushl %esi
	pushl %edi
	pushl %ebp
	pushl %eax
	call copy_process
	addl $20,%esp
1:	ret

// 获得空闲pid
int find_empty_process(void)
{
	int i;

	repeat:
		if ((++last_pid)<0) last_pid=1;
		for(i=0 ; i<NR_TASKS ; i++)
			if (task[i] && task[i]->pid == last_pid) goto repeat;
	for(i=1 ; i<NR_TASKS ; i++)
		if (!task[i])
			return i;
	return -EAGAIN;
}

int copy_process(int nr,long ebp,long edi,long esi,long gs,long none,
		long ebx,long ecx,long edx,
		long fs,long es,long ds,
		long eip,long cs,long eflags,long esp,long ss)
{
	struct task_struct *p;
	int i;
	struct file *f;

	// 获得4KB的物理空间
	// 将4KB物理空间起始地址开始部分存放新进程的task_struct
	p = (struct task_struct *) get_free_page();
	if (!p)
		return -EAGAIN;
	// 占用一个位置
	task[nr] = p;
	// 将父进程的task_struct复制给子进程
	*p = *current;	/* NOTE! this doesn't copy the supervisor stack */
	// 设置子进程task_struct
	p->state = TASK_UNINTERRUPTIBLE;
	p->pid = last_pid;
	p->father = current->pid;
	p->counter = p->priority;
	p->signal = 0;
	p->alarm = 0;
	p->leader = 0;		/* process leadership doesn't inherit */
	p->utime = p->stime = 0;
	p->cutime = p->cstime = 0;
	p->start_time = jiffies;
	// 设置上下文
	p->tss.back_link = 0;
	// 设置子进程的栈顶
	p->tss.esp0 = PAGE_SIZE + (long) p;
	p->tss.ss0 = 0x10;
	p->tss.eip = eip;
	p->tss.eflags = eflags;
	p->tss.eax = 0;
	p->tss.ecx = ecx;
	p->tss.edx = edx;
	p->tss.ebx = ebx;
	p->tss.esp = esp;
	p->tss.ebp = ebp;
	p->tss.esi = esi;
	p->tss.edi = edi;
	p->tss.es = es & 0xffff;
	p->tss.cs = cs & 0xffff;
	p->tss.ss = ss & 0xffff;
	p->tss.ds = ds & 0xffff;
	p->tss.fs = fs & 0xffff;
	p->tss.gs = gs & 0xffff;
	p->tss.ldt = _LDT(nr);
	p->tss.trace_bitmap = 0x80000000;
	if (last_task_used_math == current)
		__asm__("clts ; fnsave %0"::"m" (p->tss.i387));
	// 复制页表
	if (copy_mem(nr,p)) {
		task[nr] = NULL;
		free_page((long) p);
		return -EAGAIN;
	}
	for (i=0; i<NR_OPEN;i++)
		if (f=p->filp[i])
			f->f_count++;
	if (current->pwd)
		current->pwd->i_count++;
	if (current->root)
		current->root->i_count++;
	if (current->executable)
		current->executable->i_count++;
	set_tss_desc(gdt+(nr<<1)+FIRST_TSS_ENTRY,&(p->tss));
	set_ldt_desc(gdt+(nr<<1)+FIRST_LDT_ENTRY,&(p->ldt));
	// 子进程可运行
	p->state = TASK_RUNNING;	/* do this last, just in case */
	return last_pid;
}
```
### vfork


## exec

# 进程的调度

进程调度就是从TASK_RUNNING 可运行的进程中找出一个进程，切换运行该进程

而进程调度要考虑进程的类型，即 IO消耗性，CPU消耗性

我们既希望切换运行的进程能有效利用CPU，又希望IO响应迅速

## schedule 

Linux0.11 进程调度的算法是，从所有TASK_RUNNING的进程中找出剩余时间片最大数的进程，切换运行，如果所有进程的时间片都消耗完了，则按照进程优先级将时间片复位，再找出最大时间片的进程进行切换运行

```c
void schedule(void)
{
	int i,next,c;
	struct task_struct ** p;

	for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
		if (*p) {
			if ((*p)->alarm && (*p)->alarm < jiffies) {
					(*p)->signal |= (1<<(SIGALRM-1));
					(*p)->alarm = 0;
				}
			if (((*p)->signal & ~(_BLOCKABLE & (*p)->blocked)) &&
			(*p)->state==TASK_INTERRUPTIBLE)
				(*p)->state=TASK_RUNNING;
		}

/* this is the scheduler proper: */

	while (1) {
		c = -1;
		next = 0;
		i = NR_TASKS;
		// 找到剩余时间片最大的进程
		p = &task[NR_TASKS];
		while (--i) {
			if (!*--p)
				continue;
			if ((*p)->state == TASK_RUNNING && (*p)->counter > c)
				c = (*p)->counter, next = i;
		}
		// 如果找到了，则进行切换
		if (c) break;
		// 如果没有，则说明所有进程的时间片都使用完了，则将所有
		// 进程的时间片复位
		for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
			if (*p)
				(*p)->counter = ((*p)->counter >> 1) +
						(*p)->priority;
	}
	switch_to(next);
}
```

## 时钟中断，时间片递减

从上面的调度算法可知，切换哪个进程的关键是看进程的当前时间片，

进程的当前时间片的改变是由时钟中断处理函数处理的,

时钟中断处理函数，会将当前进程时间片减一，如果当前进程运行在用户态且时间片为0，则进行调度

### _timer_interrupt

每次时钟中断，调用 `_timer_interrupt` 处理，

`_timer_interrupt`调用 `do_timer`

```c
.align 2
_timer_interrupt:
	push %ds		# save ds,es and put kernel data space
	push %es		# into them. %fs is used by _system_call
	push %fs
	pushl %edx		# we save %eax,%ecx,%edx as gcc doesn't
	pushl %ecx		# save those across function calls. %ebx
	pushl %ebx		# is saved as we use that in ret_sys_call
	pushl %eax
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	incl _jiffies
	movb $0x20,%al		# EOI to interrupt controller #1
	outb %al,$0x20
	movl CS(%esp),%eax
	andl $3,%eax		# %eax is CPL (0 or 3, 0=supervisor)
	pushl %eax
	call _do_timer		# 'do_timer(long CPL)' does everything from
	addl $4,%esp		# task switching to accounting ...
	jmp ret_from_sys_call
```

##### do_timer
```c
// cpl : 0 或者 3，
//       0表示当前中断发生时进程运行在内核态
//       3表示当前中断发生时进程运行在用户态           
void do_timer(long cpl)
{
	extern int beepcount;
	extern void sysbeepstop(void);

	if (beepcount)
		if (!--beepcount)
			sysbeepstop();

	if (cpl)
		current->utime++; // 用户态运行时间增加
	else
		current->stime++; // 内核态运行时间增加

	if (next_timer) {
		next_timer->jiffies--;
		while (next_timer && next_timer->jiffies <= 0) {
			void (*fn)(void);
			
			fn = next_timer->fn;
			next_timer->fn = NULL;
			next_timer = next_timer->next;
			(fn)();
		}
	}
	if (current_DOR & 0xf0)
		do_floppy_timer();
	// 将当前进程的时间片递减，如果时间片为0，则进行进程调度
	if ((--current->counter)>0) return;
	current->counter=0;
	// 如果时钟中断发生在内核态，则不进行调度
	// 只有用户态才进行调度
	if (!cpl) return;
	// 当前为用户态且时间片为0，进行调度
	schedule();
}
```

# 进程的切换
```asm
#define switch_to(prev,next,last)					\
do {									\
	last = __switch_to(prev,task_thread_info(prev), task_thread_info(next));	\
} while (0)

/*
 * 从 previous 线程切换到 next 线程
 * r0 = previous task_struct, r1 = previous thread_info, r2 = next thread_info
 * previous and next are guaranteed not to be the same.
 */
ENTRY(__switch_to)
										@ 1. 保存当前线程的cpu_context
	add	ip, r1, #TI_CPU_SAVE            @ 获得当前进程 cpu_context的内存基地址，存放在ip寄存器
	stmia	ip!, {r4 - sl, fp, sp, lr}	@ 保存当前线程的寄存器
	                                    @ 以ip为基地址，将 r4 - sl 寄存器和
										@ fp sp lr 寄存器全部保存到 thread_info.cpu_context

										@ 2. 调用 atomic_notifier_call_chain
	mov	r5, r0                          @ 用r5暂存 previously task_struct
	add	r4, r2, #TI_CPU_SAVE
	ldr	r0, =thread_notify_head         @ 函数参数0 =thread_notify_head
	mov	r1, #THREAD_NOTIFY_SWITCH       @ 函数参数1 #THREAD_NOTIFY_SWITCH
	bl	atomic_notifier_call_chain      @ 调用函数 atomic_notifier_call_chain
	mov	r0, r5                          @ r0记录 previously task_struct

										@ 3. 切换next线程的cpu_context
	ldmia	r4, {r4 - sl, fp, sp, pc}	@ Load all regs saved previously
```


### thread_info 和 进程上下文 cpu_context
```c
// thread_info保存在线程内核栈区底部
// cpu_context字段用于记录线程上下文
struct thread_info {
	unsigned long		flags;		/* low level flags */
	int			preempt_count;	/* 0 => preemptable, <0 => bug */
	mm_segment_t		addr_limit;	/* address limit */
	struct task_struct	*task;		/* main task structure */
	struct exec_domain	*exec_domain;	/* execution domain */
	__u32			cpu;		/* cpu */
	__u32			cpu_domain;	/* cpu domain */
	struct cpu_context_save	cpu_context;	/* cpu context */
	__u32			syscall;	/* syscall number */
	__u8			used_cp[16];	/* thread used copro */
	unsigned long		tp_value;
	struct crunch_state	crunchstate;
	union fp_state		fpstate __attribute__((aligned(8)));
	union vfp_state		vfpstate;
	struct restart_block	restart_block;
};


struct cpu_context_save {
	__u32	r4;
	__u32	r5;
	__u32	r6;
	__u32	r7;
	__u32	r8;
	__u32	r9;
	__u32	sl;
	__u32	fp;
	__u32	sp;
	__u32	pc;
	__u32	extra[2];		/* Xscale 'acc' register, etc */
};
```

### 新进程从哪里开始运行
```asm
ENTRY(__switch_to)
	stmia	ip!, {r4 - sl, fp, sp, lr}	
	ldmia	r4, {r4 - sl, fp, sp, pc}	
```

因为进程保存上下文是将lr寄存器的值保存到 `thread_info.cpu_context.pc` ，所以当切换运行时，pc的值为lr的值，也就是 `__switch_to` 的返回地址开始运行, 其调用关系如下，所以最后从 schedule 返回

```c
schedule
	context_switch(rq, prev, next);		
		switch_to(prev, next, prev);
			__switch_to
```

# 进程的睡眠和唤醒
## wait_event
```c

/*
 * wait_event : 进程睡眠在等待队列wq上，直到表达式 condition 结果
 * 为真，进程会被置位 TASK_UNINTERRUPTIBLE ，然后主动调度，由于
 * 进程状态不是TASK_RUNNING，所以进程之后都不会被调度，直到用户发现
 * 某些变量改变导致condition为真时，就调用 wake_up() 唤醒wq上所有
 * 进程，也就是将进程的运行状态改成TASK_RUNNING
 */
#define wait_event(wq, condition) 					\
do {									\
	if (condition)	 						\
		break;							\
	__wait_event(wq, condition);					\
} while (0)

#define __wait_event(wq, condition) 					\
do {									\
	// 创建等待队列节点，并将当前进程记录到节点
	DEFINE_WAIT(__wait);						\
	wait_queue_t __wait = {						\
		.private	= current,				\
		.func		= autoremove_wake_function,		\
		.task_list	= LIST_HEAD_INIT((__wait).task_list),	\
	}
									\
	for (;;) {							\
		// 将__wait节点加入wq，并改变进程状态为TASK_UNINTERRUPTIBLE
		prepare_to_wait(&wq, &__wait, TASK_UNINTERRUPTIBLE);	\
		// 如果条件为真，则退出
		if (condition)						\
			break;						\
		// 调度进程，由于当前进程状态为TASK_UNINTERRUPTIBLE
		// 所以之后都不会被调度，除非wake_up
		schedule();						\
	}								\
	// 设置进程状态为TASK_RUNNING
	// 并将节点移除等待队列
	finish_wait(&wq, &__wait);					\
} while (0)

#define is_sync_wait(wait)	(!(wait) || ((wait)->private))

void
prepare_to_wait(wait_queue_head_t *q, wait_queue_t *wait, int state)
{
	unsigned long flags;

	wait->flags &= ~WQ_FLAG_EXCLUSIVE;
	spin_lock_irqsave(&q->lock, flags);
	// 如果节点task_list为空，说明节点没有加入等待队列
	// 则加入等待队列q，否则说明已经加入了等待队列,则
	// 不进行加入
	if (list_empty(&wait->task_list))
		__add_wait_queue(q, wait);
			list_add(&new->task_list, &head->task_list);
	// 改变进程状态
	if (is_sync_wait(wait))
		set_current_state(state);
	spin_unlock_irqrestore(&q->lock, flags);
}

void finish_wait(wait_queue_head_t *q, wait_queue_t *wait)
{
	unsigned long flags;

	__set_current_state(TASK_RUNNING);
	// 如果节点加入了等待队列，则进行移除
	if (!list_empty_careful(&wait->task_list)) {
		spin_lock_irqsave(&q->lock, flags);
		list_del_init(&wait->task_list);
		spin_unlock_irqrestore(&q->lock, flags);
	}
}
```

### wake_up
```c
// 将等待队列x上所有线程 的状态置为 TASK_RUNNING
#define wake_up(x)			__wake_up(x, TASK_NORMAL, 1, NULL)

void __wake_up(wait_queue_head_t *q, unsigned int mode,
			int nr_exclusive, void *key)
{
	unsigned long flags;

	spin_lock_irqsave(&q->lock, flags);
	__wake_up_common(q, mode, nr_exclusive, 0, key);
	spin_unlock_irqrestore(&q->lock, flags);
}

static void __wake_up_common(wait_queue_head_t *q, unsigned int mode,
			     int nr_exclusive, int sync, void *key)
{
	wait_queue_t *curr, *next;

	list_for_each_entry_safe(curr, next, &q->task_list, task_list) {
		unsigned flags = curr->flags;

		// wait_event func为 autoremove_wake_function
		if (curr->func(curr, mode, sync, key) &&
				(flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
			break;
	}
}

int autoremove_wake_function(wait_queue_t *wait, unsigned mode, int sync, void *key)
{
	int ret = default_wake_function(wait, mode, sync, key);
		return try_to_wake_up(curr->private, mode, sync);
			p->state = TASK_RUNNING;

	// 将线程移除等待队列
	if (ret)
		list_del_init(&wait->task_list);
	return ret;
}
```

# PID
## 线程组的PID

# INIT_TASK

# current 和内核栈
## thread_info



