#if os(Android)
import CJNI

/// `NativeCore.call(request)`: one JSON request in, one JSON response out.
/// Kotlin calls it from a background thread; it blocks until the work is done.
@_cdecl("Java_com_adamhunt_retroguide_core_NativeCore_call")
public func nativeCoreCall(_ env: UnsafeMutablePointer<JNIEnv?>, _ type: jclass, _ request: jstring) -> jstring? {
    guard let raw = cjni_copy_string(env, request) else { return nil }
    let text = String(cString: raw)
    cjni_free(raw)
    let response = Core.shared.handle(text)
    return response.withCString { cjni_new_string(env, $0) }
}
#endif
