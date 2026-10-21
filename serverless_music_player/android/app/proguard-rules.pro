-keep class androidx.media.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# MuZic's own playback card
-keep class com.auralis.player.PlaybackService { *; }
-keep class com.auralis.player.TransportReceiver { *; }
