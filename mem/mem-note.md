# 0.背景知识
## 0.1 硬件
SRAM : 硬件复杂，成本高，CPU通过A0-A18个地址线一次输入要访问的地址，就能获得数据，所以CPU能直接访问
DDR SRAM: 硬件简单，成本低，但CPU需要通过a0-a10地址线多次输入地址，先输入行地址，再输入列地址，才获得数据，由于有时序问题，所以用sdram控制器实现，cpu不能直接访问。

## 0.2 内存管理的目的
不仅是回收未使用内存，
是减少内存碎片，否则分配大片内存时会失败。

# 1. 物理内存的管理
## 1.1 物理分区
![](./pic/1.jpg)
linux将物理内存分为多个区，
ZONE_NORMAL : 操作系统可以直接映射到虚拟地址空间的物理页面，这些页面可以被操作系统直接访问和操作
ZONE_HIGHMEM: 无法直接映射到虚拟地址空间的物理页面，无法直接访问，只能通过如临时内存映射等方式访问
注意：当系统物理空间不足1GB，内核会将所有物理空间视为ZONE_NORMAL，当超过1GB，则出现ZONE_HIGHMEM。

## 1.2 node zone page
抽象出3个类型描述和使用内存
struct node : 表示一定数量的物理内存资源和处理器，允许多个处理器访问共享内存。可理解为多个物理内存条。
struct zone : 表示连续的物理内存区域，包含多个页。按照不同的使用目的，内存被划分成不同的zone，方便管理
struct page : 表示一个物理内存页，通常是4KB或更大的固定大小。

### 1.2.1 struct page 
struct page 表示物理内存页面的信息，每个物理页面对应着一个 struct page 结构体。

物理页面是指系统中的一段连续物理内存，通常是4KB或更大的固定大小。

struct page 包含了描述一个物理页面的各种信息，包括页面的状态、页面的属性、页面的使用情况等。此外，该结构体中还包含了指向该页面所属的内存区域（zone）、页面的引用计数（count）、页面的标志（flags）等重要字段。

在实际的内存管理过程中，操作系统使用 struct page 来管理系统中所有的物理页面，包括分配、释放、映射到虚拟地址等。

```c
struct page *mem_map;
EXPORT_SYMBOL(mem_map);
```
每个zone都有一个mem_map 指向struct page数组，管理此zone下所有物理页。

page数组的索引号称为物理页帧号pfn。通过pfn可以获得物理页的地址
```c
// 如果一个页大小为4KB，则PAGE_SHIFT 为12

pfn = paddr >> PAGE_SHIFT;

#define __pfn_to_phys(pfn)    ((unsigned long long)(pfn) << PAGE_SHIFT)
#define pfn_to_phys(pfn)      __pfn_to_phys(pfn)

unsigned long long phys_addr = pfn_to_phys(pfn);
```

pfn和mem_map数组下标的关系
注意：每个zone和独立的mem_map数组，而pfn是将多个zone合并成一个数组的下标。
所以对于 ZONE_NORMAL 的mem_map 和 pfn的关系为
```c
// pfn 减去 ZONE_NORMAL 的起始页帧号，得到pfn对应的 mem_map 的下标
struct page *page = &mem_map[pfn - zone->zone_start_pfn];
```

pfn和page的转换
```c
#include <linux/mm.h>

struct page *pg = pfn_to_page(pfn);
unsigned int pfn = page_to_pfn(page);
```

### 1.2.2 如何从node到page
![](./pic/2.jpg)
```c
// node 中有关内存资源使用对应的 pglist_data 描述
typedef struct pglist_data {
	struct zone node_zones[MAX_NR_ZONES];
	struct zonelist node_zonelists[MAX_ZONELISTS];
	...
};
```

```c
struct zone {
	...
	struct free_area	free_area[MAX_ORDER];
	...
};

struct free_area {
	struct list_head	free_list[MIGRATE_TYPES];
	unsigned long		nr_free;
};
```

## 1.3 伙伴系统 
伙伴系统用于物理页的分配的释放。
![](./pic/3.jpg)
物理内存依旧按照frame page划分成固定大小的页，每个frame page都有一个page和其对应。
为了减少内存碎片，将page按不同大小合并成大页。
最小的是 2^0 也就是一个page大小，然后是 2^1 * page 大小，最后是 2^(MAX_ORDER-1)\*page大小
分配：分配内存时会尽可能使用小内存块，比如分配4KB内存，但发现2^2对应的链表依旧分配完了，就从2^3链表取一块进行拆分，加入2^2完成分配。
释放：用户释放内存后，根据内存大小加入对应的链表，然后尽可能进行合并，系统会检查是否有相邻物理地址内存块，有则进行合并，并移到上级链表。


### 1.3.1 迁移类型
![](./pic/4.jpg)
![](./pic/5.jpg)
每个zone都维护一个伙伴系统
每个数组元素有一个元素为链表的数组，分为三种类型的链表 movable 可移动(如应用程序动态分配的内存)，unmovable 不可移动（如内核的物理内存），reclaimable 可回收（如文件的页缓存）。比如.text对应的内存就应该从 unmovable中分配。

```c
struct page {
   unsigned long private; // page的大小，2^0, 2^1 之类，
                          // 由于buddy中一块内存可能又多个page合并构成，
                          // 返回给用户首个page，
                          // 使用private告诉用户此块内存的大小

   atomic_t _mapcount;    // 是否被虚拟地址映射
                          // 可用于判断此page是否被分配了

   atomic_t _refcount;
};
```

### 1.3.2 zone的三种页缓存
```c
struct zone {
	...
	long lowmem_reserve[MAX_NR_ZONES];
	struct per_cpu_pages	__percpu *per_cpu_pageset;
	struct free_area	free_area[MAX_ORDER];
	...
};
```
对于一个物理内存条，使用node描述，node分为多个zone分别管理，一个zone有三个变量存放page

lowmem_reserve:表示该内存区域中为了避免低内存条件而保留的页数，这些页不能被用户进程或内核缓存使用，只有在系统高负载时才会释放出来。
pageset ： 表示每个 CPU 上的本地页管理器，它包含了用于分配和释放页面的数据结构，以及用于记录该 CPU 上的页面使用情况的变量。
free_area : cpu共享的内存分配区域，使用伙伴系统管理.

这些页缓存都在系统初始化时分配好，等待被使用。
当进程分配内存时，首先从当前CPU的per_cpu_pageset中查找是否有可用的页面，如果找到，直接从本地per_cpu_pageset中分配页面，从而避免不同CPU之间锁竞争。如果当前CPU的per_cpu_pageset中没有可用页面，则尝试从当前zone的free_area中分配页面，如果当前zone的free_area中也没有可用页面，则到其他zone分配页面。


```c
struct per_cpu_pages {
	...
	// 每个元素都是双向链表，每个链表对应一种页面大小，每个链表包含多个struct page。
	struct list_head lists[NR_PCP_LISTS];
};
```

#### per-cpu的意义
![](./pic/6.jpg)
![](./pic/7.jpg)
即使是单线程进程，也可能存在多CPU之间的竞争。这是因为多CPU核心在同时执行相同的代码时，会共享同一个内存空间。当多个CPU核心尝试访问和修改同一个内存位置时，就会产生竞争条件。

例如，在一个多CPU核心的系统上，如果一个进程在使用全局变量时不加同步机制，那么多个CPU核心就会在同时尝试对该变量进行读写操作，这就会导致竞争条件。此时，由于每个CPU核心都有自己的缓存，不同的CPU核心可能会缓存相同的变量值，导致数据不一致性。

因此，在多CPU环境下，需要采取同步机制（如锁、原子操作、memory barrier等）来保证多个CPU核心之间的互斥访问和数据一致性，避免竞争条件的发生。

将线程绑定到单个CPU可以解决一些CPU之间竞争条件，但可能无法充分利用系统并发性能。

如果使用per_cpu，对同个变量符号，每个CPU都有一个此变量的副本独立存在于内存中，每个CPU运行时只访问自己的变量，从而保证缓存和内存的值一定同步，避免了竞争。

```c
#include <linux/percpu.h>

struct vector {
    int x;
    int y;
    int z;
};

// 有几个CPU就会定义几个 private_vector 变量
DEFINE_PER_CPU(struct vector, private_vector);

void vector_add(struct vector *result, const struct vector *a, const struct vector *b)
{
    result->x = a->x + b->x;
    result->y = a->y + b->y;
    result->z = a->z + b->z;
}

int main()
{
    int i, num_cpus = num_online_cpus();
    struct vector a = {1, 2, 3};
    struct vector b = {4, 5, 6};
    struct vector sum = {0, 0, 0};

    for (i = 0; i < num_cpus; i++) {
        __get_cpu_var(private_vector).x = i; // 每个cpu访问自己的private_vector
        vector_add(&__get_cpu_var(private_vector), &a, &b);
        sum.x += __get_cpu_var(private_vector).x;
        sum.y += __get_cpu_var(private_vector).y;
        sum.z += __get_cpu_var(private_vector).z;
        __put_cpu_var(private_vector);
    }

    printk(KERN_INFO "sum = (%d, %d, %d)\n", sum.x, sum.y, sum.z);

    return 0;
}
```
如果不使用per_cpu，则访问变量时需要获得锁，导致性能降低。

### 1.3.3 伙伴系统的接口
```c
struct page *alloc_pages(gfp_t gfp, unsigned int order);
```
用于申请一块2^order的连续物理内存块
内核内存环境良好，直接进行快速分配
当前内存环境恶劣时，进入慢分配流程，慢分配时可能会进行页内存的迁移，合并等以获得需求大小的struct page.

### 1.3.4 CMA
伙伴系统有个缺点，即最大分配的struct page有限，如 MAX_ORDER 为 11，则最大为 2^11 = 4MB.

如果希望申请大于4MB的内存，需要在初始化时保留一大块内存，等待驱动使用。但当驱动没有使用时，这大块内存被闲置。

为了解决上面问题，内核实现了CMA机制，当内存空闲时，空闲的内存加入伙伴系统，可用于小内存的分配。当驱动等使用CMA分配大块内存时，保证能分配大块连续内存（若已被分配用于小内存，则会进行内存迁移）。

![](./pic/8.jpg)

在内存初始化时，专门划分一大块区域用作CMA。

空闲时CMA调用cma_release将内存加入伙伴系统的特定链表，每个节点对应的内存大小为 2^MAX_ORDER。
伙伴系统可以将CMA链表的内存进行拆分加入小页链表，以给用户分配。但是有个限制，即用户分配的内存必须是 movable，因为当CMA需要大块内存分配时，可能需要内存迁移。

