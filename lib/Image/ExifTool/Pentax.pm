#------------------------------------------------------------------------------
# File:         Pentax.pm
#
# Description:  Pentax/Asahi EXIF maker notes tags
#
# Revisions:    11/25/2003 - P. Harvey Created
#               02/10/2004 - P. Harvey Completely re-done
#               02/16/2004 - W. Smith Updated (see ref 3)
#               11/10/2004 - P. Harvey Added support for Asahi cameras
#               01/10/2005 - P. Harvey Added LensType with values from ref 4
#               03/30/2005 - P. Harvey Added new tags from ref 5
#               10/04/2005 - P. Harvey Added MOV tags
#               10/22/2007 - P. Harvey Got my new K10D! (more new tags to decode)
#
# References:   1) Image::MakerNotes::Pentax
#               2) http://johnst.org/sw/exiftags/ (Asahi cameras)
#               3) Wayne Smith private communication (Optio 550)
#               4) http://kobe1995.jp/~kaz/astro/istD.html
#               5) John Francis (http://www.panix.com/~johnf/raw/index.html) (ist-D/ist-DS)
#               6) http://www.cybercom.net/~dcoffin/dcraw/
#               7) Douglas O'Brien private communication (*istD, K10D)
#               8) Denis Bourez private communication
#               9) Kazumichi Kawabata private communication
#              10) David Buret private communication (*istD)
#              11) http://forums.dpreview.com/forums/read.asp?forum=1036&message=17465929
#              12) Derby Chang private communication
#              13) http://homepage3.nifty.com/kamisaka/makernote/makernote_pentax.htm (2007/02/28)
#              14) Ger Vermeulen private communication (Optio S6)
#              15) Barney Garrett private communication (Samsung GX-1S)
#              16) Axel Kellner private communication (K10D)
#              17) Cvetan Ivanov private communication (K100D)
#              18) http://www.gvsoft.homedns.org/exif/makernote-pentax-type3.html
#              19) Dave Nicholson private communication (K10D)
#              20) Bogdan and yeryry (http://www.cpanforum.com/posts/8037)
#              21) Peter (*istD, http://www.cpanforum.com/posts/8078)
#              JD) Jens Duttke private communication
#
# Notes:        See POD documentation at the bottom of this file
#------------------------------------------------------------------------------

package Image::ExifTool::Pentax;

use strict;
use vars qw($VERSION);
use Image::ExifTool::Exif;
use Image::ExifTool::HP;

$VERSION = '1.84';

sub CryptShutterCount($$);

# pentax lens type codes (ref 4)
# The first number gives the lens series, and the 2nd gives the model number
# Series numbers: K=1; A=2; F=3; FAJ,DFA=4; FA=3,4,5,6; FA*=5,6; DA=3,4,7; DA*=7,8
my %pentaxLensType = (
    Notes => q{
        The first number gives the series of the lens, and the second identifies the
        lens model.  Note that newer series numbers may not always be properly
        identified by cameras running older firmware versions.
    },
    '0 0' => 'M-42 or No Lens', #17
    '1 0' => 'K,M Lens',
    '2 0' => 'A Series Lens', #7 (from smc PENTAX-A 400mm F5.6)
    '3 0' => 'SIGMA',
    '3 17' => 'smc PENTAX-FA SOFT 85mm F2.8',
    '3 18' => 'smc PENTAX-F 1.7X AF ADAPTER',
    '3 19' => 'smc PENTAX-F 24-50mm F4',
    '3 20' => 'smc PENTAX-F 35-80mm F4-5.6',
    '3 21' => 'smc PENTAX-F 80-200mm F4.7-5.6',
    '3 22' => 'smc PENTAX-F FISH-EYE 17-28mm F3.5-4.5',
    '3 23' => 'smc PENTAX-F 100-300mm F4.5-5.6',
    '3 24' => 'smc PENTAX-F 35-135mm F3.5-4.5',
    '3 25' => 'smc PENTAX-F 35-105mm F4-5.6 or SIGMA or Tokina',
    # or '3 25' => SIGMA AF 28-300 F3.5-5.6 DL IF', #11
    # or '3 25' => 'Tokina 80-200mm F2.8 ATX-Pro', #12
    # or '3 25' => 'SIGMA 55-200mm F4-5.6 DC', #JD
    '3 26' => 'smc PENTAX-F* 250-600mm F5.6 ED[IF]',
    '3 27' => 'smc PENTAX-F 28-80mm F3.5-4.5',
    # or '3 27' => 'Tokina AT-X Pro AF 28-70mm F2.6-2.8', #JD
    '3 28' => 'smc PENTAX-F 35-70mm F3.5-4.5',
    # or '3 28' => 'Tokina 19-35mm F3.5-4.5 AF', #12
    '3 29' => 'PENTAX-F 28-80mm F3.5-4.5 or SIGMA AF 18-125mm F3.5-5.6 DC', #11 (sigma)
    '3 30' => 'PENTAX-F 70-200mm F4-5.6',
    '3 31' => 'smc PENTAX-F 70-210mm F4-5.6',
    # or '3 31' => 'Tokina AF 730 75-300mm F4.5-5.6',
    '3 32' => 'smc PENTAX-F 50mm F1.4',
    '3 33' => 'smc PENTAX-F 50mm F1.7',
    '3 34' => 'smc PENTAX-F 135mm F2.8 [IF]',
    '3 35' => 'smc PENTAX-F 28mm F2.8',
    '3 36' => 'SIGMA 20mm F1.8 EX DG ASPHERICAL RF',
    '3 38' => 'smc PENTAX-F* 300mm F4.5 ED[IF]',
    '3 39' => 'smc PENTAX-F* 600mm F4 ED[IF]',
    '3 40' => 'smc PENTAX-F MACRO 100mm F2.8',
    '3 41' => 'smc PENTAX-F MACRO 50mm F2.8 or Sigma 50mm F2,8 MACRO', #4,16
    #'3 44' => 'SIGMA 17-70mm F2.8-4.5 DC MACRO', (Bart Hickman)
    #'3 44' => 'SIGMA 18-50mm F3.5-5.6 DC, 12-24mm F4.5 EX DG or Tamron 35-90mm F4 AF', #4,12,12
    #'3 44' => 'SIGMA AF 10-20mm F4-5.6 EX DC', #JD
    '3 44' => 'Tamron 35-90mm F4 AF or various SIGMA models', #4,12,Bart,JD
    '3 46' => 'SIGMA APO 70-200mm F2.8 EX or EX APO 100-300mm F4 IF', #JD(100-300)
    '3 50' => 'smc PENTAX-FA 28-70mm F4 AL',
    '3 51' => 'SIGMA 28mm F1.8 EX DG ASPHERICAL MACRO',
    '3 52' => 'smc PENTAX-FA 28-200mm F3.8-5.6 AL[IF]',
    # or '3 52' => 'Tamron AF LD 28-200mm F3.8-5.6 (IF) Aspherical (171D), #JD
    '3 53' => 'smc PENTAX-FA 28-80mm F3.5-5.6 AL',
    '3 247' => 'smc PENTAX-DA FISH-EYE 10-17mm F3.5-4.5 ED[IF]',
    '3 248' => 'smc PENTAX-DA 12-24mm F4 ED AL[IF]',
    '3 250' => 'smc PENTAX-DA 50-200mm F4-5.6 ED',
    '3 251' => 'smc PENTAX-DA 40mm F2.8 Limited',
    '3 252' => 'smc PENTAX-DA 18-55mm F3.5-5.6 AL',
    '3 253' => 'smc PENTAX-DA 14mm F2.8 ED[IF]',
    '3 254' => 'smc PENTAX-DA 16-45mm F4 ED AL',
    '3 255' => 'SIGMA',
    # '3 255' => 'SIGMA 18-200mm F3.5-6.3 DC', #8
    # '3 255' => 'SIGMA DL-II 35-80mm F4-5.6', #12
    # '3 255' => 'SIGMA DL Zoom 75-300mm F4-5.6', #12
    # '3 255' => 'SIGMA DF EX Aspherical 28-70mm F2.8', #12
    # '3 255' => 'SIGMA AF Tele 400mm F5.6 Multi-coated', #JD
    '4 1' => 'smc PENTAX-FA SOFT 28mm F2.8',
    '4 2' => 'smc PENTAX-FA 80-320mm F4.5-5.6',
    '4 3' => 'smc PENTAX-FA 43mm F1.9 Limited',
    '4 6' => 'smc PENTAX-FA 35-80mm F4-5.6',
    '4 12' => 'smc PENTAX-FA 50mm F1.4', #17
    '4 15' => 'smc PENTAX-FA 28-105mm F4-5.6 [IF]',
    '4 16' => 'TAMRON AF 80-210mm F4-5.6 (178D)', #13
    '4 19' => 'TAMRON SP AF 90mm F2.8 (172E)',
    '4 20' => 'smc PENTAX-FA 28-80mm F3.5-5.6',
    '4 21' => 'Cosina AF 100-300mm F5.6-6.7', #20
    '4 22' => 'TOKINA 28-80mm F3.5-5.6', #13
    '4 23' => 'smc PENTAX-FA 20-35mm F4 AL',
    '4 24' => 'smc PENTAX-FA 77mm F1.8 Limited',
    '4 25' => 'TAMRON SP AF 14mm F2.8', #13
    '4 26' => 'smc PENTAX-FA MACRO 100mm F3.5',
    '4 27' => 'TAMRON AF28-300mm F/3.5-6.3 LD Aspherical[IF] MACRO (185D/285D)',
    '4 28' => 'smc PENTAX-FA 35mm F2 AL',
    '4 29' => 'TAMRON AF 28-200mm F/3.8-5.6 LD Super II MACRO (371D)', #JD
    '4 34' => 'smc PENTAX-FA 24-90mm F3.5-4.5 AL[IF]',
    '4 35' => 'smc PENTAX-FA 100-300mm F4.7-5.8',
    '4 36' => 'TAMRON AF70-300mm F/4-5.6 LD MACRO', # both 572D and A17 (Di) - ref JD
    '4 37' => 'TAMRON SP AF 24-135mm F3.5-5.6 AD AL (190D)', #13
    '4 38' => 'smc PENTAX-FA 28-105mm F3.2-4.5 AL[IF]',
    '4 39' => 'smc PENTAX-FA 31mm F1.8AL Limited',
    '4 41' => 'TAMRON AF 28-200mm Super Zoom F3.8-5.6 Aspherical XR [IF] MACRO (A03)',
    '4 43' => 'smc PENTAX-FA 28-90mm F3.5-5.6',
    '4 44' => 'smc PENTAX-FA J 75-300mm F4.5-5.8 AL',
    '4 45' => 'TAMRON 28-300mm F3.5-6.3 Ultra zoom XR',
    '4 46' => 'smc PENTAX-FA J 28-80mm F3.5-5.6 AL',
    '4 47' => 'smc PENTAX-FA J 18-35mm F4-5.6 AL',
    '4 49' => 'TAMRON SP AF 28-75mm F2.8 XR Di (A09)',
    '4 51' => 'smc PENTAX-D FA 50mm F2.8 MACRO',
    '4 52' => 'smc PENTAX-D FA 100mm F2.8 MACRO',
    '4 230' => 'Tamron SP AF 17-50mm F/2.8 XR Di II', #20
    '4 231' => 'smc PENTAX-DA 18-250mm F3.5-6.3 ED AL [IF]', #21
    '4 243' => 'smc PENTAX-DA 70mm F2.4 Limited', #JD
    '4 244' => 'smc PENTAX-DA 21mm F3.2 AL Limited', #9
    '4 245' => 'Schneider D-XENON 50-200mm', #15
    '4 246' => 'Schneider D-XENON 18-55mm', #15
    '4 247' => 'smc PENTAX-DA FISH-EYE 10-17mm F3.5-4.5 ED[IF]', #10
    '4 248' => 'smc PENTAX-DA 12-24mm F4 ED AL [IF]', #10
    '4 249' => 'TAMRON XR DiII 18-200mm F3.5-6.3 (A14)',
    '4 250' => 'smc PENTAX-DA 50-200mm F4-5.6 ED', #8
    '4 251' => 'smc PENTAX-DA 40mm F2.8 Limited', #9
    '4 252' => 'smc PENTAX-DA 18-55mm F3.5-5.6 AL', #8
    '4 253' => 'smc PENTAX-DA 14mm F2.8 ED[IF]',
    '4 254' => 'smc PENTAX-DA 16-45mm F4 ED AL',
    '5 1' => 'smc PENTAX-FA* 24mm F2 AL[IF]',
    '5 2' => 'smc PENTAX-FA 28mm F2.8 AL',
    '5 3' => 'smc PENTAX-FA 50mm F1.7',
    '5 4' => 'smc PENTAX-FA 50mm F1.4',
    '5 5' => 'smc PENTAX-FA* 600mm F4 ED[IF]',
    '5 6' => 'smc PENTAX-FA* 300mm F4.5 ED[IF]',
    '5 7' => 'smc PENTAX-FA 135mm F2.8 [IF]',
    '5 8' => 'smc PENTAX-FA MACRO 50mm F2.8',
    '5 9' => 'smc PENTAX-FA MACRO 100mm F2.8',
    '5 10' => 'smc PENTAX-FA* 85mm F1.4 [IF]',
    '5 11' => 'smc PENTAX-FA* 200mm F2.8 ED[IF]',
    '5 12' => 'smc PENTAX-FA 28-80mm F3.5-4.7',
    '5 13' => 'smc PENTAX-FA 70-200mm F4-5.6',
    '5 14' => 'smc PENTAX-FA* 250-600mm F5.6 ED[IF]',
    '5 15' => 'smc PENTAX-FA 28-105mm F4-5.6',
    '5 16' => 'smc PENTAX-FA 100-300mm F4.5-5.6',
    '6 1' => 'smc PENTAX-FA* 85mm F1.4 [IF]',
    '6 2' => 'smc PENTAX-FA* 200mm F2.8 ED[IF]',
    '6 3' => 'smc PENTAX-FA* 300mm F2.8 ED[IF]',
    '6 4' => 'smc PENTAX-FA* 28-70mm F2.8 AL',
    '6 5' => 'smc PENTAX-FA* 80-200mm F2.8 ED[IF]',
    '6 6' => 'smc PENTAX-FA* 28-70mm F2.8 AL',
    '6 7' => 'smc PENTAX-FA* 80-200mm F2.8 ED[IF]',
    '6 8' => 'smc PENTAX-FA 28-70mm F4AL',
    '6 9' => 'smc PENTAX-FA 20mm F2.8',
    '6 10' => 'smc PENTAX-FA* 400mm F5.6 ED[IF]',
    '6 13' => 'smc PENTAX-FA* 400mm F5.6 ED[IF]',
    '6 14' => 'smc PENTAX-FA* MACRO 200mm F4 ED[IF]',
    '7 0' => 'smc PENTAX-DA 21mm F3.2 AL Limited', #13
    '7 229' => 'smc PENTAX-DA 18-55mm F3.5-5.6 AL II', #JD
    '7 230' => 'Tamron AF 17-50mm F2.8 XR Di-II LD (Model A16)', #JD
    '7 231' => 'smc PENTAX-DA 18-250mm F3.5-6.3 ED AL [IF]', #JD
    '7 233' => 'smc PENTAX-DA 35mm F2.8 Macro Limited', #JD
    '7 234' => 'smc PENTAX-DA* 300mm F4 ED [IF] SDM (SDM unused)', #19 (NC)
    '7 235' => 'smc PENTAX-DA* 200mm F2.8 ED [IF] SDM (SDM unused)', #PH (NC)
    '7 236' => 'smc PENTAX-DA 55-300mm f/4-5.8 ED', #JD
    '7 238' => 'TAMRON AF 18-250mm F3.5-6.3 Di II LD Aspherical [IF] MACRO', #JD
    '7 241' => 'smc PENTAX-DA* 50-135mm F2.8 ED [IF] SDM (SDM unused)', #PH
    '7 242' => 'smc PENTAX-DA* 16-50mm F2.8 ED AL [IF] SDM (SDM unused)', #19
    '7 243' => 'smc PENTAX-DA 70mm F2.4 Limited', #PH
    '7 244' => 'smc PENTAX-DA 21mm F3.2 AL Limited', #16
    '8 234' => 'smc PENTAX-DA* 300mm F4 ED [IF] SDM', #19
    '8 235' => 'smc PENTAX-DA* 200mm F2.8 ED [IF] SDM', #JD
    '8 241' => 'smc PENTAX-DA* 50-135mm F2.8 ED [IF] SDM', #JD
    '8 242' => 'smc PENTAX-DA* 16-50mm F2.8 ED AL [IF] SDM', #JD
);

