上一节 qemu 初始化的 main 函数，我们解析了一个开头，得到了表示体系结构的 MachineClass 以及 MachineState。

## 4\. 初始化块设备

我们接着回到 main 函数，接下来初始化的是块设备，调用的是 configure_blockdev。这里我们需要重点关注上面参数中的硬盘，不过我们放在存储虚拟化那一节再解析。

configure\_blockdev(&bdo\_queue, machine_class, snapshot);

## 5\. 初始化计算虚拟化的加速模式

接下来初始化的是计算虚拟化的加速模式，也即要不要使用 KVM。根据参数中的配置是启用 KVM。这里调用的是 configure_accelerator。

configure_accelerator(current_machine, argv\[0\]);

void 

 configure_accelerator(MachineState *ms, const 

 char *progname)

{

const 

 char *accel;

char \*\*accel_list, \*\*tmp;

int ret;

bool accel_initialised = false;

bool init_failed = false;

AccelClass *acc = NULL;

accel = qemu\_opt\_get(qemu\_get\_machine_opts(), "accel");

accel = "kvm";

accel_list = g_strsplit(accel, ":", 0);

for (tmp = accel\_list; !accel\_initialised && tmp && *tmp; tmp++) {

acc = accel_find(*tmp);

ret = accel\_init\_machine(acc, ms);

}

}

static AccelClass *accel_find(const 

 char *opt_name)

{

char *class_name = g\_strdup\_printf(ACCEL\_CLASS\_NAME("%s"), opt_name);

AccelClass *ac = ACCEL_CLASS(object\_class\_by_name(class_name));

g_free(class_name);

return ac;

}

static 

 int 

 accel\_init\_machine(AccelClass \*acc, MachineState \*ms)

{

ObjectClass *oc = OBJECT_CLASS(acc);

const 

 char *cname = object\_class\_get_name(oc);

AccelState *accel = ACCEL(object_new(cname));

int ret;

ms->accelerator = accel;

*(acc->allowed) = true;

ret = acc->init_machine(ms);

return ret;

}

在 configure\_accelerator 中，我们看命令行参数里面的 accel，发现是 kvm，则调用 accel\_find 根据名字，得到相应的纸面上的 class，并初始化为 Class 类。

MachineClass 是计算机体系结构的 Class 类，同理，AccelClass 就是加速器的 Class 类，然后调用 accel\_init\_machine，通过 object_new，将 AccelClass 这个 Class 类实例化为 AccelState，类似对于体系结构的实例是 MachineState。

在 accel\_find 中，我们会根据名字 kvm，找到纸面上的 class，也即 kvm\_accel\_type，然后调用 type\_initialize，里面调用 kvm\_accel\_type 的 class\_init 方法，也即 kvm\_accel\_class\_init。

static 

 void 

 kvm\_accel\_class_init(ObjectClass *oc, void *data)

{

AccelClass *ac = ACCEL_CLASS(oc);

ac->name = "KVM";

ac->init\_machine = kvm\_init;

ac->allowed = &kvm_allowed;

}

在 kvm\_accel\_class\_init 中，我们创建 AccelClass，将 init\_machine 设置为 kvm\_init。在 accel\_init\_machine 中其实就调用了这个 init\_machine 函数，也即调用 kvm_init 方法。

static 

 int 

 kvm_init(MachineState *ms)

{

MachineClass *mc = MACHINE\_GET\_CLASS(ms);

int soft\_vcpus\_limit, hard\_vcpus\_limit;

KVMState *s;

const KVMCapabilityInfo *missing_cap;

int ret;

int type = 0;

const 

 char *kvm_type;

s = KVM_STATE(ms->accelerator);

s->fd = qemu_open("/dev/kvm", O_RDWR);

ret = kvm_ioctl(s, KVM\_GET\_API_VERSION, 0);

......

do {

ret = kvm_ioctl(s, KVM\_CREATE\_VM, type);

} while (ret == -EINTR);

......

s->vmfd = ret;

soft\_vcpus\_limit = kvm\_recommended\_vcpus(s);

hard\_vcpus\_limit = kvm\_max\_vcpus(s);

......

ret = kvm\_arch\_init(ms, s);

if (ret < 0) {

goto err;

}

if (machine\_kernel\_irqchip_allowed(ms)) {

kvm\_irqchip\_create(ms, s);

}

......

return 

 0;

}

这里面的操作就从用户态到内核态的 KVM 了。就像前面原理讲过的一样，用户态使用内核态 KVM 的能力，需要打开一个文件 /dev/kvm，这是一个字符设备文件，打开一个字符设备文件的过程我们讲过，这里不再赘述。

static struct miscdevice 

 kvm_dev 

 = {

KVM_MINOR,

"kvm",

&kvm\_chardev\_ops,

};

static struct file_operations 

 kvm\_chardev\_ops 

 = {

.unlocked\_ioctl = kvm\_dev_ioctl,

.compat\_ioctl = kvm\_dev_ioctl,

.llseek = noop_llseek,

};

