package NOTIFY;

#-------------------------------------------------------------------------------------------------
# Letzte Aenderung:     $Date: $
#                       $Revision: $
#                       $Author: $
#
# Aufgabe:		- Ausfuehrbarer Code von notify.pl
#
# $Id: $
#-------------------------------------------------------------------------------------------------

use v5.10;
use strict;
use vars qw($VERSION $SVN $OVERSION);

use constant SVN_ID => '($Id: $)

$Author: $ 

$Revision: $ 
$Date: $ 
';

($VERSION = SVN_ID) =~ s/^(.*\$Revision: )([0-9]*)(.*)$/1.0 R$2/ms;
$SVN      = $VERSION . ' ' . SVN_ID;
$OVERSION = $VERSION;

use base 'Exporter';

our @EXPORT    = ();
our @EXPORT_OK = ();

use vars @EXPORT, @EXPORT_OK;

use vars qw(@ISA);
@ISA = qw();

use Trace;
use CmdLine;
use Configuration;
use Utils;

#
# Module
#
use FindBin qw($Bin $Script $RealBin $RealScript);
use Storable;
use WebService::Prowl;
use WebService::NotifyMyAndroid;

#
# Konstantendefinition
#

#
# Variablendefinition
#

#
# Methodendefinition
#
sub version {
  my $self     = shift();
  my $pversion = shift();

  $OVERSION =~ m/^([^\s]*)\sR([0-9]*)$/;
  my ($oVer, $oRel) = ($1, $2);
  $oVer = 1 if (!$oVer);
  $oRel = 0 if (!$oRel);

  if (defined($pversion)) {
    $pversion =~ m/^([^\s]*)\sR([0-9]*)$/;
    my ($pVer, $pRel) = ($1, $2);
    $pVer = 1 if (!$pVer);
    $pRel = 0 if (!$pRel);
    $VERSION = $oRel gt $pRel ? "$pVer R$oRel" : "$pVer R$pRel";
  }

  return wantarray() ? ($VERSION, $OVERSION) : $VERSION;
}


sub new {
  #################################################################
  #     Legt ein neues Objekt an
  my $self  = shift;
  my $class = ref($self) || $self;
  my @args  = @_;

  my $ptr = {};
  bless $ptr, $class;
  $ptr->_init(@args);

  return $ptr;
}


sub _init {
  #################################################################
  #   Initialisiert ein neues Objekt
  my $self = shift;
  my @args = @_;

  $self->{Startzeit} = time();
  
  $VERSION = $self->version(shift(@args));
 
  Trace->Trc('S', 1, 0x00001, Configuration->prg, $VERSION . " (" . $$ . ")" . " Test: " . Trace->test() . " Parameter: " . CmdLine->new()->{ArgStrgRAW});
  
  # Test der benoetigten INI-Variablen
  # DB-Zugriff

  # Test der Komandozeilenparameter
  if (CmdLine->option('Help') || CmdLine->option('Version')) {
    CmdLine->usage();
    if (CmdLine->option('Help') || CmdLine->option('Version')) {
      Trace->Exit(0, 1, 0x00002, Configuration->prg, $VERSION);
    }
    Trace->Exit(1, 0, 0x08000, join(" ", CmdLine->argument()));
  }
  
  # Einmalige oder parallele Ausführung
  if (Configuration->config('Notfy', 'LockFile')) {
    $self->{LockFile} = File::Spec->canonpath(Utils::extendString(Configuration->config('Notfy', 'LockFile'), "BIN|$Bin|SCRIPT|" . uc($Script)));
    $self->{Lock} = LockFile::Simple->make(-max => 5, -delay => 1, -format => '%f', -autoclean => 1, -stale => 1, -wfunc => undef);
    my $errtxt;
    $SIG{'__WARN__'} = sub {$errtxt = $_[0]};
    my $lockerg = $self->{Lock}->trylock($self->{LockFile});
    undef($SIG{'__WARN__'});
    if (defined($errtxt)) {
      $errtxt =~ s/^(.*) .+ .+ line [0-9]+.*$/$1/;
      chomp($errtxt);
      Trace->Trc('S', 1, 0x00012, $errtxt) if defined($errtxt);
    }
    if (!$lockerg) {
      Trace->Exit(0, 1, 0x00013, Configuration->prg, $self->{LockFile})
    } else {
      Trace->Trc('S', 1, 0x00014, $self->{LockFile})
    }
  }
  
  if (Configuration->config('Notify', 'Storable')) {
    $self->{Storable} = Utils::extendString(Configuration->config('Notify', 'Storable'), "BIN|$Bin|SCRIPT|" . uc($Script));
    eval {$self->{Store} = retrieve $self->{Storable}};
  }
}


