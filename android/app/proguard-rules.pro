# Preserve runtime metadata used by Flutter plugins and serialized API models.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
-keepattributes Signature,InnerClasses,EnclosingMethod

# Room 2.5.0's consumer rule keeps RoomDatabase implementations but does not
# keep the no-argument constructors that Room invokes reflectively. R8 can
# otherwise remove WorkDatabase_Impl.<init>() from release builds.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
