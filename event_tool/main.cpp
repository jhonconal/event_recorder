#include <QCoreApplication>
#include <QCommandLineParser>
#include <QCommandLineOption>
#include <QDateTime>
#include <QStringList>
#include <QFileInfo>
#include <QDir>
#include <iostream>
#include "event_manager.h"

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("cmdtool");
    QCoreApplication::setApplicationVersion("1.0");

    QCommandLineParser parser;
    parser.setApplicationDescription("Linux Input Event Recorder and Playback Tool");
    parser.addHelpOption();
    parser.addVersionOption();

    parser.addPositionalArgument("command", "Command to execute: 'record', 'play', or 'list'.");

    QCommandLineOption deviceOption(QStringList() << "d" << "device",
            "Specify input device (e.g. /dev/input/event2). Used for recording; overrides device for playback.",
            "device");
    parser.addOption(deviceOption);

    QCommandLineOption outputOption(QStringList() << "o" << "output",
            "Output file path for recording.",
            "file");
    parser.addOption(outputOption);

    QCommandLineOption inputOption(QStringList() << "i" << "input",
            "Input file path for playback.",
            "file");
    parser.addOption(inputOption);

    QCommandLineOption loopOption(QStringList() << "n" << "loop",
            "Number of times to loop playback (0 = infinite).",
            "count", "1");
    parser.addOption(loopOption);

    QCommandLineOption speedOption(QStringList() << "s" << "speed",
            "Playback speed multiplier (e.g. 2.0 for double speed).",
            "speed", "1.0");
    parser.addOption(speedOption);

    parser.process(app);

    const QStringList args = parser.positionalArguments();
    if (args.isEmpty()) {
        parser.showHelp(1);
    }

    QString command = args.first();
    EventManager manager;

    if (command == "list") {
        manager.scanDevices();
        return 0;
    } 
    else if (command == "record") {
        QString dev = parser.value(deviceOption);
        if (dev.isEmpty()) {
            std::cerr << "Error: You must specify a device using -d /dev/input/eventX for recording." << std::endl;
            return 1;
        }
        
        QString out = parser.value(outputOption);
        if (out.isEmpty()) {
            out = "recordings/recorded_events_" + QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss") + ".bin";
            std::cout << "Output file not specified. Using default: " << out.toStdString() << std::endl;
        }

        // ensure directory exists
        QFileInfo outInfo(out);
        QDir().mkpath(outInfo.absolutePath());

        if (!manager.recordEvents(dev, out)) {
            return 1;
        }
    } 
    else if (command == "play") {
        QString in = parser.value(inputOption);
        if (in.isEmpty()) {
            std::cerr << "Error: You must specify an input file using -i parameter for playback." << std::endl;
            return 1;
        }

        QString dev = parser.value(deviceOption);
        int loops = parser.value(loopOption).toInt();
        double speed = parser.value(speedOption).toDouble();
        if (speed <= 0.0) speed = 1.0;

        if (!manager.playEvents(in, dev, loops, speed)) {
            return 1;
        }
    } 
    else {
        std::cerr << "Unknown command: " << command.toStdString() << std::endl;
        parser.showHelp(1);
    }

    return 0;
}
