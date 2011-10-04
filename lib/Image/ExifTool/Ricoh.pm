#------------------------------------------------------------------------------
# File:         Ricoh.pm
#
# Description:  Ricoh EXIF maker notes tags
#
# Revisions:    03/28/2005 - P. Harvey Created
#
# References:   1) http://www.ozhiker.com/electronics/pjmt/jpeg_info/ricoh_mn.html
#               2) http://homepage3.nifty.com/kamisaka/makernote/makernote_ricoh.htm
#------------------------------------------------------------------------------

package Image::ExifTool::Ricoh;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.06';

sub ProcessRicohText($$$);
sub ProcessRicohRMETA($$$);

%Image::ExifTool::Ricoh::Main = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    NOTES => 'These tags are used by Ricoh Caplio camera models.',
    0x0001 => { Name => 'MakerNoteType',    Writable => 'string' },
    0x0002 => { Name => 'MakerNoteVersion', Writable => 'string' },
    0x0e00 => {
        Name => 'PrintIM',
        Writable => 0,
        Description => 'Print Image Matching',
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
    0x1001 => {
        Name => 'ImageInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Ricoh::ImageInfo',
        },
    },
    0x1003 => {
        Name => 'Sharpness',
        Writable => 'int32u',
        PrintConv => {
            0 => 'Sharp',
            1 => 'Normal',
            2 => 'Soft',
        },
    },
    0x2001 => [
        {
            Name => 'RicohSubdir',
            Condition => '$self->{Model} !~ /^Caplio RR1\b/',
            SubDirectory => {
                Validate => '$val =~ /^\[Ricoh Camera Info\]/',
                TagTable => 'Image::ExifTool::Ricoh::Subdir',
                Start => '$valuePtr + 20',
                ByteOrder => 'BigEndian',
            },
        },
        {
            Name => 'RicohRR1Subdir',
            SubDirectory => {
                Validate => '$val =~ /^\[Ricoh Camera Info\]/',
                TagTable => 'Image::ExifTool::Ricoh::Subdir',
                Start => '$valuePtr + 20',
                ByteOrder => 'BigEndian',
                # the Caplio RR1 uses a different base address -- doh!
                Base => '$start-20',
            },
        },
    ],
);

# Ricoh image info (ref 2)
%Image::ExifTool::Ricoh::ImageInfo = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    PRIORITY => 0,
    FORMAT => 'int8u',
    FIRST_ENTRY => 0,
    IS_OFFSET => [ 28 ],   # tag 28 is 'IsOffset'
    0 => {
        Name => 'RicohImageWidth',
        Format => 'int16u',
    },
    2 => {
        Name => 'RicohImageHeight',
        Format => 'int16u',
    },
    6 => {
        Name => 'RicohDate',
        Groups => { 2 => 'Time' },
        Format => 'int8u[7]',
        # (what an insane way to encode the date)
        ValueConv => q{
            sprintf("%.2x%.2x:%.2x:%.2x %.2x:%.2x:%.2x",
                    split(' ', $val));
        },
        ValueConvInv => q{
            my @vals = ($val =~ /(\d{1,2})/g);
            push @vals, 0 if @vals < 7;
            join(' ', map(hex, @vals));
        },
    },
    28 => {
        Name => 'PreviewImageStart',
        Format => 'int16u',
        Flags => 'IsOffset',
        OffsetPair => 30,   # associated byte count tagID
        DataTag => 'PreviewImage',
        Protected => 2,
    },
    30 => {
        Name => 'PreviewImageLength',
        Format => 'int16u',
        OffsetPair => 28,   # point to associated offset
        DataTag => 'PreviewImage',
        Protected => 2,
    },
    32 => {
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Off',
            1 => 'Auto', #PH
            2 => 'On',
        },
    },
    33 => {
        Name => 'Macro',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    34 => {
        Name => 'Sharpness',
        PrintConv => {
            0 => 'Sharp',
            1 => 'Normal',
            2 => 'Soft',
        },
    },
    38 => {
        Name => 'WhiteBalance',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Cloudy',
            3 => 'Tungsten',
            4 => 'Fluorescent',
            # 5 (One Pushes, flake setting?)
            # 7 (details setting?)
        },
    },
    39 => {
        Name => 'ISOSetting',
        PrintConv => {
            0 => 'Auto',
            1 => 64,
            2 => 100,
            4 => 200,
            6 => 400,
            7 => 800,
            8 => 1600,
        },
    },
    40 => {
        Name => 'Saturation',
        PrintConv => {
            0 => 'High',
            1 => 'Normal',
            2 => 'Low',
            3 => 'None (B&W)',
        },
    },
);

