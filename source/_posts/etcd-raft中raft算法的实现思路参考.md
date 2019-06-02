---
title: raft算法及etcd/raft的实现思路借鉴
date: 2019-05-17 16:27:43
tags:
---

#### TL;DR

简单记录一下实践过程，并结合对etcd/raft源码的阅读，总结一下自己的缺陷以及etcd中可借鉴的思想。本文没有介绍raft算法如何实现，关于raft算法的介绍可直接参考以下文档：

1. [《The Raft Consensus Algorithm》](1)
2. [《In Search of an Understandable Consensus Algorithm》](2)
3. [《Raft一致性算法论文：探索一种易理解的一致性算法 中文译文》](3)
4. [《CoreOS 实战：剖析 etcd》](4)
5. [《etcd/raft design》](5)

<!-- more -->

无论是`Kafka`、`Zookeeper`还是`etcd`，这些分布式集群都绕不开“共识算法”，比如Zookeeper使用的`ZAB`、etcd使用的`raft`。其中`raft`算法的共识选举过程有趣好懂，就手痒痒地尝试实现了一下。

#### raft集群的简单实现

在raft一致性算法的相关，详细描述了如何实现选举以及日志同步，基于简单的实践的最低要求，我只简单地完成了以下两点，简单记录一下思路：

##### 节点需要维持的几个重要属性

* currentTerm 当前的任期号，从0开始递增 (Time is divided into terms, and each term begins with an election.)
* commitIndex  当前被调剂哦的最大日志条目的索引值

##### raft的选举过程

raft节点维持一个有限状态机，其中包含 `Follower`, `Candidate`, `Leader`三个状态，状态的转换如下所示：