# Pentax model ID codes - PH
my %pentaxModelID = (
    0x0000d => 'Optio 330/430',
    0x12926 => 'Optio 230',
    0x12958 => 'Optio 330GS',
    0x12962 => 'Optio 450/550',
    0x1296c => 'Optio S',
    0x12994 => '*ist D',
    0x129b2 => 'Optio 33L',
    0x129bc => 'Optio 33LF',
    0x129c6 => 'Optio 33WR/43WR/555',
    0x129d5 => 'Optio S4',
    0x12a02 => 'Optio MX',
    0x12a0c => 'Optio S40',
    0x12a16 => 'Optio S4i',
    0x12a34 => 'Optio 30',
    0x12a52 => 'Optio S30',
    0x12a66 => 'Optio 750Z',
    0x12a70 => 'Optio SV',
    0x12a75 => 'Optio SVi',
    0x12a7a => 'Optio X',
    0x12a8e => 'Optio S5i',
    0x12a98 => 'Optio S50',
    0x12aa2 => '*ist DS',
    0x12ab6 => 'Optio MX4',
    0x12ac0 => 'Optio S5n',
    0x12aca => 'Optio WP',
    0x12afc => 'Optio S55',
    0x12b10 => 'Optio S5z',
    0x12b1a => '*ist DL',
    0x12b24 => 'Optio S60',
    0x12b2e => 'Optio S45',
    0x12b38 => 'Optio S6',
    0x12b4c => 'Optio WPi', #13
    0x12b56 => 'BenQ DC X600',
    0x12b60 => '*ist DS2',
    0x12b62 => 'Samsung GX-1S',
    0x12b6a => 'Optio A10',
    0x12b7e => '*ist DL2',
    0x12b80 => 'Samsung GX-1L',
    0x12b9c => 'K100D',
    0x12b9d => 'K110D',
    0x12ba2 => 'K100D Super', #JD
    0x12bb0 => 'Optio T10/T20',
    0x12be2 => 'Optio W10',
    0x12bf6 => 'Optio M10',
    0x12c1e => 'K10D',
    0x12c20 => 'Samsung GX10',
    0x12c28 => 'Optio S7',
    0x12c2d => 'Optio L20',
    0x12c32 => 'Optio M20',
    0x12c3c => 'Optio W20',
    0x12c46 => 'Optio A20',
    0x12c8c => 'Optio M30',
    0x12c78 => 'Optio E30',
    0x12c82 => 'Optio T30',
    0x12c96 => 'Optio W30',
    0x12ca0 => 'Optio A30',
    0x12cb4 => 'Optio E40',
    0x12cbe => 'Optio M40',
    0x12cc8 => 'Optio Z10',
    0x12cd2 => 'K20D',
    0x12cdc => 'Optio S10',
    0x12ce6 => 'Optio A40',
    0x12cf0 => 'Optio V10',
    0x12cfa => 'K200D',
    0x12d0e => 'Optio E50',
    0x12d18 => 'Optio M50',
);

# Pentax city codes - (PH, Optio WP)
my %pentaxCities = (
    0 => 'Pago Pago',
    1 => 'Honolulu',
    2 => 'Anchorage',
    3 => 'Vancouver',
    4 => 'San Fransisco',
    5 => 'Los Angeles',
    6 => 'Calgary',
    7 => 'Denver',
    8 => 'Mexico City',
    9 => 'Chicago',
    10 => 'Miami',
    11 => 'Toronto',
    12 => 'New York',
    13 => 'Santiago',
    14 => 'Caracus',
    15 => 'Halifax',
    16 => 'Buenos Aires',
    17 => 'Sao Paulo',
    18 => 'Rio de Janeiro',
    19 => 'Madrid',
    20 => 'London',
    21 => 'Paris',
    22 => 'Milan',
    23 => 'Rome',
    24 => 'Berlin',
    25 => 'Johannesburg',
    26 => 'Istanbul',
    27 => 'Cairo',
    28 => 'Jerusalem',
    29 => 'Moscow',
    30 => 'Jeddah',
    31 => 'Tehran',
    32 => 'Dubai',
    33 => 'Karachi',
    34 => 'Kabul',
    35 => 'Male',
    36 => 'Delhi',
    37 => 'Colombo',
    38 => 'Kathmandu',
    39 => 'Dacca',
    40 => 'Yangon',
    41 => 'Bangkok',
    42 => 'Kuala Lumpur',
    43 => 'Vientiane',
    44 => 'Singapore',
    45 => 'Phnom Penh',
    46 => 'Ho Chi Minh',
    47 => 'Jakarta',
    48 => 'Hong Kong',
    49 => 'Perth',
    50 => 'Beijing',
    51 => 'Shanghai',
    52 => 'Manila',
    53 => 'Taipei',
    54 => 'Seoul',
    55 => 'Adelaide',
    56 => 'Tokyo',
    57 => 'Guam',
    58 => 'Sydney',
    59 => 'Noumea',
    60 => 'Wellington',
    61 => 'Auckland',
    62 => 'Lima',
    63 => 'Dakar',
    64 => 'Algiers',
    65 => 'Helsinki',
    66 => 'Athens',
    67 => 'Nairobi',
    68 => 'Amsterdam',
    69 => 'Stockholm',
    70 => 'Lisbon', #14
);

# decoding for Pentax Firmware ID tags - PH
my %pentaxFirmwareID = (
    # the first 2 numbers are the firmware version, I'm not sure what the second 2 mean
    # Note: the byte order may be different for some models
    # which give, for example, version 0.01 instead of 1.00
    ValueConv => sub {
        my $val = shift;
        return $val unless length($val) == 4;
        # (value is encrypted by toggling all bits)
        my @a = map { $_ ^ 0xff } unpack("C*",$val);
        return sprintf('%d %.2d %.2d %.2d', @a);
    },
    ValueConvInv => sub {
        my $val = shift;
        my @a = $val=~/\b\d+\b/g;
        return $val unless @a == 4;
        @a = map { ($_ & 0xff) ^ 0xff } @a;
        return pack("C*", @a);
    },
    PrintConv => '$val=~tr/ /./; $val',
    PrintConvInv => '$val=~s/^(\d+)\.(\d+)\.(\d+)\.(\d+)/$1 $2 $3 $4/ ? $val : undef',
);

# convert 16 metering segment values to approximate LV equivalent - PH
my %convertMeteringSegments = (
    PrintConv    => sub { join ' ', map(
        { $_==255 ? 'n/a' : $_==0 ? '0' : sprintf '%.1f', $_ / 8 - 6 } split(' ',$_[0])
    ) },
    PrintConvInv => sub { join ' ', map(
        { /^n/i ? 255 : $_==0 ? '0' : int(($_ + 6) * 8 + 0.5) }        split(' ',$_[0])
    ) },
);

# lens code conversions
my %lensCode = (
    Unknown => 1,
    PrintConv => 'sprintf("0x%.2x", $val)',
    PrintConvInv => 'hex($val)',
);

