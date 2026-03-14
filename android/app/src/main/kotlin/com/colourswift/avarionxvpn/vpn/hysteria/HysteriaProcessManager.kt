package com.colourswift.avarionxvpn.vpn.hysteria

import android.content.Context
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.Future

class HysteriaProcessManager(
    private val context: Context,
    private val stats: HysteriaVpnStats
) {
    private val ioExecutor = Executors.newCachedThreadPool()

    private var process: Process? = null
    private var stdoutFuture: Future<*>? = null
    private var stderrFuture: Future<*>? = null

    private val socksHost = "127.0.0.1"
    private val socksPort = 1080

    fun start(configFile: File): HysteriaProcessHandle {
        stop()

        val binary = HysteriaBinary.installIfMissing(context)
        HyLog.write(context, "binary path=${binary.absolutePath}")
        HyLog.write(context, "config path=${configFile.absolutePath}")

        process = ProcessBuilder(
            binary.absolutePath,
            "-c",
            configFile.absolutePath
        ).start()

        HyLog.write(context, "ProcessBuilder started")

        stdoutFuture = ioExecutor.submit {
            try {
                process?.inputStream?.bufferedReader()?.useLines { lines ->
                    lines.forEach { line ->
                        stats.appendProcessLog(line)
                        HyLog.write(context, "stdout: $line")
                    }
                }
            } catch (t: Throwable) {
                HyLog.write(context, "stdout reader error=${t.message ?: "unknown"}")
            }
        }

        stderrFuture = ioExecutor.submit {
            try {
                process?.errorStream?.bufferedReader()?.useLines { lines ->
                    lines.forEach { line ->
                        stats.appendProcessLog(line)
                        HyLog.write(context, "stderr: $line")
                    }
                }
            } catch (t: Throwable) {
                HyLog.write(context, "stderr reader error=${t.message ?: "unknown"}")
            }
        }

        stats.setHysteriaAlive(true)

        return HysteriaProcessHandle(
            pid = null,
            socksHost = socksHost,
            socksPort = socksPort
        )
    }

    fun stop() {
        HyLog.write(context, "process stop called")

        try {
            process?.destroy()
        } catch (_: Throwable) {
        }

        try {
            process?.destroyForcibly()
        } catch (_: Throwable) {
        }

        try {
            stdoutFuture?.cancel(true)
        } catch (_: Throwable) {
        }

        try {
            stderrFuture?.cancel(true)
        } catch (_: Throwable) {
        }

        process = null
        stdoutFuture = null
        stderrFuture = null
        stats.setHysteriaAlive(false)
    }

    fun isAlive(): Boolean {
        return process?.isAlive == true
    }

    fun localSocksEndpoint(): InetSocketAddress {
        return InetSocketAddress(socksHost, socksPort)
    }

    fun binaryFile(): File {
        return File(context.filesDir, "hysteria")
    }
}

data class HysteriaProcessHandle(
    val pid: Long?,
    val socksHost: String,
    val socksPort: Int
)