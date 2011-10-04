#------------------------------------------------------------------------------
# File:         FlashPix.pm
#
# Description:  Read FlashPix meta information
#
# Revisions:    05/29/2006 - P. Harvey Created
#
# References:   1) http://www.exif.org/Exif2-2.PDF
#               2) http://www.graphcomp.com/info/specs/livepicture/fpx.pdf
#               3) http://search.cpan.org/~jdb/libwin32/
#               4) http://msdn2.microsoft.com/en-us/library/aa380374.aspx
#------------------------------------------------------------------------------

package Image::ExifTool::FlashPix;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;
use Image::ExifTool::ASF;   # for GetGUID()

$VERSION = '1.05';

sub ProcessFPX($$);
sub ProcessFPXR($$$);
sub ProcessProperties($$$);
sub ReadFPXValue($$$$$;$);
sub ConvertTimeSpan($);
sub ProcessHyperlinks($$);

# sector type constants
sub HDR_SIZE           () { 512; }
sub DIF_SECT           () { 0xfffffffc; }
sub FAT_SECT           () { 0xfffffffd; }
sub END_OF_CHAIN       () { 0xfffffffe; }
sub FREE_SECT          () { 0xffffffff; }

# format flags
sub VT_VECTOR          () { 0x1000; }
sub VT_ARRAY           () { 0x2000; }
sub VT_BYREF           () { 0x4000; }
sub VT_RESERVED        () { 0x8000; }

# other constants
sub VT_VARIANT         () { 12; }
sub VT_LPSTR           () { 30; }

# list of OLE format codes (unsupported codes commented out)
my %oleFormat = (
    0  => undef,        # VT_EMPTY
    1  => undef,        # VT_NULL
    2  => 'int16s',     # VT_I2
    3  => 'int32s',     # VT_I4
    4  => 'float',      # VT_R4
    5  => 'double',     # VT_R8
    6  => undef,        # VT_CY
    7  => 'VT_DATE',    # VT_DATE (double, number of days since Dec 30, 1899)
    8  => 'VT_BSTR',    # VT_BSTR (int32u count, followed by binary string)
#   9  => 'VT_DISPATCH',
    10 => 'int32s',     # VT_ERROR
    11 => 'int16s',     # VT_BOOL
    12 => 'VT_VARIANT', # VT_VARIANT
#   13 => 'VT_UNKNOWN',
#   14 => 'VT_DECIMAL',
    16 => 'int8s',      # VT_I1
    17 => 'int8u',      # VT_UI1
    18 => 'int16u',     # VT_UI2
    19 => 'int32u',     # VT_UI4
    20 => 'int64s',     # VT_I8
    21 => 'int64u',     # VT_UI8
#   22 => 'VT_INT',
#   23 => 'VT_UINT',
#   24 => 'VT_VOID',
#   25 => 'VT_HRESULT',
#   26 => 'VT_PTR',
#   27 => 'VT_SAFEARRAY',
#   28 => 'VT_CARRAY',
#   29 => 'VT_USERDEFINED',
    30 => 'VT_LPSTR',   # VT_LPSTR (int32u count, followed by string)
    31 => 'VT_LPWSTR',  # VT_LPWSTR (int32u word count, followed by Unicode string)
    64 => 'VT_FILETIME',# VT_FILETIME (int64u, number of nanoseconds since Jan 1, 1601)
    65 => 'VT_BLOB',    # VT_BLOB
#   66 => 'VT_STREAM',
#   67 => 'VT_STORAGE',
#   68 => 'VT_STREAMED_OBJECT',
#   69 => 'VT_STORED_OBJECT',
#   70 => 'VT_BLOB_OBJECT',
    71 => 'VT_CF',      # VT_CF
    72 => 'VT_CLSID',   # VT_CLSID
);

# OLE flag codes (high nibble of property type)
my %oleFlags = (
    0x1000 => 'VT_VECTOR',
    0x2000 => 'VT_ARRAY',   # not yet supported
    0x4000 => 'VT_BYREF',   # ditto
    0x8000 => 'VT_RESERVED',
);

# byte sizes for supported VT_* format and flag types
my %oleFormatSize = (
    VT_DATE     => 8,
    VT_BSTR     => 4,   # (+ string length)
    VT_VARIANT  => 4,   # (+ data length)
    VT_LPSTR    => 4,   # (+ string length)
    VT_LPWSTR   => 4,   # (+ string character length)
    VT_FILETIME => 8,
    VT_BLOB     => 4,   # (+ data length)
    VT_CF       => 4,   # (+ data length)
    VT_CLSID    => 16,
    VT_VECTOR   => 4,   # (+ vector elements)
);

# names for each type of directory entry
my @dirEntryType = qw(INVALID STORAGE STREAM LOCKBYTES PROPERTY ROOT);

%Image::ExifTool::FlashPix::Main = (
    PROCESS_PROC => \&ProcessFPXR,
    GROUPS => { 2 => 'Image' },
    NOTES => q{
        The FlashPix file format, introduced in 1996, was developed by Kodak,
        Hewlett-Packard and Microsoft.  Internally the FPX file structure mimics
        that of an old DOS disk with fixed-sized "sectors" (usually 512 bytes) and a
        "file allocation table" (FAT).  No wonder the format never became popular.

        However, some of the structures used in FlashPix streams are part of the
        EXIF specification, and are still being used in the APP2 FPXR segment of
        JPEG images by some Kodak and Hewlett-Packard digital cameras.

        ExifTool extracts FlashPix information from both FPX images and the APP2
        FPXR segment of JPEG images.  As well, FlashPix information is extracted
        from DOC, XLS and PPT (Microsoft Word, Excel and PowerPoint) documents since
        the FlashPix file format is closely related to the formats of these files.
    },
    "\x05SummaryInformation" => {
        Name => 'SummaryInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::SummaryInfo',
        },
    },
    "\x05DocumentSummaryInformation" => {
        Name => 'DocumentInfo',
        Multi => 1, # flag to process UserDefined information after this
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::DocumentInfo',
        },
    },
    "\x01CompObj" => {
        Name => 'CompObj',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::CompObj',
            DirStart => 0x1c,   # skip stream header
        },
    },
    "\x05Image Info" => {
        Name => 'ImageInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::ImageInfo',
        },
    },
    "\x05Image Contents" => {
        Name => 'Image',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::Image',
        },
    },
    "ICC Profile 0001" => {
        Name => 'ICC_Profile',
        SubDirectory => {
            TagTable => 'Image::ExifTool::ICC_Profile::Main',
            DirStart => 0x1c,   # skip stream header
        },
    },
    "\x05Extension List" => {
        Name => 'Extensions',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::Extensions',
        },
    },
    'Subimage 0000 Header' => {
        Name => 'SubimageHdr',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::SubimageHdr',
            DirStart => 0x1c,   # skip stream header
        },
    },
#   'Subimage 0000 Data'
    "\x05Data Object" => {  # plus instance number (ie. " 000000")
        Name => 'DataObject',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::DataObject',
        },
    },
