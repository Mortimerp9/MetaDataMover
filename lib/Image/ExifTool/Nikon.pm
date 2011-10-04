#------------------------------------------------------------------------------
# File:         Nikon.pm
#
# Description:  Nikon EXIF maker notes tags
#
# Revisions:    12/09/2003 - P. Harvey Created
#               05/17/2004 - P. Harvey Added information from Joseph Heled
#               09/21/2004 - P. Harvey Changed tag 2 to ISOUsed & added PrintConv
#               12/01/2004 - P. Harvey Added default PRINT_CONV
#               12/06/2004 - P. Harvey Added SceneMode
#               01/01/2005 - P. Harvey Decode preview image and preview IFD
#               03/35/2005 - T. Christiansen additions
#               05/10/2005 - P. Harvey Decode encrypted lens data
#
# References:   1) http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html
#               2) Joseph Heled private communication (tests with D70)
#               3) Thomas Walter private communication (tests with Coolpix 5400)
#               4) http://www.cybercom.net/~dcoffin/dcraw/
#               5) Brian Ristuccia private communication (tests with D70)
#               6) Danek Duvall private communication (tests with D70)
#               7) Tom Christiansen private communication (tests with D70)
#               8) Robert Rottmerhusen private communication
#               9) http://members.aol.com/khancock/pilot/nbuddy/
#              10) Werner Kober private communication (D2H, D2X, D100, D70, D200)
#              11) http://www.rottmerhusen.com/objektives/lensid/thirdparty.html
#              12) http://libexif.sourceforge.net/internals/mnote-olympus-tag_8h-source.html
#              13) Roger Larsson private communication (tests with D200)
#              14) http://homepage3.nifty.com/kamisaka/makernote/makernote_nikon.htm (2007/09/15)
#              15) http://tomtia.plala.jp/DigitalCamera/MakerNote/index.asp
#              16) Jeffrey Friedl private communication (D200 with firmware update)
#              17) http://www.wohlberg.net/public/software/photo/nstiffexif/
#              18) Anonymous user private communication (D70, D200, D2x)
#              19) Bruce Stevens private communication
#              20) Vladimir Sauta private communication (D80)
#              21) Gregor Dorlars private communication (D300)
#              22) Tanel Kuusk private communication
#              23) Alexandre Naaman private communication (D3)
#              JD) Jens Duttke private communication
#------------------------------------------------------------------------------

package Image::ExifTool::Nikon;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.91';

