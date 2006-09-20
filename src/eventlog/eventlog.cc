//=========================================================================
//  EVENTLOG.CC - part of
//                  OMNeT++/OMNEST
//           Discrete System Simulation in C++
//
//=========================================================================

/*--------------------------------------------------------------*
  Copyright (C) 1992-2006 Andras Varga

  This file is distributed WITHOUT ANY WARRANTY. See the file
  `license' for details on this and other legal matters.
*--------------------------------------------------------------*/

#include <assert.h>
#include "filereader.h"
#include "stringpool.h"
#include "eventlog.h"

StringPool eventLogStringPool;

EventLog::EventLog(FileReader *reader) : EventLogIndex(reader)
{
    parseInitializationLogEntries();
}

EventLog::~EventLog()
{
    for (EventLogEntryList::iterator it = initializationLogEntries.begin(); it != initializationLogEntries.end(); it++)
    {
        delete *it;
    }

    for (EventNumberToEventMap::iterator it = eventNumberToEventMap.begin(); it != eventNumberToEventMap.end(); it++)
    {
        delete it->second;
    }
}

void EventLog::parseInitializationLogEntries()
{
    long firstOffset = getOffsetForEventNumber(0);
    reader->seekTo(0);

    do
    {
        char *line = reader->readLine();

        if (!line)
            break;

        EventLogEntry *eventLogEntry = EventLogEntry::parseEntry(line);

        if (eventLogEntry && !dynamic_cast<EventEntry *>(eventLogEntry))
            initializationLogEntries.push_back(eventLogEntry);
    }
    while (reader->lineStartOffset() < firstOffset);
}

void EventLog::parse(long fromEventNumber, long toEventNumber)
{
    long fromOffset = getOffsetForEventNumber(fromEventNumber);
    long toOffset = getOffsetForEventNumber(toEventNumber);
    long offset = fromOffset;

    if (fromOffset == -1 || toOffset == -1)
        throw new Exception("Could not find requested events");

    while (offset <= toOffset)
    {
        Event *event = new Event(this);
        offset = event->parse(reader, offset);
        cacheEvent(event);
    }
}

void EventLog::printInitializationLogEntries(FILE *file)
{
    for (EventLogEntryList::iterator it = initializationLogEntries.begin(); it != initializationLogEntries.end(); it++)
    {
        (*it)->print(file);
    }
}

void EventLog::printEvents(FILE *file)
{
    for (EventNumberToEventMap::iterator it = eventNumberToEventMap.begin(); it != eventNumberToEventMap.end(); it++)
    {
        it->second->print(file);
    }
}

void EventLog::print(FILE *file)
{
    printInitializationLogEntries(file);
    printEvents(file);
}

Event *EventLog::getEvent(long eventNumber)
{
    if (eventNumber < 0)
    {
        throw new Exception("Event number must be >= 0, %d", eventNumber);
    }

    EventNumberToEventMap::iterator it = eventNumberToEventMap.find(eventNumber);

    if (it != eventNumberToEventMap.end())
        return it->second;
    else
    {
        long offset = getOffsetForEventNumber(eventNumber);

        if (offset == -1)
            return NULL;
        else
            return getEventForOffset(offset);
    }
}

Event *EventLog::getEventForOffset(long offset)
{
    if (offset < 0)
        throw new Exception("Offset number must be >= 0, %d", offset);

    OffsetToEventMap::iterator it = offsetToEventMap.find(offset);

    if (it != offsetToEventMap.end())
        return it->second;
    else
    {
        Event *event = new Event(this);
        event->parse(reader, offset);
        cacheEvent(event);
        return event;
    }
}

void EventLog::cacheEvent(Event *event)
{
    eventNumberToEventMap[event->getEventNumber()] = event;
    offsetToEventMap[event->getBeginOffset()] = event;
}
