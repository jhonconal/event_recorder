#ifndef EVENT_MANAGER_H
#define EVENT_MANAGER_H

#include <QString>
#include <QObject>

class EventManager : public QObject
{
    Q_OBJECT

public:
    explicit EventManager(QObject *parent = nullptr);
    ~EventManager();

    // Scan available input devices and print them to stdout
    static void scanDevices();

    // Start recording input events from a device to a output file
    bool recordEvents(const QString &devicePath, const QString &outputPath);

    // Playback events from a recorded file to a specified device (or origin device if empty)
    bool playEvents(const QString &inputPath, const QString &deviceOverridePath, int loopCount = 1, double speed = 1.0);

private:
    bool stopRequested;
};

#endif // EVENT_MANAGER_H
