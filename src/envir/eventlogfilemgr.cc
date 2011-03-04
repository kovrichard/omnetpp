//==========================================================================
//  EVENTLOGFILEMGR.CC - part of
//                     OMNeT++/OMNEST
//            Discrete System Simulation in C++
//
//  Author: Andras Varga
//
//==========================================================================

/*--------------------------------------------------------------*
  Copyright (C) 1992-2008 Andras Varga
  Copyright (C) 2006-2008 OpenSim Ltd.

  This file is distributed WITHOUT ANY WARRANTY. See the file
  `license' for details on this and other legal matters.
*--------------------------------------------------------------*/

#include <algorithm>
#include "opp_ctype.h"
#include "commonutil.h"  //vsnprintf
#include "eventlogfilemgr.h"
#include "eventlogwriter.h"
#include "cconfigoption.h"
#include "fileutil.h"
#include "cconfiguration.h"
#include "envirbase.h"
#include "cmodule.h"
#include "cmessage.h"
#include "cgate.h"
#include "cchannel.h"
#include "csimplemodule.h"
#include "ccompoundmodule.h"
#include "cdisplaystring.h"
#include "cclassdescriptor.h"

USING_NAMESPACE


Register_PerRunConfigOption(CFGID_EVENTLOG_FILE, "eventlog-file", CFG_FILENAME, "${resultdir}/${configname}-${runnumber}.elog", "Name of the eventlog file to generate.");
Register_PerRunConfigOption(CFGID_EVENTLOG_MESSAGE_DETAIL_PATTERN, "eventlog-message-detail-pattern", CFG_CUSTOM, NULL,
        "A list of patterns separated by '|' character which will be used to write "
        "message detail information into the eventlog for each message sent during "
        "the simulation. The message detail will be presented in the sequence chart "
        "tool. Each pattern starts with an object pattern optionally followed by ':' "
        "character and a comma separated list of field patterns. In both "
        "patterns and/or/not/* and various field match expressions can be used. "
        "The object pattern matches to class name, the field pattern matches to field name by default.\n"
        "  EVENTLOG-MESSAGE-DETAIL-PATTERN := ( DETAIL-PATTERN '|' )* DETAIL_PATTERN\n"
        "  DETAIL-PATTERN := OBJECT-PATTERN [ ':' FIELD-PATTERNS ]\n"
        "  OBJECT-PATTERN := MATCH-EXPRESSION\n"
        "  FIELD-PATTERNS := ( FIELD-PATTERN ',' )* FIELD_PATTERN\n"
        "  FIELD-PATTERN := MATCH-EXPRESSION\n"
        "Examples (enter them without quotes):\n"
        "  \"*\": captures all fields of all messages\n"
        "  \"*Frame:*Address,*Id\": captures all fields named somethingAddress and somethingId from messages of any class named somethingFrame\n"
        "  \"MyMessage:declaredOn(MyMessage)\": captures instances of MyMessage recording the fields declared on the MyMessage class\n"
        "  \"*:(not declaredOn(cMessage) and not declaredOn(cNamedObject) and not declaredOn(cObject))\": records user-defined fields from all messages");
Register_PerRunConfigOption(CFGID_EVENTLOG_RECORDING_INTERVALS, "eventlog-recording-intervals", CFG_CUSTOM, NULL, "Simulation time interval(s) when events should be recorded. Syntax: [<from>]..[<to>],... That is, both start and end of an interval are optional, and intervals are separated by comma. Example: ..10.2, 22.2..100, 233.3..");
Register_PerObjectConfigOption(CFGID_MODULE_EVENTLOG_RECORDING, "module-eventlog-recording", CFG_BOOL, "true", "Enables recording events on a per module basis. This is meaningful for simple modules only. \nExample:\n **.router[10..20].**.module-eventlog-recording = true\n **.module-eventlog-recording = false");

static va_list empty_va;

static bool compareMessageEventNumbers(cMessage *message1, cMessage *message2)
{
    return message1->getPreviousEventNumber() < message2->getPreviousEventNumber();
}

