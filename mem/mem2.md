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
```c
struct zone {
	..
	struct free_area free_area[MAX_ORDER];
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
![](./pic/40.jpg)

伙伴系统的特点是：
内存块是2的order幂，把所有空闲的页面分组成11个内存块链表，
每个链表分布包括 1,2,4,...1024个连续的page。
1024个page对应4MB大小的连续物理内存

从/porc/pagetypeinfo可以知道page在链表的分布
![](./pic/38.jpg)

存放在2^10链表中的page又被称为pageblock，他们是大小为 4MB

思考，物理页面是如何添加到伙伴系统？是一页一页添加，还是以2的几次幂添加？


```c
// start_kernel -> mm_init -> mem_init -> free_all_bootmem -> free_low_memory_core_early
// 将低端物理内存加入伙伴系统
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
	unsigned long start_pfn = PFN_UP(start); // 获得startd对应的物理页帧号，注意是上取整，如start位于0 - 1 物理页帧之间，则返回1
	unsigned long end_pfn = min_t(unsigned long,
				      PFN_DOWN(end), max_low_pfn); // 取end下取整的物理页帧号， max_low_pfn 为lowmem的最大页帧号

	if (start_pfn > end_pfn)
		return 0;

	__free_pages_memory(start_pfn, end_pfn);

	return end_pfn - start_pfn;
}

/*
 * 这段代码可以看出page会尽可能加入大的order
 */
static void __init __free_pages_memory(unsigned long start, unsigned long end)
{
	int order;

	while (start < end) {
		/*
		 * 为了尽可能创建大块连续物理内存块，
		 *
		 * 找order也就是找对齐值
		 *
		 * __ffs(x) : ffs(x) - 1
		 * ffs(x)   : 计算x中第一个bit为1的位置
		 *            如ffs(0x63300)，则__ffs(0x63300)为8
		 *            那么这里order为8
		 */
		order = min(MAX_ORDER - 1UL, __ffs(start));

		while (start + (1UL << order) > end)  // 1 << order 是free的page数量
			order--;

		__free_pages_bootmem(pfn_to_page(start), order); // 从start开始释放 1 << order个page

		start += (1UL << order);
	}
}

void __init __free_pages_bootmem(struct page *page, unsigned int order)
{
	unsigned int nr_pages = 1 << order;
	struct page *p = page;
	unsigned int loop;

	page_zone(page)->managed_pages += nr_pages; // 伙伴系统增加管理页面数量
	set_page_refcounted(page); // 设置page的引用计数为1
	__free_pages(page, order); // 添加到伙伴系统, 可以通过 page_zone(page) 获得page所在的zone，所以不需要传递zone参数
}
```

下面是向系统添加一段内存的情况，页帧号范围：[0x8800e, 0xaecea]
可以发现，一开始地址只能对齐order较低的情况，后面都以order=10也就是0x400对齐。
![](./pic/39.jpg)

# 页表的映射过程
思考：
	内核空间的页表存放在什么位置?

## ARM32页表映射
### 虚拟地址结构
32bit Linux一般采用3层映射模型，PGD(页面目录), PMD(页面中间目录), PTE(页面映射表)
ARM32 中只用到两层，所以实际代码需要将 PGD 和 PMD 合并。
另外ARM32也可以用段映射，是一层映射模型。
对于页面映射，可以选择64KB的页，和4KB的小页。
默认采用4KB大小的页面。

![](./pic/41.jpg)

采用段映射的虚拟地址结构：
31-12 : 段地址
11-0  : 段内偏移

采用页表映射模式的虚拟地址结构
31-20 : PGD地址
19-12 : PTE地址(256项)
11-0  : 页内偏移

当内存映射开启后，CPU放出的地址，只传递给MMU，MMU将认为是虚拟地址，映射成物理地址，发给ddr

实际代码中页表映射模式的虚拟地址结构
```c
// PMD 和 PGD 等价
#define PMD_SHIFT		21
#define PGDIR_SHIFT		21

