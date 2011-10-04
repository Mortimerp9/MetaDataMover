#------------------------------------------------------------------------------
# File:         Kodak.pm
#
# Description:  Kodak EXIF maker notes and APP3 "Meta" tags
#
# Revisions:    03/28/2005  - P. Harvey Created
#
# References:   1) http://search.cpan.org/dist/Image-MetaData-JPEG/
#               2) http://www.ozhiker.com/electronics/pjmt/jpeg_info/meta.html
#               3) http://www.cybercom.net/~dcoffin/dcraw/
#
# Notes:        There really isn't much public information about Kodak formats.
#               The only source I could find was Image::MetaData::JPEG, which
#               didn't provide information about decoding the tag values.  So
#               this module represents a lot of work downloading sample images
#               (about 100MB worth!), and testing with my daughter's CX4200.
#------------------------------------------------------------------------------

package Image::ExifTool::Kodak;

use strict;
use vars qw($VERSION);
use Image::ExifTool::Exif;

$VERSION = '1.15';

sub ProcessKodakIFD($$$);
sub ProcessKodakText($$$);
sub WriteKodakIFD($$$);

# Kodak type 1 maker notes (ref 1)
%Image::ExifTool::Kodak::Main = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    NOTES => q{
        The table below contains the most common set of Kodak tags.  The following
        Kodak camera models have been tested and found to use these tags: C360,
        C663, C875, CX6330, CX6445, CX7330, CX7430, CX7525, CX7530, DC4800, DC4900,
        DX3500, DX3600, DX3900, DX4330, DX4530, DX4900, DX6340, DX6440, DX6490,
        DX7440, DX7590, DX7630, EasyShare-One, LS420, LS443, LS633, LS743, LS753,
        V530, V550, V570, V603, V610, V705, Z650, Z700, Z710, Z730, Z740, Z760 and
        Z7590.
    },
    WRITABLE => 1,
    FIRST_ENTRY => 8,
    0x00 => {
        Name => 'KodakModel',
        Format => 'string[8]',
    },
    0x09 => {
        Name => 'Quality',
        PrintConv => { #PH
            1 => 'Fine',
            2 => 'Normal',
        },
    },
    0x0a => {
        Name => 'BurstMode',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x0c => {
        Name => 'KodakImageWidth',
        Format => 'int16u',
    },
    0x0e => {
        Name => 'KodakImageHeight',
        Format => 'int16u',
    },
    0x10 => {
        Name => 'YearCreated',
        Groups => { 2 => 'Time' },
        Format => 'int16u',
    },
    0x12 => {
        Name => 'MonthDayCreated',
        Groups => { 2 => 'Time' },
        Format => 'int8u[2]',
        ValueConv => 'sprintf("%.2d:%.2d",split(" ", $val))',
        ValueConvInv => '$val=~tr/:./ /;$val',
    },
    0x14 => {
        Name => 'TimeCreated',
        Groups => { 2 => 'Time' },
        Format => 'int8u[4]',
        Shift => 'Time',
        ValueConv => 'sprintf("%.2d:%.2d:%.2d.%.2d",split(" ", $val))',
        ValueConvInv => '$val=~tr/:./ /;$val',
    },
    0x18 => {
        Name => 'BurstMode2',
        Format => 'int16u',
        Unknown => 1, # not sure about this tag (or other 'Unknown' tags)
    },
    0x1b => {
        Name => 'ShutterMode',
        PrintConv => { #PH
            0 => 'Auto',
            8 => 'Aperture Priority',
            32 => 'Manual?',
        },
    },
    0x1c => {
        Name => 'MeteringMode',
        PrintConv => { #PH
            0 => 'Multi-segment',
            1 => 'Center-weighted average',
            2 => 'Spot',
        },
    },
    0x1d => 'SequenceNumber',
    0x1e => {
        Name => 'FNumber',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => 'int($val * 100 + 0.5)',
    },
    0x20 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e5',
        ValueConvInv => '$val * 1e5',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x24 => {
        Name => 'ExposureCompensation',
        Format => 'int16s',
        ValueConv => '$val / 1000',
        ValueConvInv => '$val * 1000',
        PrintConv => '$val > 0 ? "+$val" : $val',
        PrintConvInv => 'eval $val',
    },
    0x26 => {
        Name => 'VariousModes',
        Format => 'int16u',
        Unknown => 1,
    },
    0x28 => {
        Name => 'Distance1',
        Format => 'int32u',
        Unknown => 1,
    },
    0x2c => {
        Name => 'Distance2',
        Format => 'int32u',
        Unknown => 1,
    },
    0x30 => {
        Name => 'Distance3',
        Format => 'int32u',
        Unknown => 1,
    },
    0x34 => {
        Name => 'Distance4',
        Format => 'int32u',
        Unknown => 1,
    },
    0x38 => {
        Name => 'FocusMode',
        PrintConv => {
            0 => 'Normal',
            2 => 'Macro',
        },
    },
    0x3a => {
        Name => 'VariousModes2',
        Format => 'int16u',
        Unknown => 1,
    },
    0x3c => {
        Name => 'PanoramaMode',
        Format => 'int16u',
        Unknown => 1,
    },
    0x3e => {
        Name => 'SubjectDistance',
        Format => 'int16u',
        Unknown => 1,
    },
    0x40 => {
        Name => 'WhiteBalance',
        Priority => 0,
        PrintConv => { #PH
            0 => 'Auto',
            1 => 'Flash?',
            2 => 'Tungsten',
            3 => 'Daylight',
        },
    },
    0x5c => {
        Name => 'FlashMode',
        Flags => 'PrintHex',
        # various models express this number differently
        PrintConv => { #PH
            0x00 => 'Auto',
            0x01 => 'Fill Flash',
            0x02 => 'Off',
            0x03 => 'Red-Eye',
            0x10 => 'Fill Flash',
            0x20 => 'Off',
            0x40 => 'Red-Eye?',
        },
    },
    0x5d => {
        Name => 'FlashFired',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    0x5e => {
        Name => 'ISOSetting',
        Format => 'int16u',
        PrintConv => '$val ? $val : "Auto"',
        PrintConvInv => '$val=~/^\d+$/ ? $val : 0',
    },
    0x60 => {
        Name => 'ISO',
        Format => 'int16u',
    },
    0x62 => {
        Name => 'TotalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x64 => {
        Name => 'DateTimeStamp',
        Format => 'int16u',
        PrintConv => '$val ? "Mode $val" : "Off"',
        PrintConvInv => '$val=~tr/0-9//dc; $val ? $val : 0',
    },
    0x66 => {
        Name => 'ColorMode',
        Format => 'int16u',
        Flags => 'PrintHex',
        # various models express this number differently
        PrintConv => { #PH
            0x01 => 'B&W',
            0x02 => 'Sepia',
            0x03 => 'B&W Yellow Filter',
            0x04 => 'B&W Red Filter',
            0x20 => 'Saturated Color',
            0x40 => 'Neutral Color',
            0x100 => 'Saturated Color',
            0x200 => 'Neutral Color',
            0x2000 => 'B&W',
            0x4000 => 'Sepia',
        },
    },
    0x68 => {
        Name => 'DigitalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x6b => {
        Name => 'Sharpness',
        Format => 'int8s',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
);

# Kodak type 2 maker notes (ref PH)
%Image::ExifTool::Kodak::Type2 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    NOTES => q{
        These tags are used by the Kodak DC220, DC260, DC265 and DC290,
        Hewlett-Packard PhotoSmart 618, C500 and C912, Pentax EI-200 and EI-2000,
        and Minolta EX1500Z.
    },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0x08 => {
        Name => 'KodakMaker',
        Format => 'string[32]',
    },
    0x28 => {
        Name => 'KodakModel',
        Format => 'string[32]',
    },
    0x6c => {
        Name => 'KodakImageWidth',
        Format => 'int32u',
    },
    0x70 => {
        Name => 'KodakImageHeight',
        Format => 'int32u',
    },
);

# Kodak type 3 maker notes (ref PH)
%Image::ExifTool::Kodak::Type3 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    NOTES => 'These tags are used by the DC240, DC280, DC3400 and DC5000.',
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0x0c => {
        Name => 'YearCreated',
        Groups => { 2 => 'Time' },
        Format => 'int16u',
    },
    0x0e => {
        Name => 'MonthDayCreated',
        Groups => { 2 => 'Time' },
        Format => 'int8u[2]',
        ValueConv => 'sprintf("%.2d:%.2d",split(" ", $val))',
        ValueConvInv => '$val=~tr/:./ /;$val',
    },
    0x10 => {
        Name => 'TimeCreated',
        Groups => { 2 => 'Time' },
        Format => 'int8u[4]',
        Shift => 'Time',
        ValueConv => 'sprintf("%2d:%.2d:%.2d.%.2d",split(" ", $val))',
        ValueConvInv => '$val=~tr/:./ /;$val',
    },
    0x1e => {
        Name => 'OpticalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x37 => {
        Name => 'Sharpness',
        Format => 'int8s',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    0x38 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e5',
        ValueConvInv => '$val * 1e5',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x3c => {
        Name => 'FNumber',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => 'int($val * 100 + 0.5)',
    },
    0x4e => {
        Name => 'ISO',
        Format => 'int16u',
    },
);

# Kodak type 4 maker notes (ref PH)
%Image::ExifTool::Kodak::Type4 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    NOTES => 'These tags are used by the DC200 and DC215.',
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0x20 => {
        Name => 'OriginalFileName',
        Format => 'string[12]',
    },
);