当CMA分配大块内存时，调用 cma_alloc从伙伴系统中回收内存。

在设备树或内存配置时指定保留多大空间做cma
```dts
    reserved-memory {
        #address-cells = <1>;
        #size-cells = <1>;
        ranges;

        /* Chipselect 3 is physically at 0x4c000000 */
        vram: vram@4c000000 {
            /* 8 MB of designated video RAM */
            compatible = "shared-dma-pool";
            reg = <0x4c000000 0x00800000>;
            no-map;
        };
    };

```

```c
struct cma {
	unsigned long   base_pfn;
	unsigned long   count;
	unsigned long   *bitmap;
	unsigned int order_per_bit; /* Order of pages represented by one bit */
	spinlock_t	lock;
	char name[CMA_MAX_NAME];
};

#define MAX_CMA_AREAS	(1 + CONFIG_CMA_AREAS)
extern struct cma cma_areas[MAX_CMA_AREAS];
extern unsigned cma_area_count;

```

![](./pic/9.jpg)
cma_area : 指向整个cma空间。
base_pfn : 可以找到对应物理地址
count : CMA区域可以分配的最大页面数量（即可用的物理页面数）
order_per_bit : 表示每个位可表示的页面指数。

bitmap : CMA分配情况

bitmap 和 order_per_bit ，若order_per_bit为0，则占用2^0即一个bit位，若为2，则占用2^2即占用4个bit。每个bit位都对应一个页块（如4MB）


### 1.3.5 伙伴系统的初始化
#### memblock
##### memblock的初始化
物理内存有些会被保留，不参与伙伴系统内存分配，比如：内核镜像(.init段除外)，dtb，u-boot(reboot时会被调用)，页表，GPU，camera，音视频编解码，dtb设置为reserved的区域（CMA除外）
![](./pic/10.jpg)

要初始化伙伴系统，首先需要区分哪些内存可用于伙伴系统，哪些内存被保留。
memblock是全局变量，其memory属性记录可用于伙伴系统的内存块，reserved属性记录被保留的内存块。
通过 memblock_add，memblock_remove给 memblock.memory添加删除内存块。
通过 memblock_reserve，memblock_free给 memblock.reserved添加删除保留块
```c
  int __init_memblock memblock_add(phys_addr_t base, phys_addr_t size)

  int __init_memblock memblock_remove(phys_addr_t base, phys_addr_t size)

  int __init_memblock memblock_reserve(phys_addr_t base, phys_addr_t size)

  void __init_memblock memblock_free(void *ptr, size_t size)
```

```c
setup_arch
   setup_machine_fdt
      early_init_dt_scan
         early_init_dt_scan_memory
            遍历设备树memory节点，从reg属性获得base,size
            early_init_dt_add_memory_arch(base, size)
               memblock_add_node(base, size, 0, MEMBLOCK_NONE)
                  memblock_add_range(&memblock.memory, base, size, nid, flags) // 将可分配的内存信息加入 memblock.memory

   arm_memblock_init
      early_init_fdt_scan_reserved_mem  // 将保留内存信息加入 memblock.reserved
```

```dts
memory@80000000 {
	device_type = "memory";
	reg = <0 0x80000000 0 0x40000000>;
};

reserved-memory {
	#address-cells = <2>;
	#size-cells = <2>;
	ranges;

	/* Chipselect 2 is physically at 0x18000000 */
	vram: vram@18000000 {
		/* 8 MB of designated video RAM */
		compatible = "shared-dma-pool";
		reg = <0 0x18000000 0 0x00800000>;
		no-map;
	};
};
```
初始化后，memblock_memory_init_regions 和 memblock_reserved_init_regions 分别保留可分配和保留信息
![](./pic/11.jpg)

##### memblock 释放内存给伙伴系统
memblock.memory获得可用的内存信息，使用 free_page 添加到伙伴系统
```c
mm_init
   mem_init
   memblock_free_all // 将memblock.memory 记录的内存释放到伙伴系统
      free_low_memory_core_early
         for_each_free_mem_range(i, NUMA_NO_NODE, MEMBLOCK_NONE, &start, &end,
                  NULL)  // memblock.memory 数组获得每个节点的 start, end
             __free_memory_core(start, end);
                __free_pages_memory(start_pfn, end_pfn); // 将地址转换位页号
                   memblock_free_pages(pfn_to_page(start), start, order); // 由页号得到 page
                      __free_pages_core(page, order);

                         __free_pages_ok(page, order, FPI_TO_TAIL | FPI_SKIP_KASAN_POISON);
                            migratetype = get_pfnblock_migratetype(page, pfn);  // 获得可移动属性
                            __free_one_page(page, pfn, zone, order, migratetype, fpi_flags);  //加入伙伴系统
```

#### CMA
在dts中，如果reserved的内存节点有类似属性，则不会被释放给伙伴系统
```dts
removed-dma-pool "linux,dma-default";
no-map
```
如果有如下属性，则会被释放给伙伴系统
```dts
shared-cma-pool "linux,cma-default";
reuse
```

```c
do_initcalls
   for (i = 0; i < cma_area_count; i++) //遍历CMA数组，将每个CMA区域都释放给伙伴系统
      cma_activate_area(&cma_areas[i]);
         cma->bitmap = bitmap_zalloc(cma_bitmap_maxno(cma), GFP_KERNEL);  // 准备bitmap表用于记录有哪些内存释放给了伙伴系统，方便CMA需要时会让伙伴系统归还
         for (pfn = base_pfn; pfn < base_pfn + cma->count;
             pfn += pageblock_nr_pages)
             init_cma_reserved_pageblock(pfn_to_page(pfn));      // 以pageblock为单位释放内存
                set_pageblock_migratetype(page, MIGRATE_CMA); // 将此页标记为CMA类型
                __free_pages(page, pageblock_order);  // 释放page，将page添加到pageblock_order的链表上
```
#### .init段
```c
rest_init
   kernel_init
      free_initmem
         free_initmem_default
            extern char __init_begin[], __init_end[];
            free_reserved_area(&__init_begin, &__init_end,
                     poison, "unused kernel image (initmem)");

               start = (void *)PAGE_ALIGN((unsigned long)start);
               for (pos = start; pos < end; pos += PAGE_SIZE, pages++) {  // 以page为单位释放到伙伴系统
                  struct page *page = virt_to_page(pos);
                  free_reserved_page(page);
                         __free_page(page);
               }
               pr_info("Freeing %s memory: %ldK\n", s, K(pages));
]
```
### 1.3.4 slab
伙伴系统有个缺点：最小分配内存大小为一个页。
为了适合小内存的申请释放，实现了 slab缓存。
slab是从伙伴系统申请一页（一个page或多个page大小），将一页内存分成相同大小的内存块，如32B的slab每个内存块为32B，64Bslab每个内存块大小为64B。
当用户申请小内存时，按照申请的大小到对应的slab缓存中获得内存块，
当用户释放内存时，按照内存大小释放到对应的slab。

比如task_struct是常用的类型，那么可以对task_struct构造一个slab，slab块的大小为64B。
![](./pic/12.jpg)

slab各个版本
slab: 老版本实现
slob: 轻量级slab
slub: 对slab的重新实现

#### slab的实现原理
核心三个类型：
kmem_cache, kmem_cache_node, kmem_cache_cpu
kmem_cache，相同大小的slab由同个kmem_cache管理
kmem_cache_node，这时一个元素为指针的数组，除了服务器外通常只有一个元素
kmem_cache_cpu，使用\_\_percpu修饰，每个cpu有单独的一份拷贝。

当用户申请slab时，根据申请大小到对应的kmem_cache，如果希望多cpu访问则从 kmem_cache_node分配，否则从kmem_cache_cpu分配。

空闲的slab由free_list管理，分配时，将首个节点返回给用户，并将free_list指向下一个节点即可。一个slab的申请完了，就移动free_list到下一个slab，如果所有slab都用完了，就从伙伴系统分配一个page构造成 slab。
![](./pic/13.jpg)

#### slab的接口
```c
创建和销毁 kmem_cache
kmem_cache_create
kmem_cache_destory

从 kmem_cache 分配一个obj
kmem_cache_alloc
释放 obj到 kmem_cache
kmem_cache_free
```

### 1.3.5 kmalloc
kmalloc是基于伙伴系统和slab实现的，当申请的内存大则从伙伴系统，小则走slab。

# 2. 虚拟地址 
## 2.1 虚拟地址和MMU
![](./pic/14.jpg)
当cpu开启MMU后，虚拟地址被转换成物理地址，发给SDRAM

为什么一定要虚拟地址：
Linux环境太复杂，连接器无法在链接节点知道程序的加载地址，所以假定程序都从0地址开始。那么不同进程的地址就重叠了，所以需要运行将链接的地址映射到不同的物理地址。

### 2.1.1 MMU的工作原理
![](./pic/15.jpg)
MMU的映射是以页为单位
页表：虚拟地址和物理地址的映射关系表，保存在内存中。
Table Walk Unit：读取页表的硬件，当转换虚拟地址时，他会读取对应的页表
TLBs：页表缓存，由于读取内存太非时间，当转换一个地址时会将附件地址的页表也加载在MMU的TLBs

有个寄存器保存了页表的地址。
当输入虚拟地址和ASSID给MMU，ASSID用于解决不同进程相同虚拟地址的情况，
MMU首先在缓存中查找释放有对应虚拟地址号和ASSID相同的条目，如果有则直接返回物理地址。
如果没有在TLB中找对应的物理地址基地址，若找到返回物理地址，
如果没有则根据寄存器加载内存中的页表，并缓存相邻页表。并返回物理地址
![](./pic/24.jpg)


## 2.3 页表
### 2.3.1 一级页表
![](./pic/16.jpg)
虚拟地址分为两段:
[31:12] 20位 虚拟页表号: 所以能表示2\^20 = 1M个页表，每个页表对应4KB大小的物理页，所以能映射4GB的物理地址。
[11:0]  12位 页内偏移。
首先根据 虚拟地址第一段 虚拟页表号作为索引，寄存器TIBRx存储了页表的首地址，有索引和首地址就得到物理页号，从而找到了物理页，再加上虚拟地址第二段页内偏移做物理页页内偏移。就得到物理地址。


一级页表有个致命问题：
页表太大，如上为 1M个页表项，一个页表项如果为4B，则为4MB，每个进程都有自己的页表，1K个进程则需要4GB的物理内存存储页表。
所以实际环境不存在一级页表.

