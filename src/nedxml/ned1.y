/*===============================================================
 * File: ned.y
 *
 *  Grammar for OMNeT++ NED.
 *
 *  Author: Andras Varga
 *
 *  Based on code from nedc.
 *
 *  nedc credits:
 *     original code:
 *       Jan Heijmans, Alex Paalvast, Robert van der Leij, 1996
 *       (nedc was originally named jar, for Jan+Alex+Robert)
 *     modifications
 *       Gabor Lencse 1998
 *     restructuring, maintenance, new features, etc:
 *       Andras Varga 1996-2001
 *
 *=============================================================*/

/*--------------------------------------------------------------*
  Copyright (C) 1992,2006 Andras Varga

  This file is distributed WITHOUT ANY WARRANTY. See the file
  `license' for details on this and other legal matters.
*--------------------------------------------------------------*/

%token INCLUDE SIMPLE
%token CHANNEL /*DELAY ERROR DATARATE are no longer tokens*/
%token MODULE PARAMETERS GATES GATESIZES SUBMODULES CONNECTIONS DISPLAY
%token IN OUT
%token NOCHECK LEFT_ARROW RIGHT_ARROW
%token FOR TO DO IF LIKE
%token NETWORK
%token ENDSIMPLE ENDMODULE ENDCHANNEL
%token ENDNETWORK ENDFOR
%token MACHINES ON
%token CHANATTRNAME

%token INTCONSTANT REALCONSTANT NAME STRINGCONSTANT CHARCONSTANT
%token TRUE_ FALSE_
%token INPUT_ XMLDOC
%token REF ANCESTOR
%token CONSTDECL NUMERICTYPE STRINGTYPE BOOLTYPE XMLTYPE ANYTYPE

%token CPLUSPLUS CPLUSPLUSBODY
%token MESSAGE CLASS STRUCT ENUM NONCOBJECT
%token EXTENDS FIELDS PROPERTIES ABSTRACT READONLY
%token CHARTYPE SHORTTYPE INTTYPE LONGTYPE DOUBLETYPE UNSIGNED_

%token SIZEOF SUBMODINDEX PLUSPLUS
%token EQ NE GT GE LS LE
%token AND OR XOR NOT
%token BIN_AND BIN_OR BIN_XOR BIN_COMPL
%token SHIFT_LEFT SHIFT_RIGHT

%token INVALID_CHAR   /* just to generate parse error --VA */

/* Operator precedences (low to high) and associativity */
%left '?' ':'
%left AND OR XOR
%left EQ NE GT GE LS LE
%left BIN_AND BIN_OR BIN_XOR
%left SHIFT_LEFT SHIFT_RIGHT
%left '+' '-'
%left '*' '/' '%'
%right '^'
%left UMIN NOT BIN_COMPL

%start networkdescription


%{

/*
 * Note:
 * This file contains about 5 shift-reduce conflicts, 3 of them around 'expression'.
 *
 * Plus one (real) ambiguity exists between submodule display string
 * and compound module display string if no connections are present.
 */


#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "nedyydefs.h"
#include "nederror.h"

#define YYDEBUG 1           /* allow debugging */
#define YYDEBUGGING_ON 0    /* turn on/off debugging */

#if YYDEBUG != 0
#define YYERROR_VERBOSE     /* more detailed error messages */
#include <string.h>         /* YYVERBOSE needs it */
#endif

#define yylloc ned1yylloc
#define yyin ned1yyin
#define yyout ned1yyout
#define yyrestart ned1yyrestart
#define yy_scan_string ned1yy_scan_string
#define yy_delete_buffer ned1yy_delete_buffer
extern FILE *yyin;
extern FILE *yyout;
struct yy_buffer_state;
struct yy_buffer_state *yy_scan_string(const char *str);
void yy_delete_buffer(struct yy_buffer_state *);
void yyrestart(FILE *);
int yylex();
void yyerror (const char *s);

#include "nedparser.h"
#include "nedfilebuffer.h"
#include "nedelements.h"
#include "nedutil.h"
#include "nedyylib.h"

static struct NED1ParserState
{
    bool inLoop;
    bool inNetwork;
    bool inGroup;

    /* tmp flags, used with msg fields */
    bool isAbstract;
    bool isReadonly;

    /* NED-I: modules, channels, networks */
    NedFileNode *nedfile;
    CommentNode *comment;
    ImportNode *import;
    ExtendsNode *extends;
    ChannelNode *channel;
    NEDElement *module;  // in fact, CompoundModuleNode* or SimpleModule*
    ParametersNode *params;
    ParamNode *param;
    ParametersNode *substparams;
    ParamGroupNode *substparamgroup;
    ParamNode *substparam;
    PropertyNode *property;
    PropertyKeyNode *propkey;
    GatesNode *gates;
    GateNode *gate;
    GatesNode *gatesizes;
    GateGroupNode *gatesizesgroup;
    GateNode *gatesize;
    SubmodulesNode *submods;
    SubmoduleNode *submod;
    ConnectionsNode *conns;
    ConnectionGroupNode *conngroup;
    ConnectionNode *conn;
    ChannelSpecNode *chanspec;
    LoopNode *loop;
    ConditionNode *condition;
} ps;

static void resetParserState()
{
    static NED1ParserState cleanps;
    ps = cleanps;
}

ChannelSpecNode *createChannelSpec(NEDElement *conn);
void removeRedundantChanSpecParams();
void createSubstparamsNodeIfNotExists();
void createGatesizesNodeIfNotExists();

%}

