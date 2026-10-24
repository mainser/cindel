#ifndef CINDEL_NATIVE_H
#define CINDEL_NATIVE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Module entrypoint used by the Flutter plugin. Database calls use Dart FFI.
uint32_t cindel_abi_version(void);

#ifdef __cplusplus
}
#endif
#endif
