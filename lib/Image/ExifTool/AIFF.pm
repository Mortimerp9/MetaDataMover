#------------------------------------------------------------------------------
# File:         AIFF.pm
#
# Description:  Read AIFF meta information
#
# Revisions:    01/06/2006 - P. Harvey Created
#
# References:   1) http://developer.apple.com/documentation/QuickTime/INMAC/SOUND/imsoundmgr.30.htm#pgfId=3190
#               2) http://astronomy.swin.edu.au/~pbourke/dataformats/aiff/
#               3) http://www.mactech.com/articles/mactech/Vol.06/06.01/SANENormalized/
#------------------------------------------------------------------------------

package Image::ExifTool::AIFF;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::ID3;

$VERSION = '1.01';

# information for time/date-based tags (time zero is Jan 1, 1904)
my %timeInfo = (
    Groups => { 2 => 'Time' },
    ValueConv => 'ConvertUnixTime($val - ((66 * 365 + 17) * 24 * 3600))',
    PrintConv => '$self->ConvertDateTime($val)',
);

# AIFF info
%Image::ExifTool::AIFF::Main = (
    PROCESS_PROC => \&Image::ExifTool::AIFF::ProcessSubChunks,
    GROUPS => { 2 => 'Audio' },
    NOTES => 'Only the tags decoded by ExifTool are listed in this table.',
#    FORM => 'Format',
    FVER => {
        Name => 'FormatVersion',
        SubDirectory => { TagTable => 'Image::ExifTool::AIFF::FormatVers' },
    },
    COMM => {
        Name => 'Common',
        SubDirectory => { TagTable => 'Image::ExifTool::AIFF::Common' },
    },
    COMT => {
        Name => 'Comment',
        SubDirectory => { TagTable => 'Image::ExifTool::AIFF::Comment' },
    },
    NAME => 'Name',
    AUTH => { Name => 'Author', Groups => { 2 => 'Author' } },
   '(c) ' => { Name => 'Copyright', Groups => { 2 => 'Author' } },
    ANNO => 'Annotation',
   'ID3 ' => {
        Name => 'ID3',
        SubDirectory => {
            TagTable => 'Image::ExifTool::ID3::Main',
            ProcessProc => \&Image::ExifTool::ID3::ProcessID3,
        },
    },
#    SSND => 'SoundData',
#    MARK => 'Marker',
#    INST => 'Instrument',
#    MIDI => 'MidiData',
#    AESD => 'AudioRecording',
#    APPL => 'ApplicationSpecific',
);

%Image::ExifTool::AIFF::Common = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Audio' },
    FORMAT => 'int16u',
    0 => 'NumChannels',
    1 => { Name => 'NumSampleFrames', Format => 'int32u' },
    3 => 'SampleSize',
    4 => { Name => 'SampleRate', Format => 'extended' }, #3
    9 => {
        Name => 'CompressionType',
        Format => 'string[4]',
        PrintConv => {
            NONE => 'None',
            ACE2 => 'ACE 2-to-1',
            ACE8 => 'ACE 8-to-3',
            MAC3 => 'MAC 3-to-1',
            MAC6 => 'MAC 6-to-1',
            sowt => 'Little-endian, no compression',
        },
    },
);

%Image::ExifTool::AIFF::FormatVers = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    FORMAT => 'int32u',
    0 => { Name => 'FormatVersionTime', %timeInfo },
);

%Image::ExifTool::AIFF::Comment = (
    PROCESS_PROC => \&Image::ExifTool::AIFF::ProcessComment,
    GROUPS => { 2 => 'Audio' },
    0 => { Name => 'CommentTime', %timeInfo },
    1 => 'MarkerID',
    2 => 'Comment',
);

#------------------------------------------------------------------------------
# Process AIFF Comment chunk
# Inputs: 0) ExifTool object reference, 1) DirInfo reference, 2) tag table ref
# Returns: 1 on success
sub ProcessComment($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    my $verbose = $exifTool->Options('Verbose');
    return 0 unless $dirLen > 2;
    my $numComments = unpack('n',$$dataPt);
    my $pos = 2;
    my $i;
    $verbose and $exifTool->VerboseDir('Comment', $numComments);
    for ($i=0; $i<$numComments; ++$i) {
        last if $pos + 8 > $dirLen;
        my ($time, $markerID, $size) = unpack("x${pos}Nnn", $$dataPt);
        $exifTool->HandleTag($tagTablePtr, 0, $time);
        $exifTool->HandleTag($tagTablePtr, 1, $markerID) if $markerID;
        $pos += 8;
        last if $pos + $size > $dirLen;
        my $val = substr($$dataPt, $pos, $size);
        $exifTool->HandleTag($tagTablePtr, 2, $val);
        ++$size if $size & 0x01;    # account for padding byte if necessary
        $pos += $size;
    }
}

#------------------------------------------------------------------------------
# Extract information from a AIFF file
# Inputs: 0) ExifTool object reference, 1) DirInfo reference
# Returns: 1 on success, 0 if this wasn't a valid AIFF file
sub ProcessAIFF($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $verbose = $exifTool->Options('Verbose');
    my ($buff, $err);

    # verify this is a valid AIFF file
    return 0 unless $raf->Read($buff, 12) == 12;
    return 0 unless $buff =~ /^FORM....(AIF(F|C))/s;
    $exifTool->SetFileType($1);
    SetByteOrder('MM');
    my $tagTablePtr = GetTagTable('Image::ExifTool::AIFF::Main');
    my $pos = 12;
#
# Read chunks in AIFF image
#
    for (;;) {
        $raf->Read($buff, 8) == 8 or last;
        $pos += 8;
        my ($tag, $len) = unpack('a4N', $buff);
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        $exifTool->VPrint(0, "AIFF '$tag' chunk ($len bytes of data):\n");
        # AIFF chunks are padded to an even number of bytes
        my $len2 = $len + ($len & 0x01);
        if ($tagInfo) {
            $raf->Read($buff, $len2) == $len2 or $err=1, last;
            $exifTool->HandleTag($tagTablePtr, $tag, $buff,
                DataPt => \$buff,
                DataPos => $pos,
                Start => 0,
                Size => $len,
            );
        } else {
            $raf->Seek($len2, 1) or $err=1, last;
        }
        $pos += $len2;
    }
    $err and $exifTool->Warn('Error reading AIFF file (corrupted?)');
    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::AIFF - Read AIFF meta information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract
information from AIFF (Audio Interchange File Format) audio files.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://developer.apple.com/documentation/QuickTime/INMAC/SOUND/imsoundmgr.30.htm#pgfId=3190>

=item L<http://astronomy.swin.edu.au/~pbourke/dataformats/aiff/>

=item L<http://www.mactech.com/articles/mactech/Vol.06/06.01/SANENormalized/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/AIFF Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

