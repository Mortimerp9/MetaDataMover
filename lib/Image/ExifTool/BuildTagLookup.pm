#------------------------------------------------------------------------------
# File:         BuildTagLookup.pm
#
# Description:  Utility to build tag lookup tables in Image::ExifTool::TagLookup.pm
#
# Revisions:    12/31/2004 - P. Harvey Created
#               02/15/2005 - PH Added ability to generate TagNames documentation
#
# Notes:        Documentation for the tag tables may either be placed in the
#               %docs hash below or in a NOTES entry in the table itself, and
#               individual tags may have their own Notes entry.
#------------------------------------------------------------------------------

package Image::ExifTool::BuildTagLookup;

use strict;
require Exporter;

BEGIN {
    # prevent ExifTool from loading the user config file
    $Image::ExifTool::noConfig = 1;
}

use vars qw($VERSION @ISA);
use Image::ExifTool qw(:Utils :Vars);
use Image::ExifTool::Shortcuts;
use Image::ExifTool::HTML qw(EscapeHTML);
use Image::ExifTool::IPTC;
use Image::ExifTool::Canon;
use Image::ExifTool::Nikon;

$VERSION = '1.72';
@ISA = qw(Exporter);

sub NumbersFirst;

# colors for html pages
my $noteFont = "<span class=n>";
my $noteFontSmall = "<span class='n s'>";

my $docType = q{<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
        "http://www.w3.org/TR/html4/loose.dtd">
};


my $caseInsensitive;    # flag to ignore case when sorting tag names

# Descriptions for the TagNames documentation
# (descriptions may also be defined in tag table NOTES)
# Note: POD headers in these descriptions start with '~' instead of '=' to keep
# from confusing POD parsers which apparently parse inside quoted strings.
my %docs = (
    PodHeader => q{
~head1 NAME

Image::ExifTool::TagNames - ExifTool tag name documentation

~head1 DESCRIPTION

This document contains a complete list of ExifTool tag names, organized into
tables based on information type.  Tag names are used to indicate the
specific meta information that is extracted or written in an image.

~head1 TAG TABLES
},
    ExifTool => q{
The tables listed below give the names of all tags recognized by ExifTool.
},
    ExifTool2 => q{
B<Tag ID>, B<Index> or B<Sequence> is given in the first column of each
table.  A B<Tag ID> is the computer-readable equivalent of a tag name, and
is the identifier that is actually stored in the file.  An B<Index> refers
to the location of a value when found at a fixed position within a data
block, and B<Sequence> gives the order of values for a serial data stream.

A B<Tag Name> is the handle by which the information is accessed in
ExifTool.  In some instances, more than one name may correspond to a single
tag ID.  In these cases, the actual name used depends on the context in
which the information is found.  Case is not significant for tag names.  A
question mark (C<?>) after a tag name indicates that the information is
either not understood, not verified, or not very useful -- these tags are
not extracted by ExifTool unless the Unknown (-u) option is enabled.  Be
aware that some tag names are different than the descriptions printed out by
default when extracting information with exiftool.  To see the tag names
instead of the descriptions, use C<exiftool -s>.

The B<Writable> column indicates whether the tag is writable by ExifTool.
Anything but an C<N> in this column means the tag is writable.  A C<Y>
indicates writable information that is either unformatted or written using
the existing format.  Other expressions give details about the information
format, and vary depending on the general type of information.  The format
name may be followed by a number in square brackets to indicate the number
of values written, or the number of characters in a fixed-length string
(including a null terminator which is added if required).

An asterisk (C<*>) after an entry in the B<Writable> column indicates a
"protected" tag which is not writable directly, but is set via a Composite
or Extra tag.  A tilde (C<~>) indicates a tag this is only writable when
print conversion is disabled (by setting PrintConv to 0, or using the -n
option). A slash (C</>) indicates an "avoided" tag that is not created
unless the group is specified (due to name conflicts with other tags).  An
exclamation point (C<!>) indicates a tag that is considered unsafe to write
under normal circumstances.  These "unsafe" tags are not set when calling
SetNewValuesFromFile() or when using the exiftool -TagsFromFile option
unless specified explicitly, and care should be taken when editing them
manually since they may affect the way an image is rendered.  A plus sign
(C<+>) indicates a "list" tag which supports multiple values and allows
individual values to be added and deleted.

The HTML version of these tables also list possible B<Values> for
discrete-valued tags, as well as B<Notes> for some tags.

B<Note>: If you are familiar with common meta-information tag names, you may
find that some ExifTool tag names are different than expected.  The usual
reason for this is to make the tag names more consistent across different
types of meta information.  To determine a tag name, either consult this
documentation or run C<exiftool -s> on a file containing the information in
question.
},
    EXIF => q{
EXIF stands for "Exchangeable Image File Format".  This type of information
is formatted according to the TIFF specification, and may be found in JPG,
TIFF, PNG, MIFF and HDP images, as well as many TIFF-based RAW images, and
even some AVI and MOV videos.

The EXIF meta information is organized into different Image File Directories
(IFD's) within an image.  The names of these IFD's correspond to the
ExifTool family 1 group names.  When writing EXIF information, the default
B<Group> listed below is used unless another group is specified.

Also listed in the table below are TIFF, DNG, HDP and other tags which are
not part of the EXIF specification, but may co-exist with EXIF tags in some
images.
},
    GPS => q{
These GPS tags are part of the EXIF standard, and are stored in a separate
IFD within the EXIF information.

ExifTool is very flexible about the input format when writing lat/long
coordinates, and will accept from 1 to 3 floating point numbers (for decimal
degrees, degrees and minutes, or degrees, minutes and seconds) separated by
just about anything, and will format them properly according to the EXIF
specification.

Some GPS tags have values which are fixed-length strings. For these, the
indicated string lengths include a null terminator which is added
automatically by ExifTool.  Remember that the descriptive values are used
when writing (ie. 'Above Sea Level', not '0') unless the print conversion is
disabled (with '-n' on the command line, or the PrintConv option in the
API).
},
    XMP => q{
XMP stands for "Extensible Metadata Platform", an XML/RDF-based metadata
format which is being pushed by Adobe.  Information in this format can be
embedded in many different image file types including JPG, JP2, TIFF, GIF,
PS, PDF, PSD, DNG, PNG, SVG and MIFF, as well as audio file formats
supporting ID3v2 information.

The XMP B<Tag ID>'s aren't listed because in most cases they are identical
to the B<Tag Name>.

All XMP information is stored as character strings.  The B<Writable> column
specifies the information format:  C<integer> is a string of digits
(possibly beginning with a '+' or '-'), C<real> is a floating point number,
C<rational> is two C<integer> strings separated by a '/' character, C<date>
is a date/time string in the format "YYYY:MM:DD HH:MM:SS[.SS][+/-HH:MM]",
C<boolean> is either "True" or "False", and C<lang-alt> is a list of string
alternatives in different languages.

Individual languages for C<lang-alt> tags are accessed by suffixing the tag
name with a '-', followed by an RFC 3066 language code (ie. "XMP:Title-fr",
or "Rights-en-US").  A C<lang-alt> tag with no language code accesses the
"x-default" language, but causes other languages to be deleted when writing.
The "x-default" language code may be specified when writing a new value to
write only the default language, but note that all languages are still
deleted if "x-default" tag is deleted.  When reading, "x-default" is not
specified.

The XMP tags are organized according to schema B<Namespace> in the following
tables.  Note that a few of the longer namespace prefixes given below have
been shortened for convenience (since the family 1 group names are derived
from these by adding a leading "XMP-").  In cases where a tag name exists in
more than one namespace, less common namespaces are avoided when writing.
However, any namespace may be written by specifying a family 1 group name
for the tag, ie) XMP-exif:Contrast or XMP-crs:Contrast.

ExifTool will extract XMP information even if it is not listed in these
tables.  For example, the C<pdfx> namespace doesn't have a predefined set of
tag names because it is used to store application-defined PDF information,
but this information is extracted by ExifTool anyway.
},
    IPTC => q{
IPTC stands for "International Press Telecommunications Council".  This is
an older meta information format that is slowly being phased out in favor of
XMP.  IPTC information may be embedded in JPG, TIFF, PNG, MIFF, PS, PDF, PSD
and DNG images.

The IPTC specification dictates a length for ASCII (C<string> or C<digits>)
values.  These lengths are given in square brackets after the B<Writable>
format name.  For tags where a range of lengths is allowed, the minimum and
maximum lengths are separated by a comma within the brackets.  IPTC strings
are not null terminated.

IPTC information is separated into different records, each of which has its
own set of tags.
},
    Photoshop => q{
Photoshop tags are found in PSD files, as well as inside embedded Photoshop
information in many other file types (JPEG, TIFF, PDF, PNG to name a few).

Many Photoshop tags are marked as Unknown (indicated by a question mark
after the tag name) because the information they provide is not very useful
under normal circumstances (and because Adobe denied my application for
their file format documentation -- apparently open source software is too
big a concept for them).  These unknown tags are not extracted unless the
Unknown (-u) option is used.
},
    PrintIM => q{
The format of the PrintIM information is known, however no PrintIM tags have
been decoded.  Use the Unknown (-u) option to extract PrintIM information.
},
    Kodak => q{
Many Kodak models don't store the maker notes in standard IFD format, and
these formats vary with different models.  Some information has been
decoded, but much of the Kodak information remains unknown.
},
    'Kodak SpecialEffects' => q{
The Kodak SpecialEffects and Borders tags are found in sub-IFD's within the
Kodak JPEG APP3 "Meta" segment.
},
    Minolta => q{
These tags are used by Minolta and Konica/Minolta cameras.  Minolta doesn't
make things easy for decoders because the meaning of some tags and the
location where some information is stored is different for different camera
models.  (Take MinoltaQuality for example, which may be located in 5
different places.)
},
    Olympus => q{
Tags 0x0000 through 0x0103 are used by some older Olympus cameras, and are
the same as Konica/Minolta tags.  The Olympus tags are also used for Epson
and Agfa cameras.
},
    Panasonic => q{
These tags are used in Panasonic/Leica cameras.
},
    Pentax => q{
These tags are used in Pentax/Asahi cameras.
},
    Sigma => q{
These tags are used in Sigma/Foveon cameras.
},
    Sony => q{
The maker notes in images from current Sony camera models contain a wealth
of information, but very little is known about these tags.  Use the ExifTool
Unknown (-u) or Verbose (-v) options to see information about the unknown
tags.
},
    CanonRaw => q{
These tags apply to CRW-format Canon RAW files and information in the APP0
"CIFF" segment of JPEG images.  When writing CanonRaw/CIFF information, the
length of the information is preserved (and the new information is truncated
or padded as required) unless B<Writable> is C<resize>. Currently, only
JpgFromRaw and ThumbnailImage are allowed to change size.
},
    Unknown => q{
The following tags are decoded in unsupported maker notes.  Use the Unknown
(-u) option to display other unknown tags.
},
    PDF => q{
The tags listed in the PDF tables below are those which are used by ExifTool
to extract meta information, but they are only a small fraction of the total
number of available PDF tags.

When writing PDF files, ExifTool uses an increment update.  This has an
advantage that the original PDF can be easily recovered by deleting the
C<PDF-update> pseudo-group (with C<-PDF-update:all=> on the command line).
},
    DNG => q{
The main DNG tags are found in the EXIF table.  The tables below define only
information found within structures of these main DNG tag values.
},
    MPEG => q{
The MPEG format doesn't specify any file-level meta information.  In lieu of
this, information is extracted from the first audio and video frame headers
in the file.
},
    Real => q{
ExifTool recognizes three basic types of Real audio/video files: 1)
RealMedia (RM, RV and RMVB), 2) RealAudio (RA), and 3) Real Metafile (RAM
and RPM).
},
    Extra => q{
The extra tags represent extra information extracted or generated by
ExifTool that is not associated with another tag group.  The three writable
"pseudo" tags (Filename, Directory and FileModifyDate) may be written
without the need to rewrite the file since their values are not contained
within the file data.
},
    Composite => q{
The values of the composite tags are derived from the values of other tags.
These are convenience tags which are calculated after all other information
is extracted.
},
    Shortcuts => q{
Shortcut tags are convenience tags that represent one or more other tag
names.  They are used like regular tags to read and write the information
for a specified set of tags.

The shortcut tags below have been pre-defined, but user-defined shortcuts
may be added via the %Image::ExifTool::Shortcuts::UserDefined lookup in the
~/.ExifTool_config file.  See the Image::ExifTool::Shortcuts documentation
for more details.
},
    PodTrailer => q{
~head1 NOTES

This document generated automatically by
L<Image::ExifTool::BuildTagLookup|Image::ExifTool::BuildTagLookup>.

~head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

~head1 SEE ALSO

L<Image::ExifTool(3pm)|Image::ExifTool>

~cut
},
);


