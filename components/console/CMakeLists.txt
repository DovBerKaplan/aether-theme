cmake_minimum_required(VERSION 3.22)
project(aether-console VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(KF6WindowSystem REQUIRED)
find_package(LayerShellQt REQUIRED)

qt_add_executable(aether-console
    src/main.cpp
    src/ConsoleController.h
    src/SessionStore.h
    src/SshConfig.h
    src/Discovery.h
    src/Launcher.h
    src/Metrics.h
    src/LogStream.h)
target_link_libraries(aether-console PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus
    KF6::WindowSystem LayerShellQt::Interface)
target_compile_definitions(aether-console PRIVATE
    AETHER_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    AETHER_SHARED_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../shared")

install(TARGETS aether-console RUNTIME DESTINATION bin)
install(DIRECTORY qml DESTINATION share/aether-console)
install(DIRECTORY ../shared/AetherShared DESTINATION share/aether/shared)