# nikon lens ID numbers (ref 8/11)
my %nikonLensIDs = (
    Notes => q{
        The Nikon LensID is constructed as a Composite tag from the raw hex values
        of 8 other tags: LensIDNumber, LensFStops, MinFocalLength, MaxFocalLength,
        MaxApertureAtMinFocal, MaxApertureAtMaxFocal, MCUVersion and LensType, in
        that order.  (source:
        L<http://www.rottmerhusen.com/objektives/lensid/thirdparty.html>)
    },
    # (hex digits must be uppercase in keys below)
    '01 58 50 50 14 14 02 00' => 'AF Nikkor 50mm f/1.8',
    '01 00 00 00 00 00 02 00' => 'AF Teleconverter TC-16A 1.6x',
    '01 00 00 00 00 00 08 00' => 'AF Teleconverter TC-16A 1.6x',
    '02 42 44 5C 2A 34 02 00' => 'AF Zoom-Nikkor 35-70mm f/3.3-4.5',
    '02 42 44 5C 2A 34 08 00' => 'AF Zoom-Nikkor 35-70mm f/3.3-4.5',
    '03 48 5C 81 30 30 02 00' => 'AF Zoom-Nikkor 70-210mm f/4',
    '04 48 3C 3C 24 24 03 00' => 'AF Nikkor 28mm f/2.8',
    '05 54 50 50 0C 0C 04 00' => 'AF Nikkor 50mm f/1.4',
    '06 54 53 53 24 24 06 00' => 'AF Micro-Nikkor 55mm f/2.8',
    '07 40 3C 62 2C 34 03 00' => 'AF Zoom-Nikkor 28-85mm f/3.5-4.5',
    '08 40 44 6A 2C 34 04 00' => 'AF Zoom-Nikkor 35-105mm f/3.5-4.5',
    '09 48 37 37 24 24 04 00' => 'AF Nikkor 24mm f/2.8',
    '0A 48 8E 8E 24 24 03 00' => 'AF Nikkor 300mm f/2.8 IF-ED',
    '0B 48 7C 7C 24 24 05 00' => 'AF Nikkor 180mm f/2.8 IF-ED',
    '0D 40 44 72 2C 34 07 00' => 'AF Zoom-Nikkor 35-135mm f/3.5-4.5',
    '0E 48 5C 81 30 30 05 00' => 'AF Zoom-Nikkor 70-210mm f/4',
    '0F 58 50 50 14 14 05 00' => 'AF Nikkor 50mm f/1.8 N',
    '10 48 8E 8E 30 30 08 00' => 'AF Nikkor 300mm f/4 IF-ED',
    '11 48 44 5C 24 24 08 00' => 'AF Zoom-Nikkor 35-70mm f/2.8',
    '12 48 5C 81 30 3C 09 00' => 'AF Nikkor 70-210mm f/4-5.6',
    '13 42 37 50 2A 34 0B 00' => 'AF Zoom-Nikkor 24-50mm f/3.3-4.5',
    '14 48 60 80 24 24 0B 00' => 'AF Zoom-Nikkor 80-200mm f/2.8 ED',
    '15 4C 62 62 14 14 0C 00' => 'AF Nikkor 85mm f/1.8',
    '17 3C A0 A0 30 30 11 00' => 'Nikkor 500mm f/4 P',
    '18 40 44 72 2C 34 0E 00' => 'AF Zoom-Nikkor 35-135mm f/3.5-4.5 N',
    '1A 54 44 44 18 18 11 00' => 'AF Nikkor 35mm f/2',
    '1B 44 5E 8E 34 3C 10 00' => 'AF Zoom-Nikkor 75-300mm f/4.5-5.6',
    '1C 48 30 30 24 24 12 00' => 'AF Nikkor 20mm f/2.8',
    '1D 42 44 5C 2A 34 12 00' => 'AF Zoom-Nikkor 35-70mm f/3.3-4.5 N',
    '1E 54 56 56 24 24 13 00' => 'AF Micro-Nikkor 60mm f/2.8',
    '1F 54 6A 6A 24 24 14 00' => 'AF Micro-Nikkor 105mm f/2.8',
    '20 48 60 80 24 24 15 00' => 'AF Zoom-Nikkor ED 80-200mm f/2.8',
    '21 40 3C 5C 2C 34 16 00' => 'AF Zoom-Nikkor 28-70mm f/3.5-4.5',
    '22 48 72 72 18 18 16 00' => 'AF DC-Nikkor 135mm f/2',
    '24 48 60 80 24 24 1A 02' => 'AF Zoom-Nikkor ED 80-200mm f/2.8D',
    '25 48 44 5C 24 24 1B 02' => 'AF Zoom-Nikkor 35-70mm f/2.8D',
    '25 48 44 5C 24 24 52 02' => 'AF Zoom-Nikkor 35-70mm f/2.8D',
    '27 48 8E 8E 24 24 1D 02' => 'AF-I Nikkor 300mm f/2.8D IF-ED',
    '27 48 8E 8E 24 24 F1 02' => 'AF-I Nikkor 300mm f/2.8D IF-ED + TC-14E',
    '27 48 8E 8E 24 24 E1 02' => 'AF-I Nikkor 300mm f/2.8D IF-ED + TC-17E',
    '27 48 8E 8E 24 24 F2 02' => 'AF-I Nikkor 300mm f/2.8D IF-ED + TC-20E',
    '28 3C A6 A6 30 30 1D 02' => 'AF-I Nikkor 600mm f/4D IF-ED',
    '2A 54 3C 3C 0C 0C 26 02' => 'AF Nikkor 28mm f/1.4D',
    '2C 48 6A 6A 18 18 27 02' => 'AF DC-Nikkor 105mm f/2D',
    '2D 48 80 80 30 30 21 02' => 'AF Micro-Nikkor 200mm f/4D IF-ED',
    '2E 48 5C 82 30 3C 28 02' => 'AF Nikkor 70-210mm f/4-5.6D',
    '2F 48 30 44 24 24 29 02' => 'AF Zoom-Nikkor 20-35mm f/2.8D IF',
    '31 54 56 56 24 24 25 02' => 'AF Micro-Nikkor 60mm f/2.8D',
    '32 54 6A 6A 24 24 35 02' => 'AF Micro-Nikkor 105mm f/2.8D',
  # '32 54 6A 6A 24 24 35 02' => 'Sigma MACRO 105mm f/2.8 EX DG', #JD
    '33 48 2D 2D 24 24 31 02' => 'AF Nikkor 18mm f/2.8D',
    '34 48 29 29 24 24 32 02' => 'AF Fisheye Nikkor 16mm f/2.8D',
    '35 3C A0 A0 30 30 33 02' => 'AF-I Nikkor 500mm f/4D IF-ED',
    '36 48 37 37 24 24 34 02' => 'AF Nikkor 24mm f/2.8D',
    '37 48 30 30 24 24 36 02' => 'AF Nikkor 20mm f/2.8D',
    '38 4C 62 62 14 14 37 02' => 'AF Nikkor 85mm f/1.8D',
    '3A 40 3C 5C 2C 34 39 02' => 'AF Zoom-Nikkor 28-70mm f/3.5-4.5D',
    '3B 48 44 5C 24 24 3A 02' => 'AF Zoom-Nikkor 35-70mm f/2.8D N',
    '3D 3C 44 60 30 3C 3E 02' => 'AF Zoom-Nikkor 35-80mm f/4-5.6D',
    '3E 48 3C 3C 24 24 3D 02' => 'AF Nikkor 28mm f/2.8D',
    '3F 40 44 6A 2C 34 45 02' => 'AF Zoom-Nikkor 35-105mm f/3.5-4.5D',
    '41 48 7C 7C 24 24 43 02' => 'AF Nikkor 180mm f/2.8D IF-ED',
    '42 54 44 44 18 18 44 02' => 'AF Nikkor 35mm f/2D',
    '43 54 50 50 0C 0C 46 02' => 'AF Nikkor 50mm f/1.4D',
    '44 44 60 80 34 3C 47 02' => 'AF Nikkor 80-200mm f/4.5-5.6D',
    '45 40 3C 60 2C 3C 48 02' => 'AF Zoom-Nikkor 28-80mm F/3.5-5.6D',
    '46 3C 44 60 30 3C 49 02' => 'AF Zoom-Nikkor 35-80mm f/4-5.6D N',
    '47 42 37 50 2A 34 4A 02' => 'AF Zoom-Nikkor 24-50mm f/3.3-4.5D',
    '48 48 8E 8E 24 24 4B 02' => 'AF-S Nikkor 300mm f/2.8D IF-ED',
    '49 3C A6 A6 30 30 4C 02' => 'AF-S Nikkor 600mm f/4D IF-ED',
    '49 3C A6 A6 30 30 F1 02' => 'AF-S Nikkor 600mm f/4D IF-ED + TC-14E',
    '49 3C A6 A6 30 30 F2 02' => 'AF-S Nikkor 600mm f/4D IF-ED + TC-20E',
    '4A 54 62 62 0C 0C 4D 02' => 'AF Nikkor 85mm f/1.4D IF',
    '4B 3C A0 A0 30 30 4E 02' => 'AF-S Nikkor 500mm f/4D IF-ED',
    '4B 3C A0 A0 30 30 F1 02' => 'AF-S Nikkor 500mm f/4D IF-ED + TC-14E',
    '4B 3C A0 A0 30 30 F2 02' => 'AF-S Nikkor 500mm f/4D IF-ED + TC-20E',
    '4C 40 37 6E 2C 3C 4F 02' => 'AF Zoom-Nikkor 24-120mm f/3.5-5.6D IF',
    '4D 40 3C 80 2C 3C 62 02' => 'AF Zoom-Nikkor 28-200mm f/3.5-5.6D IF',
    '4E 48 72 72 18 18 51 02' => 'AF DC-Nikkor 135mm f/2D',
    '4F 40 37 5C 2C 3C 53 06' => 'IX-Nikkor 24-70mm f/3.5-5.6',
    '53 48 60 80 24 24 60 02' => 'AF Zoom-Nikkor 80-200mm f/2.8D ED',
    '54 44 5C 7C 34 3C 58 02' => 'AF Zoom-Micro Nikkor 70-180mm f/4.5-5.6D ED',
    '56 48 5C 8E 30 3C 5A 02' => 'AF Zoom-Nikkor 70-300mm f/4-5.6D ED',
    '59 48 98 98 24 24 5D 02' => 'AF-S Nikkor 400mm f/2.8D IF-ED',
    '5A 3C 3E 56 30 3C 5E 06' => 'IX-Nikkor 30-60mm f/4-5.6',
    '5D 48 3C 5C 24 24 63 02' => 'AF-S Zoom-Nikkor 28-70mm f/2.8D IF-ED',
    '5E 48 60 80 24 24 64 02' => 'AF-S Zoom-Nikkor 80-200mm f/2.8D IF-ED',
    '5F 40 3C 6A 2C 34 65 02' => 'AF Zoom-Nikkor 28-105mm f/3.5-4.5D IF',
    '60 40 3C 60 2C 3C 66 02' => 'AF Zoom-Nikkor 28-80mm f/3.5-5.6D', #(http://www.exif.org/forum/topic.asp?TOPIC_ID=16)
    '61 44 5E 86 34 3C 67 02' => 'AF Zoom-Nikkor 75-240mm f/4.5-5.6D',
    '63 48 2B 44 24 24 68 02' => 'AF-S Nikkor 17-35mm f/2.8D IF-ED',
    '64 00 62 62 24 24 6A 02' => 'PC Micro-Nikkor 85mm f/2.8D',
    '65 44 60 98 34 3C 6B 0A' => 'AF VR Zoom-Nikkor 80-400mm f/4.5-5.6D ED',
    '66 40 2D 44 2C 34 6C 02' => 'AF Zoom-Nikkor 18-35mm f/3.5-4.5D IF-ED',
    '67 48 37 62 24 30 6D 02' => 'AF Zoom-Nikkor 24-85mm f/2.8-4D IF',
    '68 42 3C 60 2A 3C 6E 06' => 'AF Zoom-Nikkor 28-80mm f/3.3-5.6G',
    '69 48 5C 8E 30 3C 6F 06' => 'AF Zoom-Nikkor 70-300mm f/4-5.6G',
    '6A 48 8E 8E 30 30 70 02' => 'AF-S Nikkor 300mm f/4D IF-ED',
    '6B 48 24 24 24 24 71 02' => 'AF Nikkor ED 14mm f/2.8D',
    '6D 48 8E 8E 24 24 73 02' => 'AF-S Nikkor 300mm f/2.8D IF-ED II',
    '6E 48 98 98 24 24 74 02' => 'AF-S Nikkor 400mm f/2.8D IF-ED II',
    '6F 3C A0 A0 30 30 75 02' => 'AF-S Nikkor 500mm f/4D IF-ED II',
    '70 3C A6 A6 30 30 76 02' => 'AF-S Nikkor 600mm f/4D IF-ED II',
    '72 48 4C 4C 24 24 77 00' => 'Nikkor 45mm f/2.8 P',
    '74 40 37 62 2C 34 78 06' => 'AF-S Zoom-Nikkor 24-85mm f/3.5-4.5G IF-ED',
    '75 40 3C 68 2C 3C 79 06' => 'AF Zoom-Nikkor 28-100mm f/3.5-5.6G',
    '76 58 50 50 14 14 7A 02' => 'AF Nikkor 50mm f/1.8D',
    '77 48 5C 80 24 24 7B 0E' => 'AF-S VR Zoom-Nikkor 70-200mm f/2.8G IF-ED',
    '78 40 37 6E 2C 3C 7C 0E' => 'AF-S VR Zoom-Nikkor 24-120mm f/3.5-5.6G IF-ED',
    '79 40 3C 80 2C 3C 7F 06' => 'AF Zoom-Nikkor 28-200mm f/3.5-5.6G IF-ED',
    '7A 3C 1F 37 30 30 7E 06' => 'AF-S DX Zoom-Nikkor 12-24mm f/4G IF-ED',
    '7B 48 80 98 30 30 80 0E' => 'AF-S VR Zoom-Nikkor 200-400mm f/4G IF-ED',
    '7D 48 2B 53 24 24 82 06' => 'AF-S DX Zoom-Nikkor 17-55mm f/2.8G IF-ED',
    '7F 40 2D 5C 2C 34 84 06' => 'AF-S DX Zoom-Nikkor 18-70mm f/3.5-4.5G IF-ED',
    '80 48 1A 1A 24 24 85 06' => 'AF DX Fisheye-Nikkor 10.5mm f/2.8G ED',
    '81 54 80 80 18 18 86 0E' => 'AF-S VR Nikkor 200mm f/2G IF-ED',
    '82 48 8E 8E 24 24 87 0E' => 'AF-S VR Nikkor 300mm f/2.8G IF-ED',
    '89 3C 53 80 30 3C 8B 06' => 'AF-S DX Zoom-Nikkor 55-200mm f/4-5.6G ED',
    '8A 54 6A 6A 24 24 8C 0E' => 'AF-S VR Micro-Nikkor 105mm f/2.8G IF-ED', #10
    '8B 40 2D 80 2C 3C FD 0E' => 'AF-S DX VR Zoom-Nikkor 18-200mm f/3.5-5.6G IF-ED', #20
    '8B 40 2D 80 2C 3C 8D 0E' => 'AF-S DX VR Zoom-Nikkor 18-200mm f/3.5-5.6G IF-ED',
    '8C 40 2D 53 2C 3C 8E 06' => 'AF-S DX Zoom-Nikkor 18-55mm f/3.5-5.6G ED',
    '8D 44 5C 8E 34 3C 8F 0E' => 'AF-S VR Zoom-Nikkor 70-300mm f/4.5-5.6G IF-ED', #10
    '8F 40 2D 72 2C 3C 91 06' => 'AF-S DX Zoom-Nikkor 18-135mm f/3.5-5.6G IF-ED',
    '90 3B 53 80 30 3C 92 0E' => 'AF-S DX VR Zoom-Nikkor 55-200mm f/4-5.6G IF-ED',
    '92 48 24 37 24 24 94 06' => 'AF-S Zoom-Nikkor 14-24mm f/2.8G ED',
    '93 48 37 5C 24 24 95 06' => 'AF-S Zoom-Nikkor 24-70mm f/2.8G ED',
    '94 40 2D 53 2C 3C 96 06' => 'AF-S DX Zoom-Nikkor 18-55mm f/3.5-5.6G ED II', #10 (D40)
    '95 4C 37 37 2C 2C 97 02' => 'PC-E Nikkor 24mm f/3.5D ED',
    '95 00 37 37 2C 2C 97 06' => 'PC-E Nikkor 24mm f/3.5D ED', #JD
    '96 48 98 98 24 24 98 0E' => 'AF-S VR Nikkor 400mm f/2.8G ED',
    '97 3C A0 A0 30 30 99 0E' => 'AF-S VR Nikkor 500mm f/4G ED',
    '98 3C A6 A6 30 30 9A 0E' => 'AF-S VR Nikkor 600mm f/4G ED',
    '99 40 29 62 2C 3C 9B 0E' => 'AF-S DX VR Zoom-Nikkor 16-85mm f/3.5-5.6G ED',
    '9A 40 2D 53 2C 3C 9C 0E' => 'AF-S DX VR Zoom-Nikkor 18-55mm f/3.5-5.6G',
    '9C 54 56 56 24 24 9E 06' => 'AF-S Micro Nikkor 60mm f/2.8G ED',
#
    'FE 47 00 00 24 24 4B 06' => 'Sigma 4.5mm f/2.8 EX DC HSM Circular Fisheye', #JD
    '26 48 11 11 30 30 1C 02' => 'Sigma 8mm F4 EX Circular Fisheye',
    '79 40 11 11 2C 2C 1C 06' => 'Sigma 8mm F3.5 EX', #JD
    '02 3F 24 24 2C 2C 02 00' => 'Sigma 14mm F3.5',
    '48 48 24 24 24 24 4B 02' => 'Sigma 14mm F2.8 EX Aspherical HSM',
    '26 48 27 27 24 24 1C 02' => 'Sigma 15mm F2.8 EX Diagonal Fish-Eye',
    '26 58 31 31 14 14 1C 02' => 'Sigma 20mm F1.8 EX Aspherical DG DF RF',
    '26 58 37 37 14 14 1C 02' => 'Sigma 24mm F1.8 EX Aspherical DG DF MACRO',
    '02 46 37 37 25 25 02 00' => 'Sigma 24mm F2.8 Macro',
    '26 58 3C 3C 14 14 1C 02' => 'Sigma 28mm F1.8 EX DG DF',
    '48 54 3E 3E 0C 0C 4B 06' => 'Sigma 30mm F1.4 EX DC HSM',
    '32 54 50 50 24 24 35 02' => 'Sigma 50mm F2.8 EX DG Macro',
    '79 48 5C 5C 24 24 1C 06' => 'Sigma 70mm F2.8 EX DG Macro', #JD
    '02 48 65 65 24 24 02 00' => 'Sigma 90mm F2.8 Macro',
    '48 48 76 76 24 24 4B 06' => 'Sigma 150mm F2.8 EX DG APO Macro HSM',
    '48 4C 7C 7C 2C 2C 4B 02' => 'Sigma 180mm F3.5 EX DG Macro',
    '48 4C 7D 7D 2C 2C 4B 02' => 'Sigma APO MACRO 180mm F3.5 EX DG HSM',
    '48 54 8E 8E 24 24 4B 02' => 'Sigma APO 300mm F2.8 EX DG HSM',
    '26 48 8E 8E 30 30 1C 02' => 'Sigma APO TELE MACRO 300mm F4',
    '02 2F 98 98 3D 3D 02 00' => 'Sigma 400mm F5.6 APO',
    '02 37 A0 A0 34 34 02 00' => 'Sigma APO 500mm F4.5', #19
    '48 44 A0 A0 34 34 4B 02' => 'Sigma APO 500mm F4.5 EX HSM',
    '48 3C 19 31 30 3C 4B 06' => 'Sigma 10-20mm F4-5.6 EX DC HSM',
    'F9 3C 19 31 30 3C 4B 06' => 'Sigma 10-20mm F4-5.6 EX DC HSM', #JD
    '48 38 1F 37 34 3C 4B 06' => 'Sigma 12-24mm F4.5-5.6 EX Aspherical DG HSM',
    '26 40 27 3F 2C 34 1C 02' => 'Sigma 15-30mm F3.5-4.5 EX Aspherical DG DF',
    '48 48 2B 44 24 30 4B 06' => 'Sigma 17-35mm F2.8-4 EX DG  Aspherical HSM',
    '26 54 2B 44 24 30 1C 02' => 'Sigma 17-35mm F2.8-4 EX Aspherical',
    '7A 47 2B 5C 24 34 4B 06' => 'Sigma 17-70mm F2.8-4.5 DC Macro Asp. IF HSM',
    '7F 48 2B 5C 24 34 1C 06' => 'Sigma 17-70mm F2.8-4.5 DC Macro Asp. IF',
    '26 40 2D 44 2B 34 1C 02' => 'Sigma 18-35 F3.5-4.5 Aspherical',
    '26 48 2D 50 24 24 1C 06' => 'Sigma 18-50mm F2.8 EX DC',
    '7A 48 2D 50 24 24 4B 06' => 'Sigma 18-50mm F2.8 EX DC HSM',
    '26 40 2D 50 2C 3C 1C 06' => 'Sigma 18-50mm F3.5-5.6 DC',
    '7A 40 2D 50 2C 3C 4B 06' => 'Sigma 18-50mm F3.5-5.6 DC HSM',
    '26 40 2D 70 2B 3C 1C 06' => 'Sigma 18-125mm F3.5-5.6 DC',
    '26 40 2D 80 2C 40 1C 06' => 'Sigma 18-200mm F3.5-6.3 DC',
    '26 48 31 49 24 24 1C 02' => 'Sigma 20-40mm F2.8',
    '26 48 37 56 24 24 1C 02' => 'Sigma 24-60mm F2.8 EX DG',
    'B6 48 37 56 24 24 1C 02' => 'Sigma 24-60mm F2.8 EX DG',
    '26 54 37 5C 24 24 1C 02' => 'Sigma 24-70mm F2.8 EX DG Macro',
    '67 54 37 5C 24 24 1C 02' => 'Sigma 24-70mm F2.8 EX DG Macro',
    '26 40 37 5C 2C 3C 1C 02' => 'Sigma 24-70mm F3.5-5.6 Aspherical HF',
    '26 54 37 73 24 34 1C 02' => 'Sigma 24-135mm F2.8-4.5',
    '02 46 3C 5C 25 25 02 00' => 'Sigma 28-70mm F2.8',
    '26 54 3C 5C 24 24 1C 02' => 'Sigma 28-70mm F2.8 EX',
    '26 48 3C 5C 24 24 1C 06' => 'Sigma 28-70mm F2.8 EX DG',
    '26 48 3C 5C 24 30 1C 02' => 'Sigma 28-70mm F2.8-4 High Speed Zoom',
    '02 3F 3C 5C 2D 35 02 00' => 'Sigma 28-70mm F3.5-4.5 UC',
    '26 40 3C 60 2C 3C 1C 02' => 'Sigma 28-80mm F3.5-5.6 Mini Zoom Macro II Aspherical',
    '26 40 3C 65 2C 3C 1C 02' => 'Sigma 28-90mm F3.5-5.6 Macro',
    '26 48 3C 6A 24 30 1C 02' => 'Sigma 28-105mm F2.8-4 Aspherical',
    '26 3E 3C 6A 2E 3C 1C 02' => 'Sigma 28-105mm F3.8-5.6 UC-III Aspherical IF',
    '26 40 3C 80 2C 3C 1C 02' => 'Sigma 28-200mm F3.5-5.6 Compact Aspherical Hyperzoom Macro',
    '26 40 3C 80 2B 3C 1C 02' => 'Sigma 28-200mm F3.5-5.6 Compact Aspherical Hyperzoom Macro',
    '26 41 3C 8E 2C 40 1C 02' => 'Sigma 28-300mm F3.5-6.3 DG Macro',
    '26 40 3C 8E 2C 40 1C 02' => 'Sigma 28-300mm F3.5-6.3 Macro',
    '02 40 44 73 2B 36 02 00' => 'Sigma 35-135mm F3.5-4.5 a',
    '7A 47 50 76 24 24 4B 06' => 'Sigma APO 50-150mm F2.8 EX DC HSM',
    '48 3C 50 A0 30 40 4B 02' => 'Sigma 50-500mm F4-6.3 EX APO RF HSM',
    '26 3C 54 80 30 3C 1C 06' => 'Sigma 55-200mm F4-5.6 DC',
    '7A 3B 53 80 30 3C 4B 06' => 'Sigma 55-200mm F4-5.6 DC HSM',
    '48 54 5C 80 24 24 4B 02' => 'Sigma 70-200mm F2.8 EX APO IF HSM',
    '02 46 5C 82 25 25 02 00' => 'Sigma 70-210mm F2.8 APO', #JD
    '26 3C 5C 82 30 3C 1C 02' => 'Sigma 70-210mm F4-5.6 UC-II',
    '26 3C 5C 8E 30 3C 1C 02' => 'Sigma 70-300mm F4-5.6 DG Macro',
    '56 3C 5C 8E 30 3C 1C 02' => 'Sigma 70-300mm F4-5.6 APO Macro Super II',
    'E0 3C 5C 8E 30 3C 4B 06' => 'Sigma 70-300mm F4-5.6 APO DG Macro HSM', #22
    '02 37 5E 8E 35 3D 02 00' => 'Sigma 75-300mm F4.5-5.6 APO',
    '02 3A 5E 8E 32 3D 02 00' => 'Sigma 75-300mm F4.0-5.6',
    '77 44 61 98 34 3C 7B 0E' => 'Sigma 80-400mm f4.5-5.6 EX OS',
    '48 48 68 8E 30 30 4B 02' => 'Sigma 100-300mm F4 EX IF HSM',
    '48 54 6F 8E 24 24 4B 02' => 'Sigma APO 120-300mm F2.8 EX DG HSM',
    '26 44 73 98 34 3C 1C 02' => 'Sigma 135-400mm F4.5-5.6 APO Aspherical',
    '26 40 7B A0 34 40 1C 02' => 'Sigma APO 170-500mm F5-6.3 Aspherical RF',
    '48 3C 8E B0 3C 3C 4B 02' => 'Sigma APO 300-800 F5.6 EX DG HSM',
#
    '32 53 64 64 24 24 35 02' => 'Tamron SP AF90mm f/2.8 Di Macro 1:1 (272E)',
    '00 4C 7C 7C 2C 2C 00 02' => 'Tamron SP AF180mm f/3.5 Di Model B01',
    '00 36 1C 2D 34 3C 00 06' => 'Tamron SP AF11-18mm f/4.5-5.6 Di II LD Aspherical (IF)',
    '07 46 2B 44 24 30 03 02' => 'Tamron SP AF17-35mm f/2.8-4 Di LD Aspherical (IF)',
    '00 53 2B 50 24 24 00 06' => 'Tamron SP AF17-50mm f/2.8 (A16)', #PH
    '00 3F 2D 80 2B 40 00 06' => 'Tamron AF18-200mm f/3.5-6.3 XR Di II LD Aspherical (IF)',
    '00 3F 2D 80 2C 40 00 06' => 'Tamron AF18-200mm f/3.5-6.3 XR Di II LD Aspherical (IF) Macro',
    '00 40 2D 88 2C 40 00 06' => 'Tamron AF18-250mm f/3.5-6.3 Di II LD Aspherical (IF) Macro (A18NII)', #JD
    '00 40 2D 88 2C 40 62 06' => 'Tamron AF18-250mm F/3.5-6.3 Di II LD Aspherical (IF) Macro', # A18N?
    '07 40 2F 44 2C 34 03 02' => 'Tamron AF19-35mm f/3.5-4.5 N',
    '07 40 30 45 2D 35 03 02' => 'Tamron AF19-35mm f/3.5-4.5',
    '00 49 30 48 22 2B 00 02' => 'Tamron SP AF20-40mm f/2.7-3.5',
    '0E 4A 31 48 23 2D 0E 02' => 'Tamron SP AF20-40mm f/2.7-3.5',
    '45 41 37 72 2C 3C 48 02' => 'Tamron SP AF24-135mm f/3.5-5.6 AD Aspherical (IF) Macro',
    '33 54 3C 5E 24 24 62 02' => 'Tamron SP AF28-75mm f/2.8 XR Di LD Aspherical (IF) Macro',
    '10 3D 3C 60 2C 3C D2 02' => 'Tamron AF28-80mm f/3.5-5.6 Aspherical',
    '45 3D 3C 60 2C 3C 48 02' => 'Tamron AF28-80mm f/3.5-5.6 Aspherical',
    '00 48 3C 6A 24 24 00 02' => 'Tamron SP AF28-105mm f/2.8',
    '0B 3E 3D 7F 2F 3D 0E 02' => 'Tamron AF28-200mm f/3.8-5.6D',
    '0B 3E 3D 7F 2F 3D 0E 00' => 'Tamron AF28-200mm f/3.8-5.6',
    '4D 41 3C 8E 2B 40 62 02' => 'Tamron AF28-300mm f/3.5-6.3 XR Di LD Aspherical (IF)',
    '4D 41 3C 8E 2C 40 62 02' => 'Tamron AF28-300mm f/3.5-6.3 XR LD Aspherical (IF)',
    '00 47 53 80 30 3C 00 06' => 'Tamron AF55-200mm f/4-5.6 Di II LD',
    '69 48 5C 8E 30 3C 6F 02' => 'Tamron AF70-300mm f/4-5.6 LD Macro 1:2',
    '20 3C 80 98 3D 3D 1E 02' => 'Tamron AF200-400mm f/5.6 LD IF',
    '00 3E 80 A0 38 3F 00 02' => 'Tamron SP AF200-500mm f/5-6.3 Di LD (IF)',
    '00 3F 80 A0 38 3F 00 02' => 'Tamron SP AF200-500mm f/5-6.3 Di',
#
    '00 40 2B 2B 2C 2C 00 02' => 'Tokina AT-X 17 AF PRO - AF 17mm f/3.5',
    '00 47 44 44 24 24 00 06' => 'Tokina AT-X M35 Pro DX - 35mm f/2.8',
    '00 54 68 68 24 24 00 02' => 'Tokina AT-X M100 PRO D - 100mm f/2.8',
    '00 54 8E 8E 24 24 00 02' => 'Tokina AT-X 300 AF PRO 300mm f/2.8',
    '00 40 18 2B 2C 34 00 06' => 'Tokina AT-X 107 DX Fish-Eye -AF 10-17mm f/3.5-4.5',
    '00 48 1C 29 24 24 00 06' => 'Tokina AT-X 116 PRO DX AF 11-16mm f/2.8',
    '00 3C 1F 37 30 30 00 06' => 'Tokina AT-X 124 AF PRO DX - AF 12-24mm f/4',
    '00 48 29 50 24 24 00 06' => 'Tokina AT-X 165 PRO DX - AF 16-50mm f/2.8',
    '07 48 3C 5C 24 24 03 00' => 'Tokina AT-X AF 28-70mm f/2.8', #JD
    '25 48 3C 5C 24 24 1B 02' => 'Tokina AT-X 287 AF PRO SV 28-70mm f/2.8',
    '00 48 3C 60 24 24 00 02' => 'Tokina AT-X 280 AF PRO 28-80mm f/2.8 Aspherical',
    '00 48 50 72 24 24 00 06' => 'Tokina AT-X 535 PRO DX - AF 50-135mm f/2.8',
    '14 54 60 80 24 24 0B 00' => 'Tokina AT-X 828 AF 80-200mm f/2.8',
    '24 44 60 98 34 3C 1A 02' => 'Tokina AT-X 840 AF II 80-400mm f/4.5-5.6',
    '00 44 60 98 34 3C 00 02' => 'Tokina AT-X 840D 80-400mm f/4.5-5.6', #PH
    '14 48 68 8E 30 30 0B 00' => 'Tokina AT-X 340 AF II 100-300mm f/4',
#
    '00 54 56 56 30 30 00 00' => 'Coastal Optical Systems 60mm 1:4 UV-VIS-IR Macro Apo',
#
    '00 54 48 48 18 18 00 00' => 'Voigtlander Ultron SL2 40mm f/2 SL II Aspherical',
    '00 54 55 55 0C 0C 00 00' => 'Voigtlander Nokton SL2 58mm f/1.4 SL II',
#
    '07 3E 30 43 2D 35 03 00' => 'Soligor AF Zoom 19-35mm 1:3.5-4.5',
    '03 43 5C 81 35 35 02 00' => 'Soligor AF C/D Zoom UMCS 70-210mm 1:4.5',
#
    '12 36 5C 81 35 3D 09 00' => 'Cosina AF Zoom 70-210mm f/4.5-5.6 MC Macro',
    '06 3F 68 68 2C 2C 06 00' => 'Cosina 100mm f/3.5 Macro',
#
    '2F 40 30 44 2C 34 29 02' => 'Unknown 20-35mm f/3.5-4.5D',
    '1E 5D 64 64 20 20 13 00' => 'Unknown 90mm f/2.5',
    '12 3B 68 8D 3D 43 09 02' => 'Unknown 100-290mm f/5.6-6.7',
    '00 00 00 00 00 00 00 01' => 'Manual Lens No CPU',
);

my %retouchValues = (
    0 => 'None',
    3 => 'B & W',
    4 => 'Sepia',
    5 => 'Trim',
    6 => 'Small Picture',
    7 => 'D-Lighting',
    8 => 'Red Eye',
    9 => 'Cyanotype',
    10 => 'Sky Light',
    11 => 'Warm Tone',
    12 => 'Color Custom',
    13 => 'Image Overlay',
);

# Nikon maker note tags
%Image::ExifTool::Nikon::Main = (
    PROCESS_PROC => \&Image::ExifTool::Nikon::ProcessNikon,
    WRITE_PROC => \&Image::ExifTool::Nikon::ProcessNikon,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PRINT_CONV => 'Image::ExifTool::Nikon::FormatString($val)',
    0x0001 => { #2
        # the format differs for different models.  for D70, this is a string '0210',
        # but for the E775 it is binary: "\x00\x01\x00\x00"
        Name => 'MakerNoteVersion',
        Writable => 'undef',
        Count => 4,
        # convert to string if binary
        ValueConv => '$_=$val; /^[\x00-\x09]/ and $_=join("",unpack("CCCC",$_)); $_',
        ValueConvInv => '$val',
        PrintConv => '$_=$val;s/^(\d{2})/$1\./;s/^0//;$_',
        PrintConvInv => '$_=$val;s/\.//;"0$_"',
    },
    0x0002 => {
        # this is the ISO actually used by the camera
        # (may be different than ISO setting if auto)
        Name => 'ISO',
        Writable => 'int16u',
        Count => 2,
        Priority => 0,  # the EXIF ISO is more reliable
        Groups => { 2 => 'Image' },
        # D300 sets this to undef with 4 zero bytes when LO ISO is used - PH
        RawConv => '$val eq "\0\0\0\0" ? undef : $val',
        # first number is 1 for "Hi ISO" modes (H0.3, H0.7 and H1.0 on D80) - PH
        PrintConv => '$_=$val;s/^0 //;s/^1 (\d+)/Hi $1/;$_',
        PrintConvInv => '$_=$val;/^\d+/ ? "0 $_" : (s/Hi ?//i ? "1 $_" : $_)',
    },
    0x0003 => { Name => 'ColorMode',    Writable => 'string' },
    0x0004 => { Name => 'Quality',      Writable => 'string' },
    0x0005 => { Name => 'WhiteBalance', Writable => 'string' },
    0x0006 => { Name => 'Sharpness',    Writable => 'string' },
    0x0007 => { Name => 'FocusMode',    Writable => 'string' },
    0x0008 => { Name => 'FlashSetting', Writable => 'string' },
    # FlashType shows 'Built-in,TTL' when builtin flash fires,
    # and 'Optional,TTL' when external flash is used (ref 2)
    0x0009 => { #2
        Name => 'FlashType',
        Writable => 'string',
        Count => 13,
    },
    # 0x000a - rational values: 5.6 to 9.283 - found in coolpix models - PH
    #          (not correlated with any LV or scale factor)
    0x000b => { Name => 'WhiteBalanceFineTune', Writable => 'int16s' }, #2
    0x000c => {
        Name => 'ColorBalance1',
        Writable => 'rational64u',
        Count => 4,
    },
    0x000d => { #15
        Name => 'ProgramShift',
        Writable => 'undef',
        Count => 4,
        ValueConv => 'my ($a,$b,$c)=unpack("c3",$val); $c ? $a*($b/$c) : 0',
        ValueConvInv => q{
            my $a = int($val*6 + ($val>0 ? 0.5 : -0.5));
            $a<-128 or $a>127 ? undef : pack("c4",$a,1,6,0);
        },
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    0x000e => {
        Name => 'ExposureDifference',
        Writable => 'undef',
        Count => 4,
        ValueConv => 'my ($a,$b,$c)=unpack("c3",$val); $c ? $a*($b/$c) : 0',
        ValueConvInv => q{
            my $a = int($val*12 + ($val>0 ? 0.5 : -0.5));
            $a<-128 or $a>127 ? undef : pack("c4",$a,1,12,0);
        },
        PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
        PrintConvInv => '$val',
    },
    0x000f => { Name => 'ISOSelection', Writable => 'string' }, #2
    0x0010 => {
        Name => 'DataDump',
        Writable => 0,
        Binary => 1,
    },
    0x0011 => {
        Name => 'NikonPreview',
        Groups => { 1 => 'NikonPreview', 2 => 'Image' },
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::PreviewImage',
            Start => '$val',
        },
    },
    0x0012 => { #2
        Name => 'FlashExposureComp',
        Description => 'Flash Exposure Compensation',
        Writable => 'undef',
        Count => 4,
        Notes => 'may be set even if flash does not fire',
        ValueConv => 'my ($a,$b,$c)=unpack("c3",$val); $c ? $a*($b/$c) : 0',
        ValueConvInv => q{
            my $a = int($val*6 + ($val>0 ? 0.5 : -0.5));
            $a<-128 or $a>127 ? undef : pack("c4",$a,1,6,0);
        },
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    # D70 - another ISO tag
    0x0013 => { #2
        Name => 'ISOSetting',
        Writable => 'int16u',
        Count => 2,
        PrintConv => '$_=$val;s/^0 //;$_',
        PrintConvInv => '"0 $val"',
    },
    # D70 Image boundary?? top x,y bot-right x,y
    0x0016 => { #2
        Name => 'ImageBoundary',
        Writable => 'int16u',
        Count => 4,
    },
    # 0x0017 - 00 01 06 00 (D2Hs,D2X,D2Xs,D40,D40X,D50,D70,D70s,D80,D200,D300,D3) - PH
    #          fe 01 06 00 (D2X) - PH
    0x0018 => { #5
        Name => 'FlashExposureBracketValue',
        Writable => 'undef',
        Count => 4,
        ValueConv => 'my ($a,$b,$c)=unpack("c3",$val); $c ? $a*($b/$c) : 0',
        ValueConvInv => q{
            my $a = int($val*6 + ($val>0 ? 0.5 : -0.5));
            $a<-128 or $a>127 ? undef : pack("c4",$a,1,6,0);
        },
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    0x0019 => { #5
        Name => 'ExposureBracketValue',
        Writable => 'rational64s',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => 'eval $val',
    },
    0x001a => { #PH
        Name => 'ImageProcessing',
        Writable => 'string',
    },
    0x001b => { #15
        Name => 'CropHiSpeed',
        Writable => 'int16u',
        Count => 7,
        PrintConv => q{
            my @a = split ' ', $val;
            return "Unknown ($val)" unless @a == 7;
            $a[0] = $a[0] ? "On" : "Off";
            return "$a[0] ($a[1]x$a[2] cropped to $a[3]x$a[4] at pixel $a[5],$a[6])";
        }
    },
    # 0x001c - 00 01 06 (D2Hs,D2X,D2Xs,D200,D3,D300) - PH
    0x001d => { #4
        Name => 'SerialNumber',
        Writable => 0,
        Notes => 'not writable because this value is used as a key to decrypt other information',
    },
    0x001e => { #14
        Name => 'ColorSpace',
        Writable => 'int16u',
        PrintConv => {
            1 => 'sRGB',
            2 => 'Adobe RGB',
        },
    },
    0x001f => { #PH
        Name => 'VRInfo',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::VRInfo' },
    },
    0x0020 => { #16
        Name => 'ImageAuthentication',
        Writable => 'int8u',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x0022 => { #21
        Name => 'ActiveD-Lighting',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'Low',
            3 => 'Normal',
            5 => 'High',
        },
    },
    0x0023 => { #PH
        Name => 'PictureControl',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::PictureControl' },
    },
    0x0024 => { #JD
        Name => 'WorldTime',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::WorldTime',
            # (CaptureNX does flip the byte order of this record)
        },
    },        
    0x0025 => { #PH
        Name => 'ISOInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::ISOInfo',
            ByteOrder => 'BigEndian', #(NC)
        },
    },
    0x002a => { #23 (this tag added with D3 firmware 1.10 -- also written by Nikon utilities)
        Name => 'VignetteControl',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'Low',
            3 => 'Normal',
            5 => 'High',
        },
    },
    0x0080 => { Name => 'ImageAdjustment',  Writable => 'string' },
    0x0081 => { Name => 'ToneComp',         Writable => 'string' }, #2
    0x0082 => { Name => 'AuxiliaryLens',    Writable => 'string' },
    0x0083 => {
        Name => 'LensType',
        Writable => 'int8u',
        # credit to Tom Christiansen (ref 7) for figuring this out...
        PrintConv => q[$_ = $val ? Image::ExifTool::DecodeBits($val,
            {
                0 => 'MF',
                1 => 'D',
                2 => 'G',
                3 => 'VR',
            }) : 'AF';
            # remove commas and change "D G" to just "G"
            s/,//g; s/\bD G\b/G/; $_
        ],
        PrintConvInv => q[
            my $bits = 0;
            $bits |= 0x01 if $val =~ /\bMF\b/i;
            $bits |= 0x02 if $val =~ /\bD\b/i;
            $bits |= 0x06 if $val =~ /\bG\b/i;
            $bits |= 0x08 if $val =~ /\bVR\b/i;
            return $bits;
        ],
    },
    0x0084 => { #2
        Name => "Lens",
        Writable => 'rational64u',
        Count => 4,
        # short focal, long focal, aperture at short focal, aperture at long focal
        PrintConv => q{
            $val =~ tr/,/./;    # in case locale is whacky
            my ($a,$b,$c,$d) = split ' ', $val;
            ($a==$b ? $a : "$a-$b") . "mm f/" . ($c==$d ? $c : "$c-$d")
        },
        PrintConvInv => '$_=$val; tr/a-z\///d; s/(^|\s)([0-9.]+)(?=\s|$)/$1$2-$2/g; s/-/ /g; $_',
    },
    0x0085 => {
        Name => 'ManualFocusDistance',
        Writable => 'rational64u',
    },
    0x0086 => {
        Name => 'DigitalZoom',
        Writable => 'rational64u',
    },
    0x0087 => { #5
        Name => 'FlashMode',
        Writable => 'int8u',
        PrintConv => {
            0 => 'Did Not Fire',
            1 => 'Fired, Manual', #14
            7 => 'Fired, External', #14
            8 => 'Fired, Commander Mode',
            9 => 'Fired, TTL Mode',
        },
    },
    0x0088 => [
        {
            Name => 'AFInfo',
            Condition => '$$self{Model} =~ /^NIKON D/i',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::AFInfo',
                ByteOrder => 'BigEndian',
            },
        },
        {
            Name => 'AFInfo',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::AFInfo',
                ByteOrder => 'LittleEndian',
            },
        },
    ],
    0x0089 => { #5
        Name => 'ShootingMode',
        Writable => 'int16u',
        # the meaning of bit 5 seems to change:  For the D200 it indicates "Auto ISO" - PH
        Notes => 'for the D70, Bit 5 = Unused LE-NR Slowdown',
        # credit to Tom Christiansen (ref 7) for figuring this out...
        # The (new?) bit 5 seriously complicates our life here: after firmwareB's
        # 1.03, bit 5 turns on when you ask for BUT DO NOT USE the long-range
        # noise reduction feature, probably because even not using it, it still
        # slows down your drive operation to 50% (1.5fps max not 3fps).  But no
        # longer does !$val alone indicate single-frame operation. - TC, D70
        PrintConv => q[
            $_ = '';
            unless ($val & 0x87) {
                return 'Single-Frame' unless $val;
                $_ = 'Single-Frame, ';
            }
            return $_ . Image::ExifTool::DecodeBits($val,
            {
                0 => 'Continuous',
                1 => 'Delay',
                2 => 'PC Control',
                4 => 'Exposure Bracketing',
                5 => $$self{Model}=~/D70\b/ ? 'Unused LE-NR Slowdown' : 'Auto ISO',
                6 => 'White-Balance Bracketing',
                7 => 'IR Control',
            });
        ],
    },
    0x008a => { #15
        Name => 'AutoBracketRelease',
        Writable => 'int16u',
        PrintConv => {
            0 => 'None',
            1 => 'Auto Release',
            2 => 'Manual Release',
            # have seen 255 (="n/a"?) - PH
        },
    },
    0x008b => { #8
        Name => 'LensFStops',
        ValueConv => 'my ($a,$b,$c)=unpack("C3",$val); $c ? $a*($b/$c) : 0',
        ValueConvInv => 'my $a=int($val*12+0.5);$a<256 ? pack("C4",$a,1,12,0) : undef',
        PrintConv => 'sprintf("%.2f", $val)',
        PrintConvInv => '$val',
        Writable => 'undef',
        Count => 4,
    },
    0x008c => {
        Name => 'ContrastCurve', #JD
        Writable => 0,
        Binary => 1,
    },
    0x008d => { Name => 'ColorHue' ,        Writable => 'string' }, #2
    # SceneMode takes on the following values: PORTRAIT, PARTY/INDOOR, NIGHT PORTRAIT,
    # BEACH/SNOW, LANDSCAPE, SUNSET, NIGHT SCENE, MUSEUM, FIREWORKS, CLOSE UP, COPY,
    # BACK LIGHT, PANORAMA ASSIST, SPORT, DAWN/DUSK
    0x008f => { Name => 'SceneMode',        Writable => 'string' }, #2
    # LightSource shows 3 values COLORED SPEEDLIGHT NATURAL.
    # (SPEEDLIGHT when flash goes. Have no idea about difference between other two.)
    0x0090 => { Name => 'LightSource',      Writable => 'string' }, #2
    0x0091 => [ #18
        {
            Condition => '$$valPt =~ /^0208/',
            Name => 'ShotInfoD80',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ShotInfoD80',
                DecryptStart => 4,
                DecryptLen => 764,
                # (Capture NX can change the makernote byte order, but this stays big-endian)
                ByteOrder => 'BigEndian',
            },
        },
        { #PH
            Condition => '$$valPt =~ /^0209/',
            Name => 'ShotInfoD40',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ShotInfoD40',
                DecryptStart => 4,
                DecryptLen => 748,
                ByteOrder => 'BigEndian',
            },
        },
        { #JD (D300)
            # D3 and D300 use the same version number, but the length is different
            Condition => '$$valPt =~ /^0210/ and $count == 5291',
            Name => 'ShotInfoD300',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ShotInfoD300',
                DecryptStart => 4,
                DecryptLen => 813,
                ByteOrder => 'BigEndian',
            },
        },
        {
            Condition => '$$valPt =~ /^02/',
            Name => 'ShotInfo02xx',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ShotInfo',
                ProcessProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                WriteProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                DecryptStart => 4,
                DecryptLen => 0x279,
                ByteOrder => 'BigEndian',
            },
        },
        {
            Name => 'ShotInfoUnknown',
            Writable => 0,
            Unknown => 1, # no tags known so don't process unless necessary
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ShotInfo',
                DirOffset => 4,
                ByteOrder => 'BigEndian',
            },
        },
    ],
    0x0092 => { #2
        Name => 'HueAdjustment',
        Writable => 'int16s',
    },
    # 0x0093 - ref 15 calls this Saturation, but this is wrong - PH
    0x0093 => { #21
        Name => 'NEFCompression',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Lossy (type 1)', # (older models)
            2 => 'Uncompressed', #JD - D100 (even though TIFF compression is set!)
            3 => 'Lossless',
            4 => 'Lossy (type 2)',
        },
    },
    0x0094 => { Name => 'Saturation',       Writable => 'int16s' },
    0x0095 => { Name => 'NoiseReduction',   Writable => 'string' },
    0x0096 => {
        Name => 'LinearizationTable', # same table as DNG LinearizationTable (ref JD)
        Writable => 0,
        Binary => 1,
    },
    0x0097 => [ #4
        # (NOTE: these are byte-swapped by NX when byte order changes)
        {
            Condition => '$$valPt =~ /^0100/', # (D100)
            Name => 'ColorBalance0100',
            SubDirectory => {
                Start => '$valuePtr + 72',
                TagTable => 'Image::ExifTool::Nikon::ColorBalance1',
            },
        },
        {
            Condition => '$$valPt =~ /^0102/', # (D2H)
            Name => 'ColorBalance0102',
            SubDirectory => {
                Start => '$valuePtr + 10',
                TagTable => 'Image::ExifTool::Nikon::ColorBalance2',
            },
        },
        {
            Condition => '$$valPt =~ /^0103/', # (D70)
            Name => 'ColorBalance0103',
            # D70:  at file offset 'tag-value + base + 20', 4 16 bits numbers,
            # v[0]/v[1] , v[2]/v[3] are the red/blue multipliers.
            SubDirectory => {
                Start => '$valuePtr + 20',
                TagTable => 'Image::ExifTool::Nikon::ColorBalance3',
            },
        },
        {
            Condition => '$$valPt =~ /^0205/', # (D50)
            Name => 'ColorBalance0205',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ColorBalance2',
                ProcessProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                WriteProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                DecryptStart => 4,
                DecryptLen => 22, # 284 bytes encrypted, but don't need to decrypt it all
                DirOffset => 14,
            },
        },
        {
            Condition => '$$valPt =~ /^0209/', # (D3)
            Name => 'ColorBalance0209',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ColorBalance4',
                ProcessProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                WriteProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                DecryptStart => 284,
                DecryptLen => 18, # but don't need to decrypt it all
                DirOffset => 10,
            },
        },
        {
            Condition => '$$valPt =~ /^02/', # (D2X=0204,D2Hs=0206,D200=0207,D40=0208)
            Name => 'ColorBalance02',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::ColorBalance2',
                ProcessProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                WriteProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                DecryptStart => 284,
                DecryptLen => 14, # 324 bytes encrypted, but don't need to decrypt it all
                DirOffset => 6,
            },
        },
        {
            Name => 'ColorBalanceUnknown',
            Writable => 0,
        },
    ],
    0x0098 => [
        { #8
            Condition => '$$valPt =~ /^0100/', # D100, D1X - PH
            Name => 'LensData0100',
            SubDirectory => { TagTable => 'Image::ExifTool::Nikon::LensData00' },
        },
        { #8
            Condition => '$$valPt =~ /^0101/', # D70, D70s - PH
            Name => 'LensData0101',
            SubDirectory => { TagTable => 'Image::ExifTool::Nikon::LensData01' },
        },
        # note: this information is encrypted if the version is 02xx
        { #8
            # 0201 - D200, D2Hs, D2X and D2Xs
            # 0202 - D40, D40X and D80
            # 0203 - D300
            Condition => '$$valPt =~ /^020[1-3]/',
            Name => 'LensData0201',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::LensData01',
                ProcessProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                WriteProc => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
                DecryptStart => 4,
            },
        },
        {
            Name => 'LensDataUnknown',
            Writable => 0,
        },
    ],
    0x0099 => { #2/15
        Name => 'RawImageCenter',
        Writable => 'int16u',
        Count => 2,
    },
    0x009a => { #10
        Name => 'SensorPixelSize',
        Writable => 'rational64u',
        Count => 2,
        PrintConv => '$val=~s/ / x /;"$val um"',
        PrintConvInv => '$val=~tr/a-zA-Z/ /;$val',
    },
    0x009c => { #14
        # L2/L3 has these modes (from owner's manual): - PH
        # Portrait Assist: FACE-PRIORITY AF,PORTRAIT,PORTRAIT LEFT,PORTRAIT RIGHT,
        #                  PORTRAIT CLOSE-UP,PORTRAIT COUPLE,PORTRAIT-FIGURE
        # Landscape Assist:LANDSCAPE,SCENIC VIEW,ARCHITECTURE,GROUP RIGHT,GROUP LEFT
        # Sports Assist:   SPORTS,SPORT SPECTATOR,SPORT COMPOSITE
        Name => 'SceneAssist',
        Writable => 'string',
    },
    0x009e => { #JD
        Name => 'RetouchHistory',
        Writable => 'int16u',
        Count => 10,
        # trim off extra "None" values
        ValueConv => '$val=~s/( 0)+$//; $val',
        ValueConvInv => 'my $n=($val=~/ \d+/g);$n < 9 ? $val . " 0" x (9-$n) : $val',
        PrintConv => [
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
            \%retouchValues,
        ],
    },
    0x00a0 => { Name => 'SerialNumber',     Writable => 'string' }, #2
    0x00a2 => { # size of compressed image data plus EOI segment (ref 10)
        Name => 'ImageDataSize',
        Writable => 'int32u',
    },
    # 0x00a3 - int8u, values: 0 (All DSLR's but D1,D1H,D1X,D100)
    # 0x00a4 - version number found only in NEF images from DSLR models except the
    # D1,D1X,D2H and D100.  Value is "0200" for all available samples except images
    # edited by Nikon Capture Editor 4.3.1 W and 4.4.2 which have "0100" - PH
    0x00a5 => { #15
        Name => 'ImageCount',
        Writable => 'int32u',
    },
    0x00a6 => { #15
        Name => 'DeletedImageCount',
        Writable => 'int32u',
    },
    # the sum of 0xa5 and 0xa6 is equal to 0xa7 ShutterCount (D2X,D2Hs,D2H,D200, ref 10)
    0x00a7 => { # Number of shots taken by camera so far (ref 2)
        Name => 'ShutterCount',
        Writable => 0,
        Notes => 'not writable because this value is used as a key to decrypt other information',
    },
    0x00a8 => [#JD
        {
            Name => 'FlashInfo0100',
            Condition => '$$valPt =~ /^010[01]/',
            SubDirectory => { TagTable => 'Image::ExifTool::Nikon::FlashInfo0100' },
        },
        {
            Name => 'FlashInfo0102',
            Condition => '$$valPt =~ /^0102/',
            SubDirectory => { TagTable => 'Image::ExifTool::Nikon::FlashInfo0102' },
        },
        {
            Name => 'FlashInfoUnknown',
            SubDirectory => { TagTable => 'Image::ExifTool::Nikon::FlashInfoUnknown' },
        },
    ],
    0x00a9 => { #2
        Name => 'ImageOptimization',
        Writable => 'string',
        Count => 16,
    },
    0x00aa => { Name => 'Saturation',       Writable => 'string' }, #2
    0x00ab => { Name => 'VariProgram',      Writable => 'string' }, #2
    0x00ac => { Name => 'ImageStabilization',Writable=> 'string' }, #14
    0x00ad => { Name => 'AFResponse',       Writable => 'string' }, #14
    0x00b0 => { #PH
        Name => 'MultiExposure',
        Condition => '$$valPt =~ /^0100/',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::MultiExposure' },
    },
    0x00b1 => { #14/PH/JD (D80)
        Name => 'HighISONoiseReduction',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'Minimal', # for high ISO (>800) when setting is "Off"
            2 => 'Low',     # Low,Normal,High take effect for ISO > 400
            4 => 'Normal',
            6 => 'High',
        },
    },
    # 0x00b2 (string: 'Normal', 0xc3's, 0xff's or 0x20's)
    0x00b3 => { #14
        Name => 'ToningEffect',
        Writable => 'string',
    },
    0x00b7 => { #JD
        Name => 'AFInfo2',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::AFInfo2' },
    },
    0x00b8 => { #PH
        Name => 'FileInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::FileInfo',
            ByteOrder => 'BigEndian',
        },
    },
    0x00b9 => {
        Name => 'Nikon_0x00b9',
        Description => 'Nikon 0x00b9',
        Unknown => 1,
        PrintConv => '"0x" . unpack("H*", $val)',
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        Writable => 0,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
    # 0x0e01 - In D70 NEF files produced by Nikon Capture, the data for this tag extends 4 bytes
    # past the end of the maker notes.  Very odd.  I hope these 4 bytes aren't useful because
    # they will get lost by any utility that blindly copies the maker notes (not ExifTool) - PH
    0x0e01 => {
        Name => 'NikonCaptureData',
        SubDirectory => {
            TagTable => 'Image::ExifTool::NikonCapture::Main',
        },
    },
    # 0x0e05 written by Nikon Capture to NEF files, values of 1 and 2 - PH
    0x0e09 => { #12
        Name => 'NikonCaptureVersion',
        Writable => 'string',
    },
    # 0x0e0e is in D70 Nikon Capture files (not out-of-the-camera D70 files) - PH
    0x0e0e => { #PH
        Name => 'NikonCaptureOffsets',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::CaptureOffsets',
            Validate => '$val =~ /^0100/',
            Start => '$valuePtr + 4',
        },
    },
    0x0e10 => { #17
        Name => 'NikonScanIFD',
        Groups => { 1 => 'NikonScan', 2 => 'Image' },
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Nikon::Scan',
            Start => '$val',
        },
    },
    # 0x0e13 - some sort of edit history written by Nikon Capture
    0x0e1d => { #JD
        Name => 'NikonICCProfile',
        Binary => 1,
        Protected => 1,
        Writable => 'undef', # must be defined here so tag will be extracted if specified
        WriteCheck => q{
            require Image::ExifTool::ICC_Profile;
            return Image::ExifTool::ICC_Profile::ValidateICC(\$val);
        },
        SubDirectory => {
            DirName => 'NikonICCProfile',
            TagTable => 'Image::ExifTool::ICC_Profile::Main',
        },
    },
);

