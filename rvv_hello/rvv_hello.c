#include <stdio.h>
#include <stdint.h>
#include <asm/hwprobe.h>

// struct riscv_hwprobe {
//     __s64 key;
//     __u64 value;
// };

// long sys_riscv_hwprobe(struct riscv_hwprobe *pairs, size_t pair_count,
//                        size_t cpu_count, cpu_set_t *cpus,
//                        unsigned int flags);

int main(){
    // printf("Hello World, attempting an rdtime\n");

    // volatile uint64_t csr_time = 0;
    // asm volatile ("rdtime %0" : "=r"(csr_time));    

    // printf("I survived rdtime, it gave me %lu\n");

    // long hw_probe_ret = 0;
    // riscv_hwprobe hw_probe;

    // hw_probe_ret = sys_riscv_hwprobe( &hw_probe, 
    //                                     size_t pair_count,
    //                                     size_t cpu_count, 
    //                                     cpu_set_t *cpus,
    //                                     unsigned int flags
    //                                 );    
    // // First set MSTATUS.VS
    // asm volatile (" li      t0, %0       " :: "i"(MSTATUS_FS | MSTATUS_XS | MSTATUS_VS));
    // asm volatile (" csrs    mstatus, t0" );

    printf("Hello World, attempting some RVV\n");

    // Run some vector instructions here
    // Vector configuration
    #define AVL 32
    uint64_t vl;
    asm volatile("li        t0 ,  %0" :: "i"(32));
    asm volatile("vsetvli   %0, t0, e64, m8, ta, ma" : "=r"(vl));

    // Vector permutation/arithmetic
    asm volatile("vmv.v.i   v0 ,  1");
    asm volatile("vadd.vv   v16, v0, v0");

    // Allocate array in memory
    uint64_t array [AVL];
    // initialize with deadbeef
    for ( unsigned int i = 0; i < AVL; i++ ) {
        array[i] = 0xdeadbeefdeadbeef;
    }

    uint64_t* address = array;
    // Vector load
    asm volatile("vle64.v	v24, (%0)": "+&r"(address));

    // Vector store
    asm volatile("vse64.v	v16, (%0)": "+&r"(address));

    // Vector load
    asm volatile("vle64.v	v8 , (%0)": "+&r"(address));

    printf("Survived RVV\n");

    return 0;
}