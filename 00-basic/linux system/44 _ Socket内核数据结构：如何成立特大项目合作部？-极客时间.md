上一节我们讲了 Socket 在 TCP 和 UDP 场景下的调用流程。这一节，我们就沿着这个流程到内核里面一探究竟，看看在内核里面，都创建了哪些数据结构，做了哪些事情。

## 解析 socket 函数

我们从 Socket 系统调用开始。

SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)

{

int retval;

struct socket *sock;

int flags;

......

if (SOCK\_NONBLOCK != O\_NONBLOCK && (flags & SOCK_NONBLOCK))

flags = (flags & ~SOCK\_NONBLOCK) | O\_NONBLOCK;

retval = sock_create(family, type, protocol, &sock);

......

retval = sock\_map\_fd(sock, flags & (O\_CLOEXEC | O\_NONBLOCK));

......

return retval;

}

这里面的代码比较容易看懂，Socket 系统调用会调用 sock\_create 创建一个 struct socket 结构，然后通过 sock\_map_fd 和文件描述符对应起来。

在创建 Socket 的时候，有三个参数。

一个是 family，表示地址族。不是所有的 Socket 都要通过 IP 进行通信，还有其他的通信方式。例如，下面的定义中，domain sockets 就是通过本地文件进行通信的，不需要 IP 地址。只不过，通过 IP 地址只是最常用的模式，所以我们这里着重分析这种模式。

#define AF_UNIX 1

#define AF_INET 2

第二个参数是 type，也即 Socket 的类型。类型是比较少的。

第三个参数是 protocol，是协议。协议数目是比较多的，也就是说，多个协议会属于同一种类型。

常用的 Socket 类型有三种，分别是 SOCK\_STREAM、SOCK\_DGRAM 和 SOCK_RAW。

enum 

 sock_type {

SOCK_STREAM = 1,

SOCK_DGRAM = 2,

SOCK_RAW = 3,

......

}

SOCK\_STREAM 是面向数据流的，协议 IPPROTO\_TCP 属于这种类型。SOCK\_DGRAM 是面向数据报的，协议 IPPROTO\_UDP 属于这种类型。如果在内核里面看的话，IPPROTO\_ICMP 也属于这种类型。SOCK\_RAW 是原始的 IP 包，IPPROTO_IP 属于这种类型。

这一节，我们重点看 SOCK\_STREAM 类型和 IPPROTO\_TCP 协议。

为了管理 family、type、protocol 这三个分类层次，内核会创建对应的数据结构。

接下来，我们打开 sock\_create 函数看一下。它会调用 \_\_sock_create。

int \_\_sock\_create(struct net *net, int family, int 

 type, int protocol,

struct socket **res, int kern)

{

int err;

struct socket *sock;

const 

 struct net\_proto\_family *pf;

......

sock = sock_alloc();

......

sock->type = type;

......

pf = rcu\_dereference(net\_families\[family\]);

......

err = pf->create(net, sock, protocol, kern);

......

*res = sock;

return 

 0;

}

这里先是分配了一个 struct socket 结构。接下来我们要用到 family 参数。这里有一个 net\_families 数组，我们可以以 family 参数为下标，找到对应的 struct net\_proto_family。

#define AF_UNSPEC 0

#define AF_UNIX 1

#define AF_LOCAL 1

#define AF_INET 2

......

#define AF_INET6 10

......

#define AF_MPLS 28

......

#define AF_MAX 44

#define NPROTO AF_MAX

struct 

 net\_proto\_family \_\_rcu *net\_families\[NPROTO\] \_\_read\_mostly;

我们可以找到 net\_families 的定义。每一个地址族在这个数组里面都有一项，里面的内容是 net\_proto\_family。每一种地址族都有自己的 net\_proto\_family，IP 地址族的 net\_proto\_family 定义如下，里面最重要的就是，create 函数指向 inet\_create。

static 

 const 

 struct 

 net\_proto\_family inet\_family\_ops = {

.family = PF_INET,

.create = inet_create,

......

}

我们回到函数 \_\_sock\_create。接下来，在这里面，这个 inet_create 会被调用。

static int inet_create(struct 

 net *net, struct 

 socket *sock, int protocol, int kern)

