---
title: JVM的内存区及数据在内存中的存储
date: 2016-04-1 09:01:30
tags: [Java,jvm,stack,heap]
meta: [jvm,堆和栈的区别]
categories: [Java]
---

> JVM在执行JAVA程序时，会将不同的数据装载并存放在不同的内存区中这些数据内存区统称为"Runtime Data Area",
其中即分为我们熟识的三个主要区域：Heap、Stack和Method Area

### Heap（堆）
在Java程序运行时，只有一个Heap区域，用于存放程序所有的对象（不包括基本的数据类型），是线程共享的区域，我们常提到的GC
基本都是活动在这个区域。和C语言一样，Heap区域需要由程序员手动申请空间，但是因为java中存在GC，java中就不需要像C语言一
样，实时地考虑对不再使用的空间进行释放

### Stack（栈）
栈是一种FILO（先进后出）的数据结构，在JVM中，栈区是绑定在java程序的每一个线程上的，存放局部变量、对象的引用、操作指令等，
并且为线程所私有，不允许被其它线程访问，所以线程的生命周期就是栈的声明周期。<br>
栈中维护的单位为栈帧，每调用一个方法，都会启用一个栈帧，而方法中的局部变量、操作数都是存放在栈帧中。Java中方法调用的过程
也是对栈的操作过程。


### Method Area (方法区)
方法区也称静态区，是JVM的一个逻辑内存区域，在编译、执行Java程序时，类加载器（ClassLoader）加载的类（描述）信息会存入
方法区。对于静态变量，因为是所有实例化对象全局共享的，所以指向的是同一块内存，故从设计上静态变量也应该是在类加载时装载
进方法区的类信息，因此静态变量也是存储在方法区中的。

>*[Chapter 2. The Structure of the Java Virtual Machine](http://docs.oracle.com/javase/specs/jvms/se7/html/jvms-2.html#jvms-2.5.4)<br>
The Java Virtual Machine has a method area that is shared among all Java Virtual Machine threads. The method area is analogous to the storage area for compiled code of a conventional language or analogous to the "text" segment in an operating system process. It stores per-class structures such as the run-time constant pool, field and method data, and the code for methods and constructors, including the special methods  used in class and instance initialization and interface initialization.*

<!--more-->
### Stack和Heap的区别
+ Heap中内存分配由程序员手动执行，而 Stack中由编译器自动分配和释放
+ Heap是比较大的自由空间，大小可以通过JVM调优来控制；Stack是大小有限的一个空间
+ Heap通过new来分配内存，相比Stack而言速度比较慢，并且堆内的内存不是共享的，而在栈中的内存可以共享，通过
  下面代码，便可了解Heap和Stack的不同
```
public static void main(String[] args) {
		// TODO Auto-generated method stub
		String a = "asdf";
		String b = "asdf";
		String c = get1();
		String d = get2();
    String e = new String("asdf");
    String f = new String("asdf");
		System.out.println(a==b);
		System.out.println(c==d);
		System.out.println(a==c);
    System.out.println(e==f);
	}

	static String get1(){
		String a = "asdf";
		return a;
	}
	static String get2(){
		String a = "asdf";
		return a;
	}
```
输出：true  true  true false