%%

/*
 * Top-level components (no shift-reduce conflict here)
 */
networkdescription
        : somedefinitions
        ;

somedefinitions
        : somedefinitions definition
        |
        ;

definition
        : import

        | channeldefinition
                { if (np->getStoreSourceFlag()) storeComponentSourceCode(ps.channel, @1); }
        | simpledefinition
                { if (np->getStoreSourceFlag()) storeComponentSourceCode(ps.module, @1); }
        | moduledefinition
                { if (np->getStoreSourceFlag()) storeComponentSourceCode(ps.module, @1); }
        | networkdefinition
                { if (np->getStoreSourceFlag()) storeComponentSourceCode(ps.module, @1); }
        ;

/*
 * Imports (no shift-reduce conflict here)
 */
import
        : INCLUDE
          filenames ';'
        ;

filenames
        : filenames ',' filename
        | filename
        ;

filename
        : STRINGCONSTANT
                {
                  ps.import = (ImportNode *)createNodeWithTag(NED_IMPORT, ps.nedfile );
                  ps.import->setFilename(toString(trimQuotes(@1)));
                  storeComments(ps.import,@1);
                  storePos(ps.import, @$);
                }
        ;

/*
 * Channel - old syntax
 */
channeldefinition
        : channelheader opt_channelattrblock endchannel
                { storePos(ps.channel, @$); }
        ;

channelheader
        : CHANNEL NAME
                {
                  ps.channel = (ChannelNode *)createNodeWithTag(NED_CHANNEL, ps.nedfile);
                  ps.channel->setName(toString(@2));
                  ps.extends = (ExtendsNode *)createNodeWithTag(NED_EXTENDS, ps.channel);
                  ps.extends->setName("BasicChannel"); // implicit base class "BasicChannel" FIXME why store if implicit?
                  ps.params = (ParametersNode *)createNodeWithTag(NED_PARAMETERS, ps.channel);
                  ps.params->setIsImplicit(true);
                  storeComments(ps.channel,@1,@2);
                }
        ;

opt_channelattrblock
        :
        | channelattrblock
                { storePos(ps.params, @$); }
        ;

channelattrblock
        : channelattrblock CHANATTRNAME expression opt_semicolon
                {
                  ps.params->setIsImplicit(false);
                  ps.param = addParameter(ps.params, @2);
                  addExpression(ps.param, "value",@3,$3);
                  storeComments(ps.param,@2,@3);
                  storePos(ps.param, @2); // XXX rather: @2..@4
                }
        | CHANATTRNAME expression opt_semicolon
                {
                  ps.params->setIsImplicit(false);
                  ps.param = addParameter(ps.params, @1);
                  addExpression(ps.param, "value",@2,$2);
                  storeComments(ps.param,@1,@2);
                  storePos(ps.param, @$);
                }
        ;

endchannel
        : ENDCHANNEL NAME opt_semicolon
                {
                  storeTrailingComment(ps.channel,@2);
                }
        | ENDCHANNEL opt_semicolon
                {
                  storeTrailingComment(ps.channel,@1);
                }
        ;

/*
 * Simple module - old syntax
 */
simpledefinition
        : simpleheader
            opt_paramblock
            opt_gateblock
          endsimple
                { storePos(ps.module, @$); }
        ;

simpleheader
        : SIMPLE NAME
                {
                  ps.module = (SimpleModuleNode *)createNodeWithTag(NED_SIMPLE_MODULE, ps.nedfile );
                  ((SimpleModuleNode *)ps.module)->setName(toString(@2));
                  storeComments(ps.module,@1,@2);
                }
        ;

endsimple
        : ENDSIMPLE NAME opt_semicolon
                {
                  storeTrailingComment(ps.module,@2);
                }
        | ENDSIMPLE opt_semicolon
                {
                  storeTrailingComment(ps.module,@1);
                }
        ;

/*
 * Module - old syntax
 */
moduledefinition
        : moduleheader
            opt_paramblock
            opt_gateblock
            opt_submodblock
            opt_connblock
            opt_displayblock
          endmodule
                { storePos(ps.module, @$); }
        ;

moduleheader
        : MODULE NAME
                {
                  ps.module = (CompoundModuleNode *)createNodeWithTag(NED_COMPOUND_MODULE, ps.nedfile );
                  ((CompoundModuleNode *)ps.module)->setName(toString(@2));
                  storeComments(ps.module,@1,@2);
                }
        ;

endmodule
        : ENDMODULE NAME opt_semicolon
                {
                  storeTrailingComment(ps.module,@2);
                }
        | ENDMODULE opt_semicolon
                {
                  storeTrailingComment(ps.module,@1);
                }
        ;

/*
 * Display block - old syntax
 */
opt_displayblock
        : displayblock
        |
        ;

