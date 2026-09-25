# VietTelex — R8 full mode. Activity/Service giữ qua manifest; Compose + AndroidX tự mang
# consumer rules. Không reflection, không serialization ⇒ không cần -keep thêm.
# Gỡ log/kiểm tra Kotlin không cần ở release (nhỏ + nhanh hơn).
-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    public static void checkNotNullParameter(java.lang.Object, java.lang.String);
    public static void checkParameterIsNotNull(java.lang.Object, java.lang.String);
}
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}