KVM 这个字符设备文件定义了一个字符设备文件的操作函数 kvm\_chardev\_ops，这里面只定义了 ioctl 的操作。

接下来，用户态就通过 ioctl 系统调用，调用到 kvm\_dev\_ioctl 这个函数。这个过程我们在字符设备那一节也讲了。

static 

 long 

 kvm\_dev\_ioctl(struct file *filp,

unsigned 

 int ioctl, unsigned 

 long arg)

{

long r = -EINVAL;

switch (ioctl) {

case KVM\_GET\_API_VERSION:

r = KVM\_API\_VERSION;

break;

case KVM\_CREATE\_VM:

r = kvm\_dev\_ioctl\_create\_vm(arg);

break;

case KVM\_CHECK\_EXTENSION:

r = kvm\_vm\_ioctl\_check\_extension_generic(NULL, arg);

break;

case KVM\_GET\_VCPU\_MMAP\_SIZE:

r = PAGE_SIZE;

break;

......

}

out:

return r;

}

我们可以看到，在用户态 qemu 中，调用 KVM\_GET\_API\_VERSION 查看版本号，内核就有相应的分支，返回版本号，如果能够匹配上，则调用 KVM\_CREATE_VM 创建虚拟机。

创建虚拟机，需要调用 kvm\_dev\_ioctl\_create\_vm。

static 

 int 

 kvm\_dev\_ioctl\_create\_vm(unsigned 

 long type)

{

int r;

struct 

 kvm *kvm;

struct 

 file *file;

kvm = kvm\_create\_vm(type);

......

r = get\_unused\_fd_flags(O_CLOEXEC);

......

file = anon\_inode\_getfile("kvm-vm", &kvm\_vm\_fops, kvm, O_RDWR);

......

fd_install(r, file);

return r;

}

在 kvm\_dev\_ioctl\_create\_vm 中，首先调用 kvm\_create\_vm 创建一个 struct kvm 结构。这个结构在内核里面代表一个虚拟机。

从下面结构的定义里，我们可以看到，这里面有 vcpu，有 mm_struct 结构。这个结构本来用来管理进程的内存的。虚拟机也是一个进程，所以虚拟机的用户进程空间也是用它来表示。虚拟机里面的操作系统以及应用的进程空间不归它管。

在 kvm\_dev\_ioctl\_create\_vm 中，第二件事情就是创建一个文件描述符，和 struct file 关联起来，这个 struct file 的 file\_operations 会被设置为 kvm\_vm_fops。

struct 

 kvm {

struct 

 mm_struct *mm;

struct 

 kvm_memslots \_\_rcu *memslots\[KVM\_ADDRESS\_SPACE\_NUM\];

struct 

 kvm_vcpu *vcpus\[KVM\_MAX\_VCPUS\];

atomic_t online_vcpus;

int created_vcpus;

int last\_boosted\_vcpu;

struct 

 list_head vm_list;

struct 

 mutex lock;

struct 

 kvm\_io\_bus \_\_rcu *buses\[KVM\_NR_BUSES\];

......

struct 

 kvm\_vm\_stat stat;

struct 

 kvm_arch arch;

refcount_t users_count;

......

long tlbs_dirty;

struct 

 list_head devices;

pid_t userspace_pid;

};

static 

 struct 

 file_operations kvm\_vm\_fops = {

.release = kvm\_vm\_release,

.unlocked\_ioctl = kvm\_vm_ioctl,

.llseek = noop_llseek,

};

kvm\_dev\_ioctl\_create\_vm 结束之后，对于一台虚拟机而言，只是在内核中有一个数据结构，对于相应的资源还没有分配，所以我们还需要接着看。

## 6\. 初始化网络设备

接下来，调用 net\_init\_clients 进行网络设备的初始化。我们可以解析 net 参数，也会在 net\_init\_clients 中解析 netdev 参数。这属于网络虚拟化的部分，我们先暂时放一下。

int 

 net\_init\_clients(Error **errp)

{

QTAILQ_INIT(&net_clients);

if (qemu\_opts\_foreach(qemu\_find\_opts("netdev"),

net\_init\_netdev, NULL, errp)) {

return 

 -1;

}

if (qemu\_opts\_foreach(qemu\_find\_opts("nic"), net\_param\_nic, NULL, errp)) {

return 

 -1;

}

if (qemu\_opts\_foreach(qemu\_find\_opts("net"), net\_init\_client, NULL, errp)) {

return 

 -1;

}

return 

 0;

}

## 7.CPU 虚拟化

接下来，我们要调用 machine\_run\_board\_init。这里面调用了 MachineClass 的 init 函数。盼啊盼才到了它，这才调用了 pc\_init1。

void 

 machine\_run\_board_init(MachineState *machine)

{

MachineClass *machine_class = MACHINE\_GET\_CLASS(machine);

numa\_complete\_configuration(machine);

if (nb\_numa\_nodes) {

machine\_numa\_finish\_cpu\_init(machine);

}

......

machine_class->init(machine);

}

