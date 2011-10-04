#------------------------------------------------------------------------------
# File:         ExifTool.pm
#
# Description:  Read and write meta information
#
# URL:          http://owl.phy.queensu.ca/~phil/exiftool/
#
# Revisions:    Nov. 12/2003 - P. Harvey Created
#               (See html/history.html for revision history)
#
# Legal:        Copyright (c) 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)
#               This library is free software; you can redistribute it and/or
#               modify it under the same terms as Perl itself.
#------------------------------------------------------------------------------

package Image::ExifTool;

use strict;
require 5.004;  # require 5.004 for UNIVERSAL::isa (otherwise 5.002 would do)
require Exporter;
use File::RandomAccess;
    
use vars qw($VERSION $RELEASE @ISA %EXPORT_TAGS $AUTOLOAD @fileTypes %allTables
            @tableOrder $exifAPP1hdr $xmpAPP1hdr $psAPP13hdr $psAPP13old
            @loadAllTables %UserDefined $evalWarning @noWriteTIFF);

$VERSION = '7.34';
$RELEASE = '';
@ISA = qw(Exporter);
%EXPORT_TAGS = (
    # all public non-object-oriented functions:
    Public => [qw(
        ImageInfo GetTagName GetShortcuts GetAllTags GetWritableTags
        GetAllGroups GetDeleteGroups GetFileType CanWrite CanCreate
    )],
    # exports not part of the public API, but used by ExifTool modules:
    DataAccess => [qw(
        ReadValue GetByteOrder SetByteOrder ToggleByteOrder Get8u Get8s Get16u
        Get16s Get32u Get32s GetFloat GetDouble GetFixed32s Write WriteValue
        Tell Set8u Set8s Set16u Set32u
    )],
    Utils => [qw(
        GetTagTable TagTableKeys GetTagInfoList GenerateTagIDs
    )],
    Vars => [qw(
        %allTables @tableOrder @fileTypes
    )],
);
# set all of our EXPORT_TAGS in EXPORT_OK
Exporter::export_ok_tags(keys %EXPORT_TAGS);

# test for problems that can arise if encoding.pm is used
{ my $t = "\xff"; die "Incompatible encoding!\n" if ord($t) != 0xff; }

# The following functions defined in Image::ExifTool::Writer are declared
# here so their prototypes will be available.  The Writer routines will be
# autoloaded when any of these are called.
sub SetNewValue($;$$%);
sub SetNewValuesFromFile($$;@);
sub GetNewValues($;$$);
sub CountNewValues($);
sub SaveNewValues($);
sub RestoreNewValues($);
sub WriteInfo($$;$$);
sub SetFileModifyDate($$;$);
sub SetFileName($$;$);
sub GetAllTags(;$);
sub GetWritableTags(;$);
sub GetAllGroups($);
sub GetNewGroups($);
sub GetDeleteGroups();
# non-public routines below
sub InsertTagValues($$$;$);
sub IsWritable($);
sub GetNewFileName($$);
sub LoadAllTables();
sub GetNewTagInfoList($;$);
sub GetNewTagInfoHash($@);
sub GetLangInfo($$);
sub Get64s($$);
sub Get64u($$);
sub GetExtended($$);
sub DecodeBits($$;$);
sub EncodeBits($$;$$);
sub HexDump($;$%);
sub DumpTrailer($$);
sub DumpUnknownTrailer($$);
sub VerboseInfo($$$%);
sub VerboseDir($$;$$);
sub VPrint($$@);
sub Rationalize($;$);
sub Write($@);
sub ProcessTrailers($$);
sub WriteTrailerBuffer($$$);
sub AddNewTrailers($;@);
sub Tell($);
sub WriteValue($$;$$$$);
sub WriteDirectory($$$;$);
sub WriteBinaryData($$$);
sub CheckBinaryData($$$);
sub WriteTIFF($$$);
sub Charset2Unicode($$;$);
sub Latin2Unicode($$);
sub UTF82Unicode($$;$);
sub Unicode2Charset($$;$);
sub Unicode2Latin($$;$);
sub Unicode2UTF8($$);
sub PackUTF8(@);
sub UnpackUTF8($);

# list of main tag tables to load in LoadAllTables() (sub-tables are recursed
# automatically).  Note: They will appear in this order in the documentation
# (unless tweaked in BuildTagLookup::GetTableOrder()), so put Exif first.
@loadAllTables = qw(
    PhotoMechanic Exif GeoTiff CanonRaw KyoceraRaw MinoltaRaw SigmaRaw JPEG
    Jpeg2000 BMP BMP PICT PNG MNG MIFF PDF PostScript Photoshop::Header
    FujiFilm::RAF Panasonic::Raw Sony::SR2SubIFD ITC ID3 Vorbis FLAC APE
    APE::NewHeader APE::OldHeader MPC MPEG::Audio MPEG::Video MPEG::VBR
    QuickTime QuickTime::ImageFile Flash Flash::FLV Real::Media Real::Audio
    Real::Metafile RIFF AIFF ASF DICOM MIE HTML XMP::SVG
);

# recognized file types, in the order we test unknown files
# Notes: 1) There is no need to test for like types separately here
# 2) Put types with no file signature at end of list to avoid false matches
@fileTypes = qw(JPEG CRW TIFF GIF MRW RAF X3F JP2 PNG MIE MIFF PS PDF PSD XMP
                BMP PPM RIFF AIFF ASF MOV MPEG Real SWF FLV OGG FLAC APE MPC
                ICC ITC HTML VRD QTIF FPX PICT MP3 DICM RAW);

# file types that we can write (edit)
my @writeTypes = qw(JPEG TIFF GIF CRW MRW ORF RAF PNG MIE PSD XMP PPM EPS PS
                    PDF ICC VRD JP2);

# TIFF-based file extensions that we can't write
@noWriteTIFF = qw(3FR DCR K25 KDC ARW SRF SR2);

# file types that we can create from scratch
# - must update CanCreate() documentation if this list is changed!
my @createTypes = qw(XMP ICC MIE VRD);

# file type lookup for all recognized file extensions
my %fileTypeLookup = (
   '3FR' => ['TIFF', 'Hasselblad RAW format (TIFF-like)'],
    ACR  => ['DICM', 'American College of Radiology ACR-NEMA'],
    AI   => [['PDF','PS'], 'Adobe Illustrator (PDF-like or PS-like)'],
    AIF  => ['AIFF', 'Audio Interchange File Format'],
    AIFC => ['AIFF', 'Audio Interchange File Format Compressed'],
    AIFF => ['AIFF', 'Audio Interchange File Format'],
    APE  => ['APE',  "Monkey's Audio format"],
    ARW  => ['TIFF', 'Sony Alpha RAW format (TIFF-like)'],
    ASF  => ['ASF',  'Microsoft Advanced Systems Format'],
    AVI  => ['RIFF', 'Audio Video Interleaved (RIFF-based)'],
    BMP  => ['BMP',  'Windows BitMaP'],
    BTF  => ['BTF',  'Big Tagged Image File Format'],
    CIFF => ['CRW',  'Camera Image File Format (same as CRW)'],
    CR2  => ['TIFF', 'Canon RAW 2 format (TIFF-like)'],
    CRW  => ['CRW',  'Canon RAW format'],
    CS1  => ['PSD',  'Sinar CaptureShop 1-Shot RAW (PSD-like)'],
    DC3  => ['DICM', 'DICOM image file'],
    DCM  => ['DICM', 'DICOM image file'],
    DIB  => ['BMP',  'Device Independent Bitmap (aka. BMP)'],
    DIC  => ['DICM', 'DICOM image file'],
    DICM => ['DICM', 'DICOM image file'],
    DIVX => ['ASF',  'DivX media format (ASF-based)'],
    DNG  => ['TIFF', 'Digital Negative (TIFF-like)'],
    DCR  => ['TIFF', 'Kodak Digital Camera RAW (TIFF-like)'],
    DOC  => ['FPX',  'Microsoft Word Document (FPX-like)'],
    EPS  => ['EPS',  'Encapsulated PostScript Format'],
    EPSF => ['EPS',  'Encapsulated PostScript Format'],
    ERF  => ['TIFF', 'Epson Raw Format (TIFF-like)'],
    FLAC => ['FLAC', 'Free Lossless Audio Codec'],
    FLV  => ['FLV',  'Flash Video'],
    FPX  => ['FPX',  'FlashPix'],
    GIF  => ['GIF',  'Compuserve Graphics Interchange Format'],
    HDP  => ['TIFF', 'Windows HD Photo (TIFF-based)'],
    HTM  => ['HTML', 'HyperText Markup Language'],
    HTML => ['HTML', 'HyperText Markup Language'],
    ICC  => ['ICC',  'International Color Consortium'],
    ICM  => ['ICC',  'International Color Consortium'],
    ITC  => ['ITC',  'iTunes Cover Flow'],
    JNG  => ['PNG',  'JPG Network Graphics (PNG-like)'],
    JP2  => ['JP2',  'JPEG 2000 file'],
    JPEG => ['JPEG', 'Joint Photographic Experts Group'],
    JPG  => ['JPEG', 'Joint Photographic Experts Group'],
    JPX  => ['JP2',  'JPEG 2000 file'],
    K25  => ['TIFF', 'Kodak DC25 RAW (TIFF-like)'],
    KDC  => ['TIFF', 'Kodak Digital Camera RAW (TIFF-like)'],
    M4A  => ['MOV',  'MPG4 Audio (QuickTime-based)'],
    MEF  => ['TIFF', 'Mamiya (RAW) Electronic Format (TIFF-like)'],
    MIE  => ['MIE',  'Meta Information Encapsulation format'],
    MIF  => ['MIFF', 'Magick Image File Format'],
    MIFF => ['MIFF', 'Magick Image File Format'],
    MNG  => ['PNG',  'Multiple-image Network Graphics (PNG-like)'],
    MOS  => ['TIFF', 'Creo Leaf Mosaic (TIFF-like)'],
    MOV  => ['MOV',  'Apple QuickTime movie'],
    MP3  => ['MP3',  'MPEG Layer 3 audio (uses ID3 information)'],
    MP4  => ['MOV',  'MPEG Layer 4 video (QuickTime-based)'],
    MPC  => ['MPC',  'Musepack Audio'],
    MPEG => ['MPEG', 'MPEG audio/video format 1'],
    MPG  => ['MPEG', 'MPEG audio/video format 1'],
    MRW  => ['MRW',  'Minolta RAW format'],
    NEF  => ['TIFF', 'Nikon (RAW) Electronic Format (TIFF-like)'],
    OGG  => ['OGG',  'Ogg Vorbis audio file'],
    ORF  => ['ORF',  'Olympus RAW format'],
    PBM  => ['PPM',  'Portable BitMap (PPM-like)'],
    PCT  => ['PICT', 'Apple PICTure'],
    PDF  => ['PDF',  'Adobe Portable Document Format'],
    PEF  => ['TIFF', 'Pentax (RAW) Electronic Format (TIFF-like)'],
    PGM  => ['PPM',  'Portable Gray Map (PPM-like)'],
    PICT => ['PICT', 'Apple PICTure'],
    PNG  => ['PNG',  'Portable Network Graphics'],
    PPM  => ['PPM',  'Portable Pixel Map'],
    PPT  => ['FPX',  'Microsoft PowerPoint presentation (FPX-like)'],
    PS   => ['PS',   'PostScript'],
    PSD  => ['PSD',  'PhotoShop Drawing'],
    QIF  => ['QTIF', 'QuickTime Image File'],
    QT   => ['MOV',  'QuickTime movie'],
    QTI  => ['QTIF', 'QuickTime Image File'],
    QTIF => ['QTIF', 'QuickTime Image File'],
    RA   => ['Real', 'Real Audio'],
    RAF  => ['RAF',  'FujiFilm RAW Format'],
    RAM  => ['Real', 'Real Audio Metafile'],
    RAW  => ['RAW',  'Kyocera Contax N Digital RAW or Panasonic RAW'],
    RIF  => ['RIFF', 'Resource Interchange File Format'],
    RIFF => ['RIFF', 'Resource Interchange File Format'],
    RM   => ['Real', 'Real Media'],
    RMVB => ['Real', 'Real Media Variable Bitrate'],
    RPM  => ['Real', 'Real Media Plug-in Metafile'],
    RV   => ['Real', 'Real Video'],
    SR2  => ['TIFF', 'Sony RAW Format 2 (TIFF-like)'],
    SRF  => ['TIFF', 'Sony RAW Format (TIFF-like)'],
    SVG  => ['XMP',  'Scalable Vector Graphics (XML-based)'],
    SWF  => ['SWF',  'Shockwave Flash'],
    THM  => ['JPEG', 'Canon Thumbnail (aka. JPG)'],
    TIF  => ['TIFF', 'Tagged Image File Format'],
    TIFF => ['TIFF', 'Tagged Image File Format'],
    VRD  => ['VRD',  'Canon VRD Recipe Data (written by DPP)'],
    WAV  => ['RIFF', 'WAVeform (Windows digital audio format)'],
    WDP  => ['TIFF', 'Windows Media Photo (TIFF-based)'],
    WMA  => ['ASF',  'Windows Media Audio (ASF-based)'],
    WMV  => ['ASF',  'Windows Media Video (ASF-based)'],
    X3F  => ['X3F',  'Sigma RAW format'],
    XHTML=> ['HTML', 'Extensible HyperText Markup Language'],
    XLS  => ['FPX',  'Microsoft Excel worksheet (FPX-like)'],
    XMP  => ['XMP',  'Extensible Metadata Platform data file'],
);

# MIME types for applicable file types above
# (missing entries default to 'application/unknown')
my %mimeType = (
   '3FR' => 'image/x-raw',
    AIFF => 'audio/aiff',
    APE  => 'audio/x-monkeys-audio',
    ASF  => 'video/x-ms-asf',
    ARW  => 'image/x-raw',
    AVI  => 'video/avi',
    BMP  => 'image/bmp',
    BTF  => 'application/unknown', #TEMPORARY!
   'Canon 1D RAW' => 'image/x-raw', # (uses .TIF file extension)
    CR2  => 'image/x-raw',
    CRW  => 'image/x-raw',
    EPS  => 'application/postscript',
    ERF  => 'image/x-raw',
    DCR  => 'image/x-raw',
    DICM => 'application/dicom',
    DIVX => 'video/divx',
    DNG  => 'image/x-raw',
    DOC  => 'application/msword',
    FLAC => 'audio/flac',
    FLV  => 'video/x-flv',
    FPX  => 'image/vnd.fpx',
    GIF  => 'image/gif',
    HDP  => 'image/vnd.ms-photo',
    HTML => 'text/html',
    ITC  => 'application/itunes',
    JNG  => 'image/jng',
    JP2  => 'image/jp2',
    JPEG => 'image/jpeg',
    K25  => 'image/x-raw',
    KDC  => 'image/x-raw',
    M4A  => 'audio/mp4',
    MEF  => 'image/x-raw',
    MIE  => 'application/x-mie',
    MIFF => 'application/x-magick-image',
    MNG  => 'video/mng',
    MOS  => 'image/x-raw',
    MOV  => 'video/quicktime',
    MP3  => 'audio/mpeg',
    MP4  => 'video/mp4',
    MPC  => 'audio/x-musepack',
    MPEG => 'video/mpeg',
    MRW  => 'image/x-raw',
    NEF  => 'image/x-raw',
    OGG  => 'audio/x-ogg',
    ORF  => 'image/x-raw',
    PBM  => 'image/x-portable-bitmap',
    PDF  => 'application/pdf',
    PEF  => 'image/x-raw',
    PGM  => 'image/x-portable-graymap',
    PICT => 'image/pict',
    PNG  => 'image/png',
    PPM  => 'image/x-portable-pixmap',
    PPT  => 'application/vnd.ms-powerpoint',
    PS   => 'application/postscript',
    PSD  => 'application/photoshop',
    QTIF => 'image/x-quicktime',
    RA   => 'audio/x-pn-realaudio',
    RAF  => 'image/x-raw',
    RAM  => 'audio/x-pn-realaudio',
    RAW  => 'image/x-raw',
    RM   => 'application/vnd.rn-realmedia',
    RMVB => 'application/vnd.rn-realmedia-vbr',
    RPM  => 'audio/x-pn-realaudio-plugin',
    RV   => 'video/vnd.rn-realvideo',
    SR2  => 'image/x-raw',
    SRF  => 'image/x-raw',
    SVG  => 'image/svg+xml',
    SWF  => 'application/x-shockwave-flash',
    TIFF => 'image/tiff',
    WAV  => 'audio/x-wav',
    WDP  => 'image/vnd.ms-photo',
    WMA  => 'audio/x-ms-wma',
    WMV  => 'video/x-ms-wmv',
    X3F  => 'image/x-raw',
    XLS  => 'application/vnd.ms-excel',
    XMP  => 'application/rdf+xml',
);

# module names for each file type
# (missing entries have same module name as file type)
my %moduleName = (
    BTF  => 'BigTIFF',
    CRW  => 'CanonRaw',
    DICM => 'DICOM',
    EPS  => 'PostScript',
    ICC  => 'ICC_Profile',
    FLV  => 'Flash',
    FPX  => 'FlashPix',
    JP2  => 'Jpeg2000',
    JPEG => '',     # (in the current module)
    MOV  => 'QuickTime',
    MP3  => 'ID3',
    MRW  => 'MinoltaRaw',
    OGG  => 'Vorbis',
    ORF  => 'Olympus',
    PS   => 'PostScript',
    PSD  => 'Photoshop',
    QTIF => 'QuickTime',
    RAF  => 'FujiFilm',
    RAW  => 'KyoceraRaw',
    SWF  => 'Flash',
    TIFF => '',
    VRD  => 'CanonVRD',
    X3F  => 'SigmaRaw',
);

# default group priority for writing
my @defaultWriteGroups = qw(EXIF IPTC XMP MakerNotes Photoshop ICC_Profile CanonVRD);

# group hash for ExifTool-generated tags
my %allGroupsExifTool = ( 0 => 'ExifTool', 1 => 'ExifTool', 2 => 'ExifTool' );

# headers for various segment types
$exifAPP1hdr = "Exif\0\0";
$xmpAPP1hdr = "http://ns.adobe.com/xap/1.0/\0";
$psAPP13hdr = "Photoshop 3.0\0";
$psAPP13old = 'Adobe_Photoshop2.5:';

sub DummyWriteProc { return 1; }

# tag information for preview image -- this should be used for all
# PreviewImage tags so they are handled properly when reading/writing
%Image::ExifTool::previewImageTagInfo = (
    Name => 'PreviewImage',
    Writable => 'undef',
    # a value of 'none' is ok...
    WriteCheck => '$val eq "none" ? undef : $self->CheckImage(\$val)',
    DataTag => 'PreviewImage',
    # we allow preview image to be set to '', but we don't want a zero-length value
    # in the IFD, so set it temorarily to 'none'.  Note that the length is <= 4,
    # so this value will fit in the IFD so the preview fixup won't be generated.
    RawConv => '$self->ValidateImage(\$val,$tag)',
    ValueConvInv => '$val eq "" and $val="none"; $val',
);

# extra tags that aren't truly EXIF tags, but are generated by the script
# Note: any tag in this list with a name corresponding to a Group0 name is
#       used to write the entire corresponding directory as a block.
%Image::ExifTool::Extra = (
    GROUPS => { 0 => 'File', 1 => 'File', 2 => 'Image' },
    DID_TAG_ID => 1,   # tag ID's aren't meaningful for these tags
    WRITE_PROC => \&DummyWriteProc,
    Comment => {
        Notes => 'comment embedded in JPEG, GIF89a or PPM/PGM/PBM image',
        Writable => 1,
        WriteGroup => 'Comment',
        Priority => 0,  # to preserve order of JPEG COM segments
    },
    Directory => {
        Writable => 1,
        Protected => 1,
        # translate backslashes in directory names and add trailing '/'
        ValueConvInv => '$_=$val; tr/\\\\/\//; m{[^/]$} and $_ .= "/"; $_',
    },
    FileName => {
        Writable => 1,
        Protected => 1,
        ValueConvInv => '$val=~tr/\\\\/\//; $val',
    },
    FileSize => {
        PrintConv => sub {
            my $val = shift;
            $val < 2048 and return "$val bytes";
            $val < 2097152 and return sprintf('%.0f kB', $val / 1024);
            return sprintf('%.0f MB', $val / 1048576);
        },
    },
    FileType    => { },
    FileModifyDate => {
        Description => 'File Modification Date/Time',
        Notes => 'the filesystem modification time',
        Groups => { 2 => 'Time' },
        Writable => 1,
        # all pseudo-tags must be protected so -tagsfromfile fails with
        # unrecognized files unless a pseudo tag is specified explicitly
        Protected => 1,
        Shift => 'Time',
        ValueConv => 'ConvertUnixTime($val,"local")',
        ValueConvInv => 'GetUnixTime($val,"local")',
        PrintConv => '$self->ConvertDateTime($val)',
        PrintConvInv => '$self->InverseDateTime($val)', 
    },
    MIMEType    => { },
    ImageWidth  => { },
    ImageHeight => { },
    XResolution => { },
    YResolution => { },
    MaxVal      => { }, # max pixel value in PPM or PGM image
    EXIF => {
        Notes => 'the full EXIF data block for JPEG images',
        Groups => { 0 => 'EXIF' },
        Binary => 1,
    },
    ICC_Profile => {
        Notes => 'the full ICC_Profile data block',
        Groups => { 0 => 'ICC_Profile' },
        Flags => ['Writable' ,'Protected', 'Binary'],
        WriteCheck => q{
            require Image::ExifTool::ICC_Profile;
            return Image::ExifTool::ICC_Profile::ValidateICC(\$val);
        },
    },
    XMP => {
        Notes => 'the full XMP data block',
        Groups => { 0 => 'XMP' },
        # (not necessary to make this Protected since it
        # isn't extracted with the Binary option)
        Flags => [ 'Writable', 'Binary' ],
        WriteCheck => q{
            require Image::ExifTool::XMP;
            return Image::ExifTool::XMP::CheckXMP($self, $tagInfo, \$val);
        },
    },
    CanonVRD => {
        Notes => 'the full Canon DPP VRD trailer block',
        Groups => { 0 => 'CanonVRD' },
        WriteGroup => 'MakerNotes', # (so VRDOffset will get updated)
        Flags => ['Writable' ,'Protected', 'Binary'],
        Permanent => 0, # (this is 1 by default for MakerNotes tags)
        WriteCheck => q{
            return undef if $val =~ /^CANON OPTIONAL DATA\0/;
            return 'Invalid CanonVRD data';
        },
    },
    Encryption  => { }, # PDF encryption filter
    ExifByteOrder => {
        Writable => 1,
        Notes => 'only writable for newly created EXIF segments',
        PrintConv => {
            II => 'Little-endian (Intel, II)',
            MM => 'Big-endian (Motorola, MM)',
        },
    },
    ExifUnicodeByteOrder => {
        Writable => 1,
        Notes => q{
            the EXIF specification is particularly vague about the byte ordering for
            Unicode text, and different applications use different conventions.  By
            default ExifTool writes Unicode text in EXIF byte order, but this write-only
            tag may be used to force a specific byte order
        },
        PrintConv => {
            II => 'Little-endian (Intel, II)',
            MM => 'Big-endian (Motorola, MM)',
        },
    },
    ExifToolVersion => {
        Description => 'ExifTool Version Number',
        Groups => \%allGroupsExifTool,
    },
    GIFVersion => { },
    Now => {
        Groups => { 0 => 'ExifTool', 1 => 'ExifTool', 2 => 'Time' },
        Notes => q{
            used to set the value of a tag to the current date/time. Not generated unless
            specified
        },
        ValueConv => q{
            my @tm = localtime;
            sprintf("%4d:%.2d:%.2d %.2d:%.2d:%.2d", $tm[5]+1900, $tm[4]+1, $tm[3],
                    $tm[2], $tm[1], $tm[0]);
        },
        PrintConv => '$self->ConvertDateTime($val)',
    },
    ID3Size     => { },
    Error       => { Priority => 0, Groups => \%allGroupsExifTool },
    Warning     => { Priority => 0, Groups => \%allGroupsExifTool },
);

