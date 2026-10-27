#include "cjni.h"

#if defined(__ANDROID__)
#include <stdlib.h>
#include <string.h>

char *cjni_copy_string(JNIEnv *env, jstring string) {
    const char *chars = (*env)->GetStringUTFChars(env, string, NULL);
    char *copy = strdup(chars);
    (*env)->ReleaseStringUTFChars(env, string, chars);
    return copy;
}

void cjni_free(char *pointer) {
    free(pointer);
}

jstring cjni_new_string(JNIEnv *env, const char *text) {
    return (*env)->NewStringUTF(env, text);
}
#endif
