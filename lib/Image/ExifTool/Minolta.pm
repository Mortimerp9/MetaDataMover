#------------------------------------------------------------------------------
# File:         Minolta.pm
#
# Description:  Minolta EXIF maker notes tags
#
# Revisions:    04/06/2004 - P. Harvey Created
#               09/09/2005 - P. Harvey Added ability to write MRW files
#
# References:   1) http://www.dalibor.cz/minolta/makernote.htm
#               2) Jay Al-Saadi private communication (testing with A2)
#               3) Shingo Noguchi, PhotoXP (http://www.daifukuya.com/photoxp/)
#               4) Niels Kristian Bech Jensen private communication
#               5) http://www.cybercom.net/~dcoffin/dcraw/
#               6) Pedro Corte-Real private communication
#               7) ExifTool forum post by bronek (http://www.cpanforum.com/posts/1118)
#               8) http://www.chauveau-central.net/mrw-format/
#               9) CPAN Forum post by 'geve' (http://www.cpanforum.com/threads/2168)
#              10) http://homepage3.nifty.com/kamisaka/makernote/makernote_km.htm
#              11) http://www.dyxum.com/dforum/forum_posts.asp?TID=6371&PN=1 and
#                  http://www.dyxum.com/dAdmin/lenses/MakerNoteList_Public.asp?stro=makr
#                  http://dyxum.com/dforum/forum_posts.asp?TID=23435&PN=2
#              12) http://www.minolta-forum.de/forum/index.php?showtopic=14914
#              13) http://www.mhohner.de/minolta/lenses.php
#              14) Jeffery Small private communication (tests with 7D)
#              15) http://homepage3.nifty.com/kamisaka/makernote/makernote_sony.htm
#              16) Thomas Kassner private communication
#              JD) Jens Duttke private communication
#------------------------------------------------------------------------------

package Image::ExifTool::Minolta;

use strict;
use vars qw($VERSION %minoltaLensIDs %minoltaColorMode %sonyColorMode %minoltaSceneMode);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.41';

