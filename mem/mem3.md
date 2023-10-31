# 物理内存的管理 -- memblock
## 核心数据结构
### memblock 
memblock 内存页帧分配器是 Linux 启动早期内存管理器，在伙伴系统（Buddy System）接管内存管理之前为系统提供内存分配、预留等功能。

memblock 将系统启动时获取的可用内存范围（如从设备树中获取的内存范围）纳入管理，为内核启动阶段内存分配需求提供服务，直到 memblock 分配器将内存管理权移交给伙伴系统。同时 memblock 分配器也维护预留内存（reserved memory），使其不会被分配器直接用于分配，保证其不被非预留者使用。

```c
struct memblock {
	// 分配内存的方向
	// true 从0地址向高地址分配
	// false 从高地址向0地址分配
	bool bottom_up;  
	// 可分配的物理内存的最大地址
	phys_addr_t current_limit;
	// 可使用的内存：包括已分配和未分配
	struct memblock_type memory;
	// 已分配的内存
	struct memblock_type reserved;
};
```
#### memblock_type
memblock_type 描述同类型的可离散的多个物理内存块

```c
struct memblock_type {
	unsigned long cnt; // 记录了结构体中含有的内存区块数量。regions数组有效元素
	unsigned long max; // 结构体中为 regions 数组分配的数量，当需要维护内存区域数目超过 max 后 ，则会倍增 regions 的内存空间
	phys_addr_t total_size; // 当前内存管理集合所管理的所有内存区域的内存大小综合
	struct memblock_region *regions; // 为内存区块数组，描述该集合下管理的所有内存区块，每个数组元素代表一块内存区域，可通过索引获取对应区块。注意区块是按照内存升序或降序排列（由上一层结构中 bottom_up 决定），且相邻数组元素所描述内存必不连续（连续会合并为一个数组元素）。
	char *name; // 为内存类型集合名字，如名为 memory 代表可用内存集合，reserved 代码预留内存集合。
};
```

##### 物理类型 和 内存类型
```c
struct memblock_type memory;
struct memblock_type physmem;
```
内存类型是物理类型的子集，物理类型包含所有物理内存，

引导内核时可以使用 mem=nn[KMG] 指定可用的内存大小，导致部分内存不可见。

内存类型只包含mem=nn[KMG]指定的内存


#### memblock_region
memblock_region 描述一段连续的物理内存块

```c
enum memblock_flags {
	MEMBLOCK_NONE		= 0x0,	// 没有特殊要求的区域
	MEMBLOCK_HOTPLUG	= 0x1,	// 支持的热插拔的内存区域
	MEMBLOCK_MIRROR		= 0x2,  // 支持内存镜像的区域，内存镜像就是内存热备份
	MEMBLOCK_NOMAP		= 0x4,	// 不添加到内核线性映射区
};

// 内存区域
struct memblock_region {
	phys_addr_t base; // 起始物理地址
	phys_addr_t size; // 大小
	enum memblock_flags flags;
#ifdef CONFIG_NEED_MULTIPLE_NODES
	int nid;
#endif
};
```

### 数据结构间的关系
![](./pic/65.jpg)

## 主要逻辑

memblock 依次进行

* 可用内存初始化
* 预留内存初始化
* 为内核提供内存管理服务，释放和移交管理权等流程。

### 可用内存初始化

#### 全局变量
```c
static struct memblock_region memblock_memory_init_regions[INIT_MEMBLOCK_REGIONS] __initdata_memblock;
static struct memblock_region memblock_reserved_init_regions[INIT_MEMBLOCK_REGIONS] __initdata_memblock;
#ifdef CONFIG_HAVE_MEMBLOCK_PHYS_MAP
static struct memblock_region memblock_physmem_init_regions[INIT_PHYSMEM_REGIONS] __initdata_memblock;
#endif

struct memblock memblock __initdata_memblock = {
	.memory.regions		= memblock_memory_init_regions,
	.memory.cnt		= 1,	/* empty dummy entry */
	.memory.max		= INIT_MEMBLOCK_REGIONS,
	.memory.name		= "memory",

	.reserved.regions	= memblock_reserved_init_regions,
	.reserved.cnt		= 1,	/* empty dummy entry */
	.reserved.max		= INIT_MEMBLOCK_REGIONS,
	.reserved.name		= "reserved",

#ifdef CONFIG_HAVE_MEMBLOCK_PHYS_MAP
	.physmem.regions	= memblock_physmem_init_regions,
	.physmem.cnt		= 1,	/* empty dummy entry */
	.physmem.max		= INIT_PHYSMEM_REGIONS,
	.physmem.name		= "physmem",
#endif

	.bottom_up		= false,
	.current_limit		= MEMBLOCK_ALLOC_ANYWHERE,
};
```

#### 初始化memblock

```c
start_kernel
	setup_arch(char **cmdline_p)
		mdesc = setup_machine_fdt(atags_vaddr);
			early_init_dt_scan_nodes();
				// 初始化 memblock.memory，即可参与内存分配的区域
				of_scan_flat_dt(early_init_dt_scan_memory, NULL);

		// 确定 arm_lowmem_limit
		adjust_lowmem_bounds();
		// 初始化 memblock.reserve，即不参与内存分配的区域
		arm_memblock_init(mdesc);
			/* 预留内核镜像内存，其中包括.text,.data,.init */
			memblock_reserve(__pa(KERNEL_START), KERNEL_END - KERNEL_START);
			arm_initrd_init();
			// 预留vector page内存
			// 如果CPU支持向量重定向（控制寄存器的V位），则CPU中断向量被映射到这里。
			arm_mm_memblock_reserve();
			//预留架构相关的内存，这里包括内存屏障和安全ram
			if (mdesc->reserve)
				mdesc->reserve();  
			early_init_fdt_reserve_self();  //预留设备树自身加载所占内存
			early_init_fdt_scan_reserved_mem();  //初始化设备树扫描reserved-memory节点预留内存
			dma_contiguous_reserve(arm_dma_limit);  //内核配置参数或命令行参数中预留的DMA连续内存
			arm_memblock_steal_permitted = false;
			memblock_dump_all();

		/* Memory may have been removed so recalculate the bounds. */
		adjust_lowmem_bounds();
```