#   "\x05Data Object Store" => { # plus instance number (ie. " 000000")
    "\x05Transform" => {    # plus instance number (ie. " 000000")
        Name => 'Transform',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::Transform',
        },
    },
    "\x05Operation" => {    # plus instance number (ie. " 000000")
        Name => 'Operation',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::Operation',
        },
    },
    "\x05Global Info" => {
        Name => 'GlobalInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::GlobalInfo',
        },
    },
    "\x05Screen Nail" => { # plus class ID (ie. "_bd0100609719a180")
        Name => 'ScreenNail',
        Groups => { 2 => 'Other' },
        # strip off stream header
        ValueConv => 'length($val) > 0x1c and $val = substr($val, 0x1c); \$val',
    },
    "\x05Audio Info" => {
        Name => 'AudioInfo',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FlashPix::AudioInfo',
        },
    },
    'Audio Stream' => { # plus instance number (ie. " 000000")
        Name => 'AudioStream',
        Groups => { 2 => 'Audio' },
        # strip off stream header
        ValueConv => 'length($val) > 0x1c and $val = substr($val, 0x1c); \$val',
    },
    "Current User" => { #PH
        Name => 'CurrentUser',
        # not sure what the rest of this data is, but extract ASCII name from it - PH
        ValueConv => q{
            return undef if length $val < 12;
            my ($size,$pos) = unpack('x4VV', $val);
            my $len = $size - $pos - 4;
            return undef if $len < 0 or length $val < $size + 8;
            return substr($val, 8 + $pos, $len);
        },
    },
);

# Summary Information properties
%Image::ExifTool::FlashPix::SummaryInfo = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Image' },
    NOTES => q{
        The Dictionary, CodePage and LocalIndicator tags are common to all FlashPix
        property tables, even though they are only listed in the SummaryInfo table.
    },
    0x00 => { Name => 'Dictionary', Groups => { 2 => 'Other' }, Binary => 1 },
    0x01 => { Name => 'CodePage',   Groups => { 2 => 'Other' } },
    0x02 => 'Title',
    0x03 => 'Subject',
    0x04 => { Name => 'Author',     Groups => { 2 => 'Author' } },
    0x05 => 'Keywords',
    0x06 => 'Comments',
    0x07 => 'Template',
    0x08 => { Name => 'LastSavedBy',Groups => { 2 => 'Author' } },
    0x09 => 'RevisionNumber',
    0x0a => { Name => 'TotalEditTime', PrintConv => \&ConvertTimeSpan },
    0x0b => 'LastPrinted',
    0x0c => { Name => 'CreateDate', Groups => { 2 => 'Time' } },
    0x0d => { Name => 'ModifyDate', Groups => { 2 => 'Time' } },
    0x0e => 'PageCount',
    0x0f => 'WordCount',
    0x10 => 'CharCount',
    0x11 => { Name => 'ThumbnailClip', Binary => 1 },
    0x12 => 'Software',
    0x13 => 'Security',
    0x80000000 => { Name => 'LocaleIndicator', Groups => { 2 => 'Other' } },
);

# Document Summary Information properties (ref 4)
%Image::ExifTool::FlashPix::DocumentInfo = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Document' },
    NOTES => q{
        The DocumentSummaryInformation property set includes a UserDefined property
        set for which only the Hyperlinks and HyperlinkBase tags are pre-defined. 
        However, ExifTool will also extract any other information found in the
        UserDefined properties.
    },
    0x02 => 'Category',
    0x03 => 'PresentationTarget',
    0x04 => 'Bytes',
    0x05 => 'Lines',
    0x06 => 'Paragraphs',
    0x07 => 'Slides',
    0x08 => 'Notes',
    0x09 => 'HiddenSlides',
    0x0a => 'MMClips',
    0x0b => 'ScaleCrop',
    0x0c => 'HeadingPairs',
    0x0d => 'TitleOfParts',
    0x0e => 'Manager',
    0x0f => 'Company',
    0x10 => 'LinksUpToDate',
    0x11 => 'CharCountWithSpaces',
  # 0x12 ?
    0x13 => 'SharedDoc', #PH (unconfirmed)
  # 0x14 ?
  # 0x15 ?
    0x16 => 'HyperlinksChanged',
    0x17 => { #PH (unconfirmed)
        Name => 'AppVersion',
        # (not sure what the lower 16 bits mean, so print them in hex inside brackets)
        ValueConv => 'sprintf("%d (%.4x)",$val >> 16, $val & 0xffff)',
    },
   '_PID_LINKBASE' => 'HyperlinkBase',
   '_PID_HLINKS' => {
        Name => 'Hyperlinks',
        RawConv => \&ProcessHyperlinks,
    },
);

