#include "event_manager.h"
#include <QFile>
#include <QDataStream>
#include <QTextStream>
#include <QDir>
#include <QDebug>
#include <QDateTime>
#include <iostream>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <signal.h>
#include <thread>
#include <chrono>

// Set to 1 to use plaintext format, 0 to use binary format
#define USE_PLAINTEXT_FORMAT 1

// Magic header for binary data file
const char MAGIC_HEADER[] = "INPUT";
const int MAGIC_SIZE = 5;
const int FILE_VERSION = 1;

static bool g_stopRequested = false;

// Signal handler to capture Ctrl+C and gracefully terminate loops
static void signalHandler(int signum) {
    if (signum == SIGINT || signum == SIGTERM) {
        g_stopRequested = true;
    }
}

EventManager::EventManager(QObject *parent) : QObject(parent), stopRequested(false)
{
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
}

EventManager::~EventManager()
{
}

void EventManager::scanDevices()
{
    QDir dir("/dev/input");
    QStringList filters;
    filters << "event*";
    dir.setNameFilters(filters);
    dir.setFilter(QDir::System | QDir::NoDotAndDotDot);
    
    QFileInfoList list = dir.entryInfoList();
    if (list.isEmpty()) {
        std::cerr << "No event devices found in /dev/input" << std::endl;
        return;
    }

    std::cout << "Available input devices:" << std::endl;
    for (int i = 0; i < list.size(); ++i) {
        QFileInfo fileInfo = list.at(i);
        QString devPath = fileInfo.absoluteFilePath();
        
        int fd = open(devPath.toStdString().c_str(), O_RDONLY);
        if (fd < 0) {
            std::cout << "  [" << (i + 1) << "] " << devPath.toStdString() << " - <Permission Denied>" << std::endl;
            continue;
        }

        char name[256];
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), &name) < 1) {
            name[0] = '\0';
        }
        close(fd);

        std::cout << "  [" << (i + 1) << "] " << devPath.toStdString() << "  -  " << name << std::endl;
    }
}

bool EventManager::recordEvents(const QString &devicePath, const QString &outputPath)
{
    g_stopRequested = false;

    int fd = open(devicePath.toStdString().c_str(), O_RDONLY);
    if (fd < 0) {
        std::cerr << "Failed to open device: " << devicePath.toStdString() << " " << strerror(errno) << std::endl;
        return false;
    }

    char devName[256];
    if (ioctl(fd, EVIOCGNAME(sizeof(devName) - 1), &devName) < 1) {
        devName[0] = '\0';
    }

    QFile outFile(outputPath);
    if (!outFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        std::cerr << "Failed to open output file: " << outputPath.toStdString() << std::endl;
        close(fd);
        return false;
    }

#if USE_PLAINTEXT_FORMAT
    QTextStream out(&outFile);
    out << "# Magic: " << MAGIC_HEADER << "\n";
    out << "# Version: " << FILE_VERSION << "\n";
    out << "# DevicePath: " << devicePath << "\n";
    out << "# DeviceName: " << QString(devName) << "\n";
    out.flush();
#else
    QDataStream out(&outFile);
    out.setVersion(QDataStream::Qt_5_0);

    // Write file header
    out.writeRawData(MAGIC_HEADER, MAGIC_SIZE);
    out << (qint32)FILE_VERSION;
    out << devicePath;
    out << QString(devName);
#endif
    
    std::cout << "==========================================" << std::endl;
    std::cout << "         Starts Recording Events" << std::endl;
    std::cout << "==========================================" << std::endl;
    std::cout << "Device: " << devicePath.toStdString() << " (" << devName << ")" << std::endl;
    std::cout << "Output: " << outputPath.toStdString() << std::endl;
    std::cout << ">>> Operate the device, press Ctrl+C to stop recording <<<" << std::endl;

    struct input_event ev;
    long eventCount = 0;

    // We can use a non-blocking read or select/poll, but a blocking read is fine
    // since we use signals to interrupt it. However, blocking read might not interrupt
    // smoothly on all systems. Let's set O_NONBLOCK and use select.
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    fd_set readfds;
    struct timeval tv;

    while (!g_stopRequested) {
        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        tv.tv_sec = 0;
        tv.tv_usec = 100000; // 100ms timeout

        int ret = select(fd + 1, &readfds, NULL, NULL, &tv);
        if (ret > 0) {
            if (FD_ISSET(fd, &readfds)) {
                ssize_t n = read(fd, &ev, sizeof(ev));
                if (n == (ssize_t)sizeof(ev)) {
#if USE_PLAINTEXT_FORMAT
                    char buf[256];
                    snprintf(buf, sizeof(buf), "[%ld.%06ld] %04x %04x %08x\n", 
                             (long)ev.time.tv_sec, (long)ev.time.tv_usec, ev.type, ev.code, ev.value);
                    outFile.write(buf);
                    outFile.flush();
#else
                    out.writeRawData((const char*)&ev, sizeof(ev));
#endif
                    eventCount++;
                } else if (n < 0 && errno != EAGAIN) {
                    std::cerr << "Read error: " << strerror(errno) << std::endl;
                    break;
                }
            }
        } else if (ret < 0 && errno != EINTR) {
            std::cerr << "Select error: " << strerror(errno) << std::endl;
            break;
        }
    }

    outFile.close();
    close(fd);

    std::cout << "\n==========================================" << std::endl;
    std::cout << "           Recording Completed" << std::endl;
    std::cout << "==========================================" << std::endl;
    std::cout << "File: " << outputPath.toStdString() << std::endl;
    std::cout << "Event Count: " << eventCount << std::endl;

    return true;
}

