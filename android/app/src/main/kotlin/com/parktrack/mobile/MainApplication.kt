package com.parktrack.mobile

import android.app.Application
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MapKitFactory.setApiKey("3f833508-456e-4d01-a150-751294a1c879")
    }
}