#define PMD_SIZE		(1UL << PMD_SHIFT)
#define PMD_MASK		(~(PMD_SIZE-1))
#define PGDIR_SIZE		(1UL << PGDIR_SHIFT)
#define PGDIR_MASK		(~(PGDIR_SIZE-1))
```
需要注意ARM支持的页表模式的虚拟地址结构，PGD地址占20bit，但是Linux却使用21bit
因为一个page为4KB，而一个PGD项对应256个PTE，占用256\*4 = 1024字节，
又有arm 和 Linux两个PGD，占用512个PTE，占用2048字节，
所以一个page可以给两个PGD分配，所以linux使用21bit

### create_mapping
create_mapping 用于给定空间建立映射。
该函数使用 map_desc 描述内存区间
```c
struct map_desc {
	unsigned long virtual; // 起始虚拟地址
	unsigned long pfn;     // 起始物理页帧号
	unsigned long length;  // 空间大小
	unsigned int type;     // 权限
};
```

```c
static void __init create_mapping(struct map_desc *md)
{
	unsigned long addr, length, end;
	phys_addr_t phys;
	const struct mem_type *type;
	pgd_t *pgd;

	addr = md->virtual & PAGE_MASK;
	phys = __pfn_to_phys(md->pfn);  // 获得物理地址
	length = PAGE_ALIGN(md->length + (md->virtual & ~PAGE_MASK)); // 映射大小

	pgd = pgd_offset_k(addr); // 获得PGD页表项
	end = addr + length; // 结束物理地址
	do {
		unsigned long next = pgd_addr_end(addr, end); // 下一次映射的起始物理地址
		                                              // 一次映射 PGDIR_SIZE 大小的空间，也就是 2MB

		alloc_init_pud(pgd, addr, next, phys, type);

		phys += next - addr;
		addr = next;
	} while (pgd++, addr != end);
}


#define pgd_offset_k(addr)	pgd_offset(&init_mm, addr)
#define pgd_offset(mm, addr)	((mm)->pgd + pgd_index(addr)) // 这里看出 init_mm.pgd 记录内核页表地址
#define pgd_index(addr)		((addr) >> PGDIR_SHIFT)

struct mm_struct init_mm = {
	...
	.pgd		= swapper_pg_dir, // 内存页表存放在这里
	...
};

#define pgd_addr_end(addr, end)						\
({	unsigned long __boundary = ((addr) + PGDIR_SIZE) & PGDIR_MASK;	\
	(__boundary - 1 < (end) - 1)? __boundary: (end);		\
})

typedef struct { pmdval_t pgd[2]; } pgd_t; // pgd++ 移动两个PGD页表项
typedef u32 pmdval_t;

//-------------------------------------------------------------------------------

static void __init alloc_init_pud(pgd_t *pgd, unsigned long addr,
				  unsigned long end, phys_addr_t phys,
				  const struct mem_type *type)
{
	pud_t *pud = pud_offset(pgd, addr); // pgd项和pud项等价
	unsigned long next;

	do {
		next = pud_addr_end(addr, end);
		alloc_init_pmd(pud, addr, next, phys, type);
		phys += next - addr;
	} while (pud++, addr = next, addr != end); // 由于next等于end所以只循环一次
}

static inline pud_t * pud_offset(pgd_t * pgd, unsigned long address)
{
	return (pud_t *)pgd;
}

#define pud_addr_end(addr, end)			(end)

//-------------------------------------------------------------------------------

static void __init alloc_init_pmd(pud_t *pud, unsigned long addr,
				      unsigned long end, phys_addr_t phys,
				      const struct mem_type *type)
{
	pmd_t *pmd = pmd_offset(pud, addr); // pmd 和 pud等价
	unsigned long next;

	do {
		next = pmd_addr_end(addr, end); // next 等于 end

		if (type->prot_sect &&
				((addr | next | phys) & ~SECTION_MASK) == 0) {
			__map_init_section(pmd, addr, next, phys, type); // ?
		} else {
			alloc_init_pte(pmd, addr, next,
						__phys_to_pfn(phys), type);
		}

		phys += next - addr;

	} while (pmd++, addr = next, addr != end); // 由于 next 等于 end 所以只循环一次
}

static inline pmd_t *pmd_offset(pud_t *pud, unsigned long addr)
{
	return (pmd_t *)pud;
}

#define pmd_addr_end(addr,end) (end)

#define	__phys_to_pfn(paddr)	((unsigned long)((paddr) >> PAGE_SHIFT))
#define	__pfn_to_phys(pfn)	((phys_addr_t)(pfn) << PAGE_SHIFT)


//-------------------------------------------------------------------------------

static void __init alloc_init_pte(pmd_t *pmd, unsigned long addr,
				  unsigned long end, unsigned long pfn,
				  const struct mem_type *type)
{
	pte_t *pte = early_pte_alloc(pmd, addr, type->prot_l1); // 分配page用作pte表，返回pte表的基地址
	do {
		set_pte_ext(pte, pfn_pte(pfn, __pgprot(type->prot_pte)), 0); // 设置PTE页表项,包括Linux 和 arm
		pfn++;
	} while (pte++, addr += PAGE_SIZE, addr != end); // 从最前面可知 end 和addr差了 2MB，而这里一次映射4KB，所以需要循环 512次
}

#define pfn_pte(pfn,prot)	__pte(__pfn_to_phys(pfn) | pgprot_val(prot)) // 获得pte项填充内容
#define set_pte_ext(ptep,pte,ext) cpu_set_pte_ext(ptep,pte,ext)

