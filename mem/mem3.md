# 物理内存的管理
## 核心数据结构
### memblock 
memblock 是替代 bootmem 的接口, 用于在伙伴系统初始化前，提供内存管理

```c
struct memblock {
	// 分配内存的方向
	// true 从0地址向高地址分配
	// false 从高地址向0地址分配
	bool bottom_up;  
	// 可分配的物理内存的最大地址
	phys_addr_t current_limit;
	// 内存类型：包括已分配和未分配
	struct memblock_type memory;
	// 内存类型：预留类型，也就是已经被分配的内存
	struct memblock_type reserved;
};
```
#### memblock_type
memblock_type 描述同类型的可离散的多个物理内存块

```c
struct memblock_type {
	unsigned long cnt; // 当前内存管理集合中记录内存区域的个数
	unsigned long max; // 当前内存管理集合能记录的内存区域的最大个数
	phys_addr_t total_size; // 当前内存管理集合所管理的所有内存区域的内存大小综合
	struct memblock_region *regions; // 所管理的内存区域
	char *name;
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

## 内核确定物理内存信息

### 定义 memblock 全局变量
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

### 初始化memblock

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

#### early_init_dt_scan_memory
##### 设备树中memory定义  
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
##### 内核如何分析fdt格式的设备树节点
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
##### dt_mem_next_cell 获得cell的值并指向下一个cell
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

##### 将从设备树获得的信息添加到memory子系统
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

## memblock 编程接口
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
```c
static inline void * __init memblock_alloc(phys_addr_t size,  phys_addr_t align)
{
	return memblock_alloc_try_nid(size, align, MEMBLOCK_LOW_LIMIT,
				      MEMBLOCK_ALLOC_ACCESSIBLE, NUMA_NO_NODE);
}

void * __init memblock_alloc_try_nid(
			phys_addr_t size, phys_addr_t align,
			phys_addr_t min_addr, phys_addr_t max_addr,
			int nid)
{
	void *ptr;

	memblock_dbg("%s: %llu bytes align=0x%llx nid=%d from=%pa max_addr=%pa %pS\n",
		     __func__, (u64)size, (u64)align, nid, &min_addr,
		     &max_addr, (void *)_RET_IP_);
	ptr = memblock_alloc_internal(size, align,
					   min_addr, max_addr, nid, false);
	if (ptr)
		memset(ptr, 0, size);

	return ptr;
}

static void * __init memblock_alloc_internal(
				phys_addr_t size, phys_addr_t align,
				phys_addr_t min_addr, phys_addr_t max_addr,
				int nid, bool exact_nid)
{
	phys_addr_t alloc;

	/*
	 * Detect any accidental use of these APIs after slab is ready, as at
	 * this moment memblock may be deinitialized already and its
	 * internal data may be destroyed (after execution of memblock_free_all)
	 */
	if (WARN_ON_ONCE(slab_is_available()))
		return kzalloc_node(size, GFP_NOWAIT, nid);

	if (max_addr > memblock.current_limit)
		max_addr = memblock.current_limit;

	alloc = memblock_alloc_range_nid(size, align, min_addr, max_addr, nid,
					exact_nid);

	/* retry allocation without lower limit */
	if (!alloc && min_addr)
		alloc = memblock_alloc_range_nid(size, align, 0, max_addr, nid,
						exact_nid);

	if (!alloc)
		return NULL;

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
	phys_addr_t found;

	if (WARN_ONCE(nid == MAX_NUMNODES, "Usage of MAX_NUMNODES is deprecated. Use NUMA_NO_NODE instead\n"))
		nid = NUMA_NO_NODE;

	if (!align) {
		/* Can't use WARNs this early in boot on powerpc */
		dump_stack();
		align = SMP_CACHE_BYTES;
	}

again:
	found = memblock_find_in_range_node(size, align, start, end, nid,
					    flags);
	if (found && !memblock_reserve(found, size))
		goto done;

	if (nid != NUMA_NO_NODE && !exact_nid) {
		found = memblock_find_in_range_node(size, align, start,
						    end, NUMA_NO_NODE,
						    flags);
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
	/* Skip kmemleak for kasan_init() due to high volume. */
	if (end != MEMBLOCK_ALLOC_KASAN)
		/*
		 * The min_count is set to 0 so that memblock allocated
		 * blocks are never reported as leaks. This is because many
		 * of these blocks are only referred via the physical
		 * address which is not looked up by kmemleak.
		 */
		kmemleak_alloc_phys(found, size, 0, 0);

	return found;
}
```