# NOTE: this subdir is not currently writable because the offsets would require
# special code to handle the funny start location and base offset
%Image::ExifTool::Ricoh::Subdir = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    0x0004 => { Name => 'RicohDateTime1', Groups => { 2 => 'Time' } }, #PH
    0x0005 => { Name => 'RicohDateTime2', Groups => { 2 => 'Time' } }, #PH
    # 0x000E ProductionNumber? (ref 2)
);

# Ricoh text-type maker notes (PH)
%Image::ExifTool::Ricoh::Text = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&ProcessRicohText,
    NOTES => q{
        Ricoh RDC models such as the RDC-i700, RDC-5000, RDC-6000, RDC-7 and
        RDC-4300 use a text-based format for their maker notes instead of the IFD
        format used by the Caplio models.  Below is a list of known tags in this
        information.
    },
    Rev => 'Revision',
    Rv => 'Revision',
    Rg => 'RedGain',
    Gg => 'GreenGain',
    Bg => 'BlueGain',
);

%Image::ExifTool::Ricoh::RMETA = (
    GROUPS => { 0 => 'APP5', 1 => 'RMETA', 2 => 'Image' },
    PROCESS_PROC => \&Image::ExifTool::Ricoh::ProcessRicohRMETA,
    NOTES => q{
        The Ricoh Caplio Pro G3 has the ability to add custom fields to the APP5
        "RMETA" segment of JPEG images.  While only a few observed tags have been
        defined below, ExifTool will extract any information found here.
    },
    'Sign type' => { Name => 'SignType', PrintConv => {
        1 => 'Directional',
        2 => 'Warning',
        3 => 'Information',
    } },
    Location => { PrintConv => {
        1 => 'Verge',
        2 => 'Gantry',
        3 => 'Central reservation',
        4 => 'Roundabout',
    } },
    Lit => { PrintConv => {
        1 => 'Yes',
        2 => 'No',
    } },
    Condition => { PrintConv => {
        1 => 'Good',
        2 => 'Fair',
        3 => 'Poor',
        4 => 'Damaged',
    } },
    Azimuth => { PrintConv => {
        1 => 'N',
        2 => 'NNE',
        3 => 'NE',
        4 => 'ENE',
        5 => 'E',
        6 => 'ESE',
        7 => 'SE',
        8 => 'SSE',
        9 => 'S',
        10 => 'SSW',
        11 => 'SW',
        12 => 'WSW',
        13 => 'W',
        14 => 'WNW',
        15 => 'NW',
        16 => 'NNW',
    } },
);

# information stored in Ricoh AVI images (ref PH)
%Image::ExifTool::Ricoh::AVI = (
    PROCESS_PROC => \&Image::ExifTool::RIFF::ProcessChunks,
    ucmt => {
        Name => 'Comment',
        ValueConv => '$_=$val; s/^Unicode//; tr/\0//d; s/\s+$//; $_',
    },
    mnrt => {
        Name => 'MakerNoteRicoh',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Ricoh::Main',
            Start => '$valuePtr + 8',
            ByteOrder => 'BigEndian',
            Base => '8',
        },
    },
    rdc2 => {
        Name => 'RicohRDC2',
        Unknown => 1,
        ValueConv => 'unpack("H*",$val)',
        # have seen values like 0a000444 and 00000000 - PH
    },
    thum => {
        Name => 'ThumbnailImage',
        Binary => 1,
    },
);

#------------------------------------------------------------------------------
# Process Ricoh text-based maker notes
# Inputs: 0) ExifTool object reference
#         1) Reference to directory information hash
#         2) Pointer to tag table for this directory
# Returns: 1 on success, otherwise returns 0 and sets a Warning
sub ProcessRicohText($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dataLen = $$dirInfo{DataLen};
    my $dirStart = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen} || $dataLen - $dirStart;
    my $verbose = $exifTool->Options('Verbose');

    my $data = substr($$dataPt, $dirStart, $dirLen);
    return 1 if $data =~ /^\0/;     # blank Ricoh maker notes
    # validate text maker notes
    unless ($data =~ /^(Rev|Rv)/) {
        $exifTool->Warn('Bad Ricoh maker notes');
        return 0;
    }
    my $pos = 0;
    while ($data =~ m/([A-Z][a-z]{1,2})([0-9A-F]+);/sg) {
        my $tag = $1;
        my $val = $2;
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        if ($verbose) {
            $exifTool->VerboseInfo($tag, $tagInfo,
                Table  => $tagTablePtr,
                Value  => $val,
            );
        }
        unless ($tagInfo) {
            next unless $exifTool->{OPTIONS}->{Unknown};
            $tagInfo = {
                Name => "Ricoh_Text_$tag",
                Unknown => 1,
                PrintConv => 'length($val) > 60 ? substr($val,0,55) . "[...]" : $val',
            };
            # add tag information to table
            Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
        }
        $exifTool->FoundTag($tagInfo, $val);
    }
    return 1;
}

