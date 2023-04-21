# 0. QEMU调试Linux
## kernel配置
为了简单，使用initramfs



## qemu
## qemu调试kernel
安装arm gdb
```shell
apt install gdb-arm-none-eabi
```


```shell
Kernel hacking -->
	Compile-time checks and compiler options -->
		[*] Compile the kernel with debug info

Gerneral setup -->
	[*] init ram filesystem 
		 (_install) initramfs source files

Boot options -->
	() default kernel command string

kernel features-->
	memory split (3G/1G user/kernel split) -->
		[*]high memory support
```

启动qemu

```shell
qemu-system-arm -M vexpress-a9 -smp 4 -m 1024M  \
	-kernel arch/arm/boot/zImage  \
	-append "rdinit=/linuxrc console=ttyAMA0 loglevel=8" \
	-dtb arch/arm/boot/dts/vexpress-v2p-ca9.dtb \
	-nographic \
	-S -s
```
-S : qemu会冻结CPU，直到远程GDB输入相应控制命令
-s : 在1234端口接受GDB的调试连接


另一个终端启动ARM gdb
```shell
arm-none-eabi-gdb --tui vmlinux
(gdb) target remote localhost:1234
(gdb) b start_kernel
(gdb) c
```

取消编译器优化
在源文件开头，写这句：（可以强制指定 本文件内以下源码全部O0编译）：
```c
#pragma GCC optimize ("O0")

// 单个函数
__attribute__((optimize("O0")))
```


# 1. 内存全景浏览

关键点：
MMU, 页表, 物理内存，物理页面，映射关系，按需分配，缺页中断，写时复制

物理内存和物理页面，接触到 struct pg_data_t , struct zone 和 struct page 。
怎么分配物理页面，接触伙伴系统机制，和页面分配器。

MMU的工作原理,
Linux内核如何建立页表映射，包括用户空间，内核空间页表的建立.
如何查询页表，修改页表。


物理内存怎么建立和虚拟内存的映射关系？
进程的虚拟内存用 struct vm_area_struct ，虚拟内存和物理内存采用建立页表的方法建立映射关系，
为什么进程地址空间建立映射的也页面有的叫匿名页面，有的叫page cache页面呢？


了解malloc怎么分配物理内存，接触到缺页中断

这时虚拟内存和物理内存已经建立和映射，这是以页为基础，如果需要小于一个页面的内存，slab机制就诞生了。

上面已经建立起虚拟内存和物理内存的基本框图，但是用户持续分配导致物理内存不足怎么办？
页回收机制和反向映射机制就产生了。

长时间运行后，产生大量碎片内存怎么办？
内存规整机制就产生了。

# 2. 物理内存
## kernel如何知道可用的内存空间的地址范围？
dts中描述了内存资源
```dts
	memory@60000000 {
		device_type = "memory";
		reg = <0x60000000 0x40000000>;
	};
```

内核解析DTS，内存相关
```c
early_init_dt_scan_memory
	分析dts memory节点，获得物理地址 base size 参数,
	调用memblock_add 将 base size信息保存到 memblock.regions[0] 中
```

所以内核如下获得可用的物理地址范围
 dts --> memblock.regions[0]


## 物理内存的映射——内核的页表
linux使用虚拟地址，在汇编部分建立了零时的段表，
但是段表现在粒度太大，所以这里需要建立页表，
页表复用段表内存空间init\_mm，首先需要将段表空间清零，
```c
prepare_page_table
	遍历虚拟地址调用pmd_clear将对应的页表清零，这里只清零一级页表
	清空的虚拟地址包括
	0 - MODULES_VADDR
	MODULES_VADDR - PAGE_OFFSET
	__phys_to_virt(arm_lowmem_limit(低端物理内存的边界)/物理内存的结束地址) - VMALLOC_START

#define PGDIR_SHIFT		21

// 根据虚拟地址找到pgd页表项下标
#define pgd_index(addr)		((addr) >> PGDIR_SHIFT)

// 根据虚拟地址找到pgd页表项
#define pgd_offset(mm, addr)	((mm)->pgd + pgd_index(addr))

// init_mm 是kernel的pgd页表
#define pgd_offset_k(addr)	pgd_offset(&init_mm, addr)

// 只使用2级页表，则 pgd页表项对应一个pud页表项
static inline pud_t * pud_offset(pgd_t * pgd, unsigned long address)
{
	return (pud_t *)pgd;
}

// 只使用2级页表，则 pud页表项对应一个pmd页表项
static inline pmd_t * pmd_offset(pud_t * pud, unsigned long address)
{
	return (pmd_t *)pud;
}

static inline pmd_t *pmd_off_k(unsigned long virt)
{
	// pmd_offset( pud_offset( pgd页表项 , virt), virt);
	// pmd_offset( pud页表项 , virt);
	// pmd页表项
	return pmd_offset( pud_offset( pgd_offset_k(virt), virt), virt);
}


#define __pmd(x)        ((pmd_t) { (x) } )

#define pmd_clear(pmdp)			\
	do {				\
		pmdp[0] = __pmd(0);	\
		pmdp[1] = __pmd(0);	\
		clean_pmd_entry(pmdp);	\
	} while (0)

// pmd_clear(pmd页表项，也就是pgd页表项)
pmd_clear(pmd_off_k(addr)); // 将页表项置零 
                            // 注意 PGDIR_SHIFT 为21,所以每次操作两个pgd
							// 一个为Linux表，一个为ARM表

```