static pte_t * __init early_pte_alloc(pmd_t *pmd, unsigned long addr, unsigned long prot)
{
	if (pmd_none(*pmd)) {
		pte_t *pte = early_alloc(PTE_HWTABLE_OFF + PTE_HWTABLE_SIZE); // 1024 * sizeof(pte) = 4KB ，刚好是一个page大小
		                                                              // 知道一个PGD项对应256项PTE，
																	  // 所以这里实际映射两个 PGD项，也就是512个PTE
																	  // 又有Linux 和 arm 两种PTE，各2个，共4个，所以为1024个pte
		__pmd_populate(pmd, __pa(pte), prot); // 填充PGD项，使其指向PTE表
	}
	BUG_ON(pmd_bad(*pmd));
	return pte_offset_kernel(pmd, addr);
}

typedef struct { pteval_t pte; } pte_t;
typedef u32 pteval_t;

#define PTRS_PER_PTE		512
#define PTRS_PER_PMD		1
#define PTRS_PER_PGD		2048

#define PTE_HWTABLE_PTRS	(PTRS_PER_PTE)
#define PTE_HWTABLE_OFF		(PTE_HWTABLE_PTRS * sizeof(pte_t)) // 512
#define PTE_HWTABLE_SIZE	(PTRS_PER_PTE * sizeof(u32)) // 512

#define pmd_none(pmd)		(!pmd_val(pmd))
#define pmd_val(x)      ((x).pmd)

static void __init *early_alloc(unsigned long sz)
{
	return early_alloc_aligned(sz, sz);
}
static void __init *early_alloc_aligned(unsigned long sz, unsigned long align)
{
	void *ptr = __va(memblock_alloc(sz, align));
	memset(ptr, 0, sz);
	return ptr;
}

#define __pa(x)			__virt_to_phys((unsigned long)(x))

static inline phys_addr_t __virt_to_phys(unsigned long x)
{
	return (phys_addr_t)x - PAGE_OFFSET + PHYS_OFFSET;
}

static inline unsigned long __phys_to_virt(phys_addr_t x)
{
	return x - PHYS_OFFSET + PAGE_OFFSET;
}

#define pte_offset_kernel(pmd,addr)	(pmd_page_vaddr(*(pmd)) + pte_index(addr)) // pte表基地址加偏移，得到pte项的地址

static inline pte_t *pmd_page_vaddr(pmd_t pmd)
{
	return __va(pmd_val(pmd) & PHYS_MASK & (s32)PAGE_MASK); // 取高[31-12]位，这是pte表的地址
}

#define pmd_val(x)      ((x).pmd)

#define pte_index(addr)		(((addr) >> PAGE_SHIFT) & (PTRS_PER_PTE - 1)) // addr计算出页表项的下标，再乘以4字节

static inline void __pmd_populate(pmd_t *pmdp, phys_addr_t pte,
				  pmdval_t prot)
{
	pmdval_t pmdval = (pte + PTE_HWTABLE_OFF) | prot; // 注意pte地址本身是4KB对齐的，所以低12位没有用，可以设置其他内容
	pmdp[0] = __pmd(pmdval); // 填充Linux PGD项
	pmdp[1] = __pmd(pmdval + 256 * sizeof(pte_t)); // 填充ARM PGD项
	flush_pmd_entry(pmdp);
}
```

# 内存的布局图
思考：
	32bit Linux中 ，内核空间线性映射的虚拟地址和物理地址是如何转换？
	32bit Linux中，高端内存起始地址如何计算出来的？
	画出arm32 Linux内核布局图

用户空间和内核空间的比例通常是3:1，内核空间只有1GB，其中部分用于直接映射物理内存，称为线性映射区，
在32bit arm Linux物理地址[0:760MB]被映射到虚拟地址[3GB:3GB+760MB]，
虚拟地址和物理地址的差值为PAGE_OFFSET，即3GB。

线性映射区，虚拟地址和物理地址的转换
```c
#define __pa(x)			__virt_to_phys((unsigned long)(x))
#define __va(x)			((void *)__phys_to_virt((phys_addr_t)(x)))

static inline phys_addr_t __virt_to_phys(unsigned long x)
{
	return (phys_addr_t)x - PAGE_OFFSET + PHYS_OFFSET;
}

static inline unsigned long __phys_to_virt(phys_addr_t x)
{
	return x - PHYS_OFFSET + PAGE_OFFSET;
}
```
PHYS_OFFSET : 内存物理地址的起始地址


那么高端内存的起始地址是如何确定的呢？

```c
static void * __initdata vmalloc_min =
	(void *)(VMALLOC_END - (240 << 20) - VMALLOC_OFFSET); // 结果为760MB