#------------------------------------------------------------------------------
# New - create new BuildTagLookup object
# Inputs: 0) reference to BuildTagLookup object or BuildTagLookup class name
sub new
{
    local $_;
    my $that = shift;
    my $class = ref($that) || $that || 'Image::ExifTool::BuildTagLookup';
    my $self = bless {}, $class;
    my (%subdirs, %isShortcut);
    my %count = (
        'unique tag names' => 0,
        'total tags' => 0,
    );
#
# loop through all tables, accumulating TagLookup and TagName information
#
    my (%tagNameInfo, %id, %longID, %longName, %shortName, %tableNum,
        %tagLookup, %tagExists, %tableWritable, %sepTable, %compositeModules);
    $self->{TAG_NAME_INFO} = \%tagNameInfo;
    $self->{ID_LOOKUP} = \%id;
    $self->{LONG_ID} = \%longID;
    $self->{LONG_NAME} = \%longName;
    $self->{SHORT_NAME} = \%shortName;
    $self->{TABLE_NUM} = \%tableNum;
    $self->{TAG_LOOKUP} = \%tagLookup;
    $self->{TAG_EXISTS} = \%tagExists;
    $self->{TABLE_WRITABLE} = \%tableWritable;
    $self->{SEPARATE_TABLE} = \%sepTable;
    $self->{COMPOSITE_MODULES} = \%compositeModules;
    $self->{COUNT} = \%count;

    Image::ExifTool::LoadAllTables();
    my @tableNames = sort keys %allTables;
    push @tableNames, 'Image::ExifTool::Shortcuts::Main'; # add Shortcuts last
    my $tableNum = 0;
    my $tableName;
    # create lookup for short table names
    foreach $tableName (@tableNames) {
        my $short = $tableName;
        $short =~ s/^Image::ExifTool:://;
        $short =~ s/::Main$//;
        $short =~ s/::/ /;
        $short =~ s/(.*)Tags$/\u$1/;
        $short =~ s/^Exif\b/EXIF/;
        $shortName{$tableName} = $short;    # remember short name
        $tableNum{$tableName} = $tableNum++;
    }
    # make lookup table to check for shortcut tags
    my $tag;
    foreach $tag (keys %Image::ExifTool::Shortcuts::Main) {
        my $entry = $Image::ExifTool::Shortcuts::Main{$tag};
        # ignore if shortcut tag name includes itself
        next if ref $entry eq 'ARRAY' and grep /^$tag$/, @$entry;
        $isShortcut{lc($tag)} = 1;
    }
    foreach $tableName (@tableNames) {
        # create short table name
        my $short = $shortName{$tableName};
        my $info = $tagNameInfo{$tableName} = [ ];
        my ($table, $shortcut);
        if ($short eq 'Shortcuts') {
            # can't use GetTagTable() for Shortcuts (not a normal table)
            $table = \%Image::ExifTool::Shortcuts::Main;
            $shortcut = 1;
        } else {
            $table = GetTagTable($tableName);
        }
        my $tableNum = $tableNum{$tableName};
        my $writeProc = $table->{WRITE_PROC};
        my $vars = $table->{VARS} || { };
        $longID{$tableName} = 0;
        $longName{$tableName} = 0;
        # save all tag names
        my ($tagID, $binaryTable, $noID, $isIPTC);
        $isIPTC = 1 if $$table{WRITE_PROC} and $$table{WRITE_PROC} eq \&Image::ExifTool::IPTC::WriteIPTC;
        $noID = 1 if $short =~ /^(Composite|XMP|Extra|Shortcuts|ASF.*)$/ or $$vars{NO_ID};
        if ($$vars{ID_LABEL} or ($table->{PROCESS_PROC} and
            $table->{PROCESS_PROC} eq \&Image::ExifTool::ProcessBinaryData))
        {
            $binaryTable = 1;
            $id{$tableName} = $$vars{ID_LABEL} || 'Index';
        } elsif ($isIPTC and $$table{PROCESS_PROC}) { #only the main IPTC table has a PROCESS_PROC
            $id{$tableName} = 'Record';
        } elsif (not $noID) {
            $id{$tableName} = 'Tag ID';
        }
        $caseInsensitive = ($tableName =~ /::XMP::/);
        my @keys = sort NumbersFirst TagTableKeys($table);
        my $defFormat = $table->{FORMAT};
        # use default format for binary data tables
        $defFormat = 'int8u' if not $defFormat and $binaryTable;

TagID:  foreach $tagID (@keys) {
            my ($tagInfo, @tagNames, $subdir, $format, @values);
            my (@infoArray, @require, @writeGroup, @writable);
            if ($shortcut) {
                # must build a dummy tagInfo list since Shortcuts is not a normal table
                $tagInfo = { Name => $tagID, Writable => 1, Require => { } };
                my $i;
                for ($i=0; $i<@{$$table{$tagID}}; ++$i) {
                    $tagInfo->{Require}->{$i} = $table->{$tagID}->[$i];
                }
                @infoArray = ( $tagInfo );
            } else {
                @infoArray = GetTagInfoList($table,$tagID);
            }
            $format = $defFormat;
            foreach $tagInfo (@infoArray) {
                if ($$tagInfo{Notes}) {
                    my $note = $$tagInfo{Notes};
                    # remove leading/trailing blank lines
                    $note =~ s/(^\s+|\s+$)//g;
                    # remove leading/trailing spaces on each line
                    $note =~ s/(^[ \t]+|[ \t]+$)//mg;
                    push @values, "($note)";
                }
                my $writable;
                if (defined $$tagInfo{Writable}) {
                    $writable = $$tagInfo{Writable};
                } elsif (not $$tagInfo{SubDirectory}) {
                    $writable = $$table{WRITABLE};
                }
                my $writeGroup;
                $writeGroup = $$tagInfo{WriteGroup};
                unless ($writeGroup) {
                    $writeGroup = $$table{WRITE_GROUP} if $writable;
                    $writeGroup = '-' unless $writeGroup;
                }
                $format = $$tagInfo{Format} if defined $$tagInfo{Format};
                if ($$tagInfo{SubDirectory}) {
                    # don't show XMP structure tags
                    next TagID if $short =~ /^XMP /;
                    $subdir = 1;
                    my $subTable = $tagInfo->{SubDirectory}->{TagTable} || $tableName;
                    push @values, $shortName{$subTable}
                } else {
                    $subdir = 0;
                }
                my $type;
                foreach $type ('Require','Desire') {
                    my $require = $$tagInfo{$type};
                    if ($require) {
                        foreach (sort { $a <=> $b } keys %$require) {
                            push @require, $$require{$_};
                        }
                    }
                }
                my $printConv = $$tagInfo{PrintConv};
                if ($$tagInfo{Mask}) {
                    push @values, sprintf('[Mask 0x%x]',$$tagInfo{Mask});
                    $$tagInfo{PrintHex} = 1 unless defined $$tagInfo{PrintHex};
                }
                if (ref($printConv) =~ /^(HASH|ARRAY)$/) {
                    my (@printConvList, @indexList, $index);
                    if (ref $printConv eq 'ARRAY') {
                        for ($index=0; $index<@$printConv; ++$index) {
                            next if ref $$printConv[$index] ne 'HASH';
                            next unless %{$$printConv[$index]};
                            push @printConvList, $$printConv[$index];
                            push @indexList, $index;
                        }
                        $printConv = shift @printConvList;
                        $index = shift @indexList;
                    }
                    while (defined $printConv) {
                        if (defined $index) {
                            # (print indices of original values if reorganized)
                            my $s = '';
                            my $idx = $$tagInfo{Relist} ? $tagInfo->{Relist}->[$index] : $index;
                            if (ref $idx) {
                                $s = 's' if @$idx > 1;
                                ($idx = join ', ', @$idx) =~ s/(.*),/$1 and/;
                            } elsif (not $$tagInfo{Relist}) {
                                while (@printConvList and $printConv eq $printConvList[0]) {
                                    shift @printConvList;
                                    $index = shift @indexList;
                                }
                                if ($idx != $index) {
                                    $idx = "$idx-$index";
                                    $s = 's';
                                }
                            }
                            push @values, "[Value$s $idx]";
                        }
                        if ($$tagInfo{SeparateTable}) {
                            $subdir = 1;
                            my $s = $$tagInfo{SeparateTable};
                            $s = $$tagInfo{Name} if $s eq '1';
                            # add module name if not specified
                            $s =~ / / or ($short =~ /^(\w+)/ and $s = "$1 $s");
                            push @values, $s;
                            $sepTable{$s} = $printConv;
                            # add PrintHex flag to PrintConv so we can check it later
                            $$printConv{PrintHex} = 1 if $$tagInfo{PrintHex};
                        } else {
                            $caseInsensitive = 0;
                            my @pk = sort NumbersFirst keys %$printConv;
                            my $bits;
                            foreach (@pk) {
                                next if $_ eq '';
                                $_ eq 'BITMASK' and $bits = $$printConv{$_}, next;
                                $_ eq 'OTHER' and next;
                                my $index;
                                if ($$tagInfo{PrintHex} or $$printConv{BITMASK}) {
                                    $index = sprintf('0x%x',$_);
                                } elsif (/^[-+]?\d+$/) {
                                    $index = $_;
                                } else {
                                    $index = $_;
                                    # translate unprintable values
                                    if ($index =~ s/([\x00-\x1f\x80-\xff])/sprintf("\\x%.2x",ord $1)/eg) {
                                        $index = qq{"$index"};
                                    } else {
                                        $index = qq{'$index'};
                                    }
                                }
                                push @values, "$index = " . $$printConv{$_};
                            }
                            if ($bits) {
                                my @pk = sort NumbersFirst keys %$bits;
                                foreach (@pk) {
                                    push @values, "Bit $_ = " . $$bits{$_};
                                }
                            }
                        }
                        last unless @printConvList;
                        $printConv = shift @printConvList;
                        $index = shift @indexList;
                    }
                } elsif ($printConv and $printConv =~ /DecodeBits\(\$val,\s*(\{.*\})\s*\)/s) {
                    $$self{Model} = '';   # needed for Nikon ShootingMode
                    my $bits = eval $1;
                    delete $$self{Model};
                    if ($@) {
                        warn $@;
                    } else {
                        my @pk = sort NumbersFirst keys %$bits;
                        foreach (@pk) {
                            push @values, "Bit $_ = " . $$bits{$_};
                        }
                    }
                }
                if ($subdir and not $$tagInfo{SeparateTable}) {
                    # subdirectories are only writable if specified explicitly
                    my $tw = $$tagInfo{Writable};
                    $writable = '-' . ($tw ? $writable : '');
                    $writable .= '!' if $tw and ($$tagInfo{Protected} || 0) & 0x01;
                } else {
                    # not writable if we can't do the inverse conversions
                    my $noPrintConvInv;
                    if ($writable) {
                        foreach ('PrintConv','ValueConv') {
                            next unless $$tagInfo{$_};
                            next if $$tagInfo{$_ . 'Inv'};
                            next if ref($$tagInfo{$_}) =~ /^(HASH|ARRAY)$/;
                            next if $$tagInfo{WriteAlso};
                            if ($_ eq 'ValueConv') {
                                undef $writable;
                            } else {
                                $noPrintConvInv = 1;
                            }
                        }
                    }
                    if (not $writable) {
                        $writable = 'N';
                    } else {
                        $writable eq '1' and $writable = $format ? $format : 'Y';
                        my $count = $$tagInfo{Count} || 1;
                        # adjust count to Writable size if different than Format
                        if ($writable and $format and $writable ne $format and
                            $Image::ExifTool::Exif::formatNumber{$writable} and
                            $Image::ExifTool::Exif::formatNumber{$format})
                        {
                            my $n1 = $Image::ExifTool::Exif::formatNumber{$format};
                            my $n2 = $Image::ExifTool::Exif::formatNumber{$writable};
                            $count *= $Image::ExifTool::Exif::formatSize[$n1] /
                                      $Image::ExifTool::Exif::formatSize[$n2];
                        }
                        if ($count != 1) {
                            $count = 'n' if $count < 0;
                            $writable .= "[$count]";
                        }
                        $writable .= '~' if $noPrintConvInv;
                        # add a '*' if this tag is protected or a '~' for unsafe tags
                        if ($$tagInfo{Protected}) {
                            $writable .= '*' if $$tagInfo{Protected} & 0x02;
                            $writable .= '!' if $$tagInfo{Protected} & 0x01;
                        }
                        $writable .= '/' if $$tagInfo{Avoid};
                    }
                    $writable .= '+' if $$tagInfo{List};
                    # Œseparate tables link like subdirectories (flagged with leading '-')
                    $writable = "-$writable" if $subdir;
                }
                # don't duplicate a tag name unless an entry is different
                my $name = $$tagInfo{Name};
                my $lcName = lc($name);
                # check for conflicts with shortcut names
                if ($isShortcut{$lcName} and $short ne 'Shortcuts' and
                    ($$tagInfo{Writable} or not $$tagInfo{SubDirectory}))
                {
                    warn "WARNING: $short $name is a shortcut tag!\n";
                }
                $name .= '?' if $$tagInfo{Unknown};
                unless (@tagNames and $tagNames[-1] eq $name and
                    $writeGroup[-1] eq $writeGroup and $writable[-1] eq $writable)
                {
                    push @tagNames, $name;
                    push @writeGroup, $writeGroup;
                    push @writable, $writable;
                }
#
# add this tag to the tag lookup unless PROCESS_PROC is 0 or shortcut tag
#
                next if $shortcut or (defined $$table{PROCESS_PROC} and not $$table{PROCESS_PROC});
                # count our tags
                if ($$tagInfo{SubDirectory}) {
                    $subdirs{$lcName} or $subdirs{$lcName} = 0;
                    ++$subdirs{$lcName};
                } else {
                    ++$count{'total tags'};
                    unless ($tagExists{$lcName} and (not $subdirs{$lcName} or $subdirs{$lcName} == $tagExists{$lcName})) {
                        ++$count{'unique tag names'};
                    }
                }
                $tagExists{$lcName} or $tagExists{$lcName} = 0;
                ++$tagExists{$lcName};
                # only add writable tags to lookup table (for speed)
                my $wflag = $$tagInfo{Writable};
                next unless $writeProc and ($wflag or ($$table{WRITABLE} and
                    not defined $wflag and not $$tagInfo{SubDirectory}));
                $tagLookup{$lcName} or $tagLookup{$lcName} = { };
                # remember number for this table
                my $tagIDs = $tagLookup{$lcName}->{$tableNum};
                # must allow for duplicate tags with the same name in a single table!
                if ($tagIDs) {
                    if (ref $tagIDs eq 'HASH') {
                        $$tagIDs{$tagID} = 1;
                        next;
                    } elsif ($tagID eq $tagIDs) {
                        next;
                    } else {
                        $tagIDs = { $tagIDs => 1, $tagID => 1 };
                    }
                } else {
                    $tagIDs = $tagID;
                }
                $tableWritable{$tableName} = 1;
                $tagLookup{$lcName}->{$tableNum} = $tagIDs;
                if ($short eq 'Composite' and $$tagInfo{Module}) {
                    $compositeModules{$lcName} = $$tagInfo{Module};
                }
            }
#
# save TagName information
#
            my $tagIDstr;
            if ($tagID =~ /^\d+(\.\d+)?$/) {
                if ($1 or $binaryTable or $isIPTC or ($short =~ /^CanonCustom/ and $tagID < 256)) {
                    $tagIDstr = $tagID;
                } else {
                    $tagIDstr = sprintf("0x%.4x",$tagID);
                }
            } elsif ($short eq 'DICOM') {
                ($tagIDstr = $tagID) =~ s/_/,/;
            } else {
                # convert non-printable characters to hex escape sequences
                if ($tagID =~ s/([\x00-\x1f\x7f-\xff])/'\x'.unpack('H*',$1)/eg) {
                    $tagID =~ s/\\x00/\\0/g;
                    next if $tagID eq 'jP\x1a\x1a'; # ignore abnormal JP2 signature tag
                    $tagIDstr = qq{"$tagID"};
                } else {
                    $tagIDstr = "'$tagID'";
                }
            }
            my $len = length $tagIDstr;
            $longID{$tableName} = $len if $longID{$tableName} < $len;
            foreach (@tagNames) {
                $len = length $_;
                $longName{$tableName} = $len if $longName{$tableName} < $len;
            }
            push @$info, [ $tagIDstr, \@tagNames, \@writable, \@values, \@require, \@writeGroup ];
        }
    }
    return $self;
}

