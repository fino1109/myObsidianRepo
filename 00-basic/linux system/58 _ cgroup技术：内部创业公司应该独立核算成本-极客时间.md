我们前面说了，容器实现封闭的环境主要靠两种技术，一种是“看起来是隔离”的技术 Namespace，另一种是用起来是隔离的技术 cgroup。

上一节我们讲了“看起来隔离“的技术 Namespace，这一节我们就来看一下“用起来隔离“的技术 cgroup。

cgroup 全称是 control group，顾名思义，它是用来做“控制”的。控制什么东西呢？当然是资源的使用了。那它都能控制哪些资源的使用呢？我们一起来看一看。

首先，cgroup 定义了下面的一系列子系统，每个子系统用于控制某一类资源。

CPU 子系统，主要限制进程的 CPU 使用率。

cpuacct 子系统，可以统计 cgroup 中的进程的 CPU 使用报告。

cpuset 子系统，可以为 cgroup 中的进程分配单独的 CPU 节点或者内存节点。

memory 子系统，可以限制进程的 Memory 使用量。

blkio 子系统，可以限制进程的块设备 IO。

devices 子系统，可以控制进程能够访问某些设备。

net_cls 子系统，可以标记 cgroups 中进程的网络数据包，然后可以使用 tc 模块（traffic control）对数据包进行控制。

freezer 子系统，可以挂起或者恢复 cgroup 中的进程。

这么多子系统，你可能要说了，那我们不用都掌握吧？没错，这里面最常用的是对于 CPU 和内存的控制，所以下面我们详细来说它。

在容器这一章的第一节，我们讲了，Docker 有一些参数能够限制 CPU 和内存的使用，如果把它落地到 cgroup 里面会如何限制呢？

为了验证 Docker 的参数与 cgroup 的映射关系，我们运行一个命令特殊的 docker run 命令，这个命令比较长，里面的参数都会映射为 cgroup 的某项配置，然后我们运行 docker ps，可以看到，这个容器的 id 为 3dc0601189dd。

docker run -d --cpu-shares 

 513 

 --cpus 

 2 

 --cpuset-cpus 

 1,3 

 --memory 

 1024M --memory-swap 

 1234M --memory-swappiness 

 7 -p 

 8081:80 testnginx:1

\# docker ps

CONTAINER ID IMAGE COMMAND CREATED STATUS PORTS NAMES

3dc0601189dd testnginx:1 

 "/bin/sh -c 'nginx -…" About a minute ago Up About a minute 0.0.0.0:8081->80/tcp boring_cohen

在 Linux 上，为了操作 cgroup，有一个专门的 cgroup 文件系统，我们运行 mount 命令可以查看。

cgroup on /sys/fs/cgroup/systemd type cgroup (rw,nosuid,nodev,noexec,relatime,xattr,release_agent=/usr/lib/systemd/systemd-cgroups-agent,name=systemd)

cgroup on /sys/fs/cgroup/net\_cls,net\_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net\_prio,net\_cls)

cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)

cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)

cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)

cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpuacct,cpu)

cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)

cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)

cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)

cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)

cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)

cgroup 文件系统多挂载到 /sys/fs/cgroup 下，通过上面的命令行，我们可以看到我们可以用 cgroup 控制哪些资源。

对于 CPU 的控制，我在这一章的第一节讲过，Docker 可以控制 cpu-shares、cpus 和 cpuset。

我们在 /sys/fs/cgroup/ 下面能看到下面的目录结构。

drwxr-xr-x 5 root root 0 May 30 

 17:00 blkio

lrwxrwxrwx 1 root root 11 May 30 

 17:00 cpu -> cpu,cpuacct

lrwxrwxrwx 1 root root 11 May 30 

 17:00 cpuacct -> cpu,cpuacct

drwxr-xr-x 5 root root 0 May 30 

 17:00 cpu,cpuacct

drwxr-xr-x 3 root root 0 May 30 

 17:00 cpuset

drwxr-xr-x 5 root root 0 May 30 

 17:00 devices

drwxr-xr-x 3 root root 0 May 30 

 17:00 freezer

drwxr-xr-x 3 root root 0 May 30 

 17:00 hugetlb

drwxr-xr-x 5 root root 0 May 30 

 17:00 memory

lrwxrwxrwx 1 root root 16 May 30 

 17:00 net_cls -> net\_cls,net\_prio

