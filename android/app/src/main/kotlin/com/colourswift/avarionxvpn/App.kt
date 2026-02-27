package com.colourswift.avarionxvpn

import android.app.Application
import io.flutter.embedding.engine.FlutterEngineGroup

class App : Application() {
    companion object {
        lateinit var group: FlutterEngineGroup
    }

    override fun onCreate() {
        super.onCreate()
        group = FlutterEngineGroup(this)
    }
}