#------------------------------------------------------------------------------
# Rewrite this file to build the lookup tables
# Inputs: 0) BuildTagLookup object reference
#         1) output tag lookup module name (ie. 'lib/Image/ExifTool/TagLookup.pm')
# Returns: true on success
sub WriteTagLookup($$)
{
    local $_;
    my ($self, $file) = @_;
    my $tagLookup = $self->{TAG_LOOKUP};
    my $tagExists = $self->{TAG_EXISTS};
    my $tableWritable = $self->{TABLE_WRITABLE};
#
# open/create necessary files and transfer file headers
#
    my $tmpFile = "${file}_tmp";
    open(INFILE,$file) or warn("Can't open $file\n"), return 0;
    unless (open(OUTFILE,">$tmpFile")) {
        warn "Can't create temporary file $tmpFile\n";
        close(INFILE);
        return 0;
    }
    my $success;
    while (<INFILE>) {
        print OUTFILE $_ or last;
        if (/^#\+{4} Begin/) {
            $success = 1;
            last;
        }
    }
    print OUTFILE "\n# list of tables containing writable tags\n";
    print OUTFILE "my \@tableList = (\n";

#
# write table list
#
    my @tableNames = sort keys %allTables;
    my $tableName;
    my %wrNum;      # translate from allTables index to writable tables index
    my $count = 0;
    my $num = 0;
    foreach $tableName (@tableNames) {
        if ($$tableWritable{$tableName}) {
            print OUTFILE "\t'$tableName',\n";
            $wrNum{$count} = $num++;
        }
        $count++;
    }
#
# write the tag lookup table
#
    my $tag;
    # verify that certain critical tag names aren't duplicated
    foreach $tag (qw{filename directory}) {
        next unless $$tagLookup{$tag};
        my $n = scalar keys %{$$tagLookup{$tag}};
        warn "Warning: $n writable '$tag' tags!\n" if $n > 1;
    }
    print OUTFILE ");\n\n# lookup for all writable tags\nmy \%tagLookup = (\n";
    foreach $tag (sort keys %$tagLookup) {
        print OUTFILE "\t'$tag' => { ";
        my @tableNums = sort { $a <=> $b } keys %{$$tagLookup{$tag}};
        my (@entries, $tableNum);
        foreach $tableNum (@tableNums) {
            my $tagID = $$tagLookup{$tag}->{$tableNum};
            my $entry;
            if (ref $tagID eq 'HASH') {
                my @tagIDs = sort keys %$tagID;
                foreach (@tagIDs) {
                    if (/^\d+$/) {
                        $_ = sprintf("0x%x",$_);
                    } else {
                        my $quot = "'";
                        # escape non-printable characters in tag ID if necessary
                        $quot = '"' if s/[\x00-\x1f,\x7f-\xff]/sprintf('\\x%.2x',ord($&))/ge;
                        $_ = $quot . $_ . $quot;
                    }
                }
                $entry = '[' . join(',', @tagIDs) . ']';
            } elsif ($tagID =~ /^\d+$/) {
                $entry = sprintf("0x%x",$tagID);
            } else {
                $entry = "'$tagID'";
            }
            my $wrNum = $wrNum{$tableNum};
            push @entries, "$wrNum => $entry";
        }
        print OUTFILE join(', ', @entries);
        print OUTFILE " },\n";
    }
#
# write tag exists lookup
#
    print OUTFILE ");\n\n# lookup for non-writable tags to check if the name exists\n";
    print OUTFILE "my \%tagExists = (\n";
    foreach $tag (sort keys %$tagExists) {
        next if $$tagLookup{$tag};
        print OUTFILE "\t'$tag' => 1,\n";
    }
#
# write module lookup for writable composite tags
#
    my $compositeModules = $self->{COMPOSITE_MODULES};
    print OUTFILE ");\n\n# module names for writable Composite tags\n";
    print OUTFILE "my \%compositeModules = (\n";
    foreach (sort keys %$compositeModules) {
        print OUTFILE "\t'$_' => '$$compositeModules{$_}',\n";
    }
    print OUTFILE ");\n\n";
#
# finish writing TagLookup.pm and clean up
#
    if ($success) {
        $success = 0;
        while (<INFILE>) {
            $success or /^#\+{4} End/ or next;
            print OUTFILE $_;
            $success = 1;
        }
    }
    close(INFILE);
    close(OUTFILE) or $success = 0;
#
# return success code
#
    if ($success) {
        rename($tmpFile, $file);
    } else {
        unlink($tmpFile);
        warn "Error rewriting file\n";
    }
    return $success;
}