### 2.3.2 二级页表
![](./pic/17.jpg)
二级页表的虚拟地址分为三段：
一级页表号[20-31]: 12位，4K个一级页表项
二级页表号[12-19]: 8位，256个二级页表项
页内偏移[0-12]：12位，最大偏移4K，也就是一个物理页的大小。

4K \* 256 \* 4K = 4GB ，所以二级页表也能表示4GB虚拟地址，映射4GB物理地址。
由于二级页表只有一级表需要预先分配，二级表用时才分配，所以一个进程的页表占用内存为 16KB 多点。
而且二级页表中二级表可以分散到物理内存，所以不需要占用连续的物理内存。

![](./pic/18.jpg)

### 2.3.3 段表
![](./pic/19.jpg)
段表类似于一级页表，但是每项映射1MB空间。
使用段表时，虚拟地址分为两段：
[31:20] 索引段表项，段表项记录物理段地址
[19:0]  段内偏移

段表格式
![](./pic/20.jpg)

### 2.3.4 ARM下页表段表
![](./pic/21.jpg)
![](./pic/22.jpg)


### 2.3.5 页表相关代码分析
#### 2.3.5.1 linux和虚拟地址
查看linux的链接脚本

arch/arm/boot/vmlinux.lds
```lds
{
  /DISCARD/ : {
    *(.discard) *(.discard.*) *(.modinfo) *(.gnu.version*)
    *(.ARM.exidx*)
    *(.ARM.extab*)
    *(.note.*)
    *(.rel.*)
    *(.data)
  }
  . = 0;
  ...
```

arch/arm/boot/vmlinux.lds
```lds
OUTPUT_ARCH(arm)
ENTRY(stext)
jiffies = jiffies_64;
SECTIONS
{
 /DISCARD/ : {
  *(.ARM.exidx.exit.text) *(.ARM.extab.exit.text) *(.ARM.exidx.text.exit) *(.ARM.extab.text.exit) *(.exitcall.exit) *(.discard) *(.discard.*) *(.modinfo) *(.gnu.version*)
 }
 . = ((0x80000000)) + 0x00008000;
```

可见对于 zImage 使用地址无关码运行。
vmlinux 使用虚拟地址运行。

所以linux的地址无关码部分必须构建页表，并开启MMU。

再看物理地址
arch/arm/boot/dts/vexpress-v2p-ca9.dts
```dts
	memory@60000000 {
		device_type = "memory";
		reg = <0x60000000 0x40000000>;
	};

	reserved-memory {
		#address-cells = <1>;
		#size-cells = <1>;
		ranges;

		/* Chipselect 3 is physically at 0x4c000000 */
		vram: vram@4c000000 {
			/* 8 MB of designated video RAM */
			compatible = "shared-dma-pool";
			reg = <0x4c000000 0x00800000>;
			no-map;
		};
	};
```
可见，物理地址从 0x60000000 - 0xa0000000,  共 1GB

#### 2.3.5.2 段映射
为了让kernel可运行，再head.S进行段映射。
段映射原理如下
![](./pic/23.jpg)

```asm
__turn_mmu_on_loc:
	.long	.                  @ __turn_mmu_on_loc的虚拟地址
	.long	__turn_mmu_on      @ __turn_mmu_on虚拟地址
	.long	__turn_mmu_on_end  @ __turn_mmu_end虚拟地址

	...

	bl	__create_page_tables   @ 建立段表
/*
 * Setup the initial page tables.  We only setup the barest
 * amount which are required to get the kernel running, which
 * generally means mapping in the kernel code.
 *
 * r8 = phys_offset, r9 = cpuid, r10 = procinfo
 *
 * Returns:
 *  r0, r3, r5-r7 corrupted
 *  r4 = physical page table address
 */

__create_page_tables:
	pgtbl	r4, r8				@ page table address

	/*
	 * Clear the swapper page table
	 * 清零页表
	 */
	mov	r0, r4               @ r0 指向页表开始
	mov	r3, #0
	add	r6, r0, #PG_DIR_SIZE @ r6 指向页表结尾
1:	str	r3, [r0], #4         @ 写4字节数据到r0指向的内存，r0 += 4
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	teq	r0, r6
	bne	1b

	/*
	 * r7存放mmu flags
	 */
	ldr	r7, [r10, #PROCINFO_MM_MMUFLAGS] @ mm_mmuflags

	/*
	 * Create identity mapping to cater for __enable_mmu.
	 * This identity mapping will be removed by paging_init().
	 * 建立对等映射，准备开启MMU
	 * 开启MMU后，使用虚拟地址，意味着必须要提供有效的页表
	 * 所以在开启MMU前需要设置页表，开启MMU的代码的物理地址等于
	 * 虚拟地址，也就是对等映射
	 */
	adr	r0, __turn_mmu_on_loc @ r0存放__turn_mmu_on_loc的物理地址

	ldmia	r0, {r3, r5, r6} @ 从r0指向的内存依次写入寄存器r3,r5,r6
                             @ r3 : __turn_mmu_on_loc的虚拟地址
                             @ r5 : __turn_mmu_on虚拟地址
                             @ r6 : __turn_mmu_on_end 虚拟地址

	sub	r0, r0, r3          @ r0 = r0 - r3
                            @ virt->phys offset
                            @ r0 存放 __turn_mmu_loc物理地址减去 __turn_mmu_loc 虚拟地址 得到的偏移值

	add	r5, r5, r0          @ phys __turn_mmu_on
	add	r6, r6, r0          @ phys __turn_mmu_on_end

	mov	r5, r5, lsr #SECTION_SHIFT  @ r5=r5>>20
                                    @ 得到物理基地址
                                    @ 对等映射：将物理地址当成虚拟地址
                                    @ 虚拟地址>>20 得到 页表索引号

	mov	r6, r6, lsr #SECTION_SHIFT  @ r6=r6>>20
                                    @ 得到物理基地址
                                    @ 对等映射：将物理地址当成虚拟地址
                                    @ 虚拟地址>>20 得到 页表索引号

1:	orr	r3, r7, r5, lsl #SECTION_SHIFT  @ flags + kernel base
                                        @ r3 = r7 | r5<<20
                                        @ 将物理基地址做高位，位或上mmu flags 得到填充页表的值

	str	r3, [r4, r5, lsl #PMD_ORDER]    @ identity mapping
                                        @ 将r3页表项值填充到页表
                                        @ 页表的地址计算：
                                        @     r4 + r5<<2
                                        @     页表基地址 + 页索引号 * 4   得到页表项地址
                                        @     之所以乘以4，是因为一个页表项占4字节

	cmp	r5, r6              @ 比较当前页表号和结束页表号
	addlo	r5, r5, #1      @ next section
                            @ 当r5 < r6 时，r5 = r5+1 , 也就是r5为下一个页表号

	blo	1b                  @ 当r5 < r6 时，循环

	/*
	 * Map our RAM from the start to the end of the kernel .bss section.
	 * 映射kernel镜像
	 */
	add	r0, r4, #PAGE_OFFSET >> (SECTION_SHIFT - PMD_ORDER) @ r0为kernel的起始页的地址
                                                            @ 因为第一个页号被对等映射占据，
                                                            @ 所以kernel的从第二个页开始
                                                            @ r0 = 页表基地址 + 第二个页的偏移地址

	ldr	r6, =(_end - 1)     @ kernel的虚拟地址的结束地址

	orr	r3, r8, r7          @ r8:kernel镜像物理起始地址的基地址
                            @ r3 = phys_offset | mmu flags

	add	r6, r4, r6, lsr #(SECTION_SHIFT - PMD_ORDER)  @ 得到镜像虚拟结束地址对应的页的地址
                                                      @ 将 r6 >> (20 - 2) 可以理解为
                                                      @ (r6 >> 20) * 4
                                                      @ 首先将虚拟地址右移20位，得到页号
                                                      @ 再将页号乘以 4 得到偏移地址
                                                      @ 将页表基地址加上偏移地址得到结束页的地址

1:	str	r3, [r0], #1 << PMD_ORDER             @ 将物理基地址和mmu flags写道对应页表项       
                                              @ 将 *r0 = r3 ,写4B
                                              @ r0 += 4

	add	r3, r3, #1 << SECTION_SHIFT           @ 增加物理基地址 
	                                          @ 1 << 20 位保证只对物理基地址增加，不修改mmc flags

	cmp	r0, r6       @ 比较当前页表项地址和镜像的结束页表项地址 
	bls	1b           @ 如果 r0 < r6 循环
```

## 2.4 虚拟空间管理
![](./pic/25.jpg)
用户空间和内核空间的比例是可调整的，menuconfig 时设置 PAGE_OFFSET
可以是 3:1 , 2:2 , 1:3 ...
增加内核空间，就能尽可能让内核使用线性映射，而非vmalloc，vmalloc的效率低。


![](./pic/26.jpg)
kernel对虚拟空间的管理不是全部都按照线性映射，而是分区管理，各个区的管理方式不同。

### 2.4.1 对线性映射区的管理
* 线性映射区的划分
![](./pic/27.jpg)
PAGE_OFFSET : 用于划分用户空间和内核空间，0+PAGE_OFFSET 得到内核空间的起始地址
PHYS_OFFSET : 内存在物理地址的偏移，0 + PHYS_OFFSET 得到物理内存的起始地址

把线性映射区映射的物理内存称为低端内存，剩余的物理内存称为高端内存。

内核有如下方法用于线性映射区物理地址和虚拟地址之间的转换
```c
static inline phys_addr_t __virt_to_phys_nodebug(unsigned long x)
{
	return (phys_addr_t)x - PAGE_OFFSET + PHYS_OFFSET;
}

static inline unsigned long __phys_to_virt(phys_addr_t x)
{
	return x - PHYS_OFFSET + PAGE_OFFSET;
}
```

* 线性映射区与高端内存的大小
由于线性映射区，虚拟地址和物理地址的转换只存在一个偏移值，特别高效，
所以应该尽可能将内核的虚拟空间作为线性映射区，kmalloc申请的虚拟空间都是线性映射区的，

随着物理内存增大，线性映射区增大，但线性映射区有个上限，因为虚拟空间有限，需要留vmalloc和特殊映射区，
最少需要给 vmalloc 和 特殊映射区留 240MB。
所以当PAGE_OFFSET划分位：
3GB/1GB: [3G, 3G + 764MB] 为线性映射
2GB/2GB: [2G, 2G + 1764MB] 为线性映射
对于64位操作系统，虚拟空间足够大，所有物理内存都划分位线性映射，不存在高端内存。

