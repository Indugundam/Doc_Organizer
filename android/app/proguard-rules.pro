# google_mlkit_text_recognition references the optional Chinese, Devanagari,
# Japanese and Korean recognizers. Only the Latin one is bundled (and used),
# so let R8 ignore the missing classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
