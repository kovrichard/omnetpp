//==========================================================================
// nedcompiler.h - part of the OMNeT++ Discrete System Simulation System
//
// Contents:
//   class NEDCompiler
//
//==========================================================================

/*--------------------------------------------------------------*
  Copyright (C) 2002 Andras Varga

  This file is distributed WITHOUT ANY WARRANTY. See the file
  `license' for details on this and other legal matters.
*--------------------------------------------------------------*/


#ifndef __NEDCOMPILER_H
#define __NEDCOMPILER_H

#include <map>
#include <vector>
#include <string>
#include "nedelements.h"


struct ltstr
{
  bool operator()(const char* s1, const char* s2) const  {return strcmp(s1,s2)<0;}
};
typedef std::map<const char *,NEDElement *,ltstr> NEDMap;

typedef std::vector<std::string> NEDStringVector;


/**
 * Caches NED files already loaded. To be used with NEDCompiler.
 * A NEDFileCache instance can be reused when compiling several
 * independent files in a row.
 *
 * @ingroup NEDCompiler
 */
class NEDFileCache
{
  protected:
    NEDMap importedfiles;

  public:
    NEDFileCache();
    ~NEDFileCache();
    void addFile(const char *name, NEDElement *node);
    NEDElement *getFile(const char *name);
};


/**
 * For fast lookup of module, channel, etc names. To be used with NEDCompiler.
 * Typically a new instance is needed for each NEDCompiler invocation.
 *
 * @ingroup NEDCompiler
 */
class NEDSymbolTable
{
  protected:
    // hash tables for channel, module and network declarations:
    NEDMap channels;
    NEDMap modules;
    NEDMap networks;

    // subclassing: enums, classes, messages, objects
    NEDMap enums;
    NEDMap classes;

  public:
    NEDSymbolTable();
    ~NEDSymbolTable();

    void add(NEDElement *node);
    NEDElement *getChannelDeclaration(const char *name);
    NEDElement *getModuleDeclaration(const char *name);
    NEDElement *getNetworkDeclaration(const char *name);
    NEDElement *getEnumDeclaration(const char *name);
    NEDElement *getClassDeclaration(const char *name);
};


/**
 * Abstract interface for loading NED imports; to be used with NEDCompiler.
 *
 * @ingroup NEDCompiler
 */
class NEDImportResolver
{
  public:
    NEDImportResolver() {}
    virtual ~NEDImportResolver() {}
    virtual NEDElement *loadImport(const char *import) = 0;
};


/**
 * Importresolver for NED-I; to be used with NEDCompiler.
 * A NEDClassicImportResolver instance can be reused when compiling several
 * independent files in a row.
 *
 * @ingroup NEDCompiler
 */
class NEDClassicImportResolver : public NEDImportResolver
{
  protected:
    NEDStringVector importpath;
  public:
    NEDClassicImportResolver() {}
    virtual ~NEDClassicImportResolver() {}
    void addImportPath(const char *dir);
    virtual NEDElement *loadImport(const char *import);
};


/**
 * Manages the "middle" part of the compilation process for NED.
 * The process actually involves DTD and syntactic validation of the input,
 * loading (and recursively validating) imports, and semantically validating
 * the input (if module types exist, etc.).
 *
 * NEDCompiler does _not_ do parsing (only for the imports, via the importresolver,
 * but the main file it already receives a NED object tree form).
 * Code (i.e. C++) generation is also not covered.
 *
 * @ingroup NEDCompiler
 */
class NEDCompiler
{
  protected:
    NEDMap imports;  // list of already imported modules (to avoid double importing)

    NEDFileCache *filecache;
    NEDSymbolTable *symboltable;
    NEDImportResolver *importresolver;

    void addImport(const char *name);
    bool isImported(const char *name);
    void doValidate(NEDElement *tree);

  public:
    NEDCompiler(NEDFileCache *fcache, NEDSymbolTable *symtab, NEDImportResolver *importres);
    virtual ~NEDCompiler();

    void validate(NEDElement *tree);
};

#endif