##### early_init_dt_scan_memory
###### 设备树中memory定义  
```
/ {
	// reg是 cells数组
	// 一个cell 由 n 个 address-cell 和 m 个 size-cell 组成
	// 一个address-cell 或 size-cell 为 32 位无符号整形数
	// 下面两行定义 n 和 m 的值
	#address-cells = <1>;
	#size-cells = <1>;

	// "memory@60000000" 只是节点的别名，纯粹的字符串
	memory@60000000 {
		// 定义此节点描述内存
		device_type = "memory";

		// 由于上面对n m 的定义
		// 这个 reg 的 一组cell中 address-cell 只有一个
		//                        size-cell 只有一个
		// 这里只定义了一组cell
		// 结合上下文表示 内存节点起始地址 0x60000000, 大小 0x40000000
		reg = <0x60000000 0x40000000>;
	};
}
```
###### 内核如何分析fdt格式的设备树节点
```c
// 假设扫描到 fdt 格式节点  memory@60000000
int __init early_init_dt_scan_memory(unsigned long node, const char *uname,
				     int depth, void *data)
{
	// 从此节点node中获得fdt格式的属性名为"device_type" 的属性值
	// 第三个参数为 plength, 用于返回 值的长度，单位为 __be32
	// 由于知道不是数组类型的值，所以不需要 值的长度
	const char *type = of_get_flat_dt_prop(node, "device_type", NULL);
	const __be32 *reg, *endp;
	int l;
	bool hotpluggable;

	/* We are scanning "memory" nodes only */
	if (type == NULL || strcmp(type, "memory") != 0)
		return 0;

	// 这个属性用于定义预留多少内存，不使用，
	// 可以用于实现输出内存快照
	reg = of_get_flat_dt_prop(node, "linux,usable-memory", &l);
	if (reg == NULL)
		reg = of_get_flat_dt_prop(node, "reg", &l);
	// 如果没有属性 usable-memory,则说明这部分内存可以使用
	// 从 reg属性获得内存的起始地址和大小

	if (reg == NULL)
		return 0;

	// l : 为reg属性值的总长度，单位为 __be32
	// l / sizeof(__be32) : 属性值一共有多少个 __be32 
	// endpd = reg + (l/sizeof(__be32)) : endp指向有效内存块末尾
	endp = reg + (l / sizeof(__be32));
	// 获得另一个属性, 此处为NULL
	hotpluggable = of_get_flat_dt_prop(node, "hotpluggable", NULL);

	// 打印memory scan node memory@60000000, reg size 2
	pr_debug("memory scan node %s, reg size %d,\n", uname, l);

	// reg 为一个数组，数组元素为 address + size
	// address由 n 个 address-cell 表示
	// size 由 m 个 size-cell 表示
	// dt_root_addr_cells 由 #address-cells 定义 n 的值
	// dt_root_size_cells 由 #size-cells 定义 m 的值
	// 接下来需要遍历数组，数组一个元素大小为 n + m， 单位 __be32
	// 也就是 dt_root_addr_cells + dt_root_size_cells
	// endp - reg 为剩余待分析的内存大小，单位 __be32
	// 所以每次遍历移动 reg，直到数组遍历完成，
	// 或者剩余空间不足表示一个数组元素
	while ((endp - reg) >= (dt_root_addr_cells + dt_root_size_cells)) {
		u64 base, size;

		// reg指向待分析的数据起始空间，
		// dt_root_addr_cells 表示 多少个__be32 空间表示一个 address
		// 所以得到一个 address的值，返回为 base
		// 并移动reg到下一个位置，也就是size
		base = dt_mem_next_cell(dt_root_addr_cells, &reg);
		// 同上
		size = dt_mem_next_cell(dt_root_size_cells, &reg);

		if (size == 0)
			continue;
		pr_debug(" - %llx ,  %llx\n", (unsigned long long)base,
		    (unsigned long long)size);

		// 将base , size添加到  memory 子系统
		early_init_dt_add_memory_arch(base, size);

		// hotpluggable为NULL, 遍历下一个数组元素
		// 由于只有一个数组元素，所以返回
		if (!hotpluggable)
			continue;

		if (early_init_dt_mark_hotplug_memory_arch(base, size))
			pr_warn("failed to mark hotplug range 0x%llx - 0x%llx\n",
				base, base + size);
	}

	return 0;
}

```
###### dt_mem_next_cell 获得cell的值并指向下一个cell
```
// s : 本类型的值占用 s 个单元，单位为 __be32
// cellp : 当前扫描到的单位的地址的地址
u64 __init dt_mem_next_cell(int s, const __be32 **cellp)
{
	// 获得当前扫描到的单位的地址
	const __be32 *p = *cellp;

	// 指向下个cell
	*cellp = p + s;
	// 返回当前cell的值
	return of_read_number(p, s);
}

// 可以拼出很大的数
// size是cell的占用单元的数量，单位为__be32
static inline u64 of_read_number(const __be32 *cell, int size)
{
	u64 r = 0;
	for (; size--; cell++)
		r = (r << 32) | be32_to_cpu(*cell);
	return r;
}
```

###### 将从设备树获得的信息添加到memory子系统
```c
void __init __weak early_init_dt_add_memory_arch(u64 base, u64 size)
{
	const u64 phys_offset = MIN_MEMBLOCK_ADDR;

	.. // 过滤非法情况，处理对齐

	memblock_add(base, size);
}

int __init_memblock memblock_add(phys_addr_t base, phys_addr_t size)
{
	phys_addr_t end = base + size - 1;

	memblock_dbg("%s: [%pa-%pa] %pS\n", __func__,
		     &base, &end, (void *)_RET_IP_);

	return memblock_add_range(&memblock.memory, base, size, MAX_NUMNODES, 0);
}

static int __init_memblock memblock_add_range(struct memblock_type *type,
				phys_addr_t base, phys_addr_t size,
				int nid, enum memblock_flags flags)
{
	bool insert = false;
	phys_addr_t obase = base;
	phys_addr_t end = base + memblock_cap_size(base, &size);
	int idx, nr_new;
	struct memblock_region *rgn;

	if (!size)
		return 0;

	/* special case for empty array */
	if (type->regions[0].size == 0) {
		WARN_ON(type->cnt != 1 || type->total_size);
		type->regions[0].base = base;
		type->regions[0].size = size;
		type->regions[0].flags = flags;
		memblock_set_region_node(&type->regions[0], nid);
		type->total_size = size;
		return 0;
	}

	// 如果由多个内存区域添加
	.. 
```

