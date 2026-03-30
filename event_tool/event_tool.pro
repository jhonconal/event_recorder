TEMPLATE = app
CONFIG += console c++11
CONFIG -= app_bundle
CONFIG += core 

# Although we don't need GUI, we use QCoreApplication and other core Qt classes.
QT += core
QT -= gui

TARGET = event_tool

SOURCES += \
    main.cpp \
    event_manager.cpp

HEADERS += \
    event_manager.h

# Enable C++11
QMAKE_CXXFLAGS += -std=c++11
