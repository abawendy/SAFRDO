#include <stdio.h>
#include <stdlib.h>
#include <time.h>
/* Random-access latency vs working-set size (pointer chase, single cycle).
   This is the access pattern of hash joins / index probes -- the memory wall. */
int main(void){
    size_t bytes[] = {4096, 32768, 262144, 2097152, 8388608, 33554432, 134217728};
    const char* lbl[] = {"4 KB (L1)","32 KB (L1)","256 KB (L2)","2 MB (L3)",
                         "8 MB (>L3)","32 MB (DRAM)","128 MB (DRAM)"};
    printf(" working set     ns / random access\n");
    printf("-------------------------------------\n");
    for(int s=0;s<7;s++){
        size_t n = bytes[s]/sizeof(int);
        int* a = malloc(bytes[s]);
        for(size_t i=0;i<n;i++) a[i]=(int)i;
        for(size_t i=n-1;i>0;i--){ size_t j=(size_t)rand()%i; int t=a[i];a[i]=a[j];a[j]=t; } /* Sattolo: one cycle */
        volatile int idx=0; long M=100000000;
        clock_t t0=clock();
        for(long k=0;k<M;k++) idx=a[idx];
        double ns=(double)(clock()-t0)/CLOCKS_PER_SEC*1e9/M;
        printf("%12s   %8.2f\n", lbl[s], ns);
        free(a);
    }
    return 0;
}