# Pentax makernote tags
%Image::ExifTool::Pentax::Main = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    0x0000 => { #5
        Name => 'PentaxVersion',
        Writable => 'int8u',
        Count => 4,
        PrintConv => '$val=~tr/ /./; $val',
        PrintConvInv => '$val=~tr/./ /; $val',
    },
    0x0001 => { #PH
        Name => 'PentaxModelType',
        Writable => 'int16u',
        # (values of 0-5 seem to group models into 6 categories, ref 13)
    },
    0x0002 => { #PH
        Name => 'PreviewImageSize',
        Groups => { 2 => 'Image' },
        Writable => 'int16u',
        Count => 2,
        PrintConv => '$val =~ tr/ /x/; $val',
    },
    0x0003 => { #PH
        Name => 'PreviewImageLength',
        OffsetPair => 0x0004, # point to associated offset
        DataTag => 'PreviewImage',
        Groups => { 2 => 'Image' },
        Writable => 'int32u',
        Protected => 2,
    },
    0x0004 => { #PH
        Name => 'PreviewImageStart',
        IsOffset => 2,  # code to use original base
        Protected => 2,
        OffsetPair => 0x0003, # point to associated byte count
        DataTag => 'PreviewImage',
        Groups => { 2 => 'Image' },
        Writable => 'int32u',
    },
    0x0005 => { #13
        Name => 'PentaxModelID',
        Writable => 'int32u',
        PrintHex => 1,
        SeparateTable => 1,
        PrintConv => \%pentaxModelID,
    },
    0x0006 => { #5
        # Note: Year is int16u in MM byte ordering regardless of EXIF byte order
        Name => 'Date',
        Groups => { 2 => 'Time' },
        Notes => 'changing either Date or Time will affect ShutterCount decryption',
        Writable => 'undef',
        Count => 4,
        Shift => 'Time',
        DataMember => 'PentaxDate',
        RawConv => '$$self{PentaxDate} = $val', # save to decrypt ShutterCount
        ValueConv => 'length($val)==4 ? sprintf("%.4d:%.2d:%.2d",unpack("nC2",$val)) : "Unknown ($val)"',
        ValueConvInv => 'my @v=split /:/, $val;pack("nC2",$v[0],$v[1],$v[2])',
    },
    0x0007 => { #5
        Name => 'Time',
        Groups => { 2 => 'Time' },
        Writable => 'undef',
        Count => 3,
        Shift => 'Time',
        DataMember => 'PentaxTime',
        RawConv => '$$self{PentaxTime} = $val', # save to decrypt ShutterCount
        ValueConv => 'length($val)>=3 ? sprintf("%.2d:%.2d:%.2d",unpack("C3",$val)) : "Unknown ($val)"',
        ValueConvInv => 'pack("C3",split(/:/,$val))',
    },
    0x0008 => { #2
        Name => 'Quality',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Good',
            1 => 'Better',
            2 => 'Best',
            3 => 'TIFF', #5
            4 => 'RAW', #5
            5 => 'Premium', #PH (K20D)
        },
    },
    0x0009 => { #3
        Name => 'PentaxImageSize',
        Groups => { 2 => 'Image' },
        Writable => 'int16u',
        PrintConv => {
            0 => '640x480',
            1 => 'Full', #PH - this can mean 2048x1536 or 2240x1680 or ... ?
            2 => '1024x768',
            3 => '1280x960', #PH (Optio WP)
            4 => '1600x1200',
            5 => '2048x1536',
            8 => '2560x1920 or 2304x1728', #PH (Optio WP) or #14
            9 => '3072x2304', #PH (Optio M30)
            10 => '3264x2448', #13
            19 => '320x240', #PH (Optio WP)
            20 => '2288x1712', #13
            21 => '2592x1944',
            22 => '2304x1728 or 2592x1944', #2 or #14
            23 => '3056x2296', #13
            25 => '2816x2212 or 2816x2112', #13 or #14
            27 => '3648x2736', #PH (Optio A20)
            '0 0' => '2304x1728', #13
            '4 0' => '1600x1200', #PH (Optio MX4)
            '5 0' => '2048x1536', #13
            '8 0' => '2560x1920', #13
            '32 2' => '960x640', #7
            '33 2' => '1152x768', #7
            '34 2' => '1536x1024', #7
            '35 1' => '2400x1600', #7
            '36 0' => '3008x2008 or 3040x2024',  #PH
            '37 0' => '3008x2000', #13
        },
    },
    0x000b => { #3
        Name => 'PictureMode',
        Writable => 'int16u',
        Count => -1,
        Notes => '1 or 2 values',
        PrintConv => [{
            0 => 'Program', #PH
            1 => 'Shutter Speed Priority', #JD
            2 => 'Program AE', #13
            3 => 'Manual', #13
            5 => 'Portrait',
            6 => 'Landscape',
            8 => 'Sport', #PH
            9 => 'Night Scene',
            # 10 FURUMODO? #13
            11 => 'Soft', #PH
            12 => 'Surf & Snow',
            13 => 'Candlelight', #13
            14 => 'Autumn',
            15 => 'Macro',
            17 => 'Fireworks',
            18 => 'Text',
            19 => 'Panorama', #PH
            30 => 'Self Portrait', #PH
            31 => 'Illustrations', #13
            33 => 'Digital Filter', #13
            37 => 'Museum', #PH
            38 => 'Food', #PH
            40 => 'Green Mode', #PH
            49 => 'Light Pet', #PH
            50 => 'Dark Pet', #PH
            51 => 'Medium Pet', #PH
            53 => 'Underwater', #PH
            54 => 'Candlelight', #PH
            55 => 'Natural Skin Tone', #PH
            56 => 'Synchro Sound Record', #PH
            58 => 'Frame Composite', #14
            60 => 'Kids', #13
            61 => 'Blur Reduction', #13
            255=> 'Digital Filter?', #13
        }],
    },
    0x000c => { #PH
        Name => 'FlashMode',
        Writable => 'int16u',
        Count => -1,
        PrintHex => 1,
        PrintConv => [{
            0x000 => 'Auto, Did not fire',
            0x001 => 'Off',
            0x002 => 'On, Did not fire', #19
            0x003 => 'Auto, Did not fire, Red-eye reduction',
            0x100 => 'Auto, Fired',
            0x102 => 'On',
            0x103 => 'Auto, Fired, Red-eye reduction',
            0x104 => 'On, Red-eye reduction',
            0x105 => 'On, Wireless (Master)', #19
            0x106 => 'On, Wireless (Control)', #19
            0x108 => 'On, Soft',
            0x109 => 'On, Slow-sync',
            0x10a => 'On, Slow-sync, Red-eye reduction',
            0x10b => 'On, Trailing-curtain Sync',
        },{ #19 (AF-540FGZ flash)
            0x000 => 'n/a - Off-Auto-Aperture', #19
            0x03f => 'Internal',
            0x100 => 'External, Auto',
            0x23f => 'External, Flash Problem', #JD
            0x300 => 'External, Manual',
            0x304 => 'External, P-TTL Auto',
            0x305 => 'External, Contrast-control Sync', #JD
            0x306 => 'External, High-speed Sync',
            0x30c => 'External, Wireless',
            0x30d => 'External, Wireless, High-speed Sync',
        }],
    },
    0x000d => [ #2
        {
            Name => 'FocusMode',
            Condition => '$self->{Make} =~ /^PENTAX/',
            Notes => 'Pentax models',
            Writable => 'int16u',
            PrintConv => { #PH
                0 => 'Normal',
                1 => 'Macro',
                2 => 'Infinity',
                3 => 'Manual',
                4 => 'Super Macro', #JD
                5 => 'Pan Focus',
                16 => 'AF-S', #17
                17 => 'AF-C', #17
            },
        },
        {
            Name => 'FocusMode',
            Writable => 'int16u',
            Notes => 'Asahi models',
            PrintConv => { #2
                0 => 'Normal',
                1 => 'Macro (1)',
                2 => 'Macro (2)',
                3 => 'Infinity',
            },
        },
    ],
    0x000e => { #7
        Name => 'AFPointSelected',
        Writable => 'int16u',
        PrintConv => {
            0xffff => 'Auto',
            0xfffe => 'Fixed Center',
            0xfffd => 'Automatic Tracking AF', #JD
            0xfffc => 'Face Recognition AF', #JD
            1 => 'Upper-left',
            2 => 'Top',
            3 => 'Upper-right',
            4 => 'Left',
            5 => 'Mid-left',
            6 => 'Center',
            7 => 'Mid-right',
            8 => 'Right',
            9 => 'Lower-left',
            10 => 'Bottom',
            11 => 'Lower-right',
        },
    },
    0x000f => { #PH
        Name => 'AFPointsInFocus',
        Writable => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0xffff => 'None',
            0 => 'Fixed Center or Multiple', #PH/14
            1 => 'Top-left',
            2 => 'Top-center',
            3 => 'Top-right',
            4 => 'Left',
            5 => 'Center',
            6 => 'Right',
            7 => 'Bottom-left',
            8 => 'Bottom-center',
            9 => 'Bottom-right',
        },
    },
    0x0010 => { #PH
        Name => 'FocusPosition',
        Writable => 'int16u',
        Notes => 'related to focus distance but affected by focal length',
    },
    0x0012 => { #PH
        Name => 'ExposureTime',
        Writable => 'int32u',
        Priority => 0,
        ValueConv => '$val * 1e-5',
        ValueConvInv => '$val * 1e5',
        # value may be 0xffffffff in Bulb mode (ref JD)
        PrintConv => '$val > 42949 ? "Unknown (Bulb)" : Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => '$val=~/(unknown|bulb)/i ? $val : eval $val',
    },
    0x0013 => { #PH
        Name => 'FNumber',
        Writable => 'int16u',
        Priority => 0,
        ValueConv => '$val / 10',
        ValueConvInv => '$val * 10',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    # ISO Tag - Entries confirmed by W. Smith 12 FEB 04
    0x0014 => {
        Name => 'ISO',
        Writable => 'int16u',
        Notes => 'may be different than EXIF:ISO, which can round to the nearest full stop',
        PrintConv => {
            3 => 50, #(NC=Not Confirmed)
            4 => 64,
            5 => 80, #(NC)
            6 => 100,
            7 => 125, #PH
            8 => 160, #PH
            9 => 200,
            10 => 250,
            11 => 320, #PH
            12 => 400,
            13 => 500,
            14 => 640,
            15 => 800,
            16 => 1000,
            17 => 1250,
            18 => 1600, #PH
            19 => 2000, #PH (NC)
            20 => 2500, #PH (NC)
            21 => 3200, #(NC)
            22 => 4000, #(NC)
            23 => 5000, #(NC)
            24 => 6400, #PH (K20D)
            50 => 50, #PH
            100 => 100, #PH
            200 => 200, #PH
            400 => 400, #PH
            800 => 800, #PH
            1600 => 1600, #PH
            3200 => 3200, #PH
            258 => 50, #PH (NC)
            259 => 70, #PH (NC)
            260 => 100, #19
            261 => 140, #19
            262 => 200, #19
            263 => 280, #19
            264 => 400, #19
            265 => 560, #19
            266 => 800, #19
            267 => 1100, #19
            268 => 1600, #19
            269 => 2200, #PH (NC)
            270 => 3200, #PH (NC)
        },
    },
    0x0015 => { #PH
        Name => 'LightReading',
        Format => 'int16s', # (because I may have seen negative numbers)
        Writable => 'int16u',
        # ranges from 0-12 for my Optio WP - PH
        Notes => q{
            calibrated differently for different models.  For the Optio WP, add 6 to get
            approximate Light Value.  May not be valid for some models, ie. Optio S
        },
    },
    0x0016 => { #PH
        Name => 'ExposureCompensation',
        Writable => 'int16u',
        ValueConv => '($val - 50) / 10',
        ValueConvInv => 'int($val * 10 + 50.5)',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
    0x0017 => { #3
        Name => 'MeteringMode',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Multi-segment',
            1 => 'Center-weighted average',
            2 => 'Spot',
        },
    },
    0x0018 => { #PH
        Name => 'AutoBracketing',
        Writable => 'int16u',
        Count => -1,
        Notes => q{
            1 or 2 values: exposure bracket step in EV, then extended bracket if
            available.  Extended bracket values are printed as 'WB-BA', 'WB-GM',
            'Saturation', 'Sharpness' or 'Contrast' followed by '+1', '+2' or '+3' for
            step size
        },
        # 1=.3ev, 2=.7, 3=1.0, ... 10=.5ev, 11=1.5, ...
        ValueConv => [ '$val<10 ? $val/3 : $val-9.5' ],
        ValueConvInv => [ 'abs($val-int($val)-.5)>0.05 ? int($val*3+0.5) : int($val+10)' ],
        PrintConv => sub {
            my @v = split(' ', shift);
            $v[0] = sprintf('%.1f', $v[0]) if $v[0];
            if ($v[1]) {
                my %s = (1=>'WB-BA',2=>'WB-GM',3=>'Saturation',4=>'Sharpness',5=>'Contrast');
                my $t = $v[1] >> 8;
                $v[1] = sprintf('%s+%d', $s{$t} || "Unknown($t)", $v[1] & 0xff);
            } elsif (defined $v[1]) {
                $v[1] = 'No Extended Bracket',
            }
            return join(' EV, ', @v);
        },
        PrintConvInv => sub {
            my @v = split(/, ?/, shift);
            $v[0] =~ s/ ?EV//i;
            if ($v[1]) {
                my %s = ('WB-BA'=>1,'WB-GM'=>2,Saturation=>3,Sharpness=>4,Contrast=>5);
                if ($v[1] =~ /^No\b/i) {
                    $v[1] = 0;
                } elsif ($v[1] =~ /Unknown\((\d+)\)\+(\d+)/i) {
                    $v[1] = ($1 << 8) + $2;
                } elsif ($v[1] =~ /([\w-]+)\+(\d+)/ and $s{$1}) {
                    $v[1] = ($s{$1} << 8) + $2;
                } else {
                    warn "Bad extended bracket\n";
                }
            }
            return "@v";
        },
    },
    0x0019 => { #3
        Name => 'WhiteBalance',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Shade',
            3 => 'Fluorescent', #2
            4 => 'Tungsten',
            5 => 'Manual',
            6 => 'DaylightFluorescent', #13
            7 => 'DaywhiteFluorescent', #13
            8 => 'WhiteFluorescent', #13
            9 => 'Flash', #13
            10 => 'Cloudy', #13
            17 => 'Kelvin', #PH
            0xfffe => 'Unknown', #13
            0xffff => 'User-Selected', #13
        },
    },
    0x001a => { #5
        Name => 'WhiteBalanceMode',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Auto (Daylight)',
            2 => 'Auto (Shade)',
            3 => 'Auto (Flash)',
            4 => 'Auto (Tungsten)',
            6 => 'Auto (DaylightFluorescent)', #19 (NC)
            7 => 'Auto (DaywhiteFluorescent)', #17 (K100D guess)
            8 => 'Auto (WhiteFluorescent)', #17 (K100D guess)
            10 => 'Auto (Cloudy)', #17 (K100D guess)
            # 0xfffd observed in K100D (ref 17)
            0xfffe => 'Unknown', #PH (you get this when shooting night sky shots)
            0xffff => 'User-Selected',
        },
    },
    0x001b => { #6
        Name => 'BlueBalance',
        Writable => 'int16u',
        ValueConv => '$val / 256',
        ValueConvInv => 'int($val * 256 + 0.5)',
    },
    0x001c => { #6
        Name => 'RedBalance',
        Writable => 'int16u',
        ValueConv => '$val / 256',
        ValueConvInv => 'int($val * 256 + 0.5)',
    },
    0x001d => [
        # Would be nice if there was a general way to determine units for FocalLength...
        {
            # Optio 30, 33WR, 43WR, 450, 550, 555, 750Z, X
            Name => 'FocalLength',
            Condition => '$self->{Model} =~ /^PENTAX Optio (30|33WR|43WR|450|550|555|750Z|X)\b/',
            Writable => 'int32u',
            Priority => 0,
            ValueConv => '$val / 10',
            ValueConvInv => '$val * 10',
            PrintConv => 'sprintf("%.1f mm",$val)',
            PrintConvInv => '$val=~s/\s*mm//;$val',
        },
        {
            # K100D, Optio 230, 330GS, 33L, 33LF, A10, M10, MX, MX4, S, S30,
            # S4, S4i, S5i, S5n, S5z, S6, S45, S50, S55, S60, SV, Svi, W10, WP,
            # *ist D, DL, DL2, DS, DS2
            # (Note: the Optio S6 seems to report the minimum focal length - PH)
            Name => 'FocalLength',
            Writable => 'int32u',
            Priority => 0,
            ValueConv => '$val / 100',
            ValueConvInv => '$val * 100',
            PrintConv => 'sprintf("%.1f mm",$val)',
            PrintConvInv => '$val=~s/\s*mm//;$val',
        },
    ],
    0x001e => { #3
        Name => 'DigitalZoom',
        Writable => 'int16u',
        ValueConv => '$val / 100', #14
        ValueConvInv => '$val * 100', #14
    },
    0x001f => {
        Name => 'Saturation',
        Writable => 'int16u',
        Count => -1,
        Notes => '1 or 2 values',
        PrintConv => [{ # the *istD has pairs of values - PH
            0 => 'Low', #PH
            1 => 'Normal', #PH
            2 => 'High', #PH
            3 => 'Med Low', #2
            4 => 'Med High', #2
            5 => 'Very Low', #(NC)
            6 => 'Very High', #(NC)
            65535 => 'None', #PH (Monochrome)
        }],
        # (the K20D supports -4 to +4 -- this needs decoding)
    },
    0x0020 => {
        Name => 'Contrast',
        Writable => 'int16u',
        Count => -1,
        Notes => '1 or 2 values',
        PrintConv => [{ # the *istD has pairs of values - PH
            0 => 'Low', #PH
            1 => 'Normal', #PH
            2 => 'High', #PH
            3 => 'Med Low', #2
            4 => 'Med High', #2
            5 => 'Very Low', #PH
            6 => 'Very High', #(NC)
        }],
    },
    0x0021 => {
        Name => 'Sharpness',
        Writable => 'int16u',
        Count => -1,
        Notes => '1 or 2 values',
        PrintConv => [{ # the *istD has pairs of values - PH
            0 => 'Soft', #PH
            1 => 'Normal', #PH
            2 => 'Hard', #PH
            3 => 'Med Soft', #2
            4 => 'Med Hard', #2
            5 => 'Very Soft', #(NC)
            6 => 'Very Hard', #(NC)
        }],
    },
    0x0022 => { #PH
        Name => 'WorldTimeLocation',
        Groups => { 2 => 'Time' },
        Writable => 'int16u',
        PrintConv => {
            0 => 'Hometown',
            1 => 'Destination',
        },
    },
    0x0023 => { #PH
        Name => 'HometownCity',
        Groups => { 2 => 'Time' },
        Writable => 'int16u',
        SeparateTable => 'City',
        PrintConv => \%pentaxCities,
    },
    0x0024 => { #PH
        Name => 'DestinationCity',
        Groups => { 2 => 'Time' },
        Writable => 'int16u',
        SeparateTable => 'City',
        PrintConv => \%pentaxCities,
    },
    0x0025 => { #PH
        Name => 'HometownDST',
        Groups => { 2 => 'Time' },
        Writable => 'int16u',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    0x0026 => { #PH
        Name => 'DestinationDST',
        Groups => { 2 => 'Time' },
        Writable => 'int16u',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    0x0027 => { #PH
        Name => 'DSPFirmwareVersion',
        Writable => 'undef',
        # - for K10D, this comes from 4 bytes at offset 0x1c in the firmware file
        %pentaxFirmwareID,
    },
    0x0028 => { #PH
        Name => 'CPUFirmwareVersion',
        Writable => 'undef',
        # - for K10D, this comes from 4 bytes at offset 0x83fbf8 in firmware file
        %pentaxFirmwareID,
    },
    0x0029 => { #5
        Name => 'FrameNumber',
        # - one report that this has a value of 84 for the first image with a *istDS
        # - another report that file number 4 has frameNumber 154 for *istD, and
        #   that framenumber jumped at about 9700 to around 26000
        # - with *istDS firmware 2.0, this tag was removed and ShutterCount was added
        Writable => 'int32u',
    },
    # 0x002b - definitely exposure related somehow - PH
    0x002d => { #PH
        Name => 'EffectiveLV',
        Notes => 'camera-calculated light value, but includes exposure compensation',
        Writable => 'int16u',
        ValueConv => '$val/1024',
        ValueConvInv => '$val * 1024',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    0x0032 => { #13
        Name => 'ImageProcessing',
        Writable => 'undef',
        Format => 'int8u',
        Count => 4,
        PrintConv => {
            '0 0' => 'Unprocessed', #PH
            '0 0 0 0' => 'Unprocessed',
            '0 0 0 4' => 'Digital Filter',
            '2 0 0 0' => 'Cropped', #PH
            # K10D gives "4 0 0 0" for any filter (bw,color,soft,slim,bright) - PH
            '4 0 0 0' => 'Color Filter',
            '16 0 0 0' => 'Frame Synthesis?',
        },
    },
    0x0033 => { #PH (K110D/K100D)
        Name => 'PictureMode',
        Writable => 'int8u',
        Count => 3,
        Relist => [ [0, 1], 2 ], # join values 0 and 1 for PrintConv
        PrintConv => [{
            # Program dial modes (from K110D)
            '0 0'  => 'Program',    # (also on K10D, custom settings: Program Line 1, e-dial in Program 3, 4 or 5)
            '0 1'  => 'Hi-speed Program', #19 (K10D, custom settings: Program Line 2, e-dial in Program 3, 4 or 5)
            '0 2'  => 'DOF Program', #19      (K10D, custom settings: Program Line 3, e-dial in Program 3, 4 or 5)
            '0 3'  => 'MTF Program', #19      (K10D, custom settings: Program Line 4, e-dial in Program 3, 4 or 5)
            '0 4'  => 'Standard', #13
            '0 5'  => 'Portrait',
            '0 6'  => 'Landscape',
            '0 7'  => 'Macro',
            '0 8'  => 'Sport',
            '0 9'  => 'Night Scene Portrait',
            '0 10' => 'No Flash',
            # SCN modes (menu-selected) (from K100D)
            '0 11' => 'Night Scene',
            '0 12' => 'Surf & Snow',
            '0 13' => 'Text',
            '0 14' => 'Sunset',
            '0 15' => 'Kids',
            '0 16' => 'Pet',
            '0 17' => 'Candlelight',
            '0 18' => 'Museum',
            # AUTO PICT modes (auto-selected)
            '1 4'  => 'Auto PICT (Standard)', #13
            '1 5'  => 'Auto PICT (Portrait)', #7 (K100D)
            '1 6'  => 'Auto PICT (Landscape)', # K110D
            '1 7'  => 'Auto PICT (Macro)', #13
            '1 8'  => 'Auto PICT (Sport)', #13
            # *istD modes (ref 7)
            '2 0'  => 'Program (HyP)', #13
            '2 1'  => 'Hi-speed Program (HyP)', #19 (K10D, custom settings: Program Line 2, e-dial in Program 1, 2)
            '2 2'  => 'DOF Program (HyP)', #19      (K10D, custom settings: Program Line 3, e-dial in Program 1, 2)
            '2 3'  => 'MTF Program (HyP)', #19      (K10D, custom settings: Program Line 4, e-dial in Program 1, 2)
            '3 0'  => 'Green Mode', #16
            '4 0'  => 'Shutter Speed Priority',
            '5 0'  => 'Aperture Priority',
            '6 0'  => 'Program Tv Shift',
            '7 0'  => 'Program Av Shift', #19
            '8 0'  => 'Manual',
            '9 0'  => 'Bulb',
            '10 0' => 'Aperture Priority, Off-Auto-Aperture',
            '11 0' => 'Manual, Off-Auto-Aperture',
            '12 0' => 'Bulb, Off-Auto-Aperture',
            # extra K10D modes (ref 16)
            '13 0' => 'Shutter & Aperture Priority AE',
            '15 0' => 'Sensitivity Priority AE',
            '16 0' => 'Flash X-Sync Speed AE',
        },{
            # EV step size (ref 19)
            0 => '1/2 EV steps',
            1 => '1/3 EV steps',
        }],
    },
    0x0034 => { #7/PH
        Name => 'DriveMode',
        Writable => 'int8u',
        Count => 4,
        PrintConv => [{
            0 => 'Single-frame',
            1 => 'Continuous',
            2 => 'Continuous (Hi)', #PH (NC) (K200D)
            3 => 'Burst', #PH (K20D)
            # (K20D also has an Interval mode that needs decoding)
        },{
            0 => 'No Timer',
            1 => 'Self-timer (12 s)',
            2 => 'Self-timer (2 s)',
        },{
            0 => 'Shutter Button', # (also computer remote control - PH)
            1 => 'Remote Control (3 s delay)', #19
            2 => 'Remote Control', #19
        },{
            0 => 'Single Exposure',
            1 => 'Multiple Exposure',
        }],
    },
    # 0x0035 - 2 numbers: 11894 7962 (not in JPEG images) - PH
    0x0037 => { #13
        Name => 'ColorSpace',
        Writable => 'int16u',
        PrintConv => {
            0 => 'sRGB',
            1 => 'Adobe RGB',
        },
    },
    0x0038 => { #5 (PEF only)
        Name => 'ImageAreaOffset',
        Writable => 'int16u',
        Count => 2,
    },
    0x0039 => { #PH
        Name => 'RawImageSize',
        Writable => 'int16u',
        Count => 2,
        PrintConv => '$_=$val;s/ /x/;$_',
    },
    0x003c => { #7/PH
        Name => 'AFPointsInFocus',
        # not writable because I'm not decoding these 4 bytes fully:
        # Nibble pattern: XSSSYUUU
        # X = unknown (AF focused flag?, 0 or 1)
        # SSS = selected AF point bitmask (0x000 or 0x7ff if unused)
        # Y = unknown (observed 0,6,7,b,e, always 0 if SSS is 0x000 or 0x7ff)
        # UUU = af points used
        Format => 'int32u',
        Notes => '*istD only',
        ValueConv => '$val & 0x7ff', # ignore other bits for now
        PrintConv => { BITMASK => {
            0 => 'Upper-left',
            1 => 'Top',
            2 => 'Upper-right',
            3 => 'Left',
            4 => 'Mid-left',
            5 => 'Center',
            6 => 'Mid-right',
            7 => 'Right',
            8 => 'Lower-left',
            9 => 'Bottom',
            10 => 'Lower-right',
        } },
    },
    # 0x003d = 8192 for most images, but occasionally 11571 for K100D/K110D - PH
    0x003e => { #PH
        Name => 'PreviewImageBorders',
        Writable => 'int8u',
        Count => 4,
        Notes => 'top, bottom, left, right',
    },
    0x003f => { #PH
        Name => 'LensType',
        Writable => 'int8u',
        Count => 2,
        SeparateTable => 1,
        ValueConv => '$val=~s/^(\d+ \d+) 0$/$1/; $val',
        ValueConvInv => '$val',
        PrintConv => \%pentaxLensType,
    },
    0x0040 => { #PH
        Name => 'SensitivityAdjust',
        Writable => 'int16u',
        ValueConv => '($val - 50) / 10',
        ValueConvInv => '$val * 10 + 50',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => '$val',
    },
    0x0041 => { #19
        Name => 'ImageProcessingCount',
        Writable => 'int16u',
    },
    0x0047 => { #PH
        Name => 'CameraTemperature',
        Writable => 'int8s',
        PrintConv => '"$val C"',
        PrintConvInv => '$val=~s/ ?c$//i; $val',
    },
    0x0048 => { #19
        Name => 'AELock',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    0x0049 => { #13
        Name => 'NoiseReduction',
        Writable => 'int16u',
        PrintConv => { 0 => 'Off', 1 => 'On' },
    },
    0x004d => { #PH
        Name => 'FlashExposureComp',
        Writable => 'int32s',
        ValueConv => '$val / 256',
        ValueConvInv => 'int($val * 256 + ($val > 0 ? 0.5 : -0.5))',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
    0x004f => { #PH
        Name => 'ImageTone', # (Called CustomImageMode in K20D manual)
        Writable => 'int16u',
        PrintConv => {
            0 => 'Natural',
            1 => 'Bright',
            2 => 'Portrait', # K20D/K200D
            3 => 'Landscape', # K20D
            4 => 'Vibrant', # K20D
            5 => 'Monochrome', # K20D
        },
    },
    0x0050 => { #PH
        Name => 'ColorTemperature',
        Writable => 'int16u',
        RawConv => '$val ? $val : undef',
        ValueConv => '53190 - $val',
        ValueConvInv => '53190 - $val',
    },
    # 0x0053-0x005a - not in JPEG images - PH
    0x005c => { #PH
        Name => 'ShakeReductionInfo',
        Format => 'undef',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::SRInfo',
        },
    },
    0x005d => { #JD/PH
        # (used by all Pentax DSLR's except *istD and *istDS until firmware 2.0 - PH)
        # Observed values for the first shot of a new K10D are:  81 [PH], 181 [19],
        # 246 [7], and 209 [18 (one of the first 20 shots)], so there must be a number
        # of test images shot in the factory.
        # This count includes shutter actuations even if they don't result in a
        # recorded image. (ie. manual white balance frame or digital preview) - PH
        Name => 'ShutterCount',
        Writable => 'undef',
        Count => 4,
        # raw value is a big-endian 4-byte integer, encrypted using Date and Time
        RawConv => 'length($val) == 4 ? unpack("N",$val) : undef',
        RawConvInv => q{
            my $val = Image::ExifTool::Pentax::CryptShutterCount($val,$self);
            return pack('N', $val);
        },
        ValueConv => \&CryptShutterCount,
        ValueConvInv => '$val',
    },
    # 0x0062: int16u - values: 1 for K10D/K200D, 3 for K20D (K10D,K20D,K200D)
    # 0x0067: int16u - values: 1 [and 65535 in Monochrome] (K20D,K200D) - PH
    # 0x0068: int8u  - values: 1 (K20D,K200D) - PH
    0x0069 => { #PH (K20D)
        Name => 'DynamicRangeExpansion',
        Writable => 'undef',
        Format => 'int8u',
        Count => 4,
        PrintConv => {
            '0 0 0 0' => 'Off',
            '1 0 0 0' => 'On',
        },
    },
    # 0x0070: in8u   - values: 0, 1 (K20D,K200D) - PH
    0x0071 => { #PH (K20D)
        Name => 'HighISONoiseReduction',
        Format => 'int8u',
        PrintConv => {
            0 => 'Off',
            1 => 'Weakest',
            2 => 'Weak',
            3 => 'Strong',
        },
    },
    0x0072 => { #JD (K20D)
        Name => 'AFAdjustment',
        Writable => 'int16s',
    },
    # 0x0073,0x0074: int16u - values: 65535 [and 0,4,8 in Monochrome] (K20D,K200D) - PH
    0x0200 => { #5
        Name => 'BlackPoint',
        Writable => 'int16u',
        Count => 4,
    },
    0x0201 => { #5
        # (this doesn't change for different fixed white balances in JPEG images: Daylight,
        # Tungsten, Kelvin, etc -- always "8192 8192 8192 8192", but it varies for these in
        # RAW images, all images in Auto, for different Manual WB settings, and for images
        # taken via Pentax Remote Assistant) - PH
        Name => 'WhitePoint',
        Writable => 'int16u',
        Count => 4,
    },
    # 0x0202: int16u[4] - values: all 0's in all my samples
    0x0203 => { #JD (not really sure what these mean)
        Name => 'ColorMatrixA',
        Writable => 'int16s',
        Count => 9,
        ValueConv => 'join(" ",map({ $_/8192 } split(" ",$val)))',
        ValueConvInv => 'join(" ",map({ int($_*8192 + ($_<0?-0.5:0.5)) } split(" ",$val)))',
        PrintConv => 'join(" ",map({sprintf("%.5f",$_)} split(" ",$val)))',
        PrintConvInv => '"$val"',
    },
    0x0204 => { #JD
        Name => 'ColorMatrixB',
        Writable => 'int16s',
        Count => 9,
        ValueConv => 'join(" ",map({ $_/8192 } split(" ",$val)))',
        ValueConvInv => 'join(" ",map({ int($_*8192 + ($_<0?-0.5:0.5)) } split(" ",$val)))',
        PrintConv => 'join(" ",map({sprintf("%.5f",$_)} split(" ",$val)))',
        PrintConvInv => '"$val"',
    },
    0x0205 => { #19
        Name => 'CameraSettings',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::CameraSettings',
        },
    },
    0x0206 => { #PH
        Name => 'AEInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::AEInfo',
        },
    },
    0x0207 => [ #PH
        {
            Name => 'LensInfo',
            # the *ist series (and Samsung GX-1) always use the old format, and all
            # other models but the K100D, K110D and K100D Super always use the newer
            # format, and for the K110D/K110D we expect ff or 00 00 at byte 20 if
            # it is the old format.)
            Condition => q{
                $$self{Model}=~/(\*ist|GX-1[LS])/ or
               ($$self{Model}=~/(K100D|K110D)/ and $$valPt=~/^.{20}(\xff|\0\0)/s)
            },
            SubDirectory => {
                TagTable => 'Image::ExifTool::Pentax::LensInfo',
            },
        },{
            Name => 'LensInfo',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Pentax::LensInfo2',
            },
        }
    ],
    0x0208 => { #PH
        Name => 'FlashInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::FlashInfo',
        },
    },
    0x0209 => { #PH
        Name => 'AEMeteringSegments',
        Format => 'int8u',
        Count => 16,
        Notes => 'measurements from each of the 16 AE metering segments, converted to LV',
        %convertMeteringSegments,
        # metering segment locations (ref JD):
        # +-------------------------+
        # |           14            |
        # |    +---+---+---+---+    |
        # |    | 5 | 3/1\ 2| 4 |    |
        # |  +-+-+-+-+ - +-+-+-+-+  |
        # +--+ 9 | 7 ||0|| 6 | 8 +--+
        # |  +-+-+-+-+ - +-+-+-+-+  |
        # |    |13 |11\ /10|12 |    |
        # |    +---+---+---+---+    |
        # |           15            |
        # +-------------------------+
    },
    0x020a => { #PH/JD/19
        Name => 'FlashMeteringSegments',
        Format => 'int8u',
        Count => 16,
        %convertMeteringSegments,
    },
    0x020b => { #PH/JD/19
        Name => 'SlaveFlashMeteringSegments',
        Format => 'int8u',
        Count => 16,
        Notes => 'used in wireless control mode',
        %convertMeteringSegments,
    },
    0x020d => { #PH
        Name => 'WB_RGGBLevelsDaylight',
        Writable => 'int16u',
        Count => 4,
    },
    0x020e => { #PH
        Name => 'WB_RGGBLevelsShade',
        Writable => 'int16u',
        Count => 4,
    },
    0x020f => { #PH
        Name => 'WB_RGGBLevelsCloudy',
        Writable => 'int16u',
        Count => 4,
    },
    0x0210 => { #PH
        Name => 'WB_RGGBLevelsTungsten',
        Writable => 'int16u',
        Count => 4,
    },
    0x0211 => { #PH
        Name => 'WB_RGGBLevelsFluorescentD',
        Writable => 'int16u',
        Count => 4,
    },
    0x0212 => { #PH
        Name => 'WB_RGGBLevelsFluorescentN',
        Writable => 'int16u',
        Count => 4,
    },
    0x0213 => { #PH
        Name => 'WB_RGGBLevelsFluorescentW',
        Writable => 'int16u',
        Count => 4,
    },
    0x0214 => { #PH
        Name => 'WB_RGGBLevelsFlash',
        Writable => 'int16u',
        Count => 4,
    },
    0x0215 => { #PH
        Name => 'CameraInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::CameraInfo',
        },
    },
    0x0216 => { #PH
        Name => 'BatteryInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::BatteryInfo',
        },
    },
    0x021f => { #JD
        Name => 'AFInfo',
        SubDirectory => {
            # NOTE: Most of these subdirectories are 'undef' format, and as such the
            # byte ordering is not changed when changed via the Pentax software (which
            # will write a little-endian TIFF on an Intel system).  So we must define
            # BigEndian byte ordering for any of these which contain multi-byte values. - PH
            ByteOrder => 'BigEndian',
            TagTable => 'Image::ExifTool::Pentax::AFInfo',
        },
    },
    0x0222 => { #PH
        Name => 'ColorInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::ColorInfo',
        },
    },
    0x0224 => { #19
        Name => 'EVStepInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::EVStepInfo',
        },
    },
    # 0x0226: undef[9] (K20D,K200D) - PH
    0x03fe => { #PH
        Name => 'DataDump',
        Writable => 0,
        PrintConv => '\$val',
    },
    0x03ff => { #PH
        Name => 'UnknownInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Pentax::UnknownInfo',
        },
    },
    0x0402 => { #5
        Name => 'ToneCurve',
        PrintConv => '\$val',
    },
    0x0403 => { #5
        Name => 'ToneCurves',
        PrintConv => '\$val',
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        Writable => 0,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
);

