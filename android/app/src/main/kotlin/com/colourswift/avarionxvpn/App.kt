package com.colourswift.avarionxvpn

import android.app.Application
import com.colourswift.avarionxvpn.vpn.backend_port.core.VpnConnectionController
import io.flutter.embedding.engine.FlutterEngineGroup

class App : Application() {
    companion object {
        lateinit var group: FlutterEngineGroup
    }

    override fun onCreate() {
        super.onCreate()
        group = FlutterEngineGroup(this)
        VpnConnectionController.init(this)
    }
}