{

struct 

 sock *sk;

struct 

 inet_protosw *answer;

struct 

 inet_sock *inet;

struct 

 proto *answer_prot;

unsigned char answer_flags;

int try\_loading\_module = 0;

int err;

lookup_protocol:

list\_for\_each\_entry\_rcu(answer, &inetsw\[sock->type\], list) {

err = 0;

if (protocol == answer->protocol) {

if (protocol != IPPROTO_IP)

break;

} else {

if (IPPROTO_IP == protocol) {

protocol = answer->protocol;

break;

}

if (IPPROTO_IP == answer->protocol)

break;

}

err = -EPROTONOSUPPORT;

}

......

sock->ops = answer->ops;

answer_prot = answer->prot;

answer_flags = answer->flags;

......

sk = sk_alloc(net, PF\_INET, GFP\_KERNEL, answer_prot, kern);

......

inet = inet_sk(sk);

inet->nodefrag = 0;

if (SOCK_RAW == sock->type) {

inet->inet_num = protocol;

if (IPPROTO_RAW == protocol)

inet->hdrincl = 1;

}

inet->inet_id = 0;

sock\_init\_data(sock, sk);

sk->sk\_destruct = inet\_sock_destruct;

sk->sk_protocol = protocol;

sk->sk\_backlog\_rcv = sk->sk_prot->backlog_rcv;

inet->uc_ttl = -1;

inet->mc_loop = 1;

inet->mc_ttl = 1;

inet->mc_all = 1;

inet->mc_index = 0;

inet->mc_list = NULL;

inet->rcv_tos = 0;

if (inet->inet_num) {

inet->inet_sport = htons(inet->inet_num);

err = sk->sk_prot->hash(sk);

}

if (sk->sk_prot->init) {

err = sk->sk_prot->init(sk);

}

......

}

在 inet\_create 中，我们先会看到一个循环 list\_for\_each\_entry_rcu。在这里，第二个参数 type 开始起作用。因为循环查看的是 inetsw\[sock->type\]。

这里的 inetsw 也是一个数组，type 作为下标，里面的内容是 struct inet_protosw，是协议，也即 inetsw 数组对于每个类型有一项，这一项里面是属于这个类型的协议。

static 

 struct 

 list_head inetsw\[SOCK_MAX\];

static 

 int __init inet_init(void)

{

......

for (r = &inetsw\[0\]; r < &inetsw\[SOCK_MAX\]; ++r)

INIT\_LIST\_HEAD(r);

for (q = inetsw\_array; q < &inetsw\_array\[INETSW\_ARRAY\_LEN\]; ++q)

inet\_register\_protosw(q);

......

}

inetsw 数组是在系统初始化的时候初始化的，就像下面代码里面实现的一样。

首先，一个循环会将 inetsw 数组的每一项，都初始化为一个链表。咱们前面说了，一个 type 类型会包含多个 protocol，因而我们需要一个链表。接下来一个循环，是将 inetsw_array 注册到 inetsw 数组里面去。inetsw_array 的定义如下，这个数组里面的内容很重要，后面会用到它们。

static 

 struct 

 inet_protosw inetsw_array\[\] =

{

{

.type = SOCK_STREAM,

.protocol = IPPROTO_TCP,

.prot = &tcp_prot,

.ops = &inet\_stream\_ops,

.flags = INET\_PROTOSW\_PERMANENT |

INET\_PROTOSW\_ICSK,

},

{

.type = SOCK_DGRAM,

.protocol = IPPROTO_UDP,

.prot = &udp_prot,

.ops = &inet\_dgram\_ops,

.flags = INET\_PROTOSW\_PERMANENT,

},

{

.type = SOCK_DGRAM,

.protocol = IPPROTO_ICMP,

.prot = &ping_prot,

.ops = &inet\_sockraw\_ops,

.flags = INET\_PROTOSW\_REUSE,

},

{

.type = SOCK_RAW,

.protocol = IPPROTO_IP,

.prot = &raw_prot,

.ops = &inet\_sockraw\_ops,

.flags = INET\_PROTOSW\_REUSE,

}

}

我们回到 inet\_create 的 list\_for\_each\_entry\_rcu 循环中。到这里就好理解了，这是在 inetsw 数组中，根据 type 找到属于这个类型的列表，然后依次比较列表中的 struct inet\_protosw 的 protocol 是不是用户指定的 protocol；如果是，就得到了符合用户指定的 family->type->protocol 的 struct inet_protosw *answer 对象。

接下来，struct socket *sock 的 ops 成员变量，被赋值为 answer 的 ops。对于 TCP 来讲，就是 inet\_stream\_ops。后面任何用户对于这个 socket 的操作，都是通过 inet\_stream\_ops 进行的。

接下来，我们创建一个 struct sock *sk 对象。这里比较让人困惑。socket 和 sock 看起来几乎一样，容易让人混淆，这里需要说明一下，socket 是用于负责对上给用户提供接口，并且和文件系统关联。而 sock，负责向下对接内核网络协议栈。

在 sk\_alloc 函数中，struct inet\_protosw \*answer 结构的 tcp\_prot 赋值给了 struct sock \*sk 的 sk\_prot 成员。tcp_prot 的定义如下，里面定义了很多的函数，都是 sock 之下内核协议栈的动作。