bool EventManager::playEvents(const QString &inputPath, const QString &deviceOverridePath, int loopCount, double speed)
{
    g_stopRequested = false;

    QFile inFile(inputPath);
    if (!inFile.open(QIODevice::ReadOnly)) {
        std::cerr << "Failed to open input file: " << inputPath.toStdString() << std::endl;
        return false;
    }

    QString origDevicePath;
    QString origDevName;

#if USE_PLAINTEXT_FORMAT
    QTextStream in(&inFile);
    QString magicLine = in.readLine();
    if (!magicLine.startsWith(QString("# Magic: %1").arg(MAGIC_HEADER))) {
        std::cerr << "Invalid file format: Magic header mismatch" << std::endl;
        return false;
    }
    QString versionLine = in.readLine();
    QString devicePathLine = in.readLine();
    QString deviceNameLine = in.readLine();
    
    origDevicePath = devicePathLine.mid(14).trimmed();
    origDevName = deviceNameLine.mid(14).trimmed();
#else
    QDataStream in(&inFile);
    in.setVersion(QDataStream::Qt_5_0);

    char magic[MAGIC_SIZE];
    if (in.readRawData(magic, MAGIC_SIZE) != MAGIC_SIZE || qstrncmp(magic, MAGIC_HEADER, MAGIC_SIZE) != 0) {
        std::cerr << "Invalid file format: Magic header mismatch" << std::endl;
        return false;
    }

    qint32 version;
    in >> version;
    if (version != FILE_VERSION) {
        std::cerr << "Unsupported file version: " << version << std::endl;
        return false;
    }

    in >> origDevicePath >> origDevName;
#endif

    QString playDevice = deviceOverridePath.isEmpty() ? origDevicePath : deviceOverridePath;

    if (playDevice.isEmpty()) {
        std::cerr << "No device specified to playback." << std::endl;
        return false;
    }

    qint64 startPos = inFile.pos();

    // Probe the file to count events
    long totalEvents = 0;
#if USE_PLAINTEXT_FORMAT
    while (!in.atEnd()) {
        if (!in.readLine().isEmpty()) totalEvents++;
    }
#else
    qint64 remainingSize = inFile.size() - startPos;
    if (remainingSize % sizeof(struct input_event) != 0) {
        std::cerr << "Warning: File size may be corrupted (not a multiple of input_event size)." << std::endl;
    }
    totalEvents = remainingSize / sizeof(struct input_event);
#endif

    if (totalEvents == 0) {
        std::cerr << "No events in file." << std::endl;
        return false;
    }

    std::cout << "==========================================" << std::endl;
    std::cout << "         Starts Playing Events" << std::endl;
    std::cout << "==========================================" << std::endl;
    std::cout << "Device: " << playDevice.toStdString() << std::endl;
    std::cout << "File: " << inputPath.toStdString() << std::endl;
    std::cout << "Speed: " << speed << "x" << std::endl;
    std::cout << "Loops: " << (loopCount == 0 ? "Infinite" : QString::number(loopCount).toStdString()) << std::endl;
    std::cout << "Event Count: " << totalEvents << std::endl;
    std::cout << ">>> Press Ctrl+C to stop playback <<<" << std::endl;

    int fd = open(playDevice.toStdString().c_str(), O_WRONLY);
    if (fd < 0) {
        std::cerr << "Failed to open playback device: " << playDevice.toStdString() << " " << strerror(errno) << std::endl;
        return false;
    }

    int currentLoop = 0;
    while (!g_stopRequested) {
        currentLoop++;
        if (loopCount > 0 && currentLoop > loopCount) {
            break;
        }

        if (loopCount == 0) {
            std::cout << "=== Loop " << currentLoop << " (Infinite) ===" << std::endl;
        } else if (loopCount > 1) {
            std::cout << "=== Loop " << currentLoop << " / " << loopCount << " ===" << std::endl;
        }

        inFile.seek(startPos); // Reset to start of events
#if USE_PLAINTEXT_FORMAT
        in.seek(startPos);
#endif

        struct input_event ev;
        bool firstEvent = true;
        struct timeval firstEventTime;
        struct timeval playbackStartTime;

#if USE_PLAINTEXT_FORMAT
        QString line;
        while (!g_stopRequested && !in.atEnd()) {
            line = in.readLine();
            if (line.isEmpty()) continue;
            
            long sec = 0, usec = 0;
            unsigned int type = 0, code = 0, value = 0;
            if (sscanf(line.toStdString().c_str(), "[%ld.%ld] %x %x %x", &sec, &usec, &type, &code, &value) != 5) {
                continue;
            }
            ev.time.tv_sec = sec;
            ev.time.tv_usec = usec;
            ev.type = type;
            ev.code = code;
            ev.value = value;
#else
        while (!g_stopRequested && inFile.read((char*)&ev, sizeof(ev)) == sizeof(ev)) {
#endif
            if (firstEvent) {
                firstEvent = false;
                firstEventTime = ev.time;
                gettimeofday(&playbackStartTime, NULL);
            } else {
                // Calculate elapsed time in event record
                double eventElapsedSec = (ev.time.tv_sec - firstEventTime.tv_sec) + 
                                         (ev.time.tv_usec - firstEventTime.tv_usec) / 1000000.0;
                
                // Adjust for playback speed
                eventElapsedSec /= speed;

                // Calculate current playback elapsed time
                struct timeval now;
                gettimeofday(&now, NULL);
                double currentElapsedSec = (now.tv_sec - playbackStartTime.tv_sec) + 
                                           (now.tv_usec - playbackStartTime.tv_usec) / 1000000.0;

                double sleepTimeSec = eventElapsedSec - currentElapsedSec;

                if (sleepTimeSec > 0.0001) { // 100 microseconds threshold
                    long microseconds = (long)(sleepTimeSec * 1000000);
                    std::this_thread::sleep_for(std::chrono::microseconds(microseconds));
                }
            }

            // Sync latest time directly into the event struct for the kernel?
            // Usually the time is ignored by evdev write or set by the kernel
            gettimeofday(&ev.time, NULL);
            
            ssize_t ret = write(fd, &ev, sizeof(ev));
            if (ret < (ssize_t)sizeof(ev)) {
                std::cerr << "Write event failed: " << strerror(errno) << std::endl;
                break;
            }
        }

        if (!g_stopRequested && (loopCount == 0 || currentLoop < loopCount)) {
            std::cout << "Inter-loop delay 1s..." << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }

    close(fd);

    std::cout << "\n==========================================" << std::endl;
    std::cout << "           Playback Completed" << std::endl;
    std::cout << "==========================================" << std::endl;

    return true;
}