# Image Information properties
%Image::ExifTool::FlashPix::ImageInfo = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Image' },
    0x21000000 => {
        Name => 'FileSource',
        PrintConv => {
            1 => 'Film Scanner',
            2 => 'Reflection Print Scanner',
            3 => 'Digital Camera',
            4 => 'Video Capture',
            5 => 'Computer Graphics',
        },
    },
    0x21000001 => {
        Name => 'SceneType',
        PrintConv => {
            1 => 'Original Scene',
            2 => 'Second Generation Scene',
            3 => 'Digital Scene Generation',
        },
    },
    0x21000002 => 'CreationPathVector',
    0x21000003 => 'SoftwareRelease',
    0x21000004 => 'UserDefinedID',
    0x21000005 => 'SharpnessApproximation',
    0x22000000 => { Name => 'Copyright',                 Groups => { 2 => 'Author' } },
    0x22000001 => { Name => 'OriginalImageBroker',       Groups => { 2 => 'Author' } },
    0x22000002 => { Name => 'DigitalImageBroker',        Groups => { 2 => 'Author' } },
    0x22000003 => { Name => 'Authorship',                Groups => { 2 => 'Author' } },
    0x22000004 => { Name => 'IntellectualPropertyNotes', Groups => { 2 => 'Author' } },
    0x23000000 => {
        Name => 'TestTarget',
        PrintConv => {
            1 => 'Color Chart',
            2 => 'Gray Card',
            3 => 'Grayscale',
            4 => 'Resolution Chart',
            5 => 'Inch Scale',
            6 => 'Centimeter Scale',
            7 => 'Millimeter Scale',
            8 => 'Micrometer Scale',
        },
    },
    0x23000002 => 'GroupCaption',
    0x23000003 => 'CaptionText',
    0x23000004 => 'People',
    0x23000007 => 'Things',
    0x2300000A => { Name => 'DateTimeOriginal', Groups => { 2 => 'Time' } },
    0x2300000B => 'Events',
    0x2300000C => 'Places',
    0x2300000F => 'ContentDescriptionNotes',
    0x24000000 => { Name => 'Make',             Groups => { 2 => 'Camera' } },
    0x24000001 => {
        Name => 'Model',
        Description => 'Camera Model Name',
        Groups => { 2 => 'Camera' },
    },
    0x24000002 => { Name => 'SerialNumber',     Groups => { 2 => 'Camera' } },
    0x25000000 => { Name => 'CreateDate',       Groups => { 2 => 'Time' } },
    0x25000001 => {
        Name => 'ExposureTime',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x25000002 => {
        Name => 'FNumber',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x25000003 => {
        Name => 'ExposureProgram',
        Groups => { 2 => 'Camera' },
        # use PrintConv of corresponding EXIF tag
        PrintConv => $Image::ExifTool::Exif::Main{0x8822}->{PrintConv},
    },
    0x25000004 => 'BrightnessValue',
    0x25000005 => 'ExposureCompensation',
    0x25000006 => {
        Name => 'SubjectDistance',
        Groups => { 2 => 'Camera' },
        PrintConv => 'sprintf("%.3f m", $val)',
    },
    0x25000007 => {
        Name => 'MeteringMode',
        Groups => { 2 => 'Camera' },
        PrintConv => $Image::ExifTool::Exif::Main{0x9207}->{PrintConv},
    },
    0x25000008 => {
        Name => 'LightSource',
        Groups => { 2 => 'Camera' },
        PrintConv => $Image::ExifTool::Exif::Main{0x9208}->{PrintConv},
    },
    0x25000009 => {
        Name => 'FocalLength',
        Groups => { 2 => 'Camera' },
        PrintConv => 'sprintf("%.1f mm",$val)',
    },
    0x2500000A => {
        Name => 'MaxApertureValue',
        Groups => { 2 => 'Camera' },
        ValueConv => '2 ** ($val / 2)',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x2500000B => {
        Name => 'Flash',
        Groups => { 2 => 'Camera' },
        PrintConv => {
            1 => 'No Flash',
            2 => 'Flash Fired',
        },
    },
    0x2500000C => {
        Name => 'FlashEnergy',
        Groups => { 2 => 'Camera' },
    },
    0x2500000D => {
        Name => 'FlashReturn',
        Groups => { 2 => 'Camera' },
        PrintConv => {
            1 => 'Subject Outside Flash Range',
            2 => 'Subject Inside Flash Range',
        },
    },
    0x2500000E => {
        Name => 'BackLight',
        PrintConv => {
            1 => 'Front Lit',
            2 => 'Back Lit 1',
            3 => 'Back Lit 2',
        },
    },
    0x2500000F => { Name => 'SubjectLocation', Groups => { 2 => 'Camera' } },
    0x25000010 => 'ExposureIndex',
    0x25000011 => {
        Name => 'SpecialEffectsOpticalFilter',
        PrintConv => {
            1 => 'None',
            2 => 'Colored',
            3 => 'Diffusion',
            4 => 'Multi-image',
            5 => 'Polarizing',
            6 => 'Split-field',
            7 => 'Star',
        },
    },
    0x25000012 => 'PerPictureNotes',
    0x26000000 => {
        Name => 'SensingMethod',
        Groups => { 2 => 'Camera' },
        PrintConv => $Image::ExifTool::Exif::Main{0x9217}->{PrintConv},
    },
    0x26000001 => { Name => 'FocalPlaneXResolution', Groups => { 2 => 'Camera' } },
    0x26000002 => { Name => 'FocalPlaneYResolution', Groups => { 2 => 'Camera' } },
    0x26000003 => {
        Name => 'FocalPlaneResolutionUnit',
        Groups => { 2 => 'Camera' },
        PrintConv => $Image::ExifTool::Exif::Main{0xa210}->{PrintConv},
    },
    0x26000004 => 'SpatialFrequencyResponse',
    0x26000005 => 'CFAPattern',
    0x27000001 => {
        Name => 'FilmCategory',
        PrintConv => {
            1 => 'Negative B&W',
            2 => 'Negative Color',
            3 => 'Reversal B&W',
            4 => 'Reversal Color',
            5 => 'Chromagenic',
            6 => 'Internegative B&W',
            7 => 'Internegative Color',
        },
    },
    0x26000007 => 'ISO',
    0x26000008 => 'Opto-ElectricConvFactor',
    0x27000000 => 'FilmBrand',
    0x27000001 => 'FilmCategory',
    0x27000002 => 'FilmSize',
    0x27000003 => 'FilmRollNumber',
    0x27000004 => 'FilmFrameNumber',
    0x29000000 => 'OriginalScannedImageSize',
    0x29000001 => 'OriginalDocumentSize',
    0x29000002 => {
        Name => 'OriginalMedium',
        PrintConv => {
            1 => 'Continuous Tone Image',
            2 => 'Halftone Image',
            3 => 'Line Art',
        },
    },
    0x29000003 => {
        Name => 'TypeOfOriginal',
        PrintConv => {
            1 => 'B&W Print',
            2 => 'Color Print',
            3 => 'B&W Document',
            4 => 'Color Document',
        },
    },
    0x28000000 => 'ScannerMake',
    0x28000001 => 'ScannerModel',
    0x28000002 => 'ScannerSerialNumber',
    0x28000003 => 'ScanSoftware',
    0x28000004 => { Name => 'ScanSoftwareRevisionDate', Groups => { 2 => 'Time' } },
    0x28000005 => 'ServiceOrganizationName',
    0x28000006 => 'ScanOperatorID',
    0x28000008 => { Name => 'ScanDate',   Groups => { 2 => 'Time' } },
    0x28000009 => { Name => 'ModifyDate', Groups => { 2 => 'Time' } },
    0x2800000A => 'ScannerPixelSize',
);

# Image Contents properties
%Image::ExifTool::FlashPix::Image = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Image' },
    # VARS storage is used as a hash lookup for tagID's which aren't constant.
    # The key is a mask for significant bits of the tagID, and the value
    # is a lookup for tagID's for which this mask is valid.
    VARS => {
        # ID's are different for each subimage
        0xff00ffff => {
            0x02000000=>1, 0x02000001=>1, 0x02000002=>1, 0x02000003=>1,
            0x02000004=>1, 0x02000005=>1, 0x02000006=>1, 0x02000007=>1,
            0x03000001=>1,
        },
    },
    0x01000000 => 'NumberOfResolutions',
    0x01000002 => 'ImageWidth',     # width of highest resolution image
    0x01000003 => 'ImageHeight',
    0x01000004 => 'DefaultDisplayHeight',
    0x01000005 => 'DefaultDisplayWidth',
    0x01000006 => {
        Name => 'DisplayUnits',
        PrintConv => {
            0 => 'inches',
            1 => 'meters',
            2 => 'cm',
            3 => 'mm',
        },
    },
    0x02000000 => 'SubimageWidth',
    0x02000001 => 'SubimageHeight',
    0x02000002 => {
        Name => 'SubimageColor',
        # decode only component count and color space of first component
        ValueConv => 'sprintf("%.2x %.4x", unpack("x4vx4v",$val))',
        PrintConv => {
            '01 0000' => 'Opacity Only',
            '01 8000' => 'Opacity Only (uncalibrated)',
            '01 0001' => 'Monochrome',
            '01 8001' => 'Monochrome (uncalibrated)',
            '03 0002' => 'YCbCr',
            '03 8002' => 'YCbCr (uncalibrated)',
            '03 0003' => 'RGB',
            '03 8003' => 'RGB (uncalibrated)',
            '04 0002' => 'YCbCr with Opacity',
            '04 8002' => 'YCbCr with Opacity (uncalibrated)',
            '04 0003' => 'RGB with Opacity',
            '04 8003' => 'RGB with Opacity (uncalibrated)',
        },
    },
    0x02000003 => {
        Name => 'SubimageNumericalFormat',
        PrintConv => {
            17 => '8-bit, Unsigned',
            18 => '16-bit, Unsigned',
            19 => '32-bit, Unsigned',
        },
    },
    0x02000004 => {
        Name => 'DecimationMethod',
        PrintConv => {
            0 => 'None (Full-sized Image)',
            8 => '8-point Prefilter',
        },
    },
    0x02000005 => 'DecimationPrefilterWidth',
    0x02000007 => 'SubimageICC_Profile',
    0x03000001 => { Name => 'JPEGTables', Binary => 1 },
    0x03000002 => 'MaxJPEGTableIndex',
);

# Extension List properties
%Image::ExifTool::FlashPix::Extensions = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Other' },
    VARS => {
        # ID's are different for each extension type
        0x0000ffff => {
            0x0001=>1, 0x0002=>1, 0x0003=>1, 0x0004=>1,
            0x0005=>1, 0x0006=>1, 0x0007=>1, 0x1000=>1,
            0x2000=>1, 0x2001=>1, 0x3000=>1, 0x4000=>1,
        },
        0x0000f00f => { 0x3001=>1, 0x3002=>1 },
    },
    0x10000000 => 'UsedExtensionNumbers',
    0x0001 => 'ExtensionName',
    0x0002 => 'ExtensionClassID',
    0x0003 => {
        Name => 'ExtensionPersistence',
        PrintConv => {
            0 => 'Always Valid',
            1 => 'Invalidated By Modification',
            2 => 'Potentially Invalidated By Modification',
        },
    },
    0x0004 => { Name => 'ExtensionCreateDate', Groups => { 2 => 'Time' } },
    0x0005 => { Name => 'ExtensionModifyDate', Groups => { 2 => 'Time' } },
    0x0006 => 'CreatingApplication',
    0x0007 => 'ExtensionDescription',
    0x1000 => 'Storage-StreamPathname',
    0x2000 => 'FlashPixStreamPathname',
    0x2001 => 'FlashPixStreamFieldOffset',
    0x3000 => 'PropertySetPathname',
    0x3001 => 'PropertySetIDCodes',
    0x3002 => 'PropertyVectorElements',
    0x4000 => 'SubimageResolutions',
);