在 pc\_init1 里面，我们重点关注两件重要的事情，一个的 CPU 的虚拟化，主要调用 pc\_cpus\_init；另外就是内存的虚拟化，主要调用 pc\_memory_init。这一节我们重点关注 CPU 的虚拟化，下一节，我们来看内存的虚拟化。

void 

 pc\_cpus\_init(PCMachineState *pcms)

{

......

for (i = 0; i < smp_cpus; i++) {

pc\_new\_cpu(possible\_cpus->cpus\[i\].type, possible\_cpus->cpus\[i\].arch\_id, &error\_fatal);

}

}

static 

 void 

 pc\_new\_cpu(const 

 char *typename, int64_t apic_id, Error **errp)

{

Object *cpu = NULL;

cpu = object_new(typename);

object\_property\_set_uint(cpu, apic_id, "apic-id", &local_err);

object\_property\_set_bool(cpu, true, "realized", &local_err);

......

}

在 pc\_cpus\_init 中，对于每一个 CPU，都调用 pc\_new\_cpu，在这里，我们又看到了 object_new，这又是一个从 TypeImpl 到 Class 类再到对象的一个过程。

这个时候，我们就要看 CPU 的类是怎么组织的了。

在上面的参数里面，CPU 的配置是这样的：

-cpu SandyBridge,+erms,+smep,+fsgsbase,+pdpe1gb,+rdrand,+f16c,+osxsave,+dca,+pcid,+pdcm,+xtpr,+tm2,+est,+smx,+vmx,+ds_cpl,+monitor,+dtes64,+pbe,+tm,+ht,+ss,+acpi,+ds,+vme

在这里我们知道，SandyBridge 是 CPU 的一种类型。在 hw/i386/pc.c 中，我们能看到这种 CPU 的定义。

{ "SandyBridge" 

 "-" 

 TYPE\_X86\_CPU, "min-xlevel", "0x8000000a" }

接下来，我们就来看"SandyBridge"，也即 TYPE\_X86\_CPU 这种 CPU 的类，是一个什么样的结构。

static 

 const TypeInfo device\_type\_info = {

.name = TYPE_DEVICE,

.parent = TYPE_OBJECT,

.instance_size = sizeof(DeviceState),

.instance\_init = device\_initfn,

.instance\_post\_init = device\_post\_init,

.instance\_finalize = device\_finalize,

.class\_base\_init = device\_class\_base_init,

.class\_init = device\_class_init,

.abstract = true,

.class_size = sizeof(DeviceClass),

};

static 

 const TypeInfo cpu\_type\_info = {

.name = TYPE_CPU,

.parent = TYPE_DEVICE,

.instance_size = sizeof(CPUState),

.instance\_init = cpu\_common_initfn,

.instance\_finalize = cpu\_common_finalize,

.abstract = true,

.class_size = sizeof(CPUClass),

.class\_init = cpu\_class_init,

};

static 

 const TypeInfo x86\_cpu\_type_info = {

.name = TYPE\_X86\_CPU,

.parent = TYPE_CPU,

.instance_size = sizeof(X86CPU),

.instance\_init = x86\_cpu_initfn,

.abstract = true,

.class_size = sizeof(X86CPUClass),

.class\_init = x86\_cpu\_common\_class_init,

};

CPU 这种类的定义是有多层继承关系的。TYPE\_X86\_CPU 的父类是 TYPE\_CPU，TYPE\_CPU 的父类是 TYPE\_DEVICE，TYPE\_DEVICE 的父类是 TYPE_OBJECT。到头了。

这里面每一层都有 class\_init，用于从 TypeImpl 生产 xxxClass，也有 instance\_init 将 xxxClass 初始化为实例。

在 TYPE\_X86\_CPU 这一层的 class\_init 中，也即 x86\_cpu\_common\_class\_init 中，设置了 DeviceClass 的 realize 函数为 x86\_cpu_realizefn。这个函数很重要，马上就能用到。

static 

 void 

 x86\_cpu\_common\_class\_init(ObjectClass *oc, void *data)

{

X86CPUClass *xcc = X86\_CPU\_CLASS(oc);

CPUClass *cc = CPU_CLASS(oc);

DeviceClass *dc = DEVICE_CLASS(oc);

device\_class\_set\_parent\_realize(dc, x86\_cpu\_realizefn,

&xcc->parent_realize);

......

}

在 TYPE\_DEVICE 这一层的 instance\_init 函数 device\_initfn，会为这个设备添加一个属性"realized"，要设置这个属性，需要用函数 device\_set_realized。

static 

 void 

 device_initfn(Object *obj)

{

DeviceState *dev = DEVICE(obj);

ObjectClass *class;

Property *prop;

dev->realized = false;

object\_property\_add_bool(obj, "realized",

device\_get\_realized, device\_set\_realized, NULL);

......

}

我们回到 pc\_new\_cpu 函数，这里面就是通过 object\_property\_set\_bool 设置这个属性为 true，所以 device\_set_realized 函数会被调用。

在 device\_set\_realized 中，DeviceClass 的 realize 函数 x86\_cpu\_realizefn 会被调用。这里面 qemu\_init\_vcpu 会调用 qemu\_kvm\_start_vcpu。

