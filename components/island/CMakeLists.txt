cmake_minimum_required(VERSION 3.22)
project(aether-island VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml DBus Sql Concurrent)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Runner REQUIRED)   # the search engine runs KRunner's own plugins in-process
find_package(LayerShellQt REQUIRED)

qt_add_executable(aether-island src/main.cpp ../shared/src/BackdropSampler.h src/SystemInfo.h src/MediaController.h src/PrefsGuard.h src/AudioLevels.h src/NotificationStore.h src/NetworkModel.h src/AudioModel.h src/BluetoothModel.h src/TetherController.h src/SystemPanels.h src/TileStore.h src/ConnectModel.h src/ConnectInput.h src/GlyphStore.h src/SearchEngine.h src/UsageIndex.h)
target_link_libraries(aether-island PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::DBus Qt6::Sql Qt6::Concurrent
    KF6::WindowSystem KF6::Runner LayerShellQt::Interface)
target_include_directories(aether-island PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../shared/src)

install(TARGETS aether-island RUNTIME DESTINATION bin)
target_compile_definitions(aether-island PRIVATE
    AETHER_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    AETHER_SHARED_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../shared"
    AETHER_KWIN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/kwin")
install(DIRECTORY qml kwin DESTINATION share/aether-island)
install(DIRECTORY ../shared/AetherShared DESTINATION share/aether/shared)

# The wallpaper panel's previews run the wallpapers' own shaders: bake each one next to the QML.
find_program(QSB6_EXE qsb6 REQUIRED)
set(WALLPAPER_QSB "")
foreach(s ribbons mist aurora ink dune)
    set(frag ${CMAKE_CURRENT_SOURCE_DIR}/../../plasmoids/org.aether.${s}/contents/shaders/${s}.frag)
    set(qsb ${CMAKE_CURRENT_BINARY_DIR}/wallpapers/${s}.frag.qsb)
    add_custom_command(OUTPUT ${qsb}
        COMMAND ${QSB6_EXE} --glsl "100 es,120,150" --hlsl 50 --msl 12 -o ${qsb} ${frag}
        DEPENDS ${frag}
        COMMENT "aether-island: baking ${s}.frag")
    list(APPEND WALLPAPER_QSB ${qsb})
endforeach()
add_custom_target(aether-island-wallpapers ALL DEPENDS ${WALLPAPER_QSB})
install(FILES ${WALLPAPER_QSB} DESTINATION share/aether-island/qml/assets/wallpapers)