static ObjectPrinterRecursionControl recurseIntoMessageFields(void *object, cClassDescriptor *descriptor, int fieldIndex, void *fieldValue, void **parents, int level) {
    const char* propertyValue = descriptor->getFieldProperty(object, fieldIndex, "eventlog");

    if (propertyValue) {
        if (!strcmp(propertyValue, "skip"))
            return SKIP;
        else if (!strcmp(propertyValue, "fullName"))
            return FULL_NAME;
        else if (!strcmp(propertyValue, "fullPath"))
            return FULL_PATH;
    }

    bool isCObject = descriptor->getFieldIsCObject(object, fieldIndex);
    if (!isCObject)
        return RECURSE;
    else {
        if (!fieldValue)
            return RECURSE;
        else {
            cArray *array = dynamic_cast<cArray *>((cObject *)fieldValue);
            return !array || array->size() != 0 ? RECURSE : SKIP;
        }
    }
}

EventlogFileManager::EventlogFileManager()
{
    feventlog = NULL;
    objectPrinter = NULL;
    recordingIntervals = NULL;
    keyframeBlockSize = 1000;
    clearInternalState();
}

EventlogFileManager::~EventlogFileManager()
{
    delete objectPrinter;
    delete recordingIntervals;
}

void EventlogFileManager::clearInternalState()
{
    eventNumber = -1;
    entryIndex = -1;
    previousKeyframeFileOffset = -1;
    isEventLogRecordingEnabled = true;
    isIntervalEventLogRecordingEnabled = true;
    isModuleEventLogRecordingEnabled = true;
    consequenceLookaheadLimits.clear();
    eventNumberToSimulationStateEventLogEntryRanges.clear();
    moduleIdToModuleDisplayStringChangedEntryReferenceMap.clear();
    messageIdToBeginSendEntryReferenceMap.clear();
}

void EventlogFileManager::configure()
{
    // setup eventlog object printer
    delete objectPrinter;
    objectPrinter = NULL;
    const char *eventLogMessageDetailPattern = ev.getConfig()->getAsCustom(CFGID_EVENTLOG_MESSAGE_DETAIL_PATTERN);
    if (eventLogMessageDetailPattern)
        objectPrinter = new ObjectPrinter(recurseIntoMessageFields, eventLogMessageDetailPattern, 3);

    // setup eventlog recording intervals
    const char *text = ev.getConfig()->getAsCustom(CFGID_EVENTLOG_RECORDING_INTERVALS);
    if (text) {
        recordingIntervals = new Intervals();
        recordingIntervals->parse(text);
    }

    // setup filename
    filename = ev.getConfig()->getAsFilename(CFGID_EVENTLOG_FILE).c_str();
    dynamic_cast<EnvirBase *>(&ev)->processFileName(filename);
}

void EventlogFileManager::open()
{
    if (!feventlog) {
        mkPath(directoryOf(filename.c_str()).c_str());
        FILE *out = fopen(filename.c_str(), "w");
        if (!out)
            throw cRuntimeError("Cannot open eventlog file `%s' for write", filename.c_str());
        ::printf("Recording eventlog to file `%s'...\n", filename.c_str());
        feventlog = out;
        clearInternalState();
    }
}

void EventlogFileManager::close()
{
    if (feventlog) {
        fclose(feventlog);
        feventlog = NULL;
        isEventLogRecordingEnabled = false;
    }
}

void EventlogFileManager::remove()
{
    removeFile(filename.c_str(), "old eventlog file");
    entryIndex = -1;
}

void EventlogFileManager::recordSimulation()
{
    if (entryIndex == -1) {
        cModule *systemModule = simulation.getSystemModule();
        recordModules(systemModule);
        recordConnections(systemModule);
        recordMessages();
    }
}