# shake reduction information (ref PH)
%Image::ExifTool::Pentax::SRInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => 'Shake reduction information.',
    0 => {
        Name => 'SRResult',
        PrintConv => { #PH/JD
            0 => 'Not stabilized',
            BITMASK => {
                0 => 'Stabilized',
                # have seen 1 for 0.5 sec exposure time, NR On - ref 19
                6 => 'Not ready',
            },
        },
    },
    1 => {
        Name => 'ShakeReduction',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
            4 => 'Off (4)', #(NC) (K20D, K200D)
            7 => 'On (7)', #(NC) (K20D, K200D)
        },
    },
    2 => {
        Name => 'SRHalfPressTime',
        # (was SR_SWSToSWRTime: SWS=photometering switch, SWR=shutter release switch)
        # (from http://www.patentstorm.us/patents/6597867-description.html)
        # (here, SR could more accurately mean Shutter Release, not Shake Reduction)
        Notes => q{
            time from when the shutter button was half pressed to when the shutter was
            released, including time for focusing
        },
        # (constant of 60 determined from times: 2sec=127; 3sec=184,197; 4sec=244,249,243,246 - PH)
        ValueConv => '$val / 60',
        ValueConvInv => 'my $v=$val*60; $v < 255 ? int($v + 0.5) : 255',
        PrintConv => 'sprintf("%.2f s",$val) . ($val > 254.5/60 ? " or longer" : "")',
        PrintConvInv => '$val=~tr/0-9.//dc; $val',
    },
    3 => { #JD
        Name => 'SRFocalLength',
        ValueConv => '$val & 0x01 ? $val * 4 : $val / 2',
        ValueConvInv => '$val <= 127 ? int($val) * 2 : int($val / 4) | 0x01',
        PrintConv => '"$val mm"',
        PrintConvInv => '$val=~s/\s*mm//;$val',
    },
);