内核确定高端内存和低端内存
```c
phys_addr_t arm_lowmem_limit __initdata = 0;

void __init adjust_lowmem_bounds(void)
	vmalloc_limit = (u64)(uintptr_t)vmalloc_min - PAGE_OFFSET + PHYS_OFFSET; // vmalloc_min : vmalloc和线性映射的最小边界
	                                                                         // 将其映射到物理地址
	for_each_mem_range(i, &block_start, &block_end) { // 遍历物理内存块
		if (block_start < vmalloc_limit) {
			if (block_end > lowmem_limit) 
				lowmem_limit = min_t(u64, vmalloc_limit, block_end);
							 
	arm_lowmem_limit = lowmem_limit;
	high_memory = __va(arm_lowmem_limit - 1) + 1;
```

### 2.4.2 二级页表的创建
#### 注意细节
![](./pic/28.jpg)
1. 由于linux需要的有些属性 arm不支持，比如脏页，所以实际有两个页表，ARM的二级页表项，Linux的二级页表项。
   由于给二级页表项分配物理空间时，一次分配一个物理页，即4KB，所以2KB用于arm，2KB用于linux。
   并且都存放两个一级页表对应的二级页表项。

####
```c
setup_arch
   adjust_lowmem_bounds // 确定低端内存 arm_lowmem_limit 指向低端内存的结束
   paging_init
      prepare_page_table // 将页表置零
	                     // 清零空间包括：
	                     // 1. 0 - PAGE_OFFSET (用户空间)
						 // 2. __pfn_to_phys(arm_lowmem_limit)(线性映射结束) - VMALLOC_START 
						 //    在线性映射到VMALLOC_START之间有8MB的隔离虚拟空间，需要清零
      map_lowmem    // 映射所有的低端内存
```
#### map_lowmem
```c
static void __init map_lowmem(void)
{
	// 获得kernel镜像的物理内存
	// KERNEL_START - __init_end 主要包括代码段，不包括.data段
	phys_addr_t kernel_x_start = round_down(__pa(KERNEL_START), SECTION_SIZE);
	phys_addr_t kernel_x_end = round_up(__pa(__init_end), SECTION_SIZE);
	phys_addr_t start, end;
	u64 i;

	// 遍历memblock.memory
	/* Map all the lowmem memory banks. */
	for_each_mem_range(i, &start, &end) {
		struct map_desc map;

		// 只映射所有的低端内存
		if (end > arm_lowmem_limit)
			end = arm_lowmem_limit;
		if (start >= end)
			break;

		if (end < kernel_x_start) {
			// 如果此内存块属于内核镜像
			map.pfn = __phys_to_pfn(start); // 物理页帧号
			map.virtual = __phys_to_virt(start); // 使用线性映射的方式计算得到虚拟地址
			map.length = end - start; // 内存大小
			map.type = MT_MEMORY_RWX; // 权限为 RWX，注意有可执行

			create_mapping(&map);
		} else if (start >= kernel_x_end) {
			// 如果不属于内核镜像部分的物理内存，则只有读写权限
			map.pfn = __phys_to_pfn(start);
			map.virtual = __phys_to_virt(start);
			map.length = end - start;
			map.type = MT_MEMORY_RW;

			create_mapping(&map);
		} else {
			// 如果有部分属于内核镜像的物理内存，则分开映射，将属于的部分
			// 使用读写执行权限，其他为读写权限
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
		}
	}
}
```

#### create_mapping
```c
static void __init create_mapping(struct map_desc *md)
{
	if (md->virtual != vectors_base() && md->virtual < TASK_SIZE) {
		pr_warn("BUG: not creating mapping for 0x%08llx at 0x%08lx in user region\n",
			(long long)__pfn_to_phys((u64)md->pfn), md->virtual);
		return;
	}

	if (md->type == MT_DEVICE &&
	    md->virtual >= PAGE_OFFSET && md->virtual < FIXADDR_START &&
	    (md->virtual < VMALLOC_START || md->virtual >= VMALLOC_END)) {
		pr_warn("BUG: mapping for 0x%08llx at 0x%08lx out of vmalloc space\n",
			(long long)__pfn_to_phys((u64)md->pfn), md->virtual);
	}

	__create_mapping(&init_mm, md, early_alloc, false);
}

static void __init __create_mapping(struct mm_struct *mm, struct map_desc *md,
				    void *(*alloc)(unsigned long sz),
				    bool ng)
{
	unsigned long addr, length, end;
	phys_addr_t phys;
	const struct mem_type *type;
	pgd_t *pgd;

	// mem_types预定义了不同读写执行权限时，页表的flags位的值
	// 获得flags的值
	type = &mem_types[md->type];

#ifndef CONFIG_ARM_LPAE
	/*
	 * Catch 36-bit addresses
	 */
	if (md->pfn >= 0x100000) {
		create_36bit_mapping(mm, md, type, ng);
		return;
	}
#endif
	// 只取[31:12]共20位用于求一级页表的下标
	addr = md->virtual & PAGE_MASK; 
	// 根据物理页帧号计算物理地址
	phys = __pfn_to_phys(md->pfn);
	length = PAGE_ALIGN(md->length + (md->virtual & ~PAGE_MASK));

	if (type->prot_l1 == 0 && ((addr | phys | length) & ~SECTION_MASK)) {
		pr_warn("BUG: map for 0x%08llx at 0x%08lx can not be mapped using pages, ignoring.\n",
			(long long)__pfn_to_phys(md->pfn), addr);
		return;
	}

	// 计算对于的页帧
	// mm->pgd + addr >> 21
	// mm->pgd 是一个 u32 的数组
	pgd = pgd_offset(mm, addr);
	// 此页对应的虚拟地址的结束地址
	end = addr + length;
	do {
		// 一轮映射2MB的虚拟地址
		// next = addr + 2MB
		unsigned long next = pgd_addr_end(addr, end);

		// pgd一级页表项，将为其分配4KB的二级页表，映射2MB的虚拟空间
		// addr 虚拟空间的起始地址
		// next 虚拟空间的结束地址
		// phys 映射对应的物理空间的起始地址
		// type 权限
		// alloc 用于分配二级页表
		// ng  false
		alloc_init_p4d(pgd, addr, next, phys, type, alloc, ng);

		phys += next - addr;
		addr = next;
	} while (pgd++, addr != end);
}
```
#### alloc\_init\_p4d alloc\_init\_pud alloc\_init\_pmd
p4d pud pmd 都是一样的，直接分析最后的 alloc\_init\_pmd

```c
static void __init alloc_init_pmd(pud_t *pud, unsigned long addr,
				      unsigned long end, phys_addr_t phys,
				      const struct mem_type *type,
				      void *(*alloc)(unsigned long sz), bool ng)
{
	pmd_t *pmd = pmd_offset(pud, addr); // pmd = pud = p4d = pgd;
	                                    // pmd就指向一级页表项
	unsigned long next;

	do {
		/*
		 * With LPAE, we must loop over to map
		 * all the pmds for the given range.
		 */
		next = pmd_addr_end(addr, end); 

        // 映射物理地址 addr - next
		/*
		 * Try a section mapping - addr, next and phys must all be
		 * aligned to a section boundary.
		 */
		if (type->prot_sect &&
				((addr | next | phys) & ~SECTION_MASK) == 0) {
			__map_init_section(pmd, addr, next, phys, type, ng); // 段映射方式
		} else {
			alloc_init_pte(pmd, addr, next,
				       __phys_to_pfn(phys), type, alloc, ng); // 页映射方式
		}

		phys += next - addr;

	} while (pmd++, addr = next, addr != end);
}
```

#### 分配二级页表，建立二级页表和一级页表的关系
```c
static void __init alloc_init_pte(pmd_t *pmd, unsigned long addr,
				  unsigned long end, unsigned long pfn,
				  const struct mem_type *type,
				  void *(*alloc)(unsigned long sz),
				  bool ng)
{
	// 给二级页表分配空间，并设置一级页表项指向二级页表
	pte_t *pte = arm_pte_alloc(pmd, addr, type->prot_l1, alloc);
	do {
		// 建立虚拟地址和物理地址的映射，写到二级页表
		// pte : 二级页表
		// pfn_pte(pfn, __pgprot(type->prot_pte) : 待映射的物理空间的起始地址
		// 0
		set_pte_ext(pte, pfn_pte(pfn, __pgprot(type->prot_pte)),
			    ng ? PTE_EXT_NG : 0);
		pfn++;
	} while (pte++, addr += PAGE_SIZE, addr != end); // 一共映射2MB的空间
	                                                 // 一次循环映射4KB，需要循环512次
													 // 需要注意的是：pte 一次增加8字节，
													 // 
}
```

分配二级页表
```c
static pte_t * __init arm_pte_alloc(pmd_t *pmd, unsigned long addr,
				unsigned long prot,
				void *(*alloc)(unsigned long sz))
{
	if (pmd_none(*pmd)) {
		// 分配512 * 4B + 512 * 4B = 4KB 的物理空间用作二级页表
		pte_t *pte = alloc(PTE_HWTABLE_OFF + PTE_HWTABLE_SIZE);
		// 设置一级页表项指向 ARM二级页表的物理起始地址
		__pmd_populate(pmd, __pa(pte), prot);
			// 下面一共消耗4KB的空间
			//
			// pte + PTE_HWTABLE_OFF 保证指向的是 arm的二级页表，而非linux的二级页表
			// PTE_HWTABLE_OFF : 512 * 4B = 2KB, 两个linux二级页表项（一个256 * 4B = 1KB）
			pmdval_t pmdval = (pte + PTE_HWTABLE_OFF) | prot;
			// 一次分配了两个二级页表，一个页表项占据1KB，两个占据2KB
			// 分配Linux页表 2KB
			pmdp[0] = __pmd(pmdval);
		#ifndef CONFIG_ARM_LPAE
			// 分配ARM页表 2KB
			pmdp[1] = __pmd(pmdval + 256 * sizeof(pte_t));
		#endif
			flush_pmd_entry(pmdp);
	}
	BUG_ON(pmd_bad(*pmd));
	return pte_offset_kernel(pmd, addr);
}
```
#### 设置二级页表

#define set_pte_ext(ptep,pte,ext) cpu_set_pte_ext(ptep,pte,ext)