#------------------------------------------------------------------------------
# sort numbers first numerically, then strings alphabetically (case insensitive)
sub NumbersFirst
{
    my $rtnVal;
    my $bNum = ($b =~ /^-?[0-9]+(\.\d*)?$/);
    if ($a =~ /^-?[0-9]+(\.\d*)?$/) {
        $rtnVal = ($bNum ? $a <=> $b : -1);
    } elsif ($bNum) {
        $rtnVal = 1;
    } else {
        my ($a2, $b2) = ($a, $b);
        # expand numbers to 3 digits (with restrictions to avoid messing up ascii-hex tags)
        $a2 =~ s/(\d+)/sprintf("%.3d",$1)/eg if $a2 =~ /^(APP)?[0-9 ]*$/ and length($a2)<16;
        $b2 =~ s/(\d+)/sprintf("%.3d",$1)/eg if $b2 =~ /^(APP)?[0-9 ]*$/ and length($b2)<16;
        $caseInsensitive and $rtnVal = (lc($a2) cmp lc($b2));
        $rtnVal or $rtnVal = ($a2 cmp $b2);
    }
    return $rtnVal;
}

#------------------------------------------------------------------------------
# Convert pod documentation to pod
# (funny, I know, but the pod headings must be hidden to prevent confusing
#  the pod parser)
# Inputs: 0) string
sub Doc2Pod($)
{
    my $doc = shift;
    $doc =~ s/\n~/\n=/g;
    return $doc;
}