# shot information (ref 19)
%Image::ExifTool::Pentax::CameraSettings = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    PRIORITY => 0,
    FIRST_ENTRY => 0,
    NOTES => 'Shot information written by Pentax DSLR cameras.',
    0 => {
        Name => 'PictureMode2',
        PrintConv => {
            0 => 'Scene Mode', #PH
            1 => 'Auto PICT', #PH (NC)
            2 => 'Program AE',
            3 => 'Green Mode',
            4 => 'Shutter Speed Priority',
            5 => 'Aperture Priority',
            6 => 'Program Tv Shift', #PH
            7 => 'Program Av Shift',
            8 => 'Manual', #PH
            9 => 'Bulb', #PH
            10 => 'Aperture Priority, Off-Auto-Aperture', #PH (NC)
            11 => 'Manual, Off-Auto-Aperture', #PH
            12 => 'Bulb, Off-Auto-Aperture', #PH (NC)
            13 => 'Shutter & Aperture Priority AE',
            15 => 'Sensitivity Priority AE',
            16 => 'Flash X-Sync Speed AE', #PH
        },
    },
    1.1 => {
        Name => 'ProgramLine',
        # only set to other than Normal when in Program AE mode
        Mask => 0x03,
        PrintConv => {
            0 => 'Normal',
            1 => 'Hi Speed',
            2 => 'Depth',
            3 => 'MTF',
        },
    },
    1.2 => {
        Name => 'EVSteps',
        Mask => 0x20,
        PrintConv => {
            0x00 => '1/2 EV steps',
            0x20 => '1/3 EV steps',
        },
    },
    1.3 => {
        Name => 'E-DialInProgram',
        # always set even when not in Program AE mode
        Mask => 0x40,
        PrintConv => {
            0x00 => 'Tv or Av',
            0x40 => 'P Shift',
        },
    },
    1.4 => {
        Name => 'ApertureRingUse',
        # always set even Aperture Ring is in A mode
        Mask => 0x80,
        PrintConv => {
            0x00 => 'Prohibited',
            0x80 => 'Permitted',
        },
    },
    2 => {
        Name => 'FlashOptions',
        Notes => 'the camera flash options settings, set even if the flash is off',
        Mask => 0xf0,
        ValueConv => '$val>>4',
        # Note: These tags correlate with the FlashMode and InternalFlashMode values,
        # and match what is displayed by the Pentax software
        PrintConv => {
            0 => 'Normal', # (this value can occur in Green Mode) - ref 19
            1 => 'Red-eye reduction', # (this value can occur in Green Mode) - ref 19
            2 => 'Auto', # (this value can occur in other than Green Mode) - ref 19
            3 => 'Auto, Red-eye reduction', #PH (this value can occur in other than Green Mode) - ref 19
            5 => 'Wireless (Master)',
            6 => 'Wireless (Control)',
            8 => 'Slow-sync',
            9 => 'Slow-sync, Red-eye reduction',
            10 => 'Trailing-curtain Sync'
        },
    },
    2.1 => {
        Name => 'MeteringMode2',
        Mask => 0x0f,
        Notes => 'may not be valid for some models, ie. *ist D',
        PrintConv => {
            0 => 'Multi-segment',
            BITMASK => {
                0 => 'Center-weighted average',
                1 => 'Spot',
            },
        },
    },
    3 => {
        Name => 'AFPointMode',
        Mask => 0xf0,
        PrintConv => {
            0x00 => 'Auto',
            BITMASK => {
                4 => 'Select',
                5 => 'Fixed Center',
                # have seen bit 6 set in pre-production images (firmware 0.20) - PH
            },
        },
    },
    3.1 => {
        Name => 'FocusMode2',
        Mask => 0x0f,
        PrintConv => {
            0 => 'Manual',
            BITMASK => {
                0 => 'AF-S',
                1 => 'AF-C',
            },
        },
    },
    4 => {
        Name => 'AFPointSelected2',
        Format => 'int16u',
        PrintConv => {
            0 => 'Auto',
            BITMASK => {
                0 => 'Upper-left',
                1 => 'Top',
                2 => 'Upper-right',
                3 => 'Left',
                4 => 'Mid-left',
                5 => 'Center',
                6 => 'Mid-right',
                7 => 'Right',
                8 => 'Lower-left',
                9 => 'Bottom',
                10 => 'Lower-right',
            },
        },
    },
    6 => {
        Name => 'ISOFloor', #PH
        # manual ISO or minimum ISO in Auto ISO mode - PH
        ValueConv => 'int(100*exp(Image::ExifTool::Pentax::PentaxEv($val-32)*log(2))+0.5)',
        ValueConvInv => 'Image::ExifTool::Pentax::PentaxEvInv(log($val/100)/log(2))+32',
    },
    7 => {
        Name => 'DriveMode2',
        PrintConv => {
            0 => 'Single-frame',
            BITMASK => {
                0 => 'Continuous',
                2 => 'Self-timer (12 s)', #PH
                3 => 'Self-timer (2 s)', #PH
                4 => 'Remote Control (3 s delay)',
                5 => 'Remote Control',
                6 => 'Exposure Bracket', #PH/19
                7 => 'Multiple Exposure',
            },
        },
    },
    8 => {
        Name => 'ExposureBracketStepSize',
        # This is set even when Exposure Bracket is Off (and the K10D
        # displays Ò---Ó as the step size when you press the EB button) - DaveN
        # because the last value is remembered and if you turn Exposure Bracket
        # on the step size goes back to what it was before.
        PrintConv => {
            3 => '0.3',
            4 => '0.5',
            5 => '0.7',
            8 => '1.0', #PH
            11 => '1.3',
            12 => '1.5',
            13 => '1.7', #(NC)
            16 => '2.0', #PH
        },
    },
    9 => { #PH/19
        Name => 'BracketShotNumber',
        PrintHex => 1,
        PrintConv => {
            0 => 'n/a',
            0x03 => '1 of 3',
            0x13 => '2 of 3',
            0x23 => '3 of 3',
            0x05 => '1 of 5',
            0x15 => '2 of 5',
            0x25 => '3 of 5',
            0x35 => '4 of 5',
            0x45 => '5 of 5',
        },
    },
    10 => {
        Name => 'WhiteBalanceSet',
        Mask => 0xf0,
        # Not necessarily the white balance used; for example if the custom menu is set to
        # "WB when using flash" -> "2 Flash", then this tag reports the camera setting while
        # tag 0x0019 reports Flash if the Flash was used.
        PrintConv => {
            0 => 'Auto',
            16 => 'Daylight',
            32 => 'Shade',
            48 => 'Cloudy',
            64 => 'DaylightFluorescent',
            80 => 'DaywhiteFluorescent',
            96 => 'WhiteFluorescent',
            112 => 'Tungsten',
            128 => 'Flash',
            144 => 'Manual',
            # The three Set Color Temperature settings refer to the 3 preset settings which
            # can be saved in the menu (see page 123 of the K10D manual)
            192 => 'Set Color Temperature 1',
            208 => 'Set Color Temperature 2',
            224 => 'Set Color Temperature 3',
        },
    },
    10.1 => {
        Name => 'MultipleExposureSet',
        Mask => 0x0f,
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    13 => {
        Name => 'RawAndJpgRecording',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        # this is actually a bit field: - PH
        # bit 0=JPEG, bit 1=RAW; high nibble: 0x0=best, 0x1=better, 0x2=good
        PrintConv => {
            1 => 'JPEG (Best)', #PH
            4 => 'RAW (PEF, Best)',
            5 => 'RAW+JPEG (PEF, Best)',
            8 => 'RAW (DNG, Best)', #PH (NC)
            9 => 'RAW+JPEG (DNG, Best)', #PH (NC)
            33 => 'JPEG (Better)', #PH
            36 => 'RAW (PEF, Better)',
            37 => 'RAW+JPEG (PEF, Better)', #PH
            40 => 'RAW (DNG, Better)', #PH
            41 => 'RAW+JPEG (DNG, Better)', #PH (NC)
            65 => 'JPEG (Good)',
            68 => 'RAW (PEF, Good)', #PH (NC)
            69 => 'RAW+JPEG (PEF, Good)', #PH (NC)
            72 => 'RAW (DNG, Good)', #PH (NC)
            73 => 'RAW+JPEG (DNG, Good)',
            # have seen values of 0,2,34 for other models (not K10D) - PH
        },
    },
    14 => { #PH
        Name => 'JpgRecordedPixels',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        PrintConv => {
            0 => '10 MP',
            1 => '6 MP',
            2 => '2 MP',
            # have seen 80,108,240,252 for *istD models - PH
        },
    },
    16 => {
        Name => 'FlashOptions2',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only; set even if the flash is off',
        Mask => 0xf0,
        # Note: the Normal and Auto values (0x00 to 0x30) do not tags always
        # correlate with the FlashMode, InternalFlashMode and FlashOptions values
        # however, these values seem to better match the K10D's actual functionality
        # (always Auto in Green mode always Normal otherwise if one of the other options
        # isn't selected) - ref 19
        # (these tags relate closely to InternalFlashMode values - PH)
        PrintConv => {
            0x00 => 'Normal', # (this value never occurs in Green Mode) - ref 19
            0x10 => 'Red-eye reduction', # (this value never occurs in Green Mode) - ref 19
            0x20 => 'Auto',  # (this value only occurs in Green Mode) - ref 19
            0x30 => 'Auto, Red-eye reduction', # (this value only occurs in Green Mode) - ref 19
            0x50 => 'Wireless (Master)',
            0x60 => 'Wireless (Control)',
            0x80 => 'Slow-sync',
            0x90 => 'Slow-sync, Red-eye reduction',
            0xa0 => 'Trailing-curtain Sync'
        },
    },
    16.1 => {
        Name => 'MeteringMode3',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        Mask => 0x0f,
        PrintConv => {
            0 => 'Multi-segment',
            BITMASK => {
                0 => 'Center-weighted average',
                1 => 'Spot',
            },
        },
    },
    17.1 => {
        Name => 'SRActive',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => q{
            K10D only; SR is active only when ShakeReduction is On, DriveMode is not
            Remote or Self-timer, and Internal/ExternalFlashMode is not "On, Wireless"
        },
        Mask => 0x80,
        PrintConv => {
            0x00 => 'No',
            0x80 => 'Yes',
        },
    },
    17.2 => {
        Name => 'Rotation',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        Mask => 0x60,
        PrintConv => {
            0x00 => 'Horizontal (normal)',
            0x20 => 'Rotate 180',
            0x40 => 'Rotate 90 CW',
            0x60 => 'Rotate 270 CW',
        },
    },
    # Bit 0x08 is set on 3 of my 3000 shots to (All 3 were Shutter Priority
    # but this may not mean anything with such a small sample) - ref 19
    17.3 => {
        Name => 'ISOSetting',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        Mask => 0x04,
        PrintConv => {
            0x00 => 'Manual',
            0x04 => 'Auto',
        },
    },
    17.4 => {
        Name => 'SensitivitySteps',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        Mask => 0x02,
        PrintConv => {
            0x00 => '1 EV Steps',
            0x02 => 'As EV Steps',
        },
    },
    18 => {
        Name => 'TvExposureTimeSetting',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        ValueConv => 'exp(-Image::ExifTool::Pentax::PentaxEv($val-68)*log(2))',
        ValueConvInv => 'Image::ExifTool::Pentax::PentaxEvInv(-log($val)/log(2))+68',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    19 => {
        Name => 'AvApertureSetting',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        ValueConv => 'exp(Image::ExifTool::Pentax::PentaxEv($val-68)*log(2)/2)',
        ValueConvInv => 'Image::ExifTool::Pentax::PentaxEvInv(log($val)*2/log(2))+68',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    20 => { #PH
        Name => 'SvISOSetting',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only',
        # ISO setting for sensitivity-priority mode
        # (conversion may not give actual displayed values:)
        # 32 => 100, 35 => 125, 36 => 140, 37 => 160,
        # 40 => 200, 43 => 250, 44 => 280, 45 => 320,
        # 48 => 400, 51 => 500, 52 => 560, 53 => 640,
        # 56 => 800, 59 => 1000,60 => 1100,61 => 1250, 64 => 1600
        ValueConv => 'int(100*exp(Image::ExifTool::Pentax::PentaxEv($val-32)*log(2))+0.5)',
        ValueConvInv => 'Image::ExifTool::Pentax::PentaxEvInv(log($val/100)/log(2))+32',
    },
    21 => { #PH
        Name => 'BaseExposureCompensation',
        Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
        Notes => 'K10D only; exposure compensation without auto bracketing',
        ValueConv => 'Image::ExifTool::Pentax::PentaxEv(64-$val)',
        ValueConvInv => '64-Image::ExifTool::Pentax::PentaxEvInv($val)',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
);

# auto-exposure information (ref PH)
%Image::ExifTool::Pentax::AEInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    # instead of /8, should these be PentaxEV(), as in CameraSettings? - PH
    0 => {
        Name => 'AEExposureTime',
        Notes => 'val = 24 * 2**((32-raw)/8)',
        ValueConv => '24*exp(-($val-32)*log(2)/8)',
        ValueConvInv => '-log($val/24)*8/log(2)+32',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    1 => {
        Name => 'AEAperture',
        Notes => 'val = 2**((raw-68)/16)',
        ValueConv => 'exp(($val-68)*log(2)/16)',
        ValueConvInv => 'log($val)*16/log(2)+68',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    2 => {
        Name => 'AE_ISO',
        Notes => 'val = 100 * 2**((raw-32)/8)',
        ValueConv => '100*exp(($val-32)*log(2)/8)',
        ValueConvInv => 'log($val/100)*8/log(2)+32',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    3 => {
        Name => 'AEXv',
        Notes => 'val = (raw-64)/8',
        ValueConv => '($val-64)/8',
        ValueConvInv => '$val * 8 + 64',
    },
    4 => {
        Name => 'AEBXv',
        Format => 'int8s',
        Notes => 'val = raw / 8',
        ValueConv => '$val / 8',
        ValueConvInv => '$val * 8',
    },
    5 => {
        Name => 'AEMinExposureTime', #19
        Notes => 'val = 24 * 2**((32-raw)/8)',
        ValueConv => '24*exp(-($val-32)*log(2)/8)', #JD
        ValueConvInv => '-log($val/24)*8/log(2)+32',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    6 => {
        Name => 'AEProgramMode',
        PrintConv => {
            0 => 'M, P or TAv',
            1 => 'Av, B or X',
            2 => 'Tv',
            3 => 'Sv or Green Mode',
            8 => 'Hi-speed Program',
            11 => 'Hi-speed Program (P-Shift)', #19
            16 => 'DOF Program', #19
            19 => 'DOF Program (P-Shift)', #19
            24 => 'MTF Program', #19
            27 => 'MTF Program (P-Shift)', #19
            35 => 'Standard',
            43 => 'Portrait',
            51 => 'Landscape',
            59 => 'Macro',
            67 => 'Sport',
            75 => 'Night Scene Portrait',
            83 => 'No Flash',
            91 => 'Night Scene',
            99 => 'Surf & Snow',
            107 => 'Text',
            115 => 'Sunset',
            123 => 'Kids',
            131 => 'Pet',
            139 => 'Candlelight',
            147 => 'Museum',
        },
    },
    7 => {
        Name => 'AEExtra',
        Unknown => 1,
    },
    9 => { #19
        Name => 'AEMaxAperture',
        Notes => 'val = 2**((raw-68)/16)',
        ValueConv => 'exp(($val-68)*log(2)/16)',
        ValueConvInv => 'log($val)*16/log(2)+68',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    10 => { #19
        Name => 'AEMaxAperture2',
        Notes => 'val = 2**((raw-68)/16)',
        ValueConv => 'exp(($val-68)*log(2)/16)',
        ValueConvInv => 'log($val)*16/log(2)+68',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    11 => { #19
        Name => 'AEMinAperture',
        Notes => 'val = 2**((raw-68)/16)',
        ValueConv => 'exp(($val-68)*log(2)/16)',
        ValueConvInv => 'log($val)*16/log(2)+68',
        PrintConv => 'sprintf("%.0f",$val)',
        PrintConvInv => '$val',
    },
    12 => { #19
        Name => 'AEMeteringMode',
        PrintConv => {
            0 => 'Multi-segment',
            BITMASK => {
                4 => 'Center-weighted average',
                5 => 'Spot',
            },
        },
    },
    14 => { #19
        Name => 'FlashExposureCompSet',
        Format => 'int8s',
        Notes => q{
            reports the camera setting, unlike tag 0x004d which reports 0 in Green mode
            or if flash was on but did not fire. Both this tag and 0x004d report the
            setting even if the flash is off
        },
        ValueConv => 'Image::ExifTool::Pentax::PentaxEv($val)',
        ValueConvInv => 'Image::ExifTool::Pentax::PentaxEvInv($val)',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
        PrintConvInv => 'eval $val',
    },
);

# lens information (ref PH)
%Image::ExifTool::Pentax::LensInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    VARS => { HAS_SUBDIR => 1 },
    DATAMEMBER => [ 0 ],
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => 'Pentax lens information structure.',
    0 => {
        Name => 'LensType',
        Format => 'int8u[2]',
        Priority => 0,
        PrintConv => \%pentaxLensType,
        SeparateTable => 1,
    },
    3 => {
        Name => 'LensData',
        Format => 'undef[17]',
        SubDirectory => { TagTable => 'Image::ExifTool::Pentax::LensData' },
    },
);

# lens information for newer models (ref PH)
%Image::ExifTool::Pentax::LensInfo2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    VARS => { HAS_SUBDIR => 1 },
    DATAMEMBER => [ 0 ],
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => 'Pentax lens information structure for newer models (K10D and later).',
    0 => {
        Name => 'LensType',
        Format => 'int8u[4]',
        Priority => 0,
        ValueConv => q{
            my @v = split(' ',$val);
            $v[0] &= 0x0f;
            $v[1] = $v[2] * 256 + $v[3]; # (always high byte first)
            return "$v[0] $v[1]";
        },
        PrintConv => \%pentaxLensType,
        SeparateTable => 1,
    },
    4 => {
        Name => 'LensData',
        Format => 'undef[17]',
        SubDirectory => { TagTable => 'Image::ExifTool::Pentax::LensData' },
    },
);

# lens data information, including lens codes (ref PH)
%Image::ExifTool::Pentax::LensData = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    DATAMEMBER => [ 0 ],
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    NOTES => q{
        Pentax lens data information.  Some of these tags require interesting binary
        gymnastics to decode them into useful values.
    },
    # this byte comes from the lens electrical contacts
    # (see http://kmp.bdimitrov.de/technology/K-mount/Ka.html)
    0.1 => { #JD
        Name => 'AutoAperture',
        Mask => 0x01,
        PrintConv => {
            0 => 'On',
            1 => 'Off',
        },
    },
    0.2 => { #JD
        Name => 'MinAperture',
        Mask => 0x06,
        PrintConv => {
            0x00 => 22,
            0x02 => 32,
            0x04 => 45,
            0x06 => 16,
        },
    },
    0.3 => { #JD
        Name => 'LensFStops',
        Mask => 0x70,
        ValueConv => '5 + (($val >> 4) ^ 0x07) / 2',
        ValueConvInv => '((($val - 5) * 2) ^ 0x07) << 4',
    },
    # 1-16 look like Lens Codes LC0-LC15, ref patent 5617173 and 5999753 [+notes by PH]
    1 => { # LC0 = lens kind + version data
        Name => 'LensKind',
        %lensCode,
    },
    2 => { # LC1 = lens data
        Name => 'LC1',
        %lensCode,
    },
    3 => { # LC2 = distance data
        Name => 'LC2',
        %lensCode,
        # FocusRange decoding needs more testing with various lenses - PH
        TestName => 'FocusRange',
        TestPrintConv => q{
            my @v;
            my $lsb = $val & 0x07;
            my $msb = $val >> 3;
            my $ls2 = $lsb ^ 0x07;
            $ls2 ^= 0x01 if $ls2 & 0x02;
            $ls2 ^= 0x03 if $ls2 & 0x04;
            foreach ($ls2, $ls2+1) {
                push(@v,'inf'), next if $_ > 7;
                push @v, sprintf("%.2f m", 2 ** ($msb / 4) * 0.18 * ($_ + 4) / 16);
            }
            return join ' - ', @v;
        },
    },
    4 => { # LC3 = K-value data (AF pulses to displace image by unit length)
        Name => 'LC3',
        %lensCode,
    },
    5 => { # LC4 = abberation correction, near distance data
        Name => 'LC4',
        %lensCode,
    },
    6 => { # LC5 = light color abberation correction data
        Name => 'LC5',
        %lensCode,
    },
    7 => { # LC6 = open abberation data
        Name => 'LC6',
        %lensCode,
    },
    8 => { # LC7 = AF minimum actuation condition
        Name => 'LC7',
        %lensCode,
    },
    9 => { # LC8 = focal length data
        Name => 'FocalLength',
        Priority => 0,
        ValueConv => '10*($val>>2) * 4**(($val&0x03)-2)', #JD
        ValueConvInv => q{
            my $range = int(log($val/10)/(2*log(2)));
            warn("Value out of range") and return undef if $range < 0 or $range > 3;
            return $range + (int($val/(10*4**($range-2))+0.5) << 2);
        },
        PrintConv => 'sprintf("%.1f mm", $val)',
        PrintConvInv => '$val=~s/\s*mm//; $val',
    },
    10 => { # LC9 = nominal AVmin/AVmax data (open/closed aperture values)
        Name => 'NominalMaxAperture',
        Mask => 0xf0,
        ValueConv => '2**(($val>>4)/4)', #JD
        ValueConvInv => '4*log($val)/log(2) << 4',
        PrintConv => 'sprintf("%.1f", $val)',
        PrintConvInv => '$val',
    },
    10.1 => { # LC9 = nominal AVmin/AVmax data (open/closed aperture values)
        Name => 'NominalMinAperture',
        Mask => 0x0f,
        ValueConv => '2**(($val+10)/4)', #JD
        ValueConvInv => '4*log($val)/log(2) - 10',
        PrintConv => 'sprintf("%.0f", $val)',
        PrintConvInv => '$val',
    },
    11 => { # LC10 = mv'/nv' data (full-aperture metering error compensation/marginal lumination compensation)
        Name => 'LC10',
        %lensCode,
    },
    12 => { # LC11 = AVC 1/EXP data
        Name => 'LC11',
        %lensCode,
    },
    13 => { # LC12 = mv1 AVminsif data
        Name => 'LC12',
        %lensCode,
    },
    14.1 => { # LC13 = AVmin (open aperture value) [MaxAperture=(2**((AVmin-1)/32))]
        Name => 'MaxAperture',
        Notes => 'effective wide open aperture for current focal length',
        Mask => 0x7f, # (not sure what the high bit indicates)
        # (a value of 1 seems to indicate 'n/a')
        RawConv => '$val > 1 ? $val : undef',
        ValueConv => '2**(($val-1)/32)',
        ValueConvInv => '32*log($val)/log(2) + 1',
        PrintConv => 'sprintf("%.1f", $val)',
        PrintConvInv => '$val',
    },
    15 => { # LC14 = UNT_12 UNT_6 data
        Name => 'LC14',
        %lensCode,
    },
    16 => { # LC15 = incorporated flash suited END data
        Name => 'LC15',
        %lensCode,
    },
);

# flash information (ref PH)
%Image::ExifTool::Pentax::FlashInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0 => {
        Name => 'FlashStatus',
        PrintHex => 1,
        PrintConv => { #19
            0x00 => 'Off',
            0x02 => 'External, Did not fire', # 0010
            0x06 => 'External, Fired',        # 0110
            0x09 => 'Internal, Did not fire', # 1001
            0x0d => 'Internal, Fired',        # 1101
        },
    },
    1 => {
        Name => 'InternalFlashMode',
        PrintHex => 1,
        PrintConv => {
            0x00 => 'n/a - Off-Auto-Aperture', #19
            0x86 => 'On, Wireless (Control)', #19
            0x95 => 'On, Wireless (Master)', #19
            0xc0 => 'On', # K10D
            0xc1 => 'On, Red-eye reduction', # *istDS2, K10D
            0xc2 => 'On, Auto', # K100D, K110D
            0xc3 => 'On, Auto, Red-eye reduction', #PH
            0xc8 => 'On, Slow-sync', # K10D
            0xc9 => 'On, Slow-sync, Red-eye reduction', # K10D
            0xca => 'On, Trailing-curtain Sync', # K10D
            0xf0 => 'Off, Normal', #19
            0xf1 => 'Off, Red-eye reduction', #19
            0xf2 => 'Off, Auto', #19
            0xf3 => 'Off, Auto, Red-eye reduction', #19
            0xf4 => 'Off, (Unknown 0xf4)', #19
            0xf5 => 'Off, Wireless (Master)', #19
            0xf6 => 'Off, Wireless (Control)', #19
            0xf8 => 'Off, Slow-sync', #19
            0xf9 => 'Off, Slow-sync, Red-eye reduction', #19
            0xfa => 'Off, Trailing-curtain Sync', #19
        },
    },
    2 => {
        Name => 'ExternalFlashMode',
        PrintHex => 1,
        PrintConv => { #19
            0x00 => 'n/a - Off-Auto-Aperture',
            0x3f => 'Off',
            0x40 => 'On, Auto',
            0xbf => 'On, Flash Problem', #JD
            0xc0 => 'On, Manual',
            0xc4 => 'On, P-TTL Auto',
            0xc5 => 'On, Contrast-control Sync', #JD
            0xc6 => 'On, High-speed Sync',
            0xcc => 'On, Wireless',
            0xcd => 'On, Wireless, High-speed Sync',
        },
    },
    3 => {
        Name => 'InternalFlashStrength',
        Notes => 'saved from the most recent flash picture, on a scale of about 0 to 100',
    },
    4 => 'TTL_DA_AUp',
    5 => 'TTL_DA_ADown',
    6 => 'TTL_DA_BUp',
    7 => 'TTL_DA_BDown',
    24.1 => { #19/17
        Name => 'ExternalFlashGuideNumber',
        Mask => 0x1f,
        Notes => 'val = 2**(raw/16 + 4), with a few exceptions',
        ValueConv => q{
            return 0 unless $val;
            $val = -3 if $val == 29;  # -3 is stored as 0x1d
            return 2**($val/16 + 4);
        },
        ValueConvInv => q{
            return 0 unless $val;
            my $raw = int((log($val)/log(2)-4)*16+0.5);
            $raw = 29 if $raw < 0;   # guide number of 14 gives -3 which is stored as 0x1d
            $raw = 31 if $raw > 31;  # maximum value is 0x1f
            return $raw;
        },
        PrintConv => '$val ? int($val + 0.5) : "n/a"',
        PrintConvInv => '$val=~/^n/ ? 0 : $val',
        # observed values for various flash focal lengths/guide numbers:
        #  AF-540FGZ (ref 19)  AF-360FGZ (ref 17)
        #     6 => 20mm/21       29 => 20mm/14   (wide angle panel used)
        #    16 => 24mm/32        6 => 24mm/21
        #    18 => 28mm/35        7 => 28mm/22
        #    21 => 35mm/39       10 => 35mm/25
        #    24 => 50mm/45       14 => 50mm/30
        #    26 => 70mm/50       17 => 70mm/33
        #    28 => 85mm/54       19 => 85mm/36
        # (I have also seen a value of 31 when both flashes are used together
        # in a wired configuration, but I don't know exactly what this means - PH)
    },
    # 24 - have seen bit 0x80 set when 2 external wired flashes are used - PH
    # 24 - have seen bit 0x40 set when wireless high speed sync is used - ref 19
    25 => { #19
        Name => 'ExternalFlashExposureComp',
        PrintConv => {
            0 => 'n/a', # Off or Auto Modes
            144 => 'n/a (Manual Mode)', # Manual Flash Output
            164 => '-3.0',
            167 => '-2.5',
            168 => '-2.0',
            171 => '-1.5',
            172 => '-1.0',
            175 => '-0.5',
            176 => '0.0',
            179 => '0.5',
            180 => '1.0',
        },
    },
    26 => { #17
        Name => 'ExternalFlashBounce',
        Notes => 'saved from the most recent external flash picture', #19
        PrintConv => {
             0 => 'n/a',
            16 => 'Direct',
            48 => 'Bounce',
        },
    },
    # ? => 'ExternalFlashAOutput',
    # ? => 'ExternalFlashBOutput',
);

# camera manufacture information (ref PH)
%Image::ExifTool::Pentax::CameraInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    FORMAT => 'int32u',
    0 => {
        Name => 'PentaxModelID',
        Priority => 0, # (Optio SVi uses incorrect Optio SV ID here)
        SeparateTable => 1,
        PrintConv => \%pentaxModelID,
    },
    1 => {
        Name => 'ManufactureDate',
        Notes => q{
            this value, and the values of the tags below, may change if the camera is
            serviced
        },
        ValueConv => q{
            $val =~ /^(\d{4})(\d{2})(\d{2})$/ and return "$1:$2:$3";
            # Optio A10 and A20 leave "200" off the year
            $val =~ /^(\d)(\d{2})(\d{2})$/ and return "200$1:$2:$3";
            return "Unknown ($val)";
        },
        ValueConvInv => '$val=~tr/0-9//dc; $val',
    },
    2 => {
        #(see http://www.pentaxforums.com/forums/pentax-dslr-discussion/25711-k10d-update-model-revision-8-1-yes-no-8.html)
        Name => 'ProductionCode', #(previously ModelRevision)
        Format => 'int32u[2]',
        Note => 'values of 8.x indicate that the camera has been serviced',
        ValueConv => '$val=~tr/ /./; $val',
        ValueConvInv => '$val=~tr/./ /; $val',
        PrintConv => '$val=~/^8\./ ? "$val (camera has been serviced)" : $val',
        PrintConvInv => '$val=~s/\s+.*//s; $val',
    },
    4 => 'InternalSerialNumber',
);

# battery information (ref PH)
%Image::ExifTool::Pentax::BatteryInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    0 => { #19
        Name => 'PowerSource',
        PrintHex => 1,
        # have seen the upper bit set (value of 0x82) for the
        # *istDS and K100D, but I'm not sure what this means - PH
        PrintConv => {
            2 => 'Body Battery',
            3 => 'Grip Battery',
            4 => 'External Power Supply', #PH
        },
    },
    1 => [
        {
            Name => 'BatteryStates',
            Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
            Notes => 'decoded for K10D only',
            ValueConv => '($val >> 4) . " " . ($val & 0x0f)',
            ValueConvInv => 'my @a=split(" ",$val); ($a[0] << 4) + $a[1]',
            PrintConv => [{ #19
                 1 => 'Body Battery Empty or Missing',
                 2 => 'Body Battery Almost Empty',
                 3 => 'Body Battery Running Low',
                 4 => 'Body Battery Full',
            },{
                 1 => 'Grip Battery Empty or Missing',
                 2 => 'Grip Battery Almost Empty',
                 3 => 'Grip Battery Running Low',
                 4 => 'Grip Battery Full',
            }],
        },
        {
            Name => 'BatteryStates',
            ValueConv => '($val >> 4) . " " . ($val & 0x0f)',
            ValueConvInv => 'my @a=split(" ",$val); ($a[0] << 4) + $a[1]',
        }
    ],
    # internal and grip battery voltage Analogue to Digital measurements,
    # open circuit and under load
    2 => [
        {
            Name => 'BatteryADBodyNoLoad',
            Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
            Notes => 'roughly calibrated for K10D with a new Pentax battery',
            # rough linear calibration drops quickly below 30% - PH
            # DVM readings: 8.18V=186, 8.42-8.40V=192 (full), 6.86V=155 (empty)
            PrintConv => 'sprintf("%d (%.1fV, %d%%)",$val,$val*8.18/186,($val-155)*100/35)',
            PrintConvInv => '$val=~s/ .*//; $val',
        },
        {
            Name => 'BatteryADBodyNoLoad',
        },
    ],
    3 => [
        {
            Name => 'BatteryADBodyLoad',
            Condition => '$$self{Model} =~ /(K10D|GX10)\b/',
            # [have seen 187] - PH
            PrintConv => 'sprintf("%d (%.1fV, %d%%)",$val,$val*8.18/186,($val-152)*100/34)',
            PrintConvInv => '$val=~s/ .*//; $val',
        },
        {
            Name => 'BatteryADBodyLoad',
        },
    ],
    4 => 'BatteryADGripNoLoad',
    5 => 'BatteryADGripLoad',
);

# auto focus information
%Image::ExifTool::Pentax::AFInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    # AF Info tag names in K10D debugging output - PH:
    # SelectArea, InFocusArea, Predictor, Defocus, IntegTime2msStep,
    # CalFlag, ContrastFlag, PrecalFlag, SelectSensor
    0x00 => { #PH
        Name => 'AFPointsUnknown1',
        Unknown => 1,
        Format => 'int16u',
        ValueConv => '$self->Options("Unknown") ? $val : $val & 0x7ff',
        ValueConvInv => '$val',
        PrintConv => {
            0x07ff => 'All',
            0x0777 => 'Central 9 points',
            BITMASK => {
                0 => 'Upper-left',
                1 => 'Top',
                2 => 'Upper-right',
                3 => 'Left',
                4 => 'Mid-left',
                5 => 'Center',
                6 => 'Mid-right',
                7 => 'Right',
                8 => 'Lower-left',
                9 => 'Bottom',
                10 => 'Lower-right',
                # (bits 12-15 are flags of some sort)
            },
        },
    },
    0x02 => { #PH
        Name => 'AFPointsUnknown2',
        Unknown => 1,
        Format => 'int16u',
        ValueConv => '$self->Options("Unknown") ? $val : $val & 0x7ff',
        ValueConvInv => '$val',
        PrintConv => {
            0 => 'Auto',
            BITMASK => {
                0 => 'Upper-left',
                1 => 'Top',
                2 => 'Upper-right',
                3 => 'Left',
                4 => 'Mid-left',
                5 => 'Center',
                6 => 'Mid-right',
                7 => 'Right',
                8 => 'Lower-left',
                9 => 'Bottom',
                10 => 'Lower-right',
                # (bits 12-15 are flags of some sort)
                # bit 15 is set for center focus point only if it is vertical
            },
        },
    },
    0x04 => { #PH (educated guess - predicted amount to drive lens)
        Name => 'AFPredictor',
        Format => 'int16s',
    },
    0x06 => 'AFDefocus', #PH (educated guess - calculated distance from focused)
    0x07 => { #PH
        # effective exposure time for AF sensors in 2 ms increments
        Name => 'AFIntegrationTime',
        Notes => 'times less than 2 ms give a value of 0',
        ValueConv => '$val * 2',
        ValueConvInv => 'int($val / 2)', # (don't round up)
        PrintConv => '"$val ms"',
        PrintConvInv => '$val=~tr/0-9//dc; $val',
    },
    # 0x0a - values: 00,05,0d,15,86,8e,a6,ae
    0x0b => { #JD
        Name => 'AFPointsInFocus',
        Notes => q{
            may report two points in focus even though a single AFPoint has been
            selected, in which case the selected AFPoint is the first reported
        },
        PrintConv => {
            0 => 'None',
            1 => 'Lower-left, Bottom',
            2 => 'Bottom',
            3 => 'Lower-right, Bottom',
            4 => 'Mid-left, Center',
            5 => 'Center (horizontal)', #PH
            6 => 'Mid-right, Center',
            7 => 'Upper-left, Top',
            8 => 'Top',
            9 => 'Upper-right, Top',
            10 => 'Right',
            11 => 'Lower-left, Mid-left',
            12 => 'Upper-left, Mid-left',
            13 => 'Bottom, Center',
            14 => 'Top, Center',
            15 => 'Lower-right, Mid-right',
            16 => 'Upper-right, Mid-right',
            17 => 'Left',
            18 => 'Mid-left',
            19 => 'Center (vertical)', #PH
            20 => 'Mid-right',
        },
    },
);

# color information - PH
%Image::ExifTool::Pentax::ColorInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    FORMAT => 'int8s',
    16 => {
        Name => 'WBShiftAB',
        Notes => 'positive is a shift toward blue',
    },
    17 => {
        Name => 'WBShiftMG',
        Notes => 'positive is a shift toward green',
    },
);

