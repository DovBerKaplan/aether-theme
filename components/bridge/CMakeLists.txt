cmake_minimum_required(VERSION 3.22)
project(aether-bridge VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml DBus)

qt_add_qml_module(aetherbridge
    URI AetherBridge
    VERSION 1.0
    CLASS_NAME AetherBridgePlugin
    PLUGIN_TARGET aetherbridge
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/AetherBridge
    SOURCES src/Bridge.h
)
target_include_directories(aetherbridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(aetherbridge PRIVATE Qt6::Core Qt6::Qml Qt6::DBus)
