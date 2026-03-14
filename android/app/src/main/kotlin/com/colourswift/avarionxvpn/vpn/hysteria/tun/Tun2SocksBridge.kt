package com.colourswift.avarionxvpn.vpn.hysteria.tun

object Tun2SocksBridge {
    init {
        System.loadLibrary("cs_tun2socks")
    }

    external fun nativeStart(tunFd: Int, config: String): Int
    external fun nativeStop()
}