struct proto tcp_prot = {

.name = "TCP",

.owner = THIS_MODULE,

.close = tcp_close,

.connect = tcp\_v4\_connect,

.disconnect = tcp_disconnect,

.accept = inet\_csk\_accept,

.ioctl = tcp_ioctl,

.init = tcp\_v4\_init_sock,

.destroy = tcp\_v4\_destroy_sock,

.shutdown = tcp_shutdown,

.setsockopt = tcp_setsockopt,

.getsockopt = tcp_getsockopt,

.keepalive = tcp\_set\_keepalive,

.recvmsg = tcp_recvmsg,

.sendmsg = tcp_sendmsg,

.sendpage = tcp_sendpage,

.backlog\_rcv = tcp\_v4\_do\_rcv,

.release\_cb = tcp\_release_cb,

.hash = inet_hash,

.get\_port = inet\_csk\_get\_port,

......

}

在 inet\_create 函数中，接下来创建一个 struct inet\_sock 结构，这个结构一开始就是 struct sock，然后扩展了一些其他的信息，剩下的代码就填充这些信息。这一幕我们会经常看到，将一个结构放在另一个结构的开始位置，然后扩展一些成员，通过对于指针的强制类型转换，来访问这些成员。

socket 的创建至此结束。

## 解析 bind 函数

接下来，我们来看 bind。

SYSCALL_DEFINE3(bind, int, fd, struct sockaddr __user *, umyaddr, int, addrlen)

{

struct 

 socket *sock;

struct 

 sockaddr_storage address;

int err, fput_needed;

sock = sockfd\_lookup\_light(fd, &err, &fput_needed);

if (sock) {

err = move\_addr\_to_kernel(umyaddr, addrlen, &address);

if (err >= 0) {

err = sock->ops->bind(sock,

(struct sockaddr *)

&address, addrlen);

}

fput_light(sock->file, fput_needed);

}

return err;

}

在 bind 中，sockfd\_lookup\_light 会根据 fd 文件描述符，找到 struct socket 结构。然后将 sockaddr 从用户态拷贝到内核态，然后调用 struct socket 结构里面 ops 的 bind 函数。根据前面创建 socket 的时候的设定，调用的是 inet\_stream\_ops 的 bind 函数，也即调用 inet_bind。

int inet_bind(struct 

 socket *sock, struct 

 sockaddr *uaddr, int addr_len)

{

struct 

 sockaddr_in *addr = (struct 

 sockaddr_in *)uaddr;

struct 

 sock *sk = sock->sk;

struct 

 inet_sock *inet = inet_sk(sk);

struct 

 net *net = sock_net(sk);

unsigned short snum;

......

snum = ntohs(addr->sin_port);

......

inet->inet\_rcv\_saddr = inet->inet_saddr = addr->sin\_addr.s\_addr;

if ((snum || !inet->bind\_address\_no_port) &&

sk->sk_prot->get_port(sk, snum)) {

......

}

inet->inet_sport = htons(inet->inet_num);

inet->inet_daddr = 0;

inet->inet_dport = 0;

sk\_dst\_reset(sk);

}

bind 里面会调用 sk\_prot 的 get\_port 函数，也即 inet\_csk\_get\_port 来检查端口是否冲突，是否可以绑定。如果允许，则会设置 struct inet\_sock 的本方的地址 inet\_saddr 和本方的端口 inet\_sport，对方的地址 inet\_daddr 和对方的端口 inet\_dport 都初始化为 0。

bind 的逻辑相对比较简单，就到这里了。

## 解析 listen 函数

接下来我们来看 listen。

SYSCALL_DEFINE2(listen, int, fd, int, backlog)

{

struct 

 socket *sock;

int err, fput_needed;

int somaxconn;

sock = sockfd\_lookup\_light(fd, &err, &fput_needed);

if (sock) {

somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn;

if ((unsigned 

 int)backlog > somaxconn)

backlog = somaxconn;

err = sock->ops->listen(sock, backlog);

fput_light(sock->file, fput_needed);

}

return err;

}

在 listen 中，我们还是通过 sockfd\_lookup\_light，根据 fd 文件描述符，找到 struct socket 结构。接着，我们调用 struct socket 结构里面 ops 的 listen 函数。根据前面创建 socket 的时候的设定，调用的是 inet\_stream\_ops 的 listen 函数，也即调用 inet_listen。

int 

 inet_listen(struct socket *sock, int backlog)

