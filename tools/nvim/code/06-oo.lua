#!/usr/bin/lua

-- Lua 语言本身是不支持面向对象编程（OOP）的，但是它提供了足够的灵活性，使得开发者可以使用多种方式来模拟面向对象编程的风格。

-- 1. 使用Table来模拟对象
-- 在Lua中，对象通常被表示为包含其属性和方法的table。
-- 定义一个模拟的对象
local myObject = {
    name = "Alice",
    age = 30,

    -- 方法：显示个人信息
    showInfo = function(self, arg)
        print("Name: " .. self.name .. ", Age: " .. self.age .. ", arg: " .. arg)
    end
}

-- 使用对象
myObject:showInfo("aaa")  -- 正确调用，不会报错


-- 2. 使用__index元方法来实现继承
-- 通过设置table的__index元方法，Lua可以模拟面向对象中的继承。

-- 父类
local Person = {
    name = "Unknown",
    age = 0,

    showInfo = function(self)
        print("Name: " .. self.name .. ", Age: " .. self.age)
    end
}

-- 子类
local Student = {
    major = "Computer Science"
}

-- 设置子类的__index为父类，实现继承
setmetatable(Student, { __index = Person })

-- 创建子类实例
local student = {
    name = "Bob",
    age = 20
}

-- 将实例的metatable设置为子类，这样实例可以访问子类和父类的方法
setmetatable(student, { __index = Student })

-- 使用实例
student:showInfo()  -- 输出: Name: Bob, Age: 20
print(student.major)  -- 输出: Computer Science
