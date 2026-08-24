# Keep ML Kit text recognition classes (仅保留 Latin + Chinese，移除 Japanese/Korean/Devanagari 以减小体积)
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }

# Keep ML Kit common classes
-keep class com.google.mlkit.common.** { *; }
-dontwarn com.google.mlkit.vision.**
-dontwarn com.google.mlkit.common.**

# Keep image package (used for pixel sampling in OCR)
-keep class com.google.mlkit.vision.text.TextRecognizer { *; }
-keep class com.google.mlkit.vision.text.TextRecognizerOptions { *; }