{

struct 

 sock *sk = sock->sk;

unsigned 

 char old_state;

int err;

old\_state = sk->sk\_state;

\* we can only allow the backlog to be adjusted.

*/

if (old\_state != TCP\_LISTEN) {

err = inet\_csk\_listen_start(sk, backlog);

}

sk->sk\_max\_ack_backlog = backlog;

}

如果这个 socket 还不在 TCP\_LISTEN 状态，会调用 inet\_csk\_listen\_start 进入监听状态。

int inet\_csk\_listen_start(struct 

 sock *sk, int backlog)

{

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

struct 

 inet_sock *inet = inet_sk(sk);

int err = -EADDRINUSE;

reqsk\_queue\_alloc(&icsk->icsk\_accept\_queue);

sk->sk\_max\_ack_backlog = backlog;

sk->sk\_ack\_backlog = 0;

inet\_csk\_delack_init(sk);

sk\_state\_store(sk, TCP_LISTEN);

if (!sk->sk_prot->get_port(sk, inet->inet_num)) {

......

}

......

}

这里面建立了一个新的结构 inet\_connection\_sock，这个结构一开始是 struct inet\_sock，inet\_csk 其实做了一次强制类型转换，扩大了结构，看到了吧，又是这个套路。

struct inet\_connection\_sock 结构比较复杂。如果打开它，你能看到处于各种状态的队列，各种超时时间、拥塞控制等字眼。我们说 TCP 是面向连接的，就是客户端和服务端都是有一个结构维护连接的状态，就是指这个结构。我们这里先不详细分析里面的变量，因为太多了，后面我们遇到一个分析一个。

首先，我们遇到的是 icsk\_accept\_queue。它是干什么的呢？

在 TCP 的状态里面，有一个 listen 状态，当调用 listen 函数之后，就会进入这个状态，虽然我们写程序的时候，一般要等待服务端调用 accept 后，等待在哪里的时候，让客户端就发起连接。其实服务端一旦处于 listen 状态，不用 accept，客户端也能发起连接。其实 TCP 的状态中，没有一个是否被 accept 的状态，那 accept 函数的作用是什么呢？

在内核中，为每个 Socket 维护两个队列。一个是已经建立了连接的队列，这时候连接三次握手已经完毕，处于 established 状态；一个是还没有完全建立连接的队列，这个时候三次握手还没完成，处于 syn_rcvd 的状态。

服务端调用 accept 函数，其实是在第一个队列中拿出一个已经完成的连接进行处理。如果还没有完成就阻塞等待。这里的 icsk\_accept\_queue 就是第一个队列。

初始化完之后，将 TCP 的状态设置为 TCP\_LISTEN，再次调用 get\_port 判断端口是否冲突。

至此，listen 的逻辑就结束了。

## 解析 accept 函数

接下来，我们解析服务端调用 accept。

SYSCALL_DEFINE3(accept, int, fd, struct 

 sockaddr \_\_user *, upeer\_sockaddr,

int \_\_user *, upeer\_addrlen)

{

return 

 sys_accept4(fd, upeer\_sockaddr, upeer\_addrlen, 0);

}

SYSCALL_DEFINE4(accept4, int, fd, struct 

 sockaddr \_\_user *, upeer\_sockaddr,

int \_\_user *, upeer\_addrlen, int, flags)

{

struct 

 socket \*sock, \*newsock;

struct 

 file *newfile;

int err, len, newfd, fput_needed;

struct 

 sockaddr_storage address;

......

sock = sockfd\_lookup\_light(fd, &err, &fput_needed);

newsock = sock_alloc();

newsock->type = sock->type;

newsock->ops = sock->ops;

newfd = get\_unused\_fd_flags(flags);

newfile = sock\_alloc\_file(newsock, flags, sock->sk->sk\_prot\_creator->name);

err = sock->ops->accept(sock, newsock, sock->file->f_flags, false);

if (upeer_sockaddr) {

if (newsock->ops->getname(newsock, (struct 

 sockaddr *)&address, &len, 2) < 0) {

}

err = move\_addr\_to_user(&address,

len, upeer\_sockaddr, upeer\_addrlen);

}

fd_install(newfd, newfile);

......

}

accept 函数的实现，印证了 socket 的原理中说的那样，原来的 socket 是监听 socket，这里我们会找到原来的 struct socket，并基于它去创建一个新的 newsock。这才是连接 socket。除此之外，我们还会创建一个新的 struct file 和 fd，并关联到 socket。

这里面还会调用 struct socket 的 sock->ops->accept，也即会调用 inet\_stream\_ops 的 accept 函数，也即 inet_accept。

int 

 inet_accept(struct socket *sock, struct socket *newsock, int flags, bool kern)

