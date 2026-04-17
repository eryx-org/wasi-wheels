// Stubs for the Itanium C++ exception ABI symbols that wasi-sdk's libc++abi
// does not implement for wasm32-wasip2. Anything that actually throws on WASI
// will trap — which is acceptable here: numpy's C++ code only throws on
// argument/state errors that should have been caught earlier in Python.

#include <stdio.h>
#include <stdlib.h>

void *__cxa_allocate_exception(unsigned long thrown_size) {
    (void)thrown_size;
    fprintf(stderr, "numpy-wasi: C++ exception thrown; aborting (unsupported on wasi).\n");
    abort();
}

void __cxa_throw(void *thrown_exception, void *tinfo, void (*dest)(void *)) {
    (void)thrown_exception;
    (void)tinfo;
    (void)dest;
    fprintf(stderr, "numpy-wasi: __cxa_throw called; aborting (unsupported on wasi).\n");
    abort();
}

void __cxa_free_exception(void *thrown_exception) {
    (void)thrown_exception;
}
