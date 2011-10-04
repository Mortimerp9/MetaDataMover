#------------------------------------------------------------------------------
# File:         HP.pm
#
# Description:  Hewlett-Packard maker notes tags
#
# Revisions:    2007-05-03 - P. Harvey Created
#------------------------------------------------------------------------------

package Image::ExifTool::HP;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);

$VERSION = '1.01';

sub ProcessHP($$$);

# HP EXIF-format maker notes (or is it Vivitar?)
%Image::ExifTool::HP::Main = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => q{
        These tables list tags found in the maker notes of some Hewlett-Packard
        camera models.
        
        The first table lists tags found in the EXIF-format maker notes of the
        PhotoSmart 720 (also used by the Vivitar ViviCam 3705, 3705B and 3715).
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
);

# other types of HP maker notes
%Image::ExifTool::HP::Type2 = (
    PROCESS_PROC => \&ProcessHP,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are used by the PhotoSmart E427.',
   'PreviewImage' => {
        Name => 'PreviewImage',
        RawConv => '$self->ValidateImage(\$val,$tag)',
    },
   'Serial Number' => 'SerialNumber',
   'Lens Shading'  => 'LensShading',
);

%Image::ExifTool::HP::Type4 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are used by the PhotoSmart M627.',
    0x0c => {
        Name => 'MaxAperture',
        Format => 'int16u',
        ValueConv => '$val / 10',
    },
    0x10 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e6',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x14 => {
        Name => 'CameraDateTime',
        Groups => { 2 => 'Time' },
        Format => 'string[20]',
    },
    0x34 => {
        Name => 'ISO',
        Format => 'int16u',
    },
    0x5c => {
        Name => 'SerialNumber',
        Format => 'string[26]',
        RawConv => '$val =~ s/^SERIAL NUMBER:// ? $val : undef',
    },
);

%Image::ExifTool::HP::Type6 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are used by the PhotoSmart M425, M525 and M527.',
    0x0c => {
        Name => 'FNumber',
        Format => 'int16u',
        ValueConv => '$val / 10',
    },
    0x10 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e6',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x14 => {
        Name => 'CameraDateTime',
        Groups => { 2 => 'Time' },
        Format => 'string[20]',
    },
    0x34 => {
        Name => 'ISO',
        Format => 'int16u',
    },
    0x58 => {
        Name => 'SerialNumber',
        Format => 'string[26]',
        RawConv => '$val =~ s/^SERIAL NUMBER:// ? $val : undef',
    },
);

#------------------------------------------------------------------------------
# Process HP maker notes
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success, otherwise returns 0 and sets a Warning
sub ProcessHP($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dataLen = $$dirInfo{DataLen};
    my $dirStart = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen} || $dataLen - $dirStart;

    # look for known text-type tags
    if ($dirStart or $dirLen != length($$dataPt)) {
        my $buff = substr($$dataPt, $dirStart, $dirLen);
        $dataPt = \$buff;
    }
    my $tagID;
    # brute-force scan for PreviewImage
    if ($$tagTablePtr{PreviewImage} and $$dataPt =~ /(\xff\xd8\xff\xdb.*\xff\xd9)/gs) {
        $exifTool->HandleTag($tagTablePtr, 'PreviewImage', $1);
        # truncate preview to speed subsequent tag scans
        my $buff = substr($$dataPt, 0, pos($$dataPt)-length($1));
        $dataPt = \$buff;
    }
    # scan for other tag ID's
    foreach $tagID (sort(TagTableKeys($tagTablePtr))) {
        next if $tagID eq 'PreviewImage';
        next unless $$dataPt =~ /$tagID:\s*([\x20-\x7f]+)/i;
        $exifTool->HandleTag($tagTablePtr, $tagID, $1);
    }
    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::HP - Hewlett-Packard maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Hewlett-Packard maker notes.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/HP Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
