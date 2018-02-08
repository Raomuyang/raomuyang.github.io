---
title: 使用NIO的内存映射计算超大文件的MD5
date: 2017-05-16 00:52:41
meta: [内存映射, NIO, MD5]
tags: [Java]
categories: Java
---

> 在最近的开发及原有方案的改良中，一个feture就是加快对GB级大文件的读取和计算MD5的速度。这是一个IO密集和CPU密集的耗时操作，
在无法硬性提高CPU的条件下，我考虑从IO上如何提高速率。

1. 超大文件的MD5计算，需要分段将文件中的内存更新到MessageDigest中。（注：MessageDigest的实例不能共享，CSDN等博客上介绍MD5计算的demo，将MessageDigest设置为单例模式，单线程计算一个文件的MD5不会出错，多线程计算就会出问题了。）
2. Java的NIO中提供了内存映射，通过将文件的一部分映射到内存中，可以一定程度地提高IO速率，从提高整体的效率。使用NIO的内存映射需要注意
内存的释放（之前未释放内存，在100GB级的文件测试中，抛出了OOM错误）。
<!--more-->

分段计算MD5的代码实现如下：
```Java
public static byte[] getMD5Digits(File file) throws IOException {
        FileInputStream inputStream = new FileInputStream(file);
        FileChannel channel = inputStream.getChannel();
        try {
            MessageDigest messagedigest = MessageDigest.getInstance("MD5");
            long position = 0;
            long remaining = file.length();
            MappedByteBuffer byteBuffer = null;
            while (remaining > 0) {
                long size = Integer.MAX_VALUE / 2;
                if (size > remaining) {
                    size = remaining;
                }
                byteBuffer = channel.map(FileChannel.MapMode.READ_ONLY, position, size);
                messagedigest.update(byteBuffer);
                position += size;
                remaining -= size;
                unMapBuffer(byteBuffer, channel.getClass());
            }
            return messagedigest.digest();
        } catch (NoSuchAlgorithmException e) {
            e.printStackTrace();
            return null;
        } finally {
            channel.close();
            inputStream.close();
        }
    }
```

手动释放映射内存的实现如下：
```Java
    /**
     * JDK不提供MappedByteBuffer的释放，但是MappedByteBuffer在Full GC时才被回收，通过手动释放的方式让其回收
     *
     * @param buffer
     */
    public static void unMapBuffer(MappedByteBuffer buffer, Class channelClass) throws IOException {
        if (buffer == null) {
            return;
        }

        Throwable throwable = null;
        try {
            Method unmap = channelClass.getDeclaredMethod("unmap", MappedByteBuffer.class);
            unmap.setAccessible(true);
            unmap.invoke(channelClass, buffer);
        } catch (NoSuchMethodException e) {
            throwable = e;
        } catch (IllegalAccessException e) {
            throwable = e;
        } catch (InvocationTargetException e) {
            throwable = e;
        }

        if (throwable != null) {
            throw new IOException("MappedByte buffer unmap error", throwable);
        }
    }
```