#define cpu_set_pte_ext			__glue(CPU_NAME,_set_pte_ext)
```asm
// r0 : 二级页表项
// r1 : 物理基地址+flags
/*
 *	cpu_v7_set_pte_ext(ptep, pte)
 *
 *	Set a level 2 translation table entry.
 *
 *	- ptep  - pointer to level 2 translation table entry
 *		  (hardware version is stored at +2048 bytes)
 *	- pte   - PTE value to store
 *	- ext	- value for extended PTE bits
 */
ENTRY(cpu_v7_set_pte_ext)
	str	r1, [r0]			@ linux version
	                        // 设置linux二级页表项

    // 设置flags
	// 删除arm页表项不支持的flags如 L_PTE_DIRTY，脏页
	// 增加arm页表项支持的flags
	bic	r3, r1, #0x000003f0
	bic	r3, r3, #PTE_TYPE_MASK
	orr	r3, r3, r2
	orr	r3, r3, #PTE_EXT_AP0 | 2

	tst	r1, #1 << 4
	orrne	r3, r3, #PTE_EXT_TEX(1)

	eor	r1, r1, #L_PTE_DIRTY
	tst	r1, #L_PTE_RDONLY | L_PTE_DIRTY 
	orrne	r3, r3, #PTE_EXT_APX

	tst	r1, #L_PTE_USER
	orrne	r3, r3, #PTE_EXT_AP1

	tst	r1, #L_PTE_XN
	orrne	r3, r3, #PTE_EXT_XN

	tst	r1, #L_PTE_YOUNG
	tstne	r1, #L_PTE_VALID
	eorne	r1, r1, #L_PTE_NONE
	tstne	r1, #L_PTE_NONE
	moveq	r3, #0

 ARM(	str	r3, [r0, #2048]! )  // 设置arm二级页表项
 								// 2048 是 Linux 页表项数组和ARM页表项数组的偏差
								// 因为 Linux和ARM页表项数组都占据 2048字节
								// Linux[0] : 1KB 
								// Linux[1] : 1KB
								// ARM[0]   : 1KB
								// ARM[1]   : 1KB
								// 刚好把4KB的一个Page用完

 THUMB(	add	r0, r0, #2048 )
 THUMB(	str	r3, [r0] )          
	ALT_SMP(W(nop))
	ALT_UP (mcr	p15, 0, r0, c7, c10, 1)		@ flush_pte
	bx	lr
ENDPROC(cpu_v7_set_pte_ext)
```


### 2.4.3 vmalloc区
#### 为什么需要vmalloc区
前面创建了线性映射区，那么映射的物理空间一定是连续分配的，而连续的物理空间大小有限（由伙伴系统导致最大4MB），
但是连续的虚拟内存并不需要连续的物理空间，只要映射不是线性的，那么就出现了vmalloc区，
vmalloc区可以分配大的虚拟空间，且映射的物理空间不需要连续。

#### vmalloc区的大小
由两方面决定：
* PAGE_SHIFT : 决定虚拟空间内核区的大小
* 物理内存的大小 : 物理内存越大，线性映射区越大，但需要保证最少给vmalloc区留 240MB

#### 如何从vmalloc区分配虚拟内存
```c
void *vmalloc(unsigned long size);
void vfree(const void *addr);
unsigned long vmalloc_to_pfn(const void *vmalloc_addr);
struct page *vmalloc_to_page(const void *vmalloc_addr);
```

#### vmalloc实现分析
从 VMALLOC_START 到 VMALLOC_END 查找一片虚拟空间
从伙伴系统申请多个物理页帧page
把每个申请的物理页帧映射到虚拟空间

```c
struct vm_struct {
	struct vm_struct	*next;
	void			*addr;         // 虚拟空间的起始地址
	unsigned long		size;      // 虚拟空间大小
	unsigned long		flags;
	struct page		**pages;       // 物理页数组
	unsigned int		nr_pages;  // 物理页数量
	phys_addr_t		phys_addr;
	const void		*caller;
};

// 描述一块虚拟空间
struct vmap_area {
	unsigned long va_start;  // 虚拟空间的起始地址
	unsigned long va_end;    // 虚拟空间的结束地址

	struct rb_node rb_node;         /* address sorted rbtree */ // 用于查找
	struct list_head list;          /* address sorted list */   // 用于遍历

	/*
	 * The following three variables can be packed, because
	 * a vmap_area object is always one of the three states:
	 *    1) in "free" tree (root is vmap_area_root)
	 *    2) in "busy" tree (root is free_vmap_area_root)
	 *    3) in purge list  (head is vmap_purge_list)
	 */
	union {
		unsigned long subtree_max_size; /* in "free" tree */
		struct vm_struct *vm;           /* in "busy" tree */ // this
		struct llist_node purge_list;   /* in purge list */
	};
};
```

```c
vmalloc(unsigned long size)
	__vmalloc_node_range(size, align, VMALLOC_START, VMALLOC_END,
				gfp_mask, PAGE_KERNEL, 0, node, caller);
	struct vm_struct *area;
	size = PAGE_ALIGN(size);
	area = __get_vm_area_node(real_size, align, VM_ALLOC | VM_UNINITIALIZED |
				vm_flags, start, end, node, gfp_mask, caller);    // 分配虚拟空间
		area = kzalloc_node(sizeof(*area), gfp_mask & GFP_RECLAIM_MASK, node);
		va = alloc_vmap_area(size, align, start, end, node, gfp_mask);	// 从VMALLOC_START - VMALLOC_END
																		// 分配size大小的虚拟空间

	    setup_vmalloc_vm(area, va, flags, caller); // 将 area 和 vm_struct关联
			vm->flags = flags;
			vm->addr = (void *)va->va_start;
			vm->size = va->va_end - va->va_start;
			vm->caller = caller;
			va->vm = vm;


	addr = __vmalloc_area_node(area, gfp_mask, prot, node); // 分配物理page
		unsigned int array_size = nr_pages * sizeof(struct page *), i;

		if (!(gfp_mask & (GFP_DMA | GFP_DMA32))) // 如果没有用DMA
			gfp_mask |= __GFP_HIGHMEM;			 // 优先从高端内存分配page

		// 分配元素为page指针的数组
		// 如果数组大小大于一个页，则递归调用 vmallo_node分配空间
		// 否则使用kmalloc分配
		if (array_size > PAGE_SIZE) {
			pages = __vmalloc_node(array_size, 1, nested_gfp, node,
						area->caller);
		} else {
			pages = kmalloc_node(array_size, nested_gfp, node);
		}
		area->pages = pages;
		area->nr_pages = nr_pages;

		// 从伙伴系统分配page
		for (i = 0; i < area->nr_pages; i++) {
			struct page *page;
			if (node == NUMA_NO_NODE)
				page = alloc_page(gfp_mask);
			else
				page = alloc_pages_node(node, gfp_mask, 0);
	
			area->pages[i] = page;
		}
	
	// 建立虚拟地址和物理地址的映射
	map_kernel_range((unsigned long)area->addr, get_vm_area_size(area), prot, pages);
		map_kernel_range_noflush(start /*虚拟空间地址*/, size /*虚拟空间大小*/, prot, pages /*物理页*/);
			unsigned long end = addr + size; // end为虚拟空间的结束地址
			pgd = pgd_offset_k(addr); // 根据虚拟地址得到一级页表项
			do {
				next = pgd_addr_end(addr, end);	// next为addr + 2MB 
												// 一个一级页表项对应2MB的虚拟空间
				vmap_p4d_range(pgd, addr, next, prot, pages, &nr, &mask);
					vmap_pte_range(pmd, addr, next, prot, pages, nr, mask)
						pte = pte_alloc_kernel_track(pmd, addr, mask);	// 分配一个page做二级页表
																		// 设置一级页表项pmd指向二级页表
																		// 返回二级页表项数组pte
						do {
							struct page *page = pages[*nr]; // *nr从0开始
					
							set_pte_at(&init_mm, addr, pte, mk_pte(page, prot)); // 设置二级页表
								cpu_set_pte_ext(ptep,__pte(pte_val(pte)|(ext)))  // 详细参见前面汇编分析
							(*nr)++;
						} while (pte++, addr += PAGE_SIZE, addr != end);


			} while (pgd++ /*下一个一级页表项*/, addr = next /*下一次需要映射的虚拟地址*/, addr != end);

		flush_cache_vmap(start, start + size);
	
	return addr; // 返回虚拟空间地址
```

#### ioremap
ioremap也是从vmalloc区分配虚拟空间，不同的是物理空间已经确定，所以直接建立映射
```c
ioremap(phys_addr_t paddr, unsigned long size)
	phys_addr_t end;
	end = paddr + size - 1;

	return ioremap_prot(paddr, size, PAGE_KERNEL_NO_CACHE);
		area = get_vm_area(size, VM_IOREMAP); // 从vmalloc区分配虚拟空间
		area->phys_addr = paddr;
		vaddr = (unsigned long)area->addr;
		ioremap_page_range(vaddr /*虚拟地址*/, vaddr + size/*虚拟结束*/, paddr/*物理地址*/, prot);
			pgd = pgd_offset_k(addr); // 根据虚拟地址得到一级页表项
			do {
				next = pgd_addr_end(addr, end); // next = addr + 2MB
												// 下一个一级页表项
				ioremap_p4d_range(pgd, addr, next, phys_addr, prot, &mask); // 同上
			} while (pgd++, phys_addr += (next - addr), addr = next, addr != end);
		
			flush_cache_vmap(start, end);

		return (void __iomem *)(off + (char __iomem *)vaddr);
```

### 2.4.4 高端内存
当物理内存足够大，线性映射剩余的内存被称为高端内存。

#### 高端内存的初始化
```c
void __init bootmem_init(void)
	find_limits(&min_low_pfn, &max_low_pfn, &max_pfn); // min_low_pfn : 起始物理页帧（除去保留部分）
	                                                   // max_low_pfn : 低端内存和高端内存的分隔页帧
													   // max_pfn : 结束物理页帧（除去保留部分）
	
	zone_sizes_init(min_low_pfn, max_low_pfn, max_pfn); // 将高端内存加入自己的伙伴系统
```
#### vmalloc和高端内存
vmalloc优先到高端内存的伙伴系统分配内存，申请失败再到低端内存

#### vmalloc区和线性映射区是否会冲突
如果没有高端内存，vmalloc从低端内存分配，则vmalloc区和线性映射区映射到同个page，
是否会导致冲突？
不会，因为对物理内存的管理由伙伴系统负责，地址映射不会影响伙伴系统。

### 2.4.5 pkmap
当开启了高端内存后，虚拟空间会分配2MB的pkmap，通过pkmap映射物理页的特点是：
如果该物理页在低端内存，则直接返回他的线性映射地址。
如果该物理页在高端内存，则在pkmap进行映射，并返回地址。