#------------------------------------------------------------------------------
# Convert pod documentation to html
# Inputs: 0) string
sub Doc2Html($)
{
    my $doc = EscapeHTML(shift);
    $doc =~ s/\n\n/<\/p>\n\n<p>/g;
    $doc =~ s/B&lt;(.*?)&gt;/<b>$1<\/b>/sg;
    $doc =~ s/C&lt;(.*?)&gt;/<code>$1<\/code>/sg;
    $doc =~ s/L&lt;(.*?)&gt;/<a href="$1">$1<\/a>/sg;
    return $doc;
}

#------------------------------------------------------------------------------
# Get the order that we want to print the tables in the documentation
# Returns: tables in the order we want
sub GetTableOrder()
{
    my %gotTable;
    my $count = 0;
    my @tableNames = @tableOrder;
    my (@orderedTables, %mainTables, @outOfOrder);
    my $lastTable = '';

    while (@tableNames) {
        my $tableName = shift @tableNames;
        next if $gotTable{$tableName};
        if ($tableName =~ /^Image::ExifTool::(\w+)::Main/) {
            $mainTables{$1} = 1;
        } elsif ($lastTable and not $tableName =~ /^${lastTable}::/) {
            push @outOfOrder, $tableName;
        }
        ($lastTable) = ($tableName =~ /^(Image::ExifTool::\w+)/);
        push @orderedTables, $tableName;
        $gotTable{$tableName} = 1;
        my $table = GetTagTable($tableName);
        # recursively scan through tables in subdirectories
        my @moreTables;
        $caseInsensitive = ($tableName =~ /::XMP::/);
        my @keys = sort NumbersFirst TagTableKeys($table);
        foreach (@keys) {
            my @infoArray = GetTagInfoList($table,$_);
            my $tagInfo;
            foreach $tagInfo (@infoArray) {
                my $subdir = $$tagInfo{SubDirectory} or next;
                $tableName = $$subdir{TagTable} or next;
                next if $gotTable{$tableName};  # next if table already loaded
                push @moreTables, $tableName;   # must scan this one too
            }
        }
        unshift @tableNames, @moreTables;
    }
    # clean up the order for tables which are out of order
    # (groups all Canon and Kodak tables together)
    my %fixOrder;
    foreach (@outOfOrder) {
        next unless /^Image::ExifTool::(\w+)/;
        # only re-order tables which have a corresponding main table
        next unless $mainTables{$1};
        $fixOrder{$1} = [];     # fix the order of these tables
    }
    my (@sortedTables, %fixPos, $pos);
    foreach (@orderedTables) {
        if (/^Image::ExifTool::(\w+)/ and $fixOrder{$1}) {
            my $fix = $fixOrder{$1};
            unless (@$fix) {
                $pos = @sortedTables;
                $fixPos{$pos} or $fixPos{$pos} = [];
                push @{$fixPos{$pos}}, $1;
            }
            push @{$fix}, $_;
        } else {
            push @sortedTables, $_;
        }
    }
    # insert back in better order
    foreach $pos (sort { $b <=> $a } keys %fixPos) { # (reverse sort)
        my $fix = $fixPos{$pos};
        foreach (@$fix) {
            splice(@sortedTables, $pos, 0, @{$fixOrder{$_}});
        }
    }
    # tweak the table order
    my %tweakOrder = (
        JPEG    => '-',     # JPEG comes first
        IPTC    => 'Exif',  # put IPTC after EXIF,
        GPS     => 'XMP',   # etc...
        GeoTiff => 'GPS',
        Kodak   => 'JVC',
       'Kodak::IFD' => 'Kodak::Unknown',
       'Kodak::TextualInfo' => 'Kodak::IFD',
        Leaf    => 'Kodak',
        Minolta => 'Leaf',
        Unknown => 'Sony',
        DNG     => 'Unknown',
        PrintIM => 'ICC_Profile',
        ID3     => 'PostScript',
        MinoltaRaw => 'KyoceraRaw',
        Olympus => 'NikonCapture',
        Pentax  => 'Panasonic',
        Ricoh   => 'Pentax',
        Sanyo   => 'Ricoh',
        PhotoMechanic => 'FotoStation',
       'Pentax::LensData' => 'Pentax::LensInfo2',
    );
    my @tweak = sort keys %tweakOrder;
    while (@tweak) {
        my $table = shift @tweak;
        my $first = $tweakOrder{$table};
        if ($tweakOrder{$first}) {
            push @tweak, $table;    # must defer this till later
            next;
        }
        delete $tweakOrder{$table}; # because the table won't move again
        my @moving = grep /^Image::ExifTool::$table\b/, @sortedTables;
        my @notMoving = grep !/^Image::ExifTool::$table\b/, @sortedTables;
        my @after;
        while (@notMoving) {
            last if $notMoving[-1] =~ /^Image::ExifTool::$first\b/;
            unshift @after, pop @notMoving;
        }
        @sortedTables = (@notMoving, @moving, @after);
    }
    return @sortedTables
}