# Subimage Header tags
%Image::ExifTool::FlashPix::SubimageHdr = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    FORMAT => 'int32u',
#   0 => 'HeaderLength',
    1 => 'SubimageWidth',
    2 => 'SubimageHeight',
    3 => 'SubimageTileCount',
    4 => 'SubimageTileWidth',
    5 => 'SubimageTileHeight',
    6 => 'NumChannels',
#   7 => 'TileHeaderOffset',
#   8 => 'TileHeaderLength',
    # ... followed by tile header table
);

# Data Object properties
%Image::ExifTool::FlashPix::DataObject = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Other' },
    0x00010000 => 'DataObjectID',
    0x00010002 => 'LockedPropertyList',
    0x00010003 => 'DataObjectTitle',
    0x00010004 => 'LastModifier',
    0x00010005 => 'RevisionNumber',
    0x00010006 => { Name => 'DataCreateDate', Groups => { 2 => 'Time' } },
    0x00010007 => { Name => 'DataModifyDate', Groups => { 2 => 'Time' } },
    0x00010008 => 'CreatingApplication',
    0x00010100 => {
        Name => 'DataObjectStatus',
        PrintConv => q{
            ($val & 0x0000ffff ? 'Exists' : 'Does Not Exist') .
            ', ' . ($val & 0xffff0000 ? 'Not ' : '') . 'Purgeable'
        },
    },
    0x00010101 => {
        Name => 'CreatingTransform',
        PrintConv => '$val ? $val :  "Source Image"',
    },
    0x00010102 => 'UsingTransforms',
    0x10000000 => 'CachedImageHeight',
    0x10000001 => 'CachedImageWidth',
);

# Transform properties
%Image::ExifTool::FlashPix::Transform = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Other' },
    0x00010000 => 'TransformNodeID',
    0x00010001 => 'OperationClassID',
    0x00010002 => 'LockedPropertyList',
    0x00010003 => 'TransformTitle',
    0x00010004 => 'LastModifier',
    0x00010005 => 'RevisionNumber',
    0x00010006 => { Name => 'TransformCreateDate', Groups => { 2 => 'Time' } },
    0x00010007 => { Name => 'TransformModifyDate', Groups => { 2 => 'Time' } },
    0x00010008 => 'CreatingApplication',
    0x00010100 => 'InputDataObjectList',
    0x00010101 => 'OutputDataObjectList',
    0x00010102 => 'OperationNumber',
    0x10000000 => 'ResultAspectRatio',
    0x10000001 => 'RectangleOfInterest',
    0x10000002 => 'Filtering',
    0x10000003 => 'SpatialOrientation',
    0x10000004 => 'ColorTwistMatrix',
    0x10000005 => 'ContrastAdjustment',
);

# Operation properties
%Image::ExifTool::FlashPix::Operation = (
    PROCESS_PROC => \&ProcessProperties,
    0x00010000 => 'OperationID',
);

# Global Info properties
%Image::ExifTool::FlashPix::GlobalInfo = (
    PROCESS_PROC => \&ProcessProperties,
    0x00010002 => 'LockedPropertyList',
    0x00010003 => 'TransformedImageTitle',
    0x00010004 => 'LastModifier',
    0x00010100 => 'VisibleOutputs',
    0x00010101 => 'MaximumImageIndex',
    0x00010102 => 'MaximumTransformIndex',
    0x00010103 => 'MaximumOperationIndex',
);

# Audio Info properties
%Image::ExifTool::FlashPix::AudioInfo = (
    PROCESS_PROC => \&ProcessProperties,
    GROUPS => { 2 => 'Audio' },
);

# CompObj tags
%Image::ExifTool::FlashPix::CompObj = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Other' },
    FORMAT => 'int32u',
    0 => { Name => 'CompObjUserTypeLen' },
    1 => { Name => 'CompObjUserType', Format => 'string[$val{0}]' },
);

# composite FlashPix tags
%Image::ExifTool::FlashPix::Composite = (
    GROUPS => { 2 => 'Image' },
    PreviewImage => {
        # extract JPEG preview from ScreenNail if possible
        Require => {
            0 => 'ScreenNail',
        },
        Binary => 1,
        RawConv => q{
            return undef unless $val[0] =~ /\xff\xd8\xff/g;
            return substr($val[0], pos($val[0])-3);
        },
    },
);

# add our composite tags
Image::ExifTool::AddCompositeTags('Image::ExifTool::FlashPix');