# lens ID numbers (ref 3)
%minoltaLensIDs = (
    0 => 'Minolta AF 28-85mm F3.5-4.5',
    1 => 'Minolta AF 80-200mm F2.8 HS-APO G',
    2 => 'Minolta AF 28-70mm F2.8 G',
    3 => 'Minolta AF 28-80mm F4-5.6',
    5 => 'Minolta AF 35-70mm F3.5-4.5',
    6 => 'Minolta AF 24-85mm F3.5-4.5 [New]',
  # 7 => 'AF 100-400mm F4.5-6.7 (D)', ??
    7 => 'Minolta AF 100-300mm F4.5-5.6 APO [New]',
    8 => 'Minolta AF 70-210mm F4.5-5.6',
    9 => 'Minolta AF 50mm F3.5 Macro',
    10 => 'Minolta AF 28-105mm F3.5-4.5 [New]',
    11 => 'Minolta AF 300mm F4 HS-APO G',
    12 => 'Minolta AF 100mm F2.8 Soft Focus',
    13 => 'Minolta AF 75-300mm F4.5-5.6',
    14 => 'Minolta AF 100-400mm F4.5-6.7 APO',
    15 => 'Minolta AF 400mm F4.5 HS-APO G',
    16 => 'Minolta AF 17-35mm F3.5 G',
    17 => 'Minolta AF 20-35mm F3.5-4.5',
    18 => 'Minolta AF 28-80mm F3.5-5.6 II',
    19 => 'Minolta AF 35mm F1.4',
    20 => 'Minolta/Sony STF 135mm F2.8 [T4.5]',
    22 => 'Minolta AF 35-80mm F4-5.6',
    23 => 'Minolta AF 200mm F4 G APO Macro',
    24 => 'Minolta/Sony AF 24-105mm F3.5-4.5 (D)', # or Sigma 18-50mm F2.8 or Sigma 17-70mm F2.8-4.5 (D)',
    25 => 'Minolta AF 100-300mm F4.5-5.6 (APO D)',
    27 => 'Minolta AF 85mm F1.4 G',
    28 => 'Minolta AF 100mm F2.8 Macro (D)',
    29 => 'Minolta AF 75-300mm F4.5-5.6 (D)',
    30 => 'Minolta AF 28-80mm F3.5-5.6 (D)',
  # 30 => 'Sigma AF 12-24mm F4.5-5.6 EX DG',
  # 30 => 'Sigma 28-70mm EX DG F2.8', #16
    31 => 'Minolta/Sony AF 50mm F2.8 Macro (D) or AF 50mm F3.5 Macro',
  # 32 => 'AF 100-400mm F4.5-6.7 (D) x1.5', ??
    32 => 'Minolta AF 300mm F2.8 G',
    33 => 'Minolta/Sony AF 70-200mm F2.8 G (D) SSM',
    35 => 'Minolta AF 85mm F1.4 G (D) Limited',
    36 => 'Minolta AF 28-100mm F3.5-5.6 (D)',
    38 => 'Minolta AF 17-35mm F2.8-4 (D)',
    39 => 'Minolta AF 28-75mm F2.8 (D)',
    40 => 'Minolta/Sony AF DT 18-70mm F3.5-5.6 (D)',
    41 => 'Minolta/Sony AF DT 11-18mm F4.5-5.6 (D)',
    42 => 'Minolta AF DT 18-200mm F3.5-6.3 (D)',
    43 => 'Minolta AF 35mm F1.4 G',
    44 => 'Minolta AF 50mm F1.4',
    45 => 'Carl Zeiss Planar T* 85mm F1.4 ZA',
    46 => 'Carl Zeiss Vario-Sonnar T* DT 16-80mm F3.5-4.5 ZA',
    47 => 'Carl Zeiss Sonnar T* 135mm F1.8 ZA',
    50 => 'Sony AF DT 18-250mm F3.5-6.3', #11
    51 => 'Sony AF DT 16-105mm F3.5-5.6 or 55-200mm f/4-5.5', #11
    128 => 'Tamron Lens (various models)',
  # 128 => 'Tamron 18-200, 28-300 or 80-300mm F3.5-6.3',
  # 128 => 'Tamron AF 28-200mm F3.8-5.6 XR Di Aspherical [IF] MACRO', (ref JD)
    129 => 'Tamron 200-400mm F5.6 or 70-300mm f/4-5.6 LD', #12
    135 => 'Vivitar 28-210mm F3.5-5.6', #16
    137 => 'Cosina 70-210mm F2.8-4 AF', #11
    138 => 'Soligor 19-35mm F3.5-4.5', #11
    255 => 'Tamron Lens (various models)',
  # 255 => 'Tamron SP AF 17-50mm f/2.8 XR Di II LD Aspherical',
  # 255 => 'Tamron AF 55-200mm f/4-5.6 Di II',
  # 255 => 'Tamron AF 70-300mm f/4-5.6 Di LD MACRO 1:2',
  # 255 => 'Tamron SP AF 200-500mm f/5.0-6.3 Di LD IF',
    255 => 'Tamron AF 70-300mm f/4-5.6 Di LD MACRO 1:2', #JD
    25501 => 'Minolta AF 50mm F1.7', #7
    25511 => 'Minolta AF 35-70mm F4',
  # 25511 => 'Sigma UC AF 28-70mm F3.5-4.5', #12
  # 25511 => 'Sigma M-AF 70-200mm F2.8 EX Aspherical', #12
  # 25511 => 'Sigma UC 28-70mm F3.5-4.5 HighSpeed-AF', #16
    25521 => 'Minolta AF 28-85mm F3.5-4.5 [New]',
  # 25521 => 'Tokina 19-35mm F3.5-4.5', #3
  # 25521 => 'Tokina 28-70mm F2.8 AT-X', #7
  # 25521 => 'Tokina 80-400mm F4.5-5.6 AT-X AF II 840', #Jens
    25531 => 'Minolta AF 28-135mm F4-4.5',
  # 25531 => 'Sigma ZOOM-alpha 35-135mm F3.5-4.5', #16
    25541 => 'Minolta AF 35-105mm F3.5-4.5', #13
    25551 => 'Minolta AF 70-210mm F4 Macro', # or Sigma 70-210mm F4-5.6 APO or Sigma M-AF 70-200mm F2.8 EX APO', #7/6
    25561 => 'Minolta AF 135mm F2.8',
    25571 => 'Minolta AF 28mm F2.8',
    25581 => 'Minolta AF 24-50mm F4',
    25601 => 'Minolta AF 100-200mm F4.5',
    25611 => 'Minolta AF 75-300mm F4.5-5.6', #13 # or Sigma 70-300mm F4-5.6 or Sigma 300mm F4 APO Macro', #12/3/7
    25621 => 'Minolta/Sony AF 50mm F1.4 [New]', #13
    25631 => 'Minolta AF 300mm F2.8 G',
    25641 => 'Minolta AF 50mm F2.8 Macro',
    25651 => 'Minolta AF 600mm F4',
    25661 => 'Minolta AF 24mm F2.8',
    25721 => 'Minolta/Sony AF 500mm F8 Reflex',
    25781 => 'Minolta AF 16mm F2.8 Fisheye', # or Sigma 8mm F4 Fisheye or Sigma 14mm F3.5',
    25791 => 'Minolta AF 20mm F2.8',
    25811 => 'Minolta/Sony AF 100mm F2.8 Macro New', # or Tamron 90mm F2.8 Macro or Sigma 180mm F5.6 Macro',
    25851 => 'Beroflex 35-135mm F3.5-4.5', #16
    25858 => 'Minolta AF 35-105mm F3.5-4.5 New', # or Tamron 24-135mm F3.5-5.6',
    25881 => 'Minolta AF 70-210mm F3.5-4.5',
    25891 => 'Minolta AF 80-200 F2.8 APO', # or Tokina 80-200mm F2.8',
    25911 => 'Minolta AF 35mm F1.4', #(from Sony list)
    25921 => 'Minolta AF 85mm F1.4 G (D)',
    25931 => 'Minolta AF 200mm F2.8 G APO',
    25941 => 'Minolta AF 3x-1x F1.7-2.8 Macro',
    25961 => 'Minolta AF 28mm F2',
    25971 => 'Minolta AF 35mm F2',
    25981 => 'Minolta AF 100mm F2',
    26041 => 'Minolta AF 80-200mm F4.5-5.6',
    26051 => 'Minolta AF 35-80mm F4-5.6', #(from Sony list)
    26061 => 'Minolta AF 100-300mm F4.5-5.6 (D)',
    26071 => 'Minolta AF 35-80mm F4-5.6', #13
    26081 => 'Minolta AF 300mm F2.8 G',
    26091 => 'Minolta AF 600mm F4 HS-APO G',
    26121 => 'Minolta AF 200mm F2.8 G HS-APO',
    26131 => 'Minolta AF 50mm F1.7 New',
    26151 => 'Minolta AF 28-105mm F3.5-4.5 Power Zoom',
    26161 => 'Minolta AF 35-200mm F4.5-5.6 Power Zoom',
    26181 => 'Minolta AF 28-80mm F4-5.6 Power Zoom',
    26191 => 'Minolta AF 80-200mm F4.5-5.6 Power Zoom',
    26201 => 'Minolta AF 28-70mm F2.8 G', #11
    26211 => 'Minolta AF 100-300mm F4.5-5.6 Power Zoom',
    26241 => 'Minolta AF 35-80mm F4-5.6 Power Zoom',
    26281 => 'Minolta AF 80-200mm F2.8 G', #11
    26291 => 'Minolta AF 85mm F1.4 New',
    26311 => 'Minolta/Sony AF 100-300mm F4.5-5.6 APO', #11
    26321 => 'Minolta AF 24-50mm F4 New',
    26381 => 'Minolta AF 50mm F2.8 Macro New',
    26391 => 'Minolta AF 100mm F2.8 Macro',
    26411 => 'Minolta AF 20mm F2.8 New',
    26421 => 'Minolta AF 24mm F2.8 New',
    26441 => 'Minolta AF 100-400mm F4.5-6.7 APO', #11
    26621 => 'Minolta AF 50mm F1.4 New',
    26671 => 'Minolta AF 35mm F2 New',
    26681 => 'Minolta AF 28mm F2 New',
    26721 => 'Minolta AF 24-105mm F3.5-4.5 (D)', #11
    45741 => 'Minolta AF 200mm F2.8 G x2', # or Tokina 300mm F2.8 x2',
    45851 => 'Tamron - SP AF 300 F2.8 LD IF', #11
);