# information decoded from JPEG SOF frame
# (define this here to avoid loading JPEG.pm)
# (ref http://www.w3.org/Graphics/JPEG/itu-t81.pdf)
%Image::ExifTool::JPEG::SOF = (
    GROUPS => { 0 => 'File', 1 => 'File', 2 => 'Image' },
    NOTES => 'This information is extracted from the JPEG Start Of Frame segment.',
    VARS => { NO_ID => 1 },
    EncodingProcess => {
        PrintHex => 1,
        PrintConv => {
            0x0 => 'Baseline DCT, Huffman coding',
            0x1 => 'Extended sequential DCT, Huffman coding',
            0x2 => 'Progressive DCT, Huffman coding',
            0x3 => 'Lossless, Huffman coding',
            0x5 => 'Sequential DCT, differential Huffman coding',
            0x6 => 'Progressive DCT, differential Huffman coding',
            0x7 => 'Lossless, Differential Huffman coding',
            0x9 => 'Extended sequential DCT, arithmetic coding',
            0xa => 'Progressive DCT, arithmetic coding',
            0xb => 'Lossless, arithmetic coding',
            0xd => 'Sequential DCT, differential arithmetic coding',
            0xe => 'Progressive DCT, differential arithmetic coding',
            0xf => 'Lossless, differential arithmetic coding',
        }
    },
    BitsPerSample    => { },
    ImageHeight      => { },
    ImageWidth       => { },
    ColorComponents  => { },
    YCbCrSubSampling => {
        Notes => 'calculated from components table',
        PrintConv => {
            '1 1' => 'YCbCr4:4:4 (1 1)',
            '2 1' => 'YCbCr4:2:2 (2 1)',
            '2 2' => 'YCbCr4:2:0 (2 2)',
            '4 1' => 'YCbCr4:1:1 (4 1)',
            '4 2' => 'YCbCr4:1:0 (4 2)',
            '1 2' => 'YCbCr4:4:0 (1 2)',
        },
    },
);

# static private ExifTool variables

%allTables = ( );   # list of all tables loaded (except composite tags)
@tableOrder = ( );  # order the tables were loaded

my $didTagID;       # flag indicating we are accessing tag ID's

# composite tags (accumulation of all Composite tag tables)
%Image::ExifTool::Composite = (
    GROUPS => { 0 => 'Composite', 1 => 'Composite' },
    DID_TAG_ID => 1,    # want empty tagID's for composite tags
    WRITE_PROC => \&DummyWriteProc,
);

# JFIF APP0 definitions
%Image::ExifTool::JFIF::Main = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    GROUPS => { 0 => 'JFIF', 1 => 'JFIF', 2 => 'Image' },
    DATAMEMBER => [ 2, 3, 5 ],
    0 => {
        Name => 'JFIFVersion',
        Format => 'int8u[2]',
        PrintConv => '$val=~tr/ /./;$val',
    },
    2 => {
        Name => 'ResolutionUnit',
        Writable => 1,
        RawConv => '$$self{JFIFResolutionUnit} = $val',
        PrintConv => {
            0 => 'None',
            1 => 'inches',
            2 => 'cm',
        },
        Priority => -1,
    },
    3 => {
        Name => 'XResolution',
        Format => 'int16u',
        Writable => 1,
        Priority => -1,
        RawConv => '$$self{JFIFXResolution} = $val',
    },
    5 => {
        Name => 'YResolution',
        Format => 'int16u',
        Writable => 1,
        Priority => -1,
        RawConv => '$$self{JFIFYResolution} = $val',
    },
);
%Image::ExifTool::JFIF::Extension = (
    GROUPS => { 0 => 'JFIF', 1 => 'JFIF', 2 => 'Image' },
    0x10 => {
        Name => 'ThumbnailImage',
        RawConv => '$self->ValidateImage(\$val,$tag)',
    },
);

# special tag names (not used for tag info)
my %specialTags = (
    PROCESS_PROC=>1, WRITE_PROC=>1, CHECK_PROC=>1, GROUPS=>1, FORMAT=>1,
    FIRST_ENTRY=>1, TAG_PREFIX=>1, PRINT_CONV=>1, DID_TAG_ID=>1, WRITABLE=>1,
    NOTES=>1, IS_OFFSET=>1, EXTRACT_UNKNOWN=>1, NAMESPACE=>1, PREFERRED=>1,
    PARENT=>1, PRIORITY=>1, WRITE_GROUP=>1, LANG_INFO=>1, VARS=>1,
    DATAMEMBER=>1, SET_GROUP1=>1,
);

#------------------------------------------------------------------------------
# Warning handler routines (warning string stored in $evalWarning)
#
# Set warning message
# Inputs: 0) warning string (undef to reset warning)
sub SetWarning($) { $evalWarning = $_[0]; }

# Get warning message
sub GetWarning()  { return $evalWarning; }

# Clean unnecessary information (line number, LF) from warning
# Inputs: 0) warning string or undef to use current warning
# Returns: cleaned warning
sub CleanWarning(;$)
{
    my $str = shift;
    unless (defined $str) {
        return undef unless defined $evalWarning;
        $str = $evalWarning;
    }
    $str = $1 if $str =~ /(.*) at /s;
    $str =~ s/\s+$//s;
    return $str;
}

#==============================================================================
# New - create new ExifTool object
# Inputs: 0) reference to exiftool object or ExifTool class name
sub new
{
    local $_;
    my $that = shift;
    my $class = ref($that) || $that || 'Image::ExifTool';
    my $self = bless {}, $class;

    # make sure our main Exif tag table has been loaded
    GetTagTable("Image::ExifTool::Exif::Main");

    $self->ClearOptions();      # create default options hash
    $self->{VALUE} = { };       # must initialize this for warning messages
    $self->{DEL_GROUP} = { };   # list of groups to delete when writing

    # initialize our new groups for writing
    $self->SetNewGroups(@defaultWriteGroups);

    return $self;
}

#------------------------------------------------------------------------------
# ImageInfo - return specified information from image file
# Inputs: 0) [optional] ExifTool object reference
#         1) filename, file reference, or scalar data reference
#         2-N) list of tag names to find (or tag list reference or options reference)
# Returns: reference to hash of tag/value pairs (with "Error" entry on error)
# Notes:
#   - if no tags names are specified, the values of all tags are returned
#   - tags may be specified with leading '-' to exclude
#   - can pass a reference to list of tags to find, in which case the list will
#     be updated with the tags found in the proper case and in the specified order.
#   - can pass reference to hash specifying options
#   - returned tag values may be scalar references indicating binary data
#   - see ClearOptions() below for a list of options and their default values
# Examples:
#   use Image::ExifTool 'ImageInfo';
#   my $info = ImageInfo($file, 'DateTimeOriginal', 'ImageSize');
#    - or -
#   my $exifTool = new Image::ExifTool;
#   my $info = $exifTool->ImageInfo($file, \@tagList, {Sort=>'Group0'} );
sub ImageInfo($;@)
{
    local $_;
    # get our ExifTool object ($self) or create one if necessary
    my $self;
    if (ref $_[0] and UNIVERSAL::isa($_[0],'Image::ExifTool')) {
        $self = shift;
    } else {
        $self = new Image::ExifTool;
    }
    my %saveOptions = %{$self->{OPTIONS}};  # save original options

    # initialize file information
    $self->{FILENAME} = $self->{RAF} = undef;

    $self->ParseArguments(@_);              # parse our function arguments
    $self->ExtractInfo(undef);              # extract meta information from image
    my $info = $self->GetInfo(undef);       # get requested information

    $self->{OPTIONS} = \%saveOptions;       # restore original options

    return $info;   # return requested information
}

#------------------------------------------------------------------------------
# Get/set ExifTool options
# Inputs: 0) ExifTool object reference,
#         1) Parameter name, 2) Value to set the option
#         3-N) More parameter/value pairs
# Returns: original value of last option specified
sub Options($$;@)
{
    local $_;
    my $self = shift;
    my $options = $$self{OPTIONS};
    my $oldVal;

    while (@_) {
        my $param = shift;
        $oldVal = $options->{$param};
        last unless @_;
        $options->{$param} = shift;
        # clone Exclude list and expand shortcuts
        if ($param eq 'Exclude' and defined $options->{$param}) {
            my @exclude;
            my $val = $options->{$param};
            if (ref $val eq 'ARRAY') {
                @exclude = @$val;
            } else {
                @exclude = ($val);
            }
            ExpandShortcuts(\@exclude);
            $options->{$param} = \@exclude;
        }
    }
    return $oldVal;
}

#------------------------------------------------------------------------------
# ClearOptions - set options to default values
# Inputs: 0) ExifTool object reference
sub ClearOptions($)
{
    local $_;
    my $self = shift;

    # create options hash with default values
    # (commented out options don't need initializing)
    $self->{OPTIONS} = {
    #   Binary      => undef,   # flag to extract binary values even if tag not specified
    #   ByteOrder   => undef,   # default byte order when creating EXIF information
        Charset     => 'UTF8',  # character set for converting Unicode characters
    #   Compact     => undef,   # compact XMP and IPTC data
        Composite   => 1,       # flag to calculate Composite tags
    #   Compress    => undef,   # flag to write new values as compressed if possible
    #   CoordFormat => undef,   # GPS lat/long coordinate format
    #   DateFormat  => undef,   # format for date/time
        Duplicates  => 1,       # flag to save duplicate tag values
    #   Exclude     => undef,   # tags to exclude
    #   FastScan    => undef,   # flag to avoid scanning for trailer
    #   FixBase     => undef,   # fix maker notes base offsets
    #   Group#      => undef,   # return tags for specified groups in family #
        HtmlDump    => 0,       # HTML dump (0-3, higher # = bigger limit)
    #   HtmlDumpBase => undef,  # base address for HTML dump
    #   IgnoreMinorErrors => undef, # ignore minor errors when reading/writing
    #   List        => undef,   # extract lists of PrintConv values into arrays
    #   MakerNotes  => undef,   # extract maker notes as a block
    #   MissingTagValue =>undef,# value for missing tags when expanded in expressions
        PrintConv   => 1,       # flag to enable print conversion
    #   ScanForXMP  => undef,   # flag to scan for XMP information in all files
        Sort        => 'Input', # order to sort found tags (Input, File, Alpha, Group#)
    #   StrictDate  => undef,   # flag to return undef for invalid date conversions
        TextOut     => \*STDOUT,# file for Verbose/HtmlDump output
        Unknown     => 0,       # flag to get values of unknown tags (0-2)
        Verbose     => 0,       # print verbose messages (0-4, higher # = more verbose)
    };
}

#------------------------------------------------------------------------------
# Extract meta information from image
# Inputs: 0) ExifTool object reference
#         1-N) Same as ImageInfo()
# Returns: 1 if this was a valid image, 0 otherwise
# Notes: pass an undefined value to avoid parsing arguments
sub ExtractInfo($;@)
{
    local $_;
    my $self = shift;
    my $options = $self->{OPTIONS};     # pointer to current options
    my %saveOptions;

    if (defined $_[0] or $options->{HtmlDump}) {
        %saveOptions = %$options;       # save original options
        
        # require duplicates for html dump
        $self->Options(Duplicates => 1) if $options->{HtmlDump};

        if (defined $_[0]) {
            # only initialize filename if called with arguments
            $self->{FILENAME} = undef;  # name of file (or '' if we didn't open it)
            $self->{RAF} = undef;       # RandomAccess object reference
    
            $self->ParseArguments(@_);  # initialize from our arguments
        }
    }
    # initialize ExifTool object members
    $self->Init();

    delete $self->{MAKER_NOTE_FIXUP};   # fixup information for extracted maker notes
    delete $self->{MAKER_NOTE_BYTE_ORDER};
    delete $self->{DONE_ID3};

    my $filename = $self->{FILENAME};   # image file name ('' if already open)
    my $raf = $self->{RAF};             # RandomAccess object

    # return our version number
    $self->FoundTag('ExifToolVersion', "$VERSION$RELEASE");
    $self->FoundTag('Now', 0) if $self->{REQ_TAG_LOOKUP}->{now} or $self->{TAGS_FROM_FILE};

    local *EXIFTOOL_FILE;   # avoid clashes with global namespace

    unless ($raf) {
        # save file name
        if (defined $filename and $filename ne '') {
            unless ($filename eq '-') {
                my $name = $filename;
                # extract file name from pipe if necessary
                $name =~ /\|$/ and $name =~ s/.*?"(.*)".*/$1/;
                my $dir;
                if (eval 'require File::Basename') {
                    $dir = File::Basename::dirname($name);
                    $name = File::Basename::basename($name);
                } else {
                    $name =~ tr/\\/\//;
                    if ($name =~ s/(.*)\///) {  # remove path
                        $dir = length($1) ? $1 : '/';
                    }
                }
                $self->FoundTag('FileName', $name);
                $self->FoundTag('Directory', $dir) if defined $dir and length $dir;
            }
            # open the file
            if (open(EXIFTOOL_FILE,$filename)) {
                my $filePt = \*EXIFTOOL_FILE;
                # create random access file object
                $raf = new File::RandomAccess($filePt);
                # patch to force pipe to be buffered because seek returns success
                # in Windows cmd shell pipe even though it really failed
                $raf->{TESTED} = -1 if $filename eq '-' or $filename =~ /\|$/;
                $self->{RAF} = $raf;
            } else {
                $self->Error('Error opening file');
            }
        } else {
            $self->Error('No file specified');
        }
    }

    if ($raf) {
        if (not $raf->{FILE_PT}) {
            # get file size from image in memory
            $self->FoundTag('FileSize', length ${$raf->{BUFF_PT}});
        } elsif (-f $raf->{FILE_PT}) {
            # get file size and last modified time if this is a plain file
            my $fileSize = -s _;
            my $fileTime = -M _;
            $self->FoundTag('FileSize', $fileSize) if defined $fileSize;
            $self->FoundTag('FileModifyDate', $^T - $fileTime*(24*3600)) if defined $fileTime;
        }

        # get list of file types to check
        my $tiffType;
        $self->{FILE_EXT} = GetFileExtension($filename);
        my @fileTypeList = GetFileType($filename);
        if (@fileTypeList) {
            # add remaining types to end of list so we test them all
            my $pat = join '|', @fileTypeList;
            push @fileTypeList, grep(!/^($pat)$/, @fileTypes);
            $tiffType = $self->{FILE_EXT};
        } else {
            # scan through all recognized file types
            @fileTypeList = @fileTypes;
            $tiffType = 'TIFF';
        }
        push @fileTypeList, ''; # end of list marker
        # initialize the input file for seeking in binary data
        $raf->BinMode();    # set binary mode before we start reading
        my $pos = $raf->Tell(); # get file position so we can rewind
        my %dirInfo = ( RAF => $raf, Base => $pos );
        # loop through list of file types to test
        my $type;
        for (;;) {
            $type = shift @fileTypeList;
            unless ($type) {
                last unless defined $type;
                # last ditch effort to scan past unknown header for JPEG/TIFF
                my $buff;
                $raf->Read($buff, 1024);
                next unless $buff =~ /(\xff\xd8\xff|MM\0\x2a|II\x2a\0)/g;
                $type = ($1 eq "\xff\xd8\xff") ? 'JPEG' : 'TIFF';
                my $skip = pos($buff) - length($1);
                $dirInfo{Base} = $pos + $skip;
                $raf->Seek($pos + $skip, 0);
                $self->Warn("Skipped unknown $skip byte header");
            }
            # save file type in member variable
            $self->{FILE_TYPE} = $type;
            $dirInfo{Parent} = ($type eq 'TIFF') ? $tiffType : $type;
            my $module = $moduleName{$type};
            $module = $type unless defined $module;
            my $func = "Process$type";

            # load module if necessary
            if ($module) {
                require "Image/ExifTool/$module.pm";
                $func = "Image::ExifTool::${module}::$func";
            }
            # process the file
            no strict 'refs';
            &$func($self, \%dirInfo) and last;
            use strict 'refs';

            # seek back to try again from the same position in the file
            unless ($raf->Seek($pos, 0)) {
                $self->Error('Error seeking in file');
                last;
            }
        }
        # scan for XMP if specified
        if ($self->Options('ScanForXMP') and (not defined $type or
            (not $self->Options('FastScan') and not $$self{FoundXMP})))
        {
            $raf->Seek($pos, 0);
            require Image::ExifTool::XMP;
            Image::ExifTool::XMP::ScanForXMP($self, $raf) and $type = '';
        }
        unless (defined $type) {
            # if we were given a single image with a known type there
            # must be a format error since we couldn't read it, otherwise
            # it is likely we don't support images of this type
            $self->Error(GetFileType($filename) ?
                'File format error' : 'Unknown file type');
        }
        # extract binary EXIF data block only if requested
        if (defined $self->{EXIF_DATA} and $self->{REQ_TAG_LOOKUP}->{exif}) {
            $self->FoundTag('EXIF', $self->{EXIF_DATA});
        }
        # calculate composite tags
        $self->BuildCompositeTags() if $options->{Composite};

        # do our HTML dump if requested
        if ($self->{HTML_DUMP}) {
            $raf->Seek(0, 2);   # seek to end of file
            $self->{HTML_DUMP}->FinishTiffDump($self, $raf->Tell());
            my $pos = $options->{HtmlDumpBase};
            $pos = ($self->{FIRST_EXIF_POS} || 0) unless defined $pos;
            my $dataPt = defined $self->{EXIF_DATA} ? \$self->{EXIF_DATA} : undef;
            undef $dataPt if defined $self->{EXIF_POS} and $pos != $self->{EXIF_POS};
            my $success = $self->{HTML_DUMP}->Print($raf, $dataPt, $pos,
                $options->{TextOut}, $options->{HtmlDump},
                $self->{FILENAME} ? "HTML Dump ($self->{FILENAME})" : 'HTML Dump');
            $self->Warn("Error reading $self->{HTML_DUMP}->{ERROR}") if $success < 0;
        }

        $raf->Close() if $filename;     # close the file if we opened it
    }

    # restore original options
    %saveOptions and $self->{OPTIONS} = \%saveOptions;

    return exists $self->{VALUE}->{Error} ? 0 : 1;
}

