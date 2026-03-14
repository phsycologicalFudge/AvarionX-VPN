#include <jni.h>
#include <string>
#include <thread>
#include <atomic>

extern "C" int hev_socks5_tunnel_main_from_str(const unsigned char *config_str, int config_len, int tun_fd);
extern "C" void hev_socks5_tunnel_quit(void);

static std::thread g_thread;
static std::atomic<bool> g_running(false);

extern "C"
JNIEXPORT jint JNICALL
Java_com_colourswift_avarionxvpn_vpn_hysteria_tun_Tun2SocksBridge_nativeStart(
        JNIEnv *env,
        jobject,
        jint tunFd,
        jstring configStr) {
    if (g_running.load()) {
        return 0;
    }

    if (configStr == nullptr || tunFd < 0) {
        return -1;
    }

    const char *cfg = env->GetStringUTFChars(configStr, nullptr);
    if (!cfg) {
        return -1;
    }

    std::string config(cfg);
    env->ReleaseStringUTFChars(configStr, cfg);

    g_running.store(true);

    g_thread = std::thread([config, tunFd]() {
        hev_socks5_tunnel_main_from_str(
                reinterpret_cast<const unsigned char *>(config.data()),
                static_cast<int>(config.size()),
                tunFd
        );
        g_running.store(false);
    });

    g_thread.detach();
    return 0;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_colourswift_avarionxvpn_vpn_hysteria_tun_Tun2SocksBridge_nativeStop(
        JNIEnv *,
jobject) {
if (!g_running.load()) {
return;
}

hev_socks5_tunnel_quit();
g_running.store(false);
}