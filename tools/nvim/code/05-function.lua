#!/usr/bin/lua

-- base
function greet(name)
    print("Hello, " .. name)
end

greet("Alice") -- 输出: Hello, Alice

function add(a, b)
    return a + b
end

local sum = add(5, 3) -- sum 的值为 8

-- 多重返回值
function getPerson()
    return "Alice", 30
end

local name, age = getPerson() -- name 的值为 "Alice"，age 的值为 30


-- 局部变量
function printScope()
    local localVariable = "I'm local"
    print(localVariable)
end

printScope() -- 输出: I'm local

-- 下面的代码将无法打印 localVariable，因为它是局部于 printScope 函数的
-- print(localVariable)

-- 函数和table
-- 使用函数返回table，实现传递复杂的数据结构
function createPerson(name, age)
    return {name = name, age = age}
end

local person = createPerson("Bob", 25)
print(person.name, person.age) -- 输出: Bob 25


-- 闭包
-- Lua函数可以捕获它们所在上下文中的变量，这称为闭包。
function createCounter()
    local count = 0
    return function()
        count = count + 1
        return count
    end
end

local counter = createCounter()
print(counter()) -- 输出: 1
print(counter()) -- 输出: 2

-- 变长参数
-- Lua函数可以使用 ... 来接收可变数量的参数，这些参数被存储在一个叫做 vararg 的表中。
function printAll(...)
    for i = 1, select("#", ...) do
        print(select(i, ...))
    end
end

printAll("apple", "banana", "cherry") -- 输出: apple, banana, cherry

-- 匿名函数
-- Lua允许定义匿名函数，这在需要临时函数或需要将函数作为参数传递时非常有用。
local addFive = function(x)
    return x + 5
end

print(addFive(3)) -- 输出: 8

-- 函数作为一等公民
-- 由于函数是一等公民，它们可以作为参数传递给其他函数，也可以作为返回值返回。
function applyOperation(value, operation)
    return operation(value)
end

local result = applyOperation(10, function(x) return x * 2 end)
print(result) -- 输出: 20