#------------------------------------------------------------------------------
# Process hyperlinks from PID_HYPERLINKS array
# (ref http://msdn.microsoft.com/archive/default.asp?url=/archive/en-us/dnaro97ta/html/msdn_hyper97.asp)
# Inputs: 0) value, 1) ExifTool ref
# Returns: list of hyperlinks
sub ProcessHyperlinks($$)
{
    my ($val, $exifTool) = @_;

    # process as an array of VT_VARIANT's
    my $dirEnd = length $val;
    return undef if $dirEnd < 4;
    my $num = Get32u(\$val, 0);
    my $valPos = 4;
    my ($i, @vals);
    for ($i=0; $i<$num; ++$i) {
        # read VT_BLOB entries as an array of VT_VARIANT's
        my $value = ReadFPXValue($exifTool, \$val, $valPos, VT_VARIANT, $dirEnd);
        last unless defined $value;
        push @vals, $value;
    }
    # filter values to extract only the links
    my @links;
    for ($i=0; $i<@vals; $i+=6) {
        push @links, $vals[$i+4];    # get address
        $links[-1] .= '#' . $vals[$i+5] if length $vals[$i+5]; # add subaddress
    }
    return \@links;
}

#------------------------------------------------------------------------------
# Print conversion for time span value
sub ConvertTimeSpan($)
{
    my $val = shift;
    if (Image::ExifTool::IsFloat($val) and $val != 0) {
        if ($val < 60) {
            $val = "$val seconds";
        } elsif ($val < 3600) {
            $val = sprintf("%.1f minutes", $val / 60);
        } elsif ($val < 24 * 3600) {
            $val = sprintf("%.1f hours", $val / 3600);
        } else {
            $val = sprintf("%.1f days", $val / (24 * 3600));
        }
    }
    return $val;
}

#------------------------------------------------------------------------------
# Read FlashPix value
# Inputs: 0) ExifTool ref, 1) data ref, 2) value offset, 3) FPX format number,
#         4) end offset, 5) options: 0x01=no padding, 0x02=translate to UTF8
# Returns: converted value (or list of values in list context) and updates
#          value offset to end of value if successful, or returns undef on error
sub ReadFPXValue($$$$$;$)
{
    my ($exifTool, $dataPt, $valPos, $type, $dirEnd, $opts) = @_;
    $opts = 0 unless defined $opts;
    my @vals;

    my $format = $oleFormat{$type & 0x0fff};
    while ($format) {
        my $count = 1;
        # handle VT_VECTOR types
        my $flags = $type & 0xf000;
        if ($flags) {
            if ($flags == VT_VECTOR) {
                $opts |= 0x01;  # values don't seem to be padded inside vectors
                my $size = $oleFormatSize{VT_VECTOR};
                last if $valPos + $size > $dirEnd;
                $count = Get32u($dataPt, $valPos);
                push @vals, '' if $count == 0;  # allow zero-element vector
                $valPos += 4;
            } else {
                # can't yet handle this property flag
                last;
            }
        }
        unless ($format =~ /^VT_/) {
            my $size = Image::ExifTool::FormatSize($format) * $count;
            last if $valPos + $size > $dirEnd;
            @vals = ReadValue($dataPt, $valPos, $format, $count, $size);
            # update position to end of value plus padding
            $valPos += ($count * $size + 3) & 0xfffffffc;
            last;
        }
        my $size = $oleFormatSize{$format};
        my ($item, $val);
        for ($item=0; $item<$count; ++$item) {
            last if $valPos + $size > $dirEnd;
            if ($format eq 'VT_VARIANT') {
                my $subType = Get32u($dataPt, $valPos);
                $valPos += $size;
                $val = ReadFPXValue($exifTool, $dataPt, $valPos, $subType, $dirEnd, $opts);
                last unless defined $val;
                push @vals, $val;
                next;   # avoid adding $size to $valPos again
            } elsif ($format eq 'VT_FILETIME') {
                # get time in seconds
                $val = 1e-7 * Image::ExifTool::Get64u($dataPt, $valPos);
                # print as date/time if value is greater than one year (PH hack)
                if ($val > 365 * 24 * 3600) {
                    # shift from Jan 1, 1601 to Jan 1, 1970
                    $val -= 134774 * 24 * 3600 if $val != 0;
                    $val = Image::ExifTool::ConvertUnixTime($val);
                }
            } elsif ($format eq 'VT_DATE') {
                $val = Image::ExifTool::GetDouble($dataPt, $valPos);
                # shift zero from Dec 30, 1899 to Jan 1, 1970 and convert to secs
                $val = ($val - 25569) * 24 * 3600 if $val != 0;
                $val = Image::ExifTool::ConvertUnixTime($val);
            } elsif ($format =~ /STR$/) {
                my $len = Get32u($dataPt, $valPos);
                $len *= 2 if $format eq 'VT_LPWSTR';    # convert to byte count
                last if $valPos + $len + 4 > $dirEnd;
                $val = substr($$dataPt, $valPos + 4, $len);
                if ($format eq 'VT_LPWSTR') {
                    # convert wide string from Unicode
                    $val = $exifTool->Unicode2Charset($val);
                } elsif ($opts & 0x02) {
                    # convert from Latin1 to UTF-8
                    $val = Image::ExifTool::Latin2Unicode($val,'v');
                    $val = Image::ExifTool::Unicode2UTF8($val,'v');
                }
                $val =~ s/\0.*//s;  # truncate at null terminator
                # update position for string length
                # (the spec states that strings should be padded to align
                #  on even 32-bit boundaries, but this isn't always the case)
                $valPos += ($opts & 0x01) ? $len : ($len + 3) & 0xfffffffc;
            } elsif ($format eq 'VT_BLOB' or $format eq 'VT_CF') {
                my $len = Get32u($dataPt, $valPos);
                last if $valPos + $len + 4 > $dirEnd;
                $val = substr($$dataPt, $valPos + 4, $len);
                # update position for data length plus padding
                # (does this padding disappear in arrays too?)
                $valPos += ($len + 3) & 0xfffffffc;
            } elsif ($format eq 'VT_CLSID') {
                $val = Image::ExifTool::ASF::GetGUID(substr($$dataPt, $valPos, $size));
            }
            $valPos += $size;   # update value pointer to end of value
            push @vals, $val;
        }
        # join VT_ values with commas unless we want an array
        @vals = ( join ', ', @vals ) if @vals > 1 and not wantarray;
        last;   # didn't really want to loop
    }
    $_[2] = $valPos;    # return updated value position

    if (wantarray) {
        return @vals;
    } elsif (@vals > 1) {
        return join(' ', @vals);
    } else {
        return $vals[0];
    }
}

#------------------------------------------------------------------------------
# Check FPX byte order mark (BOM) and set byte order appropriately
# Inputs: 0) data ref, 1) offset to BOM
# Returns: true on success
sub CheckBOM($$)
{
    my ($dataPt, $pos) = @_;
    my $bom = Get16u($dataPt, $pos);
    return 1 if $bom == 0xfffe;
    return 0 unless $bom == 0xfeff;
    ToggleByteOrder();
    return 1;
}