# Kodak type 5 maker notes (ref PH)
%Image::ExifTool::Kodak::Type5 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    NOTES => q{
        These tags are used by the CX4200, CX4210, CX4230, CX4300, CX4310, CX6200
        and CX6230.
    },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0x14 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e5',
        ValueConvInv => '$val * 1e5',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x1a => {
        Name => 'WhiteBalance',
        PrintConv => {
            1 => 'Daylight',
            2 => 'Flash',
            3 => 'Tungsten',
        },
    },
    0x1c => {
        Name => 'FNumber',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => 'int($val * 100 + 0.5)',
    },
    0x1e => {
        Name => 'ISO',
        Format => 'int16u',
    },
    0x20 => {
        Name => 'OpticalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x22 => {
        Name => 'DigitalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x27 => {
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Auto',
            1 => 'On',
            2 => 'Off',
            3 => 'Red-Eye',
        },
    },
    0x2a => {
        Name => 'ImageRotated',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    0x2b => {
        Name => 'Macro',
        PrintConv => { 0 => 'On', 1 => 'Off' },
    },
);

# Kodak type 6 maker notes (ref PH)
%Image::ExifTool::Kodak::Type6 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    NOTES => 'These tags are used by the DX3215 and DX3700.',
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0x10 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val / 1e5',
        ValueConvInv => '$val * 1e5',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x14 => {
        Name => 'ISOSetting',
        Format => 'int32u',
        Unknown => 1,
    },
    0x18 => {
        Name => 'FNumber',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => 'int($val * 100 + 0.5)',
    },
    0x1a => {
        Name => 'ISO',
        Format => 'int16u',
    },
    0x1c => {
        Name => 'OpticalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x1e => {
        Name => 'DigitalZoom',
        Format => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0x22 => {
        Name => 'Flash',
        Format => 'int16u',
        PrintConv => {
            0 => 'No Flash',
            1 => 'Fired',
        },
    },
);

