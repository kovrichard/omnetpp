#
# opp_test.pl: simple testing tool for OMNeT++ regression tests
#

#
# TODO/FIXME:
#  - some errors are handled with exit(), others with unresolved() :-(((
#  - more powerful tests, not only %contains and %not-contains
#

#
# If no args, print usage
#
$Usage = 'OMNeT++ Regression Test Tool, 2002
Syntax: opp_test [-g|-r] [-v] [-V] [-d <dir>] <testfile> ...
  -g         generate files
  -r         run test
  -v         verbose
  -V         very verbose (debug)
  -d <dir>   working directory (defaults to `work\')
  -s <prog>  shell to use to run test program
  -p <prog>  name of test program (defaults to name of working directory)

Usage in nutshell:
   1. create *.test files
   2. run opp_test with -g option to generate the source files from *.test
   3. create a makefile (opp_makemake) and build the test program
   4. run opp_test with -r option to execute the tests

All files will be created in the working directory.

';

#
# templates, variables
#
$NEDTemplate = '
simple @TNAME@
endsimple

network @TNAME@_network : @TNAME@
endnetwork
';

$CPPTemplate = '
#include "omnetpp.h"

class @TNAME@ : public cSimpleModule
{
    Module_Class_Members(@TNAME@,cSimpleModule,16384)
    virtual void activity();
};

Define_Module(@TNAME@);

void @TNAME@::activity()
{
@TESTCODE@
}
';

$INITemplate = '
[General]
network=@TNAME@_network
output-vector-file = @TNAME@.vec
output-scalar-file = @TNAME@.sca
';


# legend: 1=once, v=has value, b=has body, f=value is filename
%Entries = (
    'name'             => '1v',
    'description'      => '1b',
    'source'           => '1b',
    'file'             => 'vbf',
    'inifile'          => '1vbf',
    'contains'         => 'vbf',
    'not-contains'     => 'vbf',
    'exitcode'         => '1v',
    'ignore-exitcode'  => '1v'
);

#
#  Parse the command line for options and files.
#
@filenames = ();
$mode='';
$workingdir = 'work';
$shell='/bin/sh';
$testprogram='';
$verbose=0;
$debug=0;

if ($#ARGV == -1)
{
    print $Usage;
    exit(1);
}

while (@ARGV)
{
    $arg = shift @ARGV;

    if ($arg eq "-v") {
        $verbose=1;
    }
    elsif ($arg eq "-V") {
        $debug=1;
    }
    elsif ($arg eq "-d") {
        $workingdir = shift @ARGV;
    }
    elsif ($arg eq "-s") {
        $shell = shift @ARGV;
    }
    elsif ($arg eq "-p") {
        $testprogram = shift @ARGV;
    }
    elsif ($arg eq "-g") {
        $mode='gen';
    }
    elsif ($arg eq "--generate-files") {
        $mode='gen';
    }
    elsif ($arg eq "-r") {
        $mode='run';
    }
    elsif ($arg eq "--run") {
        $mode='run';
    }
    elsif ($arg =~ /^-/) {
        print $Usage;
        exit(1);
    }
    else {
        push(@filenames,$arg);
    }
}

if ($mode eq '')
{
    print $Usage;
    exit(1);
}

# test existence of working directory
if (! -d $workingdir) {
    print stderr "error: working directory `$workingdir' does not exist\n";
    exit(1);
}

# produce name of test program
if ($testprogram eq '') {

    if ($ENV{'OS'} =~ /windows/i) {
      $exesuffix='.exe';
    } else {
      $exesuffix='';
    }

    $workingdir =~ /([^\/\\]*)$/;
    $testprogram = $1.$exesuffix;
}

#
# generate test files
#
if ($mode eq 'gen')
{
    foreach $testfilename (@filenames)
    {
        testcase_create($testfilename);
    }
}

#
# run tests
#
if ($mode eq 'run')
{
    $num_pass=0;
    $num_fail=0;
    $num_unresolved=0;

    foreach $testfilename (@filenames)
    {
        testcase_run($testfilename);
    }

    print "========================================\n";
    print "PASS: $num_pass   FAIL: $num_fail   UNRESOLVED: $num_unresolved\n";
}

