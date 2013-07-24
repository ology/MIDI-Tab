package MIDI::Tab;
# ABSTRACT: Generate MIDI from ASCII tablature

use strict;
use warnings;

use MIDI::Simple;

use base 'Exporter';
our @ISA = qw(Exporter);
our @EXPORT = qw(from_guitar_tab from_drum_tab from_piano_tab);

our $VERSION = '0.03_1';

use constant CONTROL => 'CTL';

=head1 NAME

MIDI::Tab - Generate MIDI from ASCII tablature

=head1 SYNOPSIS

  use MIDI::Tab;
  use MIDI::Simple;

  new_score;
  patch_change 1, 34; # Bass
  patch_change 3, 49; # Strings

  my $drums = <<'EOF';
  CYM: 8-------------------------------
  BD:  8-4---8-2-8-----8-4---8-2-8-----
  SD:  ----8-------8-------8-------8---
  HH:  66--6-6-66--6-6-66--6-6-66--6-6-
  OHH: --6-------6-------6-------6-----
  EOF

  my $bass = <<'EOF';
  G3: --------------------------------
  D3: --------------------------------
  A2: 5--53-4-5--53-1-----------------
  E2: ----------------3--31-2-3--23-4-
  EOF

  my $strings = <<'EOF';
  A5: 55
  A4: 55
  EOF

  synch(
      sub {
          from_drum_tab($_[0], $drums, 'sn');
      },
      sub {
          from_guitar_tab($_[0], $bass, 'sn', 'c1');
      },
      sub {
          from_piano_tab($_[0], $strings, 'wn', 'c3');
      },
  );

  write_score('MIDI-Tab.mid');

  # Use of the control line:
  $tab = <<'EOF';
  CTL: --------3-3-3-3---------
  HH:  959595959595959595959595
  EOF

=head1 DESCRIPTION

C<MIDI::Tab> allows you to create MIDI files from ASCII tablature.  It
is designed to work alongside Sean M. Burke's C<MIDI::Simple>.

Currently, there are three types of tablature supported: drum, guitar
and piano tab.

Note that bar lines (C<|>) are ignored.  Also a "control line" may be
specified to alter no-ops for individual notes.

=cut

# TODO Make a mutator method for this list.
# TODO Don't require an made-up "line name" - just use the patch number.
our %drum_notes = (
    ABD => 35,  # Acoustic Bass Drum
    BD  => 36,  # Bass Drum 1
    CA  => 69,  # Cabasa
    CB  => 56,  # Cowbell
    CC  => 52,  # Chinese Cymbal
    CL  => 75,  # Claves
    CY2 => 57,  # Crash Cymbal 2
    CYM => 49,  # Crash Cymbal 1
    CYS => 55,  # Splash Cymbal
    ESD => 40,  # Electric Snare
    HA  => 67,  # High Agogo
    HB  => 60,  # Hi Bongo
    HC  => 39,  # Hand Clap
    HFT => 43,  # High Floor Tom
    HH  => 42,  # Closed Hi-Hat
    HMT => 48,  # Hi-Mid Tom
    HT  => 50,  # High Tom
    HTI => 65,  # High Timbale
    HWB => 76,  # Hi Wood Block
    LA  => 68,  # Low Agogo
    LB  => 61,  # Low Bongo
    LC  => 64,  # Low Conga
    LFT => 41,  # Low Floor Tom
    LG  => 74,  # Long Guiro
    LMT => 47,  # Low-Mid Tom
    LT  => 45,  # Low Tom
    LTI => 66,  # Low Timbale
    LW  => 72,  # Long Whistle
    LWB => 77,  # Low Wood Block
    MA  => 70,  # Maracas
    MC  => 78,  # Mute Cuica
    MHC => 62,  # Mute Hi Conga
    MT  => 80,  # Mute Triangle
    OC  => 79,  # Open Cuica
    OHC => 63,  # Open Hi Conga
    OHH => 46,  # Open Hi-Hat
    OT  => 81,  # Open Triangle
    PH  => 44,  # Pedal Hi-Hat
    RB  => 53,  # Ride Bell
    RI2 => 59,  # Ride Cymbal 2
    RID => 51,  # Ride Cymbal 1
    SD  => 38,  # Acoustic Snare
    SG  => 73,  # Short Guiro
    SS  => 37,  # Side Stick
    SW  => 71,  # Short Whistle
    TAM => 54,  # Tambourine
    VS  => 58,  # Vibraslap
);
%drum_notes = map { $_ => 'n' . $drum_notes{$_} } keys %drum_notes;

