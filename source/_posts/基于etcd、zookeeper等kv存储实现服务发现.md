---
title: 基于etcd/zookeeper等kv存储实现服务发现
date: 2018-09-09 22:42:08
tags: [etcd,zookeeper,service-discovery]
meta: [etcd,zookeeper,service-discovery]
categories: [Java]
---

> github 源码地址：  [suniper/plum-mesh-agent](https://github.com/suniper/plum-mesh-agent)

以之前完成的开源项目[suniper-pma](https://github.com/suniper/plum-mesh-agent)的代码实例为例，阐述一下我的服务发现和负载均衡框架是如何实现的 (注：下文中为了更好理解，所贴的代码在源代码的基础上做了一些修改)
<!-- more -->

理论上所有的KV存储都可以作为注册中心，这里以etcd和zk两种介质为例，阐述service discovery的实现过程。

### 实现原理

1. 将服务信息注册到KV Store指定节点的子节点中
2. 通过KV Store中指定的节点获取可用的服务信息初始化可用的服务列表；
3. 监听KV Store中节点的变化，从而实现可用服务列表的动态更新

实现以上场景显然需要我们有一个KV Store的驱动（Generic Driver）从而完成一些必要的操作。在第三点中，我将 `监听KV Store中节点的变化`的功能也划分到这个驱动中，推测可能用到的操作，定义接口如下：

```java
public interface KVStore extends AutoCloseable {
    /**
     * Get node and its data, return null when it does not exist
     *
     * @param key node name
     * @return Node info
     * @throws Exception exception during operation
     */
    Node get(String key) throws Exception;

    /**
     * List all child nodes and their data, return an empty list when
     * the parent node does not exist or has no children
     *
     * @param prefix 父节点
     * @return List of Node
     * @throws Exception exception during operation
     */
    List<Node> list(String prefix) throws Exception;

    /**
     * List the names of all child nodes,
     * return an empty list when the parent node does not exist or has no children
     *
     * @param prefix 父节点
     * @return List of node name
     * @throws Exception exception during operation
     */
    List<String> listKeys(String prefix) throws Exception;

    /**
     * Update the data to the node and persist the storage.
     * <p>
     * Update if the node already exists,
     * but does not modify the type of the node (temporary/persistent)
     *
     * @param key   Node name (configuration directory)
     * @param value Node data (registered service information)
     * @return reversion
     * @throws Exception exception during operation
     */
    long put(String key, String value) throws Exception;

    /**
     * Update data to nodes and persist storage.
     * <p>
     * Update if the node already exists,
     * but does not modify the type of the node (temporary/persistent)
     *
     * @param key       node name (configuration directory)
     * @param value     node data (registered service information)
     * @param ephemeral is a temporary node
     * @return reversion
     * @throws Exception exception during operation
     */
    long put(String key, String value, boolean ephemeral) throws Exception;

    /**
     * Delete the node
     *
     * @param key node name
     * @return Number of nodes successfully deleted
     * @throws Exception IllegalArgumentException: Node is not empty
     * @throws Exception exception during operation
     *                        
     */
    long delete(String key) throws Exception;

    /**
     * Whether the node exists
     * <p>
     * 节点是否存在
     *
     * @param key node name 节点名称
     * @return true: exists 存在
     * @throws Exception exception during operation
     */
    boolean exists(String key) throws Exception;

    /**
     * Monitor changes to all child nodes (without parent nodes), continuous monitoring
     * <p>
     * 监视所有子节点的变化（不包含父节点），持续监听
     *
     * @param key      Name of parent node 父节点名称
     * @param consumer Callback when child nodes change 子节点变化时的回调
     * @throws Exception exception during operation
     */
    void watchChildren(String key, BiConsumer<Event, Node> consumer) throws Exception;

    /**
     * Monitor the changes of all child nodes (excluding the parent node),
     * and judge whether it needs to exit the monitoring according to the exit signal.
     * <p>
     * 监视所有子节点的变化（不包含父节点），根据退出信号判断是否需要退出监听
     *
     * @param key              Name of parent node 父节点名称
     * @param exitSignSupplier Provide an exit signal, otherwise it will always listen 提供退出信号，否则一直监听
     * @param consumer         子节点变化时的回调
     * @throws Exception exception during operation
     */
    void watchChildren(String key, Supplier<Boolean> exitSignSupplier, BiConsumer<Event, Node> consumer) throws Exception;

    /**
     * Used to create a parent (prefix) and a persistent node
     * <p>
     * 用于创建父节点（prefix）, 且为持久节点
     *
     * @param parentNode Name of parent node 父节点名称
     * @throws Exception exception during operation
     */
    void createParentNode(String parentNode) throws Exception;
```

  一方面，基于`KVStore`接口，我们得以在无须关注介质类型（KVStore实现）的情况下，将服务发现的操作单独抽出进行开发；
另一方面，在本文的实现方式中，我将 `监听KV Store中节点的变化`的功能也划分到这个驱动中，所以`KVStore`对存储介质的子节点的动态监听的实现，即`witchChildren`接口构成了服务发现的重要闭环。

想必也注意到了 `put(String key, String value, boolean ephemeral)` 接口，是的，`KVStore`必须满足可以注册临时节点。服务程序启动时将自己的信息注册到KVStore并且维护一个心跳保持节点信息的有效，这样在服务崩溃或停止时KV Store中存储的信息会自动失效，从而保证服务发现逻辑中拿到的都是有效的服务列表。

另外，在对服务节点监听到的状态变化中，我们将其分为三类：
```java
public enum Event {
    UPDATE,
    DELETE,
    UNRECOGNIZED
}
```

### kv store的etcd的实现

> 源码地址：[plum-mesh-discovery-etcd](https://github.com/suniper/plum-mesh-agent/tree/master/plum-mesh-discovery-etcd)

etcd的基本操作可由`com.coreos.jetcd 0.0.2`实现，我们只需关注`如何监听子节点的变化`以及`如何创建临时节点`

#### 子节点监听

etcd的存储结构类似阿里云的oss，是扁平的kv存储结构，可以直接通过 `prefix` 检索，举个例子：

+ kv: v1
    + zookeeper: v2
        + content: v3
    + etcd: v4
    + mongo: v5

etcd可以通过kv可以表达出以上的层次化结构，但是在存储中实际为平行的一系列的键:
* kv/zookeeper
* kv/zookeeper/content
* kv/etcd
* kv/mongo

所以在etcd中可以很方便地通过`prefix`监听所有的“子节点”，根据节点变化的事件回调`Consumer`：

```java
@Override
    public void watchChildren(String key, Supplier<Boolean> exitSignSupplier, BiConsumer<Event, Node> consumer) throws InterruptedException {
        ByteSequence storeKey =
                Optional.ofNullable(key)
                        .map(ByteSequence::fromString)
                        .orElse(null);

        try (Watch watch = client.getWatchClient();
             Watch.Watcher watcher = watch.watch(storeKey,
                     WatchOption.newBuilder().withPrefix(storeKey).build())) {
            while (!exitSignSupplier.get()) {
                WatchResponse response = watcher.listen();
                response.getEvents().forEach(watchEvent -> {
                    // 跳过根节点的变化
                    if (watchEvent.getKeyValue().getKey().equals(storeKey)) return;
                    Event event; // 此处的Event为上一节中定义的枚举类型
                    switch (watchEvent.getEventType()) {
                        case PUT:
                            event = Event.UPDATE;
                            break;
                        case DELETE:
                            event = Event.DELETE;
                            break;
                        default:
                            event = Event.UNRECOGNIZED;
                    }
                    KeyValue keyValue = watchEvent.getKeyValue();
                    Node info = kv2NodeInfo(keyValue);
                    consumer.accept(event, info);
                });
            }
        }
    }
```

#### 创建临时的节点

很遗憾，etcd没有提供临时id的功能，但是它提供了一个[租约 Lease](https://coreos.com/etcd/docs/latest/dev-guide/interacting_v3.html)的概念,我们可以在初始化客户端时，同时生成一个租约，并且在租约到期时自动续约。当服务崩溃或者停止时，不再有能力自动续约，则节点自动失效。

##### 生成租约并自动续约：

```java
private static final int EPHEMERAL_LEASE = 60; // seconds
private Client client;
private long leaseId;

private void initLease() throws ExecutionException, InterruptedException {
        Lease lease = client.getLeaseClient();
        LeaseGrantResponse response = lease.grant(EPHEMERAL_LEASE).get();
        leaseId = response.getID();
        lease.keepAlive(leaseId);
}
```

##### 实现可临时节点的方法
```java

@Override
    public long put(String key, String value, boolean ephemeral) throws ExecutionException, InterruptedException {
        log.debug(String.format("put %s to %s", value, key));
        KV kv = client.getKVClient();
        ByteSequence storeKey =
                Optional.ofNullable(key)
                        .map(ByteSequence::fromString)
                        .orElse(null);
        ByteSequence storeValue =
                Optional.ofNullable(value)
                        .map(ByteSequence::fromString)
                        .orElse(null);
        PutOption.Builder builder = PutOption.newBuilder();
        if (ephemeral) builder.withLeaseId(leaseId);

        PutResponse response = kv.put(storeKey,
                storeValue, builder.build()).get();
        log.info(String.format("put key-value: key: %s, reversion: %s, has-prev: %s, ephemeral: %s",
                key, response.getHeader().getRevision(), response.hasPrevKv(), ephemeral));
        return response.getHeader().getRevision();
    }
```

> 由于租约到期会根据`EPHEMERAL_LEASE`有一定的延迟，所以服务发现时有一定的几率拿到失活状态的服务

### kv store的zookeeper的实现

> 源码地址：[plum-mesh-discovery-zk](https://github.com/suniper/plum-mesh-agent/tree/master/plum-mesh-discovery-zk)

zookeeper的基本操作可由`org.apache.zookeeper`实现, 最新版为`3.4.12`。和etcd一样，我们只需关注`如何监听子节点的变化`以及`如何创建临时节点`

#### 子节点监听

zookeeper提供了`Watcher`，可以对某一节点的变化进行监听，以下面的层次结构为例：

+ kv: v1
    + zookeeper: v2
        + content: v3
    + etcd: v4
    + mongo: v5

一、和etcd有所不同，zookeeper的的node与文件系统的层次结构一样，有着严格的parent和children的一对多的关系，无法通过`prefix`递归列出所有的子节点
二、zk的`Watcher`只能对一个Node进行监听，并且回调了Event事件之后，这个`Watcher`随即失效
三、`Watcher`可以监听节点本身的事件（`Update`、`Delete`等）以及子节点更新的事件（`NodeChildrenChanged`）

基于以上三点，已经可以满足我们实现类似etcd的子节点监听的要求：对`kv/`的子节点进监听，当新增了节点或 `kv/zookeeper`、 `kv/etcd`、 `kv/mongo`发生变化时回调事件（`kv/zookeeper/content`的变化无需关注）：

* 监视节点及子节点的变化：
* 当前节点发生改变时，不做任何处理；
* 子节点发生变化时，创建相应的sub-node watcher监听子节点的变化，并调用回调通知变化的信息


##### 继承`Watcher`, 实现常规的监听器（和etcd的实现逻辑类似）

常规操作，根据节点变化的事件回调`Consumer`

```Java
/**
     * Watch change of node
     */
    class SubWatcher implements Watcher {

        private BiConsumer<cn.suniper.mesh.discovery.model.Event, Node> consumer;
        private Supplier<Boolean> exitSignSupplier;
        private volatile boolean stopWatch;

        SubWatcher(BiConsumer<cn.suniper.mesh.discovery.model.Event, Node> consumer, Supplier<Boolean> exitSignSupplier) {
            this.consumer = consumer;
            this.exitSignSupplier = exitSignSupplier;
        }

        @Override
        public void process(WatchedEvent event) {
            if (exitSignSupplier.get()) {
                log.info("sub-node: stop watch event: " + event);
                return;
            }

            log.debug("sub-node: watch event: " + event);
            cn.suniper.mesh.discovery.model.Event wrapEvent;
            Node node;
            switch (event.getType()) {

                case NodeCreated:
                case NodeDataChanged:
                    wrapEvent = cn.suniper.mesh.discovery.model.Event.UPDATE;
                    try {
                        node = get(event.getPath(), this);
                        log.debug(String.format("get node(%s) data: ", event.getPath()) + node);

                    } catch (Throwable throwable) {
                        log.warn("error occurred in watcher", throwable);
                        return;
                    }
                    break;
                case NodeDeleted:
                    wrapEvent = cn.suniper.mesh.discovery.model.Event.DELETE;
                    node = new Node();
                    node.setKey(event.getPath());
                    break;
                default:
                    wrapEvent = cn.suniper.mesh.discovery.model.Event.UNRECOGNIZED;
                    node = new Node();
                    node.setKey(event.getPath());
            }

            stopWatch = true;
            consumer.accept(wrapEvent, node);
        }

        private SubWatcher activate() {
            this.stopWatch = false;
            return this;
        }
    }
```

##### 继承`Watcher`，实现根节点的监听器

这个监听器只监听根节点下所有子节点的变化。当根节点发生改变时（新增、删除），list该节点下所有的节点，并检查是否有对应的`SubWatcher`(子节点事件监听器)，若无则为其新建一个监听器：

```java

    class ChildrenWatcher implements Watcher {

        private final Supplier<Boolean> DEFAULT_SUPPLIER = () -> false;

        private ConcurrentHashMap<String, SubWatcher> childrenWatcher;
        private BiConsumer<cn.suniper.mesh.discovery.model.Event, Node> consumer;
        private String path;
        private Supplier<Boolean> exitSignSupplier;

        ChildrenWatcher(String path, BiConsumer<cn.suniper.mesh.discovery.model.Event, Node> consumer,
                        Supplier<Boolean> exitSignSupplier) {
            this.consumer = consumer;
            this.childrenWatcher = new ConcurrentHashMap<>();
            this.path = path;
            this.exitSignSupplier = exitSignSupplier == null ? DEFAULT_SUPPLIER : exitSignSupplier;
            this.listAndWatch(false);
        }

        @Override
        public void process(WatchedEvent event) {
            log.debug("parent-node: watch event: " + event);

            if (exitSignSupplier.get()) {
                log.info("parent-node: stop watch event: " + event);
                return;
            }

            switch (event.getType()) {
                case NodeChildrenChanged:
                    this.listAndWatch(true);
                    return;
                default:
                    log.debug("ignore event");
            }

            try {
                List<String> res = listKeys(path, this);
                log.debug(String.format("Sub nodes of %s: %s", path, res));
            } catch (Exception e) {
                log.warn("failed to keep watch node: " + path, e);
            }

        }

        private void listAndWatch(boolean accept) {
            try {
                List<String> subList = listKeys(path, this);

                log.debug(String.format("size of %s: %s", path, subList.size()));
                for (String sub : subList) {
                    SubWatcher watcher = childrenWatcher.computeIfAbsent(sub, k -> {
                        log.debug("create new watcher for " + sub);
                        SubWatcher newWatcher = new SubWatcher(consumer, exitSignSupplier);
                        newWatcher.stopWatch = true;
                        return newWatcher;
                    });

                    if (!watcher.stopWatch) continue;

                    log.debug("activate watcher for " + sub);
                    watcher.activate();

                    if (accept) {
                        Node node = get(sub, watcher);
                        consumer.accept(cn.suniper.mesh.discovery.model.Event.UPDATE, node);
                    } else {
                        zooKeeper.exists(sub, watcher, null, null);
                    }
                }

            } catch (Exception e) {
                log.warn("failed to list and watch node: " + path, e);
            }
        }
    }
    
```

#### 创建临时的节点

zookeeper本身支持创建临时的节点，实现的原理是zk客户端会维持与zk服务的心跳，当客户端退出时，服务端检测到心跳超时，就会自动删除该临时节点。

```java
    @Override
    public long put(String key, String value, boolean ephemeral) throws Exception {
        Stat stat = zooKeeper.exists(key, null);
        if (stat != null) {
            zooKeeper.setData(key, value.getBytes(), stat.getVersion());
        } else {
            CreateMode mode = ephemeral ? CreateMode.EPHEMERAL : CreateMode.PERSISTENT;
            zooKeeper.create(key, value.getBytes(), ZooDefs.Ids.OPEN_ACL_UNSAFE, mode);
        }

        stat = zooKeeper.exists(key, null);
        log.info(String.format("current stat: %s", stat));
        return stat.getMzxid();
    }
```

#### 关于多级父目录的创建

zk节点的每一级父目录必须为真实存在的节点，不像etcd一样可以为虚拟的prefix，所以需要递归创建父目录：

```java
@Override
public void createParentNode(String parentNode) throws Exception {
        PathUtils.validatePath(parentNode);
        if (parentNode.equals("/")) return;
        File node = new File(parentNode);
        String parent = node.getParent();
        if (!exists(parent)) {
            createParentNode(parent);
        }
        put(parentNode, DEFAULT_NODE_VALUE);
}
```

### 在`KVStore`的基础上完成服务注册与发现

> 源码地址 > [plum-mesh-discovery-core](https://github.com/suniper/plum-mesh-agent/tree/master/plum-mesh-discovery-core)

#### 服务注册

1. 无论使用何种KV Store，我们将注册服务的信息注册到一个指定的根节点，这里我们设为 `/config/suniper`
2. Register注册服务时，在根节点下创建以 `{ServerGroup}`为名的节点 => `/config/suniper/{ServerGroup}`
3. 相关的服务信息会存储在子节点中： key: `/config/suniper/{AppName}` <=> value: `ip/port/weight`
4. 服务信息存储的节点会注册为临时节点，Register会以守护线程的方式保持连接，所以所有的KV Store必须满足客户端断开连接一段时间之内会节点会自动失效 (KVStore提供的临时节点注册为我们提供了这个能力)

将服务提供者(Provider)以及服务注册相关信息作如下封装（部分信息是为了功能的拓展，不在这里介绍）:

```java

public class ProviderInfo {
    // provider
    private String name;
    private String ip;
    private int weight;
    private int port;
    private long version;
}

public class Application {
    private List<String> registryUrlList; // 用作注册中心的host:port列表
    private ProviderInfo providerInfo;
    private String serverGroup; // 所在的服务组
}
```

创建相应节点`/config/suniper/{ServerGroup}`并将Provider信息注册到这个节点中.

```java
public void register(Application application) throws Exception {
        String parentNode = String.join("/", Constants.STORE_ROOT, application.getServerGroup());
        ProviderInfo providerInfo = Optional.ofNullable(application.getProviderInfo())
                .orElse(new ProviderInfo());

        if (providerInfo.getIp() == null) {
            InetAddress address = HostUtil.getLocalIv4Address();
            if (address != null) providerInfo.setIp(address.getHostAddress());
            else throw new IllegalStateException("cannot get local host IP address");
        }
        if (providerInfo.getPort() == 0 || providerInfo.getName() == null) {
            throw new IllegalArgumentException("please check you provider info");
        }
        String storeValue = String.format("%s/%s/%s",
                providerInfo.getIp(),
                providerInfo.getPort(),
                providerInfo.getWeight());

        String storeKey = String.join("/", parentNode, providerInfo.getName());

        // check and create
        store.createParentNode(parentNode);
        long reversion = store.put(storeKey, storeValue, true);
        log.info(String.format("registered server: `%s` in node: `%s`, reversion: %s",
                storeKey, storeValue, reversion));
    }
```

> 通常情况下，我们再服务启动时调用register方法，将服务的信息注册到zk/etcd等注册中心中

#### 服务发现

在`服务注册`的操作中，我们已经明确了Node路径的生成规则，所以根据服务组`{ServerGroup}`我们就可以通过list根节点`/config/suniper/{ServerGroup}`获取到该服务组中所有的可用的服务列表；通过监听该根节点(`KVStore.watchChildren`)，我们可以实时获取到节点更新的信息。

一、我们只需要调用 `KVStore.list("/config/suniper/{ServerGroup}")`即可获取到初始化的服务列表

二、通过监听根节点的变化，我们可以实时更新服务的列表： `watchChildren(String key, Supplier<Boolean> exitSignSupplier, BiConsumer<Event, Node> consumer)`
> `exitSignSupplier`是一个退出信号的生成器，当不再需要监听时，只需令supplier发送一个`true`的退出信号即可，这个不在这里敷述，可以看源代码了解相关的实现。

我们关注一下`BiConsumer<Event, Node> consumer`如何实现，直接以代码和注释就行理解:

```java
private class Holder implements BiConsumer<Event, Node> {
        private Map<String, ProviderInfo> providerInfoMap; // 缓存 node path 和 provider info的对应关系（这个Map必须是线程安全的）
        private UpdateAction updateAction; // 执行服务列表更新动作的类，这里知道它的行为即可
        private final AtomicLong lastUpdated = new AtomicLong(System.currentTimeMillis()); // 记录列表的最后更新时间

        Holder(UpdateAction updateAction, Map<String, ProviderInfo> providerInfoMap) {
            this.providerInfoMap = providerInfoMap;
            this.updateAction = updateAction;
        }

        @Override
        public void accept(Event event, Node node) {
            // 将所有的事件分为 delete 和 update 两类
            String key = node.getKey();
            switch (event) {
                case DELETE:
                    // 子节点失效（被删除）时，移除本地缓存的Provider信息
                    ProviderInfo removed = providerInfoMap.remove(key);
                    if (removed != null)
                        log.info(String.format("Service offline: %s - %s:%s", key, removed.getIp(), removed.getPort()));
                    else
                        log.info("Service offline: %s - no such provide cache");
                    update();
                    break;
                case UPDATE:
                    // 子节点更新时（新增/更新属性）
                    ProviderInfo oldInfo = providerInfoMap.computeIfAbsent(key, k -> new ProviderInfo());
                    MapperUtil.node2Provider(node, oldInfo); // 这个方法将node信息转为provider信息，并更新旧的provider信息（使用缓存，减少对象创建的次数）
                    update();
                    break;
                default:
                    log.info(String.format("unrecognized event: %s, key: %s", event, node.getKey()));

            }
        }

        private void update() {
            // 通知updateAction更新缓存的服务列表
            lastUpdated.set(System.currentTimeMillis());
            updateAction.doUpdate();
        }

    }
```

获取并更新列表，统一在同一个方法中，每次list注册中心中的所有子节点并更新本地的Providers缓存

```java

List<RegisteredServer> obtainServerListByKvStore(Map<String, ProviderInfo> providerInfoMap) {
        // providerInfoMap: 同上，缓存 node path 和 provider info的对应关系（这个Map必须是线程安全的）
        Set<String> newKeys = new HashSet<>();
        Consumer<Node> collectNewNodesToSet = node -> newKeys.add(node.getKey());

        try {
            List<Node> nodeInfoList = store.list(parentNode);
            Stream<ProviderInfo> stream = nodeInfoList
                    .stream()
                    .peek(collectNewNodesToSet) // 将所有的node path添加到set中
                    .map(node -> providerMap.computeIfAbsent(
                            node.getKey(), k -> MapperUtil.node2Provider(node))); // 将节点转换为ProviderInfo并put到providerMap

            providerMap.keySet()
                    .parallelStream()
                    .filter(k -> !newKeys.contains(k)) // 过滤出providerMap中已经失效的provider信息（store.list返回的列表中不再存在）
                    .forEach(k -> providerMap.remove(k)); // 移除这些已失效的provider信息
            return map2ServerList(stream); // 将剩下的信息转换为Server List

        } catch (Exception e) {
            log.warn(String.format("failed to obtain list of servers: %s", parentNode), e);
            return Lists.newArrayList();
        }
    }
```

### 负载均衡的实现

负载均衡算法种类很多，为了满足`pma`的高可用性，这里我用了[Netflix/ribbon](https://github.com/Netflix/ribbon/wiki)中的负载均衡模块 `ribbon-loadbalancer`：

```xml
<dependency>
    <groupId>com.netflix.ribbon</groupId>
    <artifactId>ribbon-core</artifactId>
    <version>${ribbon.version}</version>
</dependency>
<dependency>
    <groupId>com.netflix.ribbon</groupId>
    <artifactId>ribbon-loadbalancer</artifactId>
    <version>${ribbon.version}</version>
</dependency>
```

接入`ribbon`的功能，我们需要分别实现/拓展如下接口/类：

* Server meta: com.netflix.loadbalancer.Server
* 服务列表更新器: com.netflix.loadbalancer.ServerListUpdater
* 动态服务列表: com.netflix.loadbalancer.ServerList

实现了以上接口之后，便可按照[Netflix/ribbon](https://github.com/Netflix/ribbon/wiki)提供的方式使用他提供的负载均衡: [doc](https://github.com/suniper/plum-mesh-agent/blob/master/README.md)

#### 动态服务列表

动态服务列表继承自 `com.netflix.loadbalancer.ServerList`, 只需实现如下方法：

```java
public List<T> getInitialListOfServers();
public List<T> getUpdatedListOfServers();
```

在上节的`服务发现`中提到了，`obtainServerListByKvStore`可以获取并更新可用的服务列表，所以只需将`obtainServerListByKvStore`的值返回即可。

#### 服务列表更新器

服务列表更新器需要实现以下接口，

```java
public interface ServerListUpdater {

    /**
     * start the serverList updater with the given update action
     * This call should be idempotent.
     *
     * @param updateAction
     */
    void start(UpdateAction updateAction);

    /**
     * stop the serverList updater. This call should be idempotent
     */
    void stop();

    /**
     * @return the last update timestamp as a {@link java.util.Date} string
     */
    String getLastUpdate();

    /**
     * @return the number of ms that has elapsed since last update
     */
    long getDurationSinceLastUpdateMs();

    /**
     * @return the number of update cycles missed, if valid
     */
    int getNumberMissedCycles();

    /**
     * @return the number of threads used, if vaid
     */
    int getCoreThreads();
}
```

事实上这些接口与上节的服务发现介绍的`Consumer`的功能高度重合，只需要将上面实现的`Holder`对接到Updater中即可，具体实现可见源代码 [RegistryServerListUpdater.java](https://github.com/suniper/plum-mesh-agent/blob/master/plum-mesh-discovery-core/src/main/java/cn/suniper/mesh/discovery/RegistryServerListUpdater.java)

以上，[suniper-pma](https://github.com/suniper/plum-mesh-agent)的服务发现和负载均衡组件的实现粗糙的介绍到此结束。

### BTW

* `ribbon-loadbalancer`的文档真非常简短，很多东西都不明就里而且googole不到，只能通过看源代码来了解实现机理以及如何使用
* `ribbon`的官方文档中没有说在pom依赖中应该添加哪些依赖，`ribbon-loadbalancer-2.3.0`的pom中看到所有的依赖都是使用`<scope>runtime</scope>`，在使用的时候屡屡受挫；想了解其他人是如何使用这个模块，但是只能搜到大家都直接用spring-cloud集成的功能

#### 关于 `WeightedResponseTimeRule`的负载均衡规则

> The rule that use the average/percentile response times to assign dynamic "weights" per Server which is then used in the "Weighted Round Robin" fashion.

`ribbon`的负载均衡中有一个`WeightedResponseTimeRule`，然而从文档没有详细的介绍，源代码中我都没有找到每一轮更新权重(`weights`)值的地方，在StackOverflow上提了问题，暂时没有人解答，这里先mark一下。 [WeightedResponseTimeRule: how it work in ribbon?](https://stackoverflow.com/questions/50964452/weightedresponsetimerule-how-it-work-in-ribbon)

```java
     public T executeWithLoadBalancer(final S request, final IClientConfig requestConfig) throws ClientException {
        LoadBalancerCommand<T> command = buildLoadBalancerCommand(request, requestConfig);

        try {
            return command.submit(
                new ServerOperation<T>() {
                    @Override
                    public Observable<T> call(Server server) {
                        URI finalUri = reconstructURIWithServer(server, request.getUri());
                        S requestForServer = (S) request.replaceUri(finalUri);
                        try {
                            return Observable.just(AbstractLoadBalancerAwareClient.this.execute(requestForServer, requestConfig));
                        } 
                        catch (Exception e) {
                            return Observable.error(e);
                        }
                    }
                })
                .toBlocking()
                .single();
        } catch (Exception e) {
            Throwable t = e.getCause();
            if (t instanceof ClientException) {
                throw (ClientException) t;
            } else {
                throw new ClientException(e);
            }
        } 
    }
```