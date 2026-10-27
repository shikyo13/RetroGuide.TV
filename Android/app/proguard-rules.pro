# The Swift core's JNI entry point is looked up by name
# (Java_com_adamhunt_retroguide_core_NativeCore_call).
-keep class com.adamhunt.retroguide.core.NativeCore { *; }

# libmpv's native code calls MPVLib and its observers by name.
-keep class dev.jdtech.mpv.** { *; }
-keep class * implements dev.jdtech.mpv.MPVLib$EventObserver { *; }
