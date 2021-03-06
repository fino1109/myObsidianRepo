[[01Java类加载机制]]

### 说一下 JVM由那些部分组成，运行流程是什么？

![[Pasted image 20211124143647.png]]

-   JVM包含两个子系统和两个组件: 两个子系统为Class loader(类装载)、Execution engine(执行引擎)； 两个组件为Runtime data area(运行时数据区)、Native Interface(本地接口)。
    
    -   Class loader(类装载)：根据给定的全限定名类名(如：java.lang.Object)来装载class文件到Runtime data area中的method area。
        
    -   Execution engine（执行引擎）：执行classes中的指令。
        
    -   Native Interface(本地接口)：与native libraries交互，是其它编程语言交互的接口。
        
    -   Runtime data area(运行时数据区域)：这就是我们常说的JVM的内存。
        
-   **流程** ：首先通过编译器把 Java 代码转换成字节码，类加载器（ClassLoader）再把字节码加载到内存中，将其放在运行时数据区（Runtime data area）的方法区内，而字节码文件只是 JVM 的一套指令集规范，并不能直接交给底层操作系统去执行，因此需要特定的命令解析器执行引擎（Execution Engine），将字节码翻译成底层系统指令，再交由 CPU 去执行，而这个过程中需要调用其他语言的本地库接口（Native Interface）来实现整个程序的功能。
    

### 说一下 JVM 运行时数据区

-   Java 虚拟机在执行 Java 程序的过程中会把它所管理的内存区域划分为若干个不同的数据区域。这些区域都有各自的用途，以及创建和销毁的时间，有些区域随着虚拟机进程的启动而存在，有些区域则是依赖线程的启动和结束而建立和销毁。Java 虚拟机所管理的内存被划分为如下几个区域：
    

`简单的说就是我们java运行时的东西是放在那里的`

![[Pasted image 20211124143654.png]]

-   程序计数器（Program Counter Register）：当前线程所执行的字节码的行号指示器，字节码解析器的工作是通过改变这个计数器的值，来选取下一条需要执行的字节码指令，分支、循环、跳转、异常处理、线程恢复等基础功能，都需要依赖这个计数器来完成；
    
    `为什么要线程计数器？因为线程是不具备记忆功能`
    
-   Java 虚拟机栈（Java Virtual Machine Stacks）：每个方法在执行的同时都会在Java 虚拟机栈中创建一个栈帧（Stack Frame）用于存储局部变量表、操作数栈、动态链接、方法出口等信息；
    
    `栈帧就是Java虚拟机栈中的下一个单位`
    
-   本地方法栈（Native Method Stack）：与虚拟机栈的作用是一样的，只不过虚拟机栈是服务 Java 方法的，而本地方法栈是为虚拟机调用 Native 方法服务的；
    
    `Native 关键字修饰的方法是看不到的，Native 方法的源码大部分都是 C和C++ 的代码`
    
-   Java 堆（Java Heap）：Java 虚拟机中内存最大的一块，是被所有线程共享的，几乎所有的对象实例都在这里分配内存；
    
-   方法区（Methed Area）：用于存储已被虚拟机加载的类信息、常量、静态变量、即时编译后的代码等数据。
    

`后面有详细的说明JVM 运行时数据区`

### 详细的介绍下程序计数器？（重点理解）

1.  程序计数器是一块较小的内存空间，它可以看作是：保存当前线程所正在执行的字节码指令的地址(行号)
    
2.  由于Java虚拟机的多线程是通过线程轮流切换并分配处理器执行时间的方式来实现的，一个处理器都只会执行一条线程中的指令。因此，为了线程切换后能恢复到正确的执行位置，每条线程都有一个独立的程序计数器，各个线程之间计数器互不影响，独立存储。称之为“线程私有”的内存。程序计数器内存区域是虚拟机中唯一没有规定OutOfMemoryError情况的区域。
    
    `总结：也可以把它叫做线程计数器`
    

-   **例子**：在java中最小的执行单位是线程，线程是要执行指令的，执行的指令最终操作的就是我们的电脑，就是 CPU。在CPU上面去运行，有个非常不稳定的因素，叫做调度策略，这个调度策略是时基于时间片的，也就是当前的这一纳秒是分配给那个指令的。
    
-   **假如**：
    
    -   线程A在看直播 ![[Pasted image 20211124143705.png]]
        
    -   突然，线程B来了一个视频电话，就会抢夺线程A的时间片，就会打断了线程A，线程A就会挂起  ![[Pasted image 20211124143712.png]]
        
    -   然后，视频电话结束，这时线程A究竟该干什么？ （线程是最小的执行单位，他不具备记忆功能，他只负责去干，那这个记忆就由：**程序计数器来记录**）![[Pasted image 20211124143731.png]]
        

### 详细介绍下Java虚拟机栈?（重点理解）

1.  Java虚拟机是线程私有的，它的生命周期和线程相同。
    
2.  虚拟机栈描述的是Java方法执行的内存模型：`每个方法在执行的同时`都会创建一个栈帧（Stack Frame）用于存储局部变量表、操作数栈、动态链接、方法出口等信息。
    

-   **解释**：虚拟机栈中是有单位的，单位就是**栈帧**，一个方法一个**栈帧**。一个**栈帧**中他又要存储，局部变量，操作数栈，动态链接，出口等。
![[Pasted image 20211124143740.png]]

**解析栈帧：**

1.  局部变量表：是用来存储我们临时8个基本数据类型、对象引用地址、returnAddress类型。（returnAddress中保存的是return后要执行的字节码的指令地址。）
    
2.  操作数栈：操作数栈就是用来操作的，例如代码中有个 i = 6*6，他在一开始的时候就会进行操作，读取我们的代码，进行计算后再放入局部变量表中去
    
