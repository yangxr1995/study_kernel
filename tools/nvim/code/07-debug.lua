#!/usr/bin/lua

-- 1. 打印语句：
-- 最简单的调试方法是在代码中插入print语句来输出变量的值或程序的状态。
print("Variable x is:", x)

-- 2. 断言：
-- 使用assert函数来检查程序在某个点上的期望是否为真，如果不为真，则抛出错误。
assert(x > 0, "x must be positive")


-- 3. lua调试库
-- Lua提供了一个内置的调试库（debug库），它提供了一些强大的调试工具：

-- 获取函数的调用栈：
-- 使用debug.traceback()可以获取当前函数调用栈的字符串表示，通常在错误时使用。

local _, msg = pcall(function()
    error(debug.traceback())
end)
print(msg)

-- 获取局部变量：
-- 使用debug.getlocal()可以获取函数的局部变量。

-- 获取上调变量：
-- 使用debug.getupvalue()可以获取闭包的上调变量。

-- 4. 错误处理
-- pcall/xpcall：
-- 使用pcall或xpcall来执行代码，并捕获并处理可能发生的错误。

local status, err = pcall(function()
    -- 你的代码
end)
if not status then
    print("Error:", err)
end