```c
// memblock.memory.regions[i] 表示某一个内存区域	
memblock.memory.regions[0].base = base;   // 0x60000000
memblock.memory.regions[0].size = size;   // 0x40000000
memblock.memory.regions[0].flags = flags; // MEMBLOCK_NONE 没有特殊要求的内存

memblock.memory.total_size = size;        // 所有内存区域的大小0x40000000
```

### 预留内存初始化
将需要保留的内存添加进预留内存类型集合（`memblock.reserved`）,使得后续使用 `memblock` 分配内存时，避开预留内存。例如，在分页系统初始化过程中会调用 `memblock_reserve` 函数将内核程序在内存中的范围保留，保证其不会被覆盖，调用关系如下：
```c
    - paging_init
      - setup_bootmem()
        - memblock_reserve(vmlinux_start, vmlinux_end - vmlinux_start)
```

### memblock的使用
当 memblock 系统完成初始化后，需要申请内存时内核会通过 memblock 系统。

使用者调用 `memblock_alloc` 申请内存，`memblock_free` 释放内存

`setup_vm_final` 函数调用 `create_pgd_mapping` 函数建立页全局目录时，会调用 `alloc_pgd_next` 获取一个页面作为页表。`alloc_pgd_next` 实际是调用 `memblock_phys_alloc` 函数从 `memblock` 分配器中获取一个空闲页面。又如 `setup_log_buf` 中申请存放日志的内存时，会调用 `memblock_alloc` 获得一块内存的虚拟地址。

### memblock和伙伴系统
当内核完成部分初始化功能，并继续启动到要建立以后内核都将使用内存管理系统时，就到了 `memblock` 向伙伴系统移交控制权的时候了。`mm_init` 函数负责建立内存管理系统。该函数会调用 `memblock_free_all` 函数，此函数完成 `memblock` 释放并移交管理权的流程。相关流程如下：

```c
- mm_init
    - mem_init
        - memblock_free_all
```

## 重要函数分析
```c
// 将内存区域添加到 memblock.memory
int memblock_add(phys_addr_t base, phys_addr_t size);
// 从memblock.memory 中删除内存区域
int memblock_remove(phys_addr_t base, phys_addr_t size);
// 释放内存
int memblock_free(phys_addr_t base, phys_addr_t size);
// 从memblock.memory 分配内存
static inline void * __init memblock_alloc(phys_addr_t size,  phys_addr_t align)
```

### memblock_add

memblock_add 添加内存块到 memblock.memory 

另一个类似的接口 memblock_reserve 添加内存块到 memblock.reserve

![](./pic/66.jpg)

图中的左侧是函数的执行流程图，执行效果是右侧部分。

右侧部分画的是一个典型的情况，实际的情况可能有多种，但是核心的逻辑都是对插入的region进行判断，

如果出现了物理地址范围重叠的部分，那就进行split操作，最终对具有相同flag的region进行merge操作。

#### memblock_add_range
```c
static int __init_memblock memblock_add_range(struct memblock_type *type,
				phys_addr_t base, phys_addr_t size,
				int nid, enum memblock_flags flags)
{
	bool insert = false;
	phys_addr_t obase = base;
	phys_addr_t end = base + memblock_cap_size(base, &size);
	int idx, nr_new;
	struct memblock_region *rgn;

	if (!size)
		return 0;

	// 添加内存块是从[0]开始添加，如果[0]内存块大小为0，
	// 则说明memblock_type没有添加过内存
	if (type->regions[0].size == 0) {
		WARN_ON(type->cnt != 1 || type->total_size);
		type->regions[0].base = base;
		type->regions[0].size = size;
		type->regions[0].flags = flags;
		memblock_set_region_node(&type->regions[0], nid);
		type->total_size = size;
		return 0;
	}
repeat:
	/*
	 * The following is executed twice.  Once with %false @insert and
	 * then with %true.  The first counts the number of regions needed
	 * to accommodate the new area.  The second actually inserts them.
	 */
	base = obase;
	nr_new = 0;

	for_each_memblock_type(idx, type, rgn) {
		phys_addr_t rbase = rgn->base;
		phys_addr_t rend = rbase + rgn->size;

		//  base  end   rbase   rend
		//          -----|-------|--
		// --|----|--
		// 这种情况肯定和所有已知区域块都不会重叠
		if (rbase >= end)
			break;
		//  rbase  rend   base   end
		//          -----|-------|--
		// --|----|--
		// 和当前区域块无重叠，但是和后面内存块可能重叠，continue
		if (rend <= base)
			continue;

		// 新添加区域和以前的区域有重叠

		/*
		 * @rgn overlaps.  If it separates the lower part of new
		 * area, insert that portion.
		 */
		//  base    rbase  end   rend
		//      -----|------------|--
		// --|--------------|---
		if (rbase > base) {
#ifdef CONFIG_NEED_MULTIPLE_NODES
			WARN_ON(nid != memblock_get_region_node(rgn));
#endif
			WARN_ON(flags != rgn->flags);
			nr_new++;
			if (insert) // 第一次遍历时 insert == false
				memblock_insert_region(type, idx++, base,
						       rbase - base, nid,
						       flags);
		}

		// 上面完成了添加，下一句将剩余空间清零
		//  base    rbase  end   rend
		//      -----|------------|--
		// --|--------------|---
		//
		//                base
		//          rbase  end   rend
		//      -----|------------|--
		//              ----|---
		//

		// 将此情况等价于不相交的情况
		//  rbase    base  rend   end
		//      -----|------------|--
		// --|--------------|---
		//
		//                 base   end
		//                --|-----|--
		// --|--------------|---
		//
		/* area below @rend is dealt with, forget about it */
		base = min(rend, end);
	}

	/* insert the remaining portion */
	if (base < end) {
		// 处理不重叠情况
		//                    base   end
		//                   --|-----|--
		// --|--------------|---
		//	
		//                 base   end
		//                --|-----|--
		// --|--------------|---
		//
		//  base   end
		// --|-----|--
		//       --|--------------|---
		//
		//  base   end
		// --|-----|--
		//          --|--------------|---
		nr_new++;
		if (insert)
			memblock_insert_region(type, idx, base, end - base,
					       nid, flags);
	}

	if (!nr_new)
		return 0;

	/*
	 * If this was the first round, resize array and repeat for actual
	 * insertions; otherwise, merge and return.
	 */
	if (!insert) {
		// 第一次遍历的主要目的就是确保 region[] 足够大
		// 因为使用数组类型，不方便动态添加，所以计算出 nr_new
		// 并一次分配足够的空间
		// 如果 memblock_type.region[]数组不够大，则两倍扩大他
		while (type->cnt + nr_new > type->max)
			if (memblock_double_array(type, obase, size) < 0)
				return -ENOMEM;
		// 第二次遍历，进行插入操作
		insert = true;
		goto repeat;
	} else {
		// 插入完成后，进行合并操作
		//  base   end
		// --|-----|--
		//       --|--------------|---
		//
		//                 base   end
		//                --|-----|--
		// --|--------------|---
		memblock_merge_regions(type);
		return 0;
	}
}
```