{

struct 

 sock *sk1 = sock->sk;

int err = -EINVAL;

struct 

 sock *sk2 = sk1->sk_prot->accept(sk1, flags, &err, kern);

sock\_rps\_record_flow(sk2);

sock_graft(sk2, newsock);

newsock->state = SS_CONNECTED;

}

inet\_accept 会调用 struct sock 的 sk1->sk\_prot->accept，也即 tcp\_prot 的 accept 函数，inet\_csk_accept 函数。

\* This will accept the next outstanding connection.

*/

struct 

 sock *inet\_csk\_accept(struct sock *sk, int flags, int *err, bool kern)

{

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

struct 

 request\_sock\_queue *queue = &icsk->icsk\_accept\_queue;

struct 

 request_sock *req;

struct 

 sock *newsk;

int error;

if (sk->sk\_state != TCP\_LISTEN)

goto out_err;

if (reqsk\_queue\_empty(queue)) {

long timeo = sock_rcvtimeo(sk, flags & O_NONBLOCK);

error = inet\_csk\_wait\_for\_connect(sk, timeo);

}

req = reqsk\_queue\_remove(queue, sk);

newsk = req->sk;

......

}

\* Wait for an incoming connection, avoid race conditions. This must be called

\* with the socket locked.

*/

static 

 int 

 inet\_csk\_wait\_for\_connect(struct sock *sk, long timeo)

{

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

DEFINE_WAIT(wait);

int err;

for (;;) {

prepare\_to\_wait_exclusive(sk_sleep(sk), &wait,

TASK_INTERRUPTIBLE);

release_sock(sk);

if (reqsk\_queue\_empty(&icsk->icsk\_accept\_queue))

timeo = schedule_timeout(timeo);

sched\_annotate\_sleep();

lock_sock(sk);

err = 0;

if (!reqsk\_queue\_empty(&icsk->icsk\_accept\_queue))

break;

err = -EINVAL;

if (sk->sk\_state != TCP\_LISTEN)

break;

err = sock\_intr\_errno(timeo);

if (signal_pending(current))

break;

err = -EAGAIN;

if (!timeo)

break;

}

finish_wait(sk_sleep(sk), &wait);

return err;

}

inet\_csk\_accept 的实现，印证了上面我们讲的两个队列的逻辑。如果 icsk\_accept\_queue 为空，则调用 inet\_csk\_wait\_for\_connect 进行等待；等待的时候，调用 schedule\_timeout，让出 CPU，并且将进程状态设置为 TASK\_INTERRUPTIBLE。

如果再次 CPU 醒来，我们会接着判断 icsk\_accept\_queue 是否为空，同时也会调用 signal\_pending 看有没有信号可以处理。一旦 icsk\_accept\_queue 不为空，就从 inet\_csk\_wait\_for_connect 中返回，在队列中取出一个 struct sock 对象赋值给 newsk。

## 解析 connect 函数

什么情况下，icsk\_accept\_queue 才不为空呢？当然是三次握手结束才可以。接下来我们来分析三次握手的过程。

![[ab92c2afb4aafb53143c471293ccb2df_45aa11a9ceaf4c479.png]]

三次握手一般是由客户端调用 connect 发起。

SYSCALL_DEFINE3(connect, int, fd, struct 

 sockaddr __user *, uservaddr,

int, addrlen)

{

struct 

 socket *sock;

struct 

 sockaddr_storage address;

int err, fput_needed;

sock = sockfd\_lookup\_light(fd, &err, &fput_needed);

err = move\_addr\_to_kernel(uservaddr, addrlen, &address);

err = sock->ops->connect(sock, (struct 

 sockaddr *)&address, addrlen, sock->file->f_flags);

}

connect 函数的实现一开始你应该很眼熟，还是通过 sockfd\_lookup\_light，根据 fd 文件描述符，找到 struct socket 结构。接着，我们会调用 struct socket 结构里面 ops 的 connect 函数，根据前面创建 socket 的时候的设定，调用 inet\_stream\_ops 的 connect 函数，也即调用 inet\_stream\_connect。

\* Connect to a remote host. There is regrettably still a little

\* TCP 'magic' in here.

*/

int \_\_inet\_stream_connect(struct socket *sock, struct sockaddr *uaddr,

int addr_len, int flags, int is_sendmsg)

{

struct sock *sk = sock->sk;

int err;

long timeo;

switch (sock->state) {

......

case SS_UNCONNECTED:

err = -EISCONN;

if (sk->sk\_state != TCP\_CLOSE)

goto 

 out;

err = sk->sk\_prot->connect(sk, uaddr, addr\_len);

sock->state = SS_CONNECTING;

break;

}

timeo = sock\_sndtimeo(sk, flags & O\_NONBLOCK);

if ((1 &lt;< sk-&gt;sk\_state) & (TCPF\_SYN\_SENT | TCPF\_SYN_RECV)) {

......

if (!timeo || !inet\_wait\_for_connect(sk, timeo, writebias))

goto 

 out;

err = sock\_intr\_errno(timeo);

if (signal_pending(current))

goto 

 out;

}

sock->state = SS_CONNECTED;

}