=head1 METHODS

Each of these routines generates a set of MIDI::Simple notes on the object
passed as the first parameter.  The parameters are:

 MIDI:Simple object
 Tab Notes (as ASCII text)
 Noop Arguments (for changing channels etc)

Parameters to the C<from_*_tab()> routines, that are specified after
the tablature string, are passed as C<MIDI::Simple::noop> calls at the
start of the tab rendering.  For example, the length of each unit
of time can be specified by passing a C<MIDI::Simple> duration value
(eg 'sn').

Additionally, a "control line" for individulal note modification may
be included in the tab, at the same vertical position as the note it
modifies.  This line must be named C<CTL>.  At this point it is only
used to specify triplet timing.

=head2 from_guitar_tab()

  from_guitar_tab($object, $tab_text, @noops)

Notes are specified by an ASCII guitar where each horizontal line
represents a guitar string (as if the guitar were laid face-up in
front of you).

Time runs from left to right.  You can 'tune' the guitar by specifying
different root notes for the strings.  These should be specified as a
C<MIDI::Simple> alphanumeric absolute note value (eg 'A2').  The
numbers of the tablature represent the fret at which the note is
played.

=cut

sub from_guitar_tab {
    my ($score, $tab, @noop) = @_;

    # TODO Set $patch = 24 unless another is provided.

    # Add the no-ops to the score.
    $score->noop(@noop);

    # Grab the tab lines.
    my %lines = _parse_tab($tab);

    # Create routines for each line.
    my @subs;
    for my $line (keys %lines) {
        my ($base_note_number) = is_absolute_note_spec($line);
        die "Invalid base type: $line" unless $base_note_number || $line eq CONTROL();

        my $_sub = sub {
            my $score = shift;

            # Split tab lines into notes and control.
            my @notes = ();
            @notes = _split_lines(\%lines, $line, $base_note_number) unless $line eq CONTROL();

            # Collect the noop controls.
            my @control = ();
            @control = _split_lines(\%lines, CONTROL()) if exists $lines{CONTROL()};

            # Keep track of the beat.
            my $i = 0;

            # Add each note, rest and control noop to the score.
            for my $n (@notes) {
                # Set the note noop.
                my @ctl = @noop;
                @ctl = ($control[$i]) if @control;

                # Add to the score.
                if (defined $n) {
                    $score->n($n, @ctl);
                }
                else {
                    $score->r(@ctl);
                }

                # Increment the note we are inspecting.
                $i++;
            }
        };

        # Collect the performace subroutines.
        push @subs, $_sub;
    }

    # XXX This line looks suspiciously unnecessary. Hmmmmm
    # Add the part to the score.
    $score->synch(@subs);
}

=head2 from_drum_tab()

  from_drum_tab($object, $tab_text, @noops)

Each horizontal line represents a different drum part and time runs
from left to right.  Minus or plus characters represent rest intervals.
As many or as few drums as required can be specified, each drum having
a two or three letter code, such as C<BD> for the General MIDI "Bass
Drum 1" or C<SD> for the "Acoustic Snare."  These are all listed in
C<%MIDI::Tab::drum_notes>, which can be viewed or altered by your code.

The numbers on the tablature represent the volume of the drum hit,
from 1 to 9, where 9 is the loudest.

=cut