清零后，建立线性映射，被线性映射的物理内存称为低端内存。
```c
map_lowmem
	// kernel 代码段的起始和结束
	phys_addr_t kernel_x_start = round_down(__pa(_stext), SECTION_SIZE);
	phys_addr_t kernel_x_end = round_up(__pa(__init_end), SECTION_SIZE);

	// 映射所有的低端内存
	for_each_memblock(memory, reg) {
		// 获得可用的物理地址范围
		phys_addr_t start = reg->base;
		phys_addr_t end = start + reg->size;

		struct map_desc map;

		// 线性映射只针对低端物理内存
		if (end > arm_lowmem_limit)
			end = arm_lowmem_limit;
		if (start >= end)
			break;

		// 建立线性映射
		// 注意 kernel的代码段权限只读，
		// 所以物理地址若落在kernel代码段内则要单独映射
		if (end < kernel_x_start) {
			map.pfn = __phys_to_pfn(start);
			map.virtual = __phys_to_virt(start);
			map.length = end - start;
			map.type = MT_MEMORY_RWX;

			create_mapping(&map);
		} else if (start >= kernel_x_end) {
			map.pfn = __phys_to_pfn(start);
			map.virtual = __phys_to_virt(start);
			map.length = end - start;
			map.type = MT_MEMORY_RW;

			create_mapping(&map);
		} else {
			/* This better cover the entire kernel */
			if (start < kernel_x_start) {
				map.pfn = __phys_to_pfn(start);
				map.virtual = __phys_to_virt(start);
				map.length = kernel_x_start - start;
				map.type = MT_MEMORY_RW;

				create_mapping(&map);
			}

			map.pfn = __phys_to_pfn(kernel_x_start);
			map.virtual = __phys_to_virt(kernel_x_start);
			map.length = kernel_x_end - kernel_x_start;
			map.type = MT_MEMORY_RWX;

			create_mapping(&map);

			if (kernel_x_end < end) {
				map.pfn = __phys_to_pfn(kernel_x_end);
				map.virtual = __phys_to_virt(kernel_x_end);
				map.length = end - kernel_x_end;
				map.type = MT_MEMORY_RW;

				create_mapping(&map);
			}
```

## zone的初始化
建立线性映射后，内核可以对内存进行管理，但是内核不是统一对待这些页面，而是采用区块zone的方式来管理。
struct zone成员
```c
// zone经常被访问，所以需要以 L1 cache对齐
struct zone {
	unsigned long watermark[NR_WMARK]; // 页面分配和回收使用

	long lowmem_reserve[MAX_NR_ZONES];

#ifdef CONFIG_NUMA
	int node;
#endif

	struct pglist_data	*zone_pgdat;         // 指向内存节点
	struct per_cpu_pageset __percpu *pageset; // 一部分页面构造percpu副本，减少自旋锁使用

	/* zone_start_pfn == zone_start_paddr >> PAGE_SHIFT */
	unsigned long		zone_start_pfn;  // 开始页面页帧号

	unsigned long		managed_pages;  // zone中被伙伴系统管理的页面数量
	unsigned long		spanned_pages;  // zone中包含的页面数量
	unsigned long		present_pages;  // zone中实际管理的页面数量,有些体系结构下和spanned_pages相等

	const char		*name;

	/* free areas of different sizes */
	struct free_area	free_area[MAX_ORDER]; // 空闲区域数组

	/* Write-intensive fields used from the page allocator */
	spinlock_t		lock;  // 并行访问时用于保护zone的自旋锁

	/* Fields commonly accessed by the page reclaim scanner */
	spinlock_t		lru_lock;  // 对zone中LRU链表并行访问时进行保护的自旋锁
	struct lruvec		lruvec; // LRU链表集合

	/* Zone statistics */
	atomic_long_t		vm_stat[NR_VM_ZONE_STAT_ITEMS]; // zone计数
} ____cacheline_internodealigned_in_smp;
```