![状态迁移](http://cloud.atomicer.cn/blog-img/20190517/raft-state-machinepng)

1. `Follower => Candidate`: 所有节点在初始时均设置为`Follower`，正常情况下，相应来自Leader的RPC请求或者候选人的投票请求；心跳超时的时候，感知到`Leader`已经迷失，且暂无候选人征求投票，那么将随机sleep一段时间（避免 split vote），然后将自身置为`Candidate`

2. `Candidate => Leader`: 节点状态为Candidate时，投票给自己，然后向所有的已知节点发送投票请求，统计投票结果：
    1. 多个候选人竞选，有一个节点已超过半数的投票，则承认该节点的Leader地位，将currentTerm更新为该Leader的Term
    2. 多个候选人进行，没有一个节点超过半数投票，本轮未选出leader，在(ElectionTimeout, 2*ElectionTimeout]的休眠时间之后进行下一轮
    3. 当自己获得超过半数的选票时，则将状态从`Candidate`转为`Leader`，并将currentTerm + 1，正如算法描述中说的，每一轮（Term）从一次选举开始，到下一次选举结束。

3. `Leader => Follower`: 当Leader节点无法正常发送心跳导致Follower心跳超时，在Leader节点恢复之后，除了Leader之外的其它节点可能已经重新选举：
    1. 收到anotherLeader的心跳信息，比较两个leader的currentTerm，currentTerm小的将状态切换为Follower
    2. 正常发送心跳信息时，接收到的Response.Term比currentTerm更大，将自己切换为Follower状态

> Follower/Candidate/Leader 的往来消息中，一定包含 `Term`信息

##### 日志复制

raft中的日志(log entry)并不是系统Debug日志，而是序列化后的`command`，这些Command复制到各个节点后，通过序列化内容的解析出命令后，在各个节点上执行并返回操作结果从而实现`复制状态机`

日志复制的过程中，Leader检查并匹配每个Follower节点上当前的日志索引，移动游标到`lastCommit of followerX`的位置并开始复制日志条目到Follower节点中。

###### 关于raft的复制状态机

> 这一部分我没有尝试实现，以下是raft论文中的一些描述

一旦选出了领导人，它就开始接收客户端的请求。每一个客户端请求都包含一条需要被复制状态机（replicated state machine）执行的命令。领导人把这条命令作为新的日志条目加入到它的日志中去，
> 比如分布式存储服务集群，leader节点接收客户端的`curd`命令时，将其转成一条

然后并行的向其他服务器发起 AppendEntries RPC ，要求其它服务器复制这个条目。当这个条目被安全的复制之后，
> 超过半数的节点返回了复制成功的消息；必然存在少数节点可能因运行缓慢、宕机等原因超时的情况

领导人会将这个条目应用到它的状态机中并且会向客户端返回执行结果。
> 这一步就是复制状态机的操作，将输入复制到不同的容错节点后，执行每个节点的状态机，收集每个节点（状态机）的输出结果，比较多个节点，若存在n个结果相同且 `n> counts(nodes) / 2`，则视该结果为正确结果，通过多节点保证输出结果的正确性，这是复制状态机的作用之一。

如果追随者崩溃了或者运行缓慢或者是网络丢包了，领导人会无限的重试 AppendEntries RPC（甚至在它向客户端响应之后）直到所有的追随者最终存储了所有的日志条目。
> 这里描述了存在部分情况下个别Follower节点失联的情况，如果已经有半数节点返回相同的结果，则先返回结果，Leader会在之后不断地尝试与Follower节点同步日志

##### RPC调用

raft共识算法中，维持心跳、日志复制、请求投票均由Leader/Candidate向所有的Follower节点发送，通过 `RequestVote`和 `AppendEntries`两个RPC方法实现。

关于RPC调用的实现，我试过两种方式：

1. `netty` + `avro`简单地实现RPC调用
2. 直接使用`gRPC`

分布式集群中，高性能、高可用的网络框架和序列化框架是必然的选择，`netty` + `avor` 的实践就是在这方面小试牛刀，不过显而易见的是，直接使用netty框架需要关注处理管道、序列化和反序列化的过程等细节。后来使用`gRPC`重写一遍，是为了体会一下使用框架提供的全套解决方案的便利性，etcd/raft使用的也是gRPC。

这里一定要记录我陷入的一个误区，netty本是异步网络框架，为了统计投票，我转了一个大弯实现了netty同步获取返回结果的方法。后来发现etcd在实现raft的过程中，它将所有的消息放到`message box`中，异步地消费消息队列，完全不需要复杂的同步控制逻辑。

#### etcd/raft中的实现细节

##### 状态迁移

> Raft as a state machine. The state machine takes a `Message` as input. A message can either be a local timer update or a network message sent from a remote peer. The state machine's output is a 3-tuple `{[]Messages, []LogEntries, NextState}` consisting of an array of `Messages`, `log entries`, and `Raft state changes`. For state machines with the same state, the same state machine input should always generate the same state machine output.

etcd/raft实现了一个状态机，输入 `Message`，输出 `{[]Messages, []LogEntries, NextState}`，并且确保输出函数的幂等性。其中状态机和输出函数的对应关系如下：

1. `Follower` <-> `stepFollower(r *raft, m pb.Message)`
2. `Candidate` <-> `stepCandidate(r *raft, m pb.Message)`
3. `Leader` <-> `stepLeader(r *raft, m pb.Message)`

> 本来对 “the same state machine input should always generate the same state machine output” 这句话存疑，后来发现raft状态机的输出函数被抽出（不属于raft或者node对象），消除了疑惑

##### Raft状态更新、处理以及驱动方式

###### 选举 心跳 超时

关于选举超时、心跳超时等一系列与时序相关的同步处理，第一反应应该就是用`timer`，etcd/raft的实现类似，使用一个循环等待通道中的消息，在一定的周期内触发raft状态更新、消息发送等操作，不同的是它将“regular intervals”抽象为`Tick`，`Tick`的更新方式以更大自由度的方式留给用户自己实现。

`Tick`可以理解为撞针，每次产生撞击的动作：

1. `electionElapsed/heartbeatElapsed`递增
2. Leader发送心跳
3. Follower/Candidate/Leader根据超时时间检查状态并产生相应动作

> etcd/raft中没有指定何时产生Tick动作，raftexample中给出的例子是由`time.Ticker`驱动(golang中的`time.NewTicker`可以取一个定时发送通知的channel，也是一个定时器)

###### 核心实现

核心逻辑在`raft/node.go`的 `run`函数中：

1. 每个raft node初始化完成时，会有相应的通道接提案、成员变更等消息，同时启动协程轮询检查当前的超时、状态、提案等信息，并将新生成的待发送消息放到Ready通道中
2. 每次Tick事件完成时，产生的新消息（比如需要发送心跳、同步日志等）打包放到node.Ready()通道中，用户可以从此处获取到Ready实体，其中包含需要发送的Messages等内容
3. 用户按照etcd/raft文档中说明的方式，处理Ready实体中所有的内容，等待下个周期的`Tick`触发状态的更新即可。

> 1. Write Entries, HardState and Snapshot to persistent storage in order, i.e. Entries first, then HardState and Snapshot if they are not empty. If persistent storage supports atomic writes then all of them can be written together. Note that when writing an Entry with Index i, any previously-persisted entries with Index >= i must be discarded.
> 2. Send all Messages to the nodes named in the To field. It is important that no messages be sent until the latest HardState has been persisted to disk, and all Entries written by any previous Ready batch (Messages may be sent while entries from the same batch are being persisted). To reduce the I/O latency, an optimization can be applied to make leader write to disk in parallel with its followers (as explained at section 10.2.1 in Raft thesis). If any Message has type MsgSnap, call Node.ReportSnapshot() after it has been sent (these messages may be large). Note: Marshalling messages is not thread-safe; it is important to make sure that no new entries are persisted while marshalling. The easiest way to achieve this is to serialise the messages directly inside the main raft loop.
> 3. Apply Snapshot (if any) and CommittedEntries to the state machine. If any committed Entry has Type EntryConfChange, call Node.ApplyConfChange() to apply it to the node. The configuration change may be cancelled at this point by setting the NodeID field to zero before calling ApplyConfChange (but ApplyConfChange must be called one way or the other, and the decision to cancel must be based solely on the state machine and not external information such as the observed health of the node).
> 4. Call Node.Advance() to signal readiness for the next batch of updates. This may be done at any time after step 1, although all updates must be processed in the order they were returned by Ready.

通过raftexample示例服务启动的代码可窥一斑:

```go
go func() {
    // 提案、配置处理协程
    confChangeCount := uint64(0)

		for rc.proposeC != nil && rc.confChangeC != nil {
			select {
			case prop, ok := <-rc.proposeC:
				if !ok {
					rc.proposeC = nil
				} else {
					// blocks until accepted by raft state machine
					rc.node.Propose(context.TODO(), []byte(prop))
				}

			case cc, ok := <-rc.confChangeC:
				if !ok {
					rc.confChangeC = nil
				} else {
					confChangeCount++
					cc.ID = confChangeCount
					rc.node.ProposeConfChange(context.TODO(), cc)
				}
			}
		}
		// client closed channel; shutdown raft if not already
		close(rc.stopc)
	}()

	// event loop on raft state machine updates
	for {
		select {
		case <-ticker.C:
			rc.node.Tick()

		// store raft entries to wal, then publish over commit channel
        
        // 从Ready通道中获取内容
        case rd := <-rc.node.Ready():
            // 持久化HardState、LogEntities （HardState包含Term、Vote、Commit等信息）
            rc.wal.Save(rd.HardState, rd.Entries)
            // 处理Snapshot
			if !raft.IsEmptySnap(rd.Snapshot) {
				rc.saveSnap(rd.Snapshot)
				rc.raftStorage.ApplySnapshot(rd.Snapshot)
				rc.publishSnapshot(rd.Snapshot)
            }

            // 广播发送日志到所有节点（提交。提交成功的原则：多数节点确认提交）
			rc.raftStorage.Append(rd.Entries)
            rc.transport.Send(rd.Messages)
            // 应用状态机到所有的节点 (lastApply, committedIndex]: 通过commitC通道告诉其它处理协程
			if ok := rc.publishEntries(rc.entriesToApply(rd.CommittedEntries)); !ok {
				rc.stop()
				return
            }
            // 尝试创建snapshot
            rc.maybeTriggerSnapshot()
            // 提示raft (rd) 处理完成完成
			rc.node.Advance()

		case err := <-rc.transport.ErrorC:
			rc.writeError(err)
			return

		case <-rc.stopc:
			rc.stop()
			return
		}
	}
```

##### etcd/raft的日志同步

etcd/raft中用了`Progress`来控制leader和follower之间的日志同步，progress 表示的是在Leader视角下的Follower的日志复制的进度，其中包含了 `probe` `snapshot` `replicate`三种状态，以下是etcd的desin文稿中的描述：

```
                            +--------------------------------------------------------+          
                            |                  send snapshot                         |          
                            |                                                        |          
                  +---------+----------+                                  +----------v---------+
              +--->       probe        |                                  |      snapshot      |
              |   |  max inflight = 1  <----------------------------------+  max inflight = 0  |
              |   +---------+----------+                                  +--------------------+
              |             |            1. snapshot success                                    
              |             |               (next=snapshot.index + 1)                           
              |             |            2. snapshot failure                                    
              |             |               (no change)                                         
              |             |            3. receives msgAppResp(rej=false&&index>lastsnap.index)
              |             |               (match=m.index,next=match+1)                        
receives msgAppResp(rej=true)                                                                   
(next=match+1)|             |                                                                   
              |             |                                                                   
              |             |                                                                   
              |             |   receives msgAppResp(rej=false&&index>match)                     
              |             |   (match=m.index,next=match+1)                                    
              |             |                                                                   
              |             |                                                                   
              |             |                                                                   
              |   +---------v----------+                                                        
              |   |     replicate      |                                                        
              +---+  max inflight = n  |                                                        
                  +--------------------+                                                        
```

###### Probe状态

> `max inflight = 1 `

在这个状态中，leader会在每个心跳周期内至多发送一个复制信息(`replication message`) 到progress对应的follower，此时leader发送的速度是缓慢的，并同时尝试找出follower真实匹配的index（当收到的回复`msgAppResp`是reject类型时，会触发下一交发送操作，可见raft论文中对index匹配的描述）

###### Replicate状态

> `max inflight = n `

leader会发送大量的日志条目到follower中，这个过程etcd-raft是做了优化的

###### Snapshot状态

> `max inflight = 0 `

在这个状态中，leader不会向follower中发送任何日志条目

###### 状态切换

progerss允许的状态切换： `probe  <-> replicate <-> snapshot`

1. init: probe

每一任新的leader产生时， 会针对所有的follower初始化一个progress，并将progerss的状态初始化为`Probe`，由此leader会尝试慢慢地试探follower中可匹配的index。

> etcd/raft/design.md: A newly elected leader sets the progresses of all the followers to probe state with match = 0 and next = last index [etcd/raft design](5)

2. probe <-> replicate

当progress的状态为probe时，leader在试探性地发送`replication message`, 在开始时 match 为 0, next 为最新的日志index + 1，从此处开始试探，直到找到匹配的index为止;

当progress的状态为replicate时，leader会按nextIndex发送日志条目到follower，但可能由于网络通信、机器故障等原因，造成node之间同步失败，follower返回reject信息，此时重新回到probe状态（The progress will fall back to probe when the follower replies a rejection msgAppResp or the link layer reports the follower is unreachable）

> The leader maintains a nextIndex for each follower, which is the index of the next log entry the leader will send to that follower. When a leader first comes to power, it initializes all nextIndex values to the index just after the last one in its log (11 in Figure 7). If a follower’s log is inconsistent with the leader’s, the AppendEntries consistency check will fail in the next AppendEntries RPC. After a rejection, the leader decrements nextIndex and retries the AppendEntries RPC. Eventually nextIndex will reach a point where the leader and follower logs match. When this happens, AppendEntries will succeed, which removes any conflicting entries in the follower’s log and appends entries from the leader’s log (if any). Once AppendEntries succeeds, the follower’s log is consistent with the leader’s, and it will remain that way for the rest of the term. [raft paper](2)

3. probe <-> snapshot

当follower的index落后当前太多条目或需要创建一个snapshot时, leader会发送一个msgSnap的消息，然后等待follower返回任何成功、失败、中止操作等response后重新转为`probe`状态，在这个过程中leader不会向follower发送任何日志条目

#### 回顾

raft有很多详细的文献资料可以参考，而且大多不会晦涩难懂，在初期理解raft集群的工作原理非常有帮助。不过理解原理是一回事，动手实践又是另一回事，这个过程中不乏因为理解错误而做出有问题的实现（表现在coding的时候越来越疑惑，又回过头去翻raft的论文）。有许多的细节需要去考究，比如I/O的实现、持久化存储与日志压缩、超时机制等。参考etcd/raft的实现方式，在尝试理解别人的思考方式的过程中，可以从别的角度找到一些答案，以及许多东西可以借鉴，比如我都不会想到定时器可以抽象为`Tick`（可测试性和可拓展性远高于写死的Timer）

[1]: https://raft.github.io
[2]: https://raft.github.io/raft.pdf
[3]: http://blog.luoyuanhang.com/2017/02/02/raft-paper-in-zh-CN/
[4]: https://www.infoq.cn/article/coreos-analyse-etcd
[5]: https://github.com/etcd-io/etcd/blob/master/raft/design.md
[6]: https://en.wikipedia.org/wiki/Paxos_(computer_science)