# NikonScan IFD entries (ref 17)
%Image::ExifTool::Nikon::Scan = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITE_GROUP => 'NikonScan',
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 1 => 'NikonScan', 2 => 'Image' },
    VARS => { MINOR_ERRORS => 1 }, # this IFD is non-essential and often corrupted
    NOTES => 'This information is written by the Nikon Scan software.',
    0x02 => { Name => 'FilmType',    Writable => 'string', },
    0x40 => { Name => 'MultiSample', Writable => 'string' },
    0x41 => { Name => 'BitDepth',    Writable => 'int16u' },
    0x50 => {
        Name => 'MasterGain',
        Writable => 'rational64s',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val',
    },
    0x51 => {
        Name => 'ColorGain',
        Writable => 'rational64s',
        Count => 3,
        PrintConv => 'sprintf("%.2f %.2f %.2f",split(" ",$val))',
        PrintConvInv => '$val',
    },
    0x100 => { Name => 'DigitalICE', Writable => 'string' },
    0x110 => {
        Name => 'ROCInfo',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::ROC' },
    },
    0x120 => {
        Name => 'GEMInfo',
        SubDirectory => { TagTable => 'Image::ExifTool::Nikon::GEM' },
    },
);

# ref 17
%Image::ExifTool::Nikon::ROC = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    FORMAT => 'int32u',
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 1 => 'NikonScan', 2 => 'Image' },
    0 => {
        Name => 'DigitalROC',
        ValueConv => '$val / 10',
        ValueConvInv => 'int($val * 10)',
    },
);