# EV step size information - ref 19
%Image::ExifTool::Pentax::EVStepInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 1,
    FORMAT => 'int8u',
    FIRST_ENTRY => 0,
    0 => {
        Name => 'EVSteps',
        PrintConv => {
            0 => '1/2 EV Steps',
            1 => '1/3 EV Steps',
        },
    },
    1 => {
        Name => 'SensitivitySteps',
        PrintConv => {
            0 => '1 EV Steps',
            1 => 'As EV Steps',
        },
    },
);

# unknown information - PH
%Image::ExifTool::Pentax::UnknownInfo = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    WRITABLE => 1,
    FIRST_ENTRY => 0,
    # first 8 bytes seem to be short integers which change with ISO (value is
    # usually close to ISO/100) possibly smoothing or gain parameters? - PH
    # byte 0-1 - Higher for high color temperatures (red boost or red noise supression?)
    # byte 6-7 - Higher for low color temperatures (blue boost or blue noise supression?)
    # also changing are bytes 10,11,14,15
);

# Pentax type 2 (Casio-like) maker notes (ref 1)
%Image::ExifTool::Pentax::Type2 = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    WRITABLE => 'int16u',
    NOTES => q{
        These tags are used by the Pentax Optio 330 and 430, and are similar to the
        tags used by Casio.
    },
    0x0001 => {
        Name => 'RecordingMode',
        PrintConv => {
            0 => 'Auto',
            1 => 'Night Scene',
            2 => 'Manual',
        },
    },
    0x0002 => {
        Name => 'Quality',
        PrintConv => {
            0 => 'Good',
            1 => 'Better',
            2 => 'Best',
        },
    },
    0x0003 => {
        Name => 'FocusMode',
        PrintConv => {
            2 => 'Custom',
            3 => 'Auto',
        },
    },
    0x0004 => {
        Name => 'FlashMode',
        PrintConv => {
            1 => 'Auto',
            2 => 'On',
            4 => 'Off',
            6 => 'Red-eye reduction',
        },
    },
    # Casio 0x0005 is FlashIntensity
    # Casio 0x0006 is ObjectDistance
    0x0007 => {
        Name => 'WhiteBalance',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Shade',
            3 => 'Tungsten',
            4 => 'Fluorescent',
            5 => 'Manual',
        },
    },
    0x000a => {
        Name => 'DigitalZoom',
        Writable => 'int32u',
    },
    0x000b => {
        Name => 'Sharpness',
        PrintConv => {
            0 => 'Normal',
            1 => 'Soft',
            2 => 'Hard',
        },
    },
    0x000c => {
        Name => 'Contrast',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
        },
    },
    0x000d => {
        Name => 'Saturation',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
        },
    },
    0x0014 => {
        Name => 'ISO',
        Priority => 0,
        PrintConv => {
            10 => 100,
            16 => 200,
            50 => 50, #PH
            100 => 100, #PH
            200 => 200, #PH
            400 => 400, #PH
            800 => 800, #PH
            1600 => 1600, #PH
            3200 => 3200, #PH
        },
    },
    0x0017 => {
        Name => 'ColorFilter',
        PrintConv => {
            1 => 'Full',
            2 => 'Black & White',
            3 => 'Sepia',
        },
    },
    # Casio 0x0018 is AFPoint
    # Casio 0x0019 is FlashIntensity
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        Writable => 0,
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
        },
    },
    0x1000 => {
        Name => 'HometownCityCode',
        Writable => 'undef',
        Count => 4,
    },
    0x1001 => { #PH
        Name => 'DestinationCityCode',
        Writable => 'undef',
        Count => 4,
    },
);

# ASCII-based maker notes of Optio E20 - PH
%Image::ExifTool::Pentax::Type4 = (
    PROCESS_PROC => \&Image::ExifTool::HP::ProcessHP,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    NOTES => q{
        The following few tags are extracted from the wealth of information
        available in maker notes of the Optio E20.  These maker notes are stored as
        ASCII text in a format very similar to some HP models.
    },
   'F/W Version' => 'FirmwareVersion',
);

# tags in Pentax QuickTime videos (PH - tests with Optio WP)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::Pentax::MOV = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => 'This information is found in Pentax MOV videos.',
    0x00 => {
        Name => 'Make',
        Format => 'string[24]',
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
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
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
        Name => 'ISO',
        Format => 'int16u',
    },
);

#------------------------------------------------------------------------------
# Convert Pentax hex-based EV (modulo 8) to real number
# Inputs: 0) value to convert
# ie) 0x00 -> 0
#     0x03 -> 0.33333
#     0x04 -> 0.5
#     0x05 -> 0.66666
#     0x08 -> 1   ...  etc
sub PentaxEv($)
{
    my $val = shift;
    if ($val & 0x01) {
        my $sign = $val < 0 ? -1 : 1;
        my $frac = ($val * $sign) & 0x07;
        if ($frac == 0x03) {
            $val += $sign * ( 8 / 3 - $frac);
        } elsif ($frac == 0x05) {
            $val += $sign * (16 / 3 - $frac);
        }
    }
    return $val / 8;
}

#------------------------------------------------------------------------------
# Convert number to Pentax hex-based EV (modulo 8)
# Inputs: 0) number
# Returns: Pentax EV code
sub PentaxEvInv($)
{
    my $num = shift;
    my $val = $num * 8;
    # extra fudging makes sure 0.3 and 0.33333 both round up to 3, etc
    my $sign = $num < 0 ? -1 : 1;
    my $inum = $num * $sign - int($num * $sign);
    if ($inum > 0.29 and $inum < 0.4) {
        $val += $sign / 3; 
    } elsif ($inum > 0.6 and $inum < .71) {
        $val -= $sign / 3;
    }
    return int($val + 0.5 * $sign);
}

#------------------------------------------------------------------------------
# Encrypt or decrypt Pentax ShutterCount (symmetrical encryption) - PH
# Inputs: 0) shutter count value, 1) ExifTool object ref
# Returns: Encrypted or decrypted ShutterCount
sub CryptShutterCount($$)
{
    my ($val, $exifTool) = @_;
    # Pentax Date and Time values are used in the encryption
    return undef unless $$exifTool{PentaxDate} and $$exifTool{PentaxTime} and
        length($$exifTool{PentaxDate})==4 and length($$exifTool{PentaxTime})>=3;
    # get Date and Time as integers (after padding Time with a null byte)
    my $date = unpack('N', $$exifTool{PentaxDate});
    my $time = unpack('N', $$exifTool{PentaxTime} . "\0");
    return $val ^ $date ^ (0xffffffff - $time);
}


1; # end

__END__

=head1 NAME

Image::ExifTool::Pentax - Pentax/Asahi maker notes tags

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Pentax and Asahi maker notes in EXIF information.

=head1 NOTES

I couldn't find a good source for Pentax maker notes information, but I've
managed to discover a fair bit of information by analyzing sample images
downloaded from the internet, and through tests with my own Optio WP and
K10D, and with help provided by other ExifTool users (see
L</ACKNOWLEDGEMENTS>).

The Pentax maker notes are stored in standard EXIF format, but the offsets
used for some of their cameras are wacky.  The Optio 330 gives the offset
relative to the offset of the tag in the directory, the Optio WP uses a base
offset in the middle of nowhere, and the Optio 550 uses different (and
totally illogical) bases for different menu entries.  Very weird.  (It
wouldn't surprise me if Pentax can't read their own maker notes!)  Luckily,
there are only a few entries in the maker notes which are large enough to
require offsets, so this doesn't affect much useful information.  ExifTool
attempts to make sense of this fiasco by making an assumption about where
the information should be stored to deduce the correct offsets.

=head1 REFERENCES

=over 4

=item L<Image::MakerNotes::Pentax|Image::MakerNotes::Pentax>

=item L<http://johnst.org/sw/exiftags/> (Asahi models)

=item L<http://kobe1995.jp/~kaz/astro/istD.html>

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=item (...plus lots of testing with my Optio WP and K10D!)

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Wayne Smith, John Francis, Douglas O'Brien Cvetan Ivanov, Jens
Duttke and Dave Nicholson for help figuring out some Pentax tags, Denis
Bourez, Kazumichi Kawabata, David Buret, Barney Garrett and Axel Kellner for
adding to the LensType list, and Ger Vermeulen for contributing print
conversion values for some tags.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/Pentax Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>,
L<Image::Info(3pm)|Image::Info>

=cut