#### memblock_merge_regions

合并regions, 可合并的条件
* this->base == next->end
* 并且 this 和 next 是同一个内存节点
* 并且 this->flags == next->flags

```c
static void __init_memblock memblock_merge_regions(struct memblock_type *type)
{
	int i = 0;

	/* cnt never goes below 1 */
	while (i < type->cnt - 1) {
		struct memblock_region *this = &type->regions[i];
		struct memblock_region *next = &type->regions[i + 1];

		if (this->base + this->size != next->base ||
		    memblock_get_region_node(this) !=
		    memblock_get_region_node(next) ||
		    this->flags != next->flags) {
			BUG_ON(this->base + this->size > next->base);
			i++;
			continue;
		}

		this->size += next->size;
		/* move forward from next + 1, index of which is i + 2 */
		// 将next后面的元素往前移动，覆盖掉被合并的元素next
		memmove(next, next + 1, (type->cnt - (i + 2)) * sizeof(*next));
		type->cnt--;
	}
}
```

### memblock_remove

![](./pic/67.jpg)

```c
int __init_memblock memblock_remove(phys_addr_t base, phys_addr_t size)
{
	phys_addr_t end = base + size - 1;

	memblock_dbg("%s: [%pa-%pa] %pS\n", __func__,
		     &base, &end, (void *)_RET_IP_);

	return memblock_remove_range(&memblock.memory, base, size);
}

static int __init_memblock memblock_remove_range(struct memblock_type *type,
					  phys_addr_t base, phys_addr_t size)
{
	int start_rgn, end_rgn;
	int i, ret;

	// 找到type.regions[] 内存区域和 [base, end] 重叠的部分，
	// 因为只有重叠部分才是有效可以被删除的部分
	// 并分割现有region，构建新的 memblock_region 保存这些重叠的区域
	// 通过start_rgn ， end_rgn返回重叠regions
	ret = memblock_isolate_range(type, base, size, &start_rgn, &end_rgn);
	if (ret)
		return ret;

	for (i = end_rgn - 1; i >= start_rgn; i--)
		memblock_remove_region(type, i);
	return 0;
}

static void __init_memblock memblock_remove_region(struct memblock_type *type, unsigned long r)
{
	type->total_size -= type->regions[r].size;
	// 数组元素向前移动一个元素，覆盖掉被删除的 region
	memmove(&type->regions[r], &type->regions[r + 1],
		(type->cnt - (r + 1)) * sizeof(type->regions[r]));
	type->cnt--;

	/* Special case for empty arrays */
	if (type->cnt == 0) {
		WARN_ON(type->total_size != 0);
		type->cnt = 1;
		type->regions[0].base = 0;
		type->regions[0].size = 0;
		type->regions[0].flags = 0;
		memblock_set_region_node(&type->regions[0], MAX_NUMNODES);
	}
}

static int __init_memblock memblock_isolate_range(struct memblock_type *type,
					phys_addr_t base, phys_addr_t size,
					int *start_rgn, int *end_rgn)
{
	phys_addr_t end = base + memblock_cap_size(base, &size);
	int idx;
	struct memblock_region *rgn;

	*start_rgn = *end_rgn = 0;

	if (!size)
		return 0;

	/* we'll create at most two more regions */
	while (type->cnt + 2 > type->max)
		if (memblock_double_array(type, base, size) < 0)
			return -ENOMEM;

	for_each_memblock_type(idx, type, rgn) {
		phys_addr_t rbase = rgn->base;
		phys_addr_t rend = rbase + rgn->size;

		// 不可能和regions[]任意元素有重叠,break
		//        rbase
		// baese  end               rend
		//  |------|   
		//         |----------------|-----
		if (rbase >= end)
			break;

		// 和当前区域块无重叠，但是和后面内存块可能重叠，continue
		//      rbase           rend
		//                      base      end
		//                        |--------|--
		//    ---|----------------|-----
		if (rend <= base)
			continue;

		if (rbase < base) {


		// 分割
		//   case 1 :
		//      rbase       base rend end
		//                   |--------|--
		//    ---|----------------|-----
		//
		//              idx[1]_base
		//     idx_base    idx_end   
		//                   |--------|--
		//    ---|-----------|----|-----
		//                      idx[1]_end
		//
		//           继续遍历
		//                  base     end         
		//                   |--------|
		//    ---------------|----|-----
		//                  rbase rend
		//           完全覆盖的情况
		//
		//                     
		//
		//    case 2:
		//     rbase base      end   rend
		//            |---------|
		//    ---|--------------------|---
		//
		//
		//         idx[1]_base
		//            |---------|   idx[1]_end
		//    ---|----|---------------|---
		//    idx_base
		//          idx_end
		//
		//         继续遍历
		//            base      end
		//            |---------|
		//           rbase           rend 
		//    --------|---------------|---
		//        
		//          走下面if (rend > end)的情况
		//    
			/*
			 * @rgn intersects from below.  Split and continue
			 * to process the next region - the new top half.
			 */
			rgn->base = base;
			rgn->size -= base - rbase;
			type->total_size -= base - rbase;
			memblock_insert_region(type, idx, rbase, base - rbase,
					       memblock_get_region_node(rgn),
					       rgn->flags);
		} else if (rend > end) {

		// 分割并保证地址小的在前面
		// base rbase end          rend 
		// |-----------|
		//    ---|----------------|-----
		//
		//   
		//           idx[-1].end
		// |-----------|
		//    ---|-----|----------|-----
		//  idx[-1].base 
		//            idx.base   idx.end
		//
		//          继续遍历
		// base       end           
		// |-----------|
		//    ---|-----|----------------
		//      rbase rend
		//           完全覆盖的情况
		//

			/*
			 * @rgn intersects from above.  Split and redo the
			 * current region - the new bottom half.
			 */
			rgn->base = end;
			rgn->size -= end - rbase;
			type->total_size -= end - rbase;
			memblock_insert_region(type, idx--, rbase, end - rbase,
					       memblock_get_region_node(rgn),
					       rgn->flags);
		} else {

		//      base                   end
		//     rbase                  rend
		//       |----------------------|
		//    ---|----------------------|-----
		//
		//	 base                           end
		//    |------------------------------|
		//    ---|----------------------|-----
		//
		//                             rend
		//   base                      end
		//    |-------------------------|
		//    ---|----------------------|-----
		//       rbase
		// 
		//      rbase                     rend
		//      base                  end
		//       |-------------------------|
		//    ---|----------------------|-----
		//
			/* @rgn is fully contained, record it */
			// 将完全覆盖的reg对于的下标保存
			if (!*end_rgn)
				*start_rgn = idx;
			*end_rgn = idx + 1;
		}
	}

	return 0;
}
```