void EventlogFileManager::recordMessages()
{
    const char *runId = ev.getConfigEx()->getVariable(CFGVAR_RUNID);
    std::vector<cMessage *> messages;
    for (cMessageHeap::Iterator it = cMessageHeap::Iterator(simulation.getMessageQueue()); !it.end(); it++)
        messages.push_back(it());
    std::stable_sort(messages.begin(), messages.end(), compareMessageEventNumbers);
    eventnumber_t oldEventNumber = eventNumber;
    eventNumber = -1;
    for (std::vector<cMessage *>::iterator it = messages.begin(); it != messages.end(); it++) {
        cMessage *msg = *it;
        if (eventNumber != msg->getPreviousEventNumber()) {
            eventNumber = msg->getPreviousEventNumber();
            EventLogWriter::recordEventEntry_e_t_m_ce_msg(feventlog, eventNumber, msg->getSendingTime(), eventNumber == 0 ? simulation.getSystemModule()->getId() : msg->getSenderModuleId(), -1, -1);
            entryIndex = 0;
            if (eventNumber == 0) {
                EventLogWriter::recordSimulationBeginEntry_v_rid_b(feventlog, OMNETPP_VERSION, runId, keyframeBlockSize);
                entryIndex++;
            }
            removeBeginSendEntryReference(msg->getId());
            recordKeyframe();
        }
        if (eventNumber == 0) {
        	cModule *senderModule = msg->getSenderModule();
            componentMethodBegin(simulation.getSystemModule(), senderModule ? senderModule : msg->getArrivalModule(), senderModule ? "initialize(0)" : "scheduleStart()", empty_va);
        }
        if (msg->isSelfMessage())
            messageScheduled(msg);
        else if (!msg->getSenderGate()) {
            beginSend(msg);
            if (msg->isPacket()) {
                cPacket *packet = (cPacket *)msg;
                simtime_t propagationDelay = packet->getArrivalTime() - packet->getSendingTime() - (packet->isReceptionStart() ? 0 : packet->getDuration());
                messageSendDirect(msg, msg->getArrivalGate(), propagationDelay, packet->getDuration());
            }
            else
                messageSendDirect(msg, msg->getArrivalGate(), 0, 0);
            endSend(msg);
        }
        else {
            beginSend(msg);
            messageSendHop(msg, msg->getSenderGate());
            endSend(msg);
        }
        if (eventNumber == 0)
            componentMethodEnd();
        eventNumber = oldEventNumber;
    }
}

void EventlogFileManager::recordModules(cModule *module)
{
    moduleCreated(module);
    // FIXME: records display string twice if it is lazily created right now
    if (strcmp(module->getDisplayString().str(), ""))
        displayStringChanged(module);
    for (cModule::GateIterator it(module); !it.end(); it++) {
        cGate *gate = it();
        gateCreated(gate);
    }
    for (cModule::SubmoduleIterator it(module); !it.end(); it++)
        recordModules(it());
}

void EventlogFileManager::recordConnections(cModule *module)
{
    for (cModule::GateIterator it(module); !it.end(); it++) {
        cGate *gate = it();
        if (gate->getNextGate())
            connectionCreated(gate);
        cChannel *channel = gate->getChannel();
        if (channel && strcmp(channel->getDisplayString(), ""))
            displayStringChanged(channel);
    }
    for (cModule::SubmoduleIterator it(module); !it.end(); it++)
        recordConnections(it());
}

void EventlogFileManager::startRun()
{
    if (isEventLogRecordingEnabled) {
        eventNumber = 0;
        const char *runId = ev.getConfigEx()->getVariable(CFGVAR_RUNID);
        // TODO: we can't use simulation.getEventNumber() and simulation.getSimTime(), because when we start a new run
        // these numbers are still set from the previous run (i.e. not zero)
        EventLogWriter::recordEventEntry_e_t_m_ce_msg(feventlog, eventNumber, 0, simulation.getSystemModule()->getId(), -1, -1);
        entryIndex = 0;
        EventLogWriter::recordSimulationBeginEntry_v_rid_b(feventlog, OMNETPP_VERSION, runId, keyframeBlockSize);
        entryIndex++;
        recordKeyframe();
        fflush(feventlog);
    }
}

void EventlogFileManager::endRun()
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordSimulationEndEntry(feventlog);
        eventNumber = -1;
        entryIndex++;
        fflush(feventlog);
    }
}

bool EventlogFileManager::hasRecordingIntervals() const
{
    return recordingIntervals && !recordingIntervals->empty();
}