sub DESTROY {
  #################################################################
  #     Zerstoert das Objekt an
  my $self = shift;
  my ($rc, $sig) = (0,0);
  $rc  = ($? >> 8);
  $sig = $? & 127;
  if ($@ || $rc != 0 || $sig != 0) {
    my ( $routine, $i ) = ( ( caller(0) )[3] . ':', 0 );
    while ( defined( caller( ++$i ) ) ) {
      $routine .= ( caller($i) )[3] . '(' . ( caller( $i - 1 ) )[2] . '):';
    }
    Trace->Trc('S', 1, 0x00007, "$routine $@ $! $?");
    Trace->Log('Log', 0x10013, $@, $!, $?);
  }
  for my $parent (@ISA) {
    if ( my $coderef = $self->can( $parent . "::DESTROY" ) ) {
      $self->$coderef();
    }
  }
  # Eigentlich nicht noetig, da -autoclean => 1
  if ($self->{Lock}) {$self->{Lock}->unlock($self->{LockFile})}
}


sub sendNotification {
  #################################################################
  #     sendnotification
  #     Proc 1
  my $self = shift;
  my %args = (Type        => 'Prowl',
              Application => 'Notify',
              Event       => 'Benachrichtigung',
              Description => 'Keine weiteren Details',
              Priority    => '1',
              URL         => 'https://github.com/pgk69',
              Users       => undef,
              Key         => undef,
              Group       => undef,
              Flag        => undef,
              @_);

  my $merker          = $self->{subroutine};
  $self->{subroutine} = (caller(0))[3];
  Trace->Trc('S', 2, 0x00001, $self->{subroutine}, CmdLine->argument(0));
  
  my $rc = 0;

  $args{Event}       =~ tr/a-zA-Z0-9@.-:; //cd;
  $args{Description} =~ tr/a-zA-Z0-9@.\-:; //cd;

  my %users;
  if (defined($args{Users})) {
    %users = %{$args{Users}};
  } else {
    %users = Configuration->config($args{Type});
  }
  if (defined($args{Key})) {
    %users = ('defined_by_key' => $args{Key});
  }

  my $apikey;
  my $sendCurrentNotification;
  my $nma = WebService::NotifyMyAndroid->new;

  foreach my $user (keys %users) {
    $apikey =  $users{$user};

    my $uniqueGroupKey;
    $sendCurrentNotification = 1;
    if (defined($self->{Storable}) && defined($args{Flag})) {
      $uniqueGroupKey = defined($args{Group}) ? "$args{Group}:$apikey" : $apikey; 
      $sendCurrentNotification = !(defined($self->{Store}) && defined($self->{Store}->{$uniqueGroupKey}) && ($self->{Store}->{$uniqueGroupKey} eq $args{Flag}));
    }

   if ($sendCurrentNotification) {
      if (defined($uniqueGroupKey)) {
        $self->{Store}->{$uniqueGroupKey} = $args{Flag};
        store($self->{Store}, $self->{Storable}) or die "Can't store in $self->{Storable}!\n";
      }

      if ($args{Type} eq 'Prowl') {
        my $ws = WebService::Prowl->new(apikey => $apikey);
        if ($ws->verify) {
           Trace->Trc('I', 1, '%s Versand an %s', $args{Type}, $user);
           $ws->add(application => "$args{Application}",
                    event       => "$args{Event}",
                    description => "$args{Description}",
                    url         => "$args{URL}",
                    priority    => "$args{Priority}");
        } else {
          Trace->Trc('I', 1, '%s Versand an %s nicht erfolgreich (%s)', $args{Type}, $user, $ws->error());
        }
      }
      
      if ($args{Type} eq 'NMA') {
        # verify an existing API key
        my $result = $nma->verify(apikey => $apikey);
        if (defined($result->{success})) {
          # send a message
          Trace->Trc('I', 1, '%s Versand an %s', $args{Type}, $user);
          my $message = $nma->notify(apikey      => [$users{$user}],
                                     application => "$args{Application}",
                                     event       => "$args{Event}",
                                     description => "$args{Description}",
                                     priority    => "$args{Priority}");
          if (!defined($message->{success})) {
            Trace->Trc('I', 1, '%s Versand an %s nicht erfolgreich (%s)', $args{Type}, $user, $result->{error}->{content});
          }
        } else {
          Trace->Trc('I', 1, '%s Versand an %s nicht erfolgreich (%s)', $args{Type}, $user, $result->{error}->{content});
        }
      }
    } 
  } 

  Trace->Trc('S', 2, 0x00002, $self->{subroutine});
  $self->{subroutine} = $merker;

  # Explizite Uebergabe des Returncodes noetig, da sonst ein Fehler auftritt
  return $rc;
}


1;