### memblock_alloc
从 memblock.memory 申请内存块，并清零，并返回虚拟地址

memblock_phys_alloc 从 memblock.memory 申请内存块，

且排除memblock.reserved的内存区域，并返回物理地址

注意成功分配内存块时，并不会对 memblock.memory.regions[] 进行分割，

而是将其中被使用的区域建立新的内存区域加入 memblock.reserved 

```c
#define MEMBLOCK_LOW_LIMIT 0
#define MEMBLOCK_ALLOC_ACCESSIBLE	0

// 从memblock.memory.region[]分配size大小的物理内存，并转换为虚拟地址返回
// 并且返回的内存块数据清零
static inline void * __init memblock_alloc(phys_addr_t size,  phys_addr_t align)
{
	// 根据下面对函数的介绍，
	// 此分配的内存区域下限是 0, 
	// 上限是 memblock.current_limit也就是最大物理地址
	// nid是任意节点
	return memblock_alloc_try_nid(size, align, MEMBLOCK_LOW_LIMIT,
				      MEMBLOCK_ALLOC_ACCESSIBLE, NUMA_NO_NODE);
}

/*
 * size : 将被分配的内存块大小, 字节单位
 * align : 内存区域和块的对齐大小
 * min_addr : 首选分配的内存区域的下限（物理地址）
 * max_addr : 首选分配的内存区域的上限（物理地址），或者使用MEMBLOCK_ALLOC_ACCESSIBLE仅从受memblock.current_limit值限制的内存中进行分配。
 * nid :  要查找的空闲区域的节点ID，使用NUMA_NO_NODE表示任何节点。
 * 
 * 公共函数，在启用时提供附加的调试信息（包括调用者信息）。该函数将分配的内存清零。
 * 返回：
 * 成功时分配内存块的虚拟地址，失败时返回NULL。
 */
void * __init memblock_alloc_try_nid(
			phys_addr_t size, phys_addr_t align,
			phys_addr_t min_addr, phys_addr_t max_addr,
			int nid)
{
	void *ptr;

	ptr = memblock_alloc_internal(size, align,
					   min_addr, max_addr, nid, false);
	if (ptr)
		memset(ptr, 0, size);

	return ptr;
}

// exact_nid : false, 从nid节点分配失败时，尝试从其他内存节点进行分配
// 如果无法满足@min_addr限制，则会放弃该限制，并将分配回退到@min_addr以下的内存。其他约束条件，如节点和镜像内存，将在memblock_alloc_range_nid()中再次处理。
// 分配物理内存块，并返回虚拟地址
static void * __init memblock_alloc_internal(
				phys_addr_t size, phys_addr_t align,
				phys_addr_t min_addr, phys_addr_t max_addr,
				int nid, bool exact_nid)
{
	phys_addr_t alloc;

	// 检查是否启用了 slab 分配器，如果已启用，说明 memblock 已将管理权移交给伙伴系统
	if (WARN_ON_ONCE(slab_is_available()))
		return kzalloc_node(size, GFP_NOWAIT, nid);

	// 分配区域地址最大地址不超过 memblock能提供的最大地址
	if (max_addr > memblock.current_limit)
		max_addr = memblock.current_limit;

	// 分配物理内存块
	alloc = memblock_alloc_range_nid(size, align, min_addr, max_addr, nid,
					exact_nid);

	/* retry allocation without lower limit */
	// 如果使用min_addr限制条件，但分配失败，
	// 则弃用min_addr限制，尝试从min_addr之下的内存进行分配
	if (!alloc && min_addr)
		alloc = memblock_alloc_range_nid(size, align, 0, max_addr, nid,
						exact_nid);

	if (!alloc)
		return NULL;

	// 分配成功后返回虚拟地址
	return phys_to_virt(alloc);
}
```

#### memblock_alloc_range_nid
```c
phys_addr_t __init memblock_alloc_range_nid(phys_addr_t size,
					phys_addr_t align, phys_addr_t start,
					phys_addr_t end, int nid,
					bool exact_nid)
{
	enum memblock_flags flags = choose_memblock_flags();
		return system_has_some_mirror ? MEMBLOCK_MIRROR : MEMBLOCK_NONE;
	phys_addr_t found;

	if (WARN_ONCE(nid == MAX_NUMNODES, "Usage of MAX_NUMNODES is deprecated. Use NUMA_NO_NODE instead\n"))
		nid = NUMA_NO_NODE;

	if (!align) {
		/* Can't use WARNs this early in boot on powerpc */
		dump_stack();
		align = SMP_CACHE_BYTES;
	}

again:
	// 分配物理内存块
	found = memblock_find_in_range_node(size, align, start, end, nid,
					    flags);
	// 如果分配成功，则将内存块[founc, found + size) 加入 reserved
	if (found && !memblock_reserve(found, size))
		goto done;

	// 如果分配失败，且nid不受限制，则从其他nid分配
	if (nid != NUMA_NO_NODE && !exact_nid) {
		found = memblock_find_in_range_node(size, align, start,
						    end, NUMA_NO_NODE,
						    flags);
		// 如果分配成功，则将内存块[founc, found + size) 加入 reserved
		if (found && !memblock_reserve(found, size))
			goto done;
	}

	if (flags & MEMBLOCK_MIRROR) {
		flags &= ~MEMBLOCK_MIRROR;
		pr_warn("Could not allocate %pap bytes of mirrored memory\n",
			&size);
		goto again;
	}

	return 0;

done:
	// 是否进行内存泄露检查
	/* Skip kmemleak for kasan_init() due to high volume. */
	if (end != MEMBLOCK_ALLOC_KASAN)
		kmemleak_alloc_phys(found, size, 0, 0);

	return found;
}
```