drwxr-xr-x 3 root root 0 May 30 

 17:00 net\_cls,net\_prio

lrwxrwxrwx 1 root root 16 May 30 

 17:00 net_prio -> net\_cls,net\_prio

drwxr-xr-x 3 root root 0 May 30 

 17:00 perf_event

drwxr-xr-x 5 root root 0 May 30 

 17:00 pids

drwxr-xr-x 5 root root 0 May 30 

 17:00 systemd

我们可以想象，CPU 的资源控制的配置文件，应该在 cpu,cpuacct 这个文件夹下面。

cgroup.clone\_children cpu.cfs\_period\_us notify\_on_release

cgroup.event\_control cpu.cfs\_quota\_us release\_agent

cgroup.procs cpu.rt\_period\_us system.slice

cgroup.sane\_behavior cpu.rt\_runtime_us tasks

cpuacct.stat cpu.shares user.slice

cpuacct.usage cpu.stat

cpuacct.usage_percpu docker

果真，这下面是对 CPU 的相关控制，里面还有一个路径叫 docker。我们进入这个路径。

\]# ls

cgroup.clone_children

cgroup.event_control

cgroup.procs

cpuacct.stat

cpuacct.usage

cpuacct.usage_percpu

cpu.cfs\_period\_us

cpu.cfs\_quota\_us

cpu.rt\_period\_us

cpu.rt\_runtime\_us

cpu.shares

cpu.stat

3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd

notify\_on\_release

tasks

这里面有个很长的 id，是我们创建的 docker 的 id。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# ls

cgroup.clone\_children cpuacct.usage\_percpu cpu.shares

cgroup.event\_control cpu.cfs\_period_us cpu.stat

cgroup.procs cpu.cfs\_quota\_us notify\_on\_release

cpuacct.stat cpu.rt\_period\_us tasks

cpuacct.usage cpu.rt\_runtime\_us

在这里，我们能看到 cpu.shares，还有一个重要的文件 tasks。这里面是这个容器里所有进程的进程号，也即所有这些进程都被这些 CPU 策略控制。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat tasks

39487

39520

39526

39527

39528

39529

如果我们查看 cpu.shares，里面就是我们设置的 513。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat cpu.shares

513

另外，我们还配置了 cpus，这个值其实是由 cpu.cfs\_period\_us 和 cpu.cfs\_quota\_us 共同决定的。cpu.cfs\_period\_us 是运行周期，cpu.cfs\_quota\_us 是在周期内这些进程占用多少时间。我们设置了 cpus 为 2，代表的意思是，在周期 100000 微秒的运行周期内，这些进程要占用 200000 微秒的时间，也即需要两个 CPU 同时运行一个整的周期。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat cpu.cfs\_period\_us

100000

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat cpu.cfs\_quota\_us

200000

对于 cpuset，也即 CPU 绑核的参数，在另外一个文件夹里面 /sys/fs/cgroup/cpuset，这里面同样有一个 docker 文件夹，下面同样有 docker id 也即 3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd 文件夹，这里面的 cpuset.cpus 就是配置的绑定到 1、3 两个核。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat cpuset.cpus

1,3

这一章的第一节我们还讲了 Docker 可以限制内存的使用量，例如 memory、memory-swap、memory-swappiness。这些在哪里控制呢？

/sys/fs/cgroup/ 下面还有一个 memory 路径，控制策略就是在这里面定义的。

\[root@deployer memory\]

cgroup.clone_children memory.memsw.failcnt

cgroup.event\_control memory.memsw.limit\_in_bytes

cgroup.procs memory.memsw.max\_usage\_in_bytes

cgroup.sane\_behavior memory.memsw.usage\_in_bytes

docker memory.move\_charge\_at_immigrate

memory.failcnt memory.numa_stat

memory.force\_empty memory.oom\_control

memory.kmem.failcnt memory.pressure_level

memory.kmem.limit\_in\_bytes memory.soft\_limit\_in_bytes

memory.kmem.max\_usage\_in_bytes memory.stat

memory.kmem.slabinfo memory.swappiness

memory.kmem.tcp.failcnt memory.usage\_in\_bytes

memory.kmem.tcp.limit\_in\_bytes memory.use_hierarchy

memory.kmem.tcp.max\_usage\_in\_bytes notify\_on_release