sub parse_testfile
{
    my $testfilename = shift;

    undef %bodies;
    undef %values;
    undef %count;

    print "  parsing $testfilename\n" if ($debug);

    # read test file
    if (!open(IN,$testfilename)) {
        unresolved($testfilename,"cannot open test file `$testfilename'");
        return;
    }
    $txt = '';
    while (<IN>)
    {
        s/[\r\n]*$//;
        $txt.= $_."\n";
    }
    close(IN);

    # parse along "%foo:" lines
    $txt .= "\n\%:\n";  # add sentry
    while ($txt =~ s/%([^\s]*):[ \t]*(.*?)[ \t]*\n(.*?\n)(%[^\s]*:)/\4/s)
    {
        $key = $1;
        $value =$2;
        $body = $3;

        $count{$key}++;
        $key_index = $key.'('.$count{$key}.')';
        $values{$key_index}=$value;
        $bodies{$key_index}=$body;
    }

    # check entries
    foreach $key_index (keys(%values))
    {
        $key_index =~ /(.*)\((.*)\)/;
        $key = $1;
        $index = $2;
        $desc = $Entries{$key};
        if ($desc eq '') {
            unresolved($testfilename, "error in test file: invalid entry %$key"); return;
        }
        if ($desc =~ /1/ && $index>1) {
            unresolved($testfilename, "error in test file: entry %$key should occur only once."); return;
        }
        if ($desc =~ /v/ && $values{$key_index} =~ /^\s*$/) {
            unresolved($testfilename, "error in test file: entry %$key expects value after ':'"); return;
        }
        if (!$desc =~ /v/ && !$values{$key_index} =~ /\s*/) {
            unresolved($testfilename, "error in test file: entry %$key expects nothing after ':'"); return;
        }
        if (!$desc =~ /b/ && !$bodies{$key_index} =~ /\s*/) {
            unresolved($testfilename, "error in test file: entry %$key expects no body"); return;
        }
    }

    # substitute TNAME and other macros, kill comments
    $testname = $values{'name(1)'};
    foreach $key (keys(%values))
    {
        $values{$key} =~ s/\@TNAME\@/$testname/g;
        $bodies{$key} =~ s/\@TNAME\@/$testname/g;
        $bodies{$key} =~ s/^%#.*?$//mg;
    }
}

sub testcase_create
{
    my $testfilename = shift;

    parse_testfile($testfilename);

    print "  generating files for `$testfilename':\n" if ($debug);

    # source files
    foreach $key (keys(%values))
    {
        if ($key =~ /^file\b/)
        {
            # write out file
            $outfname = $workingdir."/".$values{$key};
            writefile($outfname, $bodies{$key});
        }
    }

    # code fragment
    $testcode = $bodies{'source(1)'};
    if ($testcode ne '')
    {
        $testcode = $bodies{'source(1)'};

        # generate wrapper simple module
        $ned = $NEDTemplate;
        $ned =~ s/\@TNAME\@/$testname/g;
        $nedfname = $workingdir."/".$testname.'.ned';
        writefile($nedfname, $ned);

        $cpp = $CPPTemplate;
        $cpp =~ s/\@TNAME\@/$testname/g;
        $cpp =~ s/\@TESTCODE\@/$testcode/g;
        $cppfname = $workingdir."/".$testname.'.cc';
        writefile($cppfname, $cpp);
    }

    # ini file
    $inifname = $values{'inifile(1)'};
    if ($inifname eq '') {
        $inifname = $testname.'.ini';
    }
    $inifname = $workingdir."/".$inifname;

    $inifile = $bodies{'inifile(1)'};
    if ($inifile =~ /^\s*$/s)
    {
        $inifile = $INITemplate;
        $inifile =~ s/\@TNAME\@/$testname/g;
    }
    writefile($inifname, $inifile);
}

