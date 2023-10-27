# 物理内存的管理
## 内核如何确定物理内存大小
### 设备树的定义
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
### 内核如何分析fdt格式的设备树节点
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
#### dt_mem_next_cell 获得cell的值并指向下一个cell
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

### 将从设备树获得的信息添加到memory子系统
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
memblock.memory.regions[0].flags = flags; // MEMBLOCK_NONE 普通内存 

memblock.memory.total_size = size;        // 所有内存区域的大小0x40000000
```

### 总结
内存从设备树获得内存区域信息，可能有多个内存区域，依次添加到 `memblock.memory.regions[]` 中

memblock_region 最重要描述了一块内存区域的起始地址和大小和内存是否有特殊请求
```c
/**
 * struct memblock_region - represents a memory region
 * @base: base address of the region
 * @size: size of the region
 * @flags: memory region attributes
 * @nid: NUMA node id
 */
struct memblock_region {
	phys_addr_t base;
	phys_addr_t size;
	enum memblock_flags flags;
#ifdef CONFIG_NEED_MULTIPLE_NODES
	int nid;
#endif
};

/**
 * struct memblock_type - collection of memory regions of certain type
 * @cnt: number of regions
 * @max: size of the allocated array
 * @total_size: size of all regions
 * @regions: array of regions
 * @name: the memory type symbolic name
 */
struct memblock_type {
	unsigned long cnt;
	unsigned long max;
	phys_addr_t total_size;
	struct memblock_region *regions;
	char *name;
};
```