displayblock
        : DISPLAY ':' STRINGCONSTANT ';'
                {
                  ps.property = addComponentProperty(ps.module, "display");
                  ps.params = (ParametersNode *)ps.module->getFirstChildWithTag(NED_PARAMETERS); // previous line doesn't set it
                  ps.propkey = (PropertyKeyNode *)createNodeWithTag(NED_PROPERTY_KEY, ps.property);
                  LiteralNode *literal = createLiteral(NED_CONST_STRING, trimQuotes(@3), @3);
                  ps.propkey->appendChild(literal);
                  storePos(ps.propkey, @$);
                  storePos(literal, @3);
                  storePos(ps.property, @$);
                }
        ;

/*
 * Parameters - old syntax
 */
opt_paramblock
        : paramblock
        |
        ;

paramblock
        : PARAMETERS ':'
                {
                  ps.params = (ParametersNode *)createNodeWithTag(NED_PARAMETERS, ps.module );
                  storeComments(ps.params,@1,@2);
                }
          opt_parameters
                {
                  storePos(ps.params, @$);
                }
        ;

opt_parameters
        : parameters ';'
        |
        ;

parameters
        : parameters ',' parameter  /* comma as separator */
                {
                  storeComments(ps.param,@3);
                }
        | parameter
                {
                  storeComments(ps.param,@1);
                }
        ;

/*
 * Parameter
 */
parameter
        : NAME
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  ps.param->setIsFunction(true); // because CONST is missing
                  storePos(ps.param, @$);
                }
        | NAME ':' NUMERICTYPE
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  ps.param->setIsFunction(true); // because CONST is missing
                  storePos(ps.param, @$);
                }
        | CONSTDECL NAME /* for compatibility */
                {
                  ps.param = addParameter(ps.params, @2);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  storePos(ps.param, @$);
                }
        | NAME ':' CONSTDECL
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  storePos(ps.param, @$);
                }
        | NAME ':' CONSTDECL NUMERICTYPE
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  storePos(ps.param, @$);
                }
        | NAME ':' NUMERICTYPE CONSTDECL
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_DOUBLE);
                  storePos(ps.param, @$);
                }
        | NAME ':' STRINGTYPE
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_STRING);
                  storePos(ps.param, @$);
                }
        | NAME ':' BOOLTYPE
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_BOOL);
                  storePos(ps.param, @$);
                }
        | NAME ':' XMLTYPE
                {
                  ps.param = addParameter(ps.params, @1);
                  ps.param->setType(NED_PARTYPE_XML);
                  storePos(ps.param, @$);
                }
        | NAME ':' ANYTYPE
                {
                  np->getErrors()->add(ps.params,"type 'anytype' no longer supported");
                }
        ;

/*
 * Gates - old syntax
 */
opt_gateblock
        : gateblock
        |
        ;

gateblock
        : GATES ':'
                {
                  ps.gates = (GatesNode *)createNodeWithTag(NED_GATES, ps.module );
                  storeComments(ps.gates,@1,@2);
                }
          opt_gates
                {
                  storePos(ps.gates, @$);
                }
        ;

opt_gates
        : gates
        |
        ;

gates
        : gates IN gatesI ';'
        | IN  gatesI ';'
        | gates OUT gatesO ';'
        | OUT gatesO ';'
        ;

gatesI
        : gatesI ',' gateI
        | gateI
        ;

gateI
        : NAME '[' ']'
                {
                  ps.gate = addGate(ps.gates, @1);
                  ps.gate->setType(NED_GATETYPE_INPUT);
                  ps.gate->setIsVector(true);
                  storeComments(ps.gate,@1,@3);
                  storePos(ps.gate, @$);
                }
        | NAME
                {
                  ps.gate = addGate(ps.gates, @1);
                  ps.gate->setType(NED_GATETYPE_INPUT);
                  storeComments(ps.gate,@1);
                  storePos(ps.gate, @$);
                }
        ;

gatesO
        : gatesO ',' gateO
        | gateO
        ;

gateO
        : NAME '[' ']'
                {
                  ps.gate = addGate(ps.gates, @1);
                  ps.gate->setType(NED_GATETYPE_OUTPUT);
                  ps.gate->setIsVector(true);
                  storeComments(ps.gate,@1,@3);
                  storePos(ps.gate, @$);
                }
        | NAME
                {
                  ps.gate = addGate(ps.gates, @1);
                  ps.gate->setType(NED_GATETYPE_OUTPUT);
                  storeComments(ps.gate,@1,@1);
                  storePos(ps.gate, @$);
                }
        ;

/*
 * Submodules - old syntax
 */
opt_submodblock
        : submodblock
        |
        ;

submodblock
        : SUBMODULES ':'
                {
                  ps.submods = (SubmodulesNode *)createNodeWithTag(NED_SUBMODULES, ps.module );
                  storeComments(ps.submods,@1,@2);
                }
          opt_submodules
                {
                  storePos(ps.submods, @$);
                }
        ;

opt_submodules
        : submodules
        |
        ;

submodules
        : submodules submodule
        | submodule
        ;

