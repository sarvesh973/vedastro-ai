package com.mokshastro.ai

import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Native edge-to-edge setup. The black status-bar strip comes from
    // styles.xml's `windowDrawsSystemBarBackgrounds=false`, an OS window
    // flag that Flutter's setEnabledSystemUIMode cannot override. CI
    // regenerates styles.xml on every build (flutter_native_splash:create),
    // so the fix lives here in MainActivity, which CI never touches.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
    }
}