void EventlogFileManager::clearRecordingIntervals()
{
    if (recordingIntervals) {
        delete recordingIntervals;
        recordingIntervals = NULL;
    }
}

void EventlogFileManager::flush()
{
    if (isEventLogRecordingEnabled)
        fflush(feventlog);
}

void EventlogFileManager::simulationEvent(cMessage *msg)
{
    cModule *mod = simulation.getContextModule();
    isModuleEventLogRecordingEnabled = simulation.getContextModule()->isRecordEvents();
    isIntervalEventLogRecordingEnabled = !recordingIntervals || recordingIntervals->contains(simulation.getSimTime());
    isEventLogRecordingEnabled = isModuleEventLogRecordingEnabled && isIntervalEventLogRecordingEnabled;
    if (isEventLogRecordingEnabled) {
        eventNumber = simulation.getEventNumber();
        EventLogWriter::recordEventEntry_e_t_m_ce_msg(feventlog, eventNumber, simulation.getSimTime(), mod->getId(), msg->getPreviousEventNumber(), msg->getId());
        entryIndex = 0;
        removeBeginSendEntryReference(msg->getId());
        recordKeyframe();
    }
}

void EventlogFileManager::bubble(cComponent *component, const char *text)
{
    if (isEventLogRecordingEnabled) {
        if (dynamic_cast<cModule *>(component)) {
            cModule *mod = (cModule *)component;
            EventLogWriter::recordBubbleEntry_id_txt(feventlog, mod->getId(), text);
            entryIndex++;
        }
        else if (dynamic_cast<cChannel *>(component)) {
            //TODO
        }
    }
}

void EventlogFileManager::beginSend(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        //TODO record message display string as well?
        if (msg->isPacket()) {
            cPacket *pkt = (cPacket *)msg;
            EventLogWriter::recordBeginSendEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                pkt->getId(), pkt->getTreeId(), pkt->getEncapsulationId(), pkt->getEncapsulationTreeId(),
                pkt->getClassName(), pkt->getFullName(),
                pkt->getKind(), pkt->getSchedulingPriority(), pkt->getBitLength(), pkt->hasBitError(),
                objectPrinter ? objectPrinter->printObjectToString(pkt).c_str() : NULL,
                pkt->getPreviousEventNumber());
        }
        else {
            EventLogWriter::recordBeginSendEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                msg->getId(), msg->getTreeId(), msg->getId(), msg->getTreeId(),
                msg->getClassName(), msg->getFullName(),
                msg->getKind(), msg->getSchedulingPriority(), 0, false,
                objectPrinter ? objectPrinter->printObjectToString(msg).c_str() : NULL,
                msg->getPreviousEventNumber());
        }
        entryIndex++;
        addPreviousEventNumber(msg->getPreviousEventNumber());
        addSimulationStateEventLogEntry(eventNumber, entryIndex);
        messageIdToBeginSendEntryReferenceMap[msg->getId()] = EventLogEntryReference(eventNumber, entryIndex);
    }
}

void EventlogFileManager::messageScheduled(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        EventlogFileManager::beginSend(msg);
        EventlogFileManager::endSend(msg);
    }
}

void EventlogFileManager::messageCancelled(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        if (msg->isPacket()) {
            cPacket *pkt = (cPacket *)msg;
            EventLogWriter::recordCancelEventEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                pkt->getId(), pkt->getTreeId(), pkt->getEncapsulationId(), pkt->getEncapsulationTreeId(),
                pkt->getClassName(), pkt->getFullName(),
                pkt->getKind(), pkt->getSchedulingPriority(), pkt->getBitLength(), pkt->hasBitError(),
                objectPrinter ? objectPrinter->printObjectToString(pkt).c_str() : NULL,
                pkt->getPreviousEventNumber());
        }
        else {
            EventLogWriter::recordCancelEventEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                msg->getId(), msg->getTreeId(), msg->getId(), msg->getTreeId(),
                msg->getClassName(), msg->getFullName(),
                msg->getKind(), msg->getSchedulingPriority(), 0, false,
                objectPrinter ? objectPrinter->printObjectToString(msg).c_str() : NULL,
                msg->getPreviousEventNumber());
        }
        entryIndex++;
        addPreviousEventNumber(msg->getPreviousEventNumber());
        removeBeginSendEntryReference(msg->getId());
    }
}