### 2.4.6 fixmap
特点，在编译时就确定了fixmap区虚拟地址和某些物理地址的映射关系，并且之后永远保持不变。
为什么需要fixmap?
因为在MMU开启后，只建立了内核镜像的映射，保证内核代码正常运行，
但是伙伴系统，二级页表，等没有完成初始化，如果需要访问硬件寄存器则不方便建立映射，
所以使用fixmap完成二级页表的创建，包括设备树，一些外设...

### 2.4.7 modules
安装模块时，从modules区分配虚拟内存建立映射，如果modules区分配虚拟内存失败（modules区很小16MB），
则从vmalloc区分配。
modules属于用户空间，

```c

SYSCALL_DEFINE3(init_module, void __user *, umod,
		unsigned long, len, const char __user *, uargs)
	return load_module(&info, uargs, 0);
		mod = layout_and_allocate(info, flags);
			err = move_module(info->mod, info);
				ptr = module_alloc(mod->core_layout.size);
					p = __vmalloc_node_range(size, 1, MODULES_VADDR, MODULES_END, // 优先从modules区申请
								gfp_mask, PAGE_KERNEL_EXEC, 0, NUMA_NO_NODE,
								__builtin_return_address(0));
					if (!IS_ENABLED(CONFIG_ARM_MODULE_PLTS) || p) // 如果申请失败，并配置了 CONFIG_ARM_MODULE_PLTS
						return p;                                 // 则再从vmalloc申请
					return __vmalloc_node_range(size, 1,  VMALLOC_START, VMALLOC_END,
								GFP_KERNEL, PAGE_KERNEL_EXEC, 0, NUMA_NO_NODE,
								__builtin_return_address(0));
```

### 2.5 用户空间的虚拟内存
每个进程都有自己的页表，共享一个内核页表
用户空间的虚拟内存也别分为多个区
![](./pic/29.jpg)
```c
struct task_struct {
	struct mm_struct		*mm; // 用户空间的虚拟内存
	...
};

struct mm_struct {
	..
	struct vm_area_struct *mmap; // 用户空间虚拟内存区链表
	pgd_t * pgd;    // 用户进程页表的基地址
	..
};

struct vm_area_struct {
	unsigned long vm_start;		/* Our start address within vm_mm. */
	unsigned long vm_end;		/* The first byte after our end address

	// 进程每个虚拟内存区链接在一起
	struct vm_area_struct *vm_next, *vm_prev;

	struct mm_struct *vm_mm;	/* The address space we belong to. */
};
```
![](./pic/30.jpg)

#### 2.5.1 用户空间页表的创建
创建本进程的mm_struct
拷贝内核页表项
创建父进程页表项
```c
SYSCALL_DEFINE0(fork)
	return kernel_clone(&args);
		copy_process(NULL, trace, NUMA_NO_NODE, args);
			copy_mm(clone_flags, p);
				dup_mm(tsk /*子进程*/, current->mm/*父进程的mm*/);
					mm = allocate_mm(); // 分配mm_struct
					memcpy(mm, oldmm, sizeof(*mm)); // 拷贝虚拟地址分布等信息
					mm_init(mm, tsk, mm->user_ns); 
						mm_init_owner(mm, p); // 设置子进程和mm的关联
						mm_alloc_pgd(mm);  // 拷贝内核页表项
							mm->pgd = pgd_alloc(mm);
								new_pgd = __pgd_alloc(); // 分配16KB的一级页表
								init_pgd = pgd_offset_k(0);  // 获得内核一级页表
								memcpy(new_pgd + USER_PTRS_PER_PGD, init_pgd + USER_PTRS_PER_PGD, //拷贝一级页表
										   (PTRS_PER_PGD - USER_PTRS_PER_PGD) * sizeof(pgd_t));   //一级页表项指向
										                                                          //同样的二级页表
																								  //项，所以不需拷
																								  //贝二级页表项

					dup_mmap(mm, oldmm); // 拷贝父进程mm
						mm->total_vm = oldmm->total_vm;
						mm->data_vm = oldmm->data_vm;
						mm->exec_vm = oldmm->exec_vm;
						mm->stack_vm = oldmm->stack_vm;
						pprev = &mm->mmap;
						for (mpnt = oldmm->mmap; mpnt; mpnt = mpnt->vm_next) { // 依次拷贝父进程各个VMA
							tmp = vm_area_dup(mpnt); // 创建VMA
								struct vm_area_struct *new = kmem_cache_alloc(vm_area_cachep, GFP_KERNEL);
								INIT_LIST_HEAD(&new->anon_vma_chain);
								new->vm_next = new->vm_prev = NULL;
							*pprev = tmp;         // 将拷贝的区加入mm->mmap链表
							pprev = &tmp->vm_next;
							tmp->vm_prev = prev;
							prev = tmp;

						copy_page_range(tmp, mpnt);
							copy_p4d_range(dst_vma, src_vma, dst_pgd, src_pgd,
								copy_pud_range(dst_vma, src_vma, dst_p4d, src_p4d,
									copy_pmd_range(dst_vma, src_vma, dst_pud, src_pud,
										copy_pte_range(dst_vma, src_vma, dst_pmd, src_pmd,
											do {
												copy_present_pte(dst_vma, src_vma, dst_pte, src_pte,
															   addr, rss, &prealloc);
													if (is_cow_mapping(vm_flags) && pte_write(pte)) { // 对父子页表项
														ptep_set_wrprotect(src_mm, addr, src_pte);    // 都设置写保护
														pte = pte_wrprotect(pte);                     // 实现写时拷贝
													}
													set_pte_at(dst_vma->vm_mm, addr, dst_pte, pte);   // 将进程的pte
													                                                  // 复制给子进程
																									  // 的pte

											} while (dst_pte++, src_pte++, addr += PAGE_SIZE, addr != end);
```

### 2.5.2 缺页异常 —— 写时复制
所谓缺页异常就是，没有却物理页，此时虚拟空间可能已分配，也可能未分配.

由于用户空间页表创建时，是复制父进程的页表，所以映射到同一个物理内存页，并设置了写保护，
当一个进程写这个内存页时，就会触发缺页异常，与信号类似，回调注册的缺页异常处理函数。

对于写时复制，虚拟空间已经分配，物理页没有分配.

注册缺页异常处理函数
```c
static int __init exceptions_init(void)
		hook_fault_code(4, do_translation_fault, SIGSEGV, SEGV_MAPERR,
				"I-cache maintenance fault");
			fsr_info[nr].fn   = fn;
			fsr_info[nr].sig  = sig;
			fsr_info[nr].code = code;
			fsr_info[nr].name = name;
```

发生缺页异常
```c
中断处理
	do_DataAbort(unsigned long addr, unsigned int fsr, struct pt_regs *regs)
		inf->fn(addr, fsr & ~FSR_LNX_PF, regs);

		do_translation_fault(unsigned long addr, unsigned int fsr,
					 struct pt_regs *regs)
			if (addr < TASK_SIZE)     // 如果触发缺页异常的虚拟地址属于用户空间
				return do_page_fault(addr, fsr, regs);

					struct mm_struct *mm;
					tsk = current;
					mm  = tsk->mm; // mm_struct 代表进程的虚拟空间和页表
					fault = __do_page_fault(mm, addr, fsr, flags, tsk, regs);

						struct vm_area_struct *vma;
						vma = find_vma(mm, addr); // 找到触发缺页地址对应虚拟空间
							return handle_mm_fault(vma, addr & PAGE_MASK, flags, regs);

								ret = __handle_mm_fault(vma, address, flags);
									// 分配
									struct vm_fault vmf = {
										.vma = vma,
										.address = address & PAGE_MASK,
										.flags = flags,
										.pgoff = linear_page_index(vma, address),
										.gfp_mask = __get_fault_gfp_mask(vma),
									};
									struct mm_struct *mm = vma->vm_mm;
									pgd = pgd_offset(mm, address);   // 找到address对应的一级页表项
									p4d = p4d_alloc(mm, pgd, address);  // 给一级页表项分配p4d pud pmd
									vmf.pud = pud_alloc(mm, p4d, address);
									vmf.pmd = pmd_alloc(mm, vmf.pud, address);

									return handle_pte_fault(&vmf);
										pte_t entry;
										if (!vmf->pte) { // pte项不存在，对于写时复制的情况在下面
											if (vma_is_anonymous(vmf->vma)) // 是否为匿名页，匿名页解释在下面
												return do_anonymous_page(vmf); // 匿名映射
											else
												return do_fault(vmf); // 文件映射
										}

										entry = vmf->orig_pte; // 记录原来的页表项值

										if (vmf->flags & FAULT_FLAG_WRITE) { // 写时复制
											if (!pte_write(entry))  // 如果pte写保护

												return do_wp_page(vmf);  // 分配page，建立映射，复制page，返回
													struct vm_area_struct *vma = vmf->vma;
													vmf->page = vm_normal_page(vma, vmf->address, vmf->orig_pte); // 得到父子进程
													                                                              // 共同关联的page
													return wp_page_copy(vmf);
														new_page = alloc_page_vma(GFP_HIGHUSER_MOVABLE, vma, // 分配新page
																vmf->address);
														cow_user_page(new_page, old_page, vmf);
															copy_user_highpage(dst, src, addr, vma);  // 复制page
														// 根据新的page生成页表项的值 entry
														entry = mk_pte(new_page, vma->vm_page_prot);
														entry = pte_sw_mkyoung(entry);
														entry = maybe_mkwrite(pte_mkdirty(entry), vma); // 修改为可读写权限

														page_add_new_anon_rmap(new_page, vma, vmf->address, false); // 设为匿名映射

														set_pte_at_notify(mm, vmf->address, vmf->pte, entry); // 设置新的映射关系
															void set_pte_at(struct mm_struct *mm, unsigned long addr,
																			  pte_t *ptep, pte_t pteval)
																set_pte_ext(ptep, pteval, ext);
																	cpu_set_pte_ext(ptep,pte,ext)


```

#### 匿名页
在Linux中，匿名页（anonymous page）是一种没有文件映射关联的内存页，通常用于进程堆栈和堆内存的分配。匿名页是指操作系统不知道这些页将要用于什么目的，因此它们不会被写入任何文件。相反，它们只是在物理内存上分配了一些空间，并由操作系统管理它们。

当进程需要更多的内存时，它可以通过向操作系统请求匿名页来动态增加堆栈或堆的大小。这些匿名页可以由进程自由使用，但它们不会被永久保存到磁盘上。

匿名页是一种内存分配的方式，它允许进程在运行时动态地分配内存，从而提高了内存的利用率和灵活性。同时，由于它们不会被保存到磁盘上，匿名页也可以帮助保护进程的安全性。


