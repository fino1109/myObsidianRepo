上一节，我们讲了一下虚拟化的基本原理，以及 qemu、kvm 之间的关系。这一节，我们就来看一下，用户态的 qemu 和内核态的 kvm 如何一起协作，来创建虚拟机，实现 CPU 和内存虚拟化。

这里是上一节我们讲的 qemu 启动时候的命令。

qemu-system-x86_64 -enable-kvm -name ubuntutest -m 2048 

 -hda ubuntutest.qcow2 -vnc :19 

 -net nic,model=virtio -nettap,ifname=tap0,script=no,downscript=no

接下来，我们在这里下载qemu 的代码。qemu 的 main 函数在 vl.c 下面。这是一个非常非常长的函数，我们来慢慢地解析它。

## 1\. 初始化所有的 Module

第一步，初始化所有的 Module，调用下面的函数。

module\_call\_init(MODULE\_INIT\_QOM);

上一节我们讲过，qemu 作为中间人其实挺累的，对上面的虚拟机需要模拟各种各样的外部设备。当虚拟机真的要使用物理资源的时候，对下面的物理机上的资源要进行请求，所以它的工作模式有点儿类似操作系统对接驱动。驱动要符合一定的格式，才能算操作系统的一个模块。同理，qemu 为了模拟各种各样的设备，也需要管理各种各样的模块，这些模块也需要符合一定的格式。

定义一个 qemu 模块会调用 type_init。例如，kvm 的模块要在 accel/kvm/kvm-all.c 文件里面实现。在这个文件里面，有一行下面的代码：

type_init(kvm\_type\_init);

#define type_init(function) module_init(function, MODULE\_INIT\_QOM)

#define module_init(function, type) \

static void \_\_attribute\_\_((constructor)) do\_qemu\_init_ ## function(void) \

{ \

register\_module\_init(function, type); \

}

void register\_module\_init(void (*fn)(void), module\_init\_type 

 type)

{

ModuleEntry *e;

ModuleTypeList *l;

e = g_malloc0(sizeof(*e));

e->init = fn;

e->type = type;

l = find_type(type);

QTAILQ\_INSERT\_TAIL(l, e, node);

}

从代码里面的定义我们可以看出来，type\_init 后面的参数是一个函数，调用 type\_init 就相当于调用 module\_init，在这里函数就是 kvm\_type\_init，类型就是 MODULE\_INIT_QOM。是不是感觉和驱动有点儿像？

module\_init 最终要调用 register\_module\_init。属于 MODULE\_INIT\_QOM 这种类型的，有一个 Module 列表 ModuleTypeList，列表里面是一项一项的 ModuleEntry。KVM 就是其中一项，并且会初始化每一项的 init 函数为参数表示的函数 fn，也即 KVM 这个 module 的 init 函数就是 kvm\_type_init。

当然，MODULE\_INIT\_QOM 这种类型会有很多很多的 module，从后面的代码我们可以看到，所有调用 type\_init 的地方都注册了一个 MODULE\_INIT_QOM 类型的 Module。

了解了 Module 的注册机制，我们继续回到 main 函数中 module\_call\_init 的调用。

void 

 module\_call\_init(module\_init\_type type)

{

ModuleTypeList *l;

ModuleEntry *e;

l = find_type(type);

QTAILQ_FOREACH(e, l, node) {

e->init();

}

}

在 module\_call\_init 中，我们会找到 MODULE\_INIT\_QOM 这种类型对应的 ModuleTypeList，找出列表中所有的 ModuleEntry，然后调用每个 ModuleEntry 的 init 函数。这里需要注意的是，在 module\_call\_init 调用的这一步，所有 Module 的 init 函数都已经被调用过了。

后面我们会看到很多的 Module，当你看到它们的时候，你需要意识到，它的 init 函数在这里也被调用过了。这里我们还是以对于 kvm 这个 module 为例子，看看它的 init 函数都做了哪些事情。你会发现，其实它调用的是 kvm\_type\_init。

static void kvm\_type\_init(void)

{

type\_register\_static(&kvm\_accel\_type);

}

TypeImpl *type\_register\_static(const TypeInfo *info)

{

return 

 type_register(info);

}

TypeImpl *type_register(const TypeInfo *info)