%minoltaColorMode = (
    0 => 'Natural color',
    1 => 'Black & White',
    2 => 'Vivid color',
    3 => 'Solarization',
    4 => 'Adobe RGB',
    5 => 'Sepia', #10
    9 => 'Natural', #10
    12 => 'Portrait', #10
    13 => 'Natural sRGB',
    14 => 'Natural+ sRGB',
    15 => 'Landscape', #10
    16 => 'Evening', #10
    17 => 'Night Scene', #10
    18 => 'Night Portrait', #10
);

%sonyColorMode = ( #15
    0 => 'Standard',
    1 => 'Vivid', #PH
    2 => 'Portrait',
    3 => 'Landscape',
    4 => 'Sunset',
    5 => 'Night Portrait',
    6 => 'B&W',
    7 => 'Adobe RGB',
    12 => 'Neutral', #Sony4
    100 => 'Neutral', #JD
    101 => 'Clear', #JD
    102 => 'Deep', #JD
    103 => 'Light', #JD
    104 => 'Night View', #JD
    105 => 'Autumn Leaves', #JD
);

%minoltaSceneMode = (
    0 => 'Standard',
    1 => 'Portrait',
    2 => 'Text',
    3 => 'Night Scene',
    4 => 'Sunset',
    5 => 'Sports',
    6 => 'Landscape',
    7 => 'Night Portrait', #JD
    8 => 'Macro',
    9 => 'Super Macro',
    16 => 'Auto',
    17 => 'Night View/Portrait',
);

# Minolta tag table
%Image::ExifTool::Minolta::Main = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0000 => {
        Name => 'MakerNoteVersion',
        Writable => 'undef',
        Count => 4,
    },
    0x0001 => {
        Name => 'MinoltaCameraSettingsOld',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Minolta::CameraSettings',
            ByteOrder => 'BigEndian',
        },
    },
    0x0003 => {
        Name => 'MinoltaCameraSettings',
        # These camera settings are different for the DiMAGE X31
        Condition => '$self->{Model} ne "DiMAGE X31"',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Minolta::CameraSettings',
            ByteOrder => 'BigEndian',
        },
    },
    0x0004 => { #8
        Name => 'MinoltaCameraSettings7D',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Minolta::CameraSettings7D',
            ByteOrder => 'BigEndian',
        },
    },
    # it appears that image stabilization is on if this tag exists (ref 2),
    # but it is an 8kB binary data block!
    0x0018 => {
        Name => 'ImageStabilization',
        Condition => '$self->{Model} =~ /^DiMAGE (A1|A2|X1)$/',
        Notes => q{
            a block of binary data which exists in DiMAGE A2 (and A1/X1?) images only if
            image stabilization is enabled
        },
        ValueConv => '"On"',
    },
    0x0040 => {
        Name => 'CompressedImageSize',
        Writable => 'int32u',
    },
    0x0081 => {
        # JPEG preview found in DiMAGE 7 images
        %Image::ExifTool::previewImageTagInfo,
        Permanent => 1,     # don't add this to a file
    },
    0x0088 => {
        Name => 'PreviewImageStart',
        Flags => 'IsOffset',
        OffsetPair => 0x0089, # point to associated byte count
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x0089 => {
        Name => 'PreviewImageLength',
        OffsetPair => 0x0088, # point to associated offset
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x0100 => { #10
        Name => 'SceneMode',
        Writable => 'int32u',
        PrintConv => \%minoltaSceneMode,
    },
    0x0101 => [
        {
            Name => 'ColorMode',
            Condition => '$self->{Make} !~ /^SONY/',
            Priority => 0, # Other ColorMode is more reliable for A2
            Writable => 'int32u',
            PrintConv => \%minoltaColorMode,
        },
        { #15
            Name => 'ColorMode',
            Writable => 'int32u',
            Notes => 'Sony models',
            PrintConv => \%sonyColorMode,
        },
    ],
    0x0102 => {
        Name => 'MinoltaQuality',
        Writable => 'int32u',
        # PrintConv strings conform with Minolta reference manual (ref 4)
        # (note that Minolta calls an uncompressed TIFF image "Super fine")
        PrintConv => {
            0 => 'Raw',
            1 => 'Super Fine',
            2 => 'Fine',
            3 => 'Standard',
            4 => 'Economy',
            5 => 'Extra fine',
        },
    },
    # (0x0103 is the same as 0x0102 above) -- this is true for some
    # cameras (A2/7Hi), but not others - PH
    0x0103 => [
        {
            Name => 'MinoltaQuality',
            Writable => 'int32u',
            Condition => '$self->{Model} =~ /^DiMAGE (A2|7Hi)$/',
            Notes => 'quality for DiMAGE A2/7Hi',
            Priority => 0, # lower priority because this doesn't work for A200
            PrintConv => { #4
                0 => 'Raw',
                1 => 'Super Fine',
                2 => 'Fine',
                3 => 'Standard',
                4 => 'Economy',
                5 => 'Extra fine',
            },
        },
        { #PH
            Name => 'MinoltaImageSize',
            Writable => 'int32u',
            Condition => '$self->{Model} !~ /^DiMAGE A200$/',
            Notes => 'image size for other models except A200',
            PrintConv => {
                1 => '1600x1200',
                2 => '1280x960',
                3 => '640x480',
                5 => '2560x1920',
                6 => '2272x1704',
                7 => '2048x1536',
            },
        },
    ],
    0x0104 => { #14
        Name => 'FlashExposureComp',
        Description => 'Flash Exposure Compensation',
        Writable => 'rational64s',
    },
    0x0105 => { #10
        Name => 'Teleconverter',
        Writable => 'int32u',
        PrintHex => 1,
        PrintConv => {
            0x00 => 'None',
            0x48 => 'Minolta AF 2x APO (D)',
            0x50 => 'Minolta AF 2x APO II',
            0x88 => 'Minolta AF 1.4x APO (D)',
            0x90 => 'Minolta AF 1.4x APO II',
        },
    },
    0x0107 => { #8
        Name => 'ImageStabilization',
        Writable => 'int32u',
        PrintConv => {
            1 => 'Off',
            5 => 'On',
        },
    },
    0x010a => {
        Name => 'ZoneMatching',
        Writable => 'int32u',
        PrintConv => {
            0 => 'ISO Setting Used',
            1 => 'High Key',
            2 => 'Low Key',
        },
    },
    0x010b => {
        Name => 'ColorTemperature',
        Writable => 'int32u',
    },
    0x010c => { #3 (Alpha 7)
        Name => 'LensID',
        Writable => 'int32u',
        PrintConv => \%minoltaLensIDs,
    },
    # 0x010e - WhiteBalance according to ref #10
    0x0113 => { #PH
        Name => 'ImageStabilization',
        Condition => '$self->{Model} eq "DSLR-A100"',
        Notes => 'valid for Sony A100 only',
        Writable => 'int32u',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x0114 => [
        { #8
            Name => 'MinoltaCameraSettings5D',
            Condition => '$self->{Model} =~ /^(DYNAX 5D|MAXXUM 5D|ALPHA SWEET)/',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Minolta::CameraSettings5D',
                ByteOrder => 'BigEndian',
            },
        },
        { #PH
            Name => 'MinoltaCameraSettingsA100',
            Condition => '$self->{Model} eq "DSLR-A100"',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Minolta::CameraSettingsA100',
                ByteOrder => 'BigEndian', # required because order differs for ARW and JPG images
            },
        },
    ],
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        Writable => 0,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
    0x0f00 => {
        Name => 'MinoltaCameraSettings2',
        Writable => 0,
    },
);