#### memblock_find_in_range_node
```c
static phys_addr_t __init_memblock memblock_find_in_range_node(phys_addr_t size,
					phys_addr_t align, phys_addr_t start,
					phys_addr_t end, int nid,
					enum memblock_flags flags)
{
	/* pump up @end */
	if (end == MEMBLOCK_ALLOC_ACCESSIBLE ||
	    end == MEMBLOCK_ALLOC_KASAN)
		end = memblock.current_limit;

	/* avoid allocating the first page */
	start = max_t(phys_addr_t, start, PAGE_SIZE);
	end = max(start, end);

	// 从0地址向高地址分配 还是 从高地址向0地址分配
	if (memblock_bottom_up()) // memblock.bottom_up
		return __memblock_find_range_bottom_up(start, end, size, align,
						       nid, flags);
	else
		return __memblock_find_range_top_down(start, end, size, align,
						      nid, flags);
}

// 从高地址向0地址分配
// start : 内存区域下限，此处是 0 + PAGE_SIZE
// end : 内存区域上限，此处是 memblock.current_limit，也就是最大值
static phys_addr_t __init_memblock
__memblock_find_range_top_down(phys_addr_t start, phys_addr_t end,
			       phys_addr_t size, phys_addr_t align, int nid,
			       enum memblock_flags flags)
{
	phys_addr_t this_start, this_end, cand;
	u64 i;

	// 遍历存在于memblock.memory 但排除 memblock.reserve的内存块
	// 注意并没有修改 memblock.memory.regions[] 
	// 获得 this_start this_end
	for_each_free_mem_range_reverse(i, nid, flags, &this_start, &this_end,
					NULL) {
		// 限制this_start this_end 在 [start, end] 范围内
		this_start = clamp(this_start, start, end);
		this_end = clamp(this_end, start, end);

		// 从 this_end 开始分配内存，即 [this_start, this_end] 这块内存
		// 区域最大能提供 [0, this_end]大小的内存，
		// 如果 this_end < size，则说明内存大小肯定不足
		if (this_end < size)
			continue;

		// 从this_end分配size大小的内存，并确保对齐
		// 如果分配区域在this_start内则说明分配成功
		cand = round_down(this_end - size, align);
		if (cand >= this_start)
			return cand;
	}

	return 0;
}

/**
 * clamp - clamp - 返回一个在给定范围内的值，并进行严格的类型检查
 * @val: current value
 * @lo: lowest allowable value
 * @hi: highest allowable value
 *
 * This macro does strict typechecking of @lo/@hi to make sure they are of the
 * same type as @val.  See the unnecessary pointer comparisons.
 */
#define clamp(val, lo, hi) min((typeof(val))max(val, lo), hi)

/**
 * round_down -  向下舍入到下一个指定的2的幂次方
 * @x: the value to round
 * @y: multiple to round down to (must be a power of 2)
 *
 * Rounds @x down to next multiple of @y (which must be a power of 2).
 * To perform arbitrary rounding down, use rounddown() below.
 */
#define round_down(x, y) ((x) & ~__round_mask(x, y))
```

### memblock_free
```c
/*
 * 释放由 memblock_alloc_xx 分配的内存块[base, base + size)
 * 被释放了的内存，不会被释放给伙伴分配器
 */
int __init_memblock memblock_free(phys_addr_t base, phys_addr_t size)
{
	phys_addr_t end = base + size - 1;

	memblock_dbg("%s: [%pa-%pa] %pS\n", __func__,
		     &base, &end, (void *)_RET_IP_);

	kmemleak_free_part_phys(base, size);
	// memblock_free是释放预留的内存，
	// 当这些内存不存在于memblock.reserved时，就可以从 memblock.memory中分配
	return memblock_remove_range(&memblock.reserved, base, size);
}

static int __init_memblock memblock_remove_range(struct memblock_type *type,
					  phys_addr_t base, phys_addr_t size)
{
	int start_rgn, end_rgn;
	int i, ret;

	ret = memblock_isolate_range(type, base, size, &start_rgn, &end_rgn);
	if (ret)
		return ret;

	for (i = end_rgn - 1; i >= start_rgn; i--)
		memblock_remove_region(type, i);
	return 0;
}
```

### for_each_reserved_mem_range
```c
#define for_each_reserved_mem_range(i, p_start, p_end)			\
	__for_each_mem_range(i, &memblock.reserved, NULL, NUMA_NO_NODE,	\
			     MEMBLOCK_NONE, p_start, p_end, NULL)

#define __for_each_mem_range(i, type_a, type_b, nid, flags,		\
			   p_start, p_end, p_nid)			\
	for (i = 0, __next_mem_range(&i, nid, flags, type_a, type_b,	\
				     p_start, p_end, p_nid);		\
	     i != (u64)ULLONG_MAX;					\
	     __next_mem_range(&i, nid, flags, type_a, type_b,		\
			      p_start, p_end, p_nid))

```

`__next_mem_range` 函数的功能是给出类型为 `type_a` 集合中排除 `type_b` 集合后的可用区间。

故此函数在多处遍历时被使用：

`for_each_free_mem_range` 函数使用它时，`tpye_a` 取 `memblock.memory` ，`tpye_b` 取 `memblock.reserved` ，遍历可被申请的内存。

`for_each_mem_range` 函数使用它时，`tpye_a` 取 `memblock.memory` ，`tpye_b` 取 `NULL` ，直接遍历 `memblock.memory` 可用内存集合区间。

`for_each_reserved_mem_range` 函数使用它时，`tpye_a` 取 `memblock.reserved` ，`tpye_b` 取 `NULL` ，直接遍历 `memblock.reserved` 预留内存集合区间。

## memblock_free_all
当伙伴系统建立后，调用此函数释放所有物理页到伙伴系统

```c
unsigned long __init memblock_free_all(void)
{
	unsigned long pages;

	reset_all_zones_managed_pages();

	pages = free_low_memory_core_early();
	totalram_pages_add(pages);

	return pages;
}
```

# 高端内存的确定
```c
start_kernel
	setup_arch(&command_line);
		...
		mdesc = setup_machine_fdt(atags_vaddr); // 根据设备树memory节点，初始化memblock
		...
		adjust_lowmem_bounds();
		arm_memblock_init(mdesc);
		adjust_lowmem_bounds();
		...
		paging_init(mdesc);
		...

```

## adjust_lowmem_bounds