void __init sanity_check_meminfo(void)
{
	phys_addr_t memblock_limit = 0;
	int highmem = 0;
	phys_addr_t vmalloc_limit = __pa(vmalloc_min - 1) + 1;
	struct memblock_region *reg;

	for_each_memblock(memory, reg) {
		phys_addr_t block_start = reg->base;
		phys_addr_t block_end = reg->base + reg->size;
		phys_addr_t size_limit = reg->size;

		if (reg->base >= vmalloc_limit)
			highmem = 1;
		else
			size_limit = vmalloc_limit - reg->base;


		if (!highmem) {
			if (block_end > arm_lowmem_limit) {
				if (reg->size > size_limit)
					arm_lowmem_limit = vmalloc_limit; // 低端物理内存最多到 vmalloc_limit
				else
					arm_lowmem_limit = block_end;
			}

			if (!memblock_limit) {
				if (!IS_ALIGNED(block_start, SECTION_SIZE))
					memblock_limit = block_start;
				else if (!IS_ALIGNED(block_end, SECTION_SIZE))
					memblock_limit = arm_lowmem_limit;
			}

		}
	}

	high_memory = __va(arm_lowmem_limit - 1) + 1; // 确定高端虚拟内存

	if (memblock_limit)
		memblock_limit = round_down(memblock_limit, SECTION_SIZE);
	if (!memblock_limit)
		memblock_limit = arm_lowmem_limit;

	memblock_set_current_limit(memblock_limit);
}
```
内核剩下的264MB高端虚拟内存，用于做什么呢？
保留给vmalloc fixmap和高端向量表使用。
内核很多驱动使用vmalloc分配连续虚拟内存，因为驱动不需要使用连续的物理内存，
vmalloc还能用于高端物理内存的临时映射。一个32bit系统实际的物理内存会超过内核线性映射的长度，但内核要有对所有内存寻找的能力。

![](./pic/42.jpg)
内核将物理内存低于760MB的称为线性映射内存（Normal memory），高于760MB的称为高端内存（high memory），
由于32位系统只有4GB寻址空间，对于物理内存高于760MB，低于4GB的情况，可以从保留的240MB虚拟地址空间划分一部分用于动态映射高端内存，
这样内存就可以访问到全部4GB物理内存。
如果物理内存高于4GB，则需要LPE机制扩展物理内存的访问。
用于访问高端内存的虚拟内存是有限的，一部分为临时映射，一部分为固定映射。pkmap就是固定映射。

# 分配物理页面
前面使用过memblock_alloc分配物理内存块，并返回虚拟地址，memblock_alloc在 memblock.region 中查找可用的内存区域，并从中分配所需的内存块。分配内存时，memblock_alloc 会将所选的空闲内存区域从 memblock.region 中删除，并将其标记为已分配状态。
这种分配是不细致的，伙伴系统是基于memblock.regions实现的，实现更好的物理内存管理。

memblock.region 描述的是物理内存的分布情况，包括空闲区域和已经分配的区域等。在 Linux 内核中，伙伴系统是一种用于管理可变大小内存块的内存分配器，它是建立在物理内存之上的，即 memblock.region 描述的物理内存。


## 伙伴系统分配物理内存
![](./pic/43.jpg)
alloc_pages是伙伴系统分配物理内存的接口，用于分配一个或多个连续的物理内存页，大小必须是2的整数幂次，
分配连续的物理页，有助于减少内存碎片化，但即使如此内存碎片化也就是令人头痛的问题。
```c
struct page *alloc_pages(gfp_t gfp_mask, unsigned int order);
```
gfp_mask 称为分配掩码，分为两类：
一类叫 zone modifiers : 用于指定从哪个zone中分配页面，由掩码低4位表示，分别为
```c
#define __GFP_DMA	((__force gfp_t)___GFP_DMA)
#define __GFP_HIGHMEM	((__force gfp_t)___GFP_HIGHMEM)
#define __GFP_DMA32	((__force gfp_t)___GFP_DMA32)
#define __GFP_MOVABLE	((__force gfp_t)___GFP_MOVABLE)  /* Page is movable */
#define GFP_ZONEMASK	(__GFP_DMA|__GFP_HIGHMEM|__GFP_DMA32|__GFP_MOVABLE)
```
另一类叫 action modifiers，决定分配行为，
```c
#define __GFP_WAIT	((__force gfp_t)___GFP_WAIT)	/* Can wait and reschedule? */
#define __GFP_HIGH	((__force gfp_t)___GFP_HIGH)	/* Should access emergency pools? */
#define __GFP_IO	((__force gfp_t)___GFP_IO)	/* Can start physical IO? */
#define __GFP_FS	((__force gfp_t)___GFP_FS)	/* Can call down to low-level FS? */
#define __GFP_COLD	((__force gfp_t)___GFP_COLD)	/* Cache-cold page required */
#define __GFP_NOWARN	((__force gfp_t)___GFP_NOWARN)	/* Suppress page allocation failure warning */
#define __GFP_REPEAT	((__force gfp_t)___GFP_REPEAT)	/* See above */
#define __GFP_NOFAIL	((__force gfp_t)___GFP_NOFAIL)	/* See above */
#define __GFP_NORETRY	((__force gfp_t)___GFP_NORETRY) /* See above */
#define __GFP_MEMALLOC	((__force gfp_t)___GFP_MEMALLOC)/* Allow access to emergency reserves */
#define __GFP_COMP	((__force gfp_t)___GFP_COMP)	/* Add compound page metadata */
#define __GFP_ZERO	((__force gfp_t)___GFP_ZERO)	/* Return zeroed page on success */
#define __GFP_NOMEMALLOC ((__force gfp_t)___GFP_NOMEMALLOC) /* Don't use emergency reserves.
							 * This takes precedence over the
							 * __GFP_MEMALLOC flag if both are
							 * set
							 */
