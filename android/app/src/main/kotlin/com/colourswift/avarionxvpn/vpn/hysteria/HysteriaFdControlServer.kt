package com.colourswift.avarionxvpn.vpn.hysteria

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class HysteriaFdControlServer(
    private val socketPath: String,
    private val protectFd: (Int) -> Boolean,
    private val stats: HysteriaVpnStats
) {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var boundSocket: LocalSocket? = null

    @Volatile
    private var serverSocket: LocalServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return

        executor.execute {
            try {
                bindServer()
                acceptLoop()
            } catch (t: Throwable) {
                stats.setLastError(t.message ?: "fd control server error")
            } finally {
                closeServer()
                cleanupSocketPath()
            }
        }
    }

    fun stop() {
        running.set(false)
        closeServer()
        executor.shutdownNow()
        cleanupSocketPath()
    }

    fun isRunning(): Boolean {
        return running.get()
    }

    private fun bindServer() {
        cleanupSocketPath()

        val parent = File(socketPath).parentFile
        if (parent != null && !parent.exists()) {
            parent.mkdirs()
        }

        val socket = LocalSocket()
        socket.bind(
            LocalSocketAddress(
                socketPath,
                LocalSocketAddress.Namespace.FILESYSTEM
            )
        )

        val fd = socket.fileDescriptor
            ?: throw IllegalStateException("Failed to get bound fd for FD control socket")

        val server = LocalServerSocket(fd)

        boundSocket = socket
        serverSocket = server
    }

    private fun acceptLoop() {
        while (running.get()) {
            val server = serverSocket ?: break
            val client = try {
                server.accept()
            } catch (_: Throwable) {
                if (!running.get()) {
                    break
                } else {
                    continue
                }
            }

            try {
                handleClient(client)
            } catch (t: Throwable) {
                stats.setLastError(t.message ?: "fd control client error")
                try {
                    client.close()
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun handleClient(client: LocalSocket) {
        client.use { socket ->
            val input = socket.inputStream
            val output = socket.outputStream

            val trigger = ByteArray(1)
            val read = input.read(trigger)
            if (read <= 0) {
                stats.incFdControlFailure()
                output.write(byteArrayOf(0x00))
                output.flush()
                return
            }

            val ancillary = socket.ancillaryFileDescriptors
            val receivedFd = ancillary?.firstOrNull()
            if (receivedFd == null) {
                stats.incFdControlFailure()
                output.write(byteArrayOf(0x00))
                output.flush()
                return
            }

            var rawFd = -1
            var ok = false

            try {
                rawFd = ParcelFileDescriptor.dup(receivedFd).detachFd()
                ok = protectFd(rawFd)
            } catch (_: Throwable) {
                ok = false
            } finally {
                if (rawFd >= 0) {
                    try {
                        ParcelFileDescriptor.adoptFd(rawFd).close()
                    } catch (_: Throwable) {
                    }
                }
            }

            if (ok) {
                stats.incFdControlSuccess()
                output.write(byteArrayOf(0x01))
            } else {
                stats.incFdControlFailure()
                output.write(byteArrayOf(0x00))
            }
            output.flush()
        }
    }

    private fun closeServer() {
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null

        try {
            boundSocket?.close()
        } catch (_: Throwable) {
        }
        boundSocket = null
    }

    private fun cleanupSocketPath() {
        try {
            File(socketPath).delete()
        } catch (_: Throwable) {
        }
    }
}