submodule
        : NAME ':' NAME opt_semicolon
                {
                  ps.submod = (SubmoduleNode *)createNodeWithTag(NED_SUBMODULE, ps.submods);
                  ps.submod->setName(toString(@1));
                  ps.submod->setType(toString(@3));
                  storeComments(ps.submod,@1,@4);
                }
          submodule_body
                {
                  storePos(ps.submod, @$);
                }
        | NAME ':' NAME vector opt_semicolon
                {
                  ps.submod = (SubmoduleNode *)createNodeWithTag(NED_SUBMODULE, ps.submods);
                  ps.submod->setName(toString(@1));
                  ps.submod->setType(toString(@3));
                  addVector(ps.submod, "vector-size",@4,$4);
                  storeComments(ps.submod,@1,@5);
                }
          submodule_body
                {
                  storePos(ps.submod, @$);
                }
        | NAME ':' NAME LIKE NAME opt_semicolon
                {
                  ps.submod = (SubmoduleNode *)createNodeWithTag(NED_SUBMODULE, ps.submods);
                  ps.submod->setName(toString(@1));
                  ps.submod->setLikeType(toString(@5));
                  ps.submod->setLikeParam(toString(@3)); //FIXME store as expression!!!
                  storeComments(ps.submod,@1,@6);
                }
          submodule_body
                {
                  storePos(ps.submod, @$);
                }
        | NAME ':' NAME vector LIKE NAME opt_semicolon
                {
                  ps.submod = (SubmoduleNode *)createNodeWithTag(NED_SUBMODULE, ps.submods);
                  ps.submod->setName(toString(@1));
                  ps.submod->setLikeType(toString(@6));
                  ps.submod->setLikeParam(toString(@3)); //FIXME store as expression!!!
                  addVector(ps.submod, "vector-size",@4,$4);
                  storeComments(ps.submod,@1,@7);
                }
          submodule_body
                {
                  storePos(ps.submod, @$);
                }
        ;

submodule_body
        : opt_substparamblocks
          opt_gatesizeblocks
          opt_submod_displayblock
        ;

/*
 * Substparameters - old syntax
 */
opt_substparamblocks
        : substparamblocks
                { storePos(ps.substparams, @$); /*must do it here because there might be multiple (conditional) gatesizes/parameters sections */ }
        |
        ;

substparamblocks
        : substparamblocks substparamblock
        | substparamblock
        ;

substparamblock
        : PARAMETERS ':' /*FIXME empty "parameters:" in submodule doesn't get accepted! WFT??? */
                {
                  createSubstparamsNodeIfNotExists();
                  storeComments(ps.substparams,@1,@2);
                }
          opt_substparameters
                {
                }
        | PARAMETERS IF expression ':'
                {
                  // make conditional paramgroup
                  createSubstparamsNodeIfNotExists();
                  ps.substparamgroup = (ParamGroupNode *)createNodeWithTag(NED_PARAM_GROUP, ps.substparams);
                  ps.inGroup = true;
                  storeComments(ps.substparamgroup,@1,@4);
                }
          opt_substparameters
                {
                  ps.condition = (ConditionNode *)createNodeWithTag(NED_CONDITION, ps.substparamgroup);
                  addExpression(ps.condition, "condition",@3,$3);
                  storePos(ps.substparamgroup, @$);
                  ps.inGroup = false;
                }

        ;

opt_substparameters
        : substparameters ';'
        |
        ;

substparameters
        : substparameters ',' substparameter   /* comma as separator */
        | substparameter
        ;

substparameter
        : NAME '=' expression
                {
                  NEDElement *parent = ps.inGroup ? (NEDElement *)ps.substparamgroup : (NEDElement *)ps.substparams;
                  ps.substparam = addParameter(parent,@1);
                  addExpression(ps.substparam, "value",@3,$3);
                  storeComments(ps.substparam,@1,@3);
                  storePos(ps.substparam, @$);
                }
        ;

/*
 * Gatesizes - old syntax
 */
opt_gatesizeblocks
        : gatesizeblocks
                { storePos(ps.gatesizes, @$); /*must do it here because there might be multiple (conditional) gatesizes/parameters sections */ }
        |
        ;

gatesizeblocks
        : gatesizeblocks gatesizeblock
        | gatesizeblock
        ;

gatesizeblock
        : GATESIZES ':'
                {
                  createGatesizesNodeIfNotExists();
                  storeComments(ps.gatesizes,@1,@2);
                }
          opt_gatesizes
                {
                }
        | GATESIZES IF expression ':'
                {
                  // make conditional gategroup
                  createGatesizesNodeIfNotExists();
                  ps.gatesizesgroup = (GateGroupNode *)createNodeWithTag(NED_GATE_GROUP, ps.gatesizes);
                  ps.inGroup = true;
                  storeComments(ps.gatesizesgroup,@1,@4);
                }
          opt_gatesizes
                {
                  ps.condition = (ConditionNode *)createNodeWithTag(NED_CONDITION, ps.gatesizesgroup);
                  addExpression(ps.condition, "condition",@3,$3);
                  ps.inGroup = false;
                  storePos(ps.gatesizesgroup, @$);
                }
        ;

opt_gatesizes
        : gatesizes ';'
        |
        ;

gatesizes
        : gatesizes ',' gatesize
        | gatesize
        ;