#define __GFP_HARDWALL   ((__force gfp_t)___GFP_HARDWALL) /* Enforce hardwall cpuset memory allocs */
#define __GFP_THISNODE	((__force gfp_t)___GFP_THISNODE)/* No fallback, no policies */
#define __GFP_RECLAIMABLE ((__force gfp_t)___GFP_RECLAIMABLE) /* Page is reclaimable */
#define __GFP_NOTRACK	((__force gfp_t)___GFP_NOTRACK)  /* Don't track with kmemcheck */

#define __GFP_NO_KSWAPD	((__force gfp_t)___GFP_NO_KSWAPD)
#define __GFP_OTHER_NODE ((__force gfp_t)___GFP_OTHER_NODE) /* On behalf of other node */
#define __GFP_WRITE	((__force gfp_t)___GFP_WRITE)	/* Allocator intends to dirty page */
```


alloc_pages首先要根据 gfp_mask 决定从哪个zone分配
```c
static inline struct page *alloc_pages_node(int nid, gfp_t gfp_mask,
						unsigned int order)
{
	/* Unknown node is current node */
	if (nid < 0)
		nid = numa_node_id();

	return __alloc_pages(gfp_mask, order, node_zonelist(nid, gfp_mask) /*根据node id 和 gfp_mask，找到从哪个zonelist分配*/);
}

struct page *
__attribute__((optimize("O0")))
__alloc_pages_nodemask(gfp_t gfp_mask /*GFP_KERNEL*/, unsigned int order,
			struct zonelist *zonelist, nodemask_t *nodemask)
{
	struct zoneref *preferred_zoneref;
	struct page *page = NULL;
	unsigned int cpuset_mems_cookie;
	int alloc_flags = ALLOC_WMARK_LOW|ALLOC_CPUSET|ALLOC_FAIR;
	gfp_t alloc_mask; /* The gfp_t that was actually used for allocation */
	struct alloc_context ac = {
		.high_zoneidx = gfp_zone(gfp_mask),  // ZONE_NORMAL(0) 表示使用哪个zone分配
		.nodemask = nodemask,                // 0x0
		.migratetype = gfpflags_to_migratetype(gfp_mask), // 0x0 MIGRATE_UNMOVABLE, 将gfp_mask转换为migrate类型
	};

	...

	// 首先从空闲的page分配，理想情况会成功
	page = get_page_from_freelist(alloc_mask, order, alloc_flags, &ac);
	if (unlikely(!page)) {
		alloc_mask = memalloc_noio_flags(gfp_mask);
		page = __alloc_pages_slowpath(alloc_mask, order, &ac);
	}

	...

	return page;
}