sub from_drum_tab {
    my ($score, $tab, @noop) = @_;

    # Set the drum channel if none has been provided.
    my $channel = 'c9';
    for (@noop) {
        if (/^(c\d+)$/) {
            $channel = $1;
            unshift @noop, $channel;
        }
    }

    # Add the no-ops to the score.
    $score->noop(@noop);

    # Grab the tab lines.
    my %lines = _parse_tab($tab, 'drum');

    # Create routines for each line.
    my @subs;
    for my $line (keys %lines) {
        my $_sub = sub {
            my $score = shift;

            die "Invalid drum type: $line" unless $drum_notes{$line} || $line eq CONTROL();
            my $drum = $drum_notes{$line};

            # Split tab lines into notes and control.
            my @notes = ();
            @notes = _split_lines(\%lines, $line) unless $line eq CONTROL();

            # Collect the noop controls.
            my @control = ();
            @control = _split_lines(\%lines, CONTROL()) if exists $lines{CONTROL()};

            # Keep track of the beat.
            my $i = 0;

            # Add each note, rest and control noop to the score.
            for my $n (@notes) {
                # Set the note noop.
                my @ctl = @noop;
                @ctl = ($control[$i]) if @control;

                # Add to the score.
                if (defined $n) {
                    $score->n($channel, $drum, $n, @ctl);
                }
                else {
                    $score->r(@ctl);
                }

                # Increment the note we are inspecting.
                $i++;
            }
        };

        # Collect the performace subroutines.
        push @subs, $_sub;
    }

    # XXX This line looks suspiciously unnecessary. Hmmmmm
    # Add the part to the score.
    $score->synch(@subs);
}

=head2 from_piano_tab()

  from_piano_tab($object, $tab_text, @noops)

Each horizonal line represents a different note on the piano and time
runs from left to right.  The values on the line represent volumes
from 1 to 9.

=cut

sub from_piano_tab {
    my ($score, $tab, @noop) = @_;

    # Add the no-ops to the score.
    $score->noop(@noop);

    # Grab the tab lines.
    my %lines = _parse_tab($tab);

    # Create routines for each line.
    my @subs;
    for my $line (keys %lines) {
        my $_sub = sub {
            my $score = shift;
            #die "Invalid note: $line" unless ???;

            # Split tab lines into notes and control.
            my @notes = ();
            @notes = _split_lines(\%lines, $line);

            # Collect the noop controls.
            my @control = ();
            @control = _split_lines(\%lines, CONTROL()) if exists $lines{CONTROL()};

            # Keep track of the beat.
            my $i = 0;

            # Add each note, rest and control noop to the score.
            for my $n (@notes) {
                # Set the note noop.
                my @ctl = @noop;
                @ctl = ($control[$i]) if @control;

                # Add to the score.
                if (defined $n) {
                    $score->n($line, $n, @ctl);
                }
                else {
                    $score->r(@ctl);
                }

                # Increment the note we are inspecting.
                $i++;
            }
        };

        # Collect the performace subroutines.
        push @subs, $_sub;
    }

    # XXX This line looks suspiciously unnecessary. Hmmmmm
    # Add the part to the score.
    $score->synch(@subs);
}

sub _parse_tab {
    my($tab, $type) = @_;

    # Remove bar lines.
    $tab =~ s/\|//g;

    # Set a regular expression to capture parts of the tab.
    my $re = qr/^\s*([A-Za-z0-9]+)\:\s*([0-9+-]+)\s+(.*)$/s;
    $re = qr/^\s*([A-Z]{2,3})\:\s*([0-9+-]+)\s+(.*)$/s if $type && $type eq 'drum';

    # Build lines from the tabulature.
    my %lines;
    while($tab =~ /$re/g) {
        my ($note, $line, $remainder) = ($1, $2, $3);
        $lines{$note} = $line;
        $tab = $remainder;
    }

    return %lines;
}

sub _split_lines {
    my($lines, $line, $base) = @_;

    # Construct a list of notes, volumes or noop controls.
    my @items = ();

    for my $n (split '', $lines->{$line}) {
        # Grab the control noop.
        if ($line eq CONTROL()) {
            if ($n eq '3') {
                push @items, 'ten';
            }
            else {
                push @items, undef;
            }
        }
        # Grab the note, itself.
        elsif ($n =~ /^[0-9]$/) {
            if ($base) {
                push @items, 'n' . ($base + $n);
            }
            else {
                # XXX This x12 bit looks suspiciously wrong.
                push @items, 'V' . ($n * 12);
            }
        }
        else {
            push @items, undef;
        }
    }

    return @items;
}

1;
__END__

=head1 SEE ALSO

* The code in the C<eg/> and C<t/> directories.

* L<MIDI::Simple>

=cut