# ref 17
%Image::ExifTool::Nikon::GEM = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    FORMAT => 'int32u',
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 1 => 'NikonScan', 2 => 'Image' },
    0 => {
        Name => 'DigitalGEM',
        ValueConv => '$val<95 ? $val/20-1 : 4',
        ValueConvInv => '$val == 4 ? 95 : int(($val + 1) * 20)',
    },
);

# Vibration Reduction information - PH (D300)
%Image::ExifTool::Nikon::VRInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'VRInfoVersion',
        Format => 'undef[4]',
        Writable => 0,
    },
    4 => {
        Name => 'VibrationReduction',
        PrintConv => {
            1 => 'On',
            2 => 'Off',
        },
    },
    # 5 - values: 0, 1, 2
    # 6 and 7 - values: 0
);

# Picture Control information - PH (D300)
%Image::ExifTool::Nikon::PictureControl = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'PictureControlVersion',
        Format => 'undef[4]',
        Writable => 0,
    },
    4 => {
        Name => 'PictureControlName',
        Format => 'string[20]',
        # make lower case with a leading capital for each word
        PrintConv => '$_=lc($val);s/\b(\w)/\U$1/g;$_',
        PrintConvInv => 'uc($val)',
    },
    24 => {
        Name => 'PictureControlBase',
        Format => 'string[20]',
        # make lower case with a leading capital for each word
        PrintConv => '$_=lc($val);s/\b(\w)/\U$1/g;$_',
        PrintConvInv => 'uc($val)',
    },
    # beginning at byte 44, there is some interesting information.
    # here are the observed bytes for each PictureControlMode:
    #            44 45 46 47 48 49 50 51 52 53 54 55 56 57
    # STANDARD   00 01 00 00 00 80 83 80 80 80 80 ff ff ff
    # NEUTRAL    03 c2 00 00 00 ff 82 80 80 80 80 ff ff ff
    # VIVID      00 c3 00 00 00 80 84 80 80 80 80 ff ff ff
    # MONOCHROME 06 4d 00 01 02 ff 82 80 80 ff ff 80 80 ff
    # Neutral2   03 c2 01 00 02 ff 80 7f 81 00 7f ff ff ff (custom)
    # (note that up to 9 different custom picture controls can be stored)
    #
    48 => { #21
        Name => 'PictureControlAdjust',
        PrintConv => {
            0 => 'Default Settings',
            1 => 'Quick Adjust',
            2 => 'Full Control',
        },
    },
    49 => {
        Name => 'PictureControlQuickAdjust',
        # settings: -2 to +2 (n/a for Neutral and Monochrome modes)
        DelValue => 0xff,
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val)',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    50 => {
        Name => 'Sharpness',
        # settings: 0 to 9, Auto
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val,"No Sharpening","%d")',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    51 => {
        Name => 'Contrast',
        # settings: -3 to +3, Auto
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val)',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    52 => {
        Name => 'Brightness',
        # settings: -1 to +1
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val)',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    53 => {
        Name => 'Saturation',
        # settings: -3 to +3, Auto (n/a for Monochrome mode)
        DelValue => 0xff,
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val)',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    54 => {
        Name => 'HueAdjustment',
        # settings: -3 to +3 (n/a for Monochrome mode)
        DelValue => 0xff,
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => 'Image::ExifTool::Nikon::PrintPC($val,"None")',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
    55 => {
        Name => 'FilterEffect',
        # settings: Off,Yellow,Orange,Red,Green (n/a for color modes)
        DelValue => 0xff,
        PrintHex => 1,
        PrintConv => {
            0x80 => 'Off',
            0x81 => 'Yellow',
            0x82 => 'Orange',
            0x83 => 'Red',
            0x84 => 'Green',
            0xff => 'n/a',
        },
    },
    56 => {
        Name => 'ToningEffect',
        # settings: B&W,Sepia,Cyanotype,Red,Yellow,Green,Blue-Green,Blue,
        #           Purple-Blue,Red-Purple (n/a for color modes)
        DelValue => 0xff,
        PrintHex => 1,
        PrintConv => {
            0x80 => 'B&W',
            0x81 => 'Sepia',
            0x82 => 'Cyanotype',
            0x83 => 'Red',
            0x84 => 'Yellow',
            0x85 => 'Green',
            0x86 => 'Blue-green',
            0x87 => 'Blue',
            0x88 => 'Purple-blue',
            0x89 => 'Red-purple',
            0xff => 'n/a',
        },
    },
    57 => { #21
        Name => 'ToningSaturation',
        # settings: B&W,Sepia,Cyanotype,Red,Yellow,Green,Blue-Green,Blue,
        #           Purple-Blue,Red-Purple (n/a unless ToningEffect is used)
        DelValue => 0xff,
        ValueConv => '$val - 0x80',
        ValueConvInv => '$val + 0x80',
        PrintConv => '$val==0x7f ? "n/a" : $val',
        PrintConvInv => 'Image::ExifTool::Nikon::PrintPCInv($val)',
    },
);

# World Time information - JD (D300)
%Image::ExifTool::Nikon::WorldTime = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Time' },
    0 => {
        Name => 'Timezone',
        Format => 'int16s',
        PrintConv => q{
            my $sign = $val < 0 ? '-' : '+';
            my $h = int(abs($val) / 60);
            sprintf("%s%.2d:%.2d", $sign, $h, abs($val)-60*$h);
        },
        PrintConvInv => q{
            $val =~ /([-+]?)(\d+):(\d+)/ or return undef;
            return $1 . ($2 * 60 + $3);
        },
    },
    2 => {
        Name => 'DaylightSavings',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    3 => {
        Name => 'DateFormat',
        PrintConv => {
            0 => 'Y/M/D',
            1 => 'M/D/Y',
            2 => 'D/M/Y',
        },
    },
);

# ISO information - PH (D300)
%Image::ExifTool::Nikon::ISOInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'ISO',
        Notes => 'val = 100 * 2**(raw/12-5)',
        Priority => 0, # because people like to see rounded-off values if they exist
        ValueConv => '100*exp(($val/12-5)*log(2))',
        ValueConvInv => '(log($val/100)/log(2)+5)*12',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    # 1 - 0x01
    # 2 - 0x0c (probably the ISO divisor above)
    # 3 - 0x00
    4 => {
        Name => 'ISOExpansion',
        Format => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x000 => 'Off',
            0x101 => 'Hi 0.3',
            0x102 => 'Hi 0.5',
            0x103 => 'Hi 0.7',
            0x104 => 'Hi 1.0',
            0x105 => 'Hi 1.3', # (Hi 1.3-1.7 may be possible with future models)
            0x106 => 'Hi 1.5',
            0x107 => 'Hi 1.7',
            0x108 => 'Hi 2.0', #(NC) - D3 should have this mode
            0x201 => 'Lo 0.3',
            0x202 => 'Lo 0.5',
            0x203 => 'Lo 0.7',
            0x204 => 'Lo 1.0',
        },
    },
    # bytes 6-11 same as 0-4 in my samples (why is this duplicated?)
    6 => {
        Name => 'ISO2',
        Notes => 'val = 100 * 2**(raw/12-5)',
        ValueConv => '100*exp(($val/12-5)*log(2))',
        ValueConvInv => '(log($val/100)/log(2)+5)*12',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    # 7 - 0x01
    # 8 - 0x0c (probably the ISO divisor above)
    # 9 - 0x00
    10 => {
        Name => 'ISOExpansion2',
        Format => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x000 => 'Off',
            0x101 => 'Hi 0.3',
            0x102 => 'Hi 0.5',
            0x103 => 'Hi 0.7',
            0x104 => 'Hi 1.0',
            0x105 => 'Hi 1.3', # (Hi 1.3-1.7 may be possible with future models)
            0x106 => 'Hi 1.5',
            0x107 => 'Hi 1.7',
            0x108 => 'Hi 2.0', #(NC) - D3 should have this mode
            0x201 => 'Lo 0.3',
            0x202 => 'Lo 0.5',
            0x203 => 'Lo 0.7',
            0x204 => 'Lo 1.0',
        },
    },
    # bytes 12-13: 00 00
);

# Nikon AF information (ref 13)
%Image::ExifTool::Nikon::AFInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'AFAreaMode',
        PrintConv => {
            0 => 'Single Area',
            1 => 'Dynamic Area',
            2 => 'Dynamic Area, Closest Subject',
            3 => 'Group Dynamic',
            4 => 'Single Area (wide)',
            5 => 'Dynamic Area (wide)',
        },
    },
    1 => {
        Name => 'AFPoint',
        Notes => 'in some focus modes this value is not meaningful',
        PrintConv => {
            0 => 'Center',
            1 => 'Top',
            2 => 'Bottom',
            3 => 'Left',
            4 => 'Right',
            5 => 'Upper-left',
            6 => 'Upper-right',
            7 => 'Lower-left',
            8 => 'Lower-right',
            9 => 'Far Left',
            10 => 'Far Right',
        },
    },
    2 => {
        Name => 'AFPointsInFocus',
        Format => 'int16u',
        PrintConv => {
            BITMASK => {
                0 => 'Center',
                1 => 'Top',
                2 => 'Bottom',
                3 => 'Left',
                4 => 'Right',
                5 => 'Upper-left',
                6 => 'Upper-right',
                7 => 'Lower-left',
                8 => 'Lower-right',
                9 => 'Far Left',
                10 => 'Far Right',
            },
        },
    },
);

# Nikon AF information for D3 and D300 (ref JD)
%Image::ExifTool::Nikon::AFInfo2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'AFInfo2Version',
        Format => 'undef[4]',
        Writable => 0,
    },
    8 => {
        Name => 'AFPointsUsed',
        Format => 'undef[7]',
        Notes => 'D3/D300 AF points -- 5 rows: A1-9, B1-11, C1-11, D1-11, E1-9, center point is C6',
        PrintConv => 'Image::ExifTool::Nikon::PrintAFPointsD3($val)',
    },
);

# Nikon File information - D60, D3 and D300 (ref PH)
%Image::ExifTool::Nikon::FileInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    0 => {
        Name => 'FileInfoVersion',
        Format => 'undef[4]',
        Writable => 0,
    },
    6 => {
        Name => 'DirectoryNumber',
        Format => 'int16u',
        PrintConv => 'sprintf("%.3d", $val)',
        PrintConvInv => '$val',
    },
    8 => {
        Name => 'FileNumber',
        Format => 'int16u',
        PrintConv => 'sprintf("%.4d", $val)',
        PrintConvInv => '$val',
    },
);

# ref PH
%Image::ExifTool::Nikon::CaptureOffsets = (
    PROCESS_PROC => \&ProcessNikonCaptureOffsets,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    1 => 'IFD0_Offset',
    2 => 'PreviewIFD_Offset',
    3 => 'SubIFD_Offset',
);

# ref 4
%Image::ExifTool::Nikon::ColorBalance1 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'WB_RBGGLevels',
        Format => 'int16u[4]',
        Protected => 1,
    },
);

# ref 4
%Image::ExifTool::Nikon::ColorBalance2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'This information is encrypted for most camera models.',
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'WB_RGGBLevels',
        Format => 'int16u[4]',
        Protected => 1,
    },
);

# ref 4
%Image::ExifTool::Nikon::ColorBalance3 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'WB_RGBGLevels',
        Format => 'int16u[4]',
        Protected => 1,
    },
);

# ref 4
%Image::ExifTool::Nikon::ColorBalance4 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FORMAT => 'int16u',
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'WB_GRBGLevels',
        Format => 'int16u[4]',
        Protected => 1,
    },
);

%Image::ExifTool::Nikon::Type2 = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0003 => 'Quality',
    0x0004 => 'ColorMode',
    0x0005 => 'ImageAdjustment',
    0x0006 => 'CCDSensitivity',
    0x0007 => 'WhiteBalance',
    0x0008 => 'Focus',
    0x000A => 'DigitalZoom',
    0x000B => 'Converter',
);

