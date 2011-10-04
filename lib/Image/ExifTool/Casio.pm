#------------------------------------------------------------------------------
# File:         Casio.pm
#
# Description:  Casio EXIF maker notes tags
#
# Revisions:    12/09/2003 - P. Harvey Created
#               09/10/2004 - P. Harvey Added MakerNote2 (thanks to Joachim Loehr)
#
# References:   1) http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html
#               2) Joachim Loehr private communication
#               3) http://homepage3.nifty.com/kamisaka/makernote/makernote_casio.htm
#               4) http://www.gvsoft.homedns.org/exif/makernote-casio.html
#               JD) Jens Duttke private communication
#------------------------------------------------------------------------------

package Image::ExifTool::Casio;

use strict;
use vars qw($VERSION);
use Image::ExifTool::Exif;

$VERSION = '1.23';

# older Casio maker notes (ref 1)
%Image::ExifTool::Casio::Main = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0001 => {
        Name => 'RecordingMode' ,
        Writable => 'int16u',
        PrintConv => {
            1 => 'Single Shutter',
            2 => 'Panorama',
            3 => 'Night Scene',
            4 => 'Portrait',
            5 => 'Landscape',
            7 => 'Panorama', #4
            10 => 'Night Scene', #4
            15 => 'Portrait', #4
            16 => 'Landscape', #4
        },
    },
    0x0002 => {
        Name => 'Quality',
        Writable => 'int16u',
        PrintConv => { 1 => 'Economy', 2 => 'Normal', 3 => 'Fine' },
    },
    0x0003 => {
        Name => 'FocusMode',
        Writable => 'int16u',
        PrintConv => {
            2 => 'Macro',
            3 => 'Auto',
            4 => 'Manual',
            5 => 'Infinity',
            7 => 'Spot AF', #4
        },
    },
    0x0004 => [
        {
            Name => 'FlashMode',
            Condition => '$self->{Model} =~ /^QV-(3500EX|8000SX)/',
            Writable => 'int16u',
            PrintConv => {
                1 => 'Auto',
                2 => 'On',
                3 => 'Off',
                4 => 'Off', #4
                5 => 'Red-eye Reduction', #4
            },
        },
        {
            Name => 'FlashMode',
            Writable => 'int16u',
            PrintConv => {
                1 => 'Auto',
                2 => 'On',
                3 => 'Off',
                4 => 'Red-eye Reduction',
            },
        },
    ],
    0x0005 => {
        Name => 'FlashIntensity',
        Writable => 'int16u',
        PrintConv => {
            11 => 'Weak',
            12 => 'Low', #4
            13 => 'Normal',
            14 => 'High', #4
            15 => 'Strong',
        },
    },
    0x0006 => {
        Name => 'ObjectDistance',
        Writable => 'int32u',
        ValueConv => '$val / 1000', #4
        ValueConvInv => '$val * 1000',
        PrintConv => '"$val m"',
        PrintConvInv => '$val=~s/\s*m$//;$val',
    },
    0x0007 => {
        Name => 'WhiteBalance',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Auto',
            2 => 'Tungsten',
            3 => 'Daylight',
            4 => 'Fluorescent',
            5 => 'Shade',
            129 => 'Manual',
        },
    },
    # 0x0009 Bulb? (ref unknown)
    0x000a => {
        Name => 'DigitalZoom',
        Writable => 'int32u',
        PrintHex => 1,
        PrintConv => {
            0x10000 => 'Off',
            0x10001 => '2x',
            0x19999 => '1.6x', #4
            0x20000 => '2x', #4
            0x33333 => '3.2x', #4
            0x40000 => '4x', #4
        },
    },
    0x000b => {
        Name => 'Sharpness',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Normal',
            1 => 'Soft',
            2 => 'Hard',
            16 => 'Normal', #4
            17 => '+1', #4
            18 => '-1', #4
         },
    },
    0x000c => {
        Name => 'Contrast',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
            16 => 'Normal', #4
            17 => '+1', #4
            18 => '-1', #4
        },
    },
    0x000d => {
        Name => 'Saturation',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
            16 => 'Normal', #4
            17 => '+1', #4
            18 => '-1', #4
        },
    },
    0x0014 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
    0x0015 => { #JD (Similar to Type2 0x2001)
        Name => 'FirmwareDate',
        Writable => 'string',
        Format => 'undef', # the 'string' contains nulls
        Count => 18,
        PrintConv => q{
            $_ = $val;
            if (/^(\d{2})(\d{2})\0\0(\d{2})(\d{2})\0\0(\d{2})(.{2})\0{2}$/) {
                my $yr = $1 + ($1 < 70 ? 2000 : 1900);
                my $sec = $6;
                $val = "$yr:$2:$3 $4:$5";
                $val .= ":$sec" if $sec=~/^\d{2}$/;
                return $val;
            }
            tr/\0/./;  s/\.+$//;
            return "Unknown ($_)";
        },
        PrintConvInv => q{
            $_ = $val;
            if (/^(19|20)(\d{2}):(\d{2}):(\d{2}) (\d{2}):(\d{2})$/) {
                return "$2$3\0\0$4$5\0\0$6\0\0\0\0";
            } elsif (/^Unknown\s*\((.*)\)$/i) {
                $_ = $1;  tr/./\0/;
                return $_;
            } else {
                return undef;
            }
        },
    },
    0x0016 => { #4
        Name => 'Enhancement',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Off',
            2 => 'Red',
            3 => 'Green',
            4 => 'Blue',
            5 => 'Flesh Tones',
        },
    },
    0x0017 => { #4
        Name => 'ColorFilter',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Off',
            2 => 'Black & White',
            3 => 'Sepia',
            4 => 'Red',
            5 => 'Green',
            6 => 'Blue',
            7 => 'Yellow',
            8 => 'Pink',
            9 => 'Purple',
        },
    },
    0x0018 => { #4
        Name => 'AFPoint',
        Writable => 'int16u',
        Notes => 'may not be valid for all models', #JD
        PrintConv => {
            1 => 'Center',
            2 => 'Upper Left',
            3 => 'Upper Right',
            4 => 'Near Left/Right of Center',
            5 => 'Far Left/Right of Center',
            6 => 'Far Left/Right of Center/Bottom',
            7 => 'Top Near-Left',
            8 => 'Near Upper/Left',
            9 => 'Top Near-Right',
            10 => 'Top Left',
            11 => 'Top Center',
            12 => 'Top Right',
            13 => 'Center Left',
            14 => 'Center Right',
            15 => 'Bottom Left',
            16 => 'Bottom Center',
            17 => 'Bottom Right',
        },
    },
    0x0019 => { #4
        Name => 'FlashIntensity',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Normal',
            2 => 'Weak',
            3 => 'Strong',
        },
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        # crazy I know, but the offset for this value is entry-based
        # (QV-2100, QV-2900UX, QV-3500EX and QV-4000) even though the
        # offsets for other values isn't
        EntryBased => 1,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
);