void EventlogFileManager::messageSendDirect(cMessage *msg, cGate *toGate, simtime_t propagationDelay, simtime_t transmissionDelay)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordSendDirectEntry_sm_dm_dg_pd_td(feventlog, msg->getSenderModuleId(), toGate->getOwnerModule()->getId(), toGate->getId(), propagationDelay, transmissionDelay);
        entryIndex++;
    }
}

void EventlogFileManager::messageSendHop(cMessage *msg, cGate *srcGate)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordSendHopEntry_sm_sg(feventlog, srcGate->getOwnerModule()->getId(), srcGate->getId());
        entryIndex++;
    }
}

void EventlogFileManager::messageSendHop(cMessage *msg, cGate *srcGate, simtime_t propagationDelay, simtime_t transmissionDelay)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordSendHopEntry_sm_sg_pd_td(feventlog, srcGate->getOwnerModule()->getId(), srcGate->getId(), propagationDelay, transmissionDelay);
        entryIndex++;
    }
}

void EventlogFileManager::endSend(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        bool isStart = msg->isPacket() ? ((cPacket *)msg)->isReceptionStart() : false;
        EventLogWriter::recordEndSendEntry_t_is(feventlog, msg->getArrivalTime(), isStart);
        entryIndex++;
    }
}

void EventlogFileManager::messageCreated(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        if (msg->isPacket()) {
            cPacket *pkt = (cPacket *)msg;
            EventLogWriter::recordCreateMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                pkt->getId(), pkt->getTreeId(), pkt->getEncapsulationId(), pkt->getEncapsulationTreeId(),
                pkt->getClassName(), pkt->getFullName(),
                pkt->getKind(), pkt->getSchedulingPriority(), pkt->getBitLength(), pkt->hasBitError(),
                objectPrinter ? objectPrinter->printObjectToString(pkt).c_str() : NULL,
                pkt->getPreviousEventNumber());
        }
        else {
            EventLogWriter::recordCreateMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                msg->getId(), msg->getTreeId(), msg->getId(), msg->getTreeId(),
                msg->getClassName(), msg->getFullName(),
                msg->getKind(), msg->getSchedulingPriority(), 0, false,
                objectPrinter ? objectPrinter->printObjectToString(msg).c_str() : NULL,
                msg->getPreviousEventNumber());
        }
        entryIndex++;
        addPreviousEventNumber(msg->getPreviousEventNumber());
    }
}

void EventlogFileManager::messageCloned(cMessage *msg, cMessage *clone)
{
    if (isEventLogRecordingEnabled) {
        if (msg->isPacket()) {
            cPacket *pkt = (cPacket *)msg;
            EventLogWriter::recordCloneMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe_cid(feventlog,
                pkt->getId(), pkt->getTreeId(), pkt->getEncapsulationId(), pkt->getEncapsulationTreeId(),
                pkt->getClassName(), pkt->getFullName(),
                pkt->getKind(), pkt->getSchedulingPriority(), pkt->getBitLength(), pkt->hasBitError(),
                objectPrinter ? objectPrinter->printObjectToString(pkt).c_str() : NULL,
                pkt->getPreviousEventNumber(), clone->getId());
        }
        else {
            EventLogWriter::recordCloneMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe_cid(feventlog,
                msg->getId(), msg->getTreeId(), msg->getId(), msg->getTreeId(),
                msg->getClassName(), msg->getFullName(),
                msg->getKind(), msg->getSchedulingPriority(), 0, false,
                objectPrinter ? objectPrinter->printObjectToString(msg).c_str() : NULL,
                msg->getPreviousEventNumber(), clone->getId());
        }
        entryIndex++;
        addPreviousEventNumber(msg->getPreviousEventNumber());
    }
}