memory.kmem.tcp.usage\_in\_bytes release_agent

memory.kmem.usage\_in\_bytes system.slice

memory.limit\_in\_bytes tasks

memory.max\_usage\_in_bytes user.slice

这里面全是对于 memory 的控制参数，在这里面我们可看到了 docker，里面还有容器的 id 作为文件夹。

\[docker\]# ls

3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd

cgroup.clone_children

cgroup.event_control

cgroup.procs

memory.failcnt

memory.force_empty

memory.kmem.failcnt

memory.kmem.limit\_in\_bytes

memory.kmem.max\_usage\_in_bytes

memory.kmem.slabinfo

memory.kmem.tcp.failcnt

memory.kmem.tcp.limit\_in\_bytes

memory.kmem.tcp.max\_usage\_in_bytes

memory.kmem.tcp.usage\_in\_bytes

memory.kmem.usage\_in\_bytes

memory.limit\_in\_bytes

memory.max\_usage\_in_bytes

memory.memsw.failcnt

memory.memsw.limit\_in\_bytes

memory.memsw.max\_usage\_in_bytes

memory.memsw.usage\_in\_bytes

memory.move\_charge\_at_immigrate

memory.numa_stat

memory.oom_control

memory.pressure_level

memory.soft\_limit\_in_bytes

memory.stat

memory.swappiness

memory.usage\_in\_bytes

memory.use_hierarchy

notify\_on\_release

tasks

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# ls

cgroup.clone_children memory.memsw.failcnt

cgroup.event\_control memory.memsw.limit\_in_bytes

cgroup.procs memory.memsw.max\_usage\_in_bytes

memory.failcnt memory.memsw.usage\_in\_bytes

memory.force\_empty memory.move\_charge\_at\_immigrate

memory.kmem.failcnt memory.numa_stat

memory.kmem.limit\_in\_bytes memory.oom_control

memory.kmem.max\_usage\_in\_bytes memory.pressure\_level

memory.kmem.slabinfo memory.soft\_limit\_in_bytes

memory.kmem.tcp.failcnt memory.stat

memory.kmem.tcp.limit\_in\_bytes memory.swappiness

memory.kmem.tcp.max\_usage\_in\_bytes memory.usage\_in_bytes

memory.kmem.tcp.usage\_in\_bytes memory.use_hierarchy

memory.kmem.usage\_in\_bytes notify\_on\_release

memory.limit\_in\_bytes tasks

memory.max\_usage\_in_bytes

在 docker id 的文件夹下面，有一个 memory.limit\_in\_bytes，里面配置的就是 memory。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat memory.limit\_in\_bytes

1073741824

还有 memory.swappiness，里面配置的就是 memory-swappiness。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat memory.swappiness

7

还有就是 memory.memsw.limit\_in\_bytes，里面配置的是 memory-swap。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat memory.memsw.limit\_in\_bytes

1293942784

我们还可以看一下 tasks 文件的内容，tasks 里面是容器里面所有进程的进程号。

\[3dc0601189dd218898f31f9526a6cfae83913763a4da59f95ec789c6e030ecfd\]# cat tasks

39487

39520

39526

39527

39528

39529

至此，我们看到了 cgroup 对于 Docker 资源的控制，在用户态是如何表现的。我画了一张图总结一下。

![[1c762a6283429ff3587a7fc370fc090f_807de3e033964abdb.png]]

在内核中，cgroup 是如何实现的呢？

首先，在系统初始化的时候，cgroup 也会进行初始化，在 start\_kernel 中，cgroup\_init\_early 和 cgroup\_init 都会进行初始化。

asmlinkage __visible void __init start_kernel(void)

{

......

cgroup\_init\_early();

......

cgroup_init();

......

}

在 cgroup\_init\_early 和 cgroup_init 中，会有下面的循环。

for\_each\_subsys(ss, i) {

ss->id = i;

ss->name = cgroup\_subsys\_name\[i\];

......

cgroup\_init\_subsys(ss, true);

}

#define for\_each\_subsys(ss, ssid) \

for ((ssid) = 0; (ssid) < CGROUP\_SUBSYS\_COUNT && \

(((ss) = cgroup_subsys\[ssid\]) || true); (ssid)++)

for\_each\_subsys 会在 cgroup\_subsys 数组中进行循环。这个 cgroup\_subsys 数组是如何形成的呢？