在 \_\_inet\_stream\_connect 里面，我们发现，如果 socket 处于 SS\_UNCONNECTED 状态，那就调用 struct sock 的 sk->sk\_prot->connect，也即 tcp\_prot 的 connect 函数——tcp\_v4\_connect 函数。

int tcp\_v4\_connect(struct 

 sock *sk, struct 

 sockaddr *uaddr, int addr_len)

{

struct 

 sockaddr_in *usin = (struct 

 sockaddr_in *)uaddr;

struct 

 inet_sock *inet = inet_sk(sk);

struct 

 tcp_sock *tp = tcp_sk(sk);

\_\_be16 orig\_sport, orig_dport;

__be32 daddr, nexthop;

struct 

 flowi4 *fl4;

struct 

 rtable *rt;

......

orig_sport = inet->inet_sport;

orig_dport = usin->sin_port;

rt = ip\_route\_connect(fl4, nexthop, inet->inet_saddr,

RT\_CONN\_FLAGS(sk), sk->sk\_bound\_dev_if,

IPPROTO_TCP,

orig\_sport, orig\_dport, sk);

......

tcp\_set\_state(sk, TCP\_SYN\_SENT);

err = inet\_hash\_connect(tcp\_death\_row, sk);

sk\_set\_txhash(sk);

rt = ip\_route\_newports(fl4, rt, orig\_sport, orig\_dport,

inet->inet_sport, inet->inet_dport, sk);

sk->sk\_gso\_type = SKB\_GSO\_TCPV4;

sk\_setup\_caps(sk, &rt->dst);

if (likely(!tp->repair)) {

if (!tp->write_seq)

tp->write_seq = secure\_tcp\_seq(inet->inet_saddr,

inet->inet_daddr,

inet->inet_sport,

usin->sin_port);

tp->tsoffset = secure\_tcp\_ts_off(sock_net(sk),

inet->inet_saddr,

inet->inet_daddr);

}

rt = NULL;

......

err = tcp_connect(sk);

......

}

在 tcp\_v4\_connect 函数中，ip\_route\_connect 其实是做一个路由的选择。为什么呢？因为三次握手马上就要发送一个 SYN 包了，这就要凑齐源地址、源端口、目标地址、目标端口。目标地址和目标端口是服务端的，已经知道源端口是客户端随机分配的，源地址应该用哪一个呢？这时候要选择一条路由，看从哪个网卡出去，就应该填写哪个网卡的 IP 地址。

接下来，在发送 SYN 之前，我们先将客户端 socket 的状态设置为 TCP\_SYN\_SENT。然后初始化 TCP 的 seq num，也即 write\_seq，然后调用 tcp\_connect 进行发送。

int tcp_connect(struct 

 sock *sk)

{

struct 

 tcp_sock *tp = tcp_sk(sk);

struct 

 sk_buff *buff;

int err;

......

tcp\_connect\_init(sk);

......

buff = sk\_stream\_alloc_skb(sk, 0, sk->sk_allocation, true);

......

tcp\_init\_nondata_skb(buff, tp->write\_seq++, TCPHDR\_SYN);

tcp\_mstamp\_refresh(tp);

tp->retrans_stamp = tcp\_time\_stamp(tp);

tcp\_connect\_queue_skb(sk, buff);

tcp\_ecn\_send_syn(sk, buff);

err = tp->fastopen_req ? tcp\_send\_syn_data(sk, buff) :

tcp\_transmit\_skb(sk, buff, 1, sk->sk_allocation);

......

tp->snd_nxt = tp->write_seq;

tp->pushed_seq = tp->write_seq;

buff = tcp\_send\_head(sk);

if (unlikely(buff)) {

tp->snd_nxt = TCP\_SKB\_CB(buff)->seq;

tp->pushed_seq = TCP\_SKB\_CB(buff)->seq;

}

......

inet\_csk\_reset\_xmit\_timer(sk, ICSK\_TIME\_RETRANS,

inet_csk(sk)->icsk\_rto, TCP\_RTO_MAX);

return 

 0;

}

在 tcp\_connect 中，有一个新的结构 struct tcp\_sock，如果打开他，你会发现他是 struct inet\_connection\_sock 的一个扩展，struct inet\_connection\_sock 在 struct tcp_sock 开头的位置，通过强制类型转换访问，故伎重演又一次。