sub testcase_run()
{
    my $testfilename = shift;

    parse_testfile($testfilename);

    $outfname = $workingdir.'/'.$testname.'.out';
    $errfname = $workingdir.'/'.$testname.'.err';

    # delete temp files before running the test case
    foreach $key (keys(%values))
    {
        if ($key =~ /^contains\b/ || $key =~ /^not-contains\b/)
        {
            # read file
            if ($values{$key} eq 'stdout') {
                $infname = $outfname;
            }
            elsif ($values{$key} eq 'stderr') {
                $infname = $errfname;
            }
            else {
                $infname = $values{$key};
            }

            if (-f $infname) {
                print "  deleting old copy of file `$infname'\n" if ($debug);
                unlink $workingdir.'/'.$infname;
            }
        }
    }

    # ini file
    $inifname = $values{'inifile(1)'};
    if ($inifname eq '') {
        $inifname = $testname.'.ini';
    }

    # run the program
    print "  running: $shell -c 'cd $workingdir && $testprogram -f $inifname' >$outfname 2>$errfname\n" if ($debug);
    $status = system ("$shell -c 'cd $workingdir && $testprogram -f $inifname' >$outfname 2>$errfname");
    if ($status ne '0') {
        if (256*int($status/256) != $status) {
            unresolved($testfilename, "could not execute test program, exit code: $status");
            return;
        } else {
            $status = $status/256;
            if ($values{'ignore-exitcode(1)'}) {
                print "  ignoring exitcode\n" if ($debug);
            } elsif ($status == $values{'exitcode(1)'}) {
                print "  exitcode ok ($status)\n" if ($debug);
            } elsif ($values{'exitcode(1)'} ne '') {
                fail($testfilename, "test program returned exit code $status instead of $values{'exitcode(1)'}");
                return;
            } else {
                fail($testfilename, "test program returned nonzero exit code: $status");
                return;
            }
        }
    }

    # check output files
    foreach $key (keys(%values))
    {
        if ($key =~ /^contains\b/ || $key =~ /^not-contains\b/)
        {
            # read file
            if ($values{$key} eq 'stdout') {
                $infname = $outfname;
            }
            elsif ($values{$key} eq 'stderr') {
                $infname = $errfname;
            }
            else {
                $infname = $workingdir."/".$values{$key};
            }

            print "  checking $infname\n" if ($debug);

            if (!open(IN,"$infname")) {
                fail($testfilename, "cannot read test case output file `$infname'");
                return;
            }
            $txt = '';
            while (<IN>)
            {
                s/[\r\n]*$//;
                $txt.= $_."\n";
            }
            close IN;

            # get pattern
            $pattern = $bodies{$key};
            $pattern =~ s/^\s*(.*?)\s*$/\1/s; # trim pattern

            # check contains or not-contains
            if ($key =~ /^contains\b/) {
                if (!($txt =~ /$pattern/m)) {
                   fail($testfilename, "$values{$key} fails %contains rule");
                   if (length($txt)<=8192) {
                      print "expected pattern:\n>>>>$pattern<<<<\nactual output:\n>>>>$txt<<<<\n" if ($verbose);
                   } else {
                      print "expected pattern:\n>>>>$pattern<<<<\nactual output too big to dump (>8K)\n" if ($verbose);
                   }
                   return;
                }
            }
            if ($key =~ /^not-contains\b/) {
                if ($txt =~ /$pattern/m) {
                   fail($testfilename, "$values{$key} fails %not-contains rule");
                   if (length($txt)<=8192) {
                      print "expected pattern:\n>>>>$pattern<<<<\nactual output:\n>>>>$txt<<<<\n" if ($verbose);
                   } else {
                      print "expected pattern:\n>>>>$pattern<<<<\nactual output too big to dump (>8K)\n" if ($verbose);
                   }
                   return;
                }
            }
        }
    }
    pass($testfilename);
}

sub unresolved()
{
    my $testname = shift;
    my $reason = shift;
    $num_unresolved++;
    $result{$testname} = 'UNRESOLVED';
    $reason{$testname} = $reason;
    print "*** $testname: UNRESOLVED ($reason)\n";
}

sub fail()
{
    my $testname = shift;
    my $reason = shift;
    $num_fail++;
    $result{$testname} = 'FAIL';
    $reason{$testname} = $reason;
    print "*** $testname: FAIL ($reason)\n";
}

sub pass()
{
    my $testname = shift;
    $num_pass++;
    $result{$testname} = 'PASS';
    $reason{$testname} = '';
    print "*** $testname: PASS\n";
}

sub writefile()
{
    my $fname = shift;
    my $content = shift;

    # write file but preserve file date if it already existed with identical contents
    # (to speed up make process)

    my $skipwrite = 0;
    if (-r $fname) {
       if (!open(IN,$fname)) {
            print stderr "error: cannot read file `$fname'\n";
            exit(1);
       }
       my $oldcontent = '';
       while (<IN>)
       {
            s/[\r\n]*$//;
            $oldcontent.= $_."\n";
       }
       close(IN);

       if ($content eq $oldcontent) {
            $skipwrite = 1;
       }
    }

    if ($skipwrite) {
       print "  file `$fname' already exists with identical content\n" if ($debug);
    } else {
       print "  writing `$fname'\n" if ($debug);
       if (!open(OUT,">$fname")) {
          print stderr "error: cannot write file `$fname'\n";
          exit(1);
       }
       print OUT $content;
       close OUT;
    }
}