gatesize
        : NAME vector
                {
                  NEDElement *parent = ps.inGroup ? (NEDElement *)ps.gatesizesgroup : (NEDElement *)ps.gatesizes;
                  ps.gatesize = addGate(parent,@1);
                  ps.gatesize->setIsVector(true);
                  addVector(ps.gatesize, "vector-size",@2,$2);
                  storeComments(ps.gatesize,@1,@2);
                  storePos(ps.gatesize, @$);
                }
        | NAME
                {
                  ps.gatesize = addGate(ps.gatesizes,@1);
                  storeComments(ps.gatesize,@1);
                  storePos(ps.gatesize, @$);
                }
        ;

/*
 * Submodule-displayblock - old syntax
 */
opt_submod_displayblock
        : DISPLAY ':' STRINGCONSTANT ';'
                {
                  ps.property = addComponentProperty(ps.submod, "display");
                  ps.substparams = (ParametersNode *)ps.submod->getFirstChildWithTag(NED_PARAMETERS); // previous line doesn't set it
                  ps.propkey = (PropertyKeyNode *)createNodeWithTag(NED_PROPERTY_KEY, ps.property);
                  LiteralNode *literal = createLiteral(NED_CONST_STRING, trimQuotes(@3), @3);
                  ps.propkey->appendChild(literal);
                  storePos(ps.propkey, @$);
                  storePos(literal, @3);
                  storePos(ps.property, @$);
                }
        |
        ;

/*
 * Connections - old syntax  (about 7 shift/reduce)
 */
opt_connblock
        : connblock
        |
        ;

connblock
        : CONNECTIONS NOCHECK ':'
                {
                  ps.conns = (ConnectionsNode *)createNodeWithTag(NED_CONNECTIONS, ps.module );
                  ps.conns->setAllowUnconnected(true);
                  storeComments(ps.conns,@1,@3);
                }
          opt_connections
                {
                  storePos(ps.conns, @$);
                }
        | CONNECTIONS ':'
                {
                  ps.conns = (ConnectionsNode *)createNodeWithTag(NED_CONNECTIONS, ps.module );
                  ps.conns->setAllowUnconnected(false);
                  storeComments(ps.conns,@1,@2);
                }
          opt_connections
                {
                  storePos(ps.conns, @$);
                }
        ;

opt_connections
        : connections
        |
        ;

connections
        : connections connection
        | connection
        ;

connection
        : loopconnection
        | notloopconnection
        ;

loopconnection
        : FOR
                {
                  ps.conngroup = (ConnectionGroupNode *)createNodeWithTag(NED_CONNECTION_GROUP, ps.conns);
                  ps.inLoop=1;
                }
          loopvarlist DO notloopconnections ENDFOR opt_semicolon
                {
                  ps.inLoop=0;
                }
        ;

loopvarlist
        : loopvar ',' loopvarlist
        | loopvar
        ;

loopvar
        : NAME '=' expression TO expression
                {
                  ps.loop = (LoopNode *)createNodeWithTag(NED_LOOP, ps.conngroup);
                  ps.loop->setParamName( toString(@1) );
                  addExpression(ps.loop, "from-value",@3,$3);
                  addExpression(ps.loop, "to-value",@5,$5);
                  storeComments(ps.loop,@1,@5);
                  storePos(ps.loop, @$);
                }
        ;

opt_conncondition
        : IF expression
                {
                  if (!ps.inLoop)
                  {
                      // add condition to conn
                      ps.condition = (ConditionNode *)createNodeWithTag(NED_CONDITION, ps.conn);
                      addExpression(ps.condition, "condition",@2,$2);
                      storePos(ps.condition, @$);
                  }
                }
        |
        ;

opt_conn_displaystr
        : DISPLAY STRINGCONSTANT
                {
                  bool hadChanSpec = ps.chanspec!=NULL;
                  if (!ps.chanspec)
                      ps.chanspec = createChannelSpec(ps.conn);
                  ps.property = addComponentProperty(ps.chanspec, "display");
                  ps.propkey = (PropertyKeyNode *)createNodeWithTag(NED_PROPERTY_KEY, ps.property);
                  LiteralNode *literal = createLiteral(NED_CONST_STRING, trimQuotes(@2), @2);
                  ps.propkey->appendChild(literal);
                  storePos(ps.propkey, @$);
                  storePos(literal, @2);
                  storePos(ps.property, @$);
                  if (!hadChanSpec)
                      storePos(ps.chanspec, @$);
                }
        |
        ;

notloopconnections
        : notloopconnections notloopconnection
        | notloopconnection
        ;

notloopconnection
        : leftgatespec RIGHT_ARROW rightgatespec opt_conncondition opt_conn_displaystr comma_or_semicolon
                {
                  ps.conn->setArrowDirection(NED_ARROWDIR_L2R);
                  storeComments(ps.conn,@1,@5);
                  storePos(ps.conn, @$);
                }
        | leftgatespec RIGHT_ARROW channeldescr RIGHT_ARROW rightgatespec opt_conncondition opt_conn_displaystr comma_or_semicolon
                {
                  ps.conn->setArrowDirection(NED_ARROWDIR_L2R);
                  removeRedundantChanSpecParams();
                  storeComments(ps.conn,@1,@7);
                  storePos(ps.conn, @$);
                }
        | leftgatespec LEFT_ARROW rightgatespec opt_conncondition opt_conn_displaystr comma_or_semicolon
                {
                  swapConnection(ps.conn);
                  ps.conn->setArrowDirection(NED_ARROWDIR_R2L);
                  storeComments(ps.conn,@1,@5);
                  storePos(ps.conn, @$);
                }
        | leftgatespec LEFT_ARROW channeldescr LEFT_ARROW rightgatespec opt_conncondition opt_conn_displaystr comma_or_semicolon
                {
                  swapConnection(ps.conn);
                  ps.conn->setArrowDirection(NED_ARROWDIR_R2L);
                  removeRedundantChanSpecParams();
                  storeComments(ps.conn,@1,@7);
                  storePos(ps.conn, @$);
                }
        ;

