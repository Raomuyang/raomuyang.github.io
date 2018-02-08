---
title: java 获取annotation的值以及通过反射实例化一个对象的过程
date: 2016-05-7 14:14:50
tags: [Java,反射,annotation]
meta: [Java,反射,annotation]
categories: [Java]
---

> 在Java程序开发中，反射和Annotation极大地方便了我们在编程时注入对象。Spring框架的底层实现便大量地使用了反射和主机。这里使用的是javax.persistence包中定义的一些注解，除了javax.persistence包中已经定义好的一些注解，我们还可以根据需要自定义注解。


> ### 定义Bean，注意get方法和set方法命名的规范
<!--more-->
```java
import javax.persistence.*;

@Table(name = "tb_user", schema = "juwoer")
public class User {
    private String name;

    @Basic
    @Column(name = "u_Name", nullable = false, length = 255)
    public String getName() {
        return name;
    }

    public void setName(String uName) {
        this.name = uName;
    }

}
```
> ### 获取Annotation的值及反射的操作
```java
import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import javax.persistence.Table;

public class Test {

	/**
	 * @param args
	 * @throws IllegalAccessException
	 * @throws InstantiationException
	 */
	public static void main(String[] args) throws InstantiationException, IllegalAccessException {
		// TODO Auto-generated method stub
		Table annotation = User.class.getAnnotation(Table.class);

		//获取类的注解
		System.out.println(annotation.toString());
		System.out.println(annotation.name());

		//通过class实例化User对象
		User u = User.class.newInstance();

		//用反射获取所有的域（包括私有的）
		Field[] fs = User.class.getDeclaredFields();
		for(Field f:fs){
			//因为User的name是private的
			//若不将可访问设为私有，会抛出[can not access a member of class annotation.User with modifiers "private"]的异常
			f.setAccessible(true);
			f.set(u, "test");//这里就给每bean的每个成员都赋值test
		}

		System.out.println(u.getName());
	}

}
```