static 

 void 

 qemu\_kvm\_start_vcpu(CPUState *cpu)

{

char thread\_name\[VCPU\_THREAD\_NAME\_SIZE\];

cpu->thread = g_malloc0(sizeof(QemuThread));

cpu->halt_cond = g_malloc0(sizeof(QemuCond));

qemu\_cond\_init(cpu->halt_cond);

qemu\_thread\_create(cpu->thread, thread\_name, qemu\_kvm\_cpu\_thread\_fn, cpu, QEMU\_THREAD_JOINABLE);

}

在这里面，为这个 vcpu 创建一个线程，也即虚拟机里面的一个 vcpu 对应物理机上的一个线程，然后这个线程被调度到某个物理 CPU 上。

我们来看这个 vcpu 的线程执行函数。

static 

 void *qemu\_kvm\_cpu\_thread\_fn(void *arg)

{

CPUState *cpu = arg;

int r;

rcu\_register\_thread();

qemu\_mutex\_lock_iothread();

qemu\_thread\_get_self(cpu->thread);

cpu->thread_id = qemu\_get\_thread_id();

cpu->can\_do\_io = 1;

current_cpu = cpu;

r = kvm\_init\_vcpu(cpu);

kvm\_init\_cpu_signals(cpu);

cpu->created = true;

qemu\_cond\_signal(&qemu\_cpu\_cond);

do {

if (cpu\_can\_run(cpu)) {

r = kvm\_cpu\_exec(cpu);

}

qemu\_wait\_io_event(cpu);

} while (!cpu->unplug || cpu\_can\_run(cpu));

qemu\_kvm\_destroy_vcpu(cpu);

cpu->created = false;

qemu\_cond\_signal(&qemu\_cpu\_cond);

qemu\_mutex\_unlock_iothread();

rcu\_unregister\_thread();

return 

 NULL;

}

在 qemu\_kvm\_cpu\_thread\_fn 中，先是 kvm\_init\_vcpu 初始化这个 vcpu。

int 

 kvm\_init\_vcpu(CPUState *cpu)

{

KVMState *s = kvm_state;

long mmap_size;

int ret;

......

ret = kvm\_get\_vcpu(s, kvm\_arch\_vcpu_id(cpu));

......

cpu->kvm_fd = ret;

cpu->kvm_state = s;

cpu->vcpu_dirty = true;

mmap_size = kvm_ioctl(s, KVM\_GET\_VCPU\_MMAP\_SIZE, 0);

......

cpu->kvm_run = mmap(NULL, mmap\_size, PROT\_READ | PROT\_WRITE, MAP\_SHARED, cpu->kvm_fd, 0);

......

ret = kvm\_arch\_init_vcpu(cpu);

err:

return ret;

}

在 kvm\_get\_vcpu 中，我们会调用 kvm\_vm\_ioctl(s, KVM\_CREATE\_VCPU, (void *)vcpu\_id)，在内核里面创建一个 vcpu。在上面创建 KVM\_CREATE\_VM 的时候，我们已经创建了一个 struct file，它的 file\_operations 被设置为 kvm\_vm\_fops，这个内核文件也是可以响应 ioctl 的。

如果我们切换到内核 KVM，在 kvm\_vm\_ioctl 函数中，有对于 KVM\_CREATE\_VCPU 的处理，调用的是 kvm\_vm\_ioctl\_create\_vcpu。

static 

 long kvm\_vm\_ioctl(struct file *filp,

unsigned 

 int ioctl, unsigned 

 long arg)

{

struct kvm *kvm = filp->private_data;

void __user *argp = (void __user *)arg;

int r;

switch (ioctl) {

case KVM\_CREATE\_VCPU:

r = kvm\_vm\_ioctl\_create\_vcpu(kvm, arg);

break;

case KVM\_SET\_USER\_MEMORY\_REGION: {

struct kvm\_userspace\_memory\_region kvm\_userspace_mem;

if (copy\_from\_user(&kvm\_userspace\_mem, argp,

sizeof(kvm\_userspace\_mem)))

goto 

 out;

r = kvm\_vm\_ioctl\_set\_memory\_region(kvm, &kvm\_userspace_mem);

break;

}

......

case KVM\_CREATE\_DEVICE: {

struct kvm\_create\_device cd;

if (copy\_from\_user(&cd, argp, sizeof(cd)))

goto 

 out;

r = kvm\_ioctl\_create_device(kvm, &cd);

if (copy\_to\_user(argp, &cd, sizeof(cd)))

goto 

 out;

break;

}

case KVM\_CHECK\_EXTENSION:

r = kvm\_vm\_ioctl\_check\_extension_generic(kvm, arg);

break;

default:

r = kvm\_arch\_vm_ioctl(filp, ioctl, arg);

}

out:

return r;

}

在 kvm\_vm\_ioctl\_create\_vcpu 中，kvm\_arch\_vcpu\_create 调用 kvm\_x86\_ops 的 vcpu\_create 函数来创建 CPU。