### 2.5.3 用户进程更新内核区页表
在Linux系统中，0号进程（也就是内核线程swapper）的页表只映射了内核空间，没有映射用户空间。这是因为0号进程是内核的一部分，其主要任务是管理系统的各种资源和处理各种中断和异常。因此，0号进程只需要访问内核空间，不需要访问用户空间。

在Linux中，普通进程创建时会创建一个新的虚拟地址空间，这个虚拟地址空间包括用户空间和内核空间。对于内核空间，普通进程并不需要复制内核空间相关的页表，因为内核空间的映射是共享的，所有进程都可以共享这些映射。

当一个普通进程被创建时，其虚拟地址空间的内核空间部分是由操作系统内核预先创建好的，已经包含了内核代码、数据和堆栈等内容。这些内核空间的映射是在内核初始化的时候建立的，是所有进程都共享的。

因此，普通进程在创建时只需要复制用户空间相关的页表，包括一级页表和二级页表。复制的页表是由内核空间中的swapper_pg_dir指向的一级页表，并且这些页表是对于内核空间的映射是共享的。

需要注意的是，当普通进程需要访问内核空间时，它必须通过特殊的系统调用进入内核态，这时会切换到内核的地址空间，并且可以访问内核空间的所有内容。在内核态下，进程使用的页表与用户态下的页表是不同的。在内核态下，进程使用的页表是内核专用的页表，它包含了对整个内核空间和所有进程的内存映射。


在Linux 5.0版本中，创建子进程时确实会为子进程的mm_struct复制内核空间的页表信息。

在Linux中，每个进程都有一个mm_struct结构，用于管理进程的内存地址空间。在创建子进程时，父进程会通过copy_mm()函数将自己的mm_struct结构中的信息复制到子进程的mm_struct中，包括一级页表、内存区域、映射关系等。

对于内核空间的映射，由于它是所有进程共享的，因此复制内核空间的页表信息可以提高系统的性能，因为所有进程可以共享这些映射，不需要每个进程都创建一份内核空间的页表。但是，由于内核空间的映射是共享的，需要确保进程不能修改内核空间的映射关系，否则会破坏系统的稳定性。为了保证这一点，Linux内核使用了写保护位（write-protection）来限制进程对内核空间的修改。这样，在普通进程修改自己的页表时，不能修改内核空间的映射，从而保证了系统的稳定性。

需要注意的是，即使子进程复制了父进程的内核空间的页表信息，子进程也只能访问内核空间中已经存在的内容，不能创建新的内核空间的映射。如果子进程需要修改内核空间的映射关系，需要通过内核提供的特殊接口，比如系统调用或者内核模块等。


```c

static int __kprobes
do_translation_fault(unsigned long addr, unsigned int fsr,
		     struct pt_regs *regs)
	if (addr < TASK_SIZE)
		return do_page_fault(addr, fsr, regs);
	// 如果访问内核空间，走下面
	index = pgd_index(addr); // 根据虚拟地址找到一级页表项的下标

	pgd = cpu_get_pgd() + index; // 获得当前进程的一级页表项
	pgd_k = init_mm.pgd + index; // 获得0号进程的一级页表项

	
	p4d = p4d_offset(pgd, addr);
	p4d_k = p4d_offset(pgd_k, addr);

	if (p4d_none(*p4d_k))
		goto bad_area;
	if (!p4d_present(*p4d))
		set_p4d(p4d, *p4d_k);

	pud = pud_offset(p4d, addr);
	pud_k = pud_offset(p4d_k, addr);

	if (pud_none(*pud_k))
		goto bad_area;
	if (!pud_present(*pud))
		set_pud(pud, *pud_k);

	pmd = pmd_offset(pud, addr);
	pmd_k = pmd_offset(pud_k, addr);


	index = 0;

	if (pmd_none(pmd_k[index]))  //如果0号进程没有创建对应页表的映射，则错误
		goto bad_area;

	copy_pmd(pmd, pmd_k); // 拷贝0号进程的一级页表项给当前进程
		#define copy_pmd(pmdpd,pmdps)		\ // 拷贝两个一个arm页表项一个linux页表项
			do {				\
				pmdpd[0] = pmdps[0];	\   // 设置Linux一级页表项
				pmdpd[1] = pmdps[1];	\   // 设置arm一级页表项
				flush_pmd_entry(pmdpd);	\   // 刷新TLB
			} while (0)


	return 0;

bad_area:
	do_bad_area(addr, fsr, regs); // 报错
		if (user_mode(regs))
			__do_user_fault(addr, fsr, SIGSEGV, SEGV_MAPERR, regs);
		else
			__do_kernel_fault(mm, addr, fsr, regs);
				die("Oops", regs, fsr);

	return 0;
```

## 2.5.4 mmap
mmap常用于三种情况：
1. 需要大块内存，如malloc分配大块内存时，会调用mmap
2. 文件，设备映射，通过mmap将文件页缓存或驱动缓存映射到用户空间，用户进程可以高效的操作这些内存数据
3. 用户进程使用mmap，通过匿名页实现父子进程间数据交换。

### 驱动mmap的实现
```c
#define MAX_SIZE 4096
#define PAGE_ORDER 0

static int hello_open(struct inode *inode, struct file *file)
{
    page = alloc_pages(GFP_KERNEL, PAGE_ORDER);
    if (!page) {
        printk("alloc_page failed\n");
        return -ENOMEM;
    }
    hello_buf = (char *)page_to_virt(page);
    printk("data_buf phys_addr: %x, virt_addr: %px\n",
            page_to_phys(page), hello_buf);

   return 0;
}

static int hello_release(struct inode *inode, struct file *file)
{
    __free_pages(page, PAGE_ORDER);

    return 0;
}

static int hello_mmap(struct file *file, struct vm_area_struct *vma)
{
    struct mm_struct *mm;
    unsigned long size;
    unsigned long pfn;
    int ret;

    mm = current->mm;   
    pfn = page_to_pfn(page); 

    size = vma->vm_end - vma->vm_start;
    if (size > MAX_SIZE) {
        printk("map size too large, max size is 0x%x\n", MAX_SIZE);
        return -EINVAL;
    }

    ret = remap_pfn_range(vma, vma->vm_start, pfn, size, vma->vm_page_prot);
    if (ret) {
        printk("remap_pfn_range failed\n");
        return -EAGAIN;
    }
    
    return ret;
}
```

### remap_pfn_range
```c

#define PGDIR_SHIFT		21  // 将虚拟地址的[31:21] 共11bit为一级页表的下标
                            // 知道一个pte对应1MB空间，就是 [19:0], 共20位
                            // 所以一个一级页表项对应两个二级页表
							// 用[20]位做区别

#define PGDIR_SIZE		(1UL << PGDIR_SHIFT) // 1 << 21 ，对 [31:21]部分进行操作

// 返回下一个一级页表地址
#define pgd_addr_end(addr, end)						\
({	unsigned long __boundary = ((addr) + PGDIR_SIZE) & PGDIR_MASK;	\
	(__boundary - 1 < (end) - 1)? __boundary: (end);		\
})

typedef u32 pmdval_t;
typedef struct { pmdval_t pgd[2]; } pgd_t; // 一个pgd对应8字节

/*
 * vma : 要映射到的虚拟空间区域
 * addr : 要映射到的虚拟地址
 * pfn : 参与映射的物理页号
 * size : 映射的内存大小
 * prot : 页保护权限
 */
int remap_pfn_range(struct vm_area_struct *vma, unsigned long addr,
		    unsigned long pfn, unsigned long size, pgprot_t prot)

	unsigned long end = addr + PAGE_ALIGN(size); // 虚拟地址，映射边界
	struct mm_struct *mm = vma->vm_mm; // mm中有进程的一级页表的地址

	vma->vm_flags |= VM_IO | VM_PFNMAP | VM_DONTEXPAND | VM_DONTDUMP;
	pfn -= addr >> PAGE_SHIFT; // 和 remap_p4d_range 有关
	pgd = pgd_offset(mm, addr); // 相关一级页表项的地址
	do {
		next = pgd_addr_end(addr, end); // 保存下一级页表项对应的虚拟地址,将用于映射
		remap_p4d_range(mm, pgd, addr, next,   
				pfn + (addr >> PAGE_SHIFT), prot); 
			remap_p4d_range
				remap_pud_range
					remap_pmd_range
							/*
							 * mm : 进程的虚拟地址空间
							 * pmd : 上级页表项的指针
							 * addr : 参与映射的虚拟地址
							 * end :
							 */
							remap_pte_range(struct mm_struct *mm, pmd_t *pmd,
										unsigned long addr, unsigned long end,
										unsigned long pfn, pgprot_t prot)

								mapped_pte = pte = pte_alloc_map_lock(mm, pmd, addr, &ptl); // 分配pte
									pte = alloc_page(gfp);      // 分配一个页
									pmd_populate(mm, pmd, new); // 设置pmd对应物理空间，指向pte
										__pmd_populate(pmdp, __pa(ptep), _PAGE_KERNEL_TABLE); // 所有的低端内存都映射
											#define __pa(x)			__virt_to_phys((unsigned long)(x)) // 到线性映射区
											                                                           // 所以可以快速
																									   // 得到物理地址

								do {
									// 设置pte页表，包括 ARM , Linux 两个pte页表
									// 一个
									set_pte_at(mm, addr, pte, pte_mkspecial(pfn_pte(pfn, prot)));

											// pfn得到物理基地址 或上 保护权限 得到 pteval
											pte_mkspecial(pte_t pte)
												return pte;
											#define pfn_pte(pfn,prot)	__pte(__pfn_to_phys(pfn) | pgprot_val(prot))


										set_pte_at(struct mm_struct *mm, unsigned long addr,
														  pte_t *ptep, pte_t pteval)
											set_pte_ext(ptep, pteval, ext); // 依次设置 一个 Linux pte ，一个arm pte
											                                // 一个pte对应4KB的虚拟空间

									pfn++;
								} while (pte++, addr += PAGE_SIZE, addr != end); // 一次设置4KB
								                                                 // 一共需要设置2MB
																				 // 循环512次


	} while (pgd++, addr = next, addr != end); // pgd++ ，一次增加8字节，得到下一个一级页表项的地址
```

### 文件映射
![](./pic/31.jpg)
打开文件后，读取文件后，使用页缓存加载文件内容。
由于一个page只有4KB，而文件通常大于4KB，所以使用多个page，并使用address_space将碎片的page实现连续数据的读写。

使用mmap可以将page映射到用户空间，实现高效的操作文件内容。