void EventlogFileManager::messageDeleted(cMessage *msg)
{
    if (isEventLogRecordingEnabled) {
        if (msg->isPacket()) {
            cPacket *pkt = (cPacket *)msg;
            EventLogWriter::recordDeleteMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                pkt->getId(), pkt->getTreeId(), pkt->getEncapsulationId(), pkt->getEncapsulationTreeId(),
                pkt->getClassName(), pkt->getFullName(),
                pkt->getKind(), pkt->getSchedulingPriority(), pkt->getBitLength(), pkt->hasBitError(),
                objectPrinter ? objectPrinter->printObjectToString(pkt).c_str() : NULL,
                pkt->getPreviousEventNumber());
        }
        else {
            EventLogWriter::recordDeleteMessageEntry_id_tid_eid_etid_c_n_k_p_l_er_d_pe(feventlog,
                msg->getId(), msg->getTreeId(), msg->getId(), msg->getTreeId(),
                msg->getClassName(), msg->getFullName(),
                msg->getKind(), msg->getSchedulingPriority(), 0, false,
                objectPrinter ? objectPrinter->printObjectToString(msg).c_str() : NULL,
                msg->getPreviousEventNumber());
        }
        entryIndex++;
        addPreviousEventNumber(msg->getPreviousEventNumber());
    }
}

void EventlogFileManager::componentMethodBegin(cComponent *from, cComponent *to, const char *methodFmt, va_list va)
{
    if (isEventLogRecordingEnabled) {
        if (from && from->isModule() && to->isModule()) {
            const char *methodText = "";  // for the Enter_Method_Silent case
            if (methodFmt) {
                static char methodTextBuf[MAX_METHODCALL];
                vsnprintf(methodTextBuf, MAX_METHODCALL, methodFmt, va);
                methodTextBuf[MAX_METHODCALL-1] = '\0';
                methodText = methodTextBuf;
            }
            EventLogWriter::recordModuleMethodBeginEntry_sm_tm_m(feventlog, ((cModule *)from)->getId(), ((cModule *)to)->getId(), methodText);
            entryIndex++;
        }
    }
}

void EventlogFileManager::componentMethodEnd()
{
    if (isEventLogRecordingEnabled) {
        // TODO: problem when channel method is called: we'll emit an "End" entry but no "Begin"
        // TODO: same problem when the caller is not a module or is NULL
        EventLogWriter::recordModuleMethodEndEntry(feventlog);
        entryIndex++;
    }
}

void EventlogFileManager::moduleCreated(cModule *newmodule)
{
    if (isEventLogRecordingEnabled) {
        cModule *m = newmodule;
        bool recordModuleEvents = ev.getConfig()->getAsBool(m->getFullPath().c_str(), CFGID_MODULE_EVENTLOG_RECORDING);
        m->setRecordEvents(recordModuleEvents);
        bool isCompoundModule = dynamic_cast<cCompoundModule *>(m);
        EventLogWriter::recordModuleCreatedEntry_id_c_t_pid_n_cm(feventlog, m->getId(), m->getClassName(), m->getNedTypeName(), m->getParentModule() ? m->getParentModule()->getId() : -1, m->getFullName(), isCompoundModule); //FIXME size() is missing
        entryIndex++;
        addSimulationStateEventLogEntry(eventNumber, entryIndex);
    }
}

void EventlogFileManager::moduleDeleted(cModule *module)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordModuleDeletedEntry_id(feventlog, module->getId());
        entryIndex++;
    }
}

void EventlogFileManager::moduleReparented(cModule *module, cModule *oldparent)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordModuleReparentedEntry_id_p(feventlog, module->getId(), module->getParentModule()->getId());
        entryIndex++;
    }
}

void EventlogFileManager::gateCreated(cGate *newgate)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordGateCreatedEntry_m_g_n_i_o(feventlog, newgate->getOwnerModule()->getId(), newgate->getId(), newgate->getName(), newgate->isVector() ? newgate->getIndex() : -1, newgate->getType() == cGate::OUTPUT);
        entryIndex++;
        addSimulationStateEventLogEntry(eventNumber, entryIndex);
    }
}