static 

 int kvm\_vm\_ioctl\_create\_vcpu(struct kvm *kvm, u32 id)

{

int r;

struct kvm_vcpu *vcpu;

kvm->created_vcpus++;

......

vcpu = kvm\_arch\_vcpu_create(kvm, id);

preempt\_notifier\_init(&vcpu->preempt\_notifier, &kvm\_preempt_ops);

r = kvm\_arch\_vcpu_setup(vcpu);

......

kvm\_get\_kvm(kvm);

r = create\_vcpu\_fd(vcpu);

kvm->vcpus\[atomic\_read(&kvm->online\_vcpus)\] = vcpu;

......

}

struct kvm\_vcpu *kvm\_arch\_vcpu\_create(struct kvm *kvm,

unsigned 

 int 

 id)

{

struct kvm_vcpu *vcpu;

vcpu = kvm\_x86\_ops->vcpu_create(kvm, id);

return vcpu;

}

static 

 int create\_vcpu\_fd(struct kvm_vcpu *vcpu)

{

return anon\_inode\_getfd("kvm-vcpu", &kvm\_vcpu\_fops, vcpu, O\_RDWR | O\_CLOEXEC);

}

然后，create\_vcpu\_fd 又创建了一个 struct file，它的 file\_operations 指向 kvm\_vcpu_fops。从这里可以看出，KVM 的内核模块是一个文件，可以通过 ioctl 进行操作。基于这个内核模块创建的 VM 也是一个文件，也可以通过 ioctl 进行操作。在这个 VM 上创建的 vcpu 同样是一个文件，同样可以通过 ioctl 进行操作。

我们回过头来看，kvm\_x86\_ops 的 vcpu\_create 函数。kvm\_x86\_ops 对于不同的硬件加速虚拟化指向不同的结构，如果是 vmx，则指向 vmx\_x86\_ops；如果是 svm，则指向 svm\_x86\_ops。我们这里看 vmx\_x86_ops。这个结构很长，里面有非常多的操作，我们用一个看一个。

static 

 struct 

 kvm\_x86\_ops vmx\_x86\_ops \_\_ro\_after_init = {

......

.vcpu\_create = vmx\_create_vcpu,

......

}

static 

 struct 

 kvm_vcpu *vmx\_create\_vcpu(struct 

 kvm *kvm, unsigned int id)

{

int err;

struct 

 vcpu_vmx *vmx = kmem\_cache\_zalloc(kvm\_vcpu\_cache, GFP_KERNEL);

int cpu;

vmx->vpid = allocate_vpid();

err = kvm\_vcpu\_init(&vmx->vcpu, kvm, id);

vmx->guest_msrs = kmalloc(PAGE\_SIZE, GFP\_KERNEL);

vmx->loaded_vmcs = &vmx->vmcs01;

vmx->loaded_vmcs->vmcs = alloc_vmcs();

vmx->loaded_vmcs->shadow_vmcs = NULL;

loaded\_vmcs\_init(vmx->loaded_vmcs);

cpu = get_cpu();

vmx\_vcpu\_load(&vmx->vcpu, cpu);

vmx->vcpu.cpu = cpu;

err = vmx\_vcpu\_setup(vmx);

vmx\_vcpu\_put(&vmx->vcpu);

put_cpu();

if (enable_ept) {

if (!kvm->arch.ept\_identity\_map_addr)

kvm->arch.ept\_identity\_map_addr =

VMX\_EPT\_IDENTITY\_PAGETABLE\_ADDR;

err = init\_rmode\_identity_map(kvm);

}

return &vmx->vcpu;

}

vmx\_create\_vcpu 创建用于表示 vcpu 的结构 struct vcpu\_vmx，并填写里面的内容。例如 guest\_msrs，咱们在讲系统调用的时候提过 msr 寄存器，虚拟机也需要有这样的寄存器。

enable_ept 是和内存虚拟化相关的，EPT 全称 Extended Page Table，顾名思义，是优化内存虚拟化的，这个功能我们放到内存的那一节讲。

最最重要的就是 loaded_vmcs 了。VMCS 是什么呢？它的全称是 Virtual Machine Control Structure。它是来干什么呢？

前面咱们讲进程调度的时候讲过，为了支持进程在 CPU 上的切换，CPU 硬件要求有一个 TSS 结构，用于保存进程运行时的所有寄存器的状态，进程切换的时候，需要根据 TSS 恢复寄存器。

虚拟机也是一个进程，也需要切换，而且切换更加的复杂，可能是两个虚拟机之间切换，也可能是虚拟机切换给内核，虚拟机因为里面还有另一个操作系统，要保存的信息比普通的进程多得多。那就需要有一个结构来保存虚拟机运行的上下文，VMCS 就是是 Intel 实现 CPU 虚拟化，记录 vCPU 状态的一个关键数据结构。

VMCS 数据结构主要包含以下信息。

Guest-state area，即 vCPU 的状态信息，包括 vCPU 的基本运行环境，例如寄存器等。