static struct page *
get_page_from_freelist(gfp_t gfp_mask, unsigned int order, int alloc_flags,
						const struct alloc_context *ac)
{
	struct zonelist *zonelist = ac->zonelist;
	struct zoneref *z;
	struct page *page = NULL;
	struct zone *zone;
	nodemask_t *allowednodes = NULL;/* zonelist_cache approximation */
	int zlc_active = 0;		/* set if using zonelist_cache */
	int did_zlc_setup = 0;		/* just call zlc_setup() one time */
	bool consider_zone_dirty = (alloc_flags & ALLOC_WMARK_LOW) &&
				(gfp_mask & __GFP_WRITE);
	int nr_fair_skipped = 0;
	bool zonelist_rescan;

zonelist_scan:
	zonelist_rescan = false;

	// 从zone_list找到合适的zone进行分配
	// 默认优先从 ZONE_HIGHMEM分配，但是 high_zoneidx 指定为0 ZONE_NORMAL，所以这里会从ZONE_NORMAL分配
	for_each_zone_zonelist_nodemask(zone, z, zonelist, ac->high_zoneidx,
								ac->nodemask) {
		unsigned long mark;

		// 检查水平位
		mark = zone->watermark[alloc_flags & ALLOC_WMARK_MASK];
		if (!zone_watermark_ok(zone, order, mark,
				       ac->classzone_idx, alloc_flags)) {

			...
			// 如果当前zone空闲的页面低于水平位，则回收页面 zone_allows_reclaim
			ret = zone_reclaim(zone, gfp_mask, order);

			...
			}
		}

		// 如果空闲页面足够，调用 buffered_rmqueue 从伙伴系统分配页面
try_this_zone:
		page = buffered_rmqueue(ac->preferred_zone, zone, order,
						gfp_mask, ac->migratetype);
		if (page) {
			if (prep_new_page(page, order, gfp_mask, alloc_flags))
				goto try_this_zone;
			return page;
		}
		...
}
```

从伙伴系统中分配
```c
static inline
struct page *buffered_rmqueue(struct zone *preferred_zone,
			struct zone *zone, unsigned int order,
			gfp_t gfp_flags, int migratetype)
{
	unsigned long flags;
	struct page *page;
	bool cold = ((gfp_flags & __GFP_COLD) != 0);

	// 如果需要分配的页面的order为0，即只分配一个page,则从 zone->per_cpu_pages中分配
	if (likely(order == 0)) {
		struct per_cpu_pages *pcp;
		struct list_head *list;

		local_irq_save(flags);
		pcp = &this_cpu_ptr(zone->pageset)->pcp;
		list = &pcp->lists[migratetype];
		if (list_empty(list)) {
			pcp->count += rmqueue_bulk(zone, 0,
					pcp->batch, list,
					migratetype, cold);
			if (unlikely(list_empty(list)))
				goto failed;
		}

		if (cold)
			page = list_entry(list->prev, struct page, lru);
		else
			page = list_entry(list->next, struct page, lru);

		list_del(&page->lru);
		pcp->count--;
	} else {
		// 如果需要分配的页面数量大于1，则调用 __rmqueue 分配
		spin_lock_irqsave(&zone->lock, flags);
		page = __rmqueue(zone, order, migratetype);
		spin_unlock(&zone->lock);
		if (!page)
			goto failed;
		__mod_zone_freepage_state(zone, -(1 << order),
					  get_freepage_migratetype(page));
	}

	// 分配成功后进行一些检查
	__mod_zone_page_state(zone, NR_ALLOC_BATCH, -(1 << order));
	if (atomic_long_read(&zone->vm_stat[NR_ALLOC_BATCH]) <= 0 &&
	    !test_bit(ZONE_FAIR_DEPLETED, &zone->flags))
		set_bit(ZONE_FAIR_DEPLETED, &zone->flags);

	__count_zone_vm_events(PGALLOC, zone, 1 << order);
	zone_statistics(preferred_zone, zone, gfp_flags);
	local_irq_restore(flags);

	VM_BUG_ON_PAGE(bad_range(zone, page), page);
	return page;

failed:
	local_irq_restore(flags);
	return NULL;
}

// __rmqueue -> __rmqueue_smallest
static inline
struct page *__rmqueue_smallest(struct zone *zone, unsigned int order,
						int migratetype)
{
	unsigned int current_order;
	struct free_area *area;
	struct page *page;

	/* Find a page of the appropriate size in the preferred list */
	// 从小order依次遍历，优先从小的内存开始分配，如果不满足则从大的内存切一块
	for (current_order = order; current_order < MAX_ORDER; ++current_order) {
		area = &(zone->free_area[current_order]);
		if (list_empty(&area->free_list[migratetype])) 
			continue; // 如果本order分配完了，则尝试下一个

		page = list_entry(area->free_list[migratetype].next,
							struct page, lru);
		list_del(&page->lru);
		rmv_page_order(page);
		area->nr_free--;
		expand(zone, page, order, current_order, area, migratetype); // 将大块内存切出一块返回为page，剩余的重新加入伙伴系统
		set_freepage_migratetype(page, migratetype);
		return page;
	}

	return NULL;
}

/*
 * page : 被分配的pages，其中包含需要切除的部分
 * low  : 分配的pages的order
 * high : 整个pages的order
 * area : 伙伴池
 */
static inline void expand(struct zone *zone, struct page *page,
	int low, int high, struct free_area *area,
	int migratetype)
{
	unsigned long size = 1 << high; // pages的包含page的数量

	while (high > low) { // 如果还有可以切除的部分，则继续，直到high == low，即pages只剩下需要的数量
		area--;     // 伙伴池退一个
		high--;     // 伙伴池对应的order
		size >>= 1; // 剩余的需要pages数量

		list_add(&page[size].lru, &area->free_list[migratetype]); // 将pages + size 开始，共 1 << high 个page加入伙伴系统 area->free_list
		area->nr_free++;
		set_page_order(&page[size], high);
	}
}
```
![](./pic/44.jpg)

## 释放伙伴系统的内存
free_pages -> _free_pages
```c
void free_pages(unsigned long addr, unsigned int order)
{
	if (addr != 0) {
		__free_pages(virt_to_page((void *)addr), order); // 将虚拟地址转换为page, 调用 __free_pages
	}
}