{

assert(info->parent);

return 

 type\_register\_internal(info);

}

static TypeImpl *type\_register\_internal(const TypeInfo *info)

{

TypeImpl *ti;

ti = type_new(info);

type\_table\_add(ti);

return ti;

}

static TypeImpl *type_new(const TypeInfo *info)

{

TypeImpl *ti = g_malloc0(sizeof(*ti));

int i;

if (type\_table\_lookup(info->name) != NULL) {

}

ti->name = g_strdup(info->name);

ti->parent = g_strdup(info->parent);

ti->class_size = info->class_size;

ti->instance_size = info->instance_size;

ti->class_init = info->class_init;

ti->class\_base\_init = info->class\_base\_init;

ti->class_data = info->class_data;

ti->instance_init = info->instance_init;

ti->instance\_post\_init = info->instance\_post\_init;

ti->instance_finalize = info->instance_finalize;

ti->abstract = info->abstract;

for (i = 0; info->interfaces && info->interfaces\[i\].type; i++) {

ti->interfaces\[i\].typename = g_strdup(info->interfaces\[i\].type);

}

ti->num_interfaces = i;

return ti;

}

static void type\_table\_add(TypeImpl *ti)

{

assert(!enumerating_types);

g\_hash\_table_insert(type\_table\_get(), (void *)ti->name, ti);

}

static GHashTable *type\_table\_get(void)

{

static GHashTable *type_table;

if (type_table == NULL) {

type_table = g\_hash\_table_new(g\_str\_hash, g\_str\_equal);

}

return type_table;

}

static 

 const TypeInfo kvm\_accel\_type = {

.name = TYPE\_KVM\_ACCEL,

.parent = TYPE_ACCEL,

.class\_init = kvm\_accel\_class\_init,

.instance_size = sizeof(KVMState),

};

每一个 Module 既然要模拟某种设备，那应该定义一种类型 TypeImpl 来表示这些设备，这其实是一种面向对象编程的思路，只不过这里用的是纯 C 语言的实现，所以需要变相实现一下类和对象。

kvm\_type\_init 会注册 kvm\_accel\_type，定义上面的代码，我们可以认为这样动态定义了一个类。这个类的名字是 TYPE\_KVM\_ACCEL，这个类有父类 TYPE\_ACCEL，这个类的初始化应该调用函数 kvm\_accel\_class\_init（看，这里已经直接叫类 class 了）。如果用这个类声明一个对象，对象的大小应该是 instance_size。是不是有点儿 Java 语言反射的意思，根据一些名称的定义，一个类就定义好了。

这里的调用链为：kvm\_type\_init->type\_register\_static->type\_register->type\_register_internal。

在 type\_register\_internal 中，我们会根据 kvm\_accel\_type 这个 TypeInfo，创建一个 TypeImpl 来表示这个新注册的类，也就是说，TypeImpl 才是我们想要声明的那个 class。在 qemu 里面，有一个全局的哈希表 type\_table，用来存放所有定义的类。在 type\_new 里面，我们先从全局表里面根据名字找这个类。如果找到，说明这个类曾经被注册过，就报错；如果没有找到，说明这是一个新的类，则将 TypeInfo 里面信息填到 TypeImpl 里面。type\_table\_add 会将这个类注册到全局的表里面。到这里，我们注意，class_init 还没有被调用，也即这个类现在还处于纸面的状态。

这点更加像 Java 的反射机制了。在 Java 里面，对于一个类，首先我们写代码的时候要写一个 class xxx 的定义，编译好就放在.class 文件中，这也是出于纸面的状态。然后，Java 会有一个 Class 对象，用于读取和表示这个纸面上的 class xxx，可以生成真正的对象。

相同的过程在后面的代码中我们也可以看到，class\_init 会生成 XXXClass，就相当于 Java 里面的 Class 对象，TypeImpl 还会有一个 instance\_init 函数，相当于构造函数，用于根据 XXXClass 生成 Object，这就相当于 Java 反射里面最终创建的对象。和构造函数对应的还有 instance_finalize，相当于析构函数。

这一套反射机制放在 qom 文件夹下面，全称 QEMU Object Model，也即用 C 实现了一套面向对象的反射机制。

