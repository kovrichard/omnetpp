//=========================================================================
//  PARSIMUTIL.H - part of
//
//                  OMNeT++/OMNEST
//           Discrete System Simulation in C++
//
//  Author: Andras Varga, 2003
//          Dept. of Electrical and Computer Systems Engineering,
//          Monash University, Melbourne, Australia
//
//=========================================================================

/*--------------------------------------------------------------*
  Copyright (C) 2003-2017 Andras Varga
  Copyright (C) 2006-2017 OpenSim Ltd.

  This file is distributed WITHOUT ANY WARRANTY. See the file
  `license' for details on this and other legal matters.
*--------------------------------------------------------------*/

#ifndef __OMNETPP_PARSIMUTIL_H
#define __OMNETPP_PARSIMUTIL_H

namespace omnetpp {

/**
 * @brief Parses the -p<procId> command line argument, and returns <procId>.
 * Throws exception on error.
 */
int getProcIdFromCommandLineArgs(int numPartitions, const char *caller);

}  // namespace omnetpp

#endif

