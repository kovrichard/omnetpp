//
// This file is part of an OMNeT++/OMNEST simulation test.
//
// Copyright (C) 1992-2005 Andras Varga
//
// This file is distributed WITHOUT ANY WARRANTY. See the file
// `license' for details on this and other legal matters.
//

#include <omnetpp.h>
#include <vector>
#include "stresssource.h"
#include "stress_m.h"

Define_Module(StressSource);

std::vector<StressSource *> sources;

StressSource::StressSource()
{
	timer = new cMessage("Source timer");
	sources.push_back(this);
}

StressSource::~StressSource()
{
	ev << "Cancelling and deleting self message: "  << timer << "\n";;
	cancelAndDelete(timer);
}

void StressSource::initialize()
{
	ev << "Sending self message for the first time: "  << timer << "\n";;
	scheduleAt(par("serviceTime"), timer);
}

void StressSource::handleMessage(cMessage *msg)
{
	if (msg == timer)
		// either send our own message or the message will be generated by the module actually sending it out
		msg = uniform(0, 1) < 0.5 ? generateMessage() : NULL;
	else {
		ev << "Cancelling self message due to received direct message: " << timer << "\n";;
		cancelEvent(timer);
	}

	// randomly call a source (including ourselve)
	sources.at(intrand(sources.size()))->sendOut(msg);

    // make sure our timer is always active
    if (!timer->isScheduled()) {
        ev << "Reusing self message: " << timer << "\n";
        scheduleAt(simTime() + par("serviceTime"), timer);
    }
}

void StressSource::sendOut(cMessage *msg)
{
	bool otherModule = this != simulation.contextModule();
	Enter_Method("sendOut method entered");

	// send our own message if did not get one
	if (!msg) {
		msg = generateMessage();
        msg->setName("Source's own");
    }
    else
        msg->setName("Other source's");

	take(msg);
	send(msg, "out", intrand(gateSize("out")));

	if (otherModule) {
		// cancel context module's timer
		ev << "Cancelling self message due to method call: " << timer << "\n";;
		cancelEvent(timer);
	}

	// make sure context module's timer is always active
	ev << "Reusing self message: " << timer << "\n";
	scheduleAt(simTime() + par("serviceTime"), timer);
}

cMessage *StressSource::generateMessage()
{
	bubble("Generating new message");

	cMessage *msg = new StressPacket();
	msg->setLength((long)exponential(par("messageLength")));

	return msg;
}