说完了初始化 Module，我们还回到 main 函数接着分析。

## 2\. 解析 qemu 的命令行

第二步我们就要开始解析 qemu 的命令行了。qemu 的命令行解析，就是下面这样一长串。还记得咱们自己写过一个解析命令行参数的程序吗？这里的 opts 是差不多的意思。

qemu\_add\_opts(&qemu\_drive\_opts);

qemu\_add\_opts(&qemu\_chardev\_opts);

qemu\_add\_opts(&qemu\_device\_opts);

qemu\_add\_opts(&qemu\_netdev\_opts);

qemu\_add\_opts(&qemu\_nic\_opts);

qemu\_add\_opts(&qemu\_net\_opts);

qemu\_add\_opts(&qemu\_rtc\_opts);

qemu\_add\_opts(&qemu\_machine\_opts);

qemu\_add\_opts(&qemu\_accel\_opts);

qemu\_add\_opts(&qemu\_mem\_opts);

qemu\_add\_opts(&qemu\_smp\_opts);

qemu\_add\_opts(&qemu\_boot\_opts);

qemu\_add\_opts(&qemu\_name\_opts);

qemu\_add\_opts(&qemu\_numa\_opts);

为什么有这么多的 opts 呢？这是因为，我们上一节给的参数都是简单的参数，实际运行中创建的 kvm 参数会复杂 N 倍。这里我们贴一个开源云平台软件 OpenStack 创建出来的 KVM 的参数，如下所示。不要被吓坏，你不需要全部看懂，只需要看懂一部分就行了。具体我来给你解析。

qemu-system-x86_64

-enable-kvm

-name instance-00000024

-machine pc-i440fx-trusty,accel=kvm,usb=off

-cpu SandyBridge,+erms,+smep,+fsgsbase,+pdpe1gb,+rdrand,+f16c,+osxsave,+dca,+pcid,+pdcm,+xtpr,+tm2,+est,+smx,+vmx,+ds_cpl,+monitor,+dtes64,+pbe,+tm,+ht,+ss,+acpi,+ds,+vme

-m 2048

-smp 1,sockets=1,cores=1,threads=1

......

-rtc base=utc,driftfix=slew

-drive file=/var/lib/nova/instances/1f8e6f7e-5a70-4780-89c1-464dc0e7f308/disk,if=none,id=drive-virtio-disk0,format=qcow2,cache=none

-device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1

-netdev tap,fd=32,id=hostnet0,vhost=on,vhostfd=37

-device virtio-net-pci,netdev=hostnet0,id=net0,mac=fa:16:3e:d1:2d:99,bus=pci.0,addr=0x3

-chardev file,id=charserial0,path=/var/lib/nova/instances/1f8e6f7e-5a70-4780-89c1-464dc0e7f308/console.log

-vnc 0.0.0.0:12

-device cirrus-vga,id=video0,bus=pci.0,addr=0x2

-enable-kvm：表示启用硬件辅助虚拟化。

-name instance-00000024：表示虚拟机的名称。

-machine pc-i440fx-trusty,accel=kvm,usb=off：machine 是什么呢？其实就是计算机体系结构。不知道什么是体系结构的话，可以订阅极客时间的另一个专栏《深入浅出计算机组成原理》。

qemu 会模拟多种体系结构，常用的有普通 PC 机，也即 x86 的 32 位或者 64 位的体系结构、Mac 电脑 PowerPC 的体系结构、Sun 的体系结构、MIPS 的体系结构，精简指令集。如果使用 KVM hardware-assisted virtualization，也即 BIOS 中 VD-T 是打开的，则参数中 accel=kvm。如果不使用 hardware-assisted virtualization，用的是纯模拟，则有参数 accel = tcg，-no-kvm。

-cpu SandyBridge,+erms,+smep,+fsgsbase,+pdpe1gb,+rdrand,+f16c,+osxsave,+dca,+pcid,+pdcm,+xtpr,+tm2,+est,+smx,+vmx,+ds_cpl,+monitor,+dtes64,+pbe,+tm,+ht,+ss,+acpi,+ds,+vme：表示设置 CPU，SandyBridge 是 Intel 处理器，后面的加号都是添加的 CPU 的参数，这些参数会显示在 /proc/cpuinfo 里面。