#define virt_to_page(kaddr)	pfn_to_page(virt_to_pfn(kaddr))

#define virt_to_pfn(kaddr) (__pa(kaddr) >> PAGE_SHIFT)

#define __pa(x)			__virt_to_phys((unsigned long)(x))

void __free_pages(struct page *page, unsigned int order)
{
	if (put_page_testzero(page)) {
		if (order == 0)
			free_hot_cold_page(page, false); // 如果order为0，则做特殊处理
		else
			__free_pages_ok(page, order);  // 如果order>0，则释放到伙伴系统
	}
}


__free_pages_ok -> free_one_page -> __free_one_page
static void __free_pages_ok(struct page *page, unsigned int order)
{
	unsigned long flags;
	int migratetype;
	unsigned long pfn = page_to_pfn(page);

	if (!free_pages_prepare(page, order))
		return;

	migratetype = get_pfnblock_migratetype(page, pfn);
	local_irq_save(flags);
	__count_vm_events(PGFREE, 1 << order);
	set_freepage_migratetype(page, migratetype);
	free_one_page(page_zone(page), page, pfn, order, migratetype); // page_zone(page) 得到zone
	local_irq_restore(flags);
}

// 将pages释放到伙伴系统，并做合并操作
static inline void __free_one_page(struct page *page,
		unsigned long pfn,
		struct zone *zone, unsigned int order,
		int migratetype)
{
	unsigned long page_idx;
	unsigned long combined_idx;
	unsigned long uninitialized_var(buddy_idx);
	struct page *buddy;
	int max_order = MAX_ORDER;

	// (1 << max_order) : 得到 pageblock 有多少个 page
	// pfn & ((1<<max_order) -1) : 等价于 pfn % ( (1 << max_order) - 1) ，相当于将整个内存按pageblock进行划分
	// 求要释放的内存在相关pageblock的下标
	page_idx = pfn & ((1 << max_order) - 1);

	// for (; order < max_order - 1; order++) : 由小内存块到大内存块，如果遇到相邻内存块，则合并，并到下一层再次尝试合并
	while (order < max_order - 1) {
		buddy_idx = __find_buddy_index(page_idx, order); // 见下分析
		buddy = page + (buddy_idx - page_idx);
		if (!page_is_buddy(page, buddy, order)) // 检查buddy是否为空闲内存块, 且buddy的order必须等于page的order
			break;

		// 找到了可以合并的buddy
		
		// 将buddy从free_area中取出
		if (page_is_guard(buddy)) {
			clear_page_guard(zone, buddy, order, migratetype);
		} else {
			list_del(&buddy->lru);
			zone->free_area[order].nr_free--;
			rmv_page_order(buddy);
		}

		// 进行合并, 假设order为 1, 则 1<<order 为 0b0010
		// 如果 page_idx : 0b0010 (2), 则 buddy_idx : 0b0000 (0), 则 combined_idx为 0b0000 (0)
		// 如果 page_idx : 0b0100 (4), 则 buddy_idx : 0b0110 (6), 则 combined_idx为 0b0100 (4)
		combined_idx = buddy_idx & page_idx;
		page = page + (combined_idx - page_idx);
		page_idx = combined_idx;
		order++; // order增加，标志着pages变大了
	}
	set_page_order(page, order); //修改page的order，让他代表大的内存

	if ((order < MAX_ORDER-2) && pfn_valid_within(page_to_pfn(buddy))) {
		struct page *higher_page, *higher_buddy;
		combined_idx = buddy_idx & page_idx;
		higher_page = page + (combined_idx - page_idx);
		buddy_idx = __find_buddy_index(combined_idx, order + 1);
		higher_buddy = higher_page + (buddy_idx - combined_idx);
		if (page_is_buddy(higher_page, higher_buddy, order + 1)) {
			list_add_tail(&page->lru,
				&zone->free_area[order].free_list[migratetype]);
			goto out;
		}
	}

	// 将合并出的新pages，添加到对应的链表
	list_add(&page->lru, &zone->free_area[order].free_list[migratetype]);
out:
	zone->free_area[order].nr_free++;
}

/*
 * Locate the struct page for both the matching buddy in our
 * pair (buddy1) and the combined O(n+1) page they form (page).
 *
 * 1) Any buddy B1 will have an order O twin B2 which satisfies
 * the following equation:
 *     B2 = B1 ^ (1 << O)
 * For example, if the starting buddy (buddy2) is #8 its order
 * 1 buddy is #10:
 *     B2 = 8 ^ (1 << 1) = 8 ^ 2 = 10
 *
 * 2) Any buddy B will have an order O+1 parent P which
 * satisfies the following equation:
 *     P = B & ~(1 << O)
 *
 * Assumption: *_mem_map is contiguous at least up to MAX_ORDER
 * 详细分析见下面
 */