# ref 2:
%Image::ExifTool::Casio::Type2 = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0002 => {
        Name => 'PreviewImageSize',
        Groups => { 2 => 'Image' },
        Writable => 'int16u',
        Count => 2,
        PrintConv => '$val =~ tr/ /x/; $val',
        PrintConvInv => '$val =~ tr/x/ /; $val',
    },
    0x0003 => {
        Name => 'PreviewImageLength',
        Groups => { 2 => 'Image' },
        OffsetPair => 0x0004, # point to associated offset
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x0004 => {
        Name => 'PreviewImageStart',
        Groups => { 2 => 'Image' },
        Flags => 'IsOffset',
        OffsetPair => 0x0003, # point to associated byte count
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x0008 => {
        Name => 'QualityMode',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Economy',
           1 => 'Normal',
           2 => 'Fine',
        },
    },
    0x0009 => {
        Name => 'CasioImageSize',
        Groups => { 2 => 'Image' },
        Writable => 'int16u',
        PrintConv => {
            0 => '640x480',
            4 => '1600x1200',
            5 => '2048x1536',
            20 => '2288x1712',
            21 => '2592x1944',
            22 => '2304x1728',
            36 => '3008x2008',
        },
    },
    0x000d => {
        Name => 'FocusMode',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Normal',
           1 => 'Macro',
        },
    },
    0x0014 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
        PrintConv => {
           3 => 50,
           4 => 64,
           6 => 100,
           9 => 200,
        },
    },
    0x0019 => {
        Name => 'WhiteBalance',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Auto',
           1 => 'Daylight',
           2 => 'Shade',
           3 => 'Tungsten',
           4 => 'Fluorescent',
           5 => 'Manual',
        },
    },
    0x001d => {
        Name => 'FocalLength',
        Writable => 'rational64u',
        PrintConv => 'sprintf("%.1f mm",$val)',
        PrintConvInv => '$val=~s/\s*mm$//;$val',
    },
    0x001f => {
        Name => 'Saturation',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Low',
           1 => 'Normal',
           2 => 'High',
        },
    },
    0x0020 => {
        Name => 'Contrast',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Low',
           1 => 'Normal',
           2 => 'High',
        },
    },
    0x0021 => {
        Name => 'Sharpness',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Soft',
           1 => 'Normal',
           2 => 'Hard',
        },
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        Writable => 0,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
    0x2000 => {
        # this image data is also referenced by tags 3 and 4
        # (nasty that they double-reference the image!)
        %Image::ExifTool::previewImageTagInfo,
    },
    0x2001 => { #PH
        # I downloaded images from 12 different EX-Z50 cameras, and they showed
        # only 3 distinct dates here (2004:08:31 18:55, 2004:09:13 14:14, and
        # 2004:11:26 17:07), so I'm guessing this is a firmware version date - PH
        Name => 'FirmwareDate',
        Writable => 'string',
        Format => 'undef', # the 'string' contains nulls
        Count => 18,
        PrintConv => q{
            $_ = $val;
            if (/^(\d{2})(\d{2})\0\0(\d{2})(\d{2})\0\0(\d{2})\0{4}$/) {
                my $yr = $1 + ($1 < 70 ? 2000 : 1900);
                return "$yr:$2:$3 $4:$5";
            }
            tr/\0/./;  s/\.+$//;
            return "Unknown ($_)";
        },
        PrintConvInv => q{
            $_ = $val;
            if (/^(19|20)(\d{2}):(\d{2}):(\d{2}) (\d{2}):(\d{2})$/) {
                return "$2$3\0\0$4$5\0\0$6\0\0\0\0";
            } elsif (/^Unknown\s*\((.*)\)$/i) {
                $_ = $1;  tr/./\0/;
                return $_;
            } else {
                return undef;
            }
        },
    },
    0x2011 => {
        Name => 'WhiteBalanceBias',
        Writable => 'int16u',
        Count => 2,
    },
    0x2012 => {
        Name => 'WhiteBalance',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Manual',
           1 => 'Daylight', #3
           3 => 'Shade', #3
           4 => 'Flash?',
           6 => 'Fluorescent', #3
           10 => 'Tungsten', #3
           12 => 'Flash',
        },
    },
    0x2021 => { #JD (guess)
        Name => 'AFPointPosition',
        PrintConv => q{
            my @v = split ' ', $val;
            return 'n/a' if $v[0] == 65535 or not $v[1] or not $v[3];
            sprintf"%.0f%% %.0f%%", 100*$v[0]/$v[1], 100*$v[2]/$v[3];
        },
    },
    0x2022 => {
        Name => 'ObjectDistance',
        Writable => 'int32u',
        ValueConv => '$val >= 0x20000000 ? "inf" : $val / 1000',
        ValueConvInv => '$val eq "inf" ? 0x20000000 : $val * 1000',
        PrintConv => '$val eq "inf" ? $val : "$val m"',
        PrintConvInv => '$val=~s/\s*m$//;$val',
    },
    # 0x2023 looks interesting (values 0,1,2,3,5 in samples) - PH
    0x2034 => {
        Name => 'FlashDistance',
        Writable => 'int16u',
    },
    0x3000 => {
        Name => 'RecordMode',
        Writable => 'int16u',
        PrintConv => {
            2 => 'Program AE', #3
            3 => 'Shutter Priority', #3
            4 => 'Aperture Priority', #3
            5 => 'Manual', #3
            6 => 'Best Shot', #3
            17 => 'Movie', #PH (UHQ?)
            19 => 'Movie (19)', #PH (HQ?, EX-P505)
            20 => 'YouTube Movie', #PH
        },
    },
    # 0x3001 is ShutterMode according to ref 3!
    0x3001 => {
        Name => 'SelfTimer',
        Writable => 'int16u',
        PrintConv => { 1 => 'Off' },
    },
    0x3002 => {
        Name => 'Quality',
        Writable => 'int16u',
        PrintConv => {
           1 => 'Economy',
           2 => 'Normal',
           3 => 'Fine',
        },
    },
    0x3003 => {
        Name => 'FocusMode',
        Writable => 'int16u',
        PrintConv => {
           0 => 'Manual', #(guess at translation)
           1 => 'Focus Lock', #(guess at translation)
           2 => 'Macro', #3
           3 => 'Single-Area Auto Focus',
           6 => 'Multi-Area Auto Focus',
        },
    },
    0x3006 => {
        Name => 'HometownCity',
        Writable => 'string',
    },
    0x3007 => {
        Name => 'BestShotMode',
        Writable => 'int16u',
        # unfortunately these numbers are model-dependent,
        # so we can't use a lookup as usual - PH
        PrintConv => '$val ? $val : "Off"',
        PrintConvInv => '$val=~/(\d+)/ ? $1 : 0',
    },
    0x3008 => { #3
        Name => 'AutoISO',
        Writable => 'int16u',
        PrintConv => { 1 => 'On', 2 => 'Off' },
    },
    0x3011 => { #3
        Name => 'Sharpness',
        Format => 'int16s',
        Writable => 'undef',
    },
    0x3012 => { #3
        Name => 'Contrast',
        Format => 'int16s',
        Writable => 'undef',
    },
    0x3013 => { #3
        Name => 'Saturation',
        Format => 'int16s',
        Writable => 'undef',
    },
    0x3014 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
    0x3015 => {
        Name => 'ColorMode',
        Writable => 'int16u',
        PrintConv => { 0 => 'Off' },
    },
    0x3016 => {
        Name => 'Enhancement',
        Writable => 'int16u',
        PrintConv => { 0 => 'Off' },
    },
    0x3017 => {
        Name => 'Filter',
        Writable => 'int16u',
        PrintConv => { 0 => 'Off' },
    },
    0x301c => { #3
        Name => 'SequenceNumber', # for continuous shooting
        Writable => 'int16u',
    },
    0x301d => { #3
        Name => 'BracketSequence',
        Writable => 'int16u',
        Count => 2,
    },
    # 0x301e - MultiBracket ? (ref 3)
    0x3020 => { #3
        Name => 'ImageStabilization',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
            2 => 'Best Shot',
            # 3 observed in MOV videos (EX-V7)
        },
    },
);

# tags in Casio AVI videos (ref PH)
%Image::ExifTool::Casio::AVI = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => 'This information is found in Casio GV-10 AVI videos.',
    0 => {
        Name => 'Software', # (equivalent to RIFF Software tag)
        Format => 'string',
    },
);


1;  # end

__END__

=head1 NAME

Image::ExifTool::Casio - Casio EXIF maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Casio maker notes in EXIF information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Joachim Loehr for adding support for the type 2 maker notes.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Casio Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