#define SUBSYS(\_x) \[\_x ## \_cgrp\_id\] = &\_x ## \_cgrp_subsys,

struct 

 cgroup_subsys *cgroup_subsys\[\] = {

#include 

 &lt;linux/cgroup_subsys.h&gt;

};

#undef SUBSYS

SUBSYS 这个宏定义了这个 cgroup\_subsys 数组，数组中的项定义在 cgroup\_subsys.h 头文件中。例如，对于 CPU 和内存有下面的定义。

#if IS\_ENABLED(CONFIG\_CPUSETS)

SUBSYS(cpuset)

#endif

#if IS\_ENABLED(CONFIG\_CGROUP_SCHED)

SUBSYS(cpu)

#endif

#if IS\_ENABLED(CONFIG\_CGROUP_CPUACCT)

SUBSYS(cpuacct)

#endif

#if IS\_ENABLED(CONFIG\_MEMCG)

SUBSYS(memory)

#endif

根据 SUBSYS 的定义，SUBSYS(cpu) 其实是\[cpu\_cgrp\_id\] = &cpu\_cgrp\_subsys，而 SUBSYS(memory) 其实是\[memory\_cgrp\_id\] = &memory\_cgrp\_subsys。

我们能够找到 cpu\_cgrp\_subsys 和 memory\_cgrp\_subsys 的定义。

cpuset\_cgrp\_subsys

struct cgroup_subsys 

 cpuset\_cgrp\_subsys 

 = {

.css\_alloc = cpuset\_css_alloc,

.css\_online = cpuset\_css_online,

.css\_offline = cpuset\_css_offline,

.css\_free = cpuset\_css_free,

.can\_attach = cpuset\_can_attach,

.cancel\_attach = cpuset\_cancel_attach,

.attach = cpuset_attach,

.post\_attach = cpuset\_post_attach,

.bind = cpuset_bind,

.fork = cpuset_fork,

.legacy_cftypes = files,

.early_init = true,

};

cpu\_cgrp\_subsys

struct cgroup_subsys 

 cpu\_cgrp\_subsys 

 = {

.css\_alloc = cpu\_cgroup\_css\_alloc,

.css\_online = cpu\_cgroup\_css\_online,

.css\_released = cpu\_cgroup\_css\_released,

.css\_free = cpu\_cgroup\_css\_free,

.fork = cpu\_cgroup\_fork,

.can\_attach = cpu\_cgroup\_can\_attach,

.attach = cpu\_cgroup\_attach,

.legacy\_cftypes = cpu\_files,

.early_init = true,

};

memory\_cgrp\_subsys

struct cgroup_subsys 

 memory\_cgrp\_subsys 

 = {

.css\_alloc = mem\_cgroup\_css\_alloc,

.css\_online = mem\_cgroup\_css\_online,

.css\_offline = mem\_cgroup\_css\_offline,

.css\_released = mem\_cgroup\_css\_released,

.css\_free = mem\_cgroup\_css\_free,

.css\_reset = mem\_cgroup\_css\_reset,

.can\_attach = mem\_cgroup\_can\_attach,

.cancel\_attach = mem\_cgroup\_cancel\_attach,

.post\_attach = mem\_cgroup\_move\_task,

.bind = mem\_cgroup\_bind,

.dfl\_cftypes = memory\_files,

.legacy\_cftypes = mem\_cgroup\_legacy\_files,

.early_init = 0,

};

在 for\_each\_subsys 的循环里面，cgroup\_subsys\[\]数组中的每一个 cgroup\_subsys，都会调用 cgroup\_init\_subsys，对于 cgroup_subsys 对于初始化。

static void __init cgroup\_init\_subsys(struct 

 cgroup_subsys *ss, bool early)

{

struct 

 cgroup\_subsys\_state *css;

......

idr_init(&ss->css_idr);

INIT\_LIST\_HEAD(&ss->cfts);

ss->root = &cgrp\_dfl\_root;

css = ss->css_alloc(cgroup_css(&cgrp\_dfl\_root.cgrp, ss));

......

init\_and\_link_css(css, ss, &cgrp\_dfl\_root.cgrp);

......

css->id = cgroup\_idr\_alloc(&ss->css_idr, css, 1, 2, GFP_KERNEL);

init\_css\_set.subsys\[ss->id\] = css;

......

BUG_ON(online_css(css));

......

}