#------------------------------------------------------------------------------
# Open HTMLFILE and print header and description
# Inputs: 0) Filename, 1) optional category
# Returns: True on success
my %createdFiles;
sub OpenHtmlFile($;$$)
{
    my ($htmldir, $category, $sepTable) = @_;
    my ($htmlFile, $head, $title, $url, $class);
    my $top = '';

    if ($category) {
        my @names = split ' ', $category;
        $class = shift @names;
        $htmlFile = "$htmldir/TagNames/$class.html";
        $head = $category . ($sepTable ? ' Values' : ' Tags');
        ($title = $head) =~ s/ .* / /;
        @names and $url = join '_', @names;
    } else {
        $htmlFile = "$htmldir/TagNames/index.html";
        $category = $class = 'ExifTool';
        $head = $title = 'ExifTool Tag Names';
    }
    if ($createdFiles{$htmlFile}) {
        open(HTMLFILE,">>${htmlFile}_tmp") or return 0;
    } else {
        open(HTMLFILE,">${htmlFile}_tmp") or return 0;
        print HTMLFILE "$docType<html>\n<head>\n<title>$title</title>\n";
        print HTMLFILE "<link rel=stylesheet type='text/css' href='style.css' title='Style'>\n";
        print HTMLFILE "</head>\n<body>\n";
        if ($category ne $class and $docs{$class}) {
            print HTMLFILE "<h2 class=top>$class Tags</h2>\n" or return 0;
            print HTMLFILE '<p>',Doc2Html($docs{$class}),"</p>\n" or return 0;
        } else {
            $top = " class=top";
        }
    }
    $head = "<a name='$url'>$head</a>" if $url;
    print HTMLFILE "<h2$top>$head</h2>\n" or return 0;
    print HTMLFILE '<p>',Doc2Html($docs{$category}),"</p>\n" if $docs{$category};
    $createdFiles{$htmlFile} = 1;
    return 1;
}

#------------------------------------------------------------------------------
# Close all html files and write trailers
# Returns: true on success
# Inputs: 0) BuildTagLookup object reference
sub CloseHtmlFiles($)
{
    my $self = shift;
    my $preserveDate = $$self{PRESERVE_DATE};
    my $success = 1;
    # get the date
    my ($sec,$min,$hr,$day,$mon,$yr) = localtime;
    my @month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    $yr += 1900;
    my $date = "$month[$mon] $day, $yr";
    my $htmlFile;
    my $countNewFiles = 0;
    my $countSameFiles = 0;
    foreach $htmlFile (keys %createdFiles) {
        my $tmpFile = $htmlFile . '_tmp';
        my $fileDate = $date;
        if ($preserveDate) {
            my @lines = `grep '<i>Last revised' $htmlFile`;
            $fileDate = $1 if @lines and $lines[-1] =~ m{<i>Last revised (.*)</i>};
        }
        open(HTMLFILE,">>$tmpFile") or $success = 0, next;
        # write the trailers
        print HTMLFILE "<hr>\n";
        print HTMLFILE "(This document generated automatically by Image::ExifTool::BuildTagLookup)\n";
        print HTMLFILE "<br><i>Last revised $fileDate</i>\n";
        print HTMLFILE "<p class=lf><a href=";
        if ($htmlFile =~ /index\.html$/) {
            print HTMLFILE "'../index.html'>&lt;-- Back to ExifTool home page</a></p>\n";
        } else {
            print HTMLFILE "'index.html'>&lt;-- ExifTool Tag Names</a></p>\n"
        }
        print HTMLFILE "</body>\n</html>\n" or $success = 0;
        close HTMLFILE or $success = 0;
        # check for differences and only use new file if it was changed
        # (so the date only gets updated if changes were really made)
        my $useNewFile;
        if ($success) {
            open (TEMPFILE, $tmpFile) or $success = 0, last;
            if (open (HTMLFILE, $htmlFile)) {
                while (<HTMLFILE>) {
                    my $newLine = <TEMPFILE>;
                    if (defined $newLine) {
                        next if /^<br><i>Last revised/;
                        next if $_ eq $newLine;
                    }
                    # files are different -- use the new file
                    $useNewFile = 1;
                    last;
                }
                $useNewFile = 1 if <TEMPFILE>;
                close HTMLFILE;
            } else {
                $useNewFile = 1;
            }
            close TEMPFILE;
            if ($useNewFile) {
                ++$countNewFiles;
                rename $tmpFile, $htmlFile or warn("Error renaming temporary file\n"), $success = 0;
            } else {
                ++$countSameFiles;
                unlink $tmpFile;   # erase new file and use existing file
            }
        }
        last unless $success;
    }
    # save number of files processed so we can check the results later
    $self->{COUNT}->{'HTML files changed'} = $countNewFiles;
    $self->{COUNT}->{'HTML files unchanged'} = $countSameFiles;
    return $success;
}