#------------------------------------------------------------------------------
# Get hash of extracted meta information
# Inputs: 0) ExifTool object reference
#         1-N) options hash reference, tag list reference or tag names
# Returns: Reference to information hash
# Notes: - pass an undefined value to avoid parsing arguments
#        - If groups are specified, first groups take precedence if duplicate
#          tags found but Duplicates option not set.
sub GetInfo($;@)
{
    local $_;
    my $self = shift;
    my %saveOptions;

    unless (@_ and not defined $_[0]) {
        %saveOptions = %{$self->{OPTIONS}}; # save original options
        # must set FILENAME so it isn't parsed from the arguments
        $self->{FILENAME} = '' unless defined $self->{FILENAME};
        $self->ParseArguments(@_);
    }

    # get reference to list of tags for which we will return info
    my $rtnTags = $self->SetFoundTags();

    # build hash of tag information
    my (%info, %ignored);
    my $conv = $self->{OPTIONS}->{PrintConv} ? 'PrintConv' : 'ValueConv';
    foreach (@$rtnTags) {
        my $val = $self->GetValue($_, $conv);
        defined $val or $ignored{$_} = 1, next;
        $info{$_} = $val;
    }

    # remove ignored tags from the list
    my $reqTags = $self->{REQUESTED_TAGS} || [ ];
    if (%ignored and not @$reqTags) {
        my @goodTags;
        foreach (@$rtnTags) {
            push @goodTags, $_ unless $ignored{$_};
        }
        $rtnTags = $self->{FOUND_TAGS} = \@goodTags;
    }

    # return sorted tag list if provided with a list reference
    if ($self->{IO_TAG_LIST}) {
        # use file order by default if no tags specified
        # (no such thing as 'Input' order in this case)
        my $sortOrder = $self->{OPTIONS}->{Sort};
        unless (@$reqTags or ($sortOrder and $sortOrder ne 'Input')) {
            $sortOrder = 'File';
        }
        # return tags in specified sort order
        @{$self->{IO_TAG_LIST}} = $self->GetTagList($rtnTags, $sortOrder);
    }

    # restore original options
    %saveOptions and $self->{OPTIONS} = \%saveOptions;

    return \%info;
}

#------------------------------------------------------------------------------
# Combine information from a list of info hashes
# Unless Duplicates is enabled, first entry found takes priority
# Inputs: 0) ExifTool object reference, 1-N) list of info hash references
# Returns: Combined information hash reference
sub CombineInfo($;@)
{
    local $_;
    my $self = shift;
    my (%combinedInfo, $info);

    if ($self->{OPTIONS}->{Duplicates}) {
        while ($info = shift) {
            my $key;
            foreach $key (keys %$info) {
                $combinedInfo{$key} = $$info{$key};
            }
        }
    } else {
        my (%haveInfo, $tag);
        while ($info = shift) {
            foreach $tag (keys %$info) {
                my $tagName = GetTagName($tag);
                next if $haveInfo{$tagName};
                $haveInfo{$tagName} = 1;
                $combinedInfo{$tag} = $$info{$tag};
            }
        }
    }
    return \%combinedInfo;
}

#------------------------------------------------------------------------------
# Inputs: 0) ExifTool object reference
#         1) [optional] reference to info hash or tag list ref (default is found tags)
#         2) [optional] sort order ('File', 'Input', ...)
# Returns: List of tags in specified order
sub GetTagList($;$$)
{
    local $_;
    my ($self, $info, $sortOrder) = @_;

    my $foundTags;
    if (ref $info eq 'HASH') {
        my @tags = keys %$info;
        $foundTags = \@tags;
    } elsif (ref $info eq 'ARRAY') {
        $foundTags = $info;
    }
    my $fileOrder = $self->{FILE_ORDER};

    if ($foundTags) {
        # make sure a FILE_ORDER entry exists for all tags
        # (note: already generated bogus entries for FOUND_TAGS case below)
        foreach (@$foundTags) {
            next if defined $$fileOrder{$_};
            $$fileOrder{$_} = 999;
        }
    } else {
        $sortOrder = $info if $info and not $sortOrder;
        $foundTags = $self->{FOUND_TAGS} || $self->SetFoundTags() or return undef;
    }
    $sortOrder or $sortOrder = $self->{OPTIONS}->{Sort};

    # return original list if no sort order specified
    return @$foundTags unless $sortOrder and $sortOrder ne 'Input';

    if ($sortOrder eq 'Alpha') {
        return sort @$foundTags;
    } elsif ($sortOrder =~ /^Group(\d*)/) {
        my $family = $1 || 0;
        # want to maintain a basic file order with the groups
        # ordered in the way they appear in the file
        my (%groupCount, %groupOrder);
        my $numGroups = 0;
        my $tag;
        foreach $tag (sort { $$fileOrder{$a} <=> $$fileOrder{$b} } @$foundTags) {
            my $group = $self->GetGroup($tag, $family);
            my $num = $groupCount{$group};
            $num or $num = $groupCount{$group} = ++$numGroups;
            $groupOrder{$tag} = $num;
        }
        return sort { $groupOrder{$a} <=> $groupOrder{$b} or
                      $$fileOrder{$a} <=> $$fileOrder{$b} } @$foundTags;
    } else {
        return sort { $$fileOrder{$a} <=> $$fileOrder{$b} } @$foundTags;
    }
}

#------------------------------------------------------------------------------
# Get list of found tags in specified sort order
# Inputs: 0) ExifTool object reference, 1) sort order ('File', 'Input', ...)
# Returns: List of tag keys in specified order
# Notes: If not specified, sort order is taken from OPTIONS
sub GetFoundTags($;$)
{
    local $_;
    my ($self, $sortOrder) = @_;
    my $foundTags = $self->{FOUND_TAGS} || $self->SetFoundTags() or return undef;
    return $self->GetTagList($foundTags, $sortOrder);
}

#------------------------------------------------------------------------------
# Get list of requested tags
# Inputs: 0) ExifTool object reference
# Returns: List of requested tag keys
sub GetRequestedTags($)
{
    local $_;
    return @{$_[0]->{REQUESTED_TAGS}};
}

#------------------------------------------------------------------------------
# Get tag value
# Inputs: 0) ExifTool object reference, 1) tag key
#         2) [optional] Value type: PrintConv, ValueConv, Both or Raw, the default
#            is PrintConv or ValueConv, depending on the PrintConv option setting
# Returns: Scalar context: tag value or undefined
#          List context: list of values or empty list
sub GetValue($$;$)
{
    local $_;
    my ($self, $tag, $type) = @_;

    # start with the raw value
    my $value = $self->{VALUE}->{$tag};
    return wantarray ? () : undef unless defined $value;

    # figure out what conversions to do
    my (@convTypes, $tagInfo);
    $type or $type = $self->{OPTIONS}->{PrintConv} ? 'PrintConv' : 'ValueConv';
    unless ($type eq 'Raw') {
        $tagInfo = $self->{TAG_INFO}->{$tag};
        push @convTypes, 'ValueConv';
        push @convTypes, 'PrintConv' unless $type eq 'ValueConv';
    }

    # do the conversions
    my (@val, @prt, @raw, $convType, $valueConv);
    foreach $convType (@convTypes) {
        last if ref $value eq 'SCALAR'; # don't convert a scalar reference
        my $conv = $$tagInfo{$convType};
        unless (defined $conv) {
            if ($convType eq 'ValueConv') {
                next unless $$tagInfo{Binary};
                $conv = '\$val';  # return scalar reference for binary values
            } else {
                # use PRINT_CONV from tag table if PrintConv not defined
                next unless defined($conv = $tagInfo->{Table}->{PRINT_CONV});
            }
        }
        # save old ValueConv value if we want Both
        $valueConv = $value if $type eq 'Both' and $convType eq 'PrintConv';
        my ($i, $val, $vals, @values, $convList);
        # split into list if conversion is an array
        if (ref $conv eq 'ARRAY') {
            $convList = $conv;
            $conv = $$convList[0];
            my @valList = split ' ', $value;
            # reorganize list if specified (Note: The writer currently doesn't
            # relist values, so they may be grouped but the order must not change)
            my $relist = $$tagInfo{Relist};
            if ($relist) {
                my (@newList, $oldIndex);
                foreach $oldIndex (@$relist) {
                    my ($newVal, @join);
                    if (ref $oldIndex) {
                        foreach (@$oldIndex) {
                            push @join, $valList[$_] if defined $valList[$_];
                        }
                        $newVal = join(' ', @join) if @join;
                    } else {
                        $newVal = $valList[$oldIndex];
                    }
                    push @newList, $newVal if defined $newVal;
                }
                $value = \@newList;
            } else {
                $value = \@valList;
            }
        }
        # initialize array so we can iterate over values in list
        if (ref $value eq 'ARRAY') {
            $i = 0;
            $vals = $value;
            $val = $$vals[0];
        } else {
            $val = $value;
        }
        # loop through all values in list
        for (;;) {
            if (defined $conv) {
                # get values of required tags if this is a composite tag
                if (ref $val eq 'HASH' and not @val) {
                    foreach (keys %$val) {
                        $raw[$_] = $self->{VALUE}->{$$val{$_}};
                        ($val[$_], $prt[$_]) = $self->GetValue($$val{$_}, 'Both');
                        next if defined $val[$_] or not $tagInfo->{Require}->{$_};
                        return wantarray ? () : undef;
                    }
                    # set $val to $val[0], or \@val for a CODE ref conversion
                    $val = ref $conv eq 'CODE' ? \@val : $val[0];
                }
                if (ref $conv eq 'HASH') {
                    # look up converted value in hash
                    unless (defined($value = $$conv{$val})) {
                        if ($$conv{BITMASK}) {
                            $value = DecodeBits($val, $$conv{BITMASK});
                        } elsif (not $$conv{OTHER} or
                                 # use alternate conversion routine if available
                                 not defined($value = &{$$conv{OTHER}}($val)))
                        {
                            if (($$tagInfo{PrintHex} or
                                ($$tagInfo{Mask} and not defined $$tagInfo{PrintHex}))
                                and $val and IsInt($val) and $convType eq 'PrintConv')
                            {
                                $val = sprintf('0x%x',$val);
                            }
                            $value = "Unknown ($val)";
                        }
                    }
                } else {
                    # call subroutine or do eval to convert value
                    local $SIG{'__WARN__'} = \&SetWarning;
                    undef $evalWarning;
                    if (ref $conv eq 'CODE') {
                        $value = &$conv($val, $self);
                    } else {
                        #### eval ValueConv/PrintConv ($val, $self, @val, @prt, @raw)
                        $value = eval $conv;
                        $@ and $evalWarning = $@;
                    }
                    if ($evalWarning) {
                        delete $SIG{'__WARN__'};
                        warn "$convType $tag: " . CleanWarning() . "\n";
                    }
                }
            } else {
                $value = $val;
            }
            last unless $vals;
            # save this converted value and step to next value in list
            push @values, $value if defined $value;
            if (++$i >= scalar(@$vals)) {
                $value = \@values if @values;
                last;
            }
            $val = $$vals[$i];
            $conv = $$convList[$i] if $convList;
        }
        # return undefined now if no value
        return wantarray ? () : undef unless defined $value;
        # join back into single value if split for conversion list
        if ($convList and ref $value eq 'ARRAY') {
            $value = join($convType eq 'PrintConv' ? '; ' : ' ', @$value);
        }
    }
    if ($type eq 'Both') {
        # $valueConv is undefined if there was no print conversion done
        $valueConv = $value unless defined $valueConv;
        # return Both values as a list (ValueConv, PrintConv)
        return ($valueConv, $value);
    }
    if (ref $value eq 'ARRAY') {
        # return array if requested
        return @$value if wantarray;
        # return list reference for Raw, ValueConv or if List option set
        return $value if @convTypes < 2 or $self->{OPTIONS}->{List};
        # otherwise join in comma-separated string
        $value = join ', ', @$value;
    }
    return $value;
}

#------------------------------------------------------------------------------
# Get tag identification number
# Inputs: 0) ExifTool object reference, 1) tag key
# Returns: Tag ID if available, otherwise ''
sub GetTagID($$)
{
    local $_;
    my ($self, $tag) = @_;
    my $tagInfo = $self->{TAG_INFO}->{$tag};

    if ($tagInfo) {
        GenerateAllTagIDs();    # make sure tag ID's are generated
        defined $$tagInfo{TagID} and return $$tagInfo{TagID};
    }
    # no ID for this tag (shouldn't happen)
    return '';
}

#------------------------------------------------------------------------------
# Get description for specified tag
# Inputs: 0) ExifTool object reference, 1) tag key
# Returns: Tag description
# Notes: Will always return a defined value, even if description isn't available
sub GetDescription($$)
{
    local $_;
    my ($self, $tag) = @_;
    my $tagInfo = $self->{TAG_INFO}->{$tag};
    # ($tagInfo should be defined for any extracted tag,
    # but we might as well handle the case where it isn't)
    my $desc;
    $desc = $$tagInfo{Description} if $tagInfo;
    # just make the tag more readable if description doesn't exist
    unless ($desc) {
        $desc = MakeDescription(GetTagName($tag));
        # save description in tag information
        $$tagInfo{Description} = $desc if $tagInfo;
    }
    return $desc;
}

#------------------------------------------------------------------------------
# Get group name for specified tag
# Inputs: 0) ExifTool object reference
#         1) tag key (or reference to tagInfo hash, not part of the public API)
#         2) [optional] group family number (-1 to get extended group list)
# Returns: Scalar context: Group name (for family 0 if not otherwise specified)
#          Array context: Group name if family specified, otherwise list of
#          group names for each family.
sub GetGroup($$;$)
{
    local $_;
    my ($self, $tag, $family) = @_;
    my ($tagInfo, @groups, $extra);
    if (ref $tag eq 'HASH') {
        $tagInfo = $tag;
        $tag = $tagInfo->{Name};
    } else {
        $tagInfo = $self->{TAG_INFO}->{$tag} or return '';
    }
    my $groups = $$tagInfo{Groups};
    # fill in default groups unless already done
    unless ($$tagInfo{GotGroups}) {
        my $tagTablePtr = $$tagInfo{Table};
        if ($tagTablePtr) {
            # construct our group list
            $groups or $groups = $$tagInfo{Groups} = { };
            # fill in default groups
            foreach (keys %{$$tagTablePtr{GROUPS}}) {
                $$groups{$_} or $$groups{$_} = $tagTablePtr->{GROUPS}->{$_};
            }
        }
        # set flag indicating group list was built
        $$tagInfo{GotGroups} = 1;
    }
    if (defined $family and $family >= 0) {
        return $$groups{$family} || 'Other' unless $family == 1;
        $groups[$family] = $$groups{$family};
    } else {
        return $$groups{0} unless wantarray;
        foreach (0..2) { $groups[$_] = $$groups{$_}; }
    }
    # modify family 1 group name if necessary
    if ($extra = $self->{GROUP1}->{$tag}) {
        if ($extra =~ /^\+(.*)/) {
            $groups[1] .= $1;
        } else {
            $groups[1] = $extra;
        }
    }
    if ($family) {
        return $groups[1] if $family == 1;
        # add additional matching group names to list
        # ie) for MIE-Doc, also add MIE1, MIE1-Doc, MIE-Doc1 and MIE1-Doc1
        # and for MIE2-Doc3, also add MIE2, MIE-Doc3, MIE2-Doc and MIE-Doc
        if ($groups[1] =~ /^MIE(\d*)-(.+?)(\d*)$/) {
            push @groups, 'MIE' . ($1 || '1');
            push @groups, 'MIE' . ($1 ? '' : '1') . "-$2$3";
            push @groups, "MIE$1-$2" . ($3 ? '' : '1');
            push @groups, 'MIE' . ($1 ? '' : '1') . "-$2" . ($3 ? '' : '1');
        }
    }
    return @groups;
}

#------------------------------------------------------------------------------
# Get group names for specified tags
# Inputs: 0) ExifTool object reference
#         1) [optional] information hash reference (default all extracted info)
#         2) [optional] group family number (default 0)
# Returns: List of group names in alphabetical order
sub GetGroups($;$$)
{
    local $_;
    my $self = shift;
    my $info = shift;
    my $family;

    # figure out our arguments
    if (ref $info ne 'HASH') {
        $family = $info;
        $info = $self->{VALUE};
    } else {
        $family = shift;
    }
    $family = 0 unless defined $family;

    # get a list of all groups in specified information
    my ($tag, %groups);
    foreach $tag (keys %$info) {
        $groups{ $self->GetGroup($tag, $family) } = 1;
    }
    return sort keys %groups;
}

#------------------------------------------------------------------------------
# Set priority for group where new values are written
# Inputs: 0) ExifTool object reference,
#         1-N) group names (reset to default if no groups specified)
sub SetNewGroups($;@)
{
    local $_;
    my ($self, @groups) = @_;
    @groups or @groups = @defaultWriteGroups;
    my $count = @groups;
    my %priority;
    foreach (@groups) {
        $priority{lc($_)} = $count--;
    }
    $priority{file} = 10;       # 'File' group is always written (Comment)
    $priority{composite} = 10;  # 'Composite' group is always written
    # set write priority (higher # is higher priority)
    $self->{WRITE_PRIORITY} = \%priority;
    $self->{WRITE_GROUPS} = \@groups;
}

#------------------------------------------------------------------------------
# Build composite tags from required tags
# Inputs: 0) ExifTool object reference
# Note: Tag values are calculated in alphabetical order unless a tag Require's
#       or Desire's another composite tag, in which case the calculation is
#       deferred until after the other tag is calculated.
sub BuildCompositeTags($)
{
    local $_;
    my $self = shift;

    # first, add user-defined composite tags if necessary
    if (defined %UserDefined and $UserDefined{'Image::ExifTool::Composite'}) {
        AddCompositeTags($UserDefined{'Image::ExifTool::Composite'},1);
        delete $UserDefined{'Image::ExifTool::Composite'};
    }
    my @tagList = sort keys %Image::ExifTool::Composite;
    my %tagsUsed;

    my $rawValue = $self->{VALUE};
    for (;;) {
        my %notBuilt;
        foreach (@tagList) {
            $notBuilt{$_} = 1;
        }
        my @deferredTags;
        my $tag;
COMPOSITE_TAG:
        foreach $tag (@tagList) {
            next if $specialTags{$tag};
            my $tagInfo = $self->GetTagInfo(\%Image::ExifTool::Composite, $tag);
            next unless $tagInfo;
            # put required tags into array and make sure they all exist
            my (%tagKey, $type, $found);
            foreach $type ('Require','Desire') {
                my $req = $$tagInfo{$type} or next;
                # save Require'd and Desire'd tag values in list
                my $index;
                foreach $index (keys %$req) {
                    my $reqTag = $$req{$index};
                    # allow tag group to be specified
                    if ($reqTag =~ /(.+?):(.+)/) {
                        my ($reqGroup, $name) = ($1, $2);
                        my $family;
                        $family = $1 if $reqGroup =~ s/^(\d+)//;
                        my $i = 0;
                        for (;;++$i) {
                            $reqTag = $name;
                            $reqTag .= " ($i)" if $i;
                            last unless defined $$rawValue{$reqTag};
                            my @groups = $self->GetGroup($reqTag, $family);
                            last if grep { $reqGroup eq $_ } @groups;
                        }
                    } elsif ($notBuilt{$reqTag}) {
                        # calculate this tag later if it relies on another
                        # Composite tag which hasn't been calculated yet
                        push @deferredTags, $tag;
                        next COMPOSITE_TAG;
                    }
                    if (defined $$rawValue{$reqTag}) {
                        $found = 1;
                    } else {
                        # don't continue if we require this tag
                        $type eq 'Require' and next COMPOSITE_TAG;
                    }
                    $tagKey{$index} = $reqTag;
                }
            }
            delete $notBuilt{$tag}; # this tag is OK to build now
            next unless $found;     # can't build tag if no values found
            # keep track of all require'd tag keys
            foreach (keys %tagKey) {
                # only tag keys with same name as a composite tag can be replaced
                # (also eliminates keys with instance numbers which can't be replaced either)
                next unless $Image::ExifTool::Composite{$tagKey{$_}};
                my $keyRef = \$tagKey{$_};
                $tagsUsed{$$keyRef} or $tagsUsed{$$keyRef} = [ ];
                push @{$tagsUsed{$$keyRef}}, $keyRef;
            }
            # save reference to tag key lookup as value for composite tag
            my $key = $self->FoundTag($tagInfo, \%tagKey);
            # check to see if we just replaced one of the tag keys we require'd
            next unless defined $key and $tagsUsed{$key};
            foreach (@{$tagsUsed{$key}}) {
                $$_ = $self->{MOVED_KEY};   # replace with new tag key
            }
            delete $tagsUsed{$key};         # can't be replaced again
        }
        last unless @deferredTags;
        if (@deferredTags == @tagList) {
            # everything was deferred in the last pass,
            # must be a circular dependency
            warn "Circular dependency in Composite tags\n";
            last;
        }
        @tagList = @deferredTags; # calculate deferred tags now
    }
}

#------------------------------------------------------------------------------
# Get tag name (removes copy index)
# Inputs: 0) Tag key
# Returns: Tag name
sub GetTagName($)
{
    local $_;
    $_[0] =~ /^(\S+)/;
    return $1;
}

#------------------------------------------------------------------------------
# Get list of shortcuts
# Returns: Shortcut list (sorted alphabetically)
sub GetShortcuts()
{
    local $_;
    require Image::ExifTool::Shortcuts;
    return sort keys %Image::ExifTool::Shortcuts::Main;
}

#------------------------------------------------------------------------------
# Get file type for specified extension
# Inputs: 0) file name or extension (case is not significant)
#         1) flag to return long description instead of type
# Returns: File type (or desc) or undef if extension not supported.  In array
#          context, may return more than one file type if the file may be
#          different formats.  Returns list of all recognized extensions if no
#          file specified
sub GetFileType(;$$)
{
    local $_;
    my ($file, $desc) = @_;
    return sort keys %fileTypeLookup unless defined $file;
    my $fileType;
    my $fileExt = GetFileExtension($file);
    $fileExt = uc($file) unless $fileExt;
    $fileExt and $fileType = $fileTypeLookup{$fileExt}; # look up the file type
    return $$fileType[1] if $desc;  # return description if specified
    $fileType = $$fileType[0];      # get file type (or list of types)
    if (wantarray) {
        return () unless $fileType;
        return @$fileType if ref $fileType eq 'ARRAY';
    } elsif ($fileType) {
        $fileType = $fileExt if ref $fileType eq 'ARRAY';
    }
    return $fileType;
}