通常zone有 ZONE_DMA ZONE_DMA32 ZONE_NORMAL ZONE_HIGHMEM
但arm只有 ZONE_NORMAL ZONE_HIGHMEM

要让zone来管理page，就要让zone知道自己能管理的page的范围。
在find_limit()中计算出 min_low_pfn, max_low_pfn, max_pfn.
min_low_pfn: 物理内存开始地址的页帧号,同时也是normal区域起始页帧号
max_low_pfn: normal区域的结束页帧号
max_pfn: 内存块结束地址页帧号


从kernel启动看物理空间和虚拟空间
```shell
// 物理空间
// 可以看出有两个zone, Normal zone , high zone
  Normal zone: 1520 pages used for memmap
  Normal zone: 0 pages reserved
  Normal zone: 194560 pages, LIFO batch:31
  HighMem zone: 67584 pages, LIFO batch:15

// 虚拟空间
// lowmem 映射 normal zone
// 0xef800000 - 0xc0000000 / 4096 = 194560 pages
// 线性映射关系： 
// 见后面 _virt_to_phys , _phys_to_virt
// 0xef800000 - PAGE_OFFSET(0xc0000000) + PHY_OFFSET(0x60000000) = 0x8f800000(arm_lowmem_limit)
Virtual kernel memory layout:
    vector  : 0xffff0000 - 0xffff1000   (   4 kB)
    fixmap  : 0xffc00000 - 0xfff00000   (3072 kB)
    vmalloc : 0xf0000000 - 0xff000000   ( 240 MB)
    lowmem  : 0xc0000000 - 0xef800000   ( 760 MB)
    pkmap   : 0xbfe00000 - 0xc0000000   (   2 MB)
    modules : 0xbf000000 - 0xbfe00000   (  14 MB)
      .text : 0xc0008000 - 0xc060a270   (6153 kB)
      .init : 0xc060b000 - 0xc13e8000   (14196 kB)
      .data : 0xc13e8000 - 0xc140f3c0   ( 157 kB)
       .bss : 0xc140f3c0 - 0xc1438bf0   ( 167 kB)
```

zone的初始化函数 : free_area_init_core

另一个和zone相关数据结构：zonelist。
伙伴系统从zonelist开始分配内存，zonelist有一个zoneref数组，数组元素的成员有一个zone指针。
zoneref数组的第一个成员指向的zone是页面分配器的第一个候选者，若第一个候选者分配失败之后才考虑其他成员，优先级逐渐降低。
初始化zonelist的函数 build_zonelists_node


```c
enum zone_type {
	ZONE_NORMAL,
	ZONE_HIGHMEM,
	__MAX_NR_ZONES
};

static int build_zonelists_node(pg_data_t *pgdat, struct zonelist *zonelist,
				int nr_zones)
{
	struct zone *zone;
	enum zone_type zone_type = MAX_NR_ZONES;

	do {
		zone_type--;
		zone = pgdat->node_zones + zone_type;
		if (populated_zone(zone)) {
			zoneref_set_zone(zone,
				&zonelist->_zonerefs[nr_zones++]);
			check_highest_zone(zone_type);
		}
	} while (zone_type);

	return nr_zones;
}
```
初始化后： 
```c
  _zonerefs[0]->zone_index = 1 --> ZONE_HIGHMEM
  _zonerefs[1]->zone_index = 0 --> ZONE_NORMAL
```
所以先从高端内存分配


另一个重要的全局变量 mem_map
它是struct page数组，实现快速把虚拟地址映射到物理地址，线性映射。
它的初始化 free_area_init_node -> alloc_node_mem_map

所以对于同个page可能同时被多种映射，如果是低端内存就一定被线性映射，mem_map
也可能有非线性映射 那么从 zone中分配page，再分配个虚拟空间，建立Vmalloc映射