#------------------------------------------------------------------------------
# Process FlashPix properties
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success
sub ProcessProperties($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $pos = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen} || length($$dataPt) - $pos;
    my $dirEnd = $pos + $dirLen;
    my $verbose = $exifTool->Options('Verbose');
    my ($out, $n);

    if ($dirLen < 48) {
        $exifTool->Warn('Truncated FPX properties');
        return 0;
    }
    # check and set our byte order if necessary
    unless (CheckBOM($dataPt, $pos)) {
        $exifTool->Warn('Bad FPX property byte order mark');
        return 0;
    }
    # get position of start of section
    $pos = Get32u($dataPt, $pos + 44);
    if ($pos < 48) {
        $exifTool->Warn('Bad FPX property section offset');
        return 0;
    }
    for ($n=0; $n<2; ++$n) {
        my %dictionary;     # dictionary to translate user-defined properties
        my $opts = 0;       # option flags for converting values
        last if $pos + 8 > $dirEnd;
        # read property section header
        my $size = Get32u($dataPt, $pos);
        last unless $size;
        my $numEntries = Get32u($dataPt, $pos + 4);
        $verbose and $exifTool->VerboseDir('Property Info', $numEntries, $size);
        if ($pos + 8 + 8 * $numEntries > $dirEnd) {
            $exifTool->Warn('Truncated property list');
            last;
        }
        my $index;
        for ($index=0; $index<$numEntries; ++$index) {
            my $entry = $pos + 8 + 8 * $index;
            my $tag = Get32u($dataPt, $entry);
            my $offset = Get32u($dataPt, $entry + 4);
            my $valStart = $pos + 4 + $offset;
            last if $valStart >= $dirEnd;
            my $valPos = $valStart;
            my $type = Get32u($dataPt, $pos + $offset);
            if ($tag == 0) {
                # read dictionary to get tag name lookup for this property set
                my $i;
                for ($i=0; $i<$type; ++$i) {
                    last if $valPos + 8 > $dirEnd;
                    $tag = Get32u($dataPt, $valPos);
                    my $len = Get32u($dataPt, $valPos + 4);
                    $valPos += 8 + $len;
                    last if $valPos > $dirEnd;
                    my $name = substr($$dataPt, $valPos - $len, $len);
                    $name =~ s/\0.*//s;
                    next unless length $name;
                    $dictionary{$tag} = $name;
                    next if $$tagTablePtr{$name};
                    $tag = $name;
                    $name =~ tr/a-zA-Z0-9//dc;
                    next unless length $name;
                    Image::ExifTool::AddTagToTable($tagTablePtr, $tag, { Name => ucfirst($name) });
                }
                next;
            }
            # use tag name from dictionary if available
            my ($custom, $val);
            if (defined $dictionary{$tag}) {
                $tag = $dictionary{$tag};
                $custom = 1;
            }
            my @vals = ReadFPXValue($exifTool, $dataPt, $valPos, $type, $dirEnd, $opts);
            @vals or $exifTool->Warn('Error reading property value');
            $val = @vals > 1 ? \@vals : $vals[0];
            my $format = $type & 0x0fff;
            my $flags = $type & 0xf000;
            my $formStr = $oleFormat{$format} || "Type $format";
            $formStr .= '|' . ($oleFlags{$flags} || sprintf("0x%x",$flags)) if $flags;
            my $tagInfo;
            # check for common tag ID's: Dictionary, CodePage and LocaleIndicator
            # (must be done before masking because masked tags may overlap these ID's)
            if (not $custom and ($tag == 1 or $tag == 0x80000000)) {
                # get tagInfo from SummaryInfo table
                my $summaryTable = GetTagTable('Image::ExifTool::FlashPix::SummaryInfo');
                $tagInfo = $exifTool->GetTagInfo($summaryTable, $tag);
                if ($tag == 1 and $val == 1252 and $exifTool->Options('Charset') eq 'UTF8') {
                    # set flag to translate 8-bit text only if
                    # code page is cp1252 and Charset is UTF8
                    $opts |= 0x02;
                }
            } elsif ($$tagTablePtr{$tag}) {
                $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
            } elsif ($$tagTablePtr{VARS} and not $custom) {
                # mask off insignificant bits of tag ID if necessary
                my $masked = $$tagTablePtr{VARS};
                my $mask;
                foreach $mask (keys %$masked) {
                    if ($masked->{$mask}->{$tag & $mask}) {
                        $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag & $mask);
                        last;
                    }
                }
            }
            $exifTool->HandleTag($tagTablePtr, $tag, $val,
                DataPt => $dataPt,
                Start => $valStart,
                Size => $valPos - $valStart,
                Format => $formStr,
                Index => $index,
                TagInfo => $tagInfo,
                Extra => ", type=$type",
            );
        }
        # issue warning if we hit end of property section prematurely
        $exifTool->Warn('Truncated property data') if $index < $numEntries;
        last unless $$dirInfo{Multi};
        $pos += $size;
    }

    return 1;
}

#------------------------------------------------------------------------------
# Load chain of sectors from file
# Inputs: 0) RAF ref, 1) first sector number, 2) FAT ref, 3) sector size, 4) header size
sub LoadChain($$$$$)
{
    my ($raf, $sect, $fatPt, $sectSize, $hdrSize) = @_;
    return undef unless $raf;
    my $chain = '';
    my ($buff, %loadedSect);
    for (;;) {
        last if $sect == END_OF_CHAIN;
        return undef if $loadedSect{$sect}; # avoid infinite loop
        $loadedSect{$sect} = 1;
        my $offset = $sect * $sectSize + $hdrSize;
        return undef unless $offset <= 0x7fffffff and
                            $raf->Seek($offset, 0) and
                            $raf->Read($buff, $sectSize) == $sectSize;
        $chain .= $buff;
        # step to next sector in chain
        return undef if $sect * 4 > length($$fatPt) - 4;
        $sect = Get32u($fatPt, $sect * 4);
    }
    return $chain;
}

