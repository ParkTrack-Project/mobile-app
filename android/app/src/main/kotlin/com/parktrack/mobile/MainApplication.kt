package com.parktrack.mobile

import android.app.Application
import android.content.Context
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Read saved locale from SharedPreferences BEFORE initialization
        val prefs = getSharedPreferences("app_settings", Context.MODE_PRIVATE)
        val savedLocale = prefs.getString("map_locale", null)
        
        if (savedLocale != null) {
            MapKitFactory.setLocale(savedLocale)
        }
        
        MapKitFactory.setApiKey("3f833508-456e-4d01-a150-751294a1c879")
    }
}