cgroup\_init\_subsys 里面会做两件事情，一个是调用 cgroup\_subsys 的 css\_alloc 函数创建一个 cgroup\_subsys\_state；另外就是调用 online\_css，也即调用 cgroup\_subsys 的 css_online 函数，激活这个 cgroup。

对于 CPU 来讲，css\_alloc 函数就是 cpu\_cgroup\_css\_alloc。这里面会调用 sched\_create\_group 创建一个 struct task\_group。在这个结构中，第一项就是 cgroup\_subsys\_state，也就是说，task\_group 是 cgroup\_subsys\_state 的一个扩展，最终返回的是指向 cgroup\_subsys\_state 结构的指针，可以通过强制类型转换变为 task_group。

struct 

 task_group {

struct 

 cgroup\_subsys\_state css;

#ifdef CONFIG\_FAIR\_GROUP_SCHED

struct 

 sched_entity **se;

struct 

 cfs_rq **cfs_rq;

unsigned 

 long shares;

#ifdef CONFIG_SMP

atomic\_long\_t load\_avg \_\_\_\_cacheline_aligned;

#endif

#endif

struct 

 rcu_head rcu;

struct 

 list_head list;

struct 

 task_group *parent;

struct 

 list_head siblings;

struct 

 list_head children;

struct 

 cfs_bandwidth cfs_bandwidth;

};

在 task\_group 结构中，有一个成员是 sched\_entity，前面我们讲进程调度的时候，遇到过它。它是调度的实体，也即这一个 task_group 也是一个调度实体。

接下来，online\_css 会被调用。对于 CPU 来讲，online\_css 调用的是 cpu\_cgroup\_css\_online。它会调用 sched\_online\_group->online\_fair\_sched\_group。

void 

 online\_fair\_sched_group(struct task_group *tg)

{

struct 

 sched_entity *se;

struct 

 rq *rq;

int i;

for\_each\_possible_cpu(i) {

rq = cpu_rq(i);

se = tg->se\[i\];

update\_rq\_clock(rq);

attach\_entity\_cfs_rq(se);

sync_throttle(tg, i);

}

}

在这里面，对于每一个 CPU，取出每个 CPU 的运行队列 rq，也取出 task\_group 的 sched\_entity，然后通过 attach\_entity\_cfs\_rq 将 sched\_entity 添加到运行队列中。

对于内存来讲，css\_alloc 函数就是 mem\_cgroup\_css\_alloc。这里面会调用 mem\_cgroup\_alloc，创建一个 struct mem\_cgroup。在这个结构中，第一项就是 cgroup\_subsys\_state，也就是说，mem\_cgroup 是 cgroup\_subsys\_state 的一个扩展，最终返回的是指向 cgroup\_subsys\_state 结构的指针，我们可以通过强制类型转换变为 mem_cgroup。

struct 

 mem_cgroup {

struct 

 cgroup\_subsys\_state css;

struct 

 mem\_cgroup\_id id;

struct 

 page_counter memory;

struct 

 page_counter swap;

struct 

 page_counter memsw;

struct 

 page_counter kmem;

struct 

 page_counter tcpmem;

unsigned 

 long low;

unsigned 

 long high;

struct 

 work_struct high_work;

unsigned 

 long soft_limit;

......

int swappiness;

......

\* percpu counter.

*/

struct 

 mem\_cgroup\_stat_cpu __percpu *stat;

int last\_scanned\_node;

struct 

 list_head event_list;

spinlock_t event\_list\_lock;

struct 

 mem\_cgroup\_per_node *nodeinfo\[0\];

};

在 cgroup\_init 函数中，cgroup 的初始化还做了一件很重要的事情，它会调用 cgroup\_init\_cftypes(NULL, cgroup1\_base\_files)，来初始化对于 cgroup 文件类型 cftype 的操作函数，也就是将 struct kernfs\_ops *kf\_ops 设置为 cgroup\_kf_ops。

struct 

 cftype cgroup1\_base\_files\[\] = {

......

{

.name = "tasks",

.seq\_start = cgroup\_pidlist_start,

.seq\_next = cgroup\_pidlist_next,

.seq\_stop = cgroup\_pidlist_stop,

.seq\_show = cgroup\_pidlist_show,

.private = CGROUP\_FILE\_TASKS,

.write = cgroup\_tasks\_write,

},

}