3.  动态链接：假如我方法中，有个 service.add()方法，要链接到别的方法中去，这就是动态链接，存储链接的地方。
    
4.  出口：出口是什呢，出口正常的话就是return 不正常的话就是抛出异常落
    

#### 一个方法调用另一个方法，会创建很多栈帧吗？

-   答：会创建。如果一个栈中有动态链接调用别的方法，就会去创建新的栈帧，栈中是由顺序的，一个栈帧调用另一个栈帧，另一个栈帧就会排在调用者下面
    

#### 栈指向堆是什么意思？

-   栈指向堆是什么意思，就是栈中要使用成员变量怎么办，栈中不会存储成员变量，只会存储一个应用地址
    

#### 递归的调用自己会创建很多栈帧吗？

-   答：递归的话也会创建多个栈帧，就是在栈中一直从上往下排下去
    

### 你能给我详细的介绍Java堆吗?（重点理解）

-   java堆（Java Heap）是java虚拟机所管理的内存中最大的一块，是被所有线程共享的一块内存区域，在虚拟机启动时创建。此内存区域的唯一目的就是存放对象实例。
    
-   在Java虚拟机规范中的描述是：所有的对象实例以及数组都要在堆上分配。
    
-   java堆是垃圾收集器管理的主要区域，因此也被成为“GC堆”。
    
-   从内存回收角度来看java堆可分为：新生代和老生代。
    
-   从内存分配的角度看，线程共享的Java堆中可能划分出多个线程私有的分配缓冲区。
    
-   无论怎么划分，都与存放内容无关，无论哪个区域，存储的都是对象实例，进一步的划分都是为了更好的回收内存，或者更快的分配内存。
    
-   根据Java虚拟机规范的规定，java堆可以处于物理上不连续的内存空间中。当前主流的虚拟机都是可扩展的（通过 -Xmx 和 -Xms 控制）。如果堆中没有内存可以完成实例分配，并且堆也无法再扩展时，将会抛出OutOfMemoryError异常。
    

### 能不能解释一下本地方法栈？

1.  本地方法栈很好理解，他很栈很像，只不过方法上带了 native 关键字的栈字
    
2.  它是虚拟机栈为虚拟机执行Java方法（也就是字节码）的服务方法
    
3.  native关键字的方法是看不到的，必须要去oracle官网去下载才可以看的到，而且native关键字修饰的大部分源码都是C和C++的代码。
    
4.  同理可得，本地方法栈中就是C和C++的代码
    

### 能不能解释一下方法区（重点理解）

1.  方法区是所有线程共享的内存区域，它用于存储已被Java虚拟机加载的类信息、常量、静态变量、即时编译器编译后的代码等数据。
    
2.  它有个别命叫Non-Heap（非堆）。当方法区无法满足内存分配需求时，抛出OutOfMemoryError异常。
    

### 什么是JVM字节码执行引擎

-   虚拟机核心的组件就是执行引擎，它负责执行虚拟机的字节码，一般户先进行编译成机器码后执行。
    
-   “虚拟机”是一个相对于“物理机”的概念，虚拟机的字节码是不能直接在物理机上运行的，需要JVM字节码执行引擎- 编译成机器码后才可在物理机上执行。
    

### 你听过直接内存吗？

-   直接内存（Direct Memory）并不是虚拟机运行时数据区的一部分，也不是Java虚拟机中定义的内存区域。但是这部分内存也被频繁地使用，而且也可能导致 OutOfMemoryError 异常出现，所以我们放到这里一起讲解。
    
-   我的理解就是直接内存是基于物理内存和Java虚拟机内存的中间内存
    

### 知道垃圾收集系统吗？

-   程序在运行过程中，会产生大量的内存垃圾（一些没有引用指向的内存对象都属于内存垃圾，因为这些对象已经无法访问，程序用不了它们了，对程序而言它们已经死亡），为了确保程序运行时的性能，java虚拟机在程序运行的过程中不断地进行自动的垃圾回收（GC）。
    
-   垃圾收集系统是Java的核心，也是不可少的，Java有一套自己进行垃圾清理的机制，开发人员无需手工清理
    
-   有一部分原因就是因为Java垃圾回收系统的强大导致Java领先市场
    

### 堆栈的区别是什么？

![[Pasted image 20211124143825.png]]

-   注意：
    
    -   静态变量放在方法区
        
    -   静态的对象还是放在堆。
        

### 深拷贝和浅拷贝

-   浅拷贝（shallowCopy）只是增加了一个指针指向已存在的内存地址，
    
-   深拷贝（deepCopy）是增加了一个指针并且申请了一个新的内存，使这个增加的指针指向这个新的内存，
    
-   浅复制：仅仅是指向被复制的内存地址，如果原地址发生改变，那么浅复制出来的对象也会相应的改变。
    
-   深复制：在计算机中开辟一块**新的内存地址**用于存放复制的对象。
    

### Java会存在内存泄漏吗？请说明为什么？

-   内存泄漏是指不再被使用的对象或者变量一直被占据在内存中。理论上来说，Java是有GC垃圾回收机制的，也就是说，不再被使用的对象，会被GC自动回收掉，自动从内存中清除。
    
-   但是，即使这样，Java也还是存在着内存泄漏的情况，java导致内存泄露的原因很明确：长生命周期的对象持有短生命周期对象的引用就很可能发生内存泄露，`尽管短生命周期对象已经不再需要，但是因为长生命周期对象持有它的引用而导致不能被回收`，这就是java中内存泄露的发生场景。

## Jdk7内存模型
 

## Jdk8内存模型