mmap系统调用的特点：
mmap只建立虚拟地址和文件地址偏移的关联, 设置好回调函数，返回虚拟地址给用户进程.
，不关联page，为了节省物理内存，当进程读写相关虚拟空间时，会发生缺页异常，再分配page

```c
SYSCALL_DEFINE6(mmap_pgoff, unsigned long, addr, unsigned long, len,
		unsigned long, prot, unsigned long, flags,
		unsigned long, fd, unsigned long, pgoff)
	ksys_mmap_pgoff(addr, len, prot, flags, fd, pgoff);
		if (!(flags & MAP_ANONYMOUS))  { // 不是匿名映射
			file = fget(fd);
		}
		retval = vm_mmap_pgoff(file, addr, len, prot, flags, pgoff);
			ret = do_mmap(file, addr, len, prot, flag, pgoff, &populate, &uf);
				struct mm_struct *mm = current->mm;
				addr = get_unmapped_area(file, addr, len, pgoff, flags); // 得到可用的虚拟地址
				addr = mmap_region(file, addr, len, vm_flags, pgoff, uf);
					vma = vm_area_alloc(mm);
					vma->vm_start = addr;
					vma->vm_end = addr + len;
					vma->vm_flags = vm_flags;
					vma->vm_page_prot = vm_get_page_prot(vm_flags);
					vma->vm_pgoff = pgoff;  // 设置文件偏移
					vma->vm_file = get_file(file);
					call_mmap(file, vma);
						return file->f_op->mmap(file, vma); //
							generic_file_mmap(struct file * file, struct vm_area_struct * vma)
							vma->vm_ops = &generic_file_vm_ops;  // 绑定缺页异常的回调

const struct vm_operations_struct generic_file_vm_ops = {
	.fault		= filemap_fault,
	.map_pages	= filemap_map_pages,
	.page_mkwrite	= filemap_page_mkwrite,
};


					addr = vma->vm_start;

					// 把vma加入mm
					// 把mapping->i_mmap 加入 vma
					vma_link(mm, vma, prev, rb_link, rb_parent);
						__vma_link(mm, vma, prev, rb_link, rb_parent);
							__vma_link_list(mm, vma, prev);
							__vma_link_rb(mm, vma, rb_link, rb_parent);
						__vma_link_file(vma);
							file = vma->vm_file;
							struct address_space *mapping = file->f_mapping;
							vma_interval_tree_insert(vma, &mapping->i_mmap);


					return addr;

```

### 文件缺页异常
mmap创建了个vma，记录了映射的虚拟地址，文件的address_space，文件偏移，并绑定了缺页异常处理的回调。
当发生缺页异常后：
```c
static int __kprobes
do_translation_fault(unsigned long addr, unsigned int fsr,
		     struct pt_regs *regs)
	if (addr < TASK_SIZE)
		return do_page_fault(addr, fsr, regs); // 缺页异常对应的虚拟地址发生在用户空间

			tsk = current;
			mm  = tsk->mm;

			fault = __do_page_fault(mm, addr, fsr, flags, tsk, regs);
				vma = find_vma(mm, addr); // 根据虚拟地址找到对应的虚拟空间区域描述
				                          // mmap注册了vma

			return handle_mm_fault(vma, addr & PAGE_MASK, flags, regs);
				ret = __handle_mm_fault(vma, address, flags);
					struct vm_fault vmf = {
						.vma = vma,
						.address = address & PAGE_MASK,
						.flags = flags,

						.pgoff = linear_page_index(vma, address),
							pgoff = (address - vma->vm_start) >> PAGE_SHIFT;// vma->start 是虚拟空间的起始地址
							                                                // 虚拟空间可能有多个页大小，
																			//(address - vma->vm_start )>>PAGE_SHIFT
																			// 
							pgoff += vma->vm_pgoff;                         
							return pgoff;

						.gfp_mask = __get_fault_gfp_mask(vma),
					};

					// Linux支持5级映射，但ARM只用了2级映射，这里分配5级映射的表，但实际没有效果
					pgd = pgd_offset(mm, address);            // 注意只分配一个pgd的下级表
					p4d = p4d_alloc(mm, pgd, address);        // 因为缺页异常也就缺一个页
					vmf.pud = pud_alloc(mm, p4d, address);
					vmf.pud = pud_alloc(mm, p4d, address);
					vmf.pmd = pmd_alloc(mm, vmf.pud, address); // pmd指向一个page
						pmd_t *new = pmd_alloc_one(mm, address); // 这个page之后用于存放pte[]
						pud_populate(mm, pud, new);              

					return handle_pte_fault(&vmf);
						pte_t entry;
						vmf->pte = pte_offset_map(vmf->pmd, vmf->address); // 根据虚拟地址,得到pte页表项的指针
						vmf->orig_pte = *vmf->pte; 
						if (pte_none(vmf->orig_pte))  // mmap 没有设置页表, 所以*orig_pte == NULL
							vmf->pte = NULL;

					if (!vmf->pte) 
						if (vma_is_anonymous(vmf->vma))
							return do_anonymous_page(vmf);
						else
							return do_fault(vmf);  // 文件缺页异常
								do_read_fault(vmf);
									__do_fault(vmf);
										vma->vm_ops->fault(vmf); // 回调缺页异常

											vm_fault_t filemap_fault(struct vm_fault *vmf) // 找对应物理页
												pgoff_t offset = vmf->pgoff;           // 根据文件偏移
												page = find_get_page(mapping, offset); // 找到对应物理页
												if (likely(page) && !(vmf->flags & FAULT_FLAG_TRIED)) {

												} else if (!page) {
													page = pagecache_get_page(mapping, offset,	// 如果没有
																  FGP_CREAT|FGP_FOR_MMAP,     	// 则分配page
																  vmf->gfp_mask);				// 加载文件
												vmf->page = page;

									finish_fault(vmf);
										page = vmf->page;
										alloc_set_pte(vmf, page); 
											pte_alloc_one_map(vmf);
												vmf->pte = pte_offset_map_lock(vma->vm_mm, vmf->pmd, vmf->address,
														&vmf->ptl); // pmd 指向一个page
														            // 根据虚拟地址找到对应pte
											entry = mk_pte(page, vma->vm_page_prot);
											set_pte_at(vma->vm_mm, vmf->address, vmf->pte, entry);
```

### 映射类型
![](./pic/32.jpg)
文件共享映射 : 当写页缓存会回写到文件
文件私有映射 : 当写页缓存不会回写到文件, 如加载程序，.text段就为私有映射
匿名共享映射 : 用于IPC的页缓存
匿名私有映射 : 用于分配进程自己使用的大片内存，如malloc的实现

### brk
![](./pic/34.jpg)
```c
SYSCALL_DEFINE1(brk, unsigned long, brk)
	unsigned long newbrk, oldbrk, origbrk;
	origbrk = mm->brk;
	min_brk = mm->start_brk;

	if (brk < min_brk) // 越界错误
		goto out;

	newbrk = PAGE_ALIGN(brk);
	oldbrk = PAGE_ALIGN(mm->brk);

	if (brk <= mm->brk) {  // 缩小brk区域，释放内存
		mm->brk = brk;
		ret = __do_munmap(mm, newbrk, oldbrk-newbrk, &uf, true);
		goto success;
	}

	// 扩大brk

	
	next = find_vma(mm, oldbrk); // 如果和已存在的mmap的映射冲突，则退出
	if (next && newbrk + PAGE_SIZE > vm_start_gap(next)) 
		goto out;

	// 扩展brk
	do_brk_flags(oldbrk, newbrk-oldbrk, 0, &uf);
		mapped_addr = get_unmapped_area(NULL, addr, len, 0, MAP_FIXED);

		munmap_vma_range(mm, addr, len, &prev, &rb_link, &rb_parent, uf);

		vma = vma_merge(mm, prev, addr, addr + len, flags,
				NULL, NULL, pgoff, NULL, NULL_VM_UFFD_CTX);
		if (vma)
			goto out;

		vma = vm_area_alloc(mm);
		vma_set_anonymous(vma);
		vma->vm_start = addr;
		vma->vm_end = addr + len;
		vma->vm_pgoff = pgoff;
		vma->vm_flags = flags;
		vma->vm_page_prot = vm_get_page_prot(flags);
		vma_link(mm, vma, prev, rb_link, rb_parent);

	out:
		perf_event_mmap(vma);
		mm->total_vm += len >> PAGE_SHIFT;
		mm->data_vm += len >> PAGE_SHIFT;
		if (flags & VM_LOCKED)
			mm->locked_vm += (len >> PAGE_SHIFT);
		vma->vm_flags |= VM_SOFTDIRTY;
		return 0;

	mm->brk = brk;
```
brk并不会分配page，而是设置vma
在处理缺页异常时，必须有对应的vma，否则会报段错误。
```c
__do_page_fault(struct mm_struct *mm, unsigned long addr, unsigned int fsr,
		unsigned int flags, struct task_struct *tsk,
		struct pt_regs *regs)
	vma = find_vma(mm, addr);
	fault = VM_FAULT_BADMAP;
	if (unlikely(!vma))
out:
	return fault;
		goto out;
```

### 反向映射 
前面都是正向映射：输入虚拟地址，映射大小，分配物理页，建立映射。
反向映射：输入物理页，找到与其映射的不同进程的VMA
反向映射用于页面迁移

#### 匿名页的反向映射
![](./pic/35.jpg)
实现反向映射的关键是，page有一个mapping，记录了所有映射到此page的vma
```c
static vm_fault_t do_anonymous_page(struct vm_fault *vmf)
	pte_alloc(vma->vm_mm, vmf->pmd);	// 申请一个page存放 pte[]
	page = alloc_zeroed_user_highpage_movable(vma, vmf->address);  // 分配物理页
	entry = mk_pte(page, vma->vm_page_prot);  // 计算pte填充值
	vmf->pte = pte_offset_map_lock(vma->vm_mm, vmf->pmd, vmf->address, // 找到虚拟地址对应的pte
	page_add_new_anon_rmap(page, vma, vmf->address, false); // 建立方向映射关系
		__page_set_anon_rmap(page, vma, address, 1);
		struct anon_vma *anon_vma = vma->anon_vma;  // vma->anon_vma 是个数组
		anon_vma = (void *) anon_vma + PAGE_MAPPING_ANON; // 偏移数组
		page->mapping = (struct address_space *) anon_vma;  // page就反向指向
		page->index = linear_page_index(vma, address); // 得到page在pte[]的下标

	set_pte_at(vma->vm_mm, vmf->address, vmf->pte, entry); // 建立映射
```
#### 文件页反向映射
![](./pic/36.jpg)