struct tcp_sock 里面维护了更多的 TCP 的状态，咱们同样是遇到了再分析。

接下来 tcp\_init\_nondata\_skb 初始化一个 SYN 包，tcp\_transmit\_skb 将 SYN 包发送出去，inet\_csk\_reset\_xmit_timer 设置了一个 timer，如果 SYN 发送不成功，则再次发送。

发送网络包的过程，我们放到下一节讲解。这里我们姑且认为 SYN 已经发送出去了。

我们回到 \_\_inet\_stream\_connect 函数，在调用 sk->sk\_prot->connect 之后，inet\_wait\_for_connect 会一直等待客户端收到服务端的 ACK。而我们知道，服务端在 accept 之后，也是在等待中。

网络包是如何接收的呢？对于解析的详细过程，我们会在下下节讲解，这里为了解析三次握手，我们简单的看网络包接收到 TCP 层做的部分事情。

static struct net_protocol 

 tcp_protocol 

 = {

.early\_demux = tcp\_v4\_early\_demux,

.early\_demux\_handler = tcp\_v4\_early_demux,

.handler = tcp\_v4\_rcv,

.err\_handler = tcp\_v4_err,

.no_policy = 1,

.netns_ok = 1,

.icmp\_strict\_tag_validation = 1,

}

我们通过 struct net\_protocol 结构中的 handler 进行接收，调用的函数是 tcp\_v4\_rcv。接下来的调用链为 tcp\_v4\_rcv->tcp\_v4\_do\_rcv->tcp\_rcv\_state\_process。tcp\_rcv\_state\_process，顾名思义，是用来处理接收一个网络包后引起状态变化的。

int 

 tcp\_rcv\_state_process(struct sock *sk, struct sk_buff *skb)