## 虚拟空间划分
32bit Linux 共有虚拟空间 4GB，用户空间和内核空间可以配置。
```c
CONFIG_PAGE_OFFSET
```

设置会影响 PAGE_OFFSET值，这个值也被用于做线性映射的偏移值。
```c
/* PAGE_OFFSET - the virtual address of the start of the kernel image */
#define PAGE_OFFSET		UL(CONFIG_PAGE_OFFSET)
```

线性映射的计算
```c
/*
 * PHYS_OFFSET : 物理内存的起始地址
 */
static inline phys_addr_t __virt_to_phys(unsigned long x)
{
	return (phys_addr_t)x - PAGE_OFFSET + PHYS_OFFSET;
}

static inline unsigned long __phys_to_virt(phys_addr_t x)
{
	return x - PHYS_OFFSET + PAGE_OFFSET;
}
```

## 物理内存的初始化
内核知道物理内存的地址范围和各种zone的布局后，page就要加入伙伴系统。
每个zone 都有一个free_area，这就是伙伴系统管理的基础。
所以每个zone都有一个伙伴系统。
![](./pic/37.jpg)
free_area数组，大小是MAX_ORDER，每个元素有MIGRATE_TYPES个链表

```c
struct zone {
	..
	struct free_area[MAX_ORDER];
	..
};

struct free_area {
	struct list_head free_list[MIGRATE_TYPES];
	unsigned long nr_free;
};


enum {
	MIGRATE_UNMOVABLE,
	MIGRATE_RECLAIMABLE,
	MIGRATE_MOVABLE,
	MIGRATE_PCPTYPES,	/* the number of types on the pcp lists */
	MIGRATE_RESERVE = MIGRATE_PCPTYPES,
	MIGRATE_TYPES
};
```
伙伴系统的特点是：
内存块是2的order幂，把所有空闲的页面分组成11个内存块链表，
每个链表分布包括 1,2,4,...1024个连续的page。
1024个page对应4MB大小的连续物理内存

从/porc/pagetypeinfo可以知道page在链表的分布
![](./pic/38.jpg)

存放在2^10链表中的page又被称为pageblock，他们是大小为 4MB

思考，物理页面是如何添加到伙伴系统？是一页一页添加，还是以2的几次幂添加？

```c
static unsigned long __init free_low_memory_core_early(void)
{
	unsigned long count = 0;
	phys_addr_t start, end;
	u64 i;

	memblock_clear_hotplug(0, -1);

	// 遍历memblock.memory 其记录了可用的物理内存块范围
	// 得到start end
	for_each_free_mem_range(i, NUMA_NO_NODE, &start, &end, NULL)
		count += __free_memory_core(start, end);

	return count;
}
```

```c
static unsigned long __init __free_memory_core(phys_addr_t start,
				 phys_addr_t end)
{
	unsigned long start_pfn = PFN_UP(start);
	unsigned long end_pfn = min_t(unsigned long,
				      PFN_DOWN(end), max_low_pfn);

	if (start_pfn > end_pfn)
		return 0;

	__free_pages_memory(start_pfn, end_pfn);

	return end_pfn - start_pfn;
}

static void __init __free_pages_memory(unsigned long start, unsigned long end)
{
	int order;

	while (start < end) {
		/*
		 * 找order也就是找对齐值
		 *
		 * __ffs(x) : ffs(x) - 1
		 * ffs(x)   : 计算x中第一个bit为1的位置
		 *            如ffs(0x63300)，则__ffs(0x63300)为8
		 *            那么这里order为8
		 */
		order = min(MAX_ORDER - 1UL, __ffs(start));

		while (start + (1UL << order) > end)
			order--;

		__free_pages_bootmem(pfn_to_page(start), order);

		start += (1UL << order);
	}
}
```

将page加到对应的链表
```c
void __init __free_pages_bootmem(struct page *page, unsigned int order)
{
	unsigned int nr_pages = 1 << order;
	struct page *p = page;
	unsigned int loop;

	page_zone(page)->managed_pages += nr_pages;
	set_page_refcounted(page);
	__free_pages(page, order);
}
```

下面是向系统添加一段内存的情况，页帧号范围：[0x8800e, 0xaecea]
可以发现，一开始地址只能对齐order较低的情况，后面都以order=10也就是0x400对齐。
![](./pic/39.jpg)