Host-state area，是物理 CPU 的状态信息。物理 CPU 和 vCPU 之间也会来回切换，所以，VMCS 中既要记录 vCPU 的状态，也要记录物理 CPU 的状态。

VM-execution control fields，对 vCPU 的运行行为进行控制。例如，发生中断怎么办，是否使用 EPT（Extended Page Table）功能等。

接下来，对于 VMCS，有两个重要的操作。

VM-Entry，我们称为从根模式切换到非根模式，也即切换到 guest 上，这个时候 CPU 上运行的是虚拟机。VM-Exit 我们称为 CPU 从非根模式切换到根模式，也即从 guest 切换到宿主机。例如，当要执行一些虚拟机没有权限的敏感指令时。

![[1ec7600be619221dfac03e6ade67f7dc_ebb2e570e3f54bb98.png]]

为了维护这两个动作，VMCS 里面还有几项内容：

VM-exit control fields，对 VM Exit 的行为进行控制。比如，VM Exit 的时候对 vCPU 来说需要保存哪些 MSR 寄存器，对于主机 CPU 来说需要恢复哪些 MSR 寄存器。

VM-entry control fields，对 VM Entry 的行为进行控制。比如，需要保存和恢复哪些 MSR 寄存器等。

VM-exit information fields，记录下发生 VM Exit 发生的原因及一些必要的信息，方便对 VM Exit 事件进行处理。

至此，内核准备完毕。

我们再回到 qemu 的 kvm\_init\_vcpu 函数，这里面除了创建内核中的 vcpu 结构之外，还通过 mmap 将内核的 vcpu 结构，映射到 qemu 中 CPUState 的 kvm_run 中，为什么能用 mmap 呢，上面咱们不是说过了吗，vcpu 也是一个文件。

我们再回到这个 vcpu 的线程函数 qemu\_kvm\_cpu\_thread\_fn，他在执行 kvm\_init\_vcpu 创建 vcpu 之后，接下来是一个 do-while 循环，也即一直运行，并且通过调用 kvm\_cpu\_exec，运行这个虚拟机。

int 

 kvm\_cpu\_exec(CPUState *cpu)

{

struct 

 kvm_run *run = cpu->kvm_run;

int ret, run_ret;

......

do {

......

run_ret = kvm\_vcpu\_ioctl(cpu, KVM_RUN, 0);

......

switch (run->exit_reason) {

case KVM\_EXIT\_IO:

kvm\_handle\_io(run->io.port, attrs,

(uint8_t *)run + run->io.data_offset,

run->io.direction,

run->io.size,

run->io.count);

break;

case KVM\_EXIT\_IRQ\_WINDOW\_OPEN:

ret = EXCP_INTERRUPT;

break;

case KVM\_EXIT\_SHUTDOWN:

qemu\_system\_reset_request(SHUTDOWN\_CAUSE\_GUEST_RESET);

ret = EXCP_INTERRUPT;

break;

case KVM\_EXIT\_UNKNOWN:

fprintf(stderr, "KVM: unknown exit, hardware reason %" PRIx64 "\\n",(uint64_t)run->hw.hardware\_exit\_reason);

ret = -1;

break;

case KVM\_EXIT\_INTERNAL_ERROR:

ret = kvm\_handle\_internal_error(cpu, run);

break;

......

}

} while (ret == 0);

......

return ret;

}

在 kvm\_cpu\_exec 中，我们能看到一个循环，在循环中，kvm\_vcpu\_ioctl(KVM_RUN) 运行这个虚拟机，这个时候 CPU 进入 VM-Entry，也即进入客户机模式。

如果一直是客户机的操作系统占用这个 CPU，则会一直停留在这一行运行，一旦这个调用返回了，就说明 CPU 进入 VM-Exit 退出客户机模式，将 CPU 交还给宿主机。在循环中，我们会对退出的原因 exit_reason 进行分析处理，因为有了 I/O，还有了中断等，做相应的处理。处理完毕之后，再次循环，再次通过 VM-Entry，进入客户机模式。如此循环，直到虚拟机正常或者异常退出。

我们来看 kvm\_vcpu\_ioctl(KVM_RUN) 在内核做了哪些事情。

上面我们也讲了，vcpu 在内核也是一个文件，也是通过 ioctl 进行用户态和内核态通信的，在内核中，调用的是 kvm\_vcpu\_ioctl。

static 

 long 

 kvm\_vcpu\_ioctl(struct file *filp,

unsigned 

 int ioctl, unsigned 

 long arg)

