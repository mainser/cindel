#import "CindelFlutterLibsPlugin.h"

// Defined by CindelNativeRetention.c. Referencing every FFI entrypoint keeps
// the static Rust archive reachable when the application enables dead stripping.
extern void CindelRetainNativeSymbols(void);

@implementation CindelFlutterLibsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  CindelRetainNativeSymbols();
}
@end