# Kodak type 7 maker notes (ref PH)
%Image::ExifTool::Kodak::Type7 = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => q{
        The maker notes of models such as the C340, C433, CC533, LS755, V803 and
        V1003 seem to start with the camera serial number.  The C310, C315, C330,
        C643, C743, CD33, CD43, CX7220 and CX7300 maker notes are also decoded using
        this table, although the strings for these cameras don't conform to the
        usual Kodak serial number format, and instead have the model name followed
        by 8 digits.
    },
    0 => { # (not confirmed)
        Name => 'SerialNumber',
        Format => 'string[16]',
        ValueConv => '$val=~s/\s+$//; $val', # remove trailing whitespace
        ValueConvInv => '$val',
    },
);

# Kodak IFD-format maker notes (ref PH)
%Image::ExifTool::Kodak::Type8 = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => q{
        Kodak models such as the P712, P850, P880, Z612 and Z712 use standard TIFF
        IFD format for the maker notes.  In keeping with Kodak's strategy of
        inconsitent makernotes, some models such as the Z1085 also use these tags,
        but for these models the makernotes begin with a TIFF header instead of an
        IFD entry count and use relative instead of absolute offsets.  There is a
        large amount of information stored in these maker notes (apparently with
        much duplication), but relatively few tags have so far been decoded.
    },
    0xfc00 => {
        Name => 'SubIFD0',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD0',
            Start => '$val',
        },
    },
    # SubIFD1 and higher data is preceded by a TIFF byte order mark to indicate
    # the byte ordering used
    0xfc01 => {
        Name => 'SubIFD1',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD1',
            Start => '$val',
            Base => '$start',
        },
    },
    0xfc02 => {
        Name => 'SubIFD2',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD2',
            Start => '$val',
            Base => '$start',
        },
    },
    0xfc03 => {
        Name => 'SubIFD3',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD3',
            Start => '$val',
            Base => '$start',
        },
    },
    # (SubIFD4 has the pointer zeroed in my samples, but support it
    # in case it is used by future models -- ignored if pointer is zero)
    0xfc04 => {
        Name => 'SubIFD4',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD4',
            Start => '$val',
            Base => '$start',
        },
    },
    0xfc05 => {
        Name => 'SubIFD5',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SubIFD5',
            Start => '$val',
            Base => '$start',
        },
    },
    0xff00 => {
        Name => 'CameraInfo',
        Groups => { 1 => 'MakerNotes' },    # SubIFD needs group 1 set
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::CameraInfo',
            Start => '$val',
        },
    },
);

