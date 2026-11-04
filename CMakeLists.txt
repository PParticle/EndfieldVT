cmake_minimum_required(VERSION 3.21)
project(EndfieldVT LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(EndfieldVT WIN32 src/main.cpp src/bridgereader.cpp src/gamewindow.cpp)

set_source_files_properties(qml/Theme.qml qml/Triggers.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(EndfieldVT
    URI EndfieldVT
    SOURCES src/bridgereader.h src/configfile.h src/gamewindow.h src/windowaspectratio.h
    QML_FILES
        qml/Main.qml
        qml/PreviewWindow.qml
        qml/WidgetEditor.qml
        qml/Theme.qml
        qml/AppWindow.qml
        qml/TitleBar.qml
        qml/TitleAction.qml
        qml/Sidebar.qml
        qml/PageFrame.qml
        qml/NewPage.qml
        qml/DebugPage.qml
        qml/StatusBar.qml
        qml/KindIcon.qml
        qml/ThemeTextField.qml
        qml/NumberField.qml
        qml/ThemeComboBox.qml
        qml/ThemeSlider.qml
        qml/ColorField.qml
        qml/ColorPicker.qml
        qml/FlatButton.qml
        qml/Triggers.qml
        qml/TriggerCard.qml
        qml/ConditionFields.qml
        qml/ControlView.qml
        qml/OverlayWindow.qml
)

# EndfieldDataBridge's public headers: its repository sits next to this one,
# or set EFB_INCLUDE_DIR.
set(EFB_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/../EndfieldDataBridge/include" CACHE PATH "EndfieldDataBridge include directory")
if(NOT EXISTS "${EFB_INCLUDE_DIR}/endfield_bridge_reader.h")
    message(FATAL_ERROR "endfield_bridge_reader.h not found in ${EFB_INCLUDE_DIR}; set EFB_INCLUDE_DIR")
endif()
target_include_directories(EndfieldVT PRIVATE src "${EFB_INCLUDE_DIR}")
target_link_libraries(EndfieldVT PRIVATE Qt6::Quick)
if(WIN32)
    target_link_libraries(EndfieldVT PRIVATE comctl32)
endif()
if(MSVC)
    target_compile_options(EndfieldVT PRIVATE /W4 /utf-8 /permissive-)
endif()
set_target_properties(EndfieldVT PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin
)

# The C++ that qmlcachegen compiles our QML into trips C4702 ("unreachable
# code") inside Qt's own headers. Silence it there only; our sources keep /W4.
if(MSVC)
    cmake_language(DEFER CALL _efvt_quiet_qmlcache)
    function(_efvt_quiet_qmlcache)
        get_target_property(sources EndfieldVT SOURCES)
        foreach(source IN LISTS sources)
            if(source MATCHES "/\\.rcc/qmlcache/")
                set_source_files_properties(${source} TARGET_DIRECTORY EndfieldVT
                    PROPERTIES COMPILE_OPTIONS /wd4702)
            endif()
        endforeach()
    endfunction()
endif()
