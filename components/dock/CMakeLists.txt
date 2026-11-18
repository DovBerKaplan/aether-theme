cmake_minimum_required(VERSION 3.22)
project(aether-dock VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(KF6WindowSystem REQUIRED)
find_package(LayerShellQt REQUIRED)

qt_add_executable(aether-dock src/main.cpp ../shared/src/BackdropSampler.h)
target_include_directories(aether-dock PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../shared/src)
target_link_libraries(aether-dock PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus
    KF6::WindowSystem LayerShellQt::Interface)

install(TARGETS aether-dock RUNTIME DESTINATION bin)
target_compile_definitions(aether-dock PRIVATE
    AETHER_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    AETHER_SHARED_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../shared")
install(DIRECTORY qml DESTINATION share/aether-dock)
install(DIRECTORY ../shared/AetherShared DESTINATION share/aether/shared)
install(FILES org.aether.dock.desktop.in DESTINATION share/aether-dock)