# these are standard EXIF tags, but they are duplicated here so we
# can change some names to extract the Nikon preview separately
%Image::ExifTool::Nikon::PreviewImage = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 1 => 'NikonPreview', 2 => 'Image'},
    VARS => { MINOR_ERRORS => 1 }, # this IFD is non-essential and often corrupted
    0x103 => {
        Name => 'Compression',
        PrintConv => \%Image::ExifTool::Exif::compression,
        Priority => 0,
    },
    0x11a => {
        Name => 'XResolution',
        Priority => 0,
    },
    0x11b => {
        Name => 'YResolution',
        Priority => 0,
    },
    0x128 => {
        Name => 'ResolutionUnit',
        PrintConv => {
            1 => 'None',
            2 => 'inches',
            3 => 'cm',
        },
        Priority => 0,
    },
    0x201 => {
        Name => 'PreviewImageStart',
        Flags => [ 'IsOffset', 'Permanent' ],
        OffsetPair => 0x202, # point to associated byte count
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x202 => {
        Name => 'PreviewImageLength',
        Flags => 'Permanent' ,
        OffsetPair => 0x201, # point to associated offset
        DataTag => 'PreviewImage',
        Writable => 'int32u',
        Protected => 2,
    },
    0x213 => {
        Name => 'YCbCrPositioning',
        PrintConv => {
            1 => 'Centered',
            2 => 'Co-sited',
        },
        Priority => 0,
    },
);

# these are duplicated enough times to make it worthwhile to define them centrally
my %nikonApertureConversions = (
    ValueConv => '2**($val/24)',
    ValueConvInv => '$val>0 ? 24*log($val)/log(2) : 0',
    PrintConv => 'sprintf("%.1f",$val)',
    PrintConvInv => '$val',
);

my %nikonFocalConversions = (
    ValueConv => '5 * 2**($val/24)',
    ValueConvInv => '$val>0 ? 24*log($val/5)/log(2) : 0',
    PrintConv => 'sprintf("%.1f mm",$val)',
    PrintConvInv => '$val=~s/\s*mm$//;$val',
);

# Version 100 Nikon lens data
%Image::ExifTool::Nikon::LensData00 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => 'This structure is used by the D100, and D1X with firmware version 1.1.',
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0x00 => {
        Name => 'LensDataVersion',
        Format => 'undef[4]',
        Writable => 0,
    },
    0x06 => { #8
        Name => 'LensIDNumber',
        Notes => 'see LensID values below',
    },
    0x07 => { #8
        Name => 'LensFStops',
        ValueConv => '$val / 12',
        ValueConvInv => '$val * 12',
        PrintConv => 'sprintf("%.2f", $val)',
        PrintConvInv => '$val',
    },
    0x08 => { #8/9
        Name => 'MinFocalLength',
        %nikonFocalConversions,
    },
    0x09 => { #8/9
        Name => 'MaxFocalLength',
        %nikonFocalConversions,
    },
    0x0a => { #8
        Name => 'MaxApertureAtMinFocal',
        %nikonApertureConversions,
    },
    0x0b => { #8
        Name => 'MaxApertureAtMaxFocal',
        %nikonApertureConversions,
    },
    0x0c => 'MCUVersion', #8
);

# Nikon lens data (note: needs decrypting if LensDataVersion is 020x)
%Image::ExifTool::Nikon::LensData01 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => q{
        Nikon encrypts the LensData information below if LensDataVersion is 0201 or
        higher, but  the decryption algorithm is known so the information can be
        extracted.  It isn't yet writable, however, because the encryption adds
        complications which make writing more difficult.
    },
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0x00 => {
        Name => 'LensDataVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    0x04 => { #8
        Name => 'ExitPupilPosition',
        ValueConv => '$val ? 2048 / $val : $val',
        ValueConvInv => '$val ? 2048 / $val : $val',
        PrintConv => 'sprintf("%.1f mm",$val)',
        PrintConvInv => '$val=~s/\s*mm$//; $val',
    },
    0x05 => { #8
        Name => 'AFAperture',
        %nikonApertureConversions,
    },
    0x08 => { #8
        # this seems to be 2 values: the upper nibble gives the far focus
        # range and the lower nibble gives the near focus range.  The values
        # are in the range 1-N, where N is lens-dependent.  A value of 0 for
        # the far focus range indicates infinity. (ref JD)
        Name => 'FocusPosition',
        PrintConv => 'sprintf("0x%02x", $val)',
        PrintConvInv => '$val',
    },
    0x09 => { #8/9
        # With older AF lenses this does not work... (ref 13)
        # ie) AF Nikkor 50mm f/1.4 => 48 (0x30)
        # AF Zoom-Nikkor 35-105mm f/3.5-4.5 => @35mm => 15 (0x0f), @105mm => 141 (0x8d)
        Notes => 'this focus distance is approximate, and not very accurate for some lenses',
        Name => 'FocusDistance',
        ValueConv => '0.01 * 10**($val/40)', # in m
        ValueConvInv => '$val>0 ? 40*log($val*100)/log(10) : 0',
        PrintConv => '$val ? sprintf("%.2f m",$val) : "inf"',
        PrintConvInv => '$val eq "inf" ? 0 : $val =~ s/\s*m$//, $val',
    },
    0x0a => { #8/9
        Name => 'FocalLength',
        Priority => 0,
        %nikonFocalConversions,
    },
    0x0b => { #8
        Name => 'LensIDNumber',
        Notes => 'see LensID values below',
    },
    0x0c => { #8
        Name => 'LensFStops',
        ValueConv => '$val / 12',
        ValueConvInv => '$val * 12',
        PrintConv => 'sprintf("%.2f", $val)',
        PrintConvInv => '$val',
    },
    0x0d => { #8/9
        Name => 'MinFocalLength',
        %nikonFocalConversions,
    },
    0x0e => { #8/9
        Name => 'MaxFocalLength',
        %nikonFocalConversions,
    },
    0x0f => { #8
        Name => 'MaxApertureAtMinFocal',
        %nikonApertureConversions,
    },
    0x10 => { #8
        Name => 'MaxApertureAtMaxFocal',
        %nikonApertureConversions,
    },
    0x11 => 'MCUVersion', #8
    0x12 => { #8
        Name => 'EffectiveMaxAperture',
        %nikonApertureConversions,
    },
);

# shot information (encrypted in some cameras) - ref 18
%Image::ExifTool::Nikon::ShotInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    DATAMEMBER => [ 0 ],
    NOTES => q{
        This information is encrypted for ShotInfoVersion 02xx, and some tags are
        only valid for specific models.
    },
    0x00 => {
        Name => 'ShotInfoVersion',
        RawConv => '$$self{ShotInfoVersion} = $val',
        Format => 'string[4]',
        Writable => 0,
    },
    0x66 => {
        Name => 'VR_0x66',
        Condition => '$$self{ShotInfoVersion} =~ /^(0204)$/',
        Format => 'int8u',
        Unknown => 1,
        Notes => 'D2X, D2Xs (unverified)',
        PrintConv => {
            0 => 'Off',
            1 => 'On (normal)',
            2 => 'On (active)',
        },
    },
    # 6a, 6e not correct for 0103 (D70), 0207 (D200)
    0x6a => {
        Name => 'ShutterCount',
        Condition => '$$self{ShotInfoVersion} =~ /^(0204)$/',
        Format => 'int32u',
        Priority => 0,
        Notes => 'D2X, D2Xs',
    },
    0x6e => {
        Name => 'DeletedImageCount',
        Condition => '$$self{ShotInfoVersion} =~ /^(0204)$/',
        Format => 'int32u',
        Priority => 0,
        Notes => 'D2X, D2Xs',
    },
    0x75 => { #JD
        Name => 'VibrationReduction',
        Condition => '$$self{ShotInfoVersion} =~ /^(0207)$/',
        Format => 'int8u',
        Notes => 'D200',
        PrintConv => {
            0 => 'Off',
            # (not sure what the different values represent, but values
            # of 1 and 2 have even been observed for non-VR lenses!)
            1 => 'On (1)', #PH
            2 => 'On (2)', #PH
            3 => 'On (3)', #PH (rare -- only seen once)
        },
    },
    0x82 => { # educated guess, needs verification
        Name => 'VibrationReduction',
        Condition => '$$self{ShotInfoVersion} =~ /^(0204)$/',
        Format => 'int8u',
        Notes => 'D2X, D2Xs',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    0x157 => { #JD
        Name => 'ShutterCount',
        Condition => '$$self{ShotInfoVersion} =~ /^(0205)$/',
        Format => 'undef[2]',
        Priority => 0,
        Notes => 'D50',
        # treat as a 2-byte big-endian integer
        ValueConv => 'unpack("n", $val)',
        ValueConvInv => 'pack("n",$val)',
    },
    0x1ae => { #JD
        Name => 'VibrationReduction',
        Condition => '$$self{ShotInfoVersion} =~ /^(0205)$/',
        Format => 'int8u',
        Notes => 'D50',
        PrintHex => 1,
        PrintConv => {
            0x00 => 'n/a',
            0x0c => 'Off',
            0x0f => 'On',
        },
    },
    0x256 => { #JD (same value found at offset 0x26b)
        Name => 'ISO2',
        Condition => '$$self{Model} =~ /D3\b/', # ShotInfoVersion 0210
        Notes => 'D3',
        ValueConv => '100*exp(($val/12-5)*log(2))',
        ValueConvInv => '(log($val/100)/log(2)+5)*12',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    0x276 => { #JD
        Name => 'ShutterCount',
        Condition => '$$self{Model} =~ /D3\b/',
        Format => 'int32u',
        Priority => 0,
        Notes => 'D3',
    },
    # note: DecryptLen currently set to 0x279
);

# shot information for D80 (encrypted) - ref JD
%Image::ExifTool::Nikon::ShotInfoD80 = (
    PROCESS_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    WRITE_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    VARS => { ID_LABEL => 'Index' }, # change TagID label in documentation
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are extracted from encrypted data in D80 images.',
    0x00 => {
        Name => 'ShotInfoVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    586 => {
        Name => 'ShutterCount',
        Format => 'int32u',
        Priority => 0,
    },
    # split 590 into a few different tags
    590.1 => {
        Name => 'Rotation',
        Mask => 0x07,
        PrintConv => {
            0x00 => 'Horizontal',
            0x01 => 'Rotated 270 CW',
            0x02 => 'Rotated 90 CW',
            0x03 => 'Rotated 180',
        },
    },
    590.2 => {
        Name => 'VibrationReduction',
        Mask => 0x18,
        PrintConv => {
            0x00 => 'Off',
            0x18 => 'On',
        },
    },
    590.3 => {
        Name => 'FlashFired',
        Mask => 0xe0,
        PrintConv => { BITMASK => {
            6 => 'Internal',
            7 => 'External',
        }},
    },
    # Custom Settings
    748.1 => { # CS1
        Name => 'Beep',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'On',
            0x80 => 'Off',
        },
    },
    748.2 => { # CS4
        Name => 'AFAssist',
        Mask => 0x40,
        PrintConv => {
            0x00 => 'On',
            0x40 => 'Off',
        },
    },
    748.3 => { # CS5
        Name => 'NoMemoryCard',
        Mask => 0x20,
        PrintConv => {
            0x00 => 'Release Locked',
            0x20 => 'Enable Release',
        },
    },
    748.4 => { # CS6
        Name => 'ImageReview',
        Mask => 0x10,
        PrintConv => {
            0x00 => 'On',
            0x10 => 'Off',
        },
    },
    748.5 => { # CS17
        Name => 'Illumination',
        Mask => 0x08,
        PrintConv => {
            0x00 => 'Off',
            0x08 => 'On',
        },
    },
    748.6 => { # CS11
        Name => 'MainDialExposureComp',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'Off',
            0x04 => 'On',
        },
    },
    748.7 => { # CS10
        Name => 'EVStepSize',
        Mask => 0x01,
        PrintConv => {
            0x00 => '1/3 EV',
            0x01 => '1/2 EV',
        },
    },
    749.1 => { # CS7
        Name => 'AutoISO',
        Mask => 0x40,
        PrintConv => {
            0x00 => 'Off',
            0x40 => 'On',
        },
    },
    749.2 => { # CS7-a
        Name => 'AutoISOMax',
        Mask => 0x30,
        PrintConv => {
            0x00 => 200,
            0x10 => 400,
            0x20 => 800,
            0x30 => 1600,
        },
    },
    749.3 => { # CS7-b
        Name => 'AutoISOMinShutterSpeed',
        Mask => 0x0f,
        PrintConv => {
            0x00 => '1/125 s',
            0x01 => '1/100 s',
            0x02 => '1/80 s',
            0x03 => '1/60 s',
            0x04 => '1/40 s',
            0x05 => '1/30 s',
            0x06 => '1/15 s',
            0x07 => '1/8 s',
            0x08 => '1/4 s',
            0x09 => '1/2 s',
            0x0a => '1 s',
        },
    },
    750.1 => { # CS13
        Name => 'AutoBracketSet',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'AE & Flash',
            0x40 => 'AE Only',
            0x80 => 'Flash Only',
            0xc0 => 'WB Bracketing',
        },
    },
    750.2 => { # CS14
        Name => 'AutoBracketOrder',
        Mask => 0x20,
        PrintConv => {
            0x00 => '0,-,+',
            0x20 => '-,0,+',
        },
    },
    751.1 => { # CS27
        Name => 'MonitorOffTime',
        Mask => 0xe0,
        PrintConv => {
            0x00 => '5 s',
            0x20 => '10 s',
            0x40 => '20 s',
            0x60 => '1 min',
            0x80 => '5 min',
            0xa0 => '10 min',
        },
    },
    751.2 => { # CS28
        Name => 'MeteringTime',
        Mask => 0x1c,
        PrintConv => {
            0x00 => '4 s',
            0x04 => '6 s',
            0x08 => '8 s',
            0x0c => '16 s',
            0x10 => '30 s',
            0x14 => '30 min',
        },
    },
    751.3 => { # CS29
        Name => 'SelfTimerTime',
        Mask => 0x03,
        PrintConv => {
            0x00 => '2 s',
            0x01 => '5 s',
            0x02 => '10 s',
            0x03 => '20 s',
        },
    },
    752.1 => { # CS18
        Name => 'AELockButton',
        Mask => 0x1e,
        PrintConv => {
            0x00 => 'AE/AF Lock',
            0x02 => 'AE Lock Only',
            0x04 => 'AF Lock Only',
            0x06 => 'AE Lock Hold',
            0x08 => 'AF-ON',
            0x0a => 'FV Lock',
            0x0c => 'Focus Area Selection',
            0x0e => 'AE-L/AF-L/AF Area',
            0x10 => 'AE-L/AF Area',
            0x12 => 'AF-L/AF Area',
            0x14 => 'AF-ON/AF Area',
        },
    },
    752.2 => { # CS19
        Name => 'AELock',
        Mask => 0x01,
        PrintConv => {
            0x00 => 'Off',
            0x01 => 'On',
        },
    },
    752.3 => { # CS30
        Name => 'RemoteOnDuration',
        Mask => 0xc0,
        PrintConv => {
            0x00 => '1 min',
            0x40 => '5 min',
            0x80 => '10 min',
            0xc0 => '15 min',
        },
    },
    753.1 => { # CS15
        Name => 'CommandDials',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Standard (Main Shutter, Sub Aperture)',
            0x80 => 'Reversed (Main Aperture, Sub Shutter)',
        },
    },
    753.2 => { # CS16
        Name => 'FunctionButton',
        Mask => 0x78,
        PrintConv => {
            0x00 => 'ISO Display',
            0x08 => 'Framing Grid',
            0x10 => 'AF-area Mode',
            0x18 => 'Center AF Area',
            0x20 => 'FV Lock',
            0x28 => 'Flash Off',
            0x30 => 'Matrix Metering',
            0x38 => 'Center-weighted',
            0x40 => 'Spot Metering',
        },
    },
    754.1 => { # CS8
        Name => 'GridDisplay',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Off',
            0x80 => 'On',
        },
    },
    754.2 => { # CS9
        Name => 'ViewfinderWarning',
        Mask => 0x40,
        PrintConv => {
            0x00 => 'On',
            0x40 => 'Off',
        },
    },
    754.3 => { # CS12
        Name => 'CenterWeightedAreaSize',
        Mask => 0x0c,
        PrintConv => {
            0x00 => '6 mm',
            0x04 => '8 mm',
            0x08 => '10 mm',
        },
    },
    754.4 => { # CS31
        Name => 'ExposureDelayMode',
        Mask => 0x20,
        PrintConv => {
            0x00 => 'Off',
            0x20 => 'On',
        },
    },
    754.5 => { # CS32
        Name => 'MB-D80Batteries',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'LR6 (AA Alkaline)',
            0x01 => 'HR6 (AA Ni-MH)',
            0x02 => 'FR6 (AA Lithium)',
            0x03 => 'ZR6 (AA Ni-Mg)',
        },
    },
    755.1 => { # CS23
        Name => 'FlashWarning',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'On',
            0x80 => 'Off',
        },
    },
    755.1 => { # CS24
        Name => 'FlashShutterSpeed',
        Mask => 0x78,
        ValueConv => '2 ** (($val >> 3) - 6)',
        ValueConvInv => '$val>0 ? int(log($val)/log(2)+6+0.5) << 3 : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    755.2 => { # CS25
        Name => 'AutoFP',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'Off',
            0x04 => 'On',
        },
    },
    755.3 => { # CS26
        Name => 'ModelingFlash',
        Mask => 0x02,
        PrintConv => {
            0x00 => 'Off',
            0x02 => 'On',
        },
    },
    756.1 => { # CS22
        Name => 'InternalFlash',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'TTL',
            0x40 => 'Manual',
            0x80 => 'Repeating Flash',
            0xc0 => 'Commander Mode',
        },
    },
    756.2 => { # CS22-a
        Name => 'ManualFlashOutput',
        Mask => 0x07,
        ValueConv => '2 ** (-$val)',
        ValueConvInv => '$val > 0 ? -log($val)/log(2) : 0',
        PrintConv => q{
            return 'Full' if $val > 0.99;
            Image::ExifTool::Exif::PrintExposureTime($val);
        },
        PrintConvInv => '$val=~/F/i ? 1 : eval $val',
    },
    757.1 => { # CS22-b
        Name => 'RepeatingFlashOutput',
        Mask => 0x70,
        ValueConv => '2 ** (-($val>>4)-2)',
        ValueConvInv => '$val > 0 ? int(-log($val)/log(2)-2+0.5)<<4 : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    757.2 => { # CS22-c
        Name => 'RepeatingFlashCount',
        Mask => 0x0f,
        ValueConv => '$val < 10 ? $val + 1 : 5 * ($val - 7)',
        ValueConvInv => '$val <= 10 ? $val - 1 : $val / 5 + 7',
    },
    758.1 => { # CS22-d
        Name => 'RepeatingFlashRate',
        Mask => 0xf0,
        ValueConv => 'my $v=($val>>4); $v < 10 ? $v + 1 : 10 * ($val - 8)',
        ValueConvInv => 'int(($val <= 10 ? $val - 1 : $val / 10 + 8) + 0.5) << 4',
        PrintConv => '"$val Hz"',
        PrintConvInv => '$val=~/(\d+)/; $1 || 0',
    },
    758.2 => { # CS22-n
        Name => 'CommanderChannel',
        Mask => 0x03,
        ValueConv => '$val + 1',
        ValueConvInv => '$val - 1',
    },
    759.1 => { # CS22-e
        Name => 'CommanderInternalFlash',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'TTL',
            0x40 => 'Manual',
            0x80 => 'Off',
        },
    },
    759.2 => { # CS22-h
        Name => 'CommanderGroupAMode',
        Mask => 0x30,
        PrintConv => {
            0x00 => 'TTL',
            0x10 => 'Auto Aperture',
            0x20 => 'Manual',
            0x30 => 'Off',
        },
    },
    759.3 => { # CS22-k
        Name => 'CommanderGroupBMode',
        Mask => 0x0c,
        PrintConv => {
            0x00 => 'TTL',
            0x04 => 'Auto Aperture',
            0x08 => 'Manual',
            0x0c => 'Off',
        },
    },
    760.1 => { # CS22-f
        Name => 'CommanderInternalTTLComp',
        Mask => 0x1f,
        ValueConv => '($val - 9) / 3',
        ValueConvInv => '$val * 3 + 9',
        PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
        PrintConvInv => '$val',
    },
    760.2 => { # CS22-g
        Name => 'CommanderInternalManualOutput',
        Mask => 0xe0,
        ValueConv => '2 ** (-($val>>5))',
        ValueConvInv => '$val > 0 ? int(-log($val)/log(2)+0.5) << 5 : 0',
        PrintConv => q{
            return 'Full' if $val > 0.99;
            Image::ExifTool::Exif::PrintExposureTime($val);
        },
        PrintConvInv => '$val=~/F/i ? 1 : eval $val',
    },
    761.1 => { # CS22-i
        Name => 'CommanderGroupA_TTL-AAComp',
        Mask => 0x1f,
        ValueConv => '($val - 9) / 3',
        ValueConvInv => '$val * 3 + 9',
        PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
        PrintConvInv => '$val',
    },
    761.2 => { # CS22-j
        Name => 'CommanderGroupA_ManualOutput',
        Mask => 0xe0,
        ValueConv => '2 ** (-($val>>5))',
        ValueConvInv => '$val > 0 ? int(-log($val)/log(2)+0.5) << 5 : 0',
        PrintConv => q{
            return 'Full' if $val > 0.99;
            Image::ExifTool::Exif::PrintExposureTime($val);
        },
        PrintConvInv => '$val=~/F/i ? 1 : eval $val',
    },
    762.1 => { # CS22-l
        Name => 'CommanderGroupB_TTL-AAComp',
        Mask => 0x1f,
        ValueConv => '($val - 9) / 3',
        ValueConvInv => '$val * 3 + 9',
        PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
        PrintConvInv => '$val',
    },
    762.2 => { # CS22-m
        Name => 'CommanderGroupB_ManualOutput',
        Mask => 0xe0,
        ValueConv => '2 ** (-($val>>5))',
        ValueConvInv => '$val > 0 ? int(-log($val)/log(2)+0.5) << 5 : 0',
        PrintConv => q{
            return 'Full' if $val > 0.99;
            Image::ExifTool::Exif::PrintExposureTime($val);
        },
        PrintConvInv => '$val=~/F/i ? 1 : eval $val',
    },
    763.1 => { # CS3
        Name => 'CenterAFArea',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Normal Zone',
            0x80 => 'Wide Zone',
        },
    },
    763.2 => { # CS20
        Name => 'FocusAreaSelection',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'No Wrap',
            0x04 => 'Wrap',
        },
    },
    763.3 => { # CS21
        Name => 'AFAreaIllumination',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'Auto',
            0x01 => 'Off',
            0x02 => 'On',
        },
    },
    764 => { # CS2
        Name => 'AFAreaMode',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'Single Area',
            0x40 => 'Dynamic Area',
            0x80 => 'Auto-area AF',
        },
    },
    # note: DecryptLen currently set to 764
);