#------------------------------------------------------------------------------
# Process Ricoh APP5 RMETA information
# Inputs: 0) ExifTool object reference
#         1) Reference to directory information hash
#         2) Pointer to tag table for this directory
# Returns: 1 on success, otherwise returns 0 and sets a Warning
sub ProcessRicohRMETA($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dirStart = $$dirInfo{DirStart};
    my $dataLen = length($$dataPt);
    my $verbose = $exifTool->Options('Verbose');

    $dataLen > 6 or $exifTool->Warn('Truncated Ricoh RMETA data'), return 0;
    my $byteOrder = substr($$dataPt, $dirStart, 2);
    SetByteOrder($byteOrder) or $exifTool->Warn('Bad Ricoh RMETA data'), return 0;
    my (@tags, @vals, @nums, $valPos);
    my $pos = $dirStart + 6;
    while ($pos <= $dataLen - 4) {
        my $type = Get16u($dataPt, $pos);
        my $size = Get16u($dataPt, $pos + 2);
        $pos += 4;
        $size -= 2;
        if ($size < 0 or $pos + $size > $dataLen) {
            $exifTool->Warn('Corrupted Ricoh RMETA data');
            last;
        }
        if ($type eq 1) {
            # save the tag names
            my $tags = substr($$dataPt, $pos, $size);
            $tags =~ s/\0+$//;  # remove trailing nulls
            @tags = split /\0/, $tags;
        } elsif ($type eq 2) {
            # save the ASCII tag values
            my $vals = substr($$dataPt, $pos, $size);
            $vals =~ s/\0+$//;
            @vals = split /\0/, $vals;
            $valPos = $pos; # save position of first ASCII value
        } elsif ($type eq 3) {
            # save the numerical tag values
            my $nums = substr($$dataPt, $pos, $size);
            @nums = unpack($byteOrder eq 'MM' ? 'n*' : 'v*', $nums);
        } elsif ($type eq 0) {
            $pos += 2;  # why 2 extra bytes?
        }
        $pos += $size;
    }
    if (@tags or @vals) {
        if (@tags != @vals) {
            my ($nt, $nv) = (scalar(@tags), scalar(@vals));
            $exifTool->Warn("Number of tags ($nt) and values ($nv) differs in Ricoh RMETA");
        }
        # find next tag in null-delimited list
        # unpack numerical values from block of int16u values
        my ($tag, $name, $val);
        foreach $tag (@tags) {
            $val = shift @vals;
            last unless defined $val;
            ($name = $tag) =~ s/\b([a-z])/\U$1/gs;  # make capitalize all words
            $name =~ s/ (\w)/\U$1/g;                # remove special characters
            $name = 'RMETA_Unknown' unless length($name);
            my $num = shift @nums;
            my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
            if ($tagInfo) {
                # make sure print conversion is defined
                $$tagInfo{PrintConv} = { } unless $$tagInfo{PrintConv};
            } else {
                # create tagInfo hash
                $tagInfo = { Name => $name, PrintConv => { } };
                Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
            }
            # use string value directly if no numerical value
            $num = $val unless defined $num;
            # add conversion for this value (replacing any existing entry)
            $tagInfo->{PrintConv}->{$num} = $val;
            if ($verbose) {
                $exifTool->VerboseInfo($tag, $tagInfo,
                    Table   => $tagTablePtr,
                    Value   => $num,
                    DataPt  => $dataPt,
                    DataPos => $$dirInfo{DataPos},
                    Start   => $valPos,
                    Size    => length($val),
                );
            }
            $exifTool->FoundTag($tagInfo, $num);
            $valPos += length($val) + 1;
        }
    }
    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::Ricoh - Ricoh EXIF maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to
interpret Ricoh maker notes EXIF meta information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.ozhiker.com/electronics/pjmt/jpeg_info/ricoh_mn.html>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Ricoh Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