void EventlogFileManager::gateDeleted(cGate *gate)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordGateDeletedEntry_m_g(feventlog, gate->getOwnerModule()->getId(), gate->getId());
        entryIndex++;
    }
}

void EventlogFileManager::connectionCreated(cGate *srcgate)
{
    if (isEventLogRecordingEnabled) {
        cGate *destgate = srcgate->getNextGate();
        EventLogWriter::recordConnectionCreatedEntry_sm_sg_dm_dg(feventlog, srcgate->getOwnerModule()->getId(), srcgate->getId(), destgate->getOwnerModule()->getId(), destgate->getId());  // TODO: channel, channel attributes, etc
        entryIndex++;
        addSimulationStateEventLogEntry(eventNumber, entryIndex);
    }
}

void EventlogFileManager::connectionDeleted(cGate *srcgate)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordConnectionDeletedEntry_sm_sg(feventlog, srcgate->getOwnerModule()->getId(), srcgate->getId());
        entryIndex++;
    }
}

void EventlogFileManager::displayStringChanged(cComponent *component)
{
    if (isEventLogRecordingEnabled) {
        if (dynamic_cast<cModule *>(component)) {
            cModule *module = (cModule *)component;
            EventLogWriter::recordModuleDisplayStringChangedEntry_id_d(feventlog, module->getId(), module->getDisplayString().str());
            entryIndex++;
            addSimulationStateEventLogEntry(eventNumber, entryIndex);
            std::map<int, EventLogEntryReference>::iterator it = moduleIdToModuleDisplayStringChangedEntryReferenceMap.find(module->getId());
            if (it != moduleIdToModuleDisplayStringChangedEntryReferenceMap.end())
                removeSimulationStateEventLogEntry((*it).second);
            moduleIdToModuleDisplayStringChangedEntryReferenceMap[module->getId()] = EventLogEntryReference(eventNumber, entryIndex);
        }
        else if (dynamic_cast<cChannel *>(component)) {
            cChannel *channel = (cChannel *)component;
            cGate *gate = channel->getSourceGate();
            EventLogWriter::recordConnectionDisplayStringChangedEntry_sm_sg_d(feventlog, gate->getOwnerModule()->getId(), gate->getId(), channel->getDisplayString().str());
            entryIndex++;
            addSimulationStateEventLogEntry(eventNumber, entryIndex);
            // TODO: remove overwritten entries
        }
    }
}

void EventlogFileManager::sputn(const char *s, int n)
{
    if (isEventLogRecordingEnabled) {
        EventLogWriter::recordLogLine(feventlog, s, n);
        entryIndex++;
    }
}

//========================================================================== keyframe management

void EventlogFileManager::addSimulationStateEventLogEntry(EventLogEntryReference reference)
{
    addSimulationStateEventLogEntry(reference.eventNumber, reference.entryIndex);
}

void EventlogFileManager::addSimulationStateEventLogEntry(eventnumber_t eventNumber, int entryIndex)
{
    std::map<eventnumber_t, std::vector<EventLogEntryRange> >::iterator it = eventNumberToSimulationStateEventLogEntryRanges.find(eventNumber);
    if (it != eventNumberToSimulationStateEventLogEntryRanges.end()) {
        std::vector<EventLogEntryRange> &ranges = it->second;
        EventLogEntryRange &back = ranges.back();
        if (back.eventNumber == eventNumber && back.endEntryIndex == entryIndex - 1)
            back.endEntryIndex++;
        else
            ranges.push_back(EventLogEntryRange(eventNumber, entryIndex, entryIndex));
    }
    else {
        std::vector<EventLogEntryRange> ranges;
        ranges.push_back(EventLogEntryRange(eventNumber, entryIndex, entryIndex));
        eventNumberToSimulationStateEventLogEntryRanges[eventNumber] = ranges;
    }
}

void EventlogFileManager::removeSimulationStateEventLogEntry(EventLogEntryReference reference)
{
    removeSimulationStateEventLogEntry(reference.eventNumber, reference.entryIndex);
}

