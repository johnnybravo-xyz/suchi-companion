# ML Kit loads these component registrars by manifest name and reflection.
# R8's transitive component rule retains their classes but drops their constructors.
-keepclassmembers class com.google.mlkit.common.internal.CommonComponentRegistrar {
    public <init>();
}
-keepclassmembers class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    public <init>();
}