#------------------------------------------------------------------------------
# Return true if we can write the specified file type
# Inputs: 0) file name or ext
# Returns: true if writable, 0 if not writable, undef if unrecognized
sub CanWrite($)
{
    local $_;
    my $file = shift or return undef;
    my $type = GetFileType($file) or return undef;
    if ($type eq 'TIFF') {
        # can't write TIFF files with certain extensions (various RAW formats)
        my $ext = GetFileExtension($file);
        return grep(/^$ext$/, @noWriteTIFF) ? 0 : 1 if $ext;
    }
    return scalar(grep /^$type$/, @writeTypes);
}

#------------------------------------------------------------------------------
# Return true if we can create the specified file type
# Inputs: 0) file name or ext
# Returns: true if creatable, 0 if not writable, undef if unrecognized
sub CanCreate($)
{
    local $_;
    my $file = shift or return undef;
    my $type = GetFileType($file) or return undef;
    return scalar(grep /^$type$/, @createTypes);
}

#==============================================================================
# Functions below this are not part of the public API

# Initialize member variables
# Inputs: 0) ExifTool object reference
sub Init($)
{
    local $_;
    my $self = shift;
    # delete all DataMember variables (lower-case names)
    foreach (keys %$self) {
        /[a-z]/ and delete $self->{$_};
    }
    delete $self->{FOUND_TAGS};     # list of found tags
    delete $self->{EXIF_DATA};      # the EXIF data block
    delete $self->{EXIF_POS};       # EXIF position in file
    delete $self->{FIRST_EXIF_POS}; # position of first EXIF in file
    delete $self->{EXIF_BYTE_ORDER};# the EXIF byte ordering
    delete $self->{HTML_DUMP};      # html dump information
    $self->{BASE}       = 0;        # base for offsets from start of file
    $self->{FILE_ORDER} = { };      # hash of tag order in file
    $self->{VALUE}      = { };      # hash of raw tag values
    $self->{TAG_INFO}   = { };      # hash of tag information
    $self->{GROUP1}     = { };      # hash of family 1 group names
    $self->{PRIORITY}   = { };      # priority of current tags
    $self->{LIST_TAGS}  = { };      # hash of tagInfo refs for active List-type tags
    $self->{PROCESSED}  = { };      # hash of processed directory start positions
    $self->{DIR_COUNT}  = { };      # count various types of directories
    $self->{NUM_FOUND}  = 0;        # total number of tags found (incl. duplicates)
    $self->{CHANGED}    = 0;        # number of tags changed (writer only)
    $self->{INDENT}     = '  ';     # initial indent for verbose messages
    $self->{PRIORITY_DIR} = '';     # the priority directory name
    $self->{TIFF_TYPE}  = '';       # type of TIFF data (APP1, TIFF, NEF, etc...)
    $self->{Make}       = '';       # camera make
    $self->{Model}      = '';       # camera model
    $self->{CameraType} = '';       # Olympus camera type
    if ($self->Options('HtmlDump')) {
        require Image::ExifTool::HtmlDump;
        $self->{HTML_DUMP} = new Image::ExifTool::HtmlDump;
    }
    # make sure our TextOut is a file reference
    $self->{OPTIONS}->{TextOut} = \*STDOUT unless ref $self->{OPTIONS}->{TextOut};
}

#------------------------------------------------------------------------------
# Parse function arguments and set member variables accordingly
# Inputs: Same as ImageInfo()
# - sets REQUESTED_TAGS, REQ_TAG_LOOKUP, IO_TAG_LIST, FILENAME, RAF, OPTIONS
sub ParseArguments($;@)
{
    my $self = shift;
    my $options = $self->{OPTIONS};
    my @exclude;
    my @oldGroupOpts = grep /^Group/, keys %{$self->{OPTIONS}};
    my $wasExcludeOpt;

    $self->{REQUESTED_TAGS} = [ ];
    $self->{REQ_TAG_LOOKUP} = { };
    $self->{IO_TAG_LIST} = undef;

    # handle our input arguments
    while (@_) {
        my $arg = shift;
        if (ref $arg) {
            if (ref $arg eq 'ARRAY') {
                $self->{IO_TAG_LIST} = $arg;
                foreach (@$arg) {
                    if (/^-(.*)/) {
                        push @exclude, $1;
                    } else {
                        push @{$self->{REQUESTED_TAGS}}, $_;
                    }
                }
            } elsif (ref $arg eq 'HASH') {
                my $opt;
                foreach $opt (keys %$arg) {
                    # a single new group option overrides all old group options
                    if (@oldGroupOpts and $opt =~ /^Group/) {
                        foreach (@oldGroupOpts) {
                            delete $options->{$_};
                        }
                        undef @oldGroupOpts;
                    }
                    $options->{$opt} = $$arg{$opt};
                    $opt eq 'Exclude' and $wasExcludeOpt = 1;
                }
            } elsif (ref $arg eq 'SCALAR' or UNIVERSAL::isa($arg,'GLOB')) {
                next if defined $self->{RAF};
                # convert image data from UTF-8 to character stream if necessary
                # (patches RHEL 3 UTF8 LANG problem)
                if (ref $arg eq 'SCALAR' and eval 'require Encode; Encode::is_utf8($$arg)') {
                    my $buff = pack('C*', unpack('U0U*', $$arg));
                    $arg = \$buff;
                }
                $self->{RAF} = new File::RandomAccess($arg);
                # set filename to empty string to indicate that
                # we have a file but we didn't open it
                $self->{FILENAME} = '';
            } elsif (UNIVERSAL::isa($arg, 'File::RandomAccess')) {
                $self->{RAF} = $arg;
                $self->{FILENAME} = '';
            } else {
                warn "Don't understand ImageInfo argument $arg\n";
            }
        } elsif (defined $self->{FILENAME}) {
            if ($arg =~ /^-(.*)/) {
                push @exclude, $1;
            } else {
                push @{$self->{REQUESTED_TAGS}}, $arg;
            }
        } else {
            $self->{FILENAME} = $arg;
        }
    }
    # expand shortcuts in tag arguments if provided
    if (@{$self->{REQUESTED_TAGS}}) {
        ExpandShortcuts($self->{REQUESTED_TAGS});
        # initialize lookup for requested tags
        foreach (@{$self->{REQUESTED_TAGS}}) {
            $self->{REQ_TAG_LOOKUP}->{lc(/.+?:(.+)/ ? $1 : $_)} = 1;
        }
    }

    if (@exclude or $wasExcludeOpt) {
        # must add existing excluded tags
        if ($options->{Exclude}) {
            if (ref $options->{Exclude} eq 'ARRAY') {
                push @exclude, @{$options->{Exclude}};
            } else {
                push @exclude, $options->{Exclude};
            }
        }
        $options->{Exclude} = \@exclude;
        # expand shortcuts in new exclude list
        ExpandShortcuts($options->{Exclude});
    }
}

#------------------------------------------------------------------------------
# Set list of found tags
# Inputs: 0) ExifTool object reference
# Returns: Reference to found tags list (in order of requested tags)
sub SetFoundTags($)
{
    my $self = shift;
    my $options = $self->{OPTIONS};
    my $reqTags = $self->{REQUESTED_TAGS} || [ ];
    my $duplicates = $options->{Duplicates};
    my $exclude = $options->{Exclude};
    my $fileOrder = $self->{FILE_ORDER};
    my @groupOptions = sort grep /^Group/, keys %$options;
    my $doDups = $duplicates || $exclude || @groupOptions;
    my ($tag, $rtnTags);

    # only return requested tags if specified
    if (@$reqTags) {
        $rtnTags or $rtnTags = [ ];
        # scan through the requested tags and generate a list of tags we found
        my $tagHash = $self->{VALUE};
        my $reqTag;
        foreach $reqTag (@$reqTags) {
            my (@matches, $group, $family, $allGrp, $allTag);
            if ($reqTag =~ /^(\d+)?(.+?):(.+)/) {
                ($family, $group, $tag) = ($1, $2, $3);
                if ($group =~ /^(\*|all)$/i) {
                    $allGrp = 1;
                } elsif ($group !~ /^[-\w]+$/) {
                    $self->Warn("Invalid group name '$group'");
                    $group = 'invalid';
                }
                $family = -1 unless defined $family;
            } else {
                $tag = $reqTag;
                $family = -1;
            }
            if (defined $tagHash->{$reqTag} and not $doDups) {
                $matches[0] = $tag;
            } elsif ($tag =~ /^(\*|all)$/i) {
                # tag name of '*' or 'all' matches all tags
                if ($doDups or $allGrp) {
                    @matches = keys %$tagHash;
                } else {
                    @matches = grep(!/ /, keys %$tagHash);
                }
                next unless @matches;   # don't want entry in list for '*' tag
                $allTag = 1;
            } elsif ($doDups or defined $group) {
                # must also look for tags like "Tag (1)"
                @matches = grep(/^$tag(\s|$)/i, keys %$tagHash);
            } elsif ($tag =~ /^[-\w]+$/) {
                # find first matching value
                # (use in list context to return value instead of count)
                ($matches[0]) = grep /^$tag$/i, keys %$tagHash;
                defined $matches[0] or undef @matches;
            } else {
                $self->Warn("Invalid tag name '$tag'");
            }
            if (defined $group and not $allGrp) {
                # keep only specified group
                my @grpMatches;
                foreach (@matches) {
                    my @groups = $self->GetGroup($_, $family);
                    next unless grep /^$group$/i, @groups;
                    push @grpMatches, $_;
                }
                @matches = @grpMatches;
                next unless @matches or not $allTag;
            }
            if (@matches > 1) {
                # maintain original file order for multiple tags
                @matches = sort { $$fileOrder{$a} <=> $$fileOrder{$b} } @matches;
                # return only the highest priority tag unless duplicates wanted
                unless ($doDups or $allTag or $allGrp) {
                    $tag = shift @matches;
                    my $oldPriority = $self->{PRIORITY}->{$tag} || 1;
                    foreach (@matches) {
                        my $priority = $self->{PRIORITY}->{$_};
                        $priority = 1 unless defined $priority;
                        next unless $priority >= $oldPriority;
                        $tag = $_;
                        $oldPriority = $priority || 1;
                    }
                    @matches = ( $tag );
                }
            } elsif (not @matches) {
                # put entry in return list even without value (value is undef)
                $matches[0] = "$tag (0)";
                # bogus file order entry to avoid warning if sorting in file order
                $self->{FILE_ORDER}->{$matches[0]} = 999;
            }
            push @$rtnTags, @matches;
        }
    } else {
        # no requested tags, so we want all tags
        my @allTags;
        if ($doDups) {
            @allTags = keys %{$self->{VALUE}};
        } else {
            foreach (keys %{$self->{VALUE}}) {
                # only include tag if it doesn't end in a copy number
                push @allTags, $_ unless / /;
            }
        }
        $rtnTags = \@allTags;
    }

    # filter excluded tags and group options
    while (($exclude or @groupOptions) and @$rtnTags) {
        if ($exclude) {
            my @filteredTags;
EX_TAG:     foreach $tag (@$rtnTags) {
                my $tagName = GetTagName($tag);
                my @matches = grep /(^|:)($tagName|\*|all)$/i, @$exclude;
                foreach (@matches) {
                    next EX_TAG unless /^(\d+)?(.+?):/;
                    my ($family, $group) = ($1, $2);
                    next EX_TAG if $group =~ /^(\*|all)$/i;
                    $family = -1 unless defined $family;
                    my @groups = $self->GetGroup($tag, $family);
                    next EX_TAG if grep /^$group$/i, @groups;
                }
                push @filteredTags, $tag;
            }
            $rtnTags = \@filteredTags;      # use new filtered tag list
            last if $duplicates and not @groupOptions;
        }
        # filter groups if requested, or to remove duplicates
        my (%keepTags, %wantGroup, $family, $groupOpt);
        my $allGroups = 1;
        # build hash of requested/excluded group names for each group family
        my $wantOrder = 0;
        foreach $groupOpt (@groupOptions) {
            $groupOpt =~ /^Group(\d*)/ or next;
            $family = $1 || 0;
            $wantGroup{$family} or $wantGroup{$family} = { };
            my $groupList;
            if (ref $options->{$groupOpt} eq 'ARRAY') {
                $groupList = $options->{$groupOpt};
            } else {
                $groupList = [ $options->{$groupOpt} ];
            }
            foreach (@$groupList) {
                # groups have priority in order they were specified
                ++$wantOrder;
                my ($groupName, $want);
                if (/^-(.*)/) {
                    # excluded group begins with '-'
                    $groupName = $1;
                    $want = 0;          # we don't want tags in this group
                } else {
                    $groupName = $_;
                    $want = $wantOrder; # we want tags in this group
                    $allGroups = 0;     # don't want all groups if we requested one
                }
                $wantGroup{$family}->{$groupName} = $want;
            }
        }
        # loop through all tags and decide which ones we want
        my (@tags, %bestTag);
GR_TAG: foreach $tag (@$rtnTags) {
            my $wantTag = $allGroups;   # want tag by default if want all groups
            foreach $family (keys %wantGroup) {
                my $group = $self->GetGroup($tag, $family);
                my $wanted = $wantGroup{$family}->{$group};
                next unless defined $wanted;
                next GR_TAG unless $wanted;     # skip tag if group excluded
                # take lowest non-zero want flag
                next if $wantTag and $wantTag < $wanted;
                $wantTag = $wanted;
            }
            next unless $wantTag;
            if ($duplicates) {
                push @tags, $tag;
            } else {
                my $tagName = GetTagName($tag);
                my $bestTag = $bestTag{$tagName};
                if (defined $bestTag) {
                    next if $wantTag > $keepTags{$bestTag};
                    if ($wantTag == $keepTags{$bestTag}) {
                        # want two tags with the same name -- keep the latest one
                        if ($tag =~ / \((\d+)\)$/) {
                            my $tagNum = $1;
                            next if $bestTag !~ / \((\d+)\)$/ or $1 > $tagNum;
                        }
                    }
                    # this tag is better, so delete old best tag
                    delete $keepTags{$bestTag};
                }
                $keepTags{$tag} = $wantTag;    # keep this tag (for now...)
                $bestTag{$tagName} = $tag;      # this is our current best tag
            }
        }
        unless ($duplicates) {
            # construct new tag list with no duplicates, preserving order
            foreach $tag (@$rtnTags) {
                push @tags, $tag if $keepTags{$tag};
            }
        }
        $rtnTags = \@tags;
        last;
    }

    # save found tags and return reference
    return $self->{FOUND_TAGS} = $rtnTags;
}