{

struct 

 tcp_sock *tp = tcp_sk(sk);

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

const 

 struct 

 tcphdr *th = tcp_hdr(skb);

struct 

 request_sock *req;

int queued = 0;

bool acceptable;

switch (sk->sk_state) {

......

case TCP_LISTEN:

......

if (th->syn) {

acceptable = icsk->icsk\_af\_ops->conn_request(sk, skb) >= 0;

if (!acceptable)

return 

 1;

consume_skb(skb);

return 

 0;

}

......

}

目前服务端是处于 TCP\_LISTEN 状态的，而且发过来的包是 SYN，因而就有了上面的代码，调用 icsk->icsk\_af\_ops->conn\_request 函数。struct inet\_connection\_sock 对应的操作是 inet\_connection\_sock\_af\_ops，按照下面的定义，其实调用的是 tcp\_v4\_conn_request。

const 

 struct inet\_connection\_sock\_af\_ops ipv4_specific = {

.queue\_xmit = ip\_queue_xmit,

.send\_check = tcp\_v4\_send\_check,

.rebuild\_header = inet\_sk\_rebuild\_header,

.sk\_rx\_dst\_set = inet\_sk\_rx\_dst_set,

.conn\_request = tcp\_v4\_conn\_request,

.syn\_recv\_sock = tcp\_v4\_syn\_recv\_sock,

.net\_header\_len = sizeof(struct iphdr),

.setsockopt = ip_setsockopt,

.getsockopt = ip_getsockopt,

.addr2sockaddr = inet\_csk\_addr2sockaddr,

.sockaddr_len = sizeof(struct sockaddr_in),

.mtu\_reduced = tcp\_v4\_mtu\_reduced,

};

tcp\_v4\_conn\_request 会调用 tcp\_conn\_request，这个函数也比较长，里面调用了 send\_synack，但实际调用的是 tcp\_v4\_send\_synack。具体发送的过程我们不去管它，看注释我们能知道，这是收到了 SYN 后，回复一个 SYN-ACK，回复完毕后，服务端处于 TCP\_SYN_RECV。

int 

 tcp\_conn\_request(struct request\_sock\_ops *rsk_ops,

const 

 struct tcp\_request\_sock\_ops *af\_ops,

struct sock *sk, struct sk_buff *skb)

{

......

af_ops->send_synack(sk, dst, &fl, req, &foc,

!want\_cookie ? TCP\_SYNACK_NORMAL :

TCP\_SYNACK\_COOKIE);

......

}

\* Send a SYN-ACK after having received a SYN.

*/

static 

 int 

 tcp\_v4\_send_synack(const 

 struct sock *sk, struct dst_entry *dst,

struct flowi *fl,

struct request_sock *req,

struct tcp\_fastopen\_cookie *foc,

enum tcp\_synack\_type synack_type)

{......}

这个时候，轮到客户端接收网络包了。都是 TCP 协议栈，所以过程和服务端没有太多区别，还是会走到 tcp\_rcv\_state\_process 函数的，只不过由于客户端目前处于 TCP\_SYN_SENT 状态，就进入了下面的代码分支。

int 

 tcp\_rcv\_state_process(struct sock *sk, struct sk_buff *skb)

{

struct 

 tcp_sock *tp = tcp_sk(sk);

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

const 

 struct 

 tcphdr *th = tcp_hdr(skb);

struct 

 request_sock *req;

int queued = 0;

bool acceptable;

switch (sk->sk_state) {

......

case TCP\_SYN\_SENT:

tp->rx\_opt.saw\_tstamp = 0;

tcp\_mstamp\_refresh(tp);

queued = tcp\_rcv\_synsent\_state\_process(sk, skb, th);

if (queued >= 0)

return queued;

tcp_urg(sk, skb, th);

\_\_kfree\_skb(skb);

tcp\_data\_snd_check(sk);

return 

 0;

}

......

}

tcp\_rcv\_synsent\_state\_process 会调用 tcp\_send\_ack，发送一个 ACK-ACK，发送后客户端处于 TCP_ESTABLISHED 状态。

又轮到服务端接收网络包了，我们还是归 tcp\_rcv\_state\_process 函数处理。由于服务端目前处于状态 TCP\_SYN\_RECV 状态，因而又走了另外的分支。当收到这个网络包的时候，服务端也处于 TCP\_ESTABLISHED 状态，三次握手结束。

int tcp\_rcv\_state_process(struct 

 sock *sk, struct 

 sk_buff *skb)

{

struct 

 tcp_sock *tp = tcp_sk(sk);

struct 

 inet\_connection\_sock *icsk = inet_csk(sk);

const 

 struct 

 tcphdr *th = tcp_hdr(skb);

struct 

 request_sock *req;

int queued = 0;

bool acceptable;

......

switch (sk->sk_state) {

case TCP\_SYN\_RECV:

if (req) {

inet_csk(sk)->icsk_retransmits = 0;

reqsk\_fastopen\_remove(sk, req, false);

} else {

icsk->icsk\_af\_ops->rebuild_header(sk);

tcp\_call\_bpf(sk, BPF\_SOCK\_OPS\_PASSIVE\_ESTABLISHED_CB);

tcp\_init\_congestion_control(sk);

tcp\_mtup\_init(sk);

tp->copied_seq = tp->rcv_nxt;

tcp\_init\_buffer_space(sk);

}

smp_mb();

tcp\_set\_state(sk, TCP_ESTABLISHED);

sk->sk\_state\_change(sk);

if (sk->sk_socket)

sk\_wake\_async(sk, SOCK\_WAKE\_IO, POLL_OUT);

tp->snd_una = TCP\_SKB\_CB(skb)->ack_seq;

tp->snd_wnd = ntohs(th->window) << tp->rx\_opt.snd\_wscale;

tcp\_init\_wl(tp, TCP\_SKB\_CB(skb)->seq);

break;

......

}

## 总结时刻

这一节除了网络包的接收和发送，其他的系统调用我们都分析到了。可以看出来，它们有一个统一的数据结构和流程。具体如下图所示：

![[c028381cf45d65d3f148e57408d26bd8_2fda15fab21349ce8.png]]

首先，Socket 系统调用会有三级参数 family、type、protocal，通过这三级参数，分别在 net\_proto\_family 表中找到 type 链表，在 type 链表中找到 protocal 对应的操作。这个操作分为两层，对于 TCP 协议来讲，第一层是 inet\_stream\_ops 层，第二层是 tcp_prot 层。

于是，接下来的系统调用规律就都一样了：

bind 第一层调用 inet\_stream\_ops 的 inet\_bind 函数，第二层调用 tcp\_prot 的 inet\_csk\_get_port 函数；

listen 第一层调用 inet\_stream\_ops 的 inet\_listen 函数，第二层调用 tcp\_prot 的 inet\_csk\_get_port 函数；

accept 第一层调用 inet\_stream\_ops 的 inet\_accept 函数，第二层调用 tcp\_prot 的 inet\_csk\_accept 函数；

connect 第一层调用 inet\_stream\_ops 的 inet\_stream\_connect 函数，第二层调用 tcp\_prot 的 tcp\_v4_connect 函数。

## 课堂练习

TCP 的三次握手协议非常重要，请你务必跟着代码走读一遍。另外我们这里重点关注了 TCP 的场景，请走读代码的时候，也看一下 UDP 是如何实现各层的函数的。

欢迎留言和我分享你的疑惑和见解 ，也欢迎可以收藏本节内容，反复研读。你也可以把今天的内容分享给你的朋友，和他一起学习和进步。