# Kodak SubIFD0 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD0 = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'SubIFD0 through SubIFD5 tags are used by the Z612 and Z712.',
    0xfa02 => {
        Name => 'SceneMode',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Sport',
            3 => 'Portrait',
            4 => 'Landscape',
            6 => 'Beach',
            7 => 'Night Portrait',
            8 => 'Night Landscape',
            9 => 'Snow',
            10 => 'Text',
            11 => 'Fireworks',
            12 => 'Macro',
            13 => 'Museum',
            16 => 'Children',
            17 => 'Program',
            18 => 'Aperture Priority',
            19 => 'Shutter Priority',
            20 => 'Manual',
            25 => 'Back Light',
            28 => 'Candlelight',
            29 => 'Sunset',
            31 => 'Panorama Left-Right',
            32 => 'Panorama Right-Left',
            33 => 'Smart Scene',
            34 => 'High ISO',
        },
    },
    # 0xfa04 - values: 0 (normally), 2 (panorama shots)
    # 0xfa0f - values: 0 (normally), 1 (macro?)
    # 0xfa11 - some sort of FNumber (x 100)
    0xfa19 => {
        Name => 'SerialNumber', # (verified with Z712 - PH)
        Writable => 'string',
    },
    0xfa1d => {
        Name => 'KodakImageWidth',
        Writable => 'int16u',
    },
    0xfa1e => {
        Name => 'KodakImageHeight',
        Writable => 'int16u',
    },
    0xfa20 => {
        Name => 'SensorWidth',
        Writable => 'int16u',
    },
    0xfa21 => {
        Name => 'SensorHeight',
        Writable => 'int16u',
    },
    0xfa23 => {
        Name => 'FNumber',
        Writable => 'int16u',
        Priority => 0,
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0xfa24 => {
        Name => 'ExposureTime',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val / 1e5',
        ValueConvInv => '$val * 1e5',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0xfa2e => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
    0xfa3d => {
        Name => 'OpticalZoom',
        Writable => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val=~s/ ?x//; $val',
    },
    0xfa46 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
    # 0xfa4c - related to focal length (1=wide, 32=full zoom)
    0xfa51 => {
        Name => 'KodakImageWidth',
        Writable => 'int16u',
    },
    0xfa52 => {
        Name => 'KodakImageHeight',
        Writable => 'int16u',
    },
    0xfa54 => {
        Name => 'ThumbnailWidth',
        Writable => 'int16u',
    },
    0xfa55 => {
        Name => 'ThumbnailHeight',
        Writable => 'int16u',
    },
    0xfa57 => {
        Name => 'PreviewWidth',
        Writable => 'int16u',
    },
    0xfa58 => {
        Name => 'PreviewHeight',
        Writable => 'int16u',
    },
);

# Kodak SubIFD1 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD1 = (
    PROCESS_PROC => \&ProcessKodakIFD,
    WRITE_PROC => \&WriteKodakIFD,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0027 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
    0x0028 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
);

my %sceneModeUsed = (
    0 => 'Program',
    2 => 'Aperture Priority',
    3 => 'Shutter Priority',
    4 => 'Manual',
    5 => 'Portrait',
    6 => 'Sport',
    7 => 'Children',
    8 => 'Museum',
    10 => 'High ISO',
    11 => 'Text',
    12 => 'Macro',
    13 => 'Back Light',
    16 => 'Landscape',
    17 => 'Night Landscape',
    18 => 'Night Portrait',
    19 => 'Snow',
    20 => 'Beach',
    21 => 'Fireworks',
    22 => 'Sunset',
    23 => 'Candlelight',
    28 => 'Panorama',
);

# Kodak SubIFD2 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD2 = (
    PROCESS_PROC => \&ProcessKodakIFD,
    WRITE_PROC => \&WriteKodakIFD,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x6002 => {
        Name => 'SceneModeUsed',
        Writable => 'int32u',
        PrintConv => \%sceneModeUsed,
    },
    0x6006 => {
        Name => 'OpticalZoom',
        Writable => 'int32u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val=~s/ ?x//; $val',
    },
    # 0x6009 - some sort of FNumber (x 100)
    0x6103 => {
        Name => 'MaxAperture',
        Writable => 'int32u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0xf002 => {
        Name => 'SceneModeUsed',
        Writable => 'int32u',
        PrintConv => \%sceneModeUsed,
    },
    0xf006 => {
        Name => 'OpticalZoom',
        Writable => 'int32u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val=~s/ ?x//; $val',
    },
    # 0xf009 - some sort of FNumber (x 100)
    0xf103 => {
        Name => 'FNumber',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0xf104 => {
        Name => 'ExposureTime',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val / 1e6',
        ValueConvInv => '$val * 1e6',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0xf105 => {
        Name => 'ISO',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val / 10',
        ValueConvInv => '$val * 10',
    },
);

# Kodak SubIFD3 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD3 = (
    PROCESS_PROC => \&ProcessKodakIFD,
    WRITE_PROC => \&WriteKodakIFD,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x1000 => {
        Name => 'OpticalZoom',
        Writable => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val=~s/ ?x//; $val',
    },
    # 0x1002 - related to focal length (1=wide, 32=full zoom)
    # 0x1006 - pictures remaining? (gradually decreases as pictures are taken)
);

# Kodak SubIFD4 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD4 = (
    PROCESS_PROC => \&ProcessKodakIFD,
    WRITE_PROC => \&WriteKodakIFD,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
);

# Kodak SubIFD5 tags (ref PH)
%Image::ExifTool::Kodak::SubIFD5 = (
    PROCESS_PROC => \&ProcessKodakIFD,
    WRITE_PROC => \&WriteKodakIFD,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x000f => {
        Name => 'OpticalZoom',
        Writable => 'int16u',
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val=~s/ ?x//; $val',
    },
);

# Decoded from P712, P850 and P880 samples (ref PH)
%Image::ExifTool::Kodak::CameraInfo = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are used by the  P712, P850 and P880.',
    0xf900 => {
        Name => 'SensorWidth',
        Writable => 'int16u',
        Notes => 'effective sensor size',
    },
    0xf901 => {
        Name => 'SensorHeight',
        Writable => 'int16u',
    },
    0xf902 => {
        Name => 'BayerPattern',
        Writable => 'string',
    },
    0xf903 => {
        Name => 'SensorFullWidth',
        Writable => 'int16u',
        Notes => 'includes black border?',
    },
    0xf904 => {
        Name => 'SensorFullHeight',
        Writable => 'int16u',
    },
    0xf907 => {
        Name => 'KodakImageWidth',
        Writable => 'int16u',
    },
    0xf908 => {
        Name => 'KodakImageHeight',
        Writable => 'int16u',
    },
    0xfa00 => {
        Name => 'KodakInfoType',
        Writable => 'string',
    },
    0xfa04 => {
        Name => 'SerialNumber', # (unverified)
        Writable => 'string',
    },
    0xfd04 => {
        Name => 'FNumber',
        Writable => 'int16u',
        Priority => 0,
        ValueConv => '$val / 100',
        ValueConvInv => '$val * 100',
    },
    0xfd05 => {
        Name => 'ExposureTime',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val / 1e6',
        ValueConvInv => '$val * 1e6',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0xfd06 => {
        Name => 'ISO',
        Writable => 'int16u',
        Priority => 0,
    },
);

# treat unknown maker notes as binary data (allows viewing with -U)
%Image::ExifTool::Kodak::Unknown = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    FIRST_ENTRY => 0,
);

# tags found in the KodakIFD (in IFD0 of KDC, DCR, TIFF and JPEG images) (ref PH)
%Image::ExifTool::Kodak::IFD = (
    GROUPS => { 0 => 'EXIF', 1 => 'KodakIFD', 2 => 'Image'},
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITE_GROUP => 'KodakIFD',
    SET_GROUP1 => 1,
    NOTES => q{
        These tags are found in a separate IFD of JPEG, TIFF, DCR and KDC images
        from some older Kodak models such as the DC50, DC120, DCS760C, DCS Pro 14N,
        14nx, SLR/n, Pro Back and Canon EOS D2000.
    },
    # 0x0000: int8u[4]    - values: "1 0 0 0" (DC50), "1 1 0 0" (DC120)
    0x0001 => {
        # (related to EV but exact meaning unknown)
        Name => 'UnknownEV',
        Writable => 'rational64u',
        Unknown => 1,
    },
    # 0x0002: int8u       - values: 0
    0x0003 => {
        Name => 'ExposureValue',
        Writable => 'rational64u',
    },
    # 0x0004: rational64u - values: 2.875,3.375,3.625,4,4.125,7.25
    # 0x0005: int8u       - values: 0
    # 0x0006: int32u[12]  - ?
    # 0x0007: int32u[3]   - values: "65536 67932 69256"
    0x03e9 => { Name => 'OriginalFileName', Writable => 'string' },
    0x03eb => 'SensorLeftBorder',
    0x03ec => 'SensorTopBorder',
    0x03ed => 'SensorImageWidth',
    0x03ee => 'SensorImageHeight',
    0x03f1 => {
        Name => 'TextualInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::TextualInfo',
        },
    },
    # 0x03fc: some sort of white balance index (ref 3)
    # 0x03fd: manual white balance information (ref 3)
    0x0401 => {
        Name => 'SubSecTime',
        Groups => { 2 => 'Time' },
        Writable => 'string',
    },
    0x0414 => { Name => 'NCDFileInfo',      Writable => 'string' },
    0x0846 => { Name => 'ColorTemperature', Writable => 'int16u' }, #3
    # 0x0852: used in calculating WB levels (ref 3)
    # 0x085c: used in calculating WB levels (ref 3)
    # 0x090d: linear table (ref 3)
    # 0x0c81: some sort of date (manufacture date?) - PH
    0x0ce5 => { Name => 'FirmwareVersion',  Writable => 'string' },
    # 0x1390: value: "DCSProSLRn" (tone curve name?) - PH
    0x1391 => { Name => 'ToneCurveFileName',Writable => 'string' },
    0x1784 => { Name => 'ISO',              Writable => 'int32u' }, #3
);

# textual-based Kodak TextualInfo tags (not found in KDC images) (ref PH)
%Image::ExifTool::Kodak::TextualInfo = (
    GROUPS => { 0 => 'MakerNotes', 1 => 'Kodak', 2 => 'Image'},
    PROCESS_PROC => \&ProcessKodakText,
    NOTES => q{
        Below is a list of tags which have been observed in the Kodak TextualInfo
        data, however ExifTool will extract information from any tags found here.
    },
    'Actual Compensation' => 'ActualCompensation',
    'AF Function'   => 'AFMode', # values: "S" (=Single?, then maybe C for Continuous, M for Manual?) - PH
    'Aperture'      => {
        Name => 'Aperture',
        ValueConv => '$val=~s/^f//i; $val',
    },
    'Auto Bracket'  => 'AutoBracket',
    'Brightness Value' => 'BrightnessValue',
    'Camera'        => 'CameraModel',
    'Camera body'   => 'CameraBody',
    'Compensation'  => 'ExposureCompensation',
    'Date'          => {
        Name => 'Date',
        Groups => { 2 => 'Time' },
    },
    'Exposure Bias' => 'ExposureBias',
    'Exposure Mode' => {
        Name => 'ExposureMode',
        PrintConv => {
            'M' => 'Manual',
            'A' => 'Aperture Priority', #(NC -- I suppose this could be "Auto" too)
            'S' => 'Shutter Priority', #(NC)
            'P' => 'Program', #(NC)
            'B' => 'Bulb', #(NC)
        },
    },
    'Firmware Version' => 'FirmwareVersion',
    'Flash Compensation' => 'FlashExposureComp',
    'Flash Fired'   => 'FlashFired',
    'Flash Sync Mode' => 'FlashSyncMode',
    'Focal Length'  => {
        Name => 'FocalLength',
        PrintConv => '"$val mm"',
    },
    'Height'        => 'KodakImageHeight',
    'Image Number'  => 'ImageNumber',
    'ISO'           => 'ISO',
    'ISO Speed'     => 'ISO',
    'Max Aperture'  => {
        Name => 'MaxAperture',
        ValueConv => '$val=~s/^f//i; $val',
    },
    'Meter Mode'    => 'MeterMode',
    'Min Aperture'  => {
        Name => 'MinAperture',
        ValueConv => '$val=~s/^f//i; $val',
    },
    'Popup Flash'   => 'PopupFlash',
    'Serial Number' => 'SerialNumber',
    'Shooting Mode' => 'ShootingMode',
    'Shutter'       => 'ShutterSpeed',
    'Temperature'   => 'Temperature', # with a value of 15653, what could this be? - PH
    'Time'          => {
        Name => 'SubSecTime',
        Groups => { 2 => 'Time' },
    },
    'White balance' => 'Whitebalance',
    'Width'         => 'KodakImageWidth',
    '_other_info'   => {
        Name => 'OtherInfo',
        Notes => 'any other information without a tag name',
    },
);

# Kodak APP3 "Meta" tags (ref 2)
%Image::ExifTool::Kodak::Meta = (
    GROUPS => { 0 => 'Meta', 1 => 'MetaIFD', 2 => 'Image'},
    NOTES => q{
        These tags are found in the APP3 "Meta" segment of JPEG images from Kodak
        cameras such as the DC280, DC3400, DC5000 and MC3.  The structure of this
        segment is similar to the APP1 "Exif" segment, but a different set of tags
        is used.
    },
    0xc350 => 'FilmProductCode',
    0xc351 => 'ImageSourceEK',
    0xc352 => 'CaptureConditionsPAR',
    0xc353 => {
        Name => 'CameraOwner',
        PrintConv => 'Image::ExifTool::Exif::ConvertExifText($self,$val)',
    },
    0xc354 => {
        Name => 'SerialNumber',
        Groups => { 2 => 'Camera' },
    },
    0xc355 => 'UserSelectGroupTitle',
    0xc356 => 'DealerIDNumber',
    0xc357 => 'CaptureDeviceFID',
    0xc358 => 'EnvelopeNumber',
    0xc359 => 'FrameNumber',
    0xc35a => 'FilmCategory',
    0xc35b => 'FilmGencode',
    0xc35c => 'ModelAndVersion',
    0xc35d => 'FilmSize',
    0xc35e => 'SBA_RGBShifts',
    0xc35f => 'SBAInputImageColorspace',
    0xc360 => 'SBAInputImageBitDepth',
    0xc361 => {
        Name => 'SBAExposureRecord',
        Binary => 1,
    },
    0xc362 => {
        Name => 'UserAdjSBA_RGBShifts',
        Binary => 1,
    },
    0xc363 => 'ImageRotationStatus',
    0xc364 => 'RollGuidElements',
    0xc365 => 'MetadataNumber',
    0xc366 => 'EditTagArray',
    0xc367 => 'Magnification',
    0xc36c => 'NativeXResolution',
    0xc36d => 'NativeYResolution',
    0xc36e => {
        Name => 'KodakEffectsIFD',
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::SpecialEffects',
            Start => '$val',
        },
    },
    0xc36f => {
        Name => 'KodakBordersIFD',
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Kodak::Borders',
            Start => '$val',
        },
    },
    0xc37a => 'NativeResolutionUnit',
    0xc418 => 'SourceImageDirectory',
    0xc419 => 'SourceImageFileName',
    0xc41a => 'SourceImageVolumeName',
    0xc46c => 'PrintQuality',
    0xc46e => 'ImagePrintStatus',
);

# Kodak APP3 "Meta" Special Effects sub-IFD (ref 2)
%Image::ExifTool::Kodak::SpecialEffects = (
    GROUPS => { 0 => 'Meta', 1 => 'KodakEffectsIFD', 2 => 'Image'},
    0 => 'DigitalEffectsVersion',
    1 => {
        Name => 'DigitalEffectsName',
        PrintConv => 'Image::ExifTool::Exif::ConvertExifText($self,$val)',
    },
    2 => 'DigitalEffectsType',
);

# Kodak APP3 "Meta" Borders sub-IFD (ref 2)
%Image::ExifTool::Kodak::Borders = (
    GROUPS => { 0 => 'Meta', 1 => 'KodakBordersIFD', 2 => 'Image'},
    0 => 'BordersVersion',
    1 => {
        Name => 'BorderName',
        PrintConv => 'Image::ExifTool::Exif::ConvertExifText($self,$val)',
    },
    2 => 'BorderID',
    3 => 'BorderLocation',
    4 => 'BorderType',
    8 => 'WatermarkType',
);

# tags in Kodak MOV videos (ref PH)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::Kodak::MOV = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => 'This information is found in Kodak MOV videos from models such as the P880.',
    0 => {
        Name => 'Make',
        Format => 'string[21]',
    },
    0x16 => {
        Name => 'Model',
        Format => 'string[42]',
    },
    0x40 => {
        Name => 'ModelType',
        Format => 'string[8]',
    },
    # (01 00 at offset 0x48)
    0x4e => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val ? 10 / $val : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x52 => {
        Name => 'FNumber',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x5a => {
        Name => 'ExposureCompensation',
        Format => 'rational64s',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
    },
    # 0x6c => 'WhiteBalance', ?
    0x70 => {
        Name => 'FocalLength',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f mm",$val)',
    },
);

# Kodak composite tags
%Image::ExifTool::Kodak::Composite = (
    DateCreated => {
        Groups => { 2 => 'Time' },
        Require => {
            0 => 'Kodak:YearCreated',
            1 => 'Kodak:MonthDayCreated',
        },
        ValueConv => '"$val[0]:$val[1]"',
    },
);