#------------------------------------------------------------------------------
# Utility to load our write routines if required (called via AUTOLOAD)
# Inputs: 0) autoload function, 1-N) function arguments
# Returns: result of function or dies if function not available
# To Do: Generalize this routine so it works on systems that don't use '/'
#        as a path name separator.
sub DoAutoLoad(@)
{
    my $autoload = shift;
    my @callInfo = split(/::/, $autoload);
    my $file = 'Image/ExifTool/Write';

    return if $callInfo[$#callInfo] eq 'DESTROY';
    if (@callInfo == 4) {
        # load Image/ExifTool/WriteMODULE.pl
        $file .= "$callInfo[2].pl";
    } else {
        # load Image/ExifTool/Writer.pl
        $file .= 'r.pl';
    }
    # attempt to load the package
    eval "require '$file'" or die "Error while attempting to call $autoload\n$@\n";
    unless (defined &$autoload) {
        my @caller = caller(0);
        # reproduce Perl's standard 'undefined subroutine' message:
        die "Undefined subroutine $autoload called at $caller[1] line $caller[2]\n";
    }
    no strict 'refs';
    return &$autoload(@_);     # call the function
}

#------------------------------------------------------------------------------
# AutoLoad our writer routines when necessary
#
sub AUTOLOAD
{
    return DoAutoLoad($AUTOLOAD, @_);
}

#------------------------------------------------------------------------------
# Add warning tag
# Inputs: 0) ExifTool object reference, 1) warning message, 2) true if minor
# Returns: true if warning tag was added
sub Warn($$;$)
{
    my ($self, $str, $ignorable) = @_;
    if ($ignorable) {
        return 0 if $self->{OPTIONS}->{IgnoreMinorErrors};
        $str = "[minor] $str";
    }
    $self->FoundTag('Warning', $str);
    return 1;
}

#------------------------------------------------------------------------------
# Add error tag
# Inputs: 0) ExifTool object reference, 1) error message, 2) true if minor
# Returns: true if error tag was added, otherwise warning was added
sub Error($$;$)
{
    my ($self, $str, $ignorable) = @_;
    if ($ignorable) {
        if ($self->{OPTIONS}->{IgnoreMinorErrors}) {
            $self->Warn($str);
            return 0;
        }
        $str = "[minor] $str";
    }
    $self->FoundTag('Error', $str);
    return 1;
}

#------------------------------------------------------------------------------
# Expand shortcuts
# Inputs: 0) reference to list of tags
# Notes: Handles leading '-' for excluded tags, group names, and redirected tags
sub ExpandShortcuts($)
{
    my $tagList = shift || return;

    require Image::ExifTool::Shortcuts;

    # expand shortcuts
    my @expandedTags;
    my ($entry, $tag, $excl);
    foreach $entry (@$tagList) {
        # remove leading '-'
        ($excl, $tag) = $entry =~ /^(-?)(.*)/s;
        my ($post, @post);
        # handle redirection
        if ($tag =~ /(.+?)([-+]?[<>].+)/s and not $excl) {
            ($tag, $post) = ($1, $2);
            if ($post =~ /^[-+]?>/ or $post !~ /\$/) {
                # expand shortcuts in postfix (rhs of redirection)
                my ($op, $p2, $t2) = ($post =~ /([-+]?[<>])(.+?:)?(.+)/);
                $p2 = '' unless defined $p2;
                my ($match) = grep /^\Q$t2\E$/i, keys %Image::ExifTool::Shortcuts::Main;
                if ($match) {
                    foreach (@{$Image::ExifTool::Shortcuts::Main{$match}}) {
                        /^-/ and next;  # ignore excluded tags
                        if ($p2 and /(.+?:)(.+)/) {
                            push @post, "$op$_";
                        } else {
                            push @post, "$op$p2$_";
                        }
                    }
                    next unless @post;
                    $post = shift @post;
                }
            }
        } else {
            $post = '';
        }
        # handle group names
        my $pre;
        if ($tag =~ /(.+?:)(.+)/) {
            ($pre, $tag) = ($1, $2);
        } else {
            $pre = '';
        }
        # loop over all postfixes
        for (;;) {
            # expand the tag name
            my ($match) = grep /^\Q$tag\E$/i, keys %Image::ExifTool::Shortcuts::Main;
            if ($match) {
                if ($excl) {
                    # entry starts with '-', so exclude all tags in this shortcut
                    foreach (@{$Image::ExifTool::Shortcuts::Main{$match}}) {
                        /^-/ and next;  # ignore excluded exclude tags
                        # group of expanded tag takes precedence
                        if ($pre and /(.+?:)(.+)/) {
                            push @expandedTags, "$excl$_";
                        } else {
                            push @expandedTags, "$excl$pre$_";
                        }
                    }
                } elsif (length $pre or length $post) {
                    foreach (@{$Image::ExifTool::Shortcuts::Main{$match}}) {
                        /(-?)(.+?:)?(.+)/;
                        if ($2) {
                            # group from expanded tag takes precedence
                            push @expandedTags, "$_$post";
                        } else {
                            push @expandedTags, "$1$pre$3$post";
                        }
                    }
                } else {
                    push @expandedTags, @{$Image::ExifTool::Shortcuts::Main{$match}};
                }
            } else {
                push @expandedTags, "$excl$pre$tag$post";
            }
            last unless @post;
            $post = shift @post;
        }
    }
    @$tagList = @expandedTags;
}

#------------------------------------------------------------------------------
# Add hash of composite tags to our composites
# Inputs: 0) hash reference to table of composite tags to add or module name,
#         1) overwrite existing tag
sub AddCompositeTags($;$)
{
    local $_;
    my ($add, $overwrite) = @_;
    my $module;
    unless (ref $add) {
        $module = $add;
        $add .= '::Composite';
        no strict 'refs';
        $add = \%$add;
    }
    my $defaultGroups = $$add{GROUPS};

    # make sure default groups are defined in families 0 and 1
    if ($defaultGroups) {
        $defaultGroups->{0} or $defaultGroups->{0} = 'Composite';
        $defaultGroups->{1} or $defaultGroups->{1} = 'Composite';
        $defaultGroups->{2} or $defaultGroups->{2} = 'Other';
    } else {
        $defaultGroups = $$add{GROUPS} = { 0 => 'Composite', 1 => 'Composite', 2 => 'Other' };
    }
    SetupTagTable($add);
    my $tagID;
    foreach $tagID (keys %$add) {
        next if $specialTags{$tagID};   # must skip special tags
        my $tagInfo = $$add{$tagID};
        # tagID's MUST be the exact tag name for logic in BuildCompositeTags()
        my $tag = $$tagInfo{Name};
        $$tagInfo{Module} = $module if $$tagInfo{Writable};
        # allow composite tags with the same name
        my ($t, $n, $type);
        while ($Image::ExifTool::Composite{$tag} and not $overwrite) {
            $n ? $n += 1 : $n = 2, $t = $tag;
            $tag = "${t}_$n";
        }
        # convert scalar Require/Desire entries
        foreach $type ('Require','Desire') {
            my $req = $$tagInfo{$type} or next;
            $$tagInfo{$type} = { 0 => $req } if ref($req) ne 'HASH';
        }
        # add this composite tag to our main composite table
        $$tagInfo{Table} = \%Image::ExifTool::Composite;
        $Image::ExifTool::Composite{$tag} = $tagInfo;
        # set all default groups in tag
        my $groups = $$tagInfo{Groups};
        $groups or $groups = $$tagInfo{Groups} = { };
        # fill in default groups
        foreach (keys %$defaultGroups) {
            $$groups{$_} or $$groups{$_} = $$defaultGroups{$_};
        }
        # set flag indicating group list was built
        $$tagInfo{GotGroups} = 1;
    }
}

#------------------------------------------------------------------------------
# Expand tagInfo Flags
# Inputs: 0) tagInfo hash ref
# Notes: $$tagInfo{Flags} must be defined to call this routine
sub ExpandFlags($)
{
    my $tagInfo = shift;
    my $flags = $$tagInfo{Flags};
    if (ref $flags eq 'ARRAY') {
        foreach (@$flags) {
            $$tagInfo{$_} = 1;
        }
    } elsif (ref $flags eq 'HASH') {
        my $key;
        foreach $key (keys %$flags) {
            $$tagInfo{$key} = $$flags{$key};
        }
    } else {
        $$tagInfo{$flags} = 1;
    }
}

#------------------------------------------------------------------------------
# Set up tag table (must be done once for each tag table used)
# Inputs: 0) Reference to tag table
# Notes: - generates 'Name' field from key if it doesn't exist
#        - stores 'Table' pointer
#        - expands 'Flags' for quick lookup
sub SetupTagTable($)
{
    my $tagTablePtr = shift;
    my $tagID;
    foreach $tagID (TagTableKeys($tagTablePtr)) {
        my @infoArray = GetTagInfoList($tagTablePtr,$tagID);
        # process conditional tagInfo arrays
        my $tagInfo;
        foreach $tagInfo (@infoArray) {
            $$tagInfo{Table} = $tagTablePtr;
            my $tag = $$tagInfo{Name};
            unless (defined $tag) {
                # generate name equal to tag ID if 'Name' doesn't exist
                $tag = $tagID;
                $$tagInfo{Name} = ucfirst($tag); # make first char uppercase
            }
            $$tagInfo{Flags} and ExpandFlags($tagInfo);
        }
    }
}

#------------------------------------------------------------------------------
# Utilities to check for numerical types
# Inputs: 0) value;  Returns: true if value is a numerical type
# Notes: May change commas to decimals in floats for use in other locales
sub IsFloat($) {
    return 1 if $_[0] =~ /^[+-]?(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
    # allow comma separators (for other locales)
    return 0 unless $_[0] =~ /^[+-]?(?=\d|,\d)\d*(,\d*)?([Ee]([+-]?\d+))?$/;
    $_[0] =~ tr/,/./;   # but translate ',' to '.'
    return 1;
}
sub IsInt($)   { return scalar($_[0] =~ /^[+-]?\d+$/); }
sub IsHex($)   { return scalar($_[0] =~ /^(0x)?[0-9a-f]{1,8}$/i); }

# round floating point value to specified number of significant digits
# Inputs: 0) value, 1) number of sig digits;  Returns: rounded number
sub RoundFloat($$)
{
    my ($val, $sig) = @_;
    $val == 0 and return 0;
    my $sign = $val < 0 ? ($val=-$val, -1) : 1;
    my $log = log($val) / log(10);
    my $exp = int($log) - $sig + ($log > 0 ? 1 : 0);
    return $sign * int(10 ** ($log - $exp) + 0.5) * 10 ** $exp;
}

#------------------------------------------------------------------------------
# Utility routines to for reading binary data values from file

my $swapBytes;               # set if EXIF header is not native byte ordering
my $swapWords;               # swap 32-bit words in doubles (ARM quirk)
my $currentByteOrder = 'MM'; # current byte ordering ('II' or 'MM')
my %unpackMotorola = ( S => 'n', L => 'N', C => 'C', c => 'c' );
my %unpackIntel    = ( S => 'v', L => 'V', C => 'C', c => 'c' );
my %unpackStd = %unpackMotorola;

# Swap bytes in data if necessary
# Inputs: 0) data, 1) number of bytes
# Returns: swapped data
sub SwapBytes($$)
{
    return $_[0] unless $swapBytes;
    my ($val, $bytes) = @_;
    my $newVal = '';
    $newVal .= substr($val, $bytes, 1) while $bytes--;
    return $newVal;
}
# Swap words.  Inputs: 8 bytes of data, Returns: swapped data
sub SwapWords($)
{
    return $_[0] unless $swapWords and length($_[0]) == 8;
    return substr($_[0],4,4) . substr($_[0],0,4)
}

# Unpack value, letting unpack() handle byte swapping
# Inputs: 0) unpack template, 1) data reference, 2) offset
# Returns: unpacked number
# - uses value of %unpackStd to determine the unpack template
# - can only be called for 'S' or 'L' templates since these are the only
#   templates for which you can specify the byte ordering.
sub DoUnpackStd(@)
{
    $_[2] and return unpack("x$_[2] $unpackStd{$_[0]}", ${$_[1]});
    return unpack($unpackStd{$_[0]}, ${$_[1]});
}
# Pack value
# Inputs: 0) template, 1) value, 2) data ref (or undef), 3) offset (if data ref)
# Returns: packed value
sub DoPackStd(@)
{
    my $val = pack($unpackStd{$_[0]}, $_[1]);
    $_[2] and substr(${$_[2]}, $_[3], length($val)) = $val;
    return $val;
}

# Unpack value, handling the byte swapping manually
# Inputs: 0) # bytes, 1) unpack template, 2) data reference, 3) offset
# Returns: unpacked number
# - uses value of $swapBytes to determine byte ordering
sub DoUnpack(@)
{
    my ($bytes, $template, $dataPt, $pos) = @_;
    my $val;
    if ($swapBytes) {
        $val = '';
        $val .= substr($$dataPt,$pos+$bytes,1) while $bytes--;
    } else {
        $val = substr($$dataPt,$pos,$bytes);
    }
    defined($val) or return undef;
    return unpack($template,$val);
}

# Unpack double value
# Inputs: 0) unpack template, 1) data reference, 2) offset
# Returns: unpacked number
sub DoUnpackDbl(@)
{
    my ($template, $dataPt, $pos) = @_;
    my $val = substr($$dataPt,$pos,8);
    defined($val) or return undef;
    # swap bytes and 32-bit words (ARM quirk) if necessary, then unpack value
    return unpack($template, SwapWords(SwapBytes($val, 8)));
}

# Inputs: 0) data reference, 1) offset into data
sub Get8s($$)     { return DoUnpackStd('c', @_); }
sub Get8u($$)     { return DoUnpackStd('C', @_); }
sub Get16s($$)    { return DoUnpack(2, 's', @_); }
sub Get16u($$)    { return DoUnpackStd('S', @_); }
sub Get32s($$)    { return DoUnpack(4, 'l', @_); }
sub Get32u($$)    { return DoUnpackStd('L', @_); }
sub GetFloat($$)  { return DoUnpack(4, 'f', @_); }
sub GetDouble($$) { return DoUnpackDbl('d', @_); }

sub GetRational32s($$)
{
    my ($dataPt, $pos) = @_;
    my $denom = Get16s($dataPt, $pos + 2) or return 'inf';
    # round off to a reasonable number of significant figures
    return RoundFloat(Get16s($dataPt,$pos) / $denom, 7);
}
sub GetRational32u($$)
{
    my ($dataPt, $pos) = @_;
    my $denom = Get16u($dataPt, $pos + 2) or return 'inf';
    return RoundFloat(Get16u($dataPt,$pos) / $denom, 7);
}
sub GetRational64s($$)
{
    my ($dataPt, $pos) = @_;
    my $denom = Get32s($dataPt, $pos + 4) or return 'inf';
    return RoundFloat(Get32s($dataPt,$pos) / $denom, 10);
}
sub GetRational64u($$)
{
    my ($dataPt, $pos) = @_;
    my $denom = Get32u($dataPt, $pos + 4) or return 'inf';
    return RoundFloat(Get32u($dataPt,$pos) / $denom, 10);
}
sub GetFixed16s($$)
{
    my ($dataPt, $pos) = @_;
    my $val = Get16s($dataPt, $pos) / 0x100;
    return int($val * 1000 + ($val<0 ? -0.5 : 0.5)) / 1000;
}
sub GetFixed16u($$)
{
    my ($dataPt, $pos) = @_;
    return int((Get16u($dataPt, $pos) / 0x100) * 1000 + 0.5) / 1000;
}
sub GetFixed32s($$)
{
    my ($dataPt, $pos) = @_;
    my $val = Get32s($dataPt, $pos) / 0x10000;
    # remove insignificant digits
    return int($val * 1e5 + ($val>0 ? 0.5 : -0.5)) / 1e5;
}
sub GetFixed32u($$)
{
    my ($dataPt, $pos) = @_;
    # remove insignificant digits
    return int((Get32u($dataPt, $pos) / 0x10000) * 1e5 + 0.5) / 1e5;
}
# Inputs: 0) value, 1) data ref, 2) offset
sub Set8s(@)  { return DoPackStd('c', @_); }
sub Set8u(@)  { return DoPackStd('C', @_); }
sub Set16u(@) { return DoPackStd('S', @_); }
sub Set32u(@) { return DoPackStd('L', @_); }

#------------------------------------------------------------------------------
# Get current byte order ('II' or 'MM')
sub GetByteOrder() { return $currentByteOrder; }

#------------------------------------------------------------------------------
# Set byte ordering
# Inputs: 0) 'MM'=motorola, 'II'=intel (will translate 'BigEndian', 'LittleEndian')
# Returns: 1 on success
sub SetByteOrder($)
{
    my $order = shift;

    if ($order eq 'MM') {       # big endian (Motorola)
        %unpackStd = %unpackMotorola;
    } elsif ($order eq 'II') {  # little endian (Intel)
        %unpackStd = %unpackIntel;
    } elsif ($order =~ /^Big/i) {
        $order = 'MM';
        %unpackStd = %unpackMotorola;
    } elsif ($order =~ /^Little/i) {
        $order = 'II';
        %unpackStd = %unpackIntel;
    } else {
        return 0;
    }
    my $val = unpack('S','A ');
    my $nativeOrder;
    if ($val == 0x4120) {       # big endian
        $nativeOrder = 'MM';
    } elsif ($val == 0x2041) {  # little endian
        $nativeOrder = 'II';
    } else {
        warn sprintf("Unknown native byte order! (pattern %x)\n",$val);
        return 0;
    }
    $currentByteOrder = $order;  # save current byte order

    # swap bytes if our native CPU byte ordering is not the same as the EXIF
    $swapBytes = ($order ne $nativeOrder);

    # little-endian ARM has big-endian words for doubles (thanks Riku Voipio)
    # (Note: Riku's patch checked for '0ff3', but I think it should be 'f03f' since
    # 1 is '000000000000f03f' on an x86 -- so check for both, but which is correct?)
    my $pack1d = pack('d', 1);
    $swapWords = ($pack1d eq "\0\0\x0f\xf3\0\0\0\0" or
                  $pack1d eq "\0\0\xf0\x3f\0\0\0\0");
    return 1;
}

#------------------------------------------------------------------------------
# Change byte order
sub ToggleByteOrder()
{
    SetByteOrder(GetByteOrder() eq 'II' ? 'MM' : 'II');
}

#------------------------------------------------------------------------------
# hash lookups for reading values from data
my %formatSize = (
    int8s => 1,
    int8u => 1,
    int16s => 2,
    int16u => 2,
    int32s => 4,
    int32u => 4,
    int64s => 8,
    int64u => 8,
    rational32s => 4,
    rational32u => 4,
    rational64s => 8,
    rational64u => 8,
    fixed16s => 2,
    fixed16u => 2,
    fixed32s => 4,
    fixed32u => 4,
    float => 4,
    double => 8,
    extended => 10,
    string => 1,
    binary => 1,
   'undef' => 1,
    ifd => 4,
    ifd8 => 8,
);
my %readValueProc = (
    int8s => \&Get8s,
    int8u => \&Get8u,
    int16s => \&Get16s,
    int16u => \&Get16u,
    int32s => \&Get32s,
    int32u => \&Get32u,
    int64s => \&Get64s,
    int64u => \&Get64u,
    rational32s => \&GetRational32s,
    rational32u => \&GetRational32u,
    rational64s => \&GetRational64s,
    rational64u => \&GetRational64u,
    fixed16s => \&GetFixed16s,
    fixed16u => \&GetFixed16u,
    fixed32s => \&GetFixed32s,
    fixed32u => \&GetFixed32u,
    float => \&GetFloat,
    double => \&GetDouble,
    extended => \&GetExtended,
    ifd => \&Get32u,
    ifd8 => \&Get64u,
);
sub FormatSize($) { return $formatSize{$_[0]}; }

#------------------------------------------------------------------------------
# Read value from binary data (with current byte ordering)
# Inputs: 0) data reference, 1) value offset, 2) format string,
#         3) number of values (or undef to use all data)
#         4) valid data length relative to offset
# Returns: converted value, or undefined if data isn't there
#          or list of values in list context
sub ReadValue($$$$$)
{
    my ($dataPt, $offset, $format, $count, $size) = @_;

    my $len = $formatSize{$format};
    unless ($len) {
        warn "Unknown format $format";
        $len = 1;
    }
    unless ($count) {
        return '' if defined $count or $size < $len;
        $count = int($size / $len);
    }
    # make sure entry is inside data
    if ($len * $count > $size) {
        $count = int($size / $len);     # shorten count if necessary
        $count < 1 and return undef;    # return undefined if no data
    }
    my @vals;
    my $proc = $readValueProc{$format};
    if ($proc) {
        for (;;) {
            push @vals, &$proc($dataPt, $offset);
            last if --$count <= 0;
            $offset += $len;
        }
    } else {
        # handle undef/binary/string
        $vals[0] = substr($$dataPt, $offset, $count);
        # truncate string at null terminator if necessary
        $vals[0] =~ s/\0.*//s if $format eq 'string';
    }
    return @vals if wantarray;
    return join(' ', @vals) if @vals > 1;
    return $vals[0];
}

#------------------------------------------------------------------------------
# Convert UTF-8 to current character set
# Inputs: 0) ExifTool ref, 1) UTF-8 string
# Return: Converted string
sub UTF82Charset($$)
{
    my ($self, $val) = @_;
    if ($self->{OPTIONS}->{Charset} eq 'Latin' and $val =~ /[\x80-\xff]/) {
        $val = Image::ExifTool::UTF82Unicode($val,'n',$self);
        $val = Image::ExifTool::Unicode2Latin($val,'n',$self);
    }
    return $val;
}

#------------------------------------------------------------------------------
# Convert Latin to current character set
# Inputs: 0) ExifTool ref, 1) Latin string
# Return: Converted string
sub Latin2Charset($$)
{
    my ($self, $val) = @_;
    if ($self->{OPTIONS}->{Charset} eq 'UTF8' and $val =~ /[\x80-\xff]/) {
        $val = Image::ExifTool::Latin2Unicode($val,'n');
        $val = Image::ExifTool::Unicode2UTF8($val,'n');
    }
    return $val;
}

#------------------------------------------------------------------------------
# Decode bit mask
# Inputs: 0) value to decode, 1) Reference to hash for decoding (or undef)
#         2) optional bits per word (defaults to 32)
sub DecodeBits($$;$)
{
    my ($vals, $lookup, $bits) = @_;
    $bits or $bits = 32;
    my ($val, $i, @bitList);
    my $num = 0;
    foreach $val (split ' ', $vals) {
        for ($i=0; $i<$bits; ++$i) {
            next unless $val & (1 << $i);
            my $n = $i + $num;
            if (not $lookup) {
                push @bitList, $n;
            } elsif ($$lookup{$n}) {
                push @bitList, $$lookup{$n};
            } else {
                push @bitList, "[$n]";
            }
        }
        $num += $bits;
    }
    return '(none)' unless @bitList;
    return join($lookup ? ', ' : ',', @bitList);
}

#------------------------------------------------------------------------------
# Validate an extracted image and repair if necessary
# Inputs: 0) ExifTool object reference, 1) image reference, 2) tag name or key
# Returns: image reference or undef if it wasn't valid
# Note: should be called from RawConv, not ValueConv
sub ValidateImage($$$)
{
    my ($self, $imagePt, $tag) = @_;
    return undef if $$imagePt eq 'none';
    unless ($$imagePt =~ /^(Binary data|\xff\xd8\xff)/ or
            # the first byte of the preview of some Minolta cameras is wrong,
            # so check for this and set it back to 0xff if necessary
            $$imagePt =~ s/^.(\xd8\xff\xdb)/\xff$1/s or
            $self->Options('IgnoreMinorErrors'))
    {
        # issue warning only if the tag was specifically requested
        if ($self->{REQ_TAG_LOOKUP}->{lc GetTagName($tag)}) {
            $self->Warn("$tag is not a valid JPEG image",1);
            return undef;
        }
    }
    return $imagePt;
}

#------------------------------------------------------------------------------
# Make description from a tag name
# Inputs: 0) tag name 1) optional tagID to add at end of description
# Returns: description
sub MakeDescription($;$)
{
    my ($tag, $tagID) = @_;
    # start with the tag name and force first letter to be upper case
    my $desc = ucfirst($tag);
    $desc =~ tr/_/ /;       # translate underlines to spaces
    # put a space between lower/UPPER case and lower/number combinations
    $desc =~ s/([a-z])([A-Z\d])/$1 $2/g;
    # put a space between acronyms and words
    $desc =~ s/([A-Z])([A-Z][a-z])/$1 $2/g;
    # put spaces after numbers (if more than one character following number)
    $desc =~ s/(\d)([A-Z]\S)/$1 $2/g;
    # remove space in hex number
    $desc =~ s/ 0x ([\dA-Fa-f])/ 0x$1/g;
    $desc .= ' ' . $tagID if defined $tagID;
    return $desc;
}

#------------------------------------------------------------------------------
# Return printable value
# Inputs: 0) ExifTool object reference
#         1) value to print, 2) true for unlimited line length
sub Printable($;$)
{
    my ($self, $outStr, $unlimited) = @_;
    return '(undef)' unless defined $outStr;
    $outStr =~ tr/\x01-\x1f\x7f-\xff/./;
    $outStr =~ s/\x00//g;
    # limit length if verbose < 4
    if (length($outStr) > 60 and not $unlimited and $self->{OPTIONS}->{Verbose} < 4) {
        $outStr = substr($outStr,0,54) . '[snip]';
    }
    return $outStr;
}

#------------------------------------------------------------------------------
# Convert date/time from Exif format
# Inputs: 0) ExifTool object reference, 1) Date/time in EXIF format
# Returns: Formatted date/time string
sub ConvertDateTime($$)
{
    my ($self, $date) = @_;
    my $dateFormat = $self->{OPTIONS}->{DateFormat};
    # only convert date if a format was specified and the date is recognizable
    if ($dateFormat) {
        if ($date =~ /^(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)/ and eval 'require POSIX') {
            $date = POSIX::strftime($dateFormat, $6, $5, $4, $3, $2-1, $1-1900);
        } elsif ($self->{OPTIONS}->{StrictDate}) {
            undef $date;
        }
    }
    return $date;
}

#------------------------------------------------------------------------------
# Convert Unix time to EXIF date/time string
# Inputs: 0) Unix time value, 1) non-zero to use local instead of GMT time
# Returns: EXIF date/time string
sub ConvertUnixTime($;$)
{
    my $time = shift;
    return '0000:00:00 00:00:00' if $time == 0;
    my @tm = shift() ? localtime($time) : gmtime($time);
    return sprintf("%4d:%.2d:%.2d %.2d:%.2d:%.2d", $tm[5]+1900, $tm[4]+1,
                   $tm[3], $tm[2], $tm[1], $tm[0]);
}

#------------------------------------------------------------------------------
# Get Unix time from EXIF-formatted date/time string
# Inputs: 0) EXIF date/time string, 1) non-zero to use local instead of GMT time
# Returns: Unix time or undefined on error
sub GetUnixTime($;$)
{
    my $timeStr = shift;
    return 0 if $timeStr eq '0000:00:00 00:00:00';
    my @tm = ($timeStr =~ /^(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)/);
    return undef unless @tm == 6;
    return undef unless eval 'require Time::Local';
    $tm[0] -= 1900;     # convert year
    $tm[1] -= 1;        # convert month
    @tm = reverse @tm;  # change to order required by timelocal()
    return shift() ? Time::Local::timelocal(@tm) : Time::Local::timegm(@tm);
}

#------------------------------------------------------------------------------
# Convert seconds to duration string
# Inputs: 0) Unix time value
# Returns: duration string in form "S.SS s", "MM:SS" or "H:MM:SS"
sub ConvertDuration($;$)
{
    my $time = shift;
    return $time unless IsFloat($time);
    return '0 s' if $time == 0;
    return sprintf('%.2f s', $time) if $time < 60;
    my $str = '';
    if ($time >= 3600) {
        my $h = int($time / 3600);
        $str = "$h:";
        $time -= $h * 3600;
    }
    my $m = int($time / 60);
    $time -= $m * 60;
    return sprintf('%s%.2d:%.2d', $str, $m, int($time));
}

#------------------------------------------------------------------------------
# Save information for HTML dump
# Inputs: 0) ExifTool hash ref, 1) start offset, 2) data size
#         3) comment string, 4) tool tip (or SAME), 5) flags
sub HtmlDump($$$$;$$)
{
    my $self = shift;
    my $pos = shift;
    $pos += $$self{BASE} if $$self{BASE};
    $$self{HTML_DUMP} and $self->{HTML_DUMP}->Add($pos, @_);
}

#------------------------------------------------------------------------------
# JPEG constants
my %jpegMarker = (
    0x01 => 'TEM',
    0xc0 => 'SOF0', # to SOF15, with a few exceptions below
    0xc4 => 'DHT',
    0xc8 => 'JPGA',
    0xcc => 'DAC',
    0xd0 => 'RST0',
    0xd8 => 'SOI',
    0xd9 => 'EOI',
    0xda => 'SOS',
    0xdb => 'DQT',
    0xdc => 'DNL',
    0xdd => 'DRI',
    0xde => 'DHP',
    0xdf => 'EXP',
    0xe0 => 'APP0', # to APP15
    0xf0 => 'JPG0',
    0xfe => 'COM',
);

#------------------------------------------------------------------------------
# Get JPEG marker name
# Inputs: 0) Jpeg number
# Returns: marker name
sub JpegMarkerName($)
{
    my $marker = shift;
    my $markerName = $jpegMarker{$marker};
    unless ($markerName) {
        $markerName = $jpegMarker{$marker & 0xf0};
        if ($markerName and $markerName =~ /^([A-Z]+)\d+$/) {
            $markerName = $1 . ($marker & 0x0f);
        } else {
            $markerName = sprintf("marker 0x%.2x", $marker);
        }
    }
    return $markerName;
}

#------------------------------------------------------------------------------
# Identify trailer ending at specified offset from end of file
# Inputs: 0) RAF reference, 1) offset from end of file (0 by default)
# Returns: Trailer info hash (with RAF and DirName set),
#          or undef if no recognized trailer was found
# Notes: leaves file position unchanged
sub IdentifyTrailer($;$)
{
    my $raf = shift;
    my $offset = shift || 0;
    my $pos = $raf->Tell();
    my ($buff, $type, $len);
    while ($raf->Seek(-$offset, 2) and ($len = $raf->Tell()) > 0) {
        # read up to 64 bytes before specified offset from end of file
        $len = 64 if $len > 64;
        $raf->Seek(-$len, 1) and $raf->Read($buff, $len) == $len or last;
        if ($buff =~ /AXS(!|\*).{8}$/s) {
            $type = 'AFCP';
        } elsif ($buff =~ /\xa1\xb2\xc3\xd4$/) {
            $type = 'FotoStation';
        } elsif ($buff =~ /cbipcbbl$/) {
            $type = 'PhotoMechanic';
        } elsif ($buff =~ /^CANON OPTIONAL DATA\0/) {
            $type = 'CanonVRD';
        } elsif ($buff =~ /~\0\x04\0zmie~\0\0\x06.{4}[\x10\x18]\x04$/s or
                 $buff =~ /~\0\x04\0zmie~\0\0\x0a.{8}[\x10\x18]\x08$/s)
        {
            $type = 'MIE';
        }
        last;
    }
    $raf->Seek($pos, 0);    # restore original file position
    return $type ? { RAF => $raf, DirName => $type } : undef;
}

#------------------------------------------------------------------------------
# Extract EXIF information from a jpg image
# Inputs: 0) ExifTool object reference, 1) dirInfo ref with RAF set
# Returns: 1 on success, 0 if this wasn't a valid JPEG file
sub ProcessJPEG($$)
{
    my ($self, $dirInfo) = @_;
    my ($ch,$s,$length);
    my $verbose = $self->{OPTIONS}->{Verbose};
    my $out = $self->{OPTIONS}->{TextOut};
    my $raf = $$dirInfo{RAF};
    my $htmlDump = $self->{HTML_DUMP};
    my %dumpParms = ( Out => $out );
    my ($success, $icc_profile, $wantPreview, $trailInfo);

    # check to be sure this is a valid JPG file
    return 0 unless $raf->Read($s, 2) == 2 and $s eq "\xff\xd8";
    $dumpParms{MaxLen} = 128 if $verbose < 4;
    $self->SetFileType();   # set FileType tag
    if ($htmlDump) {
        my $pos = $raf->Tell() - 2;
        $self->HtmlDump(0, $pos, '[unknown header]') if $pos;
        $self->HtmlDump($pos, 2, 'JPEG header', 'SOI Marker');
    }

    # set input record separator to 0xff (the JPEG marker) to make reading quicker
    my $oldsep = $/;
    $/ = "\xff";

    my ($nextMarker, $nextSegDataPt, $nextSegPos, $combinedSegData, $dumpEnd);

    # read file until we reach an end of image (EOI) or start of scan (SOS)
    Marker: for (;;) {
        # set marker and data pointer for current segment
        my $marker = $nextMarker;
        my $segDataPt = $nextSegDataPt;
        my $segPos = $nextSegPos;
        undef $nextMarker;
        undef $nextSegDataPt;
#
# read ahead to the next segment unless we have reached EOI or SOS
#
        unless ($marker and ($marker==0xd9 or ($marker==0xda and not $wantPreview))) {
            # read up to next marker (JPEG markers begin with 0xff)
            my $buff;
            $raf->ReadLine($buff) or last;
            # JPEG markers can be padded with unlimited 0xff's
            for (;;) {
                $raf->Read($ch, 1) or last Marker;
                $nextMarker = ord($ch);
                last unless $nextMarker == 0xff;
            }
            # read data for all markers except 0xd9 (EOI) and stand-alone
            # markers 0x00, 0x01 and 0xd0-0xd7 (NULL, TEM, RST0-RST7)
            if ($nextMarker!=0xd9 and $nextMarker!=0x00 and $nextMarker!=0x01 and
                ($nextMarker<0xd0 or $nextMarker>0xd7))
            {
                # read record length word
                last unless $raf->Read($s, 2) == 2;
                my $len = unpack('n',$s);   # get data length
                last unless defined($len) and $len >= 2;
                $nextSegPos = $raf->Tell();
                $len -= 2;  # subtract size of length word
                last unless $raf->Read($buff, $len) == $len;
                $nextSegDataPt = \$buff;    # set pointer to our next data
            }
            # read second segment too if this was the first
            next unless defined $marker;
        }
        # set some useful variables for the current segment
        my $hdr = "\xff" . chr($marker);    # header for this segment
        my $markerName = JpegMarkerName($marker);
#
# parse the current segment
#
        # handle SOF markers: SOF0-SOF15, except DHT(0xc4), JPGA(0xc8) and DAC(0xcc)
        if (($marker & 0xf0) == 0xc0 and ($marker == 0xc0 or $marker & 0x03)) {
            $length = length $$segDataPt;
            if ($verbose) {
                print $out "JPEG $markerName ($length bytes):\n";
                HexDump($segDataPt, undef, %dumpParms, Addr=>$segPos) if $verbose>2;
            }
            next unless $length >= 6;
            # extract some useful information
            my ($p, $h, $w, $n) = unpack('Cn2C', $$segDataPt);
            my $sof = GetTagTable('Image::ExifTool::JPEG::SOF');
            $self->FoundTag($$sof{ImageWidth}, $w);
            $self->FoundTag($$sof{ImageHeight}, $h);
            $self->FoundTag($$sof{EncodingProcess}, $marker - 0xc0);
            $self->FoundTag($$sof{BitsPerSample}, $p);
            $self->FoundTag($$sof{ColorComponents}, $n);
            next unless $n == 3 and $length >= 15;
            my ($i, $hmin, $hmax, $vmin, $vmax);
            # loop through all components to determine sampling frequency
            for ($i=0; $i<$n; ++$i) {
                my $sf = Get8u($segDataPt, 7 + 3 * $i);
                # isolate horizontal and vertical components
                my ($hf, $vf) = ($sf >> 4, $sf & 0x0f);
                unless ($i) {
                    $hmin = $hmax = $hf;
                    $vmin = $vmax = $vf;
                    next;
                }
                # determine min/max frequencies
                $hmin = $hf if $hf < $hmin;
                $hmax = $hf if $hf > $hmax;
                $vmin = $vf if $vf < $vmin;
                $vmax = $vf if $vf > $vmax;
            }
            if ($hmin and $vmin) {
                my ($hs, $vs) = ($hmax / $hmin, $vmax / $vmin);
                $self->FoundTag($$sof{YCbCrSubSampling}, "$hs $vs");
            }
            next;
        } elsif ($marker == 0xd9) {         # EOI
            $verbose and print $out "JPEG EOI\n";
            my $pos = $raf->Tell();
            if ($htmlDump and $dumpEnd) {
                $self->HtmlDump($dumpEnd, $pos-2-$dumpEnd, '[JPEG Image Data]', undef, 0x08);
                $self->HtmlDump($pos-2, 2, 'JPEG EOI', undef);
                $dumpEnd = 0;
            }
            $success = 1;
            # we are here because we are looking for trailer information
            if ($wantPreview and $self->{VALUE}->{PreviewImageStart}) {
                my $buff;
                # most previews start right after the JPEG EOI, but the Olympus E-20
                # preview is 508 bytes into the trailer, and the K-M Maxxum 7D preview
                # is 979 bytes in, but Minolta previews can have a random first byte...
                if ($raf->Read($buff, 1024) and ($buff =~ /\xff\xd8\xff./g or
                    ($self->{Make} =~ /Minolta/i and $buff =~ /.\xd8\xff\xdb/g)))
                {
                    # adjust PreviewImageStart to this location
                    my $start = $self->{VALUE}->{PreviewImageStart};
                    my $actual = $pos + pos($buff) - 4;
                    if ($start ne $actual and $verbose > 1) {
                        print $out "(Fixed PreviewImage location: $start -> $actual)\n";
                    }
                    $self->{VALUE}->{PreviewImageStart} = $actual;
                }
                $raf->Seek($pos, 0);
            }
            # process trailer now or finish processing trailers
            # and scan for AFCP if necessary
            my $fromEnd = 0;
            if ($trailInfo) {
                $$trailInfo{ScanForAFCP} = 1;   # scan now if necessary
                $self->ProcessTrailers($trailInfo);
                # save offset from end of file to start of first trailer
                $fromEnd = $$trailInfo{Offset};
                undef $trailInfo;
            }
            # finally, dump remaining information in JPEG trailer
            if ($verbose or $htmlDump) {
                $raf->Seek(0, 2);
                my $endPos = $raf->Tell() - $fromEnd;
                $self->DumpUnknownTrailer({
                    RAF => $raf,
                    DataPos => $pos,
                    DirLen => $endPos - $pos
                }) if $endPos > $pos;
            }
            last;       # all done parsing file
        } elsif ($marker == 0xda) {         # SOS
            # all done with meta information unless we have a trailer
            $verbose and print $out "JPEG SOS\n";
            unless ($self->Options('FastScan')) {
                $trailInfo = IdentifyTrailer($raf);
                # process trailer now unless we are doing verbose dump
                if ($trailInfo and $verbose < 3 and not $htmlDump) {
                    # process trailers (keep trailInfo to finish processing later
                    # only if we can't finish without scanning from end of file)
                    $self->ProcessTrailers($trailInfo) and undef $trailInfo;
                }
                if ($wantPreview) {
                    # seek ahead and validate preview image
                    my $buff;
                    my $curPos = $raf->Tell();
                    if ($raf->Seek($self->GetValue('PreviewImageStart'), 0) and
                        $raf->Read($buff, 4) == 4 and
                        $buff =~ /^.\xd8\xff[\xc4\xdb\xe0-\xef]/)
                    {
                        undef $wantPreview;
                    }
                    $raf->Seek($curPos, 0) or last;
                }
                next if $trailInfo or $wantPreview or $verbose > 2 or $htmlDump;
            }
            # nothing interesting to parse after start of scan (SOS)
            $success = 1;
            last;   # all done parsing file
        } elsif ($marker==0x00 or $marker==0x01 or ($marker>=0xd0 and $marker<=0xd7)) {
            # handle stand-alone markers 0x00, 0x01 and 0xd0-0xd7 (NULL, TEM, RST0-RST7)
            $verbose and $marker and print $out "JPEG $markerName:\n";
            next;
        }
        # handle all other markers
        my $dumpType = '';
        $length = length $$segDataPt;
        if ($verbose) {
            print $out "JPEG $markerName ($length bytes):\n";
            if ($verbose > 2) {
                my %extraParms = ( Addr => $segPos );
                $extraParms{MaxLen} = 128 if $verbose == 4;
                HexDump($segDataPt, undef, %dumpParms, %extraParms);
            }
        }
        if ($marker == 0xe0) {              # APP0 (JFIF, CIFF)
            if ($$segDataPt =~ /^JFIF\0/) {
                $dumpType = 'JFIF';
                my %dirInfo = (
                    DataPt => $segDataPt,
                    DataPos  => $segPos,
                    DirStart => 5,
                    DirLen => $length - 5,
                );
                SetByteOrder('MM');
                my $tagTablePtr = GetTagTable('Image::ExifTool::JFIF::Main');
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            } elsif ($$segDataPt =~ /^JFXX\0\x10/) {
                $dumpType = 'JFXX';
                my $tagTablePtr = GetTagTable('Image::ExifTool::JFIF::Extension');
                my $tagInfo = $self->GetTagInfo($tagTablePtr, 0x10);
                $self->FoundTag($tagInfo, substr($$segDataPt, 6));
            } elsif ($$segDataPt =~ /^(II|MM).{4}HEAPJPGM/s) {
                $dumpType = 'CIFF';
                my %dirInfo = (
                    RAF => new File::RandomAccess($segDataPt),
                );
                $self->{SET_GROUP1} = 'CIFF';
                require Image::ExifTool::CanonRaw;
                Image::ExifTool::CanonRaw::ProcessCRW($self, \%dirInfo);
                delete $self->{SET_GROUP1};
            }
        } elsif ($marker == 0xe1) {         # APP1 (EXIF, XMP)
            if ($$segDataPt =~ /^Exif\0/) { # (some Kodak cameras don't put a second \0)
                undef $dumpType;    # (will be dumped here)
                # this is EXIF data --
                # get the data block (into a common variable)
                my $hdrLen = length($exifAPP1hdr);
                my %dirInfo = (
                    Parent => $markerName,
                    DataPt => $segDataPt,
                    DataPos => $segPos,
                    DirStart => $hdrLen,
                    Base => $segPos + $hdrLen,
                );
                if ($htmlDump) {
                    $self->HtmlDump($segPos-4, 4, 'APP1 header',
                             "Data size: $length bytes");
                    $self->HtmlDump($segPos, $hdrLen, 'Exif header',
                             'APP1 data type: Exif');
                    $dumpEnd = $segPos + $length;
                }
                # extract the EXIF information (it is in standard TIFF format)
                $self->ProcessTIFF(\%dirInfo);
                # avoid looking for preview unless necessary because it really slows
                # us down -- only look for it if we found pointer, and preview is
                # outside EXIF, and PreviewImage is specifically requested
                my $start = $self->GetValue('PreviewImageStart');
                my $length = $self->GetValue('PreviewImageLength');
                if ($start and $length and
                    $start + $length > $self->{EXIF_POS} + length($self->{EXIF_DATA}) and
                    $self->{REQ_TAG_LOOKUP}->{previewimage})
                {
                    $wantPreview = 1;
                }
            } else {
                # Hmmm.  Could be XMP, let's see
                my $processed;
                if ($$segDataPt =~ /^http/ or $$segDataPt =~ /<exif:/) {
                    $dumpType = 'XMP';
                    my $start = ($$segDataPt =~ /^$xmpAPP1hdr/) ? length($xmpAPP1hdr) : 0;
                    my $tagTablePtr = GetTagTable('Image::ExifTool::XMP::Main');
                    my %dirInfo = (
                        Base     => 0,
                        DataPt   => $segDataPt,
                        DataPos  => $segPos,
                        DataLen  => $length,
                        DirStart => $start,
                        DirLen   => $length - $start,
                        Parent   => $markerName,
                    );
                    $processed = $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
                }
                if ($verbose and not $processed) {
                    $self->Warn("Ignored EXIF block length $length (bad header)");
                }
            }
        } elsif ($marker == 0xe2) {         # APP2 (ICC Profile, FPXR)
            if ($$segDataPt =~ /^ICC_PROFILE\0/) {
                $dumpType = 'ICC_Profile';
                # must concatenate blocks of profile
                my $block_num = Get8u($segDataPt, 12);
                my $blocks_tot = Get8u($segDataPt, 13);
                $icc_profile = '' if $block_num == 1;
                if (defined $icc_profile) {
                    $icc_profile .= substr($$segDataPt, 14);
                    if ($block_num == $blocks_tot) {
                        my $tagTablePtr = GetTagTable('Image::ExifTool::ICC_Profile::Main');
                        my %dirInfo = (
                            DataPt   => \$icc_profile,
                            DataPos  => $segPos + 14,
                            DataLen  => length($icc_profile),
                            DirStart => 0,
                            DirLen   => length($icc_profile),
                            Parent   => $markerName,
                        );
                        $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
                        undef $icc_profile;
                    }
                }
            } elsif ($$segDataPt =~ /^FPXR\0/) {
                $dumpType = 'FPXR';
                my $tagTablePtr = GetTagTable('Image::ExifTool::FlashPix::Main');
                my %dirInfo = (
                    DataPt   => $segDataPt,
                    DataPos  => $segPos,
                    DataLen  => $length,
                    DirStart => 0,
                    DirLen   => $length,
                    Parent   => $markerName,
                    # set flag if this is the last FPXR segment
                    LastFPXR => not ($nextMarker==$marker and $$nextSegDataPt=~/^FPXR\0/),
                );
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xe3) {         # APP3 (Kodak "Meta")
            if ($$segDataPt =~ /^(Meta|META|Exif)\0\0/) {
                undef $dumpType;    # (will be dumped here)
                my %dirInfo = (
                    Parent => $markerName,
                    DataPt => $segDataPt,
                    DataPos => $segPos,
                    DirStart => 6,
                    Base => $segPos + 6,
                );
                if ($htmlDump) {
                    $self->HtmlDump($segPos-4, 10, 'APP3 Meta header');
                    $dumpEnd = $segPos + $length;
                }
                my $tagTablePtr = GetTagTable('Image::ExifTool::Kodak::Meta');
                $self->ProcessTIFF(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xe5) {         # APP5 (Ricoh "RMETA")
            if ($$segDataPt =~ /^RMETA\0/) {
                $dumpType = 'Ricoh RMETA';
                my %dirInfo = (
                    Parent => $markerName,
                    DataPt => $segDataPt,
                    DataPos => $segPos,
                    DirStart => 6,
                    Base => $segPos + 6,
                );
                my $tagTablePtr = GetTagTable('Image::ExifTool::Ricoh::RMETA');
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xe6) {         # APP6 (Toshiba EPPIM)
            if ($$segDataPt =~ /^EPPIM\0/) {
                undef $dumpType;    # (will be dumped here)
                my %dirInfo = (
                    Parent => $markerName,
                    DataPt => $segDataPt,
                    DataPos => $segPos,
                    DirStart => 6,
                    Base => $segPos + 6,
                );
                if ($htmlDump) {
                    $self->HtmlDump($segPos-4, 10, 'APP6 EPPIM header');
                    $dumpEnd = $segPos + $length;
                }
                my $tagTablePtr = GetTagTable('Image::ExifTool::JPEG::EPPIM');
                $self->ProcessTIFF(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xe8) {         # APP8 (SPIFF)
            # my sample SPIFF has 32 bytes of data, but spec states 30
            if ($$segDataPt =~ /^SPIFF\0/ and $length == 32) {
                $dumpType = 'SPIFF';
                my %dirInfo = (
                    DataPt => $segDataPt,
                    DataPos  => $segPos,
                    DirStart => 6,
                    DirLen => $length - 6,
                );
                my $tagTablePtr = GetTagTable('Image::ExifTool::JPEG::SPIFF');
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xea) {         # APP10 (PhotoStudio Unicode comments)
            if ($$segDataPt =~ /^UNICODE\0/) {
                $dumpType = 'PhotoStudio';
                my $comment = $self->Unicode2Charset(substr($$segDataPt,8), 'MM');
                $self->FoundTag('Comment', $comment);
            }
        } elsif ($marker == 0xec) {         # APP12 (Ducky, Picture Info)
            if ($$segDataPt =~ /^Ducky/) {
                $dumpType = 'Ducky';
                my %dirInfo = (
                    DataPt => $segDataPt,
                    DataPos => $segPos,
                    DirStart => 5,
                    DirLen => $length - 5,
                );
                my $tagTablePtr = GetTagTable('Image::ExifTool::APP12::Ducky');
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            } else {
                my %dirInfo = ( DataPt => $segDataPt );
                my $tagTablePtr = GetTagTable('Image::ExifTool::APP12::PictureInfo');
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr) and $dumpType = 'Picture Info';
            }
        } elsif ($marker == 0xed) {         # APP13 (Photoshop, Adobe_CM)
            my $isOld;
            if ($$segDataPt =~ /^$psAPP13hdr/ or ($$segDataPt =~ /^$psAPP13old/ and $isOld=1)) {
                $dumpType = 'Photoshop';
                # add this data to the combined data if it exists
                my $dataPt = $segDataPt;
                if (defined $combinedSegData) {
                    $combinedSegData .= substr($$segDataPt,length($psAPP13hdr));
                    $dataPt = \$combinedSegData;
                }
                # peek ahead to see if the next segment is photoshop data too
                if ($nextMarker == $marker and $$nextSegDataPt =~ /^$psAPP13hdr/) {
                    # initialize combined data if necessary
                    $combinedSegData = $$segDataPt unless defined $combinedSegData;
                    # (will handle the Photoshop data the next time around)
                } else {
                    my $hdrlen = $isOld ? 27 : 14;
                    # process APP13 Photoshop record
                    my $tagTablePtr = GetTagTable('Image::ExifTool::Photoshop::Main');
                    my %dirInfo = (
                        DataPt   => $dataPt,
                        DataPos  => $segPos,
                        DataLen  => length $$dataPt,
                        DirStart => $hdrlen,    # directory starts after identifier
                        DirLen   => length($$dataPt) - $hdrlen,
                        Parent   => $markerName,
                    );
                    $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
                    undef $combinedSegData;
                }
            } elsif ($$segDataPt =~ /^Adobe_CM/) {
                $dumpType = 'Adobe_CM';
                SetByteOrder('MM');
                my $tagTablePtr = GetTagTable('Image::ExifTool::JPEG::AdobeCM');
                my %dirInfo = (
                    DataPt   => $segDataPt,
                    DataPos  => $segPos,
                    DirStart => 8,
                    DirLen   => $length - 8,
                );
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xee) {         # APP14 (Adobe)
            if ($$segDataPt =~ /^Adobe/) {
                $dumpType = 'Adobe';
                SetByteOrder('MM');
                my $tagTablePtr = GetTagTable('Image::ExifTool::JPEG::Adobe');
                my %dirInfo = (
                    DataPt   => $segDataPt,
                    DataPos  => $segPos,
                    DirStart => 5,
                    DirLen   => $length - 5,
                );
                $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
            }
        } elsif ($marker == 0xef) {         # APP15 (GraphicConverter)
            if ($$segDataPt =~ /^Q\s*(\d+)/ and $length == 4) {
                $dumpType = 'GraphicConverter';
                my $tagTablePtr = GetTagTable('Image::ExifTool::JPEG::GraphConv');
                $self->HandleTag($tagTablePtr, 'Q', $1);
            }
        } elsif ($marker == 0xfe) {         # COM (JPEG comment)
            $dumpType = 'Comment';
            $self->FoundTag('Comment', $$segDataPt);
        } elsif (($marker & 0xf0) != 0xe0) {
            undef $dumpType;    # only dump unknown APP segments
        }
        if (defined $dumpType) {
            if (not $dumpType and $self->{OPTIONS}->{Unknown}) {
                $self->Warn("Unknown $markerName segment", 1);
            }
            if ($htmlDump) {
                my $desc = $markerName . ($dumpType ? " $dumpType" : '') . ' segment';
                $self->HtmlDump($segPos-4, $length+4, $desc, undef, 0x08);
                $dumpEnd = $segPos + $length;
            }
        }
        undef $$segDataPt;
    }
    $/ = $oldsep;     # restore separator to original value
    $success or $self->Warn('JPEG format error');
    return 1;
}

#------------------------------------------------------------------------------
# Process TIFF data
# Inputs: 0) ExifTool object reference, 1) directory information reference
#         2) optional tag table reference
# Returns: 1 if this looked like a valid EXIF block, 0 otherwise, or -1 on write error
sub ProcessTIFF($$;$)
{
    my ($self, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $fileType = $$dirInfo{Parent} || '';
    my $raf = $$dirInfo{RAF};
    my $base = $$dirInfo{Base} || 0;
    my $outfile = $$dirInfo{OutFile};
    my ($length, $err, $canonSig);

    # read the image file header and offset to 0th IFD if necessary
    if ($raf) {
        if ($outfile) {
            $raf->Seek(0, 0) or return 0;
            if ($base) {
                $raf->Read($$dataPt, $base) == $base or return 0;
                Write($outfile, $$dataPt) or $err = 1;
            }
        } else {
            $raf->Seek($base, 0) or return 0;
        }
        $raf->Read($self->{EXIF_DATA}, 8) == 8 or return 0;
    } elsif ($dataPt) {
        # save a copy of the EXIF data
        my $dirStart = $$dirInfo{DirStart} || 0;
        $self->{EXIF_DATA} = substr(${$$dirInfo{DataPt}}, $dirStart);
    } elsif ($outfile) {
        # create TIFF information from scratch
        $self->{EXIF_DATA} = "MM\0\x2a\0\0\0\x08";
    } else {
        $self->{EXIF_DATA} = '';
    }
    $$self{FIRST_EXIF_POS} = $base + $$self{BASE} unless defined $$self{FIRST_EXIF_POS};
    $$self{EXIF_POS} = $base;
    $dataPt = \$self->{EXIF_DATA};

    # set byte ordering
    my $byteOrder = substr($$dataPt,0,2);
    SetByteOrder($byteOrder) or return 0;
    # save EXIF byte ordering
    $self->{EXIF_BYTE_ORDER} = $byteOrder;

    # verify the byte ordering
    my $identifier = Get16u($dataPt, 2);
    # identifier is 0x2a for TIFF (but 0x4f52, 0x5352 or ?? for ORF)
  # no longer do this because ORF files use different values
  #  return 0 unless $identifier == 0x2a;

    # get offset to IFD0
    my $offset = Get32u($dataPt, 4);
    $offset >= 8 or return 0;

    if ($raf) {
        # Canon CR2 images usually have an offset of 16, but it may be
        # greater if edited by PhotoMechanic, so check the 4-byte signature
        if ($identifier == 0x2a and $offset >= 16) {
            $raf->Read($canonSig, 8) == 8 or return 0;
            $$dataPt .= $canonSig;
            if ($canonSig =~ /^(CR\x02\0|\xba\xb0\xac\xbb)/) {
                $fileType = $canonSig =~ /^CR/ ? 'CR2' : 'Canon 1D RAW';
                $self->HtmlDump($base+8, 8, "[$fileType header]") if $self->{HTML_DUMP};
            } else {
                undef $canonSig;
            }
        } elsif ($identifier == 0x55 and $fileType =~ /^(RAW|TIFF)$/) {
            $fileType = 'RAW';  # Panasonic RAW file
            $tagTablePtr = GetTagTable('Image::ExifTool::Panasonic::Raw');
        } elsif ($identifier == 0x2b and $fileType eq 'TIFF') {
            # this looks like a BigTIFF image
            $raf->Seek(0);
            require Image::ExifTool::BigTIFF;
            return 1 if Image::ExifTool::BigTIFF::ProcessBTF($self, $dirInfo);
        } elsif (Get8u($dataPt, 2) == 0xbc and $byteOrder eq 'II' and $fileType eq 'TIFF') {
            $fileType = 'HDP';  # Windows HD Photo file
            # check version number
            my $ver = Get8u($dataPt, 3);
            if ($ver > 1) {
                $self->Error("Windows HD Photo version $ver files not yet supported");
                return 1;
            }
        }
        # we have a valid TIFF (or whatever) file
        if ($fileType and not $self->{VALUE}->{FileType}) {
            $self->SetFileType($fileType);
        }
    }
    $self->FoundTag('ExifByteOrder', GetByteOrder());
    if ($self->{HTML_DUMP}) {
        my $tip = sprintf('Byte order: %s endian\\nIdentifier: 0x%.4x\\nIFD0 offset: 0x%.4x',
                          (GetByteOrder() eq 'II') ? 'Little' : 'Big', $identifier, $offset);
        $self->HtmlDump($base, 8, "TIFF header", $tip, 0);
    }
    # remember where we found the TIFF data (APP1, APP3, TIFF, NEF, etc...)
    $self->{TIFF_TYPE} = $fileType;

    # get reference to the main EXIF table
    $tagTablePtr or $tagTablePtr = GetTagTable('Image::ExifTool::Exif::Main');

    # build directory information hash
    my %dirInfo = (
        Base     => $base,
        DataPt   => $dataPt,
        DataLen  => length $$dataPt,
        DataPos  => 0,
        DirStart => $offset,
        DirLen   => length($$dataPt) - $offset,
        RAF      => $raf,
        DirName  => 'IFD0',
        Parent   => $fileType,
        ImageData=> 1, # set flag to get information to copy image data later
    );

    # extract information from the image
    unless ($outfile) {
        # process the directory
        $self->ProcessDirectory(\%dirInfo, $tagTablePtr);
        # process GeoTiff information if available
        if ($self->{VALUE}->{GeoTiffDirectory}) {
            require Image::ExifTool::GeoTiff;
            Image::ExifTool::GeoTiff::ProcessGeoTiff($self);
        }
        # process information in recognized trailers
        if ($raf) {
            my $trailInfo = IdentifyTrailer($raf);
            if ($trailInfo) {
                $$trailInfo{ScanForAFCP} = 1;   # scan to find AFCP if necessary
                $self->ProcessTrailers($trailInfo);
            }
        }
        return 1;
    }
#
# rewrite the image
#
    if ($$dirInfo{NoTiffEnd}) {
        delete $self->{TIFF_END};
    } else {
        # initialize TIFF_END so it will be updated by WriteExif()
        $self->{TIFF_END} = 0;
    }
    if ($canonSig) {
        # write Canon CR2 specially because it has a header we want to preserve,
        # and possibly trailers added by the Canon utilities and/or PhotoMechanic
        $dirInfo{OutFile} = $outfile;
        require Image::ExifTool::CanonRaw;
        Image::ExifTool::CanonRaw::WriteCR2($self, \%dirInfo, $tagTablePtr) or $err = 1;
    } else {
        # write TIFF header (8 bytes to be immediately followed by IFD)
        $dirInfo{NewDataPos} = 8;
        # preserve padding between image data blocks in ORF images
        # (otherwise dcraw has problems because it assumes fixed block spacing)
        $dirInfo{PreserveImagePadding} = 1 if $fileType eq 'ORF' or $identifier != 0x2a;
        my $newData = $self->WriteDirectory(\%dirInfo, $tagTablePtr);
        if (not defined $newData) {
            $err = 1;
        } elsif (length($newData)) {
            my $offset = 8;
            my $header = substr($$dataPt, 0, 4) . Set32u($offset);
            Write($outfile, $header, $newData) or $err = 1;
            undef $newData; # free memory
        }
        # copy over image data now if necessary
        if (ref $dirInfo{ImageData} and not $err) {
            $self->CopyImageData($dirInfo{ImageData}, $outfile) or $err = 1;
            delete $dirInfo{ImageData};
        }
    }
    # rewrite trailers if they exist
    if ($raf and $self->{TIFF_END} and not $err) {
        my ($buf, $trailInfo);
        $raf->Seek(0, 2) or $err = 1;
        my $extra = $raf->Tell() - $self->{TIFF_END};
        # check for trailer and process if possible
        for (;;) {
            last unless $extra > 12;
            $raf->Seek($self->{TIFF_END});  # seek back to end of image
            $trailInfo = IdentifyTrailer($raf);
            last unless $trailInfo;
            my $tbuf = '';
            $$trailInfo{OutFile} = \$tbuf;  # rewrite trailer(s)
            $$trailInfo{ScanForAFCP} = 1;   # scan for AFCP if necessary
            # rewrite all trailers to buffer
            unless ($self->ProcessTrailers($trailInfo)) {
                undef $trailInfo;
                $err = 1;
                last;
            }
            # calculate unused bytes before trailer
            $extra = $$trailInfo{DataPos} - $self->{TIFF_END};
            last; # yes, the 'for' loop was just a cheap 'goto'
        }
        # ignore a single zero byte if used for padding
        # (note that Photoshop CS adds a trailer with 2 zero bytes
        #  for some reason, and these will be preserved)
        if ($extra > 0 and $self->{TIFF_END} & 0x01) {
            $raf->Seek($self->{TIFF_END}, 0) or $err = 1;
            $raf->Read($buf, 1) or $err = 1;
            $buf eq "\0" and --$extra, ++$self->{TIFF_END};
        }
        if ($extra > 0) {
            if ($self->{DEL_GROUP}->{Trailer}) {
                $self->VPrint(0, "  Deleting unknown trailer ($extra bytes)\n");
                ++$self->{CHANGED};
            } else {
                $self->VPrint(0, "  Preserving unknown trailer ($extra bytes)\n");
                $raf->Seek($self->{TIFF_END}, 0) or $err = 1;
                while ($extra) {
                    my $n = $extra < 65536 ? $extra : 65536;
                    $raf->Read($buf, $n) == $n or $err = 1, last;
                    Write($outfile, $buf) or $err = 1, last;
                    $extra -= $n;
                }
            }
        }
        # write trailer buffer if necessary
        $self->WriteTrailerBuffer($trailInfo, $outfile) or $err = 1 if $trailInfo;
        # add any new trailers we are creating
        my $trailPt = $self->AddNewTrailers();
        Write($outfile, $$trailPt) or $err = 1 if $trailPt;
    }
    # check DNG version
    if ($$self{DNGVersion} and $$self{DNGVersion} ge "\x01\x03\0\0") {
        my $ver = join('.', unpack('C*', $$self{DNGVersion}));;
        $self->Error("DNG Version $ver not yet supported", 1);
    }
    delete $self->{TIFF_END};
    return $err ? -1 : 1;
}

#------------------------------------------------------------------------------
# Return list of tag table keys (ignoring special keys)
# Inputs: 0) reference to tag table
# Returns: List of table keys (unsorted)
sub TagTableKeys($)
{
    local $_;
    my $tagTablePtr = shift;
    my @keyList;
    foreach (keys %$tagTablePtr) {
        push(@keyList, $_) unless $specialTags{$_};
    }
    return @keyList;
}

#------------------------------------------------------------------------------
# GetTagTable
# Inputs: 0) table name
# Returns: tag table reference, or undefined if not found
# Notes: Always use this function instead of requiring module and using table
# directly since this function also does the following the first time the table
# is loaded:
# - requires new module if necessary
# - generates default GROUPS hash and Group 0 name from module name
# - registers Composite tags if Composite table found
# - saves descriptions for tags in specified table
# - generates default TAG_PREFIX to be used for unknown tags
sub GetTagTable($)
{
    my $tableName = shift or return undef;

    my $table = $allTables{$tableName};

    unless ($table) {
        no strict 'refs';
        unless (defined %$tableName) {
            # try to load module for this table
            if ($tableName =~ /(.*)::/) {
                my $module = $1;
                unless (eval "require $module") {
                    $@ and warn $@;
                }
            }
            unless (defined %$tableName) {
                warn "Can't find table $tableName\n";
                return undef;
            }
        }
        no strict 'refs';
        $table = \%$tableName;
        use strict 'refs';
        # set default group 0 and 1 from module name unless already specified
        my $defaultGroups = $$table{GROUPS};
        $defaultGroups or $defaultGroups = $$table{GROUPS} = { };
        unless ($$defaultGroups{0} and $$defaultGroups{1}) {
            if ($tableName =~ /Image::.*?::([^:]*)/) {
                $$defaultGroups{0} = $1 unless $$defaultGroups{0};
                $$defaultGroups{1} = $1 unless $$defaultGroups{1};
            } else {
                $$defaultGroups{0} = $tableName unless $$defaultGroups{0};
                $$defaultGroups{1} = $tableName unless $$defaultGroups{1};
            }
        }
        $$defaultGroups{2} = 'Other' unless $$defaultGroups{2};
        # generate a tag prefix for unknown tags if necessary
        unless ($$table{TAG_PREFIX}) {
            my $tagPrefix;
            if ($tableName =~ /Image::.*?::(.*)::Main/ || $tableName =~ /Image::.*?::(.*)/) {
                ($tagPrefix = $1) =~ s/::/_/g;
            } else {
                $tagPrefix = $tableName;
            }
            $$table{TAG_PREFIX} = $tagPrefix;
        }
        # set up the new table
        SetupTagTable($table);
        # add any user-defined tags
        if (defined %UserDefined and $UserDefined{$tableName}) {
            my $tagID;
            foreach $tagID (TagTableKeys($UserDefined{$tableName})) {
                my $tagInfo = $UserDefined{$tableName}->{$tagID};
                if (ref $tagInfo eq 'HASH') {
                    $$tagInfo{Name} or $$tagInfo{Name} = ucfirst($tagID);
                } else {
                    $tagInfo = { Name => $tagInfo };
                }
                if ($$table{WRITABLE} and not defined $$tagInfo{Writable} and
                    not $$tagInfo{SubDirectory})
                {
                    $$tagInfo{Writable} = $$table{WRITABLE};
                }
                delete $$table{$tagID}; # replace any existing entry
                AddTagToTable($table, $tagID, $tagInfo);
            }
        }
        # generate tag ID's if necessary
        GenerateTagIDs($table) if $didTagID;
        # remember order we loaded the tables in
        push @tableOrder, $tableName;
        # insert newly loaded table into list
        $allTables{$tableName} = $table;
    }
    return $table;
}

#------------------------------------------------------------------------------
# Process an image directory
# Inputs: 0) ExifTool object reference, 1) directory information reference
#         2) tag table reference, 3) optional reference to processing procedure
# Returns: Result from processing (1=success)
sub ProcessDirectory($$$;$)
{
    my ($self, $dirInfo, $tagTablePtr, $processProc) = @_;

    return 0 unless $tagTablePtr and $dirInfo;
    # use default proc from tag table if no proc specified
    $processProc or $processProc = $$tagTablePtr{PROCESS_PROC};
    # set directory name from default group0 name if not done already
    $$dirInfo{DirName} or $$dirInfo{DirName} = $tagTablePtr->{GROUPS}->{0};
    # guard against cyclical recursion into the same directory
    if (defined $$dirInfo{DirStart} and defined $$dirInfo{DataPos}) {
        my $addr = $$dirInfo{DirStart} + $$dirInfo{DataPos} + ($$dirInfo{Base}||0);
        if ($self->{PROCESSED}->{$addr}) {
            $self->Warn("$$dirInfo{DirName} pointer references previous $self->{PROCESSED}->{$addr} directory");
            return 0;
        }
        $self->{PROCESSED}->{$addr} = $$dirInfo{DirName};
    }
    # otherwise process as an EXIF directory
    $processProc or $processProc = \&Image::ExifTool::Exif::ProcessExif;
    my $oldOrder = GetByteOrder();
    my $oldIndent = $self->{INDENT};
    my $oldDir = $self->{DIR_NAME};
    $self->{LIST_TAGS} = { };  # don't build lists across different directories
    $self->{INDENT} .= '| ';
    $self->{DIR_NAME} = $$dirInfo{DirName};
    my $rtnVal = &$processProc($self, $dirInfo, $tagTablePtr);
    $self->{INDENT} = $oldIndent;
    $self->{DIR_NAME} = $oldDir;
    SetByteOrder($oldOrder);
    return $rtnVal;
}

#------------------------------------------------------------------------------
# Get standardized file extension
# Inputs: 0) file name
# Returns: standardized extension (all uppercase)
sub GetFileExtension($)
{
    my $filename = shift;
    my $fileExt;
    if ($filename and $filename =~ /.*\.(.+)$/) {
        $fileExt = uc($1);   # change extension to upper case
        # convert TIF extension to TIFF because we use the
        # extension for the file type tag of TIFF images
        $fileExt eq 'TIF' and $fileExt = 'TIFF';
    }
    return $fileExt;
}

#------------------------------------------------------------------------------
# Get list of tag information hashes for given tag ID
# Inputs: 0) Tag table reference, 1) tag ID
# Returns: Array of tag information references
# Notes: Generates tagInfo hash if necessary
sub GetTagInfoList($$)
{
    my ($tagTablePtr, $tagID) = @_;
    my $tagInfo = $$tagTablePtr{$tagID};

    if (ref $tagInfo eq 'HASH') {
        return ($tagInfo);
    } elsif (ref $tagInfo eq 'ARRAY') {
        return @$tagInfo;
    } elsif ($tagInfo) {
        # create hash with name
        $tagInfo = $$tagTablePtr{$tagID} = { Name => $tagInfo };
        return ($tagInfo);
    }
    return ();
}

#------------------------------------------------------------------------------
# Find tag information, processing conditional tags
# Inputs: 0) ExifTool object reference, 1) tagTable pointer, 2) tag ID
#         3) optional value reference, 4) optional format type, 5) optional value count
# Returns: pointer to tagInfo hash, undefined if none found, or '' if $valPt needed
# Notes: You should always call this routine to find a tag in a table because
# this routine will evaluate conditional tags.
# Arguments 3-5 are only required if the information type allows $valPt, $format and/or
# $count in a Condition, and if not given when needed this routine returns ''.
sub GetTagInfo($$$;$$$)
{
    my ($self, $tagTablePtr, $tagID) = @_;
    my ($valPt, $format, $count);

    my @infoArray = GetTagInfoList($tagTablePtr, $tagID);
    # evaluate condition
    my $tagInfo;
    foreach $tagInfo (@infoArray) {
        my $condition = $$tagInfo{Condition};
        if ($condition) {
            ($valPt, $format, $count) = splice(@_, 3) if @_ > 3;
            return '' if $condition =~ /\$(valPt|format|count)\b/ and not defined $valPt;
            # set old value for use in condition if needed
            my $oldVal = $self->{VALUE}->{$$tagInfo{Name}};
            #### eval Condition ($self, $oldVal, [$valPt, $format, $count])
            unless (eval $condition) {
                $@ and warn "Condition $$tagInfo{Name}: $@";
                next;
            }
        }
        if ($$tagInfo{Unknown} and not $self->{OPTIONS}->{Unknown}) {
            # don't return Unknown tags unless that option is set
            return undef;
        }
        # return the tag information we found
        return $tagInfo;
    }
    # generate information for unknown tags (numerical only) if required
    if (not $tagInfo and $self->{OPTIONS}->{Unknown} and $tagID =~ /^\d+$/ and
        not $$self{NO_UNKNOWN})
    {
        my $printConv;
        if (defined $$tagTablePtr{PRINT_CONV}) {
            $printConv = $$tagTablePtr{PRINT_CONV};
        } else {
            # limit length of printout (can be very long)
            $printConv = 'length($val) > 60 ? substr($val,0,55) . "[...]" : $val';
        }
        my $hex = sprintf("0x%.4x", $tagID);
        my $prefix = $$tagTablePtr{TAG_PREFIX};
        $tagInfo = {
            Name => "${prefix}_$hex",
            Description => MakeDescription($prefix, $hex),
            Unknown => 1,
            Writable => 0,  # can't write unknown tags
            PrintConv => $printConv,
        };
        # add tag information to table
        AddTagToTable($tagTablePtr, $tagID, $tagInfo);
    } else {
        undef $tagInfo;
    }
    return $tagInfo;
}

#------------------------------------------------------------------------------
# Add new tag to table (must use this routine to add new tags to a table)
# Inputs: 0) reference to tag table, 1) tag ID
#         2) reference to tag information hash
# Notes: - will not overwrite existing entry in table
# - info need contain no entries when this routine is called
sub AddTagToTable($$$)
{
    my ($tagTablePtr, $tagID, $tagInfo) = @_;

    # define necessary entries in information hash
    if ($$tagInfo{Groups}) {
        # fill in default groups from table GROUPS
        foreach (keys %{$$tagTablePtr{GROUPS}}) {
            next if $tagInfo->{Groups}->{$_};
            $tagInfo->{Groups}->{$_} = $tagTablePtr->{GROUPS}->{$_};
        }
    } else {
        $$tagInfo{Groups} = $$tagTablePtr{GROUPS};
    }
    $$tagInfo{Flags} and ExpandFlags($tagInfo);
    $$tagInfo{GotGroups} = 1,
    $$tagInfo{Table} = $tagTablePtr;
    $$tagInfo{TagID} = $tagID;

    unless ($$tagInfo{Name}) {
        my $prefix = $$tagTablePtr{TAG_PREFIX};
        $$tagInfo{Name} = "${prefix}_$tagID";
        # make description to prevent tagID from getting mangled by MakeDescription()
        $$tagInfo{Description} = MakeDescription($prefix, $tagID);
    }
    # add tag to table, but never overwrite existing entries (could potentially happen
    # if someone thinks there isn't any tagInfo because a condition wasn't satisfied)
    $$tagTablePtr{$tagID} = $tagInfo unless defined $$tagTablePtr{$tagID};
}

#------------------------------------------------------------------------------
# Handle simple extraction of new tag information
# Inputs: 0) ExifTool object ref, 1) tag table reference, 2) tagID, 3) value,
#         4-N) parameters hash: Index, DataPt, DataPos, Start, Size, Parent,
#              TagInfo, ProcessProc
# Returns: tag key or undef if tag not found
sub HandleTag($$$$;%)
{
    my ($self, $tagTablePtr, $tag, $val, %parms) = @_;
    my $verbose = $self->{OPTIONS}->{Verbose};
    my $tagInfo = $parms{TagInfo} || $self->GetTagInfo($tagTablePtr, $tag, \$val);
    my $dataPt = $parms{DataPt};
    my $subdir;

    if ($tagInfo) {
        $subdir = $$tagInfo{SubDirectory}
    } else {
        return undef unless $verbose;
    }
    # read value if not done already (not necessary for subdir)
    unless (defined $val or $subdir) {
        my $start = $parms{Start} || 0;
        my $size = $parms{Size} || 0;
        # read from data in memory if possible
        if ($dataPt and $start >= 0 and $start + $size <= length($$dataPt)) {
            $val = substr($$dataPt, $start, $size);
        } else {
            my $name = $tagInfo ? $$tagInfo{Name} : "tag $tag";
            $self->Warn("Error extracting value for $name");
            return undef;
        }
    }
    # do verbose print if necessary
    if ($verbose) {
        $parms{Value} = $val;
        $parms{Table} = $tagTablePtr;
        $self->VerboseInfo($tag, $tagInfo, %parms);
    }
    if ($tagInfo) {
        if ($subdir) {
            my $subdirStart = $parms{Start};
            if ($$subdir{Start}) {
                my $valuePtr = 0;
                #### eval Start ()
                $subdirStart += eval $$subdir{Start};
            }
            $dataPt or $dataPt = \$val;
            # process subdirectory information
            my %dirInfo = (
                DirName  => $$subdir{DirName} || $$tagInfo{Name},
                DataPt   => $dataPt,
                DataLen  => length $$dataPt,
                DataPos  => $parms{DataPos},
                DirStart => $subdirStart,
                DirLen   => $parms{Size},
                Parent   => $parms{Parent},
                Base     => $parms{Base},
                Multi    => $$subdir{Multi},
            );
            my $oldOrder = GetByteOrder();
            SetByteOrder($$subdir{ByteOrder}) if $$subdir{ByteOrder};
            my $subTablePtr = GetTagTable($$subdir{TagTable}) || $tagTablePtr;
            $self->ProcessDirectory(\%dirInfo, $subTablePtr, $$subdir{ProcessProc});
            SetByteOrder($oldOrder);
        } else {
            return $self->FoundTag($tagInfo, $val);
        }
    }
    return undef;
}

#------------------------------------------------------------------------------
# Add tag to hash of extracted information
# Inputs: 0) reference to ExifTool object
#         1) reference to tagInfo hash or tag name
#         2) data value (or reference to require hash if composite)
# Returns: tag key or undef if no value
sub FoundTag($$$)
{
    local $_;
    my ($self, $tagInfo, $value) = @_;
    my $tag;

    if (ref $tagInfo eq 'HASH') {
        $tag = $$tagInfo{Name} or warn("No tag name\n"), return undef;
    } else {
        $tag = $tagInfo;
        # look for tag in Extra
        $tagInfo = $self->GetTagInfo(GetTagTable('Image::ExifTool::Extra'), $tag);
        # make temporary hash if tag doesn't exist in Extra
        # (not advised to do this since the tag won't show in list)
        $tagInfo or $tagInfo = { Name => $tag, Groups => \%allGroupsExifTool };
        $self->{OPTIONS}->{Verbose} and $self->VerboseInfo(undef, $tagInfo, Value => $value);
    }
    my $rawValueHash = $self->{VALUE};
    if ($$tagInfo{RawConv}) {
        my $conv = $$tagInfo{RawConv};
        my $val = $value;   # must do this in case eval references $val
        # initialize @val for use in Composite RawConv expressions
        my @val;
        if (ref $val eq 'HASH') {
            foreach (keys %$val) { $val[$_] = $$rawValueHash{$$val{$_}}; }
        }
        if (ref $conv eq 'CODE') {
            $value = &$conv($val, $self);
        } else {
            #### eval RawConv ($self, $val)
            $value = eval $conv;
            $@ and warn "RawConv: $@\n";
        }
        return undef unless defined $value;
    }
    # get tag priority
    my $priority = $$tagInfo{Priority};
    defined $priority or $priority = $tagInfo->{Table}->{PRIORITY};
    # handle duplicate tag names
    if (defined $$rawValueHash{$tag}) {
        # add to list if there is an active list for this tag
        if ($self->{LIST_TAGS}->{$tagInfo}) {
            $tag = $self->{LIST_TAGS}->{$tagInfo};  # use key from previous list tag
            if (ref $$rawValueHash{$tag} ne 'ARRAY') {
                $$rawValueHash{$tag} = [ $$rawValueHash{$tag} ];
            }
            push @{$$rawValueHash{$tag}}, $value;
            return $tag;    # return without creating a new entry
        }
        # get next available tag key
        my $nextTag = NextTagKey($rawValueHash, $tag);
#
# take tag with highest priority
#
        # promote existing 0-priority tag so it takes precedence over a new 0-tag
        my $oldPriority = $self->{PRIORITY}->{$tag} || 1;
        # set priority for this tag (default is 1)
        $priority = 1 if not defined $priority or
            # increase 0-priority tags if this is the priority directory
            ($priority == 0 and $self->{DIR_NAME} and $self->{PRIORITY_DIR} and
            $self->{DIR_NAME} eq $self->{PRIORITY_DIR});
        if ($priority >= $oldPriority) {
            # move existing tag out of the way since this tag is higher priority
            $self->{MOVED_KEY} = $nextTag;  # used in BuildCompositeTags()
            $self->{PRIORITY}->{$nextTag} = $self->{PRIORITY}->{$tag};
            $$rawValueHash{$nextTag} = $$rawValueHash{$tag};
            $self->{FILE_ORDER}->{$nextTag} = $self->{FILE_ORDER}->{$tag};
            my $oldInfo = $self->{TAG_INFO}->{$nextTag} = $self->{TAG_INFO}->{$tag};
            if ($self->{GROUP1}->{$tag}) {
                $self->{GROUP1}->{$nextTag} = $self->{GROUP1}->{$tag};
                delete $self->{GROUP1}->{$tag};
            }
            # update tag key for list if necessary
            $self->{LIST_TAGS}->{$oldInfo} = $nextTag if $self->{LIST_TAGS}->{$oldInfo};
        } else {
            $tag = $nextTag;        # don't override the existing tag
        }
        $self->{PRIORITY}->{$tag} = $priority;
    } elsif ($priority) {
        # set tag priority (only if exists and non-zero)
        $self->{PRIORITY}->{$tag} = $priority;
    }

    # save the raw value, file order, tagInfo ref, group1 name,
    # and tag key for lists if necessary
    $$rawValueHash{$tag} = $value;
    $self->{FILE_ORDER}->{$tag} = ++$self->{NUM_FOUND};
    $self->{TAG_INFO}->{$tag} = $tagInfo;
    $self->{GROUP1}->{$tag} = $self->{SET_GROUP1} if $self->{SET_GROUP1};
    $self->{LIST_TAGS}->{$tagInfo} = $tag if $$tagInfo{List} and not $$self{NO_LIST};

    return $tag;
}

#------------------------------------------------------------------------------
# Get next available tag key
# Inputs: 0) hash reference (keys are tag keys), 1) tag name
# Returns: next available tag key
sub NextTagKey($$)
{
    my ($info, $tag) = @_;
    if (exists $$info{$tag}) {
        my $name = $tag;
        my $i;
        for ($i=1; ; ++$i) {
            $tag = "$name ($i)";
            last unless exists $$info{$tag};
        }
    }
    return $tag;
}

#------------------------------------------------------------------------------
# Make current directory the priority directory if not set already
# Inputs: 0) reference to ExifTool object
sub SetPriorityDir($)
{
    my $self = shift;
    $self->{PRIORITY_DIR} = $self->{DIR_NAME} unless $self->{PRIORITY_DIR};
}

#------------------------------------------------------------------------------
# Set family 1 group name specific to this tag instance
# Inputs: 0) reference to ExifTool object, 1) tag key, 2) group name
sub SetGroup1($$$)
{
    my ($self, $tagKey, $extra) = @_;
    $self->{GROUP1}->{$tagKey} = $extra;
}

#------------------------------------------------------------------------------
# Set ID's for all tags in specified table
# Inputs: 0) tag table reference
sub GenerateTagIDs($)
{
    my $table = shift;

    unless ($$table{DID_TAG_ID}) {
        $$table{DID_TAG_ID} = 1;    # set flag so we won't do this table again
        my ($tagID, $tagInfo);
        foreach $tagID (keys %$table) {
            next if $specialTags{$tagID};
            # define tag ID in each element of conditional array
            my @infoArray = GetTagInfoList($table,$tagID);
            foreach $tagInfo (@infoArray) {
                # define tag ID's in info hash
                $$tagInfo{TagID} = $tagID;
            }
        }
    }
}

#------------------------------------------------------------------------------
# Generate TagID's for all loaded tables
# Inputs: None
# Notes: Causes subsequently loaded tables to automatically generate TagID's too
sub GenerateAllTagIDs()
{
    unless ($didTagID) {
        my $tableName;
        foreach $tableName (keys %allTables) {
            # generate tag ID's for all tags in this table
            GenerateTagIDs($allTables{$tableName});
        }
        $didTagID = 1;
    }
}

#------------------------------------------------------------------------------
# Delete specified tag
# Inputs: 0) reference to ExifTool object
#         1) tag key
sub DeleteTag($$)
{
    my ($self, $tag) = @_;
    delete $self->{VALUE}->{$tag};
    delete $self->{FILE_ORDER}->{$tag};
    delete $self->{TAG_INFO}->{$tag};
    delete $self->{GROUP1}->{$tag};
}

#------------------------------------------------------------------------------
# Set the FileType and MIMEType tags
# Inputs: 0) ExifTool object reference
#         1) Optional file type (uses FILE_TYPE if not specified)
sub SetFileType($;$)
{
    my $self = shift;
    my $baseType = $self->{FILE_TYPE};
    my $fileType = shift || $baseType;
    my $mimeType = $mimeType{$fileType};
    # use base file type if necessary (except if 'TIFF', which is a special case)
    $mimeType = $mimeType{$baseType} unless $mimeType or $baseType eq 'TIFF';
    $self->FoundTag('FileType', $fileType);
    $self->FoundTag('MIMEType', $mimeType || 'application/unknown');
}

#------------------------------------------------------------------------------
# Modify the value of the MIMEType tag
# Inputs: 0) ExifTool object reference, 1) file or MIME type
# Notes: combines existing type with new type: ie) a/b + c/d => c/b-d
sub ModifyMimeType($;$)
{
    my ($self, $mime) = @_;
    $mime =~ m{/} or $mime = $mimeType{$mime} or return;
    my $old = $self->{VALUE}->{MIMEType};
    if (defined $old) {
        my ($a, $b) = split '/', $old;
        my ($c, $d) = split '/', $mime;
        $d =~ s/^x-//;
        $self->{VALUE}->{MIMEType} = "$c/$b-$d";
        $self->VPrint(0, "  Modified MIMEType = $c/$b-$d\n");
    } else {
        $self->FoundTag('MIMEType', $mime);
    }
}

#------------------------------------------------------------------------------
# Print verbose output
# Inputs: 0) ExifTool ref, 1) verbose level (prints if level > this), 2-N) print args
sub VPrint($$@)
{
    my $self = shift;
    my $level = shift;
    if ($self->{OPTIONS}->{Verbose} and $self->{OPTIONS}->{Verbose} > $level) {
        my $out = $self->{OPTIONS}->{TextOut};
        print $out @_;
    }
}

#------------------------------------------------------------------------------
# Verbose dump
# Inputs: 0) ExifTool ref, 1) data ref, 2-N) HexDump options
sub VerboseDump($$;%)
{
    my $self = shift;
    my $dataPt = shift;
    if ($self->{OPTIONS}->{Verbose} and $self->{OPTIONS}->{Verbose} > 2) {
        HexDump($dataPt, undef,
            Out => $self->{OPTIONS}->{TextOut},
            MaxLen => $self->{OPTIONS}->{Verbose} < 4 ? 96 : undef,
            @_
        );
    }
}

#------------------------------------------------------------------------------
# Extract binary data from file
# 0) ExifTool object reference, 1) offset, 2) length, 3) tag name if conditional
# Returns: binary data, or undef on error
# Notes: Returns "Binary data #### bytes" instead of data unless tag is
#        specifically requested or the Binary option is set
sub ExtractBinary($$$;$)
{
    my ($self, $offset, $length, $tag) = @_;

    if ($tag and $tag eq 'PreviewImage') {
        # save PreviewImage start/length in case we want to dump trailer
        $$self{PreviewImageStart} = $offset;
        $$self{PreviewImageLength} = $length;
    }
    if ($tag and not $self->{OPTIONS}->{Binary} and not $self->{OPTIONS}->{Verbose} and
        not $self->{REQ_TAG_LOOKUP}->{lc($tag)})
    {
        return "Binary data $length bytes";
    }
    my $buff;
    unless ($self->{RAF}->Seek($offset,0)
        and $self->{RAF}->Read($buff, $length) == $length)
    {
        $tag or $tag = 'binary data';
        $self->Warn("Error reading $tag from file");
        return undef;
    }
    return $buff;
}

#------------------------------------------------------------------------------
# Process binary data
# Inputs: 0) ExifTool object reference, 1) directory information reference
#         2) tag table reference
# Returns: 1 on success
sub ProcessBinaryData($$$)
{
    my ($self, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $offset = $$dirInfo{DirStart} || 0;
    my $size = $$dirInfo{DirLen} || (length($$dataPt) - $offset);
    my $base = $$dirInfo{Base} || 0;
    my $verbose = $self->{OPTIONS}->{Verbose};
    my $unknown = $self->{OPTIONS}->{Unknown};
    my $dataPos = $$dirInfo{DataPos} || 0;

    # get default format ('int8u' unless specified)
    my $defaultFormat = $$tagTablePtr{FORMAT} || 'int8u';
    my $increment = $formatSize{$defaultFormat};
    unless ($increment) {
        warn "Unknown format $defaultFormat\n";
        $defaultFormat = 'int8u';
        $increment = $formatSize{$defaultFormat};
    }
    # prepare list of tag numbers to extract
    my @tags;
    if ($unknown > 1 and defined $$tagTablePtr{FIRST_ENTRY}) {
        # scan through entire binary table
        @tags = ($$tagTablePtr{FIRST_ENTRY}..(int($size/$increment) - 1));
        # add in floating point tag ID's if they exist
        my @ftags = grep /\./, TagTableKeys($tagTablePtr);
        @tags = sort { $a <=> $b } @tags, @ftags if @ftags;
    } elsif ($$dirInfo{DataMember}) {
        @tags = @{$$dirInfo{DataMember}};
        $verbose = 0;   # no verbose output of extracted values when writing
    } else {
        # extract known tags in numerical order
        @tags = sort { $a <=> $b } TagTableKeys($tagTablePtr);
    }
    $self->VerboseDir('BinaryData', undef, $size) if $verbose;
    # avoid creating unknown tags for tags that fail condition if Unknown is 1
    $$self{NO_UNKNOWN} = 1 if $unknown < 2;
    my $index;
    my $nextIndex = 0;
    my %val;
    foreach $index (@tags) {
        my $tagInfo;
        if ($$tagTablePtr{$index}) {
            $tagInfo = $self->GetTagInfo($tagTablePtr, $index) or next;
            next if $$tagInfo{Unknown} and
                   ($$tagInfo{Unknown} > $unknown or $index < $nextIndex);
        } else {
            # don't generate unknown tags in binary tables unless Unknown > 1
            next unless $unknown > 1;
            next if $index < $nextIndex;    # skip if data already used
            $tagInfo = $self->GetTagInfo($tagTablePtr, $index) or next;
            $$tagInfo{Unknown} = 2;    # set unknown to 2 for binary unknowns
        }
        my $entry = int($index) * $increment;   # relative offset of this entry
        my $count = 1;
        my $format = $$tagInfo{Format};
        if ($format) {
            if ($format =~ /(.*)\[(.*)\]/) {
                $format = $1;
                $count = $2;
                # evaluate count to allow count to be based on previous values
                #### eval Format (%val, $size)
                $count = eval $count;
                $@ and warn("Format $$tagInfo{Name}: $@"), next;
                next if $count < 0;
            } elsif ($format eq 'string') {
                # string with no specified count runs to end of block
                $count = ($size > $entry) ? $size - $entry : 0;
            } elsif ($format eq 'pstring') {
                $count = ($size > $entry) ? Get8u($dataPt, ($entry++)+$offset) : 0;
                $format = 'string';
            }
        } else {
            $format = $defaultFormat;
        }
        # allow nested BinaryData directories
        if ($unknown > 1) {
            # calculate next valid index for unknown tag
            my $ni = int($index) + ($formatSize{$format} * $count) / $increment;
            $nextIndex = $ni unless $nextIndex > $ni;
        }
        if ($$tagInfo{SubDirectory}) {
            my $len = $size - $entry;
            # use specified subdirectory length if given
            if ($$tagInfo{Format} and $formatSize{$format}) {
                my $n = $count * $formatSize{$format};
                $len = $n if $n < $len;
            } else {
                $len = $size - $entry;  # subdirectory runs to end of this one
            }
            my %subdirInfo = (
                DataPt   => $dataPt,
                DirStart => $entry + $offset,
                DirLen   => $len,
                Base     => $base,
            );
            my $subTablePtr = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
            $self->ProcessDirectory(\%subdirInfo, $subTablePtr);
            next;
        }
        my $val = ReadValue($dataPt, $entry+$offset, $format, $count, $size-$entry);
        next unless defined $val;
        $val &= $$tagInfo{Mask} if $$tagInfo{Mask};
        if ($verbose) {
            my $len = $count * ($formatSize{$format} || 1);
            $len > $size - $entry and $len = $size - $entry;
            $self->VerboseInfo($index, $tagInfo,
                Table  => $tagTablePtr,
                Value  => $val,
                DataPt => $dataPt,
                Size   => $len,
                Start  => $entry+$offset,
                Addr   => $entry+$offset+$base+$dataPos,
                Format => $format,
                Count  => $count,
            );
        }
        $val += $base + $$self{BASE} if $$tagInfo{IsOffset};
        $val{$index} = $val;
        $self->FoundTag($tagInfo,$val);
    }
    delete $$self{NO_UNKNOWN};
    return 1;
}

#..............................................................................
# Load .ExifTool_config file from user's home directory (unless 'noConfig' set)
unless ($Image::ExifTool::noConfig) {
    my $config = '.ExifTool_config';
    # get our home directory (HOMEDRIVE and HOMEPATH are used in Windows cmd shell)
    my $home = $ENV{EXIFTOOL_HOME} || $ENV{HOME} ||
               ($ENV{HOMEDRIVE} || '') . ($ENV{HOMEPATH} || '') || '.';
    # look for the config file in 1) the home directory, 2) the program dir
    my $file = "$home/$config";
    -r $file or $file = ($0 =~ /(.*[\\\/])/ ? $1 : './') . $config;
    if (-r $file) {
        eval "require '$file'"; # load the config file
        # print warning (minus "Compilation failed" part)
        $@ and $_=$@, s/Compilation failed.*//s, warn $_;
    }
}

#------------------------------------------------------------------------------
1;  # end