leftgatespec
        : leftmod '.' leftgate
        | parentleftgate
        ;

leftmod
        : NAME vector
                {
                  ps.conn = (ConnectionNode *)createNodeWithTag(NED_CONNECTION, ps.inLoop ? (NEDElement *)ps.conngroup : (NEDElement*)ps.conns );
                  ps.conn->setSrcModule( toString(@1) );
                  addVector(ps.conn, "src-module-index",@2,$2);
                  ps.chanspec = NULL;   // signal that there's no chanspec for this conn yet
                }
        | NAME
                {
                  ps.conn = (ConnectionNode *)createNodeWithTag(NED_CONNECTION, ps.inLoop ? (NEDElement *)ps.conngroup : (NEDElement*)ps.conns );
                  ps.conn->setSrcModule( toString(@1) );
                  ps.chanspec = NULL;   // signal that there's no chanspec for this conn yet
                }
        ;

leftgate
        : NAME vector
                {
                  ps.conn->setSrcGate( toString( @1) );
                  addVector(ps.conn, "src-gate-index",@2,$2);
                }
        | NAME
                {
                  ps.conn->setSrcGate( toString( @1) );
                }
        | NAME PLUSPLUS
                {
                  ps.conn->setSrcGate( toString( @1) );
                  ps.conn->setSrcGatePlusplus(true);
                }
        ;

parentleftgate
        : NAME vector
                {
                  ps.conn = (ConnectionNode *)createNodeWithTag(NED_CONNECTION, ps.inLoop ? (NEDElement *)ps.conngroup : (NEDElement*)ps.conns );
                  ps.conn->setSrcModule("");
                  ps.conn->setSrcGate(toString(@1));
                  addVector(ps.conn, "src-gate-index",@2,$2);
                  ps.chanspec = NULL;   // signal that there's no chanspec for this conn yet
                }
        | NAME
                {
                  ps.conn = (ConnectionNode *)createNodeWithTag(NED_CONNECTION, ps.inLoop ? (NEDElement *)ps.conngroup : (NEDElement*)ps.conns );
                  ps.conn->setSrcModule("");
                  ps.conn->setSrcGate(toString(@1));
                  ps.chanspec = NULL;   // signal that there's no chanspec for this conn yet
                }
        | NAME PLUSPLUS
                {
                  ps.conn = (ConnectionNode *)createNodeWithTag(NED_CONNECTION, ps.inLoop ? (NEDElement *)ps.conngroup : (NEDElement*)ps.conns );
                  ps.conn->setSrcModule("");
                  ps.conn->setSrcGate(toString(@1));
                  ps.conn->setSrcGatePlusplus(true);
                  ps.chanspec = NULL;   // signal that there's no chanspec for this conn yet
                }
        ;

rightgatespec
        : rightmod '.' rightgate
        | parentrightgate
        ;

rightmod
        : NAME vector
                {
                  ps.conn->setDestModule( toString(@1) );
                  addVector(ps.conn, "dest-module-index",@2,$2);
                }
        | NAME
                {
                  ps.conn->setDestModule( toString(@1) );
                }
        ;

rightgate
        : NAME vector
                {
                  ps.conn->setDestGate( toString( @1) );
                  addVector(ps.conn, "dest-gate-index",@2,$2);
                }
        | NAME
                {
                  ps.conn->setDestGate( toString( @1) );
                }
        | NAME PLUSPLUS
                {
                  ps.conn->setDestGate( toString( @1) );
                  ps.conn->setDestGatePlusplus(true);
                }
        ;

parentrightgate
        : NAME vector
                {
                  ps.conn->setDestGate( toString( @1) );
                  addVector(ps.conn, "dest-gate-index",@2,$2);
                }
        | NAME
                {
                  ps.conn->setDestGate( toString( @1) );
                }
        | NAME PLUSPLUS
                {
                  ps.conn->setDestGate( toString( @1) );
                  ps.conn->setDestGatePlusplus(true);
                }
        ;


channeldescr
        : channelattrs
                {
                  storePos(ps.chanspec, @$);
                  if (ps.chanspec->getFirstChildWithTag(NED_PARAMETERS)!=NULL)
                      storePos(ps.params, @$);
                }
        ;

channelattrs
        : NAME
                {
                  if (!ps.chanspec)
                      ps.chanspec = createChannelSpec(ps.conn);
                  ps.chanspec->setType(toString(@1));
                }
        | chanattr
        | channelattrs chanattr
        ;

chanattr
        : CHANATTRNAME expression
                {
                  if (!ps.chanspec)
                      ps.chanspec = createChannelSpec(ps.conn);
                  ps.param = addParameter(ps.params, @1);
                  addExpression(ps.param, "value",@2,$2);
                  storePos(ps.param, @$);
                }
        ;