# add our composite tags
Image::ExifTool::AddCompositeTags('Image::ExifTool::Kodak');

#------------------------------------------------------------------------------
# Process Kodak textual TextualInfo
# Inputs: 0) ExifTool object ref, 1) dirInfo hash ref, 2) tag table ref
# Returns: 1 on success
sub ProcessKodakText($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dirStart = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen} || length($$dataPt) - $dirStart;
    my $data = substr($$dataPt, $dirStart, $dirLen);
    $data =~ s/\0.*//s;     # truncate at null if it exists
    my @lines = split /[\n\r]+/, $data;
    my ($line, $success, @other, $tagInfo);
    foreach $line (@lines) {
        if ($line =~ /(.*?):\s*(.*)/) {
            my ($tag, $val) = ($1, $2);
            if ($$tagTablePtr{$tag}) {
                $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
            } else {
                my $tagName = $tag;
                $tagName =~ s/([A-Z])\s+([A-Za-z])/${1}_\U$2/g;
                $tagName =~ s/([a-z])\s+([A-Za-z0-9])/${1}\U$2/g;
                $tagName =~ s/\s+//g;
                $tagName =~ s/[^-\w]+//g;   # delete remaining invalid characters
                $tagName = 'NoName' unless $tagName;
                $tagInfo = { Name => $tagName };
                Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
            }
            $exifTool->FoundTag($tagInfo, $val);
            $success = 1;
        } else {
            # strip off leading/trailing white space and ignore blank lines
            push @other, $1 if $line =~ /^\s*(\S.*?)\s*$/;
        }
    }
    if ($success) {
        if (@other) {
            $tagInfo = $exifTool->GetTagInfo($tagTablePtr, '_other_info');
            $exifTool->FoundTag($tagInfo, \@other);
        }
    } else {
        $exifTool->Warn("Can't parse Kodak TextualInfo data", 1);
    }
    return $success;
}

#------------------------------------------------------------------------------
# Process Kodak IFD (with leading byte order mark)
# Inputs: 0) ExifTool object ref, 1) dirInfo hash ref, 2) tag table ref
# Returns: 1 on success, otherwise returns 0 and sets a Warning
sub ProcessKodakIFD($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dirStart = $$dirInfo{DirStart} || 0;
    return 1 if $dirStart <= 0 or $dirStart + 2 > $$dirInfo{DataLen};
    my $byteOrder = substr(${$$dirInfo{DataPt}}, $dirStart, 2);
    return 1 unless Image::ExifTool::SetByteOrder($byteOrder);
    $$dirInfo{DirStart} += 2;   # skip byte order mark
    $$dirInfo{DirLen} -= 2;
    if ($exifTool->{HTML_DUMP}) {
        my $base = $$dirInfo{Base} + $$dirInfo{DataPos};
        $exifTool->HtmlDump($dirStart+$base, 2, "Byte Order Mark");
    }
    return Image::ExifTool::Exif::ProcessExif($exifTool, $dirInfo, $tagTablePtr);
}

#------------------------------------------------------------------------------
# Write Kodak IFD (with leading byte order mark)
# Inputs: 0) ExifTool object ref, 1) source dirInfo ref, 2) tag table ref
# Returns: Exif data block (may be empty if no Exif data) or undef on error
sub WriteKodakIFD($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dirStart = $$dirInfo{DirStart} || 0;
    return '' if $dirStart <= 0 or $dirStart + 2 > $$dirInfo{DataLen};
    my $byteOrder = substr(${$$dirInfo{DataPt}}, $dirStart, 2);
    return '' unless Image::ExifTool::SetByteOrder($byteOrder);
    $$dirInfo{DirStart} += 2;   # skip byte order mark
    $$dirInfo{DirLen} -= 2;
    my $buff = Image::ExifTool::Exif::WriteExif($exifTool, $dirInfo, $tagTablePtr);
    return $buff unless defined $buff and length $buff;
    # apply one-time fixup for length of byte order mark
    if ($$dirInfo{Fixup}) {
        $dirInfo->{Fixup}->{Shift} += 2;
        $$dirInfo{Fixup}->ApplyFixup(\$buff);
        delete $$dirInfo{Fixup};
    }
    return Image::ExifTool::GetByteOrder() . $buff;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::Kodak - Kodak EXIF maker notes and APP3 "Meta" tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to
interpret Kodak maker notes EXIF meta information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<Image::MetaData::JPEG|Image::MetaData::JPEG>

=item L<http://www.ozhiker.com/electronics/pjmt/jpeg_info/meta.html>

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=item (...plus lots of testing with my daughter's CX4200!)

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Kodak Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