static 

 struct kernfs\_ops cgroup\_kf_ops = {

.atomic\_write\_len = PAGE_SIZE,

.open = cgroup\_file\_open,

.release = cgroup\_file\_release,

.write = cgroup\_file\_write,

.seq\_start = cgroup\_seqfile_start,

.seq\_next = cgroup\_seqfile_next,

.seq\_stop = cgroup\_seqfile_stop,

.seq\_show = cgroup\_seqfile_show,

};

在 cgroup 初始化完毕之后，接下来就是创建一个 cgroup 的文件系统，用于配置和操作 cgroup。

cgroup 是一种特殊的文件系统。它的定义如下：

struct file\_system\_type 

 cgroup\_fs\_type 

 = {

.name = "cgroup",

.mount = cgroup_mount,

.kill\_sb = cgroup\_kill_sb,

.fs\_flags = FS\_USERNS_MOUNT,

};

当我们 mount 这个 cgroup 文件系统的时候，会调用 cgroup\_mount->cgroup1\_mount。

struct dentry *cgroup1_mount(struct file\_system\_type *fs_type, int flags,

void *data, unsigned 

 long magic,

struct cgroup_namespace *ns)

{

struct super\_block *pinned\_sb = NULL;

struct cgroup\_sb\_opts opts;

struct cgroup_root *root;

struct cgroup_subsys *ss;

struct dentry *dentry;

int i, ret;

bool new_root = false;

......

root = kzalloc(sizeof(*root), GFP_KERNEL);

new_root = true;

init\_cgroup\_root(root, &opts);

ret = cgroup\_setup\_root(root, opts.subsys\_mask, PERCPU\_REF\_INIT\_DEAD);

......

dentry = cgroup\_do\_mount(&cgroup\_fs\_type, flags, root,

CGROUP\_SUPER\_MAGIC, ns);

......

return dentry;

}

cgroup 被组织成为树形结构，因而有 cgroup\_root。init\_cgroup\_root 会初始化这个 cgroup\_root。cgroup\_root 是 cgroup 的根，它有一个成员 kf\_root，是 cgroup 文件系统的根 struct kernfs\_root。kernfs\_create\_root 就是用来创建这个 kernfs\_root 结构的。

int cgroup\_setup\_root(struct 

 cgroup_root *root, u16 ss\_mask, int ref\_flags)

{

LIST_HEAD(tmp_links);

struct 

 cgroup *root_cgrp = &root->cgrp;

struct 

 kernfs\_syscall\_ops *kf_sops;

struct 

 css_set *cset;

int i, ret;

root->kf_root = kernfs\_create\_root(kf_sops,

KERNFS\_ROOT\_CREATE_DEACTIVATED,

root_cgrp);

root_cgrp->kn = root->kf_root->kn;

ret = css\_populate\_dir(&root_cgrp->self);

ret = rebind_subsystems(root, ss_mask);

......

list_add(&root->root\_list, &cgroup\_roots);

cgroup\_root\_count++;

......

kernfs_activate(root_cgrp->kn);

......

}

就像在普通文件系统上，每一个文件都对应一个 inode，在 cgroup 文件系统上，每个文件都对应一个 struct kernfs\_node 结构，当然 kernfs\_root 作为文件系的根也对应一个 kernfs_node 结构。

接下来，css\_populate\_dir 会调用 cgroup\_addrm\_files->cgroup\_add\_file->cgroup\_add\_file，来创建整棵文件树，并且为树中的每个文件创建对应的 kernfs\_node 结构，并将这个文件的操作函数设置为 kf\_ops，也即指向 cgroup\_kf\_ops 。

static 

 int 

 cgroup\_add\_file(struct cgroup\_subsys\_state *css, struct cgroup *cgrp,

struct cftype *cft)

{

char name\[CGROUP\_FILE\_NAME_MAX\];

struct 

 kernfs_node *kn;

......

kn = \_\_kernfs\_create_file(cgrp->kn, cgroup\_file\_name(cgrp, cft, name),

cgroup\_file\_mode(cft), 0, cft->kf_ops, cft,

NULL, key);

......

}

struct 

 kernfs_node *\_\_kernfs\_create_file(struct kernfs_node *parent,

const 

 char *name,

umode_t mode, loff_t size,

const 

 struct kernfs_ops *ops,

void *priv, const 

 void *ns,

struct lock\_class\_key *key)