# 内存映射
## mm_struct
`mm_struct` 是内存管理和根对象，内核和用户进程有不同的`mm_struct`

内核的`mm_struct`为 全局变量 `init_mm`，用户进程的`mm_struct`为 `task->mm`

建立内存映射的核心就是要初始化 `mm_struct.pgd`

```c
struct mm_struct init_mm = {
	.mm_rb		= RB_ROOT,
	.pgd		= swapper_pg_dir,
	.mm_users	= ATOMIC_INIT(2),
	.mm_count	= ATOMIC_INIT(1),
	.write_protect_seq = SEQCNT_ZERO(init_mm.write_protect_seq),
	MMAP_LOCK_INITIALIZER(init_mm)
	.page_table_lock =  __SPIN_LOCK_UNLOCKED(init_mm.page_table_lock),
	.arg_lock	=  __SPIN_LOCK_UNLOCKED(init_mm.arg_lock),
	.mmlist		= LIST_HEAD_INIT(init_mm.mmlist),
	.user_ns	= &init_user_ns,
	.cpu_bitmap	= CPU_BITS_NONE,
	INIT_MM_CONTEXT(init_mm)
};

EXPORT_SYMBOL(init_mm);
```

## 段映射部分

![](./pic/68.jpg)

```asm
/*
 * 建立两个段表映射，一个是对开启MMu代码的恒等映射
 * 一个是内核镜像的映射
 *
 * r8 = phys_offset, r9 = cpuid, r10 = procinfo
 * 
 *  phys_offset : 内核解压后镜像的起始地址
 *  procinfo : CPU信息
 *
 * Returns:
 *  r0, r3, r5-r7 corrupted
 *  r4 = physical page table address
 */
__create_page_tables:
	pgtbl	r4, r8				@ page table address 分配页表内存
	                            @ r4 记录页表地址
	/*
	 * 将段表清零
	 */
	mov	r0, r4
	mov	r3, #0
	add	r6, r0, #PG_DIR_SIZE
1:	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	teq	r0, r6
	bne	1b

	ldr	r7, [r10, #PROCINFO_MM_MMUFLAGS] @ 读取MMU flags

	/*
	 * 现在 __turn_mmu_on 的物理地址已经确定（因为代码已经加载完成）
	 * 所以要根据 __turn_mmu_on 到 __turn_mmu_on_end 的物理地址填充页表
	 * 并且由于__turn_mmu_on一部分运行在虚拟地址，一部分运行在物理地址
	 * 所以必须建立恒等映射
	 *
	 * 将开启MMU的代码 __turn_mmu_on 建立恒等映射
	 * __turn_mmu_on代码的虚拟地址范围是 __turn_mmu_on - __turn_mmu_on_end
	 */
	adr	r0, __turn_mmu_on_loc @ r0存放__turn_mmu_on_loc的物理地址
	ldmia	r0, {r3, r5, r6} @ 将r0指向的内存的值依次放到 r3 r5 r6
	                         @ r3 = __turn_mmu_loc 虚拟地址
							 @ r5 = __turn_mmu_on 虚拟地址
							 @ r6 = __turn_mmu_on_end 虚拟地址

	sub	r0, r0, r3			@ virt->phys offset
	                        @ 计算虚拟地址和物理地址间的偏移
							@ r0 = r0 - r3
							@ r0 = __turn_mmu_on_loc物理地址 - __turn_mmu_on_loc虚拟地址

	add	r5, r5, r0			@ phys __turn_mmu_on
							@ 计算 __turn_mmu_on的物理地址
							@ r5 = r5 + r0
							@ r5 = __turn_mmu_on虚拟地址 + offset

	add	r6, r6, r0			@ phys __turn_mmu_on_end
							@ 计算__turn_mmu_on_end的物理地址

	mov	r5, r5, lsr #SECTION_SHIFT  @ r5=r5>>20
                                    @ 对等映射：将物理地址当成虚拟地址
                                    @ 虚拟地址>>20 得到 页表索引号
									@ 同时得到物理地址基地址>>20

	mov	r6, r6, lsr #SECTION_SHIFT  @ r6=r6>>20
                                    @ 对等映射：将物理地址当成虚拟地址
                                    @ 虚拟地址>>20 得到 页表索引号
									@ 同时得到物理地址基地址>>20

1:	orr	r3, r7, r5, lsl #SECTION_SHIFT	@ flags + kernel base
                                        @ r3 = r7 | r5<<20
                                        @ 将物理基地址做高位，
										@ 位或上mmu flags 得到填充页表的值

	str	r3, [r4, r5, lsl #PMD_ORDER]	@ identity mapping
                                        @ 将r3页表项值填充到页表
                                        @ 页表的地址计算：
                                        @     r4 + r5<<2
                                        @     页表基地址 + 页索引号 * 4   得到页表项地址
                                        @     之所以乘以4，是因为一个页表项占4字节

	cmp	r5, r6                  @ 比较当前页表号和结束页表号
	addlo	r5, r5, #1			@ next section
								@ 当r5 < r6 时，r5 = r5+1 , 也就是r5为下一个页表号

	blo	1b                      @ 当r5 < r6 时，循环

	/*
	 * Map our RAM from the start to the end of the kernel .bss section.
	 * 建立内核镜像映射
	 * r4 段表的基地址
	 */
	add	r0, r4, #PAGE_OFFSET >> (SECTION_SHIFT - PMD_ORDER) @ r0记录kernel起始段地址
                                                            @ 因为第一个段被对等映射占据，
                                                            @ 所以kernel的从第二个段开始
                                                            @ r0 = 段表基地址 + 第二个段的偏移地址
	ldr	r6, =(_end - 1)   @ kernel的虚拟地址的结束地址
						  @ _end在vmlinux.lds中定义，是内核镜像结束的连接地址

	orr	r3, r8, r7        @ r8:kernel镜像物理起始地址的基地址
						  @ r3 = r8 | r7
						  @ r3 = 内核镜像物理起始地址的基地址 | MMU-flags

	add	r6, r4, r6, lsr #(SECTION_SHIFT - PMD_ORDER)  @ 得到镜像虚拟结束地址对应的段的地址
                                                      @ 将 r6 >> (20 - 2) 可以理解为
                                                      @ (r6 >> 20) * 4
                                                      @ 首先将虚拟地址右移20位，得到段号
                                                      @ 再将段号乘以 4 得到偏移地址
                                                      @ 将段表基地址加上偏移地址得到结束段的地址

1:	str	r3, [r0], #1 << PMD_ORDER             @ 将物理基地址和mmu flags写道对应页表项       
                                              @ 将 *r0 = r3 ,写4B
                                              @ r0 += 4

	add	r3, r3, #1 << SECTION_SHIFT           @ 增加物理基地址 
	                                          @ 1 << 20 位保证只对物理基地址增加，不修改mmc flags

	cmp	r0, r6       @ 比较当前页表项地址和镜像的结束页表项地址 
	bls	1b           @ 如果 r0 < r6 循环

```