void EventlogFileManager::removeSimulationStateEventLogEntry(eventnumber_t eventNumber, int entryIndex)
{
    std::map<eventnumber_t, std::vector<EventLogEntryRange> >::iterator it = eventNumberToSimulationStateEventLogEntryRanges.find(eventNumber);
    if (it != eventNumberToSimulationStateEventLogEntryRanges.end()) {
        std::vector<EventLogEntryRange> &ranges = it->second;
        for (std::vector<EventLogEntryRange>::iterator jt = ranges.begin(); jt != ranges.end(); jt++) {
            EventLogEntryRange eventLogEntryRange = *jt;
            int beginEntryIndex = eventLogEntryRange.beginEntryIndex;
            int endEntryIndex = eventLogEntryRange.endEntryIndex;
            if (eventLogEntryRange.eventNumber == eventNumber && beginEntryIndex <= entryIndex && entryIndex <= endEntryIndex) {
                ranges.erase(jt);
                if (eventLogEntryRange.beginEntryIndex != eventLogEntryRange.endEntryIndex) {
                    if (beginEntryIndex != entryIndex)
                        ranges.push_back(EventLogEntryRange(eventNumber, beginEntryIndex, entryIndex - 1));
                    if (endEntryIndex != entryIndex)
                        ranges.push_back(EventLogEntryRange(eventNumber, entryIndex + 1, endEntryIndex));
                }
                if (ranges.size() == 0)
                    eventNumberToSimulationStateEventLogEntryRanges.erase(it);
                return;
            }
        }
    }
}

void EventlogFileManager::removeBeginSendEntryReference(int messageId)
{
    std::map<int, EventLogEntryReference>::iterator it = messageIdToBeginSendEntryReferenceMap.find(messageId);
    if (it != messageIdToBeginSendEntryReferenceMap.end())
        removeSimulationStateEventLogEntry((*it).second);
    messageIdToBeginSendEntryReferenceMap.erase(messageId);
}

void EventlogFileManager::recordKeyframe()
{
    if (eventNumber % keyframeBlockSize == 0) {
        consequenceLookaheadLimits.push_back(0);
        int newPreviousKeyframeFileOffset = opp_ftell(feventlog);
        fprintf(feventlog, "KF");
        // previousKeyframeFileOffset
        fprintf(feventlog, " p %"INT64_PRINTF_FORMAT"d", previousKeyframeFileOffset);
        previousKeyframeFileOffset = newPreviousKeyframeFileOffset;
        // consequenceLookahead
        fprintf(feventlog, " c \"");
        int i = 0;
        for (std::vector<eventnumber_t>::iterator it = consequenceLookaheadLimits.begin(); it != consequenceLookaheadLimits.end(); it++) {
            eventnumber_t consequenceLookaheadLimit = *it;
            if (consequenceLookaheadLimit)
                fprintf(feventlog, "%"INT64_PRINTF_FORMAT"d:%"INT64_PRINTF_FORMAT"d,", (eventnumber_t)keyframeBlockSize * i, consequenceLookaheadLimit);
            *it = 0;
            i++;
        }
        // simulationStateEntries
        fprintf(feventlog, "\" s \"");
        for (std::map<eventnumber_t, std::vector<EventLogEntryRange> >::iterator it = eventNumberToSimulationStateEventLogEntryRanges.begin(); it != eventNumberToSimulationStateEventLogEntryRanges.end(); it++) {
            std::vector<EventLogEntryRange> &ranges = it->second;
            for (std::vector<EventLogEntryRange>::iterator jt = ranges.begin(); jt != ranges.end(); jt++) {
                (*jt).print(feventlog);
                fprintf(feventlog, ",");
            }
        }
        fprintf(feventlog, "\"\n");
        entryIndex++;
    }
}

void EventlogFileManager::addPreviousEventNumber(eventnumber_t previousEventNumber)
{
    if (previousEventNumber != -1) {
        int blockIndex = previousEventNumber / keyframeBlockSize;
        consequenceLookaheadLimits.resize(blockIndex + 1);
        consequenceLookaheadLimits[blockIndex] = std::max(consequenceLookaheadLimits[blockIndex], eventNumber - previousEventNumber);
    }
}