{

struct 

 kvm_vcpu *vcpu = filp->private_data;

void __user *argp = (void __user *)arg;

int r;

struct 

 kvm_fpu *fpu = NULL;

struct 

 kvm_sregs *kvm_sregs = NULL;

......

r = vcpu_load(vcpu);

switch (ioctl) {

case KVM_RUN: {

struct 

 pid *oldpid;

r = kvm\_arch\_vcpu\_ioctl\_run(vcpu, vcpu->run);

break;

}

case KVM\_GET\_REGS: {

struct 

 kvm_regs *kvm_regs;

kvm_regs = kzalloc(sizeof(struct kvm\_regs), GFP\_KERNEL);

r = kvm\_arch\_vcpu\_ioctl\_get_regs(vcpu, kvm_regs);

if (copy\_to\_user(argp, kvm_regs, sizeof(struct kvm_regs)))

goto out_free1;

break;

}

case KVM\_SET\_REGS: {

struct 

 kvm_regs *kvm_regs;

kvm_regs = memdup_user(argp, sizeof(*kvm_regs));

r = kvm\_arch\_vcpu\_ioctl\_set_regs(vcpu, kvm_regs);

break;

}

......

}

kvm\_arch\_vcpu\_ioctl\_run 会调用 vcpu_run，这里面也是一个无限循环。

static int vcpu_run(struct 

 kvm_vcpu *vcpu)

{

int r;

struct 

 kvm *kvm = vcpu->kvm;

for (;;) {

if (kvm\_vcpu\_running(vcpu)) {

r = vcpu\_enter\_guest(vcpu);

} else {

r = vcpu_block(kvm, vcpu);

}

....

if (signal_pending(current)) {

r = -EINTR;

vcpu->run->exit\_reason = KVM\_EXIT_INTR;

++vcpu->stat.signal_exits;

break;

}

if (need_resched()) {

cond_resched();

}

}

......

return r;

}

在这个循环中，除了调用 vcpu\_enter\_guest 进入客户机模式运行之外，还有对于信号的响应 signal_pending，也即一台虚拟机是可以被 kill 掉的，还有对于调度的响应，这台虚拟机可以被从当前的物理 CPU 上赶下来，换成别的虚拟机或者其他进程。

我们这里重点看 vcpu\_enter\_guest。

static int vcpu\_enter\_guest(struct 

 kvm_vcpu *vcpu)

{

r = kvm\_mmu\_reload(vcpu);

vcpu->mode = IN\_GUEST\_MODE;

kvm\_load\_guest_xcr0(vcpu);

......

guest\_enter\_irqoff();

kvm\_x86\_ops->run(vcpu);

vcpu->mode = OUTSIDE\_GUEST\_MODE;

......

kvm\_put\_guest_xcr0(vcpu);

kvm\_x86\_ops->handle\_external\_intr(vcpu);

++vcpu->stat.exits;

guest\_exit\_irqoff();

r = kvm\_x86\_ops->handle_exit(vcpu);

return r;

......

}

static 

 struct 

 kvm\_x86\_ops vmx\_x86\_ops \_\_ro\_after_init = {

......

.run = vmx\_vcpu\_run,

......

}

在 vcpu\_enter\_guest 中，我们会调用 vmx\_x86\_ops 的 vmx\_vcpu\_run 函数，进入客户机模式。

static 

 void __noclone vmx\_vcpu\_run(struct kvm_vcpu *vcpu)

{

struct 

 vcpu_vmx *vmx = to_vmx(vcpu);

unsigned 

 long debugctlmsr, cr3, cr4;

......

cr3 = \_\_get\_current\_cr3\_fast();

......

cr4 = cr4\_read\_shadow();

......

vmx->\_\_launched = vmx->loaded\_vmcs->launched;

asm(

"push %%" \_ASM\_DX "; push %%" \_ASM\_BP ";"

"push %%" \_ASM\_CX " \\n\\t"

"push %%" \_ASM\_CX " \\n\\t"

......

"mov %c\[rax\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_AX " \\n\\t"

"mov %c\[rbx\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_BX " \\n\\t"

"mov %c\[rdx\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_DX " \\n\\t"

"mov %c\[rsi\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_SI " \\n\\t"

"mov %c\[rdi\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_DI " \\n\\t"

"mov %c\[rbp\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_BP " \\n\\t"

#ifdef CONFIG\_X86\_64

"mov %c\[r8\](https://time.geekbang.org/column/article/%0), %%r8 \\n\\t"

"mov %c\[r9\](https://time.geekbang.org/column/article/%0), %%r9 \\n\\t"

"mov %c\[r10\](https://time.geekbang.org/column/article/%0), %%r10 \\n\\t"

"mov %c\[r11\](https://time.geekbang.org/column/article/%0), %%r11 \\n\\t"

"mov %c\[r12\](https://time.geekbang.org/column/article/%0), %%r12 \\n\\t"

"mov %c\[r13\](https://time.geekbang.org/column/article/%0), %%r13 \\n\\t"

"mov %c\[r14\](https://time.geekbang.org/column/article/%0), %%r14 \\n\\t"

"mov %c\[r15\](https://time.geekbang.org/column/article/%0), %%r15 \\n\\t"

#endif

"mov %c\[rcx\](https://time.geekbang.org/column/article/%0), %%" \_ASM\_CX " \\n\\t"

"jne 1f \\n\\t"

\_\_ex(ASM\_VMX_VMLAUNCH) "\\n\\t"

"jmp 2f \\n\\t"

"1: " \_\_ex(ASM\_VMX_VMRESUME) "\\n\\t"

"2: "

"mov %0, %c\[wordsize\](https://time.geekbang.org/column/article/%%" \_ASM\_SP ") \\n\\t"

"pop %0 \\n\\t"

"mov %%" \_ASM\_AX ", %c\[rax\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%" \_ASM\_BX ", %c\[rbx\](https://time.geekbang.org/column/article/%0) \\n\\t"

\_\_ASM\_SIZE(pop) " %c\[rcx\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%" \_ASM\_DX ", %c\[rdx\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%" \_ASM\_SI ", %c\[rsi\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%" \_ASM\_DI ", %c\[rdi\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%" \_ASM\_BP ", %c\[rbp\](https://time.geekbang.org/column/article/%0) \\n\\t"

#ifdef CONFIG\_X86\_64

"mov %%r8, %c\[r8\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r9, %c\[r9\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r10, %c\[r10\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r11, %c\[r11\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r12, %c\[r12\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r13, %c\[r13\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r14, %c\[r14\](https://time.geekbang.org/column/article/%0) \\n\\t"

"mov %%r15, %c\[r15\](https://time.geekbang.org/column/article/%0) \\n\\t"

#endif

"mov %%cr2, %%" \_ASM\_AX " \\n\\t"

"mov %%" \_ASM\_AX ", %c\[cr2\](https://time.geekbang.org/column/article/%0) \\n\\t"

"pop %%" \_ASM\_BP "; pop %%" \_ASM\_DX " \\n\\t"

"setbe %c\[fail\](https://time.geekbang.org/column/article/%0) \\n\\t"

".pushsection .rodata \\n\\t"

".global vmx_return \\n\\t"

"vmx_return: " \_ASM\_PTR " 2b \\n\\t"

......

);

......

vmx->loaded_vmcs->launched = 1;

vmx->exit_reason = vmcs_read32(VM\_EXIT\_REASON);

......

}

在 vmx\_vcpu\_run 中，出现了汇编语言的代码，比较难看懂，但是没有关系呀，里面有注释呀，我们可以沿着注释来看。

首先是 Store host registers，要从宿主机模式变为客户机模式了，所以原来宿主机运行时候的寄存器要保存下来。

接下来是 Load guest registers，将原来客户机运行的时候的寄存器加载进来。

接下来是 Enter guest mode，调用 ASM\_VMX\_VMLAUNCH 进入客户机模型运行，或者 ASM\_VMX\_VMRESUME 恢复客户机模型运行。

如果客户机因为某种原因退出，Save guest registers, load host registers，也即保存客户机运行的时候的寄存器，就加载宿主机运行的时候的寄存器。

最后将 exit_reason 保存在 vmx 结构中。

至此，CPU 虚拟化就解析完了。

## 总结时刻

CPU 的虚拟化过程还是很复杂的，我画了一张图总结了一下。

![[c43639f7024848aa3e828bcfc10ca467_520db74af69644238.png]]

首先，我们要定义 CPU 这种类型的 TypeInfo 和 TypeImpl、继承关系，并且声明它的类初始化函数。

在 qemu 的 main 函数中调用 MachineClass 的 init 函数，这个函数既会初始化 CPU，也会初始化内存。

CPU 初始化的时候，会调用 pc\_new\_cpu 创建一个虚拟 CPU，它会调用 CPU 这个类的初始化函数。

每一个虚拟 CPU 会调用 qemu\_thread\_create 创建一个线程，线程的执行函数为 qemu\_kvm\_cpu\_thread\_fn。

在虚拟 CPU 对应的线程执行函数中，我们先是调用 kvm\_vm\_ioctl(KVM\_CREATE\_VCPU)，在内核的 KVM 里面，创建一个结构 struct vcpu_vmx，表示这个虚拟 CPU。在这个结构里面，有一个 VMCS，用于保存当前虚拟机 CPU 的运行时的状态，用于状态切换。

在虚拟 CPU 对应的线程执行函数中，我们接着调用 kvm\_vcpu\_ioctl(KVM\_RUN)，在内核的 KVM 里面运行这个虚拟机 CPU。运行的方式是保存宿主机的寄存器，加载客户机的寄存器，然后调用 \_\_ex(ASM\_VMX\_VMLAUNCH) 或者 \_\_ex(ASM\_VMX\_VMRESUME)，进入客户机模式运行。一旦退出客户机模式，就会保存客户机寄存器，加载宿主机寄存器，进入宿主机模式运行，并且会记录退出虚拟机模式的原因。大部分的原因是等待 I/O，因而宿主机调用 kvm\_handle_io 进行处理。

## 课堂练习

在咱们上面操作 KVM 的过程中，出现了好几次文件系统。不愧是“Linux 中一切皆文件”。那你能否整理一下这些文件系统之间的关系呢？

欢迎留言和我分享你的疑惑和见解，也欢迎收藏本节内容，反复研读。你也可以把今天的内容分享给你的朋友，和他一起学习和进步。

![[8c0a95fa07a8b9a1abfd394479bdd637_f73ede3a7e4942b3b.jpg]]