cmake_minimum_required(VERSION 3.22.1)

project(cs_tun2socks)

set(HEV_ROOT "${CMAKE_SOURCE_DIR}/../jni/hev-socks5-tunnel")

add_compile_definitions(
        ANDROID
        ENABLE_LIBRARY
        FD_SET_DEFINED
        SOCKLEN_T_DEFINED
        LWIP_DONT_PROVIDE_BYTEORDER_FUNCTIONS
        COMMIT_ID="android"
)

file(GLOB_RECURSE HEV_SRC
        "${HEV_ROOT}/src/*.c"
)

list(FILTER HEV_SRC EXCLUDE REGEX ".*/hev-jni\\.c$")
list(FILTER HEV_SRC EXCLUDE REGEX ".*/hev-tunnel-macos\\.c$")
list(FILTER HEV_SRC EXCLUDE REGEX ".*/hev-tunnel-freebsd\\.c$")
list(FILTER HEV_SRC EXCLUDE REGEX ".*/hev-tunnel-netbsd\\.c$")
list(FILTER HEV_SRC EXCLUDE REGEX ".*/hev-tunnel-windows\\.c$")

add_library(cs_tun2socks SHARED
        tun2socks_jni.cpp
        ${HEV_SRC}
)

target_include_directories(cs_tun2socks PRIVATE
        ${CMAKE_SOURCE_DIR}/lwip_android_override
        ${HEV_ROOT}/include
        ${HEV_ROOT}/src
        ${HEV_ROOT}/src/misc
        ${HEV_ROOT}/src/core/include
        ${HEV_ROOT}/src/core/src
        ${HEV_ROOT}/third-part/hev-task-system/include
        ${HEV_ROOT}/third-part/hev-task-system/src/lib
        ${HEV_ROOT}/third-part/lwip/src/include
        ${HEV_ROOT}/third-part/lwip/src/ports/include
        ${HEV_ROOT}/third-part/lwip/custom
        ${HEV_ROOT}/third-part/yaml/include
)

find_library(log-lib log)

add_library(hev-task-system STATIC IMPORTED)
set_target_properties(hev-task-system PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/../obj/local/${ANDROID_ABI}/libhev-task-system.a"
)

add_library(lwip STATIC IMPORTED)
set_target_properties(lwip PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/../obj/local/${ANDROID_ABI}/liblwip.a"
)

add_library(yaml STATIC IMPORTED)
set_target_properties(yaml PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/../obj/local/${ANDROID_ABI}/libyaml.a"
)

target_link_libraries(
        cs_tun2socks
        hev-task-system
        lwip
        yaml
        ${log-lib}
        atomic
        m
)