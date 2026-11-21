cmake_minimum_required(VERSION 3.22)
project(aether-desk VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml DBus)
find_package(KF6WindowSystem REQUIRED)
find_package(LayerShellQt REQUIRED)

qt_add_executable(aether-desk src/main.cpp ../shared/src/BackdropSampler.h)
target_include_directories(aether-desk PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../shared/src)
target_link_libraries(aether-desk PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus
    KF6::WindowSystem LayerShellQt::Interface)

# The desktop label for Folder View (see ensureInkLabels): its QML and its compiled shader.
find_program(QSB NAMES qsb6 qsb PATHS /usr/lib/qt6/bin REQUIRED)
set(FOLDERVIEW_OUT ${CMAKE_CURRENT_BINARY_DIR}/folderview)
configure_file(folderview/AetherInkLabel.qml ${FOLDERVIEW_OUT}/AetherInkLabel.qml COPYONLY)
add_custom_command(OUTPUT ${FOLDERVIEW_OUT}/ink.frag.qsb
    COMMAND ${QSB} --glsl "100 es,120,150" --hlsl 50 --msl 12 -o ${FOLDERVIEW_OUT}/ink.frag.qsb ${CMAKE_CURRENT_SOURCE_DIR}/folderview/ink.frag
    DEPENDS folderview/ink.frag)
add_custom_target(ink-shader ALL DEPENDS ${FOLDERVIEW_OUT}/ink.frag.qsb)
add_dependencies(aether-desk ink-shader)

install(TARGETS aether-desk RUNTIME DESTINATION bin)
install(FILES ${FOLDERVIEW_OUT}/AetherInkLabel.qml ${FOLDERVIEW_OUT}/ink.frag.qsb DESTINATION share/aether-desk/folderview)
target_compile_definitions(aether-desk PRIVATE
    AETHER_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    AETHER_SHARED_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../shared"
    AETHER_FOLDERVIEW_DIR="${FOLDERVIEW_OUT}")
install(DIRECTORY qml DESTINATION share/aether-desk)
install(DIRECTORY ../shared/AetherShared DESTINATION share/aether/shared)
