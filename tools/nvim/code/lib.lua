-- 基本库：

-- assert：断言测试。
-- collectgarbage：垃圾回收控制函数。
-- dofile：执行一个文件中的Lua代码。
-- error：抛出错误。
-- getmetatable：获取对象的元表。
-- ipairs：用于遍历数组的迭代器。
-- load：加载并编译一个Lua chunk。
-- loadfile：加载并编译一个文件中的Lua chunk。
-- next：提供对表中键值对的迭代。
-- pairs：用于遍历表的迭代器。

-- pcall：以受保护模式调用函数。
-- 		全称为 "protected call"，即 "受保护的调用"。它的作用是在一个安全的环境中调用一个函数，即使被调用的函数中发生错误，也不会导致整个程序崩溃。pcall 常用于错误处理，允许你捕获并处理函数执行过程中可能抛出的错误。
-- status, message = pcall(function [, arg1, arg2, ...])
--
-- function：要调用的函数。
-- arg1, arg2, ...（可选）：传递给函数的参数。
-- status：pcall 返回的第一个值，表示函数调用的状态。如果函数成功执行，status 为 true；如果发生错误，status 为 false。
-- message：pcall 返回的第二个值，表示错误信息。如果函数成功执行，message 为 nil；如果发生错误，message 包含错误的描述。

local function divide(a, b)
    if b == 0 then
        error("division by zero")
    end
    return a / b
end

local status, message = pcall(divide, 10, 0)

if not status then
    -- 处理错误
    print("An error occurred:", message)
else
    -- 函数执行成功
    print("Result:", message)
end


-- print：打印值。
-- rawequal：原始的相等测试。
-- rawget：直接从表中获取值。
-- rawlen：返回table的长度或字符串的字节长度。
-- rawset：直接设置表中的值。
-- select：从多个返回值中选择值。
-- setmetatable：设置对象的元表。
-- tonumber：尝试将值转换为数字。
-- tostring：返回值的字符串表示。
-- type：返回值的类型。
-- xpcall：增强版的pcall。
--
-- 字符串库（string）：
--
-- string.byte：获取字符串中字符的数字代码。
-- string.char：接收数字参数并返回对应的UTF-8字符串。
-- string.dump：返回一个包含给定函数的二进制代码的字符串。
-- string.find：搜索字符串中子串的位置。
-- string.format：返回格式化后的字符串。
-- string.gmatch：返回一个迭代器函数。
-- string.gsub：替换字符串中的模式。
-- string.len：返回字符串的长度。
-- string.lower：转换字符串为小写。
-- string.match：在字符串中查找模式。
-- string.rep：重复字符串。
-- string.reverse：反转字符串。
-- string.sub：提取子串。
-- string.upper：转换字符串为大写。
-- 表库（table）：
-- 
-- table.concat：连接表中的元素。
-- table.insert：在表的指定位置插入元素。
-- table.move：在表之间移动元素。
-- table.pack：将可变数量的参数打包进一个新的table。
-- table.remove：从表中移除元素。
-- table.sort：对表进行排序。
-- table.unpack：等价于unpack，展开表中的元素。
-- 数学库（math）：
-- 
-- math.abs：绝对值。
-- math.acos：反余弦函数。
-- math.asin：反正弦函数。
-- math.atan：反正切函数。
-- math.ceil：向上取整。
-- math.cos：余弦函数。
-- math.deg：将弧度转换为度数。
-- math.exp：指数函数。
-- math.floor：向下取整。
-- math.fmod：取模。
-- math.log：对数函数。
-- math.max：返回多个参数中的最大值。
-- math.min：返回多个参数中的最小值。
-- math.pi：π的值。
-- math.rad：将度数转换为弧度。
-- math.random：生成随机数。
-- math.sin：正弦函数。
-- math.sqrt：平方根。
-- math.tan：正切函数。
-- 输入/输出库（io）：
-- 
-- io.close：关闭文件。
-- io.flush：刷新输出缓冲。
-- io.input：设置标准输入。
-- io.lines：返回一个迭代器。
-- io.open：打开文件。
-- io.output：设置标准输出。
-- io.popen：打开一个进程。
-- io.read：从文件中读取数据。
-- io.tmpfile：创建临时文件。
-- io.type：检查对象是否是文件。
-- io.write：向文件写数据。
-- 操作系统库（os）：
-- 
-- os.clock：返回程序使用的CPU时间。
-- os.date：返回当前日期和时间。
-- os.difftime：计算时间差。
-- os.execute：执行shell命令。
-- os.exit：终止程序。
-- os.getenv：获取环境变量。
-- os.remove：删除文件。
-- os.rename：重命名文件。
-- os.setlocale：设置区域设置。
-- os.time：返回时间的表示。
-- os.tmpname：创建临时文件名。
-- 查询库函数文档
