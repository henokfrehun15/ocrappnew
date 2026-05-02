# ProGuard/R8 rules for release build
# Added to suppress missing TensorFlow Lite GPU delegate warnings
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# Keep TensorFlow Lite classes just in case
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }
