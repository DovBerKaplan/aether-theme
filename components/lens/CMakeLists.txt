cmake_minimum_required(VERSION 3.22)
project(aether-lens VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml DBus Network)
find_package(LayerShellQt REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(ATSPI REQUIRED IMPORTED_TARGET atspi-2 gobject-2.0)

qt_add_executable(aether-lens src/main.cpp src/LensController.cpp src/LensActions.cpp src/ObjectDetect.cpp src/A11y.cpp src/Segmenter.cpp)
target_link_libraries(aether-lens PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus Qt6::Network
    LayerShellQt::Interface PkgConfig::ATSPI)
target_compile_definitions(aether-lens PRIVATE
    AETHER_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    AETHER_SEGMENTER_DIR="${CMAKE_CURRENT_SOURCE_DIR}/segmenter"
    AETHER_SHARED_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../shared")

install(TARGETS aether-lens RUNTIME DESTINATION bin)
install(DIRECTORY qml DESTINATION share/aether-lens)
install(DIRECTORY segmenter DESTINATION share/aether-lens)
install(DIRECTORY ../shared/AetherShared DESTINATION share/aether/shared)
install(FILES org.aether.lens.desktop.in DESTINATION share/aether-lens)