#------------------------------------------------------------------------------
# Write the TagName HTML and POD documentation
# Inputs: 0) BuildTagLookup object reference
#         1) output pod file (ie. 'lib/Image/ExifTool/TagNames.pod')
#         2) output html directory (ie. 'html')
# Returns: true on success
sub WriteTagNames($$)
{
    my ($self, $podFile, $htmldir) = @_;
    my ($tableName, $short, $url, @sepTables);
    my $tagNameInfo = $self->{TAG_NAME_INFO} or return 0;
    my $idLabel = $self->{ID_LOOKUP};
    my $shortName = $self->{SHORT_NAME};
    my $sepTable = $self->{SEPARATE_TABLE};
    my $success = 1;
    my %htmlFiles;
    my $columns = 6;    # number of columns in html index
    my $percent = int(100 / $columns);

    # open the file and write the header
    open(PODFILE,">$podFile") or return 0;
    print PODFILE Doc2Pod($docs{PodHeader}), $docs{ExifTool}, $docs{ExifTool2};
    mkdir "$htmldir/TagNames";
    OpenHtmlFile($htmldir) or return 0;
    print HTMLFILE "<blockquote>\n";
    print HTMLFILE "<table width='100%' class=frame><tr><td>\n";
    print HTMLFILE "<table width='100%' class=inner cellspacing=1><tr class=h>\n";
    print HTMLFILE "<th colspan=$columns><span class=l>Tag Table Index</span></th></tr>\n";
    print HTMLFILE "<tr class=b><td width='$percent%'>\n";
    # write the index
    my @tableNames = GetTableOrder();
    push @tableNames, 'Image::ExifTool::Shortcuts::Main';   # do Shortcuts last
    # get list of headings and add any missing ones
    my $heading = 'xxx';
    my (@tableIndexNames, @headings);
    foreach $tableName (@tableNames) {
        $short = $$shortName{$tableName};
        my @names = split ' ', $short;
        my $class = shift @names;
        if (@names) {
            # add heading for tables without a Main
            unless ($heading eq $class) {
                $heading = $class;
                push @tableIndexNames, $heading;
                push @headings, $heading;
            }
        } else {
            $heading = $short;
            push @headings, $heading;
        }
        push @tableIndexNames, $tableName;
    }
    @tableNames = @tableIndexNames;
    # print html index of headings only
    my $count = 0;
    my $lines = int((scalar(@headings) + $columns - 1) / $columns);
    foreach $tableName (@headings) {
        if ($count) {
            if ($count % $lines) {
                print HTMLFILE "<br>\n";
            } else {
                print HTMLFILE "</td><td width='$percent%'>\n";
            }
        }
        $short = $$shortName{$tableName};
        $short = $tableName unless $short;
        $url = "$short.html";
        print HTMLFILE "<a href='$url'>$short</a>";
        ++$count;
    }
    print HTMLFILE "\n</td></tr></table></td></tr></table></blockquote>\n";
    print HTMLFILE '<p>',Doc2Html($docs{ExifTool2}),"</p>\n";
    # write all the tag tables
    while (@tableNames or @sepTables) {
        while (@sepTables) {
            $tableName = shift @sepTables;
            my $printConv = $$sepTable{$tableName};
            next unless ref $printConv eq 'HASH';
            $$sepTable{$tableName} = 1;
            my $notes = $$printConv{Notes};
            if ($notes) {
                # remove unnecessary whitespace
                $notes =~ s/(^\s+|\s+$)//g;
                $notes =~ s/(^[ \t]+|[ \t]+$)//mg;
            }
            my $head = $tableName;
            $head =~ s/.* //;
            close HTMLFILE;
            if (OpenHtmlFile($htmldir, $tableName, 1)) {
                print HTMLFILE Doc2Html($notes), "\n" if $notes;
                print HTMLFILE "<blockquote>\n";
                print HTMLFILE "<table class=frame><tr><td>\n";
                print HTMLFILE "<table class='inner sep' cellspacing=1>\n";
                my $align = ' class=r';
                my $wid = 0;
                my @keys;
                foreach (sort NumbersFirst keys %$printConv) {
                    next if /^(Notes|PrintHex)$/;
                    $align = '' if $align and /[^\d]/;
                    my $w = length($_) + length($$printConv{$_});
                    $wid = $w if $wid < $w;
                    push @keys, $_;
                }
                $wid = length($tableName)+7 if $wid < length($tableName)+7;
                # print in multiple columns if there is room
                my $cols = int(80 / ($wid + 4));
                $cols = 1 if $cols < 1 or $cols > @keys;
                my $rows = int((scalar(@keys) + $cols - 1) / $cols);
                my ($r, $c);
                print HTMLFILE '<tr class=h>';
                for ($c=0; $c<$cols; ++$c) {
                    print HTMLFILE "<th>Value</th><th>$head</th>";
                }
                print HTMLFILE "</tr>\n";
                for ($r=0; $r<$rows; ++$r) {
                    print HTMLFILE '<tr>';
                    for ($c=0; $c<$cols; ++$c) {
                        my $key = $keys[$r + $c*$rows];
                        my ($index, $prt);
                        if (defined $key) {
                            $index = $key;
                            $prt = "= $$printConv{$key}";
                            if ($$printConv{PrintHex}) {
                                $index = sprintf('0x%x',$index);
                            } elsif ($index !~ /^[-+]?\d+$/) {
                                $index = "'" . EscapeHTML($index) . "'";
                            }
                        } else {
                            $index = $prt = '&nbsp;';
                        }
                        my ($ic, $pc);
                        if ($c & 0x01) {
                            $pc = ' class=b';
                            $ic = $align ? " class='r b'" : $pc;
                        } else {
                            $ic = $align;
                            $pc = '';
                        }
                        print HTMLFILE "<td$ic>$index</td><td$pc>$prt</td>\n";
                    }
                    print HTMLFILE '</tr>';
                }
                print HTMLFILE "</table></td></tr></table></blockquote>\n\n";
            }
        }
        last unless @tableNames;
        $tableName = shift @tableNames;
        $short = $$shortName{$tableName};
        unless ($short) {
            # this is just an index heading
            print PODFILE "\n=head2 $tableName Tags\n";
            print PODFILE $docs{$tableName} if $docs{$tableName};
            next;
        }
        my $info = $$tagNameInfo{$tableName};
        my $id = $$idLabel{$tableName};
        my ($hid, $showGrp);
        # widths of the different columns in the POD documentation
        my ($wID,$wTag,$wReq,$wGrp) = (8,36,24,10);
        my $composite = $short eq 'Composite' ? 1 : 0;
        my $derived = $composite ? '<th>Derived From</th>' : '';
        if ($short eq 'Shortcuts') {
            $derived = '<th>Refers To</th>';
            $composite = 2;
        }
        my $podIdLen = $self->{LONG_ID}->{$tableName};
        my $notes;
        unless ($composite == 2) {
            my $table = GetTagTable($tableName);
            $notes = $$table{NOTES};
        }
        my $prefix;
        if ($notes) {
            # remove unnecessary whitespace
            $notes =~ s/(^\s+|\s+$)//g;
            $notes =~ s/(^[ \t]+|[ \t]+$)//mg;
            if ($notes =~ /leading '(.*?_)' which/) {
                $prefix = $1;
                $podIdLen -= length $prefix;
            }
        }
        if ($podIdLen <= $wID) {
            $podIdLen = $wID;
        } elsif ($short eq 'DICOM') {
            $podIdLen = 10;
        } else {
            # align tag names in secondary columns if possible
            my $col = ($podIdLen <= 10) ? 12 : 20;
            $podIdLen = $col if $podIdLen < $col;
        }
        $id = '' if $short =~ /^XMP/;
        if ($id) {
            ($hid = "<th>$id</th>") =~ s/ /&nbsp;/g;
            $wTag -= $podIdLen - $wID;
            $wID = $podIdLen;
            my $longTag = $self->{LONG_NAME}->{$tableName};
            if ($wTag < $longTag) {
                $wID -= $longTag - $wTag;
                $wTag = $longTag;
                warn "Notice: Long tags in $tableName table\n";
            }
        } elsif ($short !~ /^(Composite|Shortcuts)/) {
            $wTag += 9;
            $hid = '';
        } else {
            $hid = '';
            $wTag += $wID - $wReq if $composite;
        }
        if ($short eq 'EXIF') {
            $derived = '<th>Group</th>';
            $showGrp = 1;
            $wTag -= $wGrp + 1;
        }
        my $head = ($short =~ / /) ? 'head3' : 'head2';
        print PODFILE "\n=$head $short Tags\n";
        print PODFILE $docs{$short} if $docs{$short};
        print PODFILE "\n$notes\n" if $notes;
        my $line = "\n";
        if ($id) {
            # shift over 'Index' heading by one character for a bit more balance
            $id = " $id" if $id eq 'Index';
            $line .= sprintf "  %-${wID}s", $id;
        } else {
            $line .= ' ';
        }
        my $tagNameHeading = ($short eq 'XMP') ? 'Namespace' : 'Tag Name';
        $line .= sprintf " %-${wTag}s", $tagNameHeading;
        $line .= sprintf " %-${wReq}s", $composite == 2 ? 'Refers To' : 'Derived From' if $composite;
        $line .= sprintf " %-${wGrp}s", 'Group' if $showGrp;
        $line .= ' Writable';
        print PODFILE $line;
        $line =~ s/^(\s*\w.{6}\w) /$1\t/;   # change space to tab after long ID label (ie. "Sequence")
        $line =~ s/\S/-/g;
        $line =~ s/- -/---/g;
        $line =~ tr/\t/ /;                  # change tab back to space
        print PODFILE $line,"\n";
        close HTMLFILE;
        OpenHtmlFile($htmldir, $short) or $success = 0;
        print HTMLFILE '<p>',Doc2Html($notes), "</p>\n" if $notes;
        print HTMLFILE "<blockquote>\n";
        print HTMLFILE "<table class=frame><tr><td>\n";
        print HTMLFILE "<table class=inner cellspacing=1>\n";
        print HTMLFILE "<tr class=h>$hid<th>$tagNameHeading</th>\n";
        print HTMLFILE "<th>Writable</th>$derived<th>Values / ${noteFont}Notes</span></th></tr>\n";
        my $rowClass = 1;
        my $infoCount = 0;
        my $infoList;
        foreach $infoList (@$info) {
            ++$infoCount;
            my ($tagIDstr, $tagNames, $writable, $values, $require, $writeGroup) = @$infoList;
            my ($align, $idStr, $w);
            if (not $id) {
                $idStr = '  ';
            } elsif ($tagIDstr =~ /^\d+(\.\d+)?$/) {
                $w = $wID - 3;
                $idStr = sprintf "  %${w}g    ", $tagIDstr;
                $align = " class=r";
            } else {
                $tagIDstr =~ s/^'$prefix/'/ if $prefix;
                $w = $wID;
                if (length $tagIDstr > $w) {
                    # put tag name on next line if ID is too long
                    $idStr = "  $tagIDstr\n   " . (' ' x $w);
                    warn "Notice: Split $$tagNames[0] line\n";
                } else {
                    $idStr = sprintf "  %-${w}s ", $tagIDstr;
                }
                $align = '';
            }
            my @reqs;
            my @tags = @$tagNames;
            my @wGrp = @$writeGroup;
            my @vals = @$writable;
            my $wrStr = shift @vals;
            my $subdir;
            # if this is a subdirectory, print subdir name (from values) instead of writable
            if ($wrStr =~ /^-/) {
                $subdir = 1;
                @vals = @$values;
                # remove Notes if subdir has Notes as well
                shift @vals if $vals[0] =~ /^\(/ and @vals >= @$writable;
                foreach (@vals) { /^\(/ and $_ = '-' }
                my $i;  # fill in any missing entries from non-directory tags
                for ($i=0; $i<@$writable; ++$i) {
                    $vals[$i] = $$writable[$i] unless defined $vals[$i];
                }
                if ($$sepTable{$vals[0]}) {
                    $wrStr =~ s/^-//;
                    $wrStr = 'N' unless $wrStr;
                } else {
                    $wrStr = $vals[0];
                }
                shift @vals;
            }
            my $tag = shift @tags;
            printf PODFILE "%s%-${wTag}s", $idStr, $tag;
            warn "Warning: Pushed $tag\n" if $id and length($tag) > $wTag;
            printf PODFILE " %-${wGrp}s", shift(@wGrp) || '-' if $showGrp;
            if ($composite) {
                @reqs = @$require;
                $w = $wReq; # Keep writable column in line
                length($tag) > $wTag and $w -= length($tag) - $wTag;
                printf PODFILE " %-${w}s", shift(@reqs) || '';
            }
            printf PODFILE " $wrStr\n";
            my $numTags = scalar @$tagNames;
            my $n = 0;
            while (@tags or @reqs or @vals) {
                my $more = (@tags or @reqs);
                $line = '  ';
                $line .= ' 'x($wID+1) if $id;
                $line .= sprintf("%-${wTag}s", shift(@tags) || '');
                $line .= sprintf(" %-${wReq}s", shift(@reqs) || '') if $composite;
                $line .= sprintf(" %-${wGrp}s", shift(@wGrp) || '-') if $showGrp;
                ++$n;
                if (@vals) {
                    my $val = shift @vals;
                    # use writable if this is a note
                    my $wrStr = $$writable[$n];
                    if ($subdir and ($val =~ /^\(/ or $val =~ /=/ or ($wrStr and $wrStr !~ /^-/))) {
                        $val = $wrStr;
                        if (defined $val) {
                            $val =~ s/^-//;
                        } else {
                            # done with tag if nothing else to print
                            last unless $more;
                        }
                    }
                    $line .= " $val" if defined $val;
                }
                $line =~ s/\s+$//;  # trim trailing white space
                print PODFILE "$line\n";
            }
            my @htmlTags;
            foreach (@$tagNames) {
                push @htmlTags, EscapeHTML($_);
            }
            $rowClass = $rowClass ? '' : " class=b";
            my $isSubdir;
            if ($$writable[0] =~ /^-/) {
                $isSubdir = 1;
                foreach (@$writable) {
                    s/^-(.+)/$1/;
                }
            }
            print HTMLFILE "<tr$rowClass>\n";
            print HTMLFILE "<td$align>$tagIDstr</td>\n" if $id;
            print HTMLFILE "<td>", join("\n  <br>",@htmlTags), "</td>\n";
            print HTMLFILE "<td class=c>",join('<br>',@$writable),"</td>\n";
            print HTMLFILE '<td>',join("\n  <br>",@$require),"</td>\n" if $composite;
            print HTMLFILE "<td class=c>",join('<br>',@$writeGroup),"</td>\n" if $showGrp;
            print HTMLFILE "<td>";
            my $close = '';
            my @values;
            if (@$values) {
                if ($isSubdir) {
                    my $smallNote;
                    foreach (@$values) {
                        if (/^[[(]/) {
                            $smallNote = 1 if $numTags < 2;
                            push @values, ($smallNote ? $noteFontSmall : $noteFont) . "$_</span>";
                            next;
                        }
                        /=/ and push(@values, $_), next;
                        my @names = split;
                        $url = (shift @names) . '.html';
                        @names and $url .= '#' . join '_', @names;
                        my $suffix = ' Tags';
                        if ($$sepTable{$_}) {
                            push @sepTables, $_;
                            $suffix = ' Values';
                        }
                        push @values, "--&gt; <a href='$url'>$_$suffix</a>";
                    }
                    # put small note last
                    $smallNote and push @values, shift @values;
                } else {
                    foreach (@$values) {
                        $_ = EscapeHTML($_);
                        /^\(/ and $_ = "$noteFont$_</span>";
                        push @values, $_;
                    }
                    print HTMLFILE "<span class=s>";
                    $close = '</span>';
                }
            } else {
                push @values, '&nbsp;';
            }
            print HTMLFILE join("\n  <br>",@values),"$close</td></tr>\n";
        }
        unless ($infoCount) {
            printf PODFILE "  [no tags known]\n";
            my $cols = 3;
            ++$cols if $hid;
            ++$cols if $derived;
            print HTMLFILE "<tr><td colspan=$cols class=c>[no tags known]</td></tr>\n";
        }
        print HTMLFILE "</table></td></tr></table></blockquote>\n\n";
    }
    close(HTMLFILE) or $success = 0;
    CloseHtmlFiles($self) or $success = 0;
    print PODFILE Doc2Pod($docs{PodTrailer}) or $success = 0;
    close(PODFILE) or $success = 0;
    return $success;
}

1;  # end


__END__

=head1 NAME

Image::ExifTool::BuildTagLookup - Build ExifTool tag lookup tables

=head1 DESCRIPTION

This module is used to generate the tag lookup tables in
Image::ExifTool::TagLookup.pm and tag name documentation in
Image::ExifTool::TagNames.pod, as well as HTML tag name documentation.  It
is used before each new ExifTool release to update the lookup tables and
documentation.

=head1 SYNOPSIS

  use Image::ExifTool::BuildTagLookup;

  $builder = new Image::ExifTool::BuildTagLookup;

  $ok = $builder->WriteTagLookup('lib/Image/ExifTool/TagLookup.pm');

  $ok = $builder->WriteTagNames('lib/Image/ExifTool/TagNames.pod','html');

=head1 MEMBER VARIABLES

=over 4

=item PRESERVE_DATE

Flag to preserve "Last revised" date in HTML files.  Set before calling
WriteTagNames().

=item COUNT

Reference to hash containing counting statistics.  Keys are the
descriptions, and values are the numerical counts.  Valid after
BuildTagLookup object is created, but additional statistics are added by
WriteTagNames().

=back

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool(3pm)|Image::ExifTool>,
L<Image::ExifTool::TagLookup(3pm)|Image::ExifTool::TagLookup>,
L<Image::ExifTool::TagNames(3pm)|Image::ExifTool::TagNames>

=cut