#------------------------------------------------------------------------------
# Extract information from a JPEG APP2 FPXR segment
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success
sub ProcessFPXR($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dirStart = $$dirInfo{DirStart};
    my $dirLen = $$dirInfo{DirLen};
    my $verbose = $exifTool->Options('Verbose');

    if ($dirLen < 13) {
        $exifTool->Warn('FPXR segment to small');
        return 0;
    }

    # get version and segment type (version is 0 in all my samples)
    my ($vers, $type) = unpack('x5C2', $$dataPt);

    if ($type == 1) {   # a "Contents List" segment

        $vers != 0 and $exifTool->Warn("Untested FPXR version $vers");
        if ($$exifTool{FPXR}) {
            $exifTool->Warn('Multiple FPXR contents lists');
            delete $$exifTool{FPXR};
        }
        my $numEntries = unpack('x7n', $$dataPt);
        my @contents;
        $verbose and $exifTool->VerboseDir('Contents List', $numEntries);
        my $pos = 9;
        my $entry;
        for ($entry = 0; $entry < $numEntries; ++$entry) {
            if ($pos + 4 > $dirLen) {
                $exifTool->Warn('Truncated FPXR contents');
                return 0;
            }
            my ($size, $default) = unpack("x${pos}Na", $$dataPt);
            pos($$dataPt) = $pos + 5;
            # according to the spec, this string is little-endian
            # (very odd, since the size word is big-endian),
            # and the first char must be '/'
            unless ($$dataPt =~ m{\G(/\0(..)*?)\0\0}sg) {
                $exifTool->Warn('Invalid FPXR stream name');
                return 0;
            }
            # convert stream pathname to ascii
            my $name = Image::ExifTool::Unicode2Latin($1, 'v');
            if ($verbose) {
                my $psize = ($size == 0xffffffff) ? 'storage' : "$size bytes";
                $exifTool->VPrint(0,"  |  $entry) Name: '$name' [$psize]\n");
            }
            # remove directory specification
            $name =~ s{.*/}{}s;
            # read storage class ID if necessary
            my $classID;
            if ($size == 0xffffffff) {
                unless ($$dataPt =~ m{(.{16})}sg) {
                    $exifTool->Warn('Truncated FPXR storage class ID');
                    return 0;
                }
                # unpack class ID in case we want to use it sometime
                $classID = Image::ExifTool::ASF::GetGUID($1);
            }
            # update position in list
            $pos = pos($$dataPt);
            # add to our contents list
            push @contents, {
                Name => $name,
                Size => $size,
                Default => $default,
                ClassID => $classID,
            };
        }
        # save contents list as $exifTool member variable
        # (must do this last so we don't save list on error)
        $$exifTool{FPXR} = \@contents;

    } elsif ($type == 2) {  # a "Stream Data" segment

        # get the contents list index and stream data offset
        my ($index, $offset) = unpack('x7nN', $$dataPt);
        my $fpxr = $$exifTool{FPXR};
        if ($fpxr and $$fpxr[$index]) {
            my $obj = $$fpxr[$index];
            # extract stream data (after 13-byte header)
            if (not defined $$obj{Stream}) {
                # ignore offset for first segment of this type
                # (in my sample images, this isn't always zero as one would expect)
                $$obj{Stream} = substr($$dataPt, $dirStart+13);
            } else {
                # add data to the stream at the proper offset
                my $pad = $offset - length($$obj{Stream});
                if ($pad >= 0) {
                    if ($pad) {
                        if ($pad > 0x10000) {
                            $exifTool->Warn("Bad FPXR stream offset ($offset)");
                        } else {
                            # pad with default value to specified offset
                            $exifTool->Warn("Padding FPXR stream with $pad default bytes",1);
                            $$obj{Stream} .= ($$obj{Default} x $pad);
                        }
                    }
                    # concatinate data with this stream
                    $$obj{Stream} .= substr($$dataPt, $dirStart+13);
                } else {
                    $exifTool->Warn("Duplicate FPXR stream data at offset $offset");
                    substr($$obj{Stream}, $offset, -$pad) = substr($$dataPt, $dirStart+13);
                }
            }
            # save value for this tag if stream is complete
            my $len = length $$obj{Stream};
            if ($len >= $$obj{Size}) {
                if ($verbose) {
                    $exifTool->VPrint(0, "  + [FPXR stream, Contents index $index, $len bytes]\n");
                }
                if ($len > $$obj{Size}) {
                    $exifTool->Warn('Extra data in FPXR segment (truncated)');
                    $$obj{Stream} = substr($$obj{Stream}, 0, $$obj{Size});
                }
                my $tag = $$obj{Name};
                my $tagInfo;
                unless ($$tagTablePtr{$tag}) {
                    # remove instance number or class ID from tag if necessary
                    $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $1) if
                        ($tag =~ /(.*) \d{6}$/s and $$tagTablePtr{$1}) or
                        ($tag =~ /(.*)_[0-9a-f]{16}$/s and $$tagTablePtr{$1});
                }
                # save the data for this tag
                $exifTool->HandleTag($tagTablePtr, $tag, $$obj{Stream},
                    DataPt => \$$obj{Stream},
                    TagInfo => $tagInfo,
                );
                delete $$obj{Stream}; # done with this stream
            }
        } else {
            $exifTool->Warn("Unlisted FPXR segment (index $index)");
        }

    } elsif ($type ne 3) {  # not a "Reserved" segment

        $exifTool->Warn("Unknown FPXR segment (type $type)");

    }

    # clean up if this was the last FPXR segment
    if ($$dirInfo{LastFPXR} and $$exifTool{FPXR}) {
        my $obj;
        my $i = 0;
        foreach $obj (@{$$exifTool{FPXR}}) {
            $exifTool->Warn("Missing stream for FPXR object $i") if defined $$obj{Stream};
            ++$i;
        }
        delete $$exifTool{FPXR};    # delete our temporary variables
    }
    return 1;
}

