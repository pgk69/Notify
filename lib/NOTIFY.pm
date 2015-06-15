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
#use DBAccess;
use Utils;

#
# Module
#
use FindBin qw($Bin $Script $RealBin $RealScript);
use LockFile::Simple qw(lock trylock unlock);
use LWP;
#use LWP::RobotUA;
use HTTP::Cookies;

use HTML::Entities;
use utf8;
use Text::Unidecode;

use Storable;
use Path::Class;
use File::Path;
use File::Basename;
#use ZMQ::LibZMQ4;
#use ZMQ::FFI;
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
  
  if (Configuration->config('Prg', 'Plugin')) {

    # refs ausschalten wg. dyn. Proceduren
    no strict 'refs';
    my %plugin = ();

    # Bearbeiten aller Erweiterungsmodule die in der INI-Date
    # in Sektion [Prg] unter "Plugin =" definiert sind
    foreach (split(/ /, Configuration->config('Prg', 'Plugin'))) {

      # Falls ein Modul existiert
      if (-e "$self->{Pfad}/plugins/${_}.pm") {

        # Einbinden des Moduls
        require $_ . '.pm';
        $_->import();

        # Initialisieren des Moduls, falls es eine eigene Sektion
        # [<Modulname>] fuer das Module in der INI-Datei gibt
        $plugin{$_} = eval {$_->new(Configuration->config('Plugin ' . $_))};
        eval {
          $plugin{$_} ? $plugin{$_}->DESTROY : ($_ . '::DESTROY')->()
            if (CmdLine->option('erase'));
        };
      }
    }
    use strict;
  }

  # Module::Refresh->refresh;
  
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

  if ($args{Type} eq 'Prowl') {
    foreach my $user (keys %users) {
      my $ws = WebService::Prowl->new(apikey => $users{$user});
      if ($ws->verify) {
         $ws->add(application => "$args{Application}",
                  event       => "$args{Event}",
                  description => "$args{Description}",
                  url         => "$args{URL}",
                  priority    => "$args{Priority}");
      } else {
        Trace->Trc('I', 1, '%s Versand an %s nicht erfolgreich (%s)', $args{Type}, $user, $ws->error());
      }
    }
  }
    
  if ($args{Type} eq 'NMA') {
    my $nma = WebService::NotifyMyAndroid->new;
    foreach my $user (keys %users) {
      # verify an existing API key
      my $result = $nma->verify(apikey => $users{$user});
      if (defined($result->{success})) {
        # send a message
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

  Trace->Trc('S', 2, 0x00002, $self->{subroutine});
  $self->{subroutine} = $merker;

  # Explizite Uebergabe des Returncodes noetig, da sonst ein Fehler auftritt
  return $rc;
}


1;