/*
 * Network - old syntax
 */
networkdefinition
        : networkheader
            opt_substparamblocks
          endnetwork
                { storePos(ps.module, @$); }
        ;

networkheader
        : NETWORK NAME ':' NAME opt_semicolon
                {
                  ps.module = (CompoundModuleNode *)createNodeWithTag(NED_COMPOUND_MODULE, ps.nedfile );
                  ((CompoundModuleNode *)ps.module)->setName(toString(@2));
                  ((CompoundModuleNode *)ps.module)->setIsNetwork(true);
                  ps.extends = (ExtendsNode *)createNodeWithTag(NED_EXTENDS, ps.module);
                  ps.extends->setName(toString(@4));
                  storeComments(ps.module,@1,@5);
                  storePos(ps.extends, @4);
                  ps.inNetwork=1;
                }
        ;

endnetwork
        : ENDNETWORK opt_semicolon
                {
                  //setTrailingComment(ps.module,@1);
                  ps.inNetwork=0;
                }
        ;

/*
 * Common part
 */
vector
        : '[' expression ']'
                { $$ = $2; }
        ;

expression
        :
          expr
                {
                  if (np->getParseExpressionsFlag()) $$ = createExpression($1);
                }
        | inputvalue
                {
                  if (np->getParseExpressionsFlag()) $$ = createExpression($1);
                }
        | xmldocvalue
                {
                  if (np->getParseExpressionsFlag()) $$ = createExpression($1);
                }
        ;

/*
 * Expressions (3 shift-reduce conflicts here)
 */

inputvalue  /* FIXME turn to isDefault=true, @prompt!!! */
        : INPUT_ '(' expr ',' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("input_OLDXXX", $3, $5); }
        | INPUT_ '(' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("input_OLDXXX", $3); }
        | INPUT_ '(' ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("input_OLDXXX"); }
        | INPUT_
                { if (np->getParseExpressionsFlag()) $$ = createFunction("input_OLDXXX"); }
        ;

xmldocvalue
        : XMLDOC '(' stringliteral ',' stringliteral ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("xmldoc", $3, $5); }
        | XMLDOC '(' stringliteral ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("xmldoc", $3); }
        ;

expr
        : simple_expr
        | '(' expr ')'
                { $$ = $2; }

        | expr '+' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("+", $1, $3); }
        | expr '-' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("-", $1, $3); }
        | expr '*' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("*", $1, $3); }
        | expr '/' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("/", $1, $3); }
        | expr '%' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("%", $1, $3); }
        | expr '^' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("^", $1, $3); }

        | '-' expr
                %prec UMIN
                { if (np->getParseExpressionsFlag()) $$ = unaryMinus($2); }

        | expr EQ expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("==", $1, $3); }
        | expr NE expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("!=", $1, $3); }
        | expr GT expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator(">", $1, $3); }
        | expr GE expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator(">=", $1, $3); }
        | expr LS expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("<", $1, $3); }
        | expr LE expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("<=", $1, $3); }

        | expr AND expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("&&", $1, $3); }
        | expr OR expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("||", $1, $3); }
        | expr XOR expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("##", $1, $3); }

        | NOT expr
                %prec UMIN
                { if (np->getParseExpressionsFlag()) $$ = createOperator("!", $2); }

        | expr BIN_AND expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("&", $1, $3); }
        | expr BIN_OR expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("|", $1, $3); }
        | expr BIN_XOR expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("#", $1, $3); }

        | BIN_COMPL expr
                %prec UMIN
                { if (np->getParseExpressionsFlag()) $$ = createOperator("~", $2); }
        | expr SHIFT_LEFT expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("<<", $1, $3); }
        | expr SHIFT_RIGHT expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator(">>", $1, $3); }
        | expr '?' expr ':' expr
                { if (np->getParseExpressionsFlag()) $$ = createOperator("?:", $1, $3, $5); }

        | NAME '(' ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction(toString(@1)); }
        | NAME '(' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction(toString(@1), $3); }
        | NAME '(' expr ',' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction(toString(@1), $3, $5); }
        | NAME '(' expr ',' expr ',' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction(toString(@1), $3, $5, $7); }
        | NAME '(' expr ',' expr ',' expr ',' expr ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction(toString(@1), $3, $5, $7, $9); }
         ;

simple_expr
        : parameter_expr
        | special_expr
        | literal
        ;

parameter_expr
        : NAME
                {
                  // if there's no modifier, might be a loop variable too
                  if (np->getParseExpressionsFlag()) $$ = createIdent(@1);
                }
        | REF NAME
                {
                  if (np->getParseExpressionsFlag()) $$ = createIdent(@2);
                  np->getErrors()->add(ps.substparams,"`ref' modifier no longer supported (add `function' "
                                     "modifier to destination parameter instead)");
                }
        | REF ANCESTOR NAME
                {
                  if (np->getParseExpressionsFlag()) $$ = createIdent(@3);
                  np->getErrors()->add(ps.substparams,"`ancestor' and `ref' modifiers no longer supported");
                }
        | ANCESTOR REF NAME
                {
                  if (np->getParseExpressionsFlag()) $$ = createIdent(@3);
                  np->getErrors()->add(ps.substparams,"`ancestor' and `ref' modifiers no longer supported");
                }
        | ANCESTOR NAME
                {
                  if (np->getParseExpressionsFlag()) $$ = createIdent(@2);
                  np->getErrors()->add(ps.substparams,"`ancestor' modifier no longer supported");
                }
        ;

