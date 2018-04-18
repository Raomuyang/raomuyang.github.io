---
title: redis分布式锁
date: 2018-02-11 10:17:39
tags: [redis]
---

基于redis的分布式锁可以基于redis的`set`命令实现：
  * NX 当不存在时创建
  * EX 设置 n 秒後过期

删除操作需要借助`eval`命令的原子性 [eval命令文档](http://redisdoc.com/script/eval.html)
> if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end

通过对这段lua脚本求值，防止过期时误解锁
<!-- more -->

以下是使用golang的实现形式，java可借助jedis，实现原理相同

```golang

package lock

import (
	"github.com/garyburd/redigo/redis"
	"errors"
	"github.com/satori/go.uuid"
	"crypto/md5"
	"fmt"
)

const (
	PREFIX  = "lock->"
	script    = "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end"

)
type RedisLock struct {
	pool       *redis.Pool
	expireTime int
	key        string
	value      string
}

func NewLock(name string, pool *redis.Pool, expireSeconds int) (*RedisLock, error) {
	if name == "" {
		return nil, errors.New("illegal argument: name")
	}
	key := PREFIX + name
	valueContent := uuid.NewV1().String() + key
	md5sum := md5.New()
	md5sum.Write([]byte(valueContent))

	lock := RedisLock{
		key: key,
		value: fmt.Sprintf("%x", md5sum.Sum(nil)),
		pool: pool,
		expireTime:expireSeconds}
	return &lock, nil
}



func (redisLock *RedisLock) TryLock() (bool, error) {
	dbConn := redisLock.pool.Get()
	rep, err := dbConn.Do("SET",
		redisLock.key, redisLock.value, "NX", "EX", redisLock.ExpireTime())
	if err != nil {
		return false, err
	}

	if rep == nil {
		return false, nil
	}
	result, err := redis.String(rep, err)
	if result == "OK" {
		return true, nil
	}
	return false, err
}

func (redisLock *RedisLock) Unlock() error {
	dbConn := redisLock.pool.Get()
	_, err := dbConn.Do("EVAL", script, 1, redisLock.key, redisLock.value)
	return err
}

func (redisLock *RedisLock) ExpireTime() int {
	if redisLock.expireTime == 0 {
		// default one day
		return 60 * 60 * 24
	}
	return redisLock.expireTime
}

func (redisLock *RedisLock) SetExpireTime(expireTime int) {
	redisLock.expireTime = expireTime
}



```