{

struct 

 kernfs_node *kn;

unsigned flags;

int rc;

flags = KERNFS_FILE;

kn = kernfs\_new\_node(parent, name, (mode & S\_IALLUGO) | S\_IFREG, flags);

kn->attr.ops = ops;

kn->attr.size = size;

kn->ns = ns;

kn->priv = priv;

......

rc = kernfs\_add\_one(kn);

......

return kn;

}

从 cgroup\_setup\_root 返回后，接下来，在 cgroup1\_mount 中，要做的一件事情是 cgroup\_do\_mount，调用 kernfs\_mount 真的去 mount 这个文件系统，返回一个普通的文件系统都认识的 dentry。这种特殊的文件系统对应的文件操作函数为 kernfs\_file\_fops。

const 

 struct 

 file_operations kernfs\_file\_fops = {

.read = kernfs\_fop\_read,

.write = kernfs\_fop\_write,

.llseek = generic\_file\_llseek,

.mmap = kernfs\_fop\_mmap,

.open = kernfs\_fop\_open,

.release = kernfs\_fop\_release,

.poll = kernfs\_fop\_poll,

.fsync = noop_fsync,

};

当我们要写入一个 CGroup 文件来设置参数的时候，根据文件系统的操作，kernfs\_fop\_write 会被调用，在这里面会调用 kernfs\_ops 的 write 函数，根据上面的定义为 cgroup\_file_write，在这里会调用 cftype 的 write 函数。对于 CPU 和内存的 write 函数，有以下不同的定义。

static 

 struct 

 cftype cpu_files\[\] = {

#ifdef CONFIG\_FAIR\_GROUP_SCHED

{

.name = "shares",

.read\_u64 = cpu\_shares\_read\_u64,

.write\_u64 = cpu\_shares\_write\_u64,

},

#endif

#ifdef CONFIG\_CFS\_BANDWIDTH

{

.name = "cfs\_quota\_us",

.read\_s64 = cpu\_cfs\_quota\_read_s64,

.write\_s64 = cpu\_cfs\_quota\_write_s64,

},

{

.name = "cfs\_period\_us",

.read\_u64 = cpu\_cfs\_period\_read_u64,

.write\_u64 = cpu\_cfs\_period\_write_u64,

},

}

static 

 struct cftype mem\_cgroup\_legacy_files\[\] = {

{

.name = "usage\_in\_bytes",

.private = MEMFILE_PRIVATE(\_MEM, RES\_USAGE),

.read\_u64 = mem\_cgroup\_read\_u64,

},

{

.name = "max\_usage\_in_bytes",

.private = MEMFILE_PRIVATE(\_MEM, RES\_MAX_USAGE),

.write = mem\_cgroup\_reset,

.read\_u64 = mem\_cgroup\_read\_u64,

},

{

.name = "limit\_in\_bytes",

.private = MEMFILE_PRIVATE(\_MEM, RES\_LIMIT),

.write = mem\_cgroup\_write,

.read\_u64 = mem\_cgroup\_read\_u64,

},

{

.name = "soft\_limit\_in_bytes",

.private = MEMFILE_PRIVATE(\_MEM, RES\_SOFT_LIMIT),

.write = mem\_cgroup\_write,

.read\_u64 = mem\_cgroup\_read\_u64,

},

}

如果设置的是 cpu.shares，则调用 cpu\_shares\_write\_u64。在这里面，task\_group 的 shares 变量更新了，并且更新了 CPU 队列上的调度实体。

int 

 sched\_group\_set_shares(struct task_group *tg, unsigned 

 long shares)

{

int i;

shares = clamp(shares, scale_load(MIN_SHARES), scale_load(MAX_SHARES));

tg->shares = shares;

for\_each\_possible_cpu(i) {

struct 

 rq *rq = cpu_rq(i);

struct 

 sched_entity *se = tg->se\[i\];

struct 

 rq_flags rf;

update\_rq\_clock(rq);

for\_each\_sched_entity(se) {

update\_load\_avg(se, UPDATE_TG);

update\_cfs\_shares(se);

}

}

......

}

但是这个时候别忘了，我们还没有将 CPU 的文件夹下面的 tasks 文件写入进程号呢。写入一个进程号到 tasks 文件里面，按照 cgroup1\_base\_files 里面的定义，我们应该调用 cgroup\_tasks\_write。