static inline unsigned long
__find_buddy_index(unsigned long page_idx, unsigned int order)
{
	return page_idx ^ (1 << order);
}

static inline int page_is_buddy(struct page *page, struct page *buddy,
							unsigned int order)
{

	// 检查buddy是否为空闲内存块
	// PageBuddy(page) 确定page是否空闲
	// page_order(buddy)确定大小
	if (PageBuddy(buddy) && page_order(buddy) == order) {
		/*
		 * zone check is done late to avoid uselessly
		 * calculating zone/node ids for pages that could
		 * never merge.
		 */
		if (page_zone_id(page) != page_zone_id(buddy))
			return 0;

		return 1;
	}
	return 0;
}
```

### __find_buddy_index分析
考虑order为1的情况
![](./pic/45.jpg)
page[0-1] 和 page[2-3]互为伙伴，page[4-5]和page[6-7]互为伙伴
所以得出结论：
buddy_idx = page_index + 2^order
buddy_idx = page_index - 2^order
从二进制看，可以得到另一个规律
![](./pic/46.jpg)
0 和 4 之间增加或减少一个 1<<order就得到对方的index，其他同理，

| page_idx的第order位 | buddy_idx的第order位 |
| -----------------   | ------------------   |
| 0                   | 1                    |
| 1                   | 0                    |

所以已知page_indx求其buddy_idx，只需要对page_indx的order进行对(1<<order)异或 
```c
static inline unsigned long
__find_buddy_index(unsigned long page_idx, unsigned int order)
{
	return page_idx ^ (1 << order);
}
```

### 合并的讨论
![](./pic/47.jpg)

## 特殊处理释放order为0的page

zone->pageset为每个CPU初始化一个percpu变量struct per_cpu_pageset. 当释放order为0的page时，释放到per_cpu_page->list对应的链表中。
```c
void free_hot_cold_page(struct page *page, bool cold /*false*/)
{
	struct zone *zone = page_zone(page);
	struct per_cpu_pages *pcp;
	unsigned long flags;
	unsigned long pfn = page_to_pfn(page);
	int migratetype;

	pcp = &this_cpu_ptr(zone->pageset)->pcp;
	if (!cold)
		list_add(&page->lru, &pcp->lists[migratetype]);
	else
		list_add_tail(&page->lru, &pcp->lists[migratetype]);
	pcp->count++;
	// 如果per_cpu_pages的页面数量大于high水平位，则释放到伙伴系统
	// 一次释放batch个页面
	if (pcp->count >= pcp->high) {
		unsigned long batch = ACCESS_ONCE(pcp->batch);
		free_pcppages_bulk(zone, batch, pcp);
		pcp->count -= batch;
	}

out:
	local_irq_restore(flags);
}
```

```c
struct per_cpu_pages {
	int count;		// 当前zone 中per_cpu_pages的页面数量
	int high;		// 当per_cpu_pages的页面数量高于high水平位，会回收到伙伴系统
	int batch;		// 一次回收到伙伴系统的页面数量

	/* Lists of pages, one per migrate type stored on the pcp-lists */
	struct list_head lists[MIGRATE_PCPTYPES];
};

struct per_cpu_pageset {
	struct per_cpu_pages pcp;
};

```

从per_cpu_pages释放到伙伴系统
```c
static void free_pcppages_bulk(struct zone *zone, int count,
					struct per_cpu_pages *pcp)
{
	int migratetype = 0;
	int batch_free = 0;
	int to_free = count;
	unsigned long nr_scanned;

	spin_lock(&zone->lock);
	nr_scanned = zone_page_state(zone, NR_PAGES_SCANNED);
	if (nr_scanned)
		__mod_zone_page_state(zone, NR_PAGES_SCANNED, -nr_scanned);

	while (to_free) {
		struct page *page;
		struct list_head *list;

		do {
			batch_free++;
			if (++migratetype == MIGRATE_PCPTYPES)
				migratetype = 0;
			list = &pcp->lists[migratetype];
		} while (list_empty(list));

		/* This is the only non-empty list. Free them all. */
		if (batch_free == MIGRATE_PCPTYPES)
			batch_free = to_free;

		do {
			int mt;	/* migratetype of the to-be-freed page */

			page = list_entry(list->prev, struct page, lru);
			/* must delete as __free_one_page list manipulates */
			list_del(&page->lru);
			mt = get_freepage_migratetype(page);
			if (unlikely(has_isolate_pageblock(zone)))
				mt = get_pageblock_migratetype(page);

			/* MIGRATE_MOVABLE list may include MIGRATE_RESERVEs */
			__free_one_page(page, page_to_pfn(page), zone, 0, mt); // 依旧调用 __free_one_page，解释同上
			trace_mm_page_pcpu_drain(page, 0, mt);
		} while (--to_free && --batch_free && !list_empty(list));
	}
	spin_unlock(&zone->lock);
}
```