#------------------------------------------------------------------------------
# Extract information from a FlashPix (FPX) file
# Inputs: 0) ExifTool object ref, 1) dirInfo ref
# Returns: 1 on success, 0 if this wasn't a valid FPX image
sub ProcessFPX($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my ($buff, $out, %dumpParms, $oldIndent, $miniStreamBuff);

    # read header
    return 0 unless $raf->Read($buff,HDR_SIZE) == HDR_SIZE;
    # check signature
    return 0 unless $buff =~ /^\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1/;

    my $fileType = $exifTool->{FILE_EXT};
    $fileType = 'FPX' unless $fileType and $fileType =~ /^(DOC|XLS|PPT)$/;
    $exifTool->SetFileType($fileType);
    SetByteOrder(substr($buff, 0x1c, 2) eq "\xff\xfe" ? 'MM' : 'II');
    my $tagTablePtr = GetTagTable('Image::ExifTool::FlashPix::Main');
    my $verbose = $exifTool->Options('Verbose');

    my $sectSize = 1 << Get16u(\$buff, 0x1e);
    my $miniSize = 1 << Get16u(\$buff, 0x20);
    my $fatCount   = Get32u(\$buff, 0x2c);  # number of FAT sectors
    my $dirStart   = Get32u(\$buff, 0x30);  # first directory sector
    my $miniCutoff = Get32u(\$buff, 0x38);  # minimum size for big-FAT streams
    my $miniStart  = Get32u(\$buff, 0x3c);  # first sector of mini-FAT
    my $miniCount  = Get32u(\$buff, 0x40);  # number of mini-FAT sectors
    my $difStart   = Get32u(\$buff, 0x44);  # first sector of DIF chain
    my $difCount   = Get32u(\$buff, 0x48);  # number of DIF sectors

    if ($verbose) {
        $out = $exifTool->Options('TextOut');
        $dumpParms{Out} = $out;
        $dumpParms{MaxLen} = 96 if $verbose == 3;
        print $out "  Sector size=$sectSize\n  FAT: Count=$fatCount\n";
        print $out "  DIR: Start=$dirStart\n";
        print $out "  MiniFAT: Mini-sector size=$miniSize Start=$miniStart Count=$miniCount Cutoff=$miniCutoff\n";
        print $out "  DIF FAT: Start=$difStart Count=$difCount\n";
    }
#
# load the FAT
#
    my $pos = 0x4c;
    my $endPos = length($buff);
    my $fat = '';
    my $fatCountCheck = 0;
    for (;;) {
        while ($pos <= $endPos - 4) {
            my $sect = Get32u(\$buff, $pos);
            $pos += 4;
            next if $sect == FREE_SECT;
            my $offset = $sect * $sectSize + HDR_SIZE;
            my $fatSect;
            unless ($raf->Seek($offset, 0) and
                    $raf->Read($fatSect, $sectSize) == $sectSize)
            {
                $exifTool->Error("Error reading FAT from sector $sect");
                return 1;
            }
            $fat .= $fatSect;
            ++$fatCountCheck;
        }
        last if $difStart == END_OF_CHAIN;
        # read next DIF (Dual Indirect FAT) sector
        my $offset = $difStart * $sectSize + HDR_SIZE;
        unless ($raf->Seek($offset, 0) and $raf->Read($buff, $sectSize) == $sectSize) {
            $exifTool->Error("Error reading DIF sector $difStart");
            return 1;
        }
        # set end of sector information in this DIF
        $endPos = $sectSize - 4;
        # next time around we want to read next DIF in chain
        $difStart = Get32u(\$buff, $endPos);
    }
    if ($fatCountCheck != $fatCount) {
        $exifTool->Warn("Bad number of FAT sectors (expected $fatCount but found $fatCountCheck)");
    }
#
# load the mini-FAT and the directory
#
    my $miniFat = LoadChain($raf, $miniStart, \$fat, $sectSize, HDR_SIZE);
    my $dir = LoadChain($raf, $dirStart, \$fat, $sectSize, HDR_SIZE);
    unless (defined $miniFat and defined $dir) {
        $exifTool->Error('Error reading mini-FAT or directory stream');
        return 1;
    }
    if ($verbose) {
        print $out "  FAT [",length($fat)," bytes]:\n";
        Image::ExifTool::HexDump(\$fat, undef, %dumpParms) if $verbose > 2;
        print $out "  Mini-FAT [",length($miniFat)," bytes]:\n";
        Image::ExifTool::HexDump(\$miniFat, undef, %dumpParms) if $verbose > 2;
        print $out "  Directory [",length($dir)," bytes]:\n";
        Image::ExifTool::HexDump(\$dir, undef, %dumpParms) if $verbose > 2;
    }
#
# process the directory
#
    if ($verbose) {
        $oldIndent = $exifTool->{INDENT};
        $exifTool->{INDENT} .= '| ';
        $exifTool->VerboseDir('FPX', undef, length $dir);
    }
    my $miniStream;
    $endPos = length($dir);
    my $index = 0;

    for ($pos=0; $pos<=$endPos-128; $pos+=128) {

        # get directory entry type
        # (0=invalid, 1=storage, 2=stream, 3=lockbytes, 4=property, 5=root)
        my $type = Get8u(\$dir, $pos + 0x42);
        next if $type == 0; # skip invalid entries
        if ($type > 5) {
            $exifTool->Warn("Invalid directory entry type $type");
            last;   # rest of directory is probably garbage
        }
        # get entry name (note: this is supposed to be length in 2-byte
        # characters but this isn't what is done in my sample FPX file, so
        # be very tolerant of this count -- it's null terminated anyway)
        my $len = Get16u(\$dir, $pos + 0x40);
        $len > 32 and $len = 32;
        my $tag = Image::ExifTool::Unicode2Latin(substr($dir, $pos, $len * 2), 'v');
        $tag =~ s/\0.*//s;  # truncate at null (in case length was wrong)

        my $sect = Get32u(\$dir, $pos + 0x74);  # start sector number
        my $size = Get32u(\$dir, $pos + 0x78);  # stream length

        # load Ministream (referenced from first directory entry)
        unless ($miniStream) {
            $miniStreamBuff = LoadChain($raf, $sect, \$fat, $sectSize, HDR_SIZE);
            unless (defined $miniStreamBuff) {
                $exifTool->Warn('Error loading Mini-FAT stream');
                last;
            }
            $miniStream = new File::RandomAccess(\$miniStreamBuff);
        }

        my $tagInfo;
        if ($$tagTablePtr{$tag}) {
            $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        } else {
            # remove instance number or class ID from tag if necessary
            $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $1) if
                ($tag =~ /(.*) \d{6}$/s and $$tagTablePtr{$1}) or
                ($tag =~ /(.*)_[0-9a-f]{16}$/s and $$tagTablePtr{$1});
        }

        next unless $tagInfo or $verbose;

        # load the data for stream types
        my $extra = '';
        my $typeStr = $dirEntryType[$type] || $type;
        if ($typeStr eq 'STREAM') {
            if ($size >= $miniCutoff) {
                # stream is in the main FAT
                $buff = LoadChain($raf, $sect, \$fat, $sectSize, HDR_SIZE);
            } elsif ($size) {
                # stream is in the mini-FAT
                $buff = LoadChain($miniStream, $sect, \$miniFat, $miniSize, 0);
            } else {
                $buff = ''; # an empty stream
            }
            unless (defined $buff) {
                my $name = $tagInfo ? $$tagInfo{Name} : 'unknown';
                $exifTool->Warn("Error reading $name stream");
                $buff = '';
            }
        } elsif ($typeStr eq 'ROOT') {
            $buff = $miniStreamBuff;
            $extra .= ' (Ministream)';
        } else {
            $buff = '';
            undef $size;
        }
        if ($verbose) {
            my $flags = Get8u(\$dir, $pos + 0x43);  # 0=red, 1=black
            my $lSib = Get32u(\$dir, $pos + 0x44);  # left sibling
            my $rSib = Get32u(\$dir, $pos + 0x48);  # right sibling
            my $chld = Get32u(\$dir, $pos + 0x4c);  # child directory
            my $col = { 0 => 'Red', 1 => 'Black' }->{$flags} || $flags;
            $extra .= " Type=$typeStr Flags=$col";
            $extra .= " Left=$lSib" unless $lSib == FREE_SECT;
            $extra .= " Right=$rSib" unless $rSib == FREE_SECT;
            $extra .= " Child=$chld" unless $chld == FREE_SECT;
            $exifTool->VerboseInfo($tag, $tagInfo,
                Index => $index++,
                Value => $buff,
                DataPt => \$buff,
                Extra => $extra,
                Size => $size,
            );
        }
        if ($tagInfo and $buff) {
            if ($$tagInfo{SubDirectory}) {
                my %dirInfo = (
                    DataPt => \$buff,
                    DirStart => $tagInfo->{SubDirectory}->{DirStart},
                    DirLen => length $buff,
                    Multi => $$tagInfo{Multi},
                );
                my $subTablePtr = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
                $exifTool->ProcessDirectory(\%dirInfo, $subTablePtr);
            } else {
                $exifTool->FoundTag($tagInfo, $buff);
            }
        }
    }
    $exifTool->{INDENT} = $oldIndent if $verbose;
    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::FlashPix - Read FlashPix meta information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract
FlashPix meta information from FPX images, and from the APP2 FPXR segment of
JPEG images.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.exif.org/Exif2-2.PDF>

=item L<http://www.graphcomp.com/info/specs/livepicture/fpx.pdf>

=item L<http://search.cpan.org/~jdb/libwin32/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/FlashPix Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