%Image::ExifTool::Minolta::CameraSettings = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    PRIORITY => 0, # not as reliable as other tags
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FORMAT => 'int32u',
    FIRST_ENTRY => 0,
    NOTES => q{
        There is some variability in CameraSettings information between different
        models (and sometimes even between different firmware versions), so this
        information may not be as reliable as it should be.  Because of this, tags
        in the following tables are set to lower priority to prevent them from
        superceeding the values of same-named tags in other locations when duplicate
        tags are disabled.
    },
    1 => {
        Name => 'ExposureMode',
        PrintConv => {
            0 => 'Program',
            1 => 'Aperture Priority',
            2 => 'Shutter Priority',
            3 => 'Manual',
        },
    },
    2 => {
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Fill flash',
            1 => 'Red-eye reduction',
            2 => 'Rear flash sync',
            3 => 'Wireless',
            4 => 'Off?', #PH
        },
    },
    3 => {
        Name => 'WhiteBalance',
        PrintConv => 'Image::ExifTool::Minolta::ConvertWhiteBalance($val)',
    },
    4 => {
        Name => 'MinoltaImageSize',
        PrintConv => {
            0 => 'Full',
            1 => '1600x1200',
            2 => '1280x960',
            3 => '640x480',
            6 => '2080x1560', #PH (A2)
            7 => '2560x1920', #PH (A2)
            8 => '3264x2176', #PH (A2)
        },
    },
    5 => {
        Name => 'MinoltaQuality',
        PrintConv => { #4
            0 => 'Raw',
            1 => 'Super Fine',
            2 => 'Fine',
            3 => 'Standard',
            4 => 'Economy',
            5 => 'Extra Fine',
        },
    },
    6 => {
        Name => 'DriveMode',
        PrintConv => {
            0 => 'Single',
            1 => 'Continuous',
            2 => 'Self-timer',
            4 => 'Bracketing',
            5 => 'Interval',
            6 => 'UHS continuous',
            7 => 'HS continuous',
        },
    },
    7 => {
        Name => 'MeteringMode',
        PrintConv => {
            0 => 'Multi-segment',
            1 => 'Center-weighted average',
            2 => 'Spot',
        },
    },
    8 => {
        Name => 'ISO',
        ValueConv => '2 ** (($val-48)/8) * 100',
        ValueConvInv => '48 + 8*log($val/100)/log(2)',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    9 => {
        Name => 'ExposureTime',
        ValueConv => '2 ** ((48-$val)/8)',
        ValueConvInv => '48 - 8*log($val)/log(2)',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    10 => {
        Name => 'FNumber',
        ValueConv => '2 ** (($val-8)/16)',
        ValueConvInv => '8 + 16*log($val)/log(2)',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    11 => {
        Name => 'MacroMode',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    12 => {
        Name => 'DigitalZoom',
        PrintConv => {
            0 => 'Off',
            1 => 'Electronic magnification',
            2 => '2x',
        },
    },
    13 => {
        Name => 'ExposureCompensation',
        ValueConv => '$val/3 - 2',
        ValueConvInv => '($val + 2) * 3',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    14 => {
        Name => 'BracketStep',
        PrintConv => {
            0 => '1/3 EV',
            1 => '2/3 EV',
            2 => '1 EV',
        },
    },
    16 => 'IntervalLength',
    17 => 'IntervalNumber',
    18 => {
        Name => 'FocalLength',
        ValueConv => '$val / 256',
        ValueConvInv => '$val * 256',
        PrintConv => 'sprintf("%.1f mm",$val)',
        PrintConvInv => '$val=~s/\s*mm$//;$val',
    },
    19 => {
        Name => 'FocusDistance',
        ValueConv => '$val / 1000',
        ValueConvInv => '$val * 1000',
        PrintConv => '$val ? "$val m" : "inf"',
        PrintConvInv => '$val eq "inf" ? 0 : $val =~ s/\s*m$//, $val',
    },
    20 => {
        Name => 'FlashFired',
        PrintConv => {
            0 => 'No',
            1 => 'Yes',
        },
    },
    21 => {
        Name => 'MinoltaDate',
        Groups => { 2 => 'Time' },
        Shift => 'Time',
        ValueConv => 'sprintf("%4d:%.2d:%.2d",$val>>16,($val&0xff00)>>8,$val&0xff)',
        ValueConvInv => 'my @a=($val=~/(\d+):(\d+):(\d+)/); @a ? ($a[0]<<16)+($a[1]<<8)+$a[2] : undef',
    },
    22 => {
        Name => 'MinoltaTime',
        Groups => { 2 => 'Time' },
        Shift => 'Time',
        ValueConv => 'sprintf("%.2d:%.2d:%.2d",$val>>16,($val&0xff00)>>8,$val&0xff)',
        ValueConvInv => 'my @a=($val=~/(\d+):(\d+):(\d+)/); @a ? ($a[0]<<16)+($a[1]<<8)+$a[2] : undef',
    },
    23 => {
        Name => 'MaxAperture',
        ValueConv => '2 ** (($val-8)/16)',
        ValueConvInv => '8 + 16*log($val)/log(2)',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    26 => {
        Name => 'FileNumberMemory',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    27 => 'LastFileNumber',
    28 => {
        Name => 'ColorBalanceRed',
        ValueConv => '$val / 256',
        ValueConvInv => '$val * 256',
    },
    29 => {
        Name => 'ColorBalanceGreen',
        ValueConv => '$val / 256',
        ValueConvInv => '$val * 256',
    },
    30 => {
        Name => 'ColorBalanceBlue',
        ValueConv => '$val / 256',
        ValueConvInv => '$val * 256',
    },
    31 => {
        Name => 'Saturation',
        ValueConv => '$val - ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
        ValueConvInv => '$val + ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    32 => {
        Name => 'Contrast',
        ValueConv => '$val - ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
        ValueConvInv => '$val + ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    33 => {
        Name => 'Sharpness',
        PrintConv => {
            0 => 'Hard',
            1 => 'Normal',
            2 => 'Soft',
        },
    },
    34 => {
        Name => 'SubjectProgram',
        PrintConv => {
            0 => 'None',
            1 => 'Portrait',
            2 => 'Text',
            3 => 'Night portrait',
            4 => 'Sunset',
            5 => 'Sports action',
        },
    },
    35 => {
        Name => 'FlashExposureComp',
        Description => 'Flash Exposure Compensation',
        ValueConv => '($val - 6) / 3',
        ValueConvInv => '$val * 3 + 6',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    36 => {
        Name => 'ISOSetting',
        PrintConv => {
            0 => 100,
            1 => 200,
            2 => 400,
            3 => 800,
            4 => 'Auto',
            5 => 64,
        },
    },
    37 => {
        Name => 'MinoltaModelID',
        PrintConv => {
            0 => 'DiMAGE 7, X1, X21 or X31',
            1 => 'DiMAGE 5',
            2 => 'DiMAGE S304',
            3 => 'DiMAGE S404',
            4 => 'DiMAGE 7i',
            5 => 'DiMAGE 7Hi',
            6 => 'DiMAGE A1',
            7 => 'DiMAGE A2 or S414',
        },
    },
    38 => {
        Name => 'IntervalMode',
        PrintConv => {
            0 => 'Still Image',
            1 => 'Time-lapse Movie',
        },
    },
    39 => {
        Name => 'FolderName',
        PrintConv => {
            0 => 'Standard Form',
            1 => 'Data Form',
        },
    },
    40 => {
        Name => 'ColorMode',
        PrintConv => {
            0 => 'Natural color',
            1 => 'Black & White',
            2 => 'Vivid color',
            3 => 'Solarization',
            4 => 'Adobe RGB',
        },
    },
    41 => {
        Name => 'ColorFilter',
        ValueConv => '$val - ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
        ValueConvInv => '$val + ($self->{Model}=~/DiMAGE A2/ ? 5 : 3)',
    },
    42 => 'BWFilter',
    43 => {
        Name => 'InternalFlash',
        PrintConv => {
            0 => 'No',
            1 => 'Fired',
        },
    },
    44 => {
        Name => 'Brightness',
        ValueConv => '$val/8 - 6',
        ValueConvInv => '($val + 6) * 8',
    },
    45 => 'SpotFocusPointX',
    46 => 'SpotFocusPointY',
    47 => {
        Name => 'WideFocusZone',
        PrintConv => {
            0 => 'No zone',
            1 => 'Center zone (horizontal orientation)',
            2 => 'Center zone (vertical orientation)',
            3 => 'Left zone',
            4 => 'Right zone',
        },
    },
    48 => {
        Name => 'FocusMode',
        PrintConv => {
            0 => 'AF',
            1 => 'MF',
        },
    },
    49 => {
        Name => 'FocusArea',
        PrintConv => {
            0 => 'Wide Focus (normal)',
            1 => 'Spot Focus',
        },
    },
    50 => {
        Name => 'DECPosition',
        PrintConv => {
            0 => 'Exposure',
            1 => 'Contrast',
            2 => 'Saturation',
            3 => 'Filter',
        },
    },
    # 7Hi only:
    51 => {
        Name => 'ColorProfile',
        Condition => '$self->{Model} eq "DiMAGE 7Hi"',
        Notes => 'DiMAGE 7Hi only',
        PrintConv => {
            0 => 'Not Embedded',
            1 => 'Embedded',
        },
    },
    # (the following may be entry 51 for other models?)
    52 => {
        Name => 'DataImprint',
        Condition => '$self->{Model} eq "DiMAGE 7Hi"',
        Notes => 'DiMAGE 7Hi only',
        PrintConv => {
            0 => 'None',
            1 => 'YYYY/MM/DD',
            2 => 'MM/DD/HH:MM',
            3 => 'Text',
            4 => 'Text + ID#',
        },
    },
    63 => { #9
        Name => 'FlashMetering',
        PrintConv => {
            0 => 'ADI (Advanced Distance Integration)',
            1 => 'Pre-flash TTL',
            2 => 'Manual flash control',
        },
    },
);

# Camera settings used by the 7D (ref 8)
%Image::ExifTool::Minolta::CameraSettings7D = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    PRIORITY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    0x00 => {
        Name => 'ExposureMode',
        PrintConv => {
            0 => 'Program',
            1 => 'Aperture Priority',
            2 => 'Shutter Priority',
            3 => 'Manual',
            4 => 'Auto',
            5 => 'Program-shift A',
            6 => 'Program-shift S',
        },
    },
    0x02 => { #PH
        Name => 'MinoltaImageSize',
        PrintConv => {
            0 => 'Large',
            1 => 'Medium',
            2 => 'Small',
        },
    },
    0x03 => {
        Name => 'MinoltaQuality',
        PrintConv => {
            0 => 'RAW',
            16 => 'Fine', #PH
            32 => 'Normal', #PH
            34 => 'RAW+JPEG',
            48 => 'Economy', #PH
        },
    },
    0x04 => {
        Name => 'WhiteBalance',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Shade',
            3 => 'Cloudy',
            4 => 'Tungsten',
            5 => 'Fluorescent',
            0x100 => 'Kelvin',
            0x200 => 'Manual',
        },
    },
    0x0e => {
        Name => 'FocusMode',
        PrintConv => {
            0 => 'Single-shot AF',
            1 => 'Continuous AF',
            # Note: these two are reversed in ref 8
            3 => 'Manual', #JD
            4 => 'Automatic AF', #JD
        },
    },
    0x10 => {
        Name => 'AFPoints',
        PrintConv => { BITMASK => {
            0 => 'Center',
            1 => 'Top',
            2 => 'Top-Right',
            3 => 'Right',
            4 => 'Bottom-Right',
            5 => 'Bottom',
            6 => 'Bottom-Left',
            7 => 'Left',
            8 => 'Top-Left',
        } },
    },
    0x15 => {
        Name => 'Flash',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x16 => { #10
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Normal',
            1 => 'Red-eye reduction',
            2 => 'Rear flash sync',
        },
    },
    0x1c => {
        Name => 'ISOSetting',
        PrintConv => {
            0 => 'Auto', #10
            1 => 100,
            3 => 200,
            4 => 400,
            5 => 800,
            6 => 1600,
            7 => 3200,
        },
    },
    0x1e => {
        Name => 'ExposureCompensation',
        Format => 'int16s',
        ValueConv => '$val / 24',
        ValueConvInv => '$val * 24',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    0x25 => {
        Name => 'ColorSpace',
        PrintConv => {
            0 => 'Natural sRGB',
            1 => 'Natural+ sRGB',
            4 => 'Adobe RGB',
        },
    },
    0x26 => {
        Name => 'Sharpness',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x27 => {
        Name => 'Contrast',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x28 => {
        Name => 'Saturation',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x2d => 'FreeMemoryCardImages',
    0x3f => {
        Format => 'int16s',
        Name => 'ColorTemperature',
        ValueConv => '$val * 100',
        ValueConvInv => '$val / 100',
    },
    0x40 => { #10
        Name => 'HueAdjustment',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x46 => {
        Name => 'Rotation',
        PrintConv => {
            72 => 'Horizontal (normal)',
            76 => 'Rotate 90 CW',
            82 => 'Rotate 270 CW',
        },
    },
    0x47 => {
        Name => 'FNumber',
        ValueConv => '2 ** (($val-8)/16)',
        ValueConvInv => '8 + 16*log($val)/log(2)',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    0x48 => {
        Name => 'ExposureTime',
        ValueConv => '2 ** ((48-$val)/8)',
        ValueConvInv => '48 - 8*log($val)/log(2)',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x4a => 'FreeMemoryCardImages',
    0x5e => {
        Name => 'ImageNumber',
        Notes => q{
            this information may appear at index 98 (0x62), depending on firmware
            version
        },
        ValueConv => '$val + 1',
        ValueConvInv => '$val - 1',
    },
    0x60 => {
        Name => 'NoiseReduction',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x62 => {
        Name => 'ImageNumber2',
        ValueConv => '$val + 1',
        ValueConvInv => '$val - 1',
    },
    0x71 => {
        Name => 'ImageStabilization',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x75 => {
        Name => 'ZoneMatchingOn',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
);

# Camera settings used by the 5D (ref 8)
%Image::ExifTool::Minolta::CameraSettings5D = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    PRIORITY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    0x0a => {
        Name => 'ExposureMode',
        PrintConv => {
            0 => 'Program',
            1 => 'Aperture Priority',
            2 => 'Shutter Priority',
            3 => 'Manual',
            4 => 'Auto?',
            4131 => 'Connected Copying?',
        },
    },
    0x0c => { #PH
        Name => 'MinoltaImageSize',
        PrintConv => {
            0 => 'Large',
            1 => 'Medium',
            2 => 'Small',
        },
    },
    0x0d => {
        Name => 'MinoltaQuality',
        PrintConv => {
            0 => 'RAW',
            16 => 'Fine', #PH
            32 => 'Normal', #PH
            34 => 'RAW+JPEG',
            48 => 'Economy', #PH
        },
    },
    0x0e => {
        Name => 'WhiteBalance',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Cloudy',
            3 => 'Shade',
            4 => 'Tungsten',
            5 => 'Fluorescent',
            6 => 'Flash',
            0x100 => 'Kelvin',
            0x200 => 'Manual',
        },
    },
    # 0x0f-0x11 something to do with WB RGB levels as shot? (PH)
    # 0x12-0x17 RGB levels for other WB modes (with G missing)? (PH)
    0x1f => { #PH
        Name => 'Flash',
        PrintConv => {
            0 => 'Did not fire',
            1 => 'Fired',
        },
    },
    0x20 => { #10
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Normal',
            1 => 'Red-eye reduction',
            2 => 'Rear flash sync',
        },
    },
    0x25 => {
        Name => 'MeteringMode',
        PrintConv => {
            0 => 'Multi-segment',
            1 => 'Center-weighted average',
            2 => 'Spot',
        },
    },
    0x26 => {
        Name => 'ISOSetting',
        PrintConv => {
            0 => 'Auto',
            1 => 100,
            3 => 200,
            4 => 400,
            5 => 800,
            6 => 1600,
            7 => 3200,
            8 => '200 (Zone Matching High)',
            10 => '80 (Zone Matching Low)',
        },
    },
# looks wrong:
#    0x28 => { #10
#        Name => 'ExposureCompensation',
#        ValueConv => '$val / 24',
#        ValueConvInv => '$val * 24',
#    },
    0x2f => { #10
        Name => 'ColorSpace',
        PrintConv => {
            0 => 'Natural sRGB',
            1 => 'Natural+ sRGB',
            2 => 'Monochrome',
            4 => 'Adobe RGB (ICC)',
            5 => 'Adobe RGB',
        },
    },
    0x30 => {
        Name => 'Sharpness',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x31 => {
        Name => 'Contrast',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x32 => {
        Name => 'Saturation',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x35 => { #PH
        Name => 'ExposureTime',
        ValueConv => '2 ** ((48-$val)/8)',
        ValueConvInv => '48 - 8*log($val)/log(2)',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    0x36 => { #PH
        Name => 'FNumber',
        ValueConv => '2 ** (($val-8)/16)',
        ValueConvInv => '8 + 16*log($val)/log(2)',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    0x37 => 'FreeMemoryCardImages',
    # 0x38 definitely not related to exposure comp as in ref 8 (PH)
    0x49 => { #PH
        Name => 'ColorTemperature',
        Format => 'int16s',
        ValueConv => '$val * 100',
        ValueConvInv => '$val / 100',
    },
    0x4a => { #10
        Name => 'HueAdjustment',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
    },
    0x50 => {
        Name => 'Rotation',
        PrintConv => {
            72 => 'Horizontal (normal)',
            76 => 'Rotate 90 CW',
            82 => 'Rotate 270 CW',
        },
    },
    0x53 => {
        Name => 'ExposureCompensation',
        ValueConv => '$val / 100 - 3',
        ValueConvInv => '($val + 3) * 100',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    0x54 => 'FreeMemoryCardImages',
    0x65 => { #10
        Name => 'Rotation',
        PrintConv => {
            0 => 'Horizontal (normal)',
            1 => 'Rotate 90 CW',
            2 => 'Rotate 270 CW',
        },
    },
    # 0x66 maybe program mode or some setting like this? (PH)
    0x6e => { #10
        Name => 'ColorTemperature',
        Format => 'int16s',
        ValueConv => '$val * 100',
        ValueConvInv => '$val / 100',
    },
    0x71 => { #10
        Name => 'PictureFinish',
        PrintConv => {
            0 => 'Natural',
            1 => 'Natural+',
            2 => 'Portrait',
            3 => 'Wind Scene',
            4 => 'Evening Scene',
            5 => 'Night Scene',
            6 => 'Night Portrait',
            7 => 'Monochrome',
            8 => 'Adobe RGB',
            9 => 'Adobe RGB (ICC)',
        },
    },
    # 0x95 FlashStrength? (PH)
    # 0xa4 similar information to 0x27, except with different values
    0xae => {
        Name => 'ImageNumber',
        ValueConv => '$val + 1',
        ValueConvInv => '$val - 1',
    },
    0xb0 => {
        Name => 'NoiseReduction',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0xbd => {
        Name => 'ImageStabilization',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
);

# Camera settings used by the Sony DSLR-A100 (ref PH)
%Image::ExifTool::Minolta::CameraSettingsA100 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    NOTES => 'Camera settings information for the Sony DSLR-A100.',
    WRITABLE => 1,
    PRIORITY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    0x00 => { #15
        Name => 'ExposureMode',
        PrintHex => 1,
        PrintConv => {
            0 => 'Program',
            1 => 'Aperture Priority',
            2 => 'Shutter Priority',
            3 => 'Manual',
            4 => 'Auto',
            0x1013 => 'Portrait',
            0x1053 => 'Landscape',
        },
    },
    0x01 => { #15
        Name => 'ExposureCompensation',
        ValueConv => '$val / 100 - 3',
        ValueConvInv => 'int(($val + 3) * 100 + 0.5)',
    },
    # 0x09 some sort of APEX value (ref 15)
    0x0b => { #15
        Name => 'WhiteBalance',
        PrintHex => 1,
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Cloudy',
            3 => 'Shade',
            4 => 'Tungsten',
            5 => 'Fluorescent',
            6 => 'Flash',
            0x100 => 'Kelvin',
            0x200 => 'Manual',
        },
    },
    # 0x12 => 'MeteringMode' (ref 15)
    # 0x13 => 'ISO' (ref 15)
    # 0x14 => 'ZoneMatching' (ref 15)
    # 0x15 => 'DynamicRangeOptimizer' (ref 15)
    0x16 => { #15
        Name => 'ColorMode',
        PrintConv => {
            0 => 'Standard',
            1 => 'Vivid',
            2 => 'Portrait',
            3 => 'Landscape',
            4 => 'Sunset',
            5 => 'Night Scene',
            7 => 'B&W',
            8 => 'Adobe RGB',
        },
    },
    # 0x17 => 'ColorSpace' (ref 15)
    0x18 => { #15
        Name => 'Sharpness',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    0x19 => { #15
        Name => 'Contrast',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    0x1a => { #15
        Name => 'Saturation',
        ValueConv => '$val - 10',
        ValueConvInv => '$val + 10',
        PrintConv => 'Image::ExifTool::Exif::PrintParameter($val)',
        PrintConvInv => '$val=~/normal/i ? 0 : $val',
    },
    0x1e => { #PH
        Name => 'DriveMode',
        PrintConv => {
            0 => 'Single Frame',
            1 => 'Continuous',
            2 => 'Self-timer',
            3 => 'Continuous Bracketing',
            4 => 'Single-Frame Bracketing',
            5 => 'White Balance Bracketing',
        },
    },
    0x3f => { #PH
        Name => 'NoiseReduction',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x5a => { #15
        Name => 'Rotation',
        PrintConv => {
            0 => 'Horizontal (Normal)',
            1 => 'Rotate 270 CW',
            2 => 'Rotate 90 CW',
        },
    },
    0x57 => { #15
        Name => 'ImageStabilization',
        Writable => 'int32u',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x5e => { #15
        Name => 'ColorTemperature',
        ValueConv => '$val * 100',
        ValueConvInv => '$val / 100',
    },
);

# tags in Konica Minolta MOV videos (ref PH)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::Minolta::MOV1 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => q{
        This information is found in MOV videos from some Konica Minolta models such
        as the DiMage Z10 and X50.
    },
    0 => {
        Name => 'Make',
        Format => 'string[32]',
    },
    0x20 => {
        Name => 'ModelType',
        Format => 'string[8]',
    },
    # (01 00 at offset 0x28)
    0x2e => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val ? 10 / $val : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x32 => {
        Name => 'FNumber',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x3a => {
        Name => 'ExposureCompensation',
        Format => 'rational64s',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
    },
    # 0x4c => 'WhiteBalance', ?
    0x50 => {
        Name => 'FocalLength',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f mm",$val)',
    },
);

# tags in Minolta MOV videos (ref PH)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::Minolta::MOV2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => q{
        This information is found in MOV videos from some Minolta models such as the
        DiMAGE X and Xt.
    },
    0 => {
        Name => 'Make',
        Format => 'string[32]',
    },
    0x18 => {
        Name => 'ModelType',
        Format => 'string[8]',
    },
    # (01 00 at offset 0x20)
    0x26 => {
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val ? 10 / $val : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x2a => {
        Name => 'FNumber',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x32 => {
        Name => 'ExposureCompensation',
        Format => 'rational64s',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
    },
    # 0x44 => 'WhiteBalance', ?
    0x48 => {
        Name => 'FocalLength',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f mm",$val)',
    },
);

# more tags in Minolta MOV videos (ref PH)
%Image::ExifTool::Minolta::MMA = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => q{
        This information is found in MOV videos from Minolta models such as the
        DiMAGE A2, S414 and 7Hi.
    },
    0 => {
        Name => 'Make',
        Format => 'string[20]',
    },
    20 => {
        Name => 'SoftwareVersion',
        Format => 'string[16]',
    },
);

# basic Minolta white balance lookup
my %minoltaWhiteBalance = (
    0 => 'Auto',
    1 => 'Daylight',
    2 => 'Cloudy',
    3 => 'Tungsten',
    5 => 'Custom',
    7 => 'Fluorescent',
    8 => 'Fluorescent 2',
    11 => 'Custom 2',
    12 => 'Custom 3',
    # the following come from tests with the A2 (ref 2)
    0x0800000 => 'Auto',
    0x1800000 => 'Daylight',
    0x2800000 => 'Cloudy',
    0x3800000 => 'Tungsten',
    0x4800000 => 'Flash',
    0x5800000 => 'Fluorescent',
    0x6800000 => 'Shade',
    0x7800000 => 'Custom1',
    0x8800000 => 'Custom2',
    0x9800000 => 'Custom3',
);

#------------------------------------------------------------------------------
# PrintConv for Minolta white balance
sub ConvertWhiteBalance($)
{
    my $val = shift;
    my $printConv = $minoltaWhiteBalance{$val};
    unless (defined $printConv) {
        if ($val & 0xffff0000) {
            # the A2 values can be shifted by += 3 settings, where
            # each setting adds or subtracts 0x0010000 (ref 2)
            my $type = ($val & 0xff000000) + 0x800000;
            if ($minoltaWhiteBalance{$type}) {
                $printConv = $minoltaWhiteBalance{$type} .
                             sprintf("%+.8g", ($val - $type) / 0x10000);
            } else {
                $printConv = sprintf("Unknown (0x%x)", $val);
            }
        } else {
            $printConv = sprintf("Unknown ($val)");
        }
    }
    return $printConv;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::Minolta - Minolta EXIF maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Minolta and Konica-Minolta maker notes in EXIF information, and to read
and write Minolta RAW (MRW) images.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.dalibor.cz/minolta/makernote.htm>

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Jay Al-Saadi, Niels Kristian Bech Jensen, Shingo Noguchi, Pedro
Corte-Real, Jeffery Small, Jens Duttke and  Thomas Kassner for the
information they provided.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Minolta Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