# shot information for D40 and D40X (encrypted) - ref PH
%Image::ExifTool::Nikon::ShotInfoD40 = (
    PROCESS_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    WRITE_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    VARS => { ID_LABEL => 'Index' }, # change TagID label in documentation
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are extracted from encrypted data in D40 and D40X images.',
    0x00 => {
        Name => 'ShotInfoVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    582 => {
        Name => 'ShutterCount',
        Format => 'int32u',
        Priority => 0,
    },
    586.1 => { #JD
        Name => 'VibrationReduction',
        Mask => 0x08,
        PrintConv => {
            0x00 => 'Off',
            0x08 => 'On',
        },
    },
    729.1 => { # CS1
        Name => 'Beep',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'On',
            0x80 => 'Off',
        },
    },
    729.2 => { # CS9
        Name => 'AFAssist',
        Mask => 0x40,
        PrintConv => {
            0x00 => 'On',
            0x40 => 'Off',
        },
    },
    729.3 => { # CS6
        Name => 'NoMemoryCard',
        Mask => 0x20,
        PrintConv => {
            0x00 => 'Release Locked',
            0x20 => 'Enable Release',
        },
    },
    729.4 => { # CS7
        Name => 'ImageReview',
        Mask => 0x10,
        PrintConv => {
            0x00 => 'On',
            0x10 => 'Off',
        },
    },
    730.1 => { # CS10-a
        Name => 'AutoISO',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Off',
            0x80 => 'On',
        },
    },
    730.2 => { # CS10-b
        Name => 'AutoISOMax',
        Mask => 0x30,
        PrintConv => {
            0x10 => 400,
            0x20 => 800,
            0x30 => 1600,
        },
    },
    730.3 => { # CS10-c
        Name => 'AutoISOMinShutterSpeed',
        Mask => 0x07,
        PrintConv => {
            0x00 => '1/125 s',
            0x01 => '1/60 s',
            0x02 => '1/30 s',
            0x03 => '1/15 s',
            0x04 => '1/8 s',
            0x05 => '1/4 s',
            0x06 => '1/2 s',
            0x07 => '1 s',
        },
    },
    731 => { # CS15-b
        Name => 'ImageReviewTime',
        Mask => 0x07,
        PrintConv => {
            0x00 => '4 s',
            0x01 => '8 s',
            0x02 => '20 s',
            0x03 => '1 min',
            0x04 => '10 min',
        },
    },
    732.1 => { # CS15-a
        Name => 'MonitorOffTime',
        Mask => 0xe0,
        PrintConv => {
            0x00 => '4 s',
            0x20 => '8 s',
            0x40 => '20 s',
            0x60 => '1 min',
            0x80 => '10 min',
        },
    },
    732.2 => { # CS15-c
        Name => 'MeteringTime',
        Mask => 0x1c,
        PrintConv => {
            0x00 => '4 s',
            0x04 => '8 s',
            0x08 => '20 s',
            0x0c => '1 min',
            0x10 => '30 min',
        },
    },
    732.3 => { # CS16
        Name => 'SelfTimerTime',
        Mask => 0x03,
        PrintConv => {
            0x00 => '2 s',
            0x01 => '5 s',
            0x02 => '10 s',
            0x03 => '20 s',
        },
    },
    733.1 => { # CS17
        Name => 'RemoteOnDuration',
        Mask => 0xc0,
        PrintConv => {
            0x00 => '1 min',
            0x40 => '5 min',
            0x80 => '10 min',
            0xc0 => '15 min',
        },
    },
    733.2 => { # CS12
        Name => 'AELockButton',
        Mask => 0x0e,
        PrintConv => {
            0x00 => 'AE/AF Lock',
            0x02 => 'AE Lock Only',
            0x04 => 'AF Lock Only',
            0x06 => 'AE Lock Hold',
            0x08 => 'AF-ON',
        },
    },
    733.3 => { # CS13
        Name => 'AELock',
        Mask => 0x01,
        PrintConv => {
            0x00 => 'Off',
            0x01 => 'On',
        },
    },
    734.1 => { # CS4
        Name => 'ShootingModeSetting',
        Mask => 0x70,
        PrintConv => {
            0x00 => 'Single Frame',
            0x10 => 'Continuous',
            0x20 => 'Self-timer',
            0x30 => 'Delayed Remote',
            0x40 => 'Quick-response Remote',
        },
    },
    734.2 => { # CS11
        Name => 'TimerFunctionButton',
        Mask => 0x07,
        PrintConv => {
            0x00 => 'Shooting Mode',
            0x01 => 'Image Quality/Size',
            0x02 => 'ISO',
            0x03 => 'White Balance',
            0x04 => 'Self-timer',
        },
    },
    735 => { # CS5
        Name => 'Metering',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'Matrix',
            0x01 => 'Center-weighted',
            0x02 => 'Spot',
        },
    },
    737.1 => { # CS14-a
        Name => 'InternalFlash',
        Mask => 0x10,
        PrintConv => {
            0x00 => 'TTL',
            0x10 => 'Manual',
        },
    },
    737.2 => { # CS14-b
        Name => 'ManualFlashOutput',
        Mask => 0x07,
        ValueConv => '2 ** (-$val)',
        ValueConvInv => '$val > 0 ? -log($val)/log(2) : 0',
        PrintConv => q{
            return 'Full' if $val > 0.99;
            Image::ExifTool::Exif::PrintExposureTime($val);
        },
        PrintConvInv => '$val=~/F/i ? 1 : eval $val',
    },
    738 => { # CS8
        Name => 'FlashLevel',
        Format => 'int8s',
        ValueConv => '$val / 6',
        ValueConvInv => '$val * 6',
        PrintConv => 'sprintf("%+.1f",$val)',
        PrintConvInv => '$val',
    },
    739 => { # CS2
        Name => 'FocusModeSetting',
        # (may differ from FocusMode if lens switch is set to Manual)
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'Manual',
            0x40 => 'AF-S',
            0x80 => 'AF-C',
            0xc0 => 'AF-A',
        },
    },
    740 => { # CS3
        Name => 'AFAreaModeSetting',
        # (may differ from AFAreaMode for Manual focus)
        Mask => 0x30,
        PrintConv => {
            0x00 => 'Single Area',
            0x10 => 'Dynamic Area',
            0x20 => 'Closest Subject',
        },
    }
    # note: DecryptLen currently set to 748
);

# shot information for the D300 (encrypted) - ref JD
%Image::ExifTool::Nikon::ShotInfoD300 = (
    PROCESS_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    WRITE_PROC => \&Image::ExifTool::Nikon::ProcessNikonEncrypted,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    VARS => { ID_LABEL => 'Index' }, # change TagID label in documentation
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are extracted from encrypted data in D300 images.',
    604 => {
        Name => 'ISO2',
        ValueConv => '100*exp(($val/12-5)*log(2))',
        ValueConvInv => '(log($val/100)/log(2)+5)*12',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    633 => {
        Name => 'ShutterCount',
        Format => 'int32u',
        Priority => 0,
    },
    721 => { #PH
        Name => 'AFFineTuneAdj',
        Format => 'int16u',
        PrintHex => 1,
        # thanks to Neil Nappe for the samples to decode this!...
        # (have seen various unknown values here when flash is enabled, but
        # these are yet to be decoded: 0x2e,0x619,0xd0d,0x103a,0x2029 - PH)
        PrintConv => {
            0x403e => '+20',
            0x303e => '+19',
            0x203e => '+18',
            0x103e => '+17',
            0x003e => '+16',
            0xe03d => '+15',
            0xc03d => '+14',
            0xa03d => '+13',
            0x803d => '+12',
            0x603d => '+11',
            0x403d => '+10',
            0x203d => '+9',
            0x003d => '+8',
            0xc03c => '+7',
            0x803c => '+6',
            0x403c => '+5',
            0x003c => '+4',
            0x803b => '+3',
            0x003b => '+2',
            0x003a => '+1',
            0x0000 => '0',
            0x00c6 => '-1',
            0x00c5 => '-2',
            0x80c5 => '-3',
            0x00c4 => '-4',
            0x40c4 => '-5',
            0x80c4 => '-6',
            0xc0c4 => '-7',
            0x00c3 => '-8',
            0x20c3 => '-9',
            0x40c3 => '-10',
            0x60c3 => '-11',
            0x80c3 => '-12',
            0xa0c3 => '-13',
            0xc0c3 => '-14',
            0xe0c3 => '-15',
            0x00c2 => '-16',
            0x10c2 => '-17',
            0x20c2 => '-18',
            0x30c2 => '-19',
            0x40c2 => '-20',
        },
    },
    791.1 => { # CSa1
        Name => 'AF-CPrioritySelection',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'Release',
            0x40 => 'Release + Focus',
            0x80 => 'Focus',
        },
    },
    791.2 => { # CSa2
        Name => 'AF-SPrioritySelection',
        Mask => 0x20,
        PrintConv => {
            0x00 => 'Focus',
            0x20 => 'Release',
        },
    },
    791.3 => { # CSa8
        Name => 'AFPointSelection',
        Mask => 0x10,
        PrintConv => {
            0x00 => '51 Points',
            0x10 => '11 Points',
        },
    },
    791.4 => { # CSa3
        Name => 'DynamicAFArea',
        Mask => 0x0c,
        PrintConv => {
            0x00 => '9 Points',
            0x04 => '21 Points',
            0x08 => '51 Points',
            0x0c => '51 Points (3D-tracking)',
        },
    },
    791.5 => { # CSa4
        Name => 'FocusTrackingLockOn',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'Long',
            0x01 => 'Normal',
            0x02 => 'Short',
            0x03 => 'Off',
        },
    },
    792.1 => { # CSa5
        Name => 'AFActivation',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Shutter/AF-On',
            0x80 => 'AF-On Only',
        },
    },
    792.2 => { # CSa7
        Name => 'FocusPointWrap',
        Mask => 0x08,
        PrintConv => {
            0x00 => 'No Wrap',
            0x08 => 'Wrap',
        },
    },
    792.3 => { # CSa6
        Name => 'AFPointIllumination',
        Mask => 0x06,
        PrintConv => {
            0x00 => 'Auto',
            0x02 => 'Off',
            0x04 => 'On',
        },
    },
    792.4 => { # CSa9
        Name => 'AFAssistIlluminator',
        Mask => 0x01,
        PrintConv => { 0x00 => 'On', 0x01 => 'Off' },
    },
    793.1 => { # CSa10
        Name => 'AF-OnForMB-D10',
        Mask => 0x70,
        PrintConv => {
            0x00 => 'AF-On',
            0x10 => 'AE/AF Lock',
            0x20 => 'AE Lock Only',
            0x30 => 'AE Lock (reset on release)',
            0x40 => 'AE Lock (hold)',
            0x50 => 'AF Lock Only',
            0x60 => 'Same as FUNC Button',
        },
    },
    796.1 => { # CSb1
        Name => 'ISOStepSize',
        Mask => 0xc0,
        PrintConv => {
            0x00 => '1/3 EV',
            0x40 => '1/2 EV',
            0x80 => '1 EV',
        },
    },
    796.2 => { # CSb2
        Name => 'ExposureControlStepSize',
        Mask => 0x30,
        PrintConv => {
            0x00 => '1/3 EV',
            0x10 => '1/2 EV',
            0x20 => '1 EV',
        },
    },
    796.3 => { # CSb3
        Name => 'FineTuneStepSize',
        Mask => 0x0c,
        PrintConv => {
            0x00 => '1/3 EV',
            0x04 => '1/2 EV',
            0x08 => '1 EV',
        },
    },
    796.4 => { # CSb4
        Name => 'EasyExposureCompensation',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'Off',
            0x01 => 'On',
            0x02 => 'On (auto reset)',
        },
    },
    797.1 => { # CSb5
        Name => 'CenterWeightedAreaSize',
        Mask => 0xe0,
        PrintConv => {
            0x00 => '6 mm',
            0x20 => '8 mm',
            0x40 => '10 mm',
            0x60 => '13 mm',
            0x80 => 'Average',
        },
    },
    797.2 => { # CSb6-b
        Name => 'FineTuneOptCenterWeighted',
        Mask => 0x0f,
        ValueConv => '($val > 0x7 ? $val - 0x10 : $val) / 6',
        ValueConvInv => 'int($val*6+($val>0?0.5:-0.5)) & 0x0f',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
    798.1 => { # CSb6-a
        Name => 'FineTuneOptMatrixMetering',
        Mask => 0xf0,
        ValueConv => '($val > 0x70 ? $val - 0x100 : $val) / 0x60',
        ValueConvInv => '(int($val*6+($val>0?0.5:-0.5))<<4) & 0xf0',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
    798.2 => { # CSb6-c
        Name => 'FineTuneOptSpotMetering',
        Mask => 0x0f,
        ValueConv => '($val > 0x7 ? $val - 0x10 : $val) / 6',
        ValueConvInv => 'int($val*6+($val>0?0.5:-0.5)) & 0x0f',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
    799.1 => { # CSf1-a
        Name => 'MultiSelectorShootMode',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'Select Center Focus Point',
            0x40 => 'Highlight Active Focus Point',
            0x80 => 'Not Used',
        },
    },
    799.2 => { # CSf1-b
        Name => 'MultiSelectorPlaybackMode',
        Mask => 0x30,
        PrintConv => {
            0x00 => 'Thumbnail On/Off',
            0x10 => 'View Histograms',
            0x20 => 'Zoom On/Off',
            0x30 => 'Choose Folder',
        },
    },
    799.3 => { # CSf1-c
        Name => 'InitialZoomSetting',
        Mask => 0x0c,
        PrintConv => {
            0x00 => 'Low Magnification',
            0x04 => 'Medium Magnification',
            0x08 => 'High Magnification',
        },
    },
    799.4 => { # CSf2
        Name => 'MultiSelector',
        Mask => 0x01,
        PrintConv => {
            0x00 => 'Do Nothing',
            0x01 => 'Reset Meter-off Delay',
        },
    },
    800.1 => { # CSd9
        Name => 'ExposureDelayMode',
        Mask => 0x40,
        PrintConv => { 0x00 => 'Off', 0x40 => 'On' },
    },
    800.2 => { # CSd4
        Name => 'CLModeShootingSpeed',
        Mask => 0x07,
        PrintConv => '"$val fps"',
        PrintConvInv => '$val=~s/\s*fps//i; $val',
    },
    801.1 => { # CSd5
        Name => 'MaxContinuousRelease',
        Mask => 0x7f,
        PrintConv => '"$val fps"',
        PrintConvInv => '$val=~s/\s*fps//i; $val',
    },
    802.1 => { # CSf10
        Name => 'ReverseIndicators',
        Mask => 0x20,
        PrintConv => {
            0x00 => '+ 0 -',
            0x20 => '- 0 +',
        },
    },
    802.2 => { # CSd6
        Name => 'FileNumberSequence',
        Mask => 0x08,
        PrintConv => { 0x00 => 'On', 0x08 => 'Off' },
    },
    802.3 => { # CSd11
        Name => 'BatteryOrder',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'MB-D10 First',
            0x04 => 'Camera Battery First',
        },
    },
    802.4 => { # CSd10
        Name => 'MB-D10Batteries',
        Mask => 0x03,
        PrintConv => {
            0x00 => 'LR6 (AA alkaline)',
            0x01 => 'HR6 (AA Ni-MH)',
            0x02 => 'FR6 (AA lithium)',
            0x03 => 'ZR6 (AA Ni-Mn)',
        },
    },
    803.1 => { # CSd1
        Name => 'Beep',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'High',
            0x40 => 'Low',
            0x80 => 'Off',
        },
    },
    803.2 => { # CSd7
        Name => 'ShootingInfoDisplay',
        Mask => 0x30,
        PrintConv => {
            0x00 => 'Auto',
            0x20 => 'Manual (dark on light)',
            0x30 => 'Manual (light on dark)',
        },
    },
    803.3 => { # CSd2
        Name => 'GridDisplay',
        Mask => 0x02,
        PrintConv => { 0x00 => 'Off', 0x02 => 'On' },
    },
    803.4 => { # CSd3
        Name => 'ViewfinderWarning',
        Mask => 0x01,
        PrintConv => { 0x00 => 'On', 0x01 => 'Off' },
    },
    807.1 => { # CSf7-a
        Name => 'CommandDialsReverseRotation',
        Mask => 0x80,
        PrintConv => { 0x00 => 'No', 0x80 => 'Yes' },
    },
    807.2 => { # CSf7-b
        Name => 'CommandDialsChangeMainSub',
        Mask => 0x40,
        PrintConv => { 0x00 => 'Off', 0x40 => 'On' },
    },
    807.3 => { # CSf7-c
        Name => 'CommandDialsApertureSetting',
        Mask => 0x20,
        PrintConv => {
            0x00 => 'Sub-command Dial',
            0x20 => 'Aperture Ring',
        },
    },
    807.4 => { # CSf7-d
        Name => 'CommandDialsMenuAndPlayback',
        Mask => 0x10,
        PrintConv => { 0x00 => 'Off', 0x10 => 'On' },
    },
    807.5 => { # CSd8
        Name => 'LCDIllumination',
        Mask => 0x08,
        PrintConv => { 0x00 => 'Off', 0x08 => 'On' },
    },
    807.6 => { # CSf3
        Name => 'PhotoInfoPlayback',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'Info Up-down, Playback Left-right',
            0x04 => 'Info Left-right, Playback Up-down',
        },
    },
    807.7 => { # CSc1
        Name => 'ShutterReleaseButtonAE-L',
        Mask => 0x02,
        PrintConv => { 0x00 => 'Off', 0x02 => 'On' },
    },
    807.8 => { # CSf7-e
        Name => 'ReleaseButtonToUseDial',
        Mask => 0x01,
        PrintConv => { 0x00 => 'No', 0x01 => 'Yes' },
    },
    808.1 => { # CSc3
        Name => 'SelfTimerTime',
        Mask => 0x18,
        PrintConv => {
            0x00 => '2 s',
            0x08 => '5 s',
            0x10 => '10 s',
            0x18 => '20 s',
        },
    },
    808.2 => { # CSc4
        Name => 'MonitorOffTime',
        Mask => 0x07,
        PrintConv => {
            0x00 => '10 s',
            0x01 => '20 s',
            0x02 => '1 min',
            0x03 => '5 min',
            0x04 => '10 min',
        },
    },
    810.1 => { # CSe1
        Name => 'FlashSyncSpeed',
        Mask => 0xf0,
        PrintConv => {
            0x00 => '1/320 s (auto FP)',
            0x10 => '1/250 s (auto FP)',
            0x20 => '1/250 s',
            0x30 => '1/200 s',
            0x40 => '1/160 s',
            0x50 => '1/125 s',
            0x60 => '1/100 s',
            0x70 => '1/80 s',
            0x80 => '1/60 s',
        },
    },
    810.2 => { # CSe2
        Name => 'FlashShutterSpeed',
        Mask => 0x0f,
        PrintConv => {
            0x00 => '1/60 s',
            0x01 => '1/30 s',
            0x02 => '1/15 s',
            0x03 => '1/8 s',
            0x04 => '1/4 s',
            0x05 => '1/2 s',
            0x06 => '1 s',
            0x07 => '2 s',
            0x08 => '4 s',
            0x09 => '8 s',
            0x0a => '15 s',
            0x0b => '30 s',
        },
    },
    811.1 => { # CSe5
        Name => 'AutoBracketSet',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'AE & Flash',
            0x40 => 'AE Only',
            0x80 => 'Flash Only',
            0xc0 => 'WB Bracketing',
        },
    },
    811.2 => { # CSe6
        Name => 'AutoBracketModeM',
        Mask => 0x30,
        PrintConv => {
            0x00 => 'Flash/Speed',
            0x10 => 'Flash/Speed/Aperture',
            0x20 => 'Flash/Aperture',
            0x30 => 'Flash Only',
        },
    },
    811.3 => { # CSe7
        Name => 'AutoBracketOrder',
        Mask => 0x08,
        PrintConv => {
            0x00 => '0,-,+',
            0x08 => '-,0,+',
        },
    },
    811.4 => { # CSe4
        Name => 'ModelingFlash',
        Mask => 0x01,
        PrintConv => { 0x00 => 'On', 0x01 => 'Off' },
    },
    812.1 => { # CSf9
        Name => 'NoMemoryCard',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Release Locked',
            0x80 => 'Enable Release',
        },
    },
    812.2 => { # CSc2
        Name => 'MeteringTime',
        Mask => 0x0f,
        PrintConv => {
            0x00 => '4 s',
            0x01 => '2 s',
            0x02 => '8 s',
            0x03 => '16 s',
            0x04 => '30 s',
            0x05 => '1 min',
            0x06 => '5 min',
            0x07 => '10 min',
            0x08 => '30 min',
            0x09 => 'No Limit',
        },
    },
    813.1 => { # CSe3
        Name => 'InternalFlash',
        Mask => 0xc0,
        PrintConv => {
            0x00 => 'TTL',
            0x40 => 'Manual',
            0x80 => 'Repeating Flash',
            0xc0 => 'Commander Mode',
        },
    },
    # note: DecryptLen currently set to 813
);