接下来的调用链为：cgroup\_tasks\_write->\_\_cgroup\_procs\_write->cgroup\_attach\_task-> cgroup\_migrate->cgroup\_migrate\_execute。将这个进程和一个 cgroup 关联起来，也即将这个进程迁移到这个 cgroup 下面。

static int cgroup\_migrate\_execute(struct 

 cgroup_mgctx *mgctx)

{

struct 

 cgroup_taskset *tset = &mgctx->tset;

struct 

 cgroup_subsys *ss;

struct 

 task_struct \*task, \*tmp_task;

struct 

 css_set \*cset, \*tmp_cset;

......

if (tset->nr_tasks) {

do\_each\_subsys_mask(ss, ssid, mgctx->ss_mask) {

if (ss->attach) {

tset->ssid = ssid;

ss->attach(tset);

}

} while\_each\_subsys_mask();

}

......

}

每一个 cgroup 子系统会调用相应的 attach 函数。而 CPU 调用的是 cpu\_cgroup\_attach-> sched\_move\_task-> sched\_change\_group。

static 

 void 

 sched\_change\_group(struct task_struct *tsk, int type)

{

struct 

 task_group *tg;

tg = container_of(task\_css\_check(tsk, cpu\_cgrp\_id, true),

struct task_group, css);

tg = autogroup\_task\_group(tsk, tg);

tsk->sched\_task\_group = tg;

#ifdef CONFIG\_FAIR\_GROUP_SCHED

if (tsk->sched\_class->task\_change_group)

tsk->sched_class->task\_change\_group(tsk, type);

else

#endif

set\_task\_rq(tsk, task_cpu(tsk));

}

在 sched\_change\_group 中设置这个进程以这个 task_group 的方式参与调度，从而使得上面的 cpu.shares 起作用。

对于内存来讲，写入内存的限制使用函数 mem\_cgroup\_write->mem\_cgroup\_resize\_limit 来设置 struct mem\_cgroup 的 memory.limit 成员。

在进程执行过程中，申请内存的时候，我们会调用 handle\_pte\_fault->do\_anonymous\_page()->mem\_cgroup\_try_charge()。

int 

 mem\_cgroup\_try_charge(struct page *page, struct mm_struct *mm,

gfp_t gfp_mask, struct mem_cgroup **memcgp,

bool compound)

{

struct 

 mem_cgroup *memcg = NULL;

......

if (!memcg)

memcg = get\_mem\_cgroup\_from\_mm(mm);

ret = try_charge(memcg, gfp\_mask, nr\_pages);

......

}

在 mem\_cgroup\_try\_charge 中，先是调用 get\_mem\_cgroup\_from\_mm 获得这个进程对应的 mem\_cgroup 结构，然后在 try\_charge 中，根据 mem\_cgroup 的限制，看是否可以申请分配内存。

至此，cgroup 对于内存的限制才真正起作用。

## 总结时刻

内核中 cgroup 的工作机制，我们在这里总结一下。

![[c9cc56d20e6a4bac0f9657e6380a96c4_e742a7aa165c4a12b.png]]

第一步，系统初始化的时候，初始化 cgroup 的各个子系统的操作函数，分配各个子系统的数据结构。

第二步，mount cgroup 文件系统，创建文件系统的树形结构，以及操作函数。

第三步，写入 cgroup 文件，设置 cpu 或者 memory 的相关参数，这个时候文件系统的操作函数会调用到 cgroup 子系统的操作函数，从而将参数设置到 cgroup 子系统的数据结构中。

第四步，写入 tasks 文件，将进程交给某个 cgroup 进行管理，因为 tasks 文件也是一个 cgroup 文件，统一会调用文件系统的操作函数进而调用 cgroup 子系统的操作函数，将 cgroup 子系统的数据结构和进程关联起来。

第五步，对于 CPU 来讲，会修改 scheduled entity，放入相应的队列里面去，从而下次调度的时候就起作用了。对于内存的 cgroup 设定，只有在申请内存的时候才起作用。

## 课堂练习

这里我们用 cgroup 限制了 CPU 和内存，如何限制网络呢？给你一个提示 tc，请你研究一下。

欢迎留言和我分享你的疑惑和见解，也欢迎收藏本节内容，反复研读。你也可以把今天的内容分享给你的朋友，和他一起学习和进步。