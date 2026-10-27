#ifndef CJNI_H
#define CJNI_H

#if defined(__ANDROID__)
#include <jni.h>

/// UTF-8 copy of a Java string; free it with cjni_free.
char *cjni_copy_string(JNIEnv *env, jstring string);
void cjni_free(char *pointer);
/// A new Java string from UTF-8 text.
jstring cjni_new_string(JNIEnv *env, const char *text);
#endif

#endif
