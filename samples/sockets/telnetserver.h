//
// This file is part of an OMNeT++/OMNEST simulation example.
//
// Copyright (C) 1992-2005 Andras Varga
//
// This file is distributed WITHOUT ANY WARRANTY. See the file
// `license' for details on this and other legal matters.
//


#ifndef __FIFO_H
#define __FIFO_H

#include "queuebase.h"

/**
 * Simple model of an Telnet server.
 */
class TelnetServer : public QueueBase
{
  public:
    Module_Class_Members(TelnetServer,QueueBase,0);

    virtual simtime_t startService(cMessage *msg);
    virtual void endService(cMessage *msg);
    virtual std::string processChars(const char *chars);
};

#endif



