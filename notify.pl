eval 'exec perl -wS $0 ${1+"$@"}'
  if 0;

#-------------------------------------------------------------------------------------------------
# Letzte Aenderung:     $Date: $
#                       $Revision: $
#                       $Author: $
#
# Aufgabe:		- Notify via Prowl und NMA
#
#-------------------------------------------------------------------------------------------------

use v5.10;
use strict;
use vars qw($VERSION $SVN);

use lib 'C:\Users\forex\workspace\Framework\lib';

use constant SVN_ID => '($Id: $)

$Author: $ 

$Revision: $ 
$Date: $ 
';

# Extraktion der Versionsinfo aus der SVN Revision
($VERSION = SVN_ID) =~ s/^(.*\$Revision: )([0-9]*)(.*)$/1.0 R$2/ms;
$SVN = $VERSION . ' ' . SVN_ID;

$| = 1;

use FindBin qw($Bin $Script $RealBin $RealScript);
use lib $Bin . "/lib";
use lib $Bin . "/lib/NOTIFY";

#
# Module
#
use CmdLine;
use Trace;
use Configuration;
use DBAccess;

use Schedule::Cron;

use diagnostics;

use NOTIFY;
# use NOTIFY::Modul1;
# use NOTIFY::Modul2;

use Fcntl;

#
# Variablendefinition
#

#
# Objektdefinition
#

# Option-Objekt: Liest und speichert die Kommandozeilenparameter
$VERSION = CmdLine->new('Service'     => 'webservice:s',
                        'Application' => 'application:s',
                        'Event'       => 'event:s',
                        'Comment'     => 'comment:s',
                        'Prio'        => 'priority:s',
                        'User'        => 'user:s',
                        'APIKey'      => 'key:s',
                        'Group'       => 'group:s',
                        'Flag'        => 'flag:s')->version($VERSION);

# Trace-Objekt: Liest und speichert die Meldungstexte; gibt Tracemeldungen aus
$VERSION = Trace->new()->version($VERSION);

# Config-Objekt: Liest und speichert die Initialisierungsdatei
$VERSION = Configuration->new()->version($VERSION);

# Datenbank-Objekt: Regelt dei Datenbankzugriffe
# $VERSION = DBAccess->new()->version($VERSION);

# Kopie des Fehlerkanals erstellen zur gelegentlichen Abschaltung
no warnings;
sysopen(MYERR, "&STDERR", O_WRONLY);
use warnings;

#
#################################################################
## main
##################################################################
#
my $prg;
eval {$prg = NOTIFY->new()};
if ($@) {
  Trace->Exit(0, 1, 0x0ffff, Configuration->config('Prg', 'Name'), $VERSION);
}
$VERSION = $prg->version($VERSION);

my ($type, $app, $event, $desc, $prio, $user, $key, @types, %users, $group, $flag);
@types = defined(CmdLine->option('Service'))     ? CmdLine->option('Service')     : ('Prowl', 'NMA'); 
$event = defined(CmdLine->option('Event'))       ? CmdLine->option('Event')       : 'Testbenachrichtigung';
$desc  = defined(CmdLine->option('Comment'))     ? CmdLine->option('Comment')     : 'Bislang keine weiteren Details';
$prio  = defined(CmdLine->option('Prio'))        ? CmdLine->option('Prio')        : 1; 
$user  = defined(CmdLine->option('User'))        ? CmdLine->option('User')        : undef; 
$key   = defined(CmdLine->option('APIKey'))      ? CmdLine->option('APIKey')      : undef; 
$group = defined(CmdLine->option('Group'))       ? CmdLine->option('Group')       : undef; 
$flag  = defined(CmdLine->option('Flag'))        ? CmdLine->option('Flag')        : undef; 

foreach $type (@types) {
  if (defined($type)) {
    $app = defined(CmdLine->option('Application')) ? CmdLine->option('Application') : "Notifytest $type";
    if (defined($user) && defined(Configuration->config($type, $user))) {
      %users = ($user => Configuration->config($type, $user));
    } else {
      %users = Configuration->config($type);
    }
  } else {
    %users = {};
  }
  $prg->sendNotification(Type        => $type,
                         Application => $app,
                         Event       => $event,
                         Description => $desc,
                         Priority    => $prio,
                         URL         => 'https://github.com/pgk69',
                         Users       => \%users,
                         Key         => $key,
                         Group       => $group,
                         Flag        => $flag);
}

Trace->Exit(0, 1, 0x00002, Configuration->config('Prg', 'Name'), $VERSION);

exit 1;
