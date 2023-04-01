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