special_expr
        : SUBMODINDEX
                { if (np->getParseExpressionsFlag()) $$ = createFunction("index"); }
        | SUBMODINDEX '(' ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("index"); }
        | SIZEOF '(' NAME ')'
                { if (np->getParseExpressionsFlag()) $$ = createFunction("sizeof", createIdent(@3)); }
        ;

literal
        : stringliteral
        | boolliteral
        | numliteral
        ;

stringliteral
        : STRINGCONSTANT
                { if (np->getParseExpressionsFlag()) $$ = createLiteral(NED_CONST_STRING, trimQuotes(@1), @1); }
        ;

boolliteral
        : TRUE_
                { if (np->getParseExpressionsFlag()) $$ = createLiteral(NED_CONST_BOOL, @1, @1); }
        | FALSE_
                { if (np->getParseExpressionsFlag()) $$ = createLiteral(NED_CONST_BOOL, @1, @1); }
        ;

numliteral
        : INTCONSTANT
                { if (np->getParseExpressionsFlag()) $$ = createLiteral(NED_CONST_INT, @1, @1); }
        | REALCONSTANT
                { if (np->getParseExpressionsFlag()) $$ = createLiteral(NED_CONST_DOUBLE, @1, @1); }
        | quantity
                { if (np->getParseExpressionsFlag()) $$ = createQuantity(toString(@1)); }
        ;

quantity
        : quantity INTCONSTANT NAME
        | quantity REALCONSTANT NAME
        | INTCONSTANT NAME
        | REALCONSTANT NAME
        ;

opt_semicolon : ';' | ;

comma_or_semicolon : ',' | ';' ;

%%

//----------------------------------------------------------------------
// general bison/flex stuff:
//

NEDElement *doParseNED1(NEDParser *p, const char *nedtext)
{
#if YYDEBUG != 0      /* #if added --VA */
    yydebug = YYDEBUGGING_ON;
#endif

    // reset the lexer
    pos.co = 0;
    pos.li = 1;
    prevpos = pos;

    yyin = NULL;
    yyout = stderr; // not used anyway

    // alloc buffer
    struct yy_buffer_state *handle = yy_scan_string(nedtext);
    if (!handle)
        {np->getErrors()->add(NULL, "unable to allocate work memory"); return false;}

    // create parser state and NEDFileNode
    np = p;
    resetParserState();
    ps.nedfile = new NedFileNode();

    // store file name with slashes always, even on Windows -- neddoc relies on that
    ps.nedfile->setFilename(slashifyFilename(np->getFileName()).c_str());
    ps.nedfile->setVersion("1");

    // store file comment
    storeFileComment(ps.nedfile);

    if (np->getStoreSourceFlag())
        storeSourceCode(ps.nedfile, np->getSource()->getFullTextPos());

    // parse
    int ret;
    try
    {
        ret = yyparse();
    }
    catch (NEDException *e)
    {
        INTERNAL_ERROR1(NULL, "error during parsing: %s", e->errorMessage());
        yy_delete_buffer(handle);
        delete e;
        return 0;
    }

    yy_delete_buffer(handle);

    //FIXME TODO: fill in @documentation properties from comments
    return ps.nedfile;
}

void yyerror(const char *s)
{
    // chop newline
    char buf[250];
    strcpy(buf, s);
    if (buf[strlen(buf)-1] == '\n')
        buf[strlen(buf)-1] = '\0';

    np->error(buf, pos.li);
}

// this function depends too much on ps, cannot be put into nedyylib.cc
ChannelSpecNode *createChannelSpec(NEDElement *conn)
{
   ChannelSpecNode *chanspec = (ChannelSpecNode *)createNodeWithTag(NED_CHANNEL_SPEC, ps.conn);
   ps.params = (ParametersNode *)createNodeWithTag(NED_PARAMETERS, chanspec);
   ps.params->setIsImplicit(true);
   return chanspec;
}

void createSubstparamsNodeIfNotExists()
{
   // check if already exists (multiple blocks must be merged)
   NEDElement *parent = ps.inNetwork ? (NEDElement *)ps.module : (NEDElement *)ps.submod;
   ps.substparams = (ParametersNode *)parent->getFirstChildWithTag(NED_PARAMETERS);
   if (!ps.substparams)
       ps.substparams = (ParametersNode *)createNodeWithTag(NED_PARAMETERS, parent);
}

void createGatesizesNodeIfNotExists()
{
   // check if already exists (multiple blocks must be merged)
   ps.gatesizes = (GatesNode *)ps.submod->getFirstChildWithTag(NED_GATES);
   if (!ps.gatesizes)
       ps.gatesizes = (GatesNode *)createNodeWithTag(NED_GATES, ps.submod);
}

void removeRedundantChanSpecParams()
{
    if (ps.chanspec && !ps.params->getFirstChild())
        delete ps.chanspec->removeChild(ps.params);
}