-m 2048：表示内存。

-smp 1,sockets=1,cores=1,threads=1：SMP 我们解析过，叫对称多处理器，和 NUMA 对应。qemu 仿真了一个具有 1 个 vcpu，一个 socket，一个 core，一个 threads 的处理器。

socket、core、threads 是什么概念呢？socket 就是主板上插 cpu 的槽的数目，也即常说的“路”，core 就是我们平时说的“核”，即双核、4 核等。thread 就是每个 core 的硬件线程数，即超线程。举个具体的例子，某个服务器是：2 路 4 核超线程（一般默认为 2 个线程），通过 cat /proc/cpuinfo，我们看到的是 242=16 个 processor，很多人也习惯成为 16 核了。

-rtc base=utc,driftfix=slew：表示系统时间由参数 -rtc 指定。

-device cirrus-vga,id=video0,bus=pci.0,addr=0x2：表示显示器用参数 -vga 设置，默认为 cirrus，它模拟了 CL-GD5446PCI VGA card。

有关网卡，使用 -net 参数和 -device。

从 HOST 角度：-netdev tap,fd=32,id=hostnet0,vhost=on,vhostfd=37。

从 GUEST 角度：-device virtio-net-pci,netdev=hostnet0,id=net0,mac=fa:16:3e:d1:2d:99,bus=pci.0,addr=0x3。

有关硬盘，使用 -hda -hdb，或者使用 -drive 和 -device。

从 HOST 角度：-drive file=/var/lib/nova/instances/1f8e6f7e-5a70-4780-89c1-464dc0e7f308/disk,if=none,id=drive-virtio-disk0,format=qcow2,cache=none

从 GUEST 角度：-device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1

-vnc 0.0.0.0:12：设置 VNC。

在 main 函数中，接下来的 for 循环和大量的 switch case 语句，就是对于这些参数的解析，我们不一一解析，后面真的用到这些参数的时候，我们再仔细看。

## 3\. 初始化 machine

回到 main 函数，接下来是初始化 machine。

machine\_class = select\_machine();

current\_machine = MACHINE(object\_new(object\_class\_get_name(

OBJECT\_CLASS(machine\_class))));

这里面的 machine_class 是什么呢？这还得从 machine 参数说起。

-machine pc-i440fx-trusty,accel=kvm,usb=off

这里的 pc-i440fx 是 x86 机器默认的体系结构。在 hw/i386/pc\_piix.c 中，它定义了对应的 machine\_class。

DEFINE\_I440FX\_MACHINE(v4_0, "pc-i440fx-4.0", NULL,

pc\_i440fx\_4\_0\_machine_options);

static void pc\_init\_

{ \

......

pc\_init1(machine, TYPE\_I440FX\_PCI\_HOST_BRIDGE, \

TYPE\_I440FX\_PCI_DEVICE); \

} \

DEFINE\_PC\_MACHINE(suffix, name, pc\_init\_

static void pc\_machine\_

) \

{ \

MachineClass *mc = MACHINE_CLASS(oc); \

optsfn(mc); \

mc->init = initfn; \

} \

static const TypeInfo pc\_machine\_type_

.name = namestr TYPE\_MACHINE\_SUFFIX, \

.parent = TYPE\_PC\_MACHINE, \

.class\_init = pc\_machine_

}; \

static void pc\_machine\_init_