# 伙伴系统
伙伴系统用于分配连续的物理页，称为 page block。

阶order是伙伴系统的专业术语，表示页的数量，2^n个连续的page称为 n阶page block

满足以下条件两个page block称为伙伴，伙伴才可以合并
* page block必须相邻, 即物理地址连续
* page block 第一个page 号必须是2的整数倍
* 如果合并成 n+1 阶page block，第一页page号必须是2^(n+1)整数倍

简单说，能合并的page block必须是从相同上级page block分割


## 数据结构
```c
struct zone {
	/* Read-mostly fields */

	/* zone watermarks, access with *_wmark_pages(zone) macros */
	unsigned long _watermark[NR_WMARK];
	unsigned long watermark_boost;

	unsigned long nr_reserved_highatomic;

	/*
	 * We don't know if the memory that we're going to allocate will be
	 * freeable or/and it will be released eventually, so to avoid totally
	 * wasting several GB of ram we must reserve some of the lower zone
	 * memory (otherwise we risk to run OOM on the lower zones despite
	 * there being tons of freeable ram on the higher zones).  This array is
	 * recalculated at runtime if the sysctl_lowmem_reserve_ratio sysctl
	 * changes.
	 */
	long lowmem_reserve[MAX_NR_ZONES];

#ifdef CONFIG_NEED_MULTIPLE_NODES
	int node;
#endif
	struct pglist_data	*zone_pgdat;
	struct per_cpu_pageset __percpu *pageset;

#ifndef CONFIG_SPARSEMEM
	/*
	 * Flags for a pageblock_nr_pages block. See pageblock-flags.h.
	 * In SPARSEMEM, this map is stored in struct mem_section
	 */
	unsigned long		*pageblock_flags;
#endif /* CONFIG_SPARSEMEM */

	/* zone_start_pfn == zone_start_paddr >> PAGE_SHIFT */
	unsigned long		zone_start_pfn;

	/*
	 * spanned_pages is the total pages spanned by the zone, including
	 * holes, which is calculated as:
	 * 	spanned_pages = zone_end_pfn - zone_start_pfn;
	 *
	 * present_pages is physical pages existing within the zone, which
	 * is calculated as:
	 *	present_pages = spanned_pages - absent_pages(pages in holes);
	 *
	 * managed_pages is present pages managed by the buddy system, which
	 * is calculated as (reserved_pages includes pages allocated by the
	 * bootmem allocator):
	 *	managed_pages = present_pages - reserved_pages;
	 *
	 * So present_pages may be used by memory hotplug or memory power
	 * management logic to figure out unmanaged pages by checking
	 * (present_pages - managed_pages). And managed_pages should be used
	 * by page allocator and vm scanner to calculate all kinds of watermarks
	 * and thresholds.
	 *
	 * Locking rules:
	 *
	 * zone_start_pfn and spanned_pages are protected by span_seqlock.
	 * It is a seqlock because it has to be read outside of zone->lock,
	 * and it is done in the main allocator path.  But, it is written
	 * quite infrequently.
	 *
	 * The span_seq lock is declared along with zone->lock because it is
	 * frequently read in proximity to zone->lock.  It's good to
	 * give them a chance of being in the same cacheline.
	 *
	 * Write access to present_pages at runtime should be protected by
	 * mem_hotplug_begin/end(). Any reader who can't tolerant drift of
	 * present_pages should get_online_mems() to get a stable value.
	 */
	atomic_long_t		managed_pages;
	unsigned long		spanned_pages;
	unsigned long		present_pages;

	const char		*name;

#ifdef CONFIG_MEMORY_ISOLATION
	/*
	 * Number of isolated pageblock. It is used to solve incorrect
	 * freepage counting problem due to racy retrieving migratetype
	 * of pageblock. Protected by zone->lock.
	 */
	unsigned long		nr_isolate_pageblock;
#endif

#ifdef CONFIG_MEMORY_HOTPLUG
	/* see spanned/present_pages for more description */
	seqlock_t		span_seqlock;
#endif

	int initialized;

	/* Write-intensive fields used from the page allocator */
	ZONE_PADDING(_pad1_)

	/* free areas of different sizes */
	struct free_area	free_area[MAX_ORDER];

	/* zone flags, see below */
	unsigned long		flags;

	/* Primarily protects free_area */
	spinlock_t		lock;

	/* Write-intensive fields used by compaction and vmstats. */
	ZONE_PADDING(_pad2_)

	/*
	 * When free pages are below this point, additional steps are taken
	 * when reading the number of free pages to avoid per-cpu counter
	 * drift allowing watermarks to be breached
	 */
	unsigned long percpu_drift_mark;

#if defined CONFIG_COMPACTION || defined CONFIG_CMA
	/* pfn where compaction free scanner should start */
	unsigned long		compact_cached_free_pfn;
	/* pfn where compaction migration scanner should start */
	unsigned long		compact_cached_migrate_pfn[ASYNC_AND_SYNC];
	unsigned long		compact_init_migrate_pfn;
	unsigned long		compact_init_free_pfn;
#endif

#ifdef CONFIG_COMPACTION
	/*
	 * On compaction failure, 1<<compact_defer_shift compactions
	 * are skipped before trying again. The number attempted since
	 * last failure is tracked with compact_considered.
	 * compact_order_failed is the minimum compaction failed order.
	 */
	unsigned int		compact_considered;
	unsigned int		compact_defer_shift;
	int			compact_order_failed;
#endif

#if defined CONFIG_COMPACTION || defined CONFIG_CMA
	/* Set to true when the PG_migrate_skip bits should be cleared */
	bool			compact_blockskip_flush;
#endif

	bool			contiguous;

	ZONE_PADDING(_pad3_)
	/* Zone statistics */
	atomic_long_t		vm_stat[NR_VM_ZONE_STAT_ITEMS];
	atomic_long_t		vm_numa_stat[NR_VM_NUMA_STAT_ITEMS];
} ____cacheline_internodealigned_in_smp;


```
