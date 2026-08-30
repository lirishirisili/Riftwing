# Keep the LevelPlay mediation SDK public surface (per LevelPlay integration guide).
-keep public interface com.ironsource.mediationsdk.sdk.** { *; }
-keep public interface com.ironsource.mediationsdk.impressionData.ImpressionDataListener { *; }
-keep class com.unity3d.mediation.** { *; }
-keep class com.ironsource.** { *; }

# Meta Audience Network (FAN) — LevelPlay facebook-adapter 5.4.0 / SDK 6.22.0.
-dontwarn com.facebook.ads.internal.**
-keeppackagenames com.facebook.*
-keep public class com.facebook.ads.** { *; }
-keep public class com.facebook.ads.** { public protected *; }