{ \

type\_register(&pc\_machine\_type\_

} \

type\_init(pc\_machine\_init\_

为了定义 machine\_class，这里有一系列的宏定义。入口是 DEFINE\_I440FX\_MACHINE。这个宏有几个参数，v4\_0 是后缀，"pc-i440fx-4.0"是名字，pc\_i440fx\_4\_0\_machine\_options 是一个函数，用于定义 machine\_class 相关的选项。这个函数定义如下：

static void pc\_i440fx\_4\_0\_machine_options(MachineClass *m)

{

pc\_i440fx\_machine_options(m);

m->alias = "pc";

m->is_default = 1;

}

static void pc\_i440fx\_machine_options(MachineClass *m)

{

PCMachineClass *pcmc = PC\_MACHINE\_CLASS(m);

pcmc->default\_nic\_model = "e1000";

m->family = "pc_piix";

m->desc = "Standard PC (i440FX + PIIX, 1996)";

m->default\_machine\_opts = "firmware=bios-256k.bin";

m->default_display = "std";

machine\_class\_allow\_dynamic\_sysbus_dev(m, TYPE\_RAMFB\_DEVICE);

}

我们先不看 pc\_i440fx\_4\_0\_machine\_options，先来看 DEFINE\_I440FX_MACHINE。

这里面定义了一个 pc\_init\_##suffix，也就是 pc\_init\_v4\_0。这里面转而调用 pc\_init1。注意这里这个函数只是定义了一下，没有被调用。

接下来，DEFINE\_I440FX\_MACHINE 里面又定义了 DEFINE\_PC\_MACHINE。它有四个参数，除了 DEFINE\_I440FX\_MACHINE 传进来的三个参数以外，多了一个 initfn，也即初始化函数，指向刚才定义的 pc\_init\_##suffix。

在 DEFINE\_PC\_MACHINE 中，我们定义了一个函数 pc\_machine\_##suffix##class\_init。从函数的名字 class\_init 可以看出，这是 machine\_class 从纸面上的 class 初始化为 Class 对象的方法。在这个函数里面，我们可以看到，它创建了一个 MachineClass 对象，这个就是 Class 对象。MachineClass 对象的 init 函数指向上面定义的 pc\_init##suffix，说明这个函数是 machine 这种类型初始化的一个函数，后面会被调用。

接着，我们看 DEFINE\_PC\_MACHINE。它定义了一个 pc\_machine\_type_##suffix 的 TypeInfo。这是用于生成纸面上的 class 的原材料，果真后面调用了 type_init。

看到了 type\_init，我们应该能够想到，既然它定义了一个纸面上的 class，那上面的那句 module\_call\_init，会和我们上面解析的 type\_init 是一样的，在全局的表里面注册了一个全局的名字是"pc-i440fx-4.0"的纸面上的 class，也即 TypeImpl。

现在全局表中有这个纸面上的 class 了。我们回到 select_machine。

static MachineClass *select_machine(void)

{

MachineClass *machine_class = find\_default\_machine();

const 

 char *optarg;

QemuOpts *opts;

......

opts = qemu\_get\_machine_opts();

qemu\_opts\_loc_restore(opts);

optarg = qemu\_opt\_get(opts, "type");

if (optarg) {

machine_class = machine_parse(optarg);

}

......

return machine_class;

}

MachineClass *find\_default\_machine(void)

{

GSList \*el, \*machines = object\_class\_get_list(TYPE_MACHINE, false);

MachineClass *mc = NULL;

for (el = machines; el; el = el->next) {

MachineClass *temp = el->data;

if (temp->is_default) {

mc = temp;

break;

}

}

g\_slist\_free(machines);

return mc;

}

static MachineClass *machine_parse(const 

 char *name)

{

MachineClass *mc = NULL;

GSList \*el, \*machines = object\_class\_get_list(TYPE_MACHINE, false);

if (name) {

mc = find_machine(name);

}

if (mc) {

g\_slist\_free(machines);

return mc;

}

......

}

在 select\_machine 中，有两种方式可以生成 MachineClass。一种方式是 find\_default\_machine，找一个默认的；另一种方式是 machine\_parse，通过解析参数生成 MachineClass。无论哪种方式，都会调用 object\_class\_get\_list 获得一个 MachineClass 的列表，然后在里面找。object\_class\_get\_list 定义如下：

GSList *object\_class\_get_list(const 

 char *implements_type,

bool include_abstract)

{

GSList *list = NULL;

object\_class\_foreach(object\_class\_get\_list\_tramp,

implements\_type, include\_abstract, &list);

return list;

}

void 

 object\_class\_foreach(void (\*fn)(ObjectClass \*klass, void *opaque), const 

 char *implements_type, bool include_abstract,

void *opaque)

{

OCFData data = { fn, implements\_type, include\_abstract, opaque };

enumerating_types = true;

g\_hash\_table_foreach(type\_table\_get(), object\_class\_foreach_tramp, &data);

enumerating_types = false;

}

在全局表 type\_table\_get() 中，对于每一项 TypeImpl，我们都执行 object\_class\_foreach_tramp。

static void object\_class\_foreach_tramp(gpointer key, gpointer value,

gpointer opaque)

{

OCFData *data = opaque;

TypeImpl *type = value;

ObjectClass *k;

type_initialize(type);

k = type->class;

......

data->fn(k, data->opaque);

}

static void type_initialize(TypeImpl *ti)

{

TypeImpl *parent;

......

ti->class_size = type\_class\_get_size(ti);

ti->instance_size = type\_object\_get_size(ti);

if (ti->instance_size == 0) {

ti->abstract = true;

}

......

ti->class = g_malloc0(ti->class_size);

......

ti->class->type = ti;

while (parent) {

if (parent->class\_base\_init) {

parent->class\_base\_init(ti->class, ti->class_data);

}

parent = type\_get\_parent(parent);

}

if (ti->class_init) {

ti->class_init(ti->class, ti->class_data);

}

}

在 object\_class\_foreach\_tramp 中，会调用将 type\_initialize，这里面会调用 class_init 将纸面上的 class 也即 TypeImpl 变为 ObjectClass，ObjectClass 是所有 Class 类的祖先，MachineClass 是它的子类。

因为在 machine 的命令行里面，我们指定了名字为"pc-i440fx-4.0"，就肯定能够找到我们注册过了的 TypeImpl，并调用它的 class_init 函数。

因而 pc\_machine\_##suffix##class\_init 会被调用，在这里面，pc\_i440fx\_machine\_options 才真正被调用初始化 MachineClass，并且将 MachineClass 的 init 函数设置为 pc_init##suffix。也即，当 select_machine 执行完毕后，就有一个 MachineClass 了。

接着，我们回到 object\_new。这就很好理解了，MachineClass 是一个 Class 类，接下来应该通过它生成一个 Instance，也即对象，这就是 object\_new 的作用。

Object *object_new(const char *typename)

{

TypeImpl *ti = type\_get\_by_name(typename);

return 

 object\_new\_with_type(ti);

}

static 

 Object *object\_new\_with_type(Type type)

{

Object *obj;

type_initialize(type);

obj = g_malloc(type->instance_size);

object\_initialize\_with_type(obj, type->instance_size, type);

obj->free = g_free;

return obj;

}

object\_new 中，TypeImpl 的 instance\_init 会被调用，创建一个对象。current_machine 就是这个对象，它的类型是 MachineState。

至此，绕了这么大一圈，有关体系结构的对象才创建完毕，接下来很多的设备的初始化，包括 CPU 和内存的初始化，都是围绕着体系结构的对象来的，后面我们会常常看到 current_machine。

## 总结时刻

这一节，我们学到，虚拟机对于设备的模拟是一件非常复杂的事情，需要用复杂的参数模拟各种各样的设备。为了能够适配这些设备，qemu 定义了自己的模块管理机制，只有了解了这种机制，后面看每一种设备的虚拟化的时候，才有一个整体的思路。

这里的 MachineClass 是我们遇到的第一个，我们需要掌握它里面各种定义之间的关系。

![[078dc698ef1b3df93ee9569e55ea2f30_4a9768b537e94580a.png]]

每个模块都会有一个定义 TypeInfo，会通过 type_init 变为全局的 TypeImpl。TypeInfo 以及生成的 TypeImpl 有以下成员：

name 表示当前类型的名称

parent 表示父类的名称

class_init 用于将 TypeImpl 初始化为 MachineClass

instance_init 用于将 MachineClass 初始化为 MachineState

所以，以后遇到任何一个类型的时候，将父类和子类之间的关系，以及对应的初始化函数都要看好，这样就一目了然了。

## 课堂练习

你可能会问，这么复杂的 qemu 命令，我是怎么找到的，当然不是我一个字一个字打的，这是著名的云平台管理软件 OpenStack 创建虚拟机的时候自动生成的命令行。所以，给你留一道课堂练习题，请你看一下 OpenStack 的基本原理，看它是通过什么工具来管理如此复杂的命令行的。

欢迎留言和我分享你的疑惑和见解，也欢迎可以收藏本节内容，反复研读。你也可以把今天的内容分享给你的朋友，和他一起学习和进步。