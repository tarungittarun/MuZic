-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# MuZic's shade-card service and its button receiver.
-keep class com.auralis.player.PlaybackService { *; }
-keep class com.auralis.player.TransportReceiver { *; }