# Flash information (ref JD)
%Image::ExifTool::Nikon::FlashInfo0100 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    DATAMEMBER => [ 9.2, 15, 16 ],
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'FlashInfoVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    # If byte 6 and 7 are both 0 either a internal flash was used, or no flash
    # - that depends on byte 4 and 5:
    # 00 36 = Internal flash (D50, D70 or D70s)
    # 02 2E = Internal flash (D80)
    # 02 30 = Internal flash (D200 or D40)
    # 02 32 = Internal flash (D300)
    # 
    # 00 00 = No flash used
    # 00 48 = No flash used (D50)
    # 00 4E = No flash used (D70 or D70s)
    # 
    # If byte 6 and 7 are not 0, they need to be interpreted instead of byte 4 and 5:
    # 02 04 = SB-600
    # 02 05 = SB-600
    # 
    # 01 01 = SB-800 (or Metz 58 AF-1)
    # 02 01 = SB-800
    # 01 03 = SB-800
    8 => {
        Name => 'ExternalFlashFlags',
        PrintConv => { BITMASK => {
            4 => 'Wide Flash Adapter',
        }},
    },
    9.1 => {
        Name => 'FlashCommanderMode',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Off',
            0x80 => 'On',
        },
    },
    9.2 => {
        Name => 'FlashControlMode',
        Mask => 0x7f,
        DataMember => 'FlashControlMode',
        RawConv => '$$self{FlashControlMode} = $val',
        PrintConv => {
            0x00 => 'Off',
            0x01 => 'iTTL-BL',
            0x02 => 'iTTL',
            0x03 => 'Auto Aperture',
            0x06 => 'Manual',
            0x07 => 'Repeating Flash',
        },
    },
    10 => [
        {
            Name => 'FlashOutput',
            Condition => '$$self{FlashControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashExposureComp',
            Description => 'Flash Exposure Compensation',
            Format => 'int8s',
            Priority => 0,
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
    11 => {
        Name => 'FlashFocalLength',
        RawConv => '$val ? $val : undef',
        PrintConv => '"$val mm"',
        PrintConvInv => '$val=~/(\d+)/; $1 || 0',
    },
    12 => {
        Name => 'RepeatingFlashRate',
        RawConv => '$val ? $val : undef',
        PrintConv => '"$val Hz"',
        PrintConvInv => '$val=~/(\d+)/; $1 || 0',
    },
    13 => {
        Name => 'RepeatingFlashCount',
        RawConv => '$val ? $val : undef',
    },
    15 => {
        Name => 'FlashGroupAControlMode',
        Mask => 0x0f,
        DataMember => 'FlashGroupAControlMode',
        RawConv => '$$self{FlashGroupAControlMode} = $val',
        PrintConv => {
            0 => 'Off',
            1 => 'iTTL-BL',
            2 => 'iTTL',
            3 => 'Auto Aperture',
            6 => 'Manual',
            7 => 'Repeating Flash',
        },
    },
    16 => {
        Name => 'FlashGroupBControlMode',
        Mask => 0x0f,
        DataMember => 'FlashGroupBControlMode',
        RawConv => '$$self{FlashGroupBControlMode} = $val',
        PrintConv => {
            0 => 'Off',
            1 => 'iTTL-BL',
            2 => 'iTTL',
            3 => 'Auto Aperture',
            6 => 'Manual',
            7 => 'Repeating Flash',
        },
    },
    17 => [
        {
            Name => 'FlashGroupAOutput',
            Condition => '$$self{FlashGroupAControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashGroupAExposureComp',
            Format => 'int8s',
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
    18 => [
        {
            Name => 'FlashGroupBOutput',
            Condition => '$$self{FlashGroupBControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashGroupBExposureComp',
            Format => 'int8s',
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
);

# Flash information for D40, D40x, D3 and D300 (ref JD)
%Image::ExifTool::Nikon::FlashInfo0102 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    DATAMEMBER => [ 9.2, 15, 16 ],
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => 'These tags are used by the D40, D40X, D60, D3 and D300.',
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'FlashInfoVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    8 => {
        Name => 'ExternalFlashFlags',
        PrintConv => { BITMASK => {
            4 => 'Wide Flash Adapter',
        }},
    },
    9.1 => {
        Name => 'FlashCommanderMode',
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Off',
            0x80 => 'On',
        },
    },
    9.2 => {
        Name => 'FlashControlMode',
        Mask => 0x7f,
        DataMember => 'FlashControlMode',
        RawConv => '$$self{FlashControlMode} = $val',
        PrintConv => {
            0x00 => 'Off',
            0x01 => 'iTTL-BL',
            0x02 => 'iTTL',
            0x03 => 'Auto Aperture',
            0x06 => 'Manual',
            0x07 => 'Repeating Flash',
        },
    },
    10 => [
        {
            Name => 'FlashOutput',
            Condition => '$$self{FlashControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashExposureComp',
            Description => 'Flash Exposure Compensation',
            Format => 'int8s',
            Priority => 0,
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
    12 => {
        Name => 'FlashFocalLength',
        RawConv => '$val ? $val : undef',
        PrintConv => '"$val mm"',
        PrintConvInv => '$val=~/(\d+)/; $1 || 0',
    },
    13 => {
        Name => 'RepeatingFlashRate',
        RawConv => '$val ? $val : undef',
        PrintConv => '"$val Hz"',
        PrintConvInv => '$val=~/(\d+)/; $1 || 0',
    },
    14 => {
        Name => 'RepeatingFlashCount',
        RawConv => '$val ? $val : undef',
    },
    16 => {
        Name => 'FlashGroupAControlMode',
        Mask => 0x0f,
        DataMember => 'FlashGroupAControlMode',
        RawConv => '$$self{FlashGroupAControlMode} = $val',
        PrintConv => {
            0 => 'Off',
            1 => 'iTTL-BL',
            2 => 'iTTL',
            3 => 'Auto Aperture',
            6 => 'Manual',
            7 => 'Repeating Flash',
        },
    },
    17 => {
        Name => 'FlashGroupBControlMode',
        Mask => 0x0f,
        DataMember => 'FlashGroupBControlMode',
        RawConv => '$$self{FlashGroupBControlMode} = $val',
        PrintConv => {
            0 => 'Off',
            1 => 'iTTL-BL',
            2 => 'iTTL',
            3 => 'Auto Aperture',
            6 => 'Manual',
            7 => 'Repeating Flash',
        },
    },
    18 => [
        {
            Name => 'FlashGroupAOutput',
            Condition => '$$self{FlashGroupAControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashGroupAExposureComp',
            Format => 'int8s',
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
    19 => [
        {
            Name => 'FlashGroupBOutput',
            Condition => '$$self{FlashGroupBControlMode} >= 0x06',
            ValueConv => '2 ** (-$val/6)',
            ValueConvInv => '$val>0 ? -6*log($val)/log(2) : 0',
            PrintConv => '$val>0.99 ? "Full" : sprintf("%.0f%%",$val*100)',
            PrintConvInv => '$val=~/(\d+)/ ? $1/100 : 1',
        },
        {
            Name => 'FlashGroupBExposureComp',
            Format => 'int8s',
            ValueConv => '-$val/6',
            ValueConvInv => '-6 * $val',
            PrintConv => '$val ? sprintf("%+.1f",$val) : 0',
            PrintConvInv => '$val',
        },
    ],
);

# Unknown Flash information (ref JD)
%Image::ExifTool::Nikon::FlashInfoUnknown = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0 => {
        Name => 'FlashInfoVersion',
        Format => 'string[4]',
        Writable => 0,
    },
);

# Multi exposure / image overlay information (ref PH)
%Image::ExifTool::Nikon::MultiExposure = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    FORMAT => 'int32u',
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    # NOTE: Must set ByteOrder in SubDirectory if any multi-byte integer tags added
    0 => {
        Name => 'MultiExposureVersion',
        Format => 'string[4]',
        Writable => 0,
    },
    1 => {
        Name => 'MultiExposureMode',
        PrintConv => {
            0 => 'Off',
            1 => 'Multiple Exposure',
            2 => 'Image Overlay',
        },
    },
    2 => 'MultiExposureShots',
    3 => {
        Name => 'MultiExposureAutoGain',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
);

# tags in Nikon QuickTime videos (PH - observations with Coolpix S3)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::Nikon::MOV = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => q{
        This information is found in Nikon MOV and QT videos.
    },
    0x00 => {
        Name => 'Make',
        Format => 'string[24]',
    },
    0x18 => {
        Name => 'Model',
        Description => 'Camera Model Name',
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
    0x44 => {
        Name => 'WhiteBalance',
        Format => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Shade',
            3 => 'Fluorescent', #2
            4 => 'Tungsten',
            5 => 'Manual',
        },
    },
    0x48 => {
        Name => 'FocalLength',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f mm",$val)',
    },
    0xaf => {
        Name => 'Software',
        Format => 'string[16]',
    },
    0xdf => { # (this is a guess ... could also be offset 0xdb)
        Name => 'ISO',
        Format => 'int16u',
        RawConv => '$val < 50 ? undef : $val', # (not valid for Coolpix L10)
    },
);


# Nikon composite tags
%Image::ExifTool::Nikon::Composite = (
    GROUPS => { 2 => 'Camera' },
    LensSpec => {
        Description => 'Lens',
        Require => {
            0 => 'Nikon:Lens',
            1 => 'Nikon:LensType',
        },
        ValueConv => '"$val[0] $val[1]"',
        PrintConv => '"$prt[0] $prt[1]"',
    },
    LensID => {
        SeparateTable => 'Nikon LensID',    # print values in a separate table
        Require => {
            0 => 'Nikon:LensIDNumber',
            1 => 'LensFStops',
            2 => 'MinFocalLength',
            3 => 'MaxFocalLength',
            4 => 'MaxApertureAtMinFocal',
            5 => 'MaxApertureAtMaxFocal',
            6 => 'MCUVersion',
            7 => 'Nikon:LensType',
        },
        # construct lens ID string as per ref 11
        ValueConv => 'uc(join(" ",(unpack("H*",pack("C*",@raw)) =~ /../g)))',
        PrintConv => \%nikonLensIDs,
    },
);

# add our composite tags
Image::ExifTool::AddCompositeTags('Image::ExifTool::Nikon');

#------------------------------------------------------------------------------
# Print D3/D300 AF points (similar to Canon::PrintAFPoints1D)
# Inputs: 0) value to convert (undef[7])
# Focus point pattern:
#        A1  A2  A3  A4  A5  A6  A7  A8  A9
#    B1  B2  B3  B4  B5  B6  B7  B8  B9  B10  B11
#    C1  C2  C3  C4  C5  C6  C7  C9  C9  C10  C11
#    D1  D2  D3  D4  D5  D6  D7  D8  D9  D10  D11
#        E1  E2  E3  E4  E5  E6  E7  E8  E9
sub PrintAFPointsD3($)
{
    my $val = shift;
    return 'Unknown' unless length $val == 7;
    # list of byte/bit positions for each focus point (upper/lower nibble)
    my @focusPts = (
             0x55,0x50,0x43,0x14,0x02,0x07,0x21,0x26,0x33,
        0x61,0x54,0x47,0x42,0x13,0x01,0x06,0x20,0x25,0x32,0x37,
        0x60,0x53,0x46,0x41,0x12,0x00,0x05,0x17,0x24,0x31,0x36,
        0x62,0x56,0x51,0x44,0x15,0x03,0x10,0x22,0x27,0x34,0x40,
             0x57,0x52,0x45,0x16,0x04,0x11,0x23,0x30,0x35
    );
    my ($focusPt, @points);
    my @dat = unpack('C*', $val);
    my @cols = (9,11,11,11,9);
    my $cols = shift @cols;
    my ($row, $col) = ('A', 1);
    foreach $focusPt (@focusPts) {
        push @points, $row . $col if $dat[$focusPt >> 4] & (0x01 << ($focusPt & 0x0f));
        if (++$col > $cols) {
            $cols = shift @cols;
            $col = 1;
            ++$row;
        }
    }
    return join(',',@points);
}

#------------------------------------------------------------------------------
# Print PictureControl value
# Inputs: 0) value (with 0x80 subtracted),
#         1) 'Normal' (0 value) string (default 'Normal')
#         2) format string for numbers (default '%+d')
# Returns: PrintConv value
sub PrintPC($;$$)
{
    my ($val, $norm, $fmt) = @_;
    return $norm || 'Normal' if $val == 0;
    return 'n/a'             if $val == 0x7f;
    return 'Auto'            if $val == -128;
    return sprintf($fmt || '%+d', $val);
}

#------------------------------------------------------------------------------
# Inverse of PrintPC
# Inputs: 0) PrintConv value (after subracting 0x80 from raw value)
# Returns: unconverted value
# Notes: raw values: 0=Auto, 0xff=n/a, ... 0x7f=-1, 0x80=0, 0x81=1, ...
sub PrintPCInv($)
{
    my $val = shift;
    return $val if $val =~ /^[-+]?\d+$/;
    return 0x7f if $val =~ /n\/a/i;
    return -128 if $val =~ /auto/i;
    return 0;
}

#------------------------------------------------------------------------------
# Clean up formatting of string values
# Inputs: 0) string value
# Returns: formatted string value
# - removes trailing spaces and changes case to something more sensible
sub FormatString($)
{
    my $str = shift;
    # limit string length (can be very long for some unknown tags)
    if (length($str) > 60) {
        $str = substr($str,0,55) . "[...]";
    } else {
        $str =~ s/\s+$//;   # remove trailing white space and null terminator
        # Don't change case of hyphenated strings (like AF-S) or non-words (no vowels)
        unless ($str =~ /-/ or $str !~ /[AEIOUY]/) {
            # change all letters but the first to lower case
            $str =~ s/([A-Z]{1})([A-Z]+)/$1\L$2/g;
        }
    }
    return $str;
}

#------------------------------------------------------------------------------
# decoding tables from ref 4
my @xlat = (
  [ 0xc1,0xbf,0x6d,0x0d,0x59,0xc5,0x13,0x9d,0x83,0x61,0x6b,0x4f,0xc7,0x7f,0x3d,0x3d,
    0x53,0x59,0xe3,0xc7,0xe9,0x2f,0x95,0xa7,0x95,0x1f,0xdf,0x7f,0x2b,0x29,0xc7,0x0d,
    0xdf,0x07,0xef,0x71,0x89,0x3d,0x13,0x3d,0x3b,0x13,0xfb,0x0d,0x89,0xc1,0x65,0x1f,
    0xb3,0x0d,0x6b,0x29,0xe3,0xfb,0xef,0xa3,0x6b,0x47,0x7f,0x95,0x35,0xa7,0x47,0x4f,
    0xc7,0xf1,0x59,0x95,0x35,0x11,0x29,0x61,0xf1,0x3d,0xb3,0x2b,0x0d,0x43,0x89,0xc1,
    0x9d,0x9d,0x89,0x65,0xf1,0xe9,0xdf,0xbf,0x3d,0x7f,0x53,0x97,0xe5,0xe9,0x95,0x17,
    0x1d,0x3d,0x8b,0xfb,0xc7,0xe3,0x67,0xa7,0x07,0xf1,0x71,0xa7,0x53,0xb5,0x29,0x89,
    0xe5,0x2b,0xa7,0x17,0x29,0xe9,0x4f,0xc5,0x65,0x6d,0x6b,0xef,0x0d,0x89,0x49,0x2f,
    0xb3,0x43,0x53,0x65,0x1d,0x49,0xa3,0x13,0x89,0x59,0xef,0x6b,0xef,0x65,0x1d,0x0b,
    0x59,0x13,0xe3,0x4f,0x9d,0xb3,0x29,0x43,0x2b,0x07,0x1d,0x95,0x59,0x59,0x47,0xfb,
    0xe5,0xe9,0x61,0x47,0x2f,0x35,0x7f,0x17,0x7f,0xef,0x7f,0x95,0x95,0x71,0xd3,0xa3,
    0x0b,0x71,0xa3,0xad,0x0b,0x3b,0xb5,0xfb,0xa3,0xbf,0x4f,0x83,0x1d,0xad,0xe9,0x2f,
    0x71,0x65,0xa3,0xe5,0x07,0x35,0x3d,0x0d,0xb5,0xe9,0xe5,0x47,0x3b,0x9d,0xef,0x35,
    0xa3,0xbf,0xb3,0xdf,0x53,0xd3,0x97,0x53,0x49,0x71,0x07,0x35,0x61,0x71,0x2f,0x43,
    0x2f,0x11,0xdf,0x17,0x97,0xfb,0x95,0x3b,0x7f,0x6b,0xd3,0x25,0xbf,0xad,0xc7,0xc5,
    0xc5,0xb5,0x8b,0xef,0x2f,0xd3,0x07,0x6b,0x25,0x49,0x95,0x25,0x49,0x6d,0x71,0xc7 ],
  [ 0xa7,0xbc,0xc9,0xad,0x91,0xdf,0x85,0xe5,0xd4,0x78,0xd5,0x17,0x46,0x7c,0x29,0x4c,
    0x4d,0x03,0xe9,0x25,0x68,0x11,0x86,0xb3,0xbd,0xf7,0x6f,0x61,0x22,0xa2,0x26,0x34,
    0x2a,0xbe,0x1e,0x46,0x14,0x68,0x9d,0x44,0x18,0xc2,0x40,0xf4,0x7e,0x5f,0x1b,0xad,
    0x0b,0x94,0xb6,0x67,0xb4,0x0b,0xe1,0xea,0x95,0x9c,0x66,0xdc,0xe7,0x5d,0x6c,0x05,
    0xda,0xd5,0xdf,0x7a,0xef,0xf6,0xdb,0x1f,0x82,0x4c,0xc0,0x68,0x47,0xa1,0xbd,0xee,
    0x39,0x50,0x56,0x4a,0xdd,0xdf,0xa5,0xf8,0xc6,0xda,0xca,0x90,0xca,0x01,0x42,0x9d,
    0x8b,0x0c,0x73,0x43,0x75,0x05,0x94,0xde,0x24,0xb3,0x80,0x34,0xe5,0x2c,0xdc,0x9b,
    0x3f,0xca,0x33,0x45,0xd0,0xdb,0x5f,0xf5,0x52,0xc3,0x21,0xda,0xe2,0x22,0x72,0x6b,
    0x3e,0xd0,0x5b,0xa8,0x87,0x8c,0x06,0x5d,0x0f,0xdd,0x09,0x19,0x93,0xd0,0xb9,0xfc,
    0x8b,0x0f,0x84,0x60,0x33,0x1c,0x9b,0x45,0xf1,0xf0,0xa3,0x94,0x3a,0x12,0x77,0x33,
    0x4d,0x44,0x78,0x28,0x3c,0x9e,0xfd,0x65,0x57,0x16,0x94,0x6b,0xfb,0x59,0xd0,0xc8,
    0x22,0x36,0xdb,0xd2,0x63,0x98,0x43,0xa1,0x04,0x87,0x86,0xf7,0xa6,0x26,0xbb,0xd6,
    0x59,0x4d,0xbf,0x6a,0x2e,0xaa,0x2b,0xef,0xe6,0x78,0xb6,0x4e,0xe0,0x2f,0xdc,0x7c,
    0xbe,0x57,0x19,0x32,0x7e,0x2a,0xd0,0xb8,0xba,0x29,0x00,0x3c,0x52,0x7d,0xa8,0x49,
    0x3b,0x2d,0xeb,0x25,0x49,0xfa,0xa3,0xaa,0x39,0xa7,0xc5,0xa7,0x50,0x11,0x36,0xfb,
    0xc6,0x67,0x4a,0xf5,0xa5,0x12,0x65,0x7e,0xb0,0xdf,0xaf,0x4e,0xb3,0x61,0x7f,0x2f ]
);

# decrypt Nikon data block (ref 4)
# Inputs: 0) reference to data block, 1) serial number key, 2) shutter count key
#         4) optional start offset (default 0)
#         5) optional number of bytes to decode (default to the end of the data)
# Returns: data block with specified data decrypted
sub Decrypt($$$;$$)
{
    my ($dataPt, $serial, $count, $start, $len) = @_;
    my ($i, $dat);

    $start or $start = 0;
    $len = length($$dataPt) - $start if not defined $len or $len > length($$dataPt) - $start;
    return $$dataPt if $len <= 0;
    my $key = 0;
    for ($i=0; $i<4; ++$i) {
        $key ^= ($count >> ($i*8)) & 0xff;
    }
    my $ci = $xlat[0][$serial & 0xff];
    my $cj = $xlat[1][$key];
    my $ck = 0x60;
    my @data = unpack("x${start}C$len", $$dataPt);
    foreach $dat (@data) {
        $cj = ($cj + $ci * $ck) & 0xff;
        $ck = ($ck + 1) & 0xff;
        $dat ^= $cj;
    }
    my $end = $start + $len;
    my $pre = $start ? substr($$dataPt, 0, $start) : '';
    my $post = $end < length($$dataPt) ? substr($$dataPt, $end) : '';
    return $pre . pack('C*',@data) . $post;
}

#------------------------------------------------------------------------------
# Read/Write Nikon Encrypted data block
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success when reading, or new directory when writing (IsWriting set)
sub ProcessNikonEncrypted($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    $exifTool or return 1;    # allow dummy access
    my $serial = $exifTool->{NikonSerialNumber};
    my $count = $exifTool->{NikonShutterCount};
    unless (defined $count) {
        if (defined $serial) {
            $exifTool->Warn("Can't decrypt Nikon information (no ShutterCount key)");
            delete $exifTool->{NikonSerialNumber};
        }
        return 0;
    }
    my $verbose = $$dirInfo{IsWriting} ? 0 : $exifTool->Options('Verbose');
    my $tagInfo = $$dirInfo{TagInfo};
    my $data = substr(${$$dirInfo{DataPt}}, $$dirInfo{DirStart}, $$dirInfo{DirLen});

    my ($start, $len, $offset, $byteOrder);

    if ($tagInfo and $$tagInfo{SubDirectory}) {
        $start = $tagInfo->{SubDirectory}->{DecryptStart};
        # may decrypt only part of the information to save time
        if ($verbose < 3 and $exifTool->Options('Unknown') < 2) {
            $len = $tagInfo->{SubDirectory}->{DecryptLen};
        }
        $offset = $tagInfo->{SubDirectory}->{DirOffset};
        $byteOrder = $tagInfo->{SubDirectory}->{ByteOrder};
    }
    $start or $start = 0;
    if (defined $offset) {
        # offset, if specified, is releative to start of encrypted data
        $offset += $start;
    } else {
        $offset = 0;
    }
    my $maxLen = length($data) - $start;
    # decrypt all the data unless DecryptLen is given
    $len = $maxLen unless $len and $len <= $maxLen;
    # use fixed serial numbers if no good serial number found
    unless ($serial =~ /^\d+$/) {
        if ($exifTool->{Model} =~ /\bD50$/) {
            $serial = 0x22; # D50 (ref 8)
        } else {
            $serial = 0x60; # D200 (ref 10), D40X (ref PH)
        }
    }
    $data = Decrypt(\$data, $serial, $count, $start, $len);

    if ($verbose > 2) {
        $exifTool->VerboseDir("Decrypted $$tagInfo{Name}");
        my %parms = (
            Prefix  => $exifTool->{INDENT} . '  ',
            Out     => $exifTool->Options('TextOut'),
            DataPos => $$dirInfo{DirStart} + $$dirInfo{DataPos} + ($$dirInfo{Base} || 0),
        );
        $parms{MaxLen} = 96 unless $verbose > 3;
        Image::ExifTool::HexDump(\$data, undef, %parms);
    }
    # process the decrypted information
    my %subdirInfo = (
        DataPt   => \$data,
        DirStart => $offset,
        DirLen   => length($data) - $offset,
        DirName  => $$dirInfo{DirName},
        DataPos  => $$dirInfo{DataPos} + $$dirInfo{DirStart},
        Base     => $$dirInfo{Base},
    );
    my $rtnVal;
    my $oldOrder = GetByteOrder();
    SetByteOrder($byteOrder) if $byteOrder;
    if ($$dirInfo{IsWriting}) {
        my $changed = $$exifTool{CHANGED};
        $rtnVal = $exifTool->WriteBinaryData(\%subdirInfo, $tagTablePtr);
        if ($changed == $$exifTool{CHANGED}) {
            undef $rtnVal;  # nothing changed so use original data
        } else {
            # re-encrypt data (symmetrical algorithm)
            $rtnVal = Decrypt(\$rtnVal, $serial, $count, $start, $len);
        }
    } else {
        $rtnVal = $exifTool->ProcessBinaryData(\%subdirInfo, $tagTablePtr);
    }
    SetByteOrder($oldOrder);
    return $rtnVal;
}

#------------------------------------------------------------------------------
# Pre-scan EXIF directory to extract specific tags
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) required tagID hash ref
# Returns: 1 if directory was scanned successfully
sub PrescanExif($$$)
{
    my ($exifTool, $dirInfo, $tagHash) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dataPos = $$dirInfo{DataPos} || 0;
    my $dataLen = $$dirInfo{DataLen};
    my $dirStart = $$dirInfo{DirStart} || 0;
    my $base = $$dirInfo{Base} || 0;
    my $raf = $$dirInfo{RAF};
    my ($index, $numEntries, $data, $buff);

    # get number of entries in IFD
    if ($dirStart >= 0 and $dirStart <= $dataLen-2) {
        $numEntries = Get16u($dataPt, $dirStart);
        # reset $numEntries to read from file if necessary
        undef $numEntries if $dirStart + 2 + 12 * $numEntries > $dataLen; 
    }
    # read IFD from file if necessary
    unless ($numEntries) {
        $raf or return 0;
        $dataPos += $dirStart;  # read data from the start of the directory
        $raf->Seek($dataPos + $base, 0) and $raf->Read($data, 2) == 2 or return 0;
        $numEntries = Get16u(\$data, 0);
        my $len = 12 * $numEntries;
        $raf->Read($buff, $len) == $len or return 0;
        $data .= $buff;
        # update variables for the newly loaded IFD (already updated dataPos)
        $dataPt = \$data;
        $dataLen = length $data;
        $dirStart = 0;
    }
    # loop through necessary IFD entries
    my ($lastTag) = sort { $b <=> $a } keys %$tagHash; # (reverse sort)
    for ($index=0; $index<$numEntries; ++$index) {
        my $entry = $dirStart + 2 + 12 * $index;
        my $tagID = Get16u($dataPt, $entry);
        last if $tagID > $lastTag;  # (assuming tags are in order)
        next unless exists $$tagHash{$tagID};   # only extract required tags
        my $format = Get16u($dataPt, $entry+2);
        next if $format < 1 or $format > 13;
        my $count = Get32u($dataPt, $entry+4);
        my $size = $count * $Image::ExifTool::Exif::formatSize[$format];
        my $formatStr = $Image::ExifTool::Exif::formatName[$format];
        my $valuePtr = $entry + 8;      # pointer to value within $$dataPt
        if ($size > 4) {
            next if $size > 0x1000000;  # set a reasonable limit on data size (16MB)
            $valuePtr = Get32u($dataPt, $valuePtr);
            # convert offset to pointer in $$dataPt
            # (don't yet handle EntryBased or FixOffsets)
            $valuePtr -= $dataPos;
            if ($valuePtr < 0 or $valuePtr+$size > $dataLen) {
                next unless $raf and $raf->Seek($base + $valuePtr + $dataPos,0) and
                                     $raf->Read($buff,$size) == $size;
                $$tagHash{$tagID} = ReadValue(\$buff,0,$formatStr,$count,$size);
                next;
            }
        }
        $$tagHash{$tagID} = ReadValue($dataPt,$valuePtr,$formatStr,$count,$size);
    }
    return 1;
}

#------------------------------------------------------------------------------
# process Nikon Capture Offsets IFD (ref PH)
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success
# Notes: This isn't a normal IFD, but is close...
sub ProcessNikonCaptureOffsets($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dirStart = $$dirInfo{DirStart};
    my $dirLen = $$dirInfo{DirLen};
    my $success = 0;
    return 0 unless $dirLen > 2;
    my $count = Get16u($dataPt, $dirStart);
    return 0 unless $count and $count * 12 + 2 <= $dirLen;
    if ($exifTool->Options('Verbose')) {
        $exifTool->VerboseDir('NikonCaptureOffsets', $count);
    }
    my $index;
    for ($index=0; $index<$count; ++$index) {
        my $pos = $dirStart + 12 * $index + 2;
        my $tagID = Get32u($dataPt, $pos);
        my $value = Get32u($dataPt, $pos + 4);
        $exifTool->HandleTag($tagTablePtr, $tagID, $value,
            Index  => $index,
            DataPt => $dataPt,
            Start  => $pos,
            Size   => 12,
        ) and $success = 1;
    }
    return $success;
}

#------------------------------------------------------------------------------
# Read/write Nikon Makernotes directory
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success, otherwise returns 0 and sets a Warning when reading
#          or new directory when writing (IsWriting set in dirInfo)
sub ProcessNikon($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    $exifTool or return 1;    # allow dummy access
    my $verbose = $exifTool->Options('Verbose');
    my $nikonInfo = $exifTool->{NikonInfo} = { };

    # pre-scan IFD to get SerialNumber (0x001d) and ShutterCount (0x00a7) for use in decryption
    my %needTags = ( 0x001d => 0, 0x00a7 => undef );
    PrescanExif($exifTool, $dirInfo, \%needTags);
    my $serial = $needTags{0x001d};
    unless ($serial =~ /^\d+$/) {
        if ($exifTool->{Model} =~ /\bD50$/) {
            $serial = 0x22; # D50 (ref 8)
        } else {
            $serial = 0x60; # D200 (ref 10), D40X (ref PH)
        }
    }
    $exifTool->{NikonSerialNumber} = $serial;
    $exifTool->{NikonShutterCount} = $needTags{0x00a7};

    # process Nikon makernotes
    my $rtnVal;
    if ($$dirInfo{IsWriting}) {
        $rtnVal = Image::ExifTool::Exif::WriteExif($exifTool, $dirInfo, $tagTablePtr);
    } else {
        $rtnVal = Image::ExifTool::Exif::ProcessExif($exifTool, $dirInfo, $tagTablePtr);
    }
    delete $exifTool->{NikonSerialNumber};
    delete $exifTool->{NikonShutterCount};
    return $rtnVal;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::Nikon - Nikon EXIF maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Nikon maker notes in EXIF information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html>

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=item L<http://members.aol.com/khancock/pilot/nbuddy/>

=item L<http://www.rottmerhusen.com/objektives/lensid/thirdparty.html>

=item L<http://homepage3.nifty.com/kamisaka/makernote/makernote_nikon.htm>

=item L<http://www.wohlberg.net/public/software/photo/nstiffexif/>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Joseph Heled, Thomas Walter, Brian Ristuccia, Danek Duvall, Tom
Christiansen, Robert Rottmerhusen, Werner Kober, Roger Larsson, Jens Duttke,
Gregor Dorlars, Neil Nappe and Alexandre Naaman for their help figuring out
some Nikon tags, and Bruce Stevens, Vladimir Sauta and Tanel Kuusk for their
additions to the LensID list.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Nikon Tags>,
L<Image::ExifTool::TagNames/NikonCapture Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
