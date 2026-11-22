//
//  ADXPthreadCompat.c
//  App 扩展层 — 修正 pthread_create_suspended_np 的线程入口
//
//  背景（真机日志）：arm64e 包里第一次注入 SpringBoard 时，进程收到 SIGBUS：
//    (rc) firstExceptionPort: 0x567623, secondExceptionPort: 0x56741b
//    *** BLADE CRASH: signal 10 (Bus error: 10) ***
//  紧接着 RemoteCall 在目标内核栈里找不到 dummyThreadTro，整个会话作废。
//
//  RemoteCall 建「挂起线程」时把 dlsym("getpid") 直接当成线程入口传进去 ——
//  getpid 的签名是 int(void)，既不是 void*(void*) 也不返回。arm64e 上这条路
//  很脆：线程一旦真的被执行（_np 变体在个别系统版本上不保证一直挂起），
//  getpid 返回时会跳到无效的 LR，正好表现为 SIGBUS。
//
//  这里不改第三方源码，只在主可执行文件里定义同名符号（主镜像的定义优先于
//  libsystem 里的），把入口换成签名正确、永不返回的桩函数；真实的 pthread
//  实现仍由 dlsym(RTLD_NEXT) 调回去，所以线程对象、TRO、内核结构一切照旧。
//
#include <pthread.h>
#include <stdio.h>
#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <unistd.h>

typedef int (*adx_pcsn_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);

/// 永远不会返回的入口：即使线程被唤醒也不会跳到无效地址。
static void *adx_suspended_stub(void *arg) {
    (void)arg;
    for (;;) pause();
    return NULL;
}

int pthread_create_suspended_np(pthread_t *thread, const pthread_attr_t *attr,
                                void *(*start_routine)(void *), void *arg) {
    static adx_pcsn_fn real_fn = NULL;
    static int probe = 0;   // 0 = 未探测, 1 = 可用, -1 = 不可用
    if (!probe) {
        real_fn = (adx_pcsn_fn)dlsym(RTLD_NEXT, "pthread_create_suspended_np");
        probe = real_fn ? 1 : -1;
    }
    if (!real_fn) return ENOSYS;
    (void)start_routine;
    int rc = real_fn(thread, attr, adx_suspended_stub, arg);
    if (rc == 0) {
        // 只在第一次调用时打一行，避免刷屏；用来确认这层生效了。
        static int logged = 0;
        if (!logged) {
            logged = 1;
            printf("[adx] (thread) 已用安全入口创建挂起线程（原入口 %p 不使用）\n",
                   (void *)start_routine);
            fflush(stdout);
        }
    }
    return rc;
}