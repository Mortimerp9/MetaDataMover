#------------------------------------------------------------------------------
# File:         XMP.pm
#
# Description:  Read XMP meta information
#
# Revisions:    11/25/2003 - P. Harvey Created
#               10/28/2004 - P. Harvey Major overhaul to conform with XMP spec
#               02/27/2005 - P. Harvey Also read UTF-16 and UTF-32 XMP
#               08/30/2005 - P. Harvey Split tag tables into separate namespaces
#               10/24/2005 - P. Harvey Added ability to parse .XMP files
#               08/25/2006 - P. Harvey Added ability to handle blank nodes
#               08/22/2007 - P. Harvey Added ability to handle alternate language tags
#
# References:   1) http://www.adobe.com/products/xmp/pdfs/xmpspec.pdf
#               2) http://www.w3.org/TR/rdf-syntax-grammar/  (20040210)
#               3) http://www.portfoliofaq.com/pfaq/v7mappings.htm
#               4) http://www.iptc.org/IPTC4XMP/
#               5) http://creativecommons.org/technology/xmp
#                  --> changed to http://wiki.creativecommons.org/Companion_File_metadata_specification (2007/12/21)
#               6) http://www.optimasc.com/products/fileid/xmp-extensions.pdf
#               7) Lou Salkind private communication
#               8) http://partners.adobe.com/public/developer/en/xmp/sdk/XMPspecification.pdf
#               9) http://www.w3.org/TR/SVG11/
#               10) http://ns.useplus.org/
#
# Notes:      - I am handling property qualifiers as if they were separate
#               properties (with no associated namespace).
#
#             - Currently, there is no special treatment of the following
#               properties which could potentially affect the extracted
#               information: xml:base, rdf:parseType (note that parseType
#               Literal isn't allowed by the XMP spec).
#
#             - The family 2 group names will be set to 'Unknown' for any XMP
#               tags not found in the XMP or Exif tag tables.
#------------------------------------------------------------------------------

package Image::ExifTool::XMP;

use strict;
use vars qw($VERSION $AUTOLOAD @ISA @EXPORT_OK $xlatNamespace %nsURI);
use Image::ExifTool qw(:Utils);
use Image::ExifTool::Exif;
require Exporter;

$VERSION = '1.88';
@ISA = qw(Exporter);
@EXPORT_OK = qw(EscapeXML UnescapeXML);

sub ProcessXMP($$;$);
sub WriteXMP($$;$);
sub ParseXMPElement($$$;$$$);
sub DecodeBase64($);
sub SaveBlankInfo($$$;$);
sub ProcessBlankInfo($$$;$);
sub ValidateXMP($;$);
sub UnescapeChar($$);
sub FormatXMPDate($);

# lookup for translating namespaces
# Note: Use $xlatNamespace (only valid during processing) to do the translation
my %stdXlatNS = (
    # shorten ugly IPTC Core namespace prefix
    'Iptc4xmpCore' => 'iptcCore',
    'photomechanic'=> 'photomech',
    'MicrosoftPhoto' => 'microsoft',
);

# Lookup to translate our namespace prefixes into URI's.  This list need
# not be complete, but it must contain an entry for each namespace prefix
# (NAMESPACE) for writable tags in the XMP tables or in the %xmpStruct table
%nsURI = (
    aux       => 'http://ns.adobe.com/exif/1.0/aux/',
    cc        => 'http://creativecommons.org/ns#', # changed 2007/12/21 - PH
    crs       => 'http://ns.adobe.com/camera-raw-settings/1.0/',
    crss      => 'http://ns.adobe.com/camera-raw-saved-settings/1.0/',
    dc        => 'http://purl.org/dc/elements/1.1/',
    exif      => 'http://ns.adobe.com/exif/1.0/',
    iX        => 'http://ns.adobe.com/iX/1.0/',
    pdf       => 'http://ns.adobe.com/pdf/1.3/',
    pdfx      => 'http://ns.adobe.com/pdfx/1.3/',
    photoshop => 'http://ns.adobe.com/photoshop/1.0/',
    rdf       => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
    rdfs      => 'http://www.w3.org/2000/01/rdf-schema#',
    stDim     => 'http://ns.adobe.com/xap/1.0/sType/Dimensions#',
    stEvt     => 'http://ns.adobe.com/xap/1.0/sType/ResourceEvent#',
    stFnt     => 'http://ns.adobe.com/xap/1.0/sType/Font#',
    stJob     => 'http://ns.adobe.com/xap/1.0/sType/Job#',
    stRef     => 'http://ns.adobe.com/xap/1.0/sType/ResourceRef#',
    stVer     => 'http://ns.adobe.com/xap/1.0/sType/Version#',
    tiff      => 'http://ns.adobe.com/tiff/1.0/',
   'x'        => 'adobe:ns:meta/',
    xapG      => 'http://ns.adobe.com/xap/1.0/g/',
    xapGImg   => 'http://ns.adobe.com/xap/1.0/g/img/',
    xmp       => 'http://ns.adobe.com/xap/1.0/',
    xmpBJ     => 'http://ns.adobe.com/xap/1.0/bj/',
    xmpDM     => 'http://ns.adobe.com/xmp/1.0/DynamicMedia/',
    xmpMM     => 'http://ns.adobe.com/xap/1.0/mm/',
    xmpRights => 'http://ns.adobe.com/xap/1.0/rights/',
    xmpTPg    => 'http://ns.adobe.com/xap/1.0/t/pg/',
    xmpidq    => 'http://ns.adobe.com/xmp/Identifier/qual/1.0/',
    xmpPLUS   => 'http://ns.adobe.com/xap/1.0/PLUS/',
    plus      => 'http://ns.useplus.org/ldf/xmp/1.0/',
    dex       => 'http://ns.optimasc.com/dex/1.0/',
    mediapro  => 'http://ns.iview-multimedia.com/mediapro/1.0/',
    Iptc4xmpCore => 'http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/',
    MicrosoftPhoto => 'http://ns.microsoft.com/photo/1.0',
    lr        => 'http://ns.adobe.com/lightroom/1.0/',
    DICOM     => 'http://ns.adobe.com/DICOM/',
    svg       => 'http://www.w3.org/2000/svg',
);

# build reverse namespace lookup
my %uri2ns;
{
    my $ns;
    foreach $ns (keys %nsURI) {
        $uri2ns{$nsURI{$ns}} = $ns;
    }
}

# conversions for GPS coordinates
sub ToDegrees
{
    require Image::ExifTool::GPS;
    Image::ExifTool::GPS::ToDegrees($_[0], 1);
}
my %latConv = (
    ValueConv    => \&ToDegrees,
    RawConv => 'require Image::ExifTool::GPS; $val', # to load Composite tags and routines
    ValueConvInv => q{
        require Image::ExifTool::GPS;
        Image::ExifTool::GPS::ToDMS($self, $val, 2, "N");
    },
    PrintConv    => 'Image::ExifTool::GPS::ToDMS($self, $val, 1, "N")',
    PrintConvInv => \&ToDegrees,
);
my %longConv = (
    ValueConv    => \&ToDegrees,
    RawConv => 'require Image::ExifTool::GPS; $val',
    ValueConvInv => q{
        require Image::ExifTool::GPS;
        Image::ExifTool::GPS::ToDMS($self, $val, 2, "E");
    },
    PrintConv    => 'Image::ExifTool::GPS::ToDMS($self, $val, 1, "E")',
    PrintConvInv => \&ToDegrees,
);
my %dateTimeInfo = (
    # NOTE: Do NOT put "Groups" here because Groups hash must not be common!
    Writable => 'date',
    Shift => 'Time',
    PrintConv => '$self->ConvertDateTime($val)',
    PrintConvInv => '$self->InverseDateTime($val,1,1)',
);

# XMP namespaces which we don't want to contribute to generated EXIF tag names
# (Note: namespaces with non-standard prefixes aren't currently ignored)
my %ignoreNamespace = ( 'x'=>1, 'rdf'=>1, 'xmlns'=>1, 'xml'=>1, 'svg'=>1 );

# these are the attributes that we handle for properties that contain
# sub-properties.  Attributes for simple properties are easy, and we
# just copy them over.  These are harder since we don't store attributes
# for properties without simple values.  (maybe this will change...)
my %recognizedAttrs = (
    'x:xaptk' => 1,
    'x:xmptk' => 1,
    'rdf:about' => 1,
    'rdf:parseType' => 1,
    'rdf:nodeID' => 1,
);

# main XMP tag table
%Image::ExifTool::XMP::Main = (
    GROUPS => { 2 => 'Unknown' },
    PROCESS_PROC => \&ProcessXMP,
    WRITE_PROC => \&WriteXMP,
    dc => {
        Name => 'dc', # (otherwise generated name would be 'Dc')
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::dc' },
    },
    xmp => {
        Name => 'xmp',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmp' },
    },
    xmpDM => {
        Name => 'xmpDM',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpDM' },
    },
    xmpRights => {
        Name => 'xmpRights',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpRights' },
    },
    xmpMM => {
        Name => 'xmpMM',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpMM' },
    },
    xmpBJ => {
        Name => 'xmpBJ',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpBJ' },
    },
    xmpTPg => {
        Name => 'xmpTPg',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpTPg' },
    },
    pdf => {
        Name => 'pdf',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::pdf' },
    },
    photoshop => {
        Name => 'photoshop',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::photoshop' },
    },
    crs => {
        Name => 'crs',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::crs' },
    },
    # crss - it would be difficult to add the ability to write this
    aux => {
        Name => 'aux',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::aux' },
    },
    tiff => {
        Name => 'tiff',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::tiff' },
    },
    exif => {
        Name => 'exif',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::exif' },
    },
    iptcCore => {
        Name => 'iptcCore',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::iptcCore' },
    },
    PixelLive => {
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::PixelLive' },
    },
    xmpPLUS => {
        Name => 'xmpPLUS',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::xmpPLUS' },
    },
    plus => {
        Name => 'plus',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::plus' },
    },
    cc => {
        Name => 'cc',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::cc' },
    },
    dex => {
        Name => 'dex',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::dex' },
    },
    photomech => {
        Name => 'photomech',
        SubDirectory => { TagTable => 'Image::ExifTool::PhotoMechanic::XMP' },
    },
    mediapro => {
        Name => 'mediapro',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::MediaPro' },
    },
    microsoft => {
        Name => 'microsoft',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::Microsoft' },
    },
    lr => {
        Name => 'lr',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::Lightroom' },
    },
    DICOM => {
        Name => 'DICOM',
        SubDirectory => { TagTable => 'Image::ExifTool::XMP::DICOM' },
    },
);

#
# Tag tables for all XMP schemas:
#
# Writable - only need to define this for writable tags if not plain text
#            (boolean, integer, rational, real, date or lang-alt)
# List - XMP list type (Bag, Seq or Alt, or set to 1 for elements in Struct lists)
#
# (Note that family 1 group names are generated from the property namespace, not
#  the group1 names below which exist so the groups will appear in the list.)
#
my %xmpTableDefaults = (
    WRITE_PROC => \&WriteXMP,
    WRITABLE => 'string',
    LANG_INFO => \&GetLangInfo,
);

# Dublin Core schema properties (dc)
%Image::ExifTool::XMP::dc = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-dc', 2 => 'Other' },
    NAMESPACE => 'dc',
    NOTES => 'Dublin Core schema tags.',
    contributor => { Groups => { 2 => 'Author' }, List => 'Bag' },
    coverage    => { },
    creator     => { Groups => { 2 => 'Author' }, List => 'Seq' },
    date        => { Groups => { 2 => 'Time' },   List => 'Seq', %dateTimeInfo },
    description => { Groups => { 2 => 'Image'  }, Writable => 'lang-alt' },
   'format'     => { Groups => { 2 => 'Image'  } },
    identifier  => { Groups => { 2 => 'Image'  } },
    language    => { List => 'Bag' },
    publisher   => { Groups => { 2 => 'Author' }, List => 'Bag' },
    relation    => { List => 'Bag' },
    rights      => { Groups => { 2 => 'Author' }, Writable => 'lang-alt' },
    source      => { Groups => { 2 => 'Author' }, Avoid => 1 },
    subject     => { Groups => { 2 => 'Image'  }, List => 'Bag' },
    title       => { Groups => { 2 => 'Image'  }, Writable => 'lang-alt' },
    type        => { Groups => { 2 => 'Image'  }, List => 'Bag' },
);

# XMP Basic schema properties (xmp, xap)
%Image::ExifTool::XMP::xmp = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmp', 2 => 'Image' },
    NAMESPACE => 'xmp',
    NOTES => q{
        XMP Basic schema tags.  If the older "xap", "xapBJ", "xapMM" or "xapRights"
        namespace prefixes are found, they are translated to the newer "xmp",
        "xmpBJ", "xmpMM" and "xmpRights" prefixes for use in family 1 group names.
    },
    Advisory    => { List => 'Bag' },
    BaseURL     => { },
    CreateDate  => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    CreatorTool => { },
    Identifier  => { Avoid => 1, List => 'Bag' },
    Label       => { },
    MetadataDate=> { Groups => { 2 => 'Time' }, %dateTimeInfo },
    ModifyDate  => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    Nickname    => { },
    Rating      => { Writable => 'integer' },
    Thumbnails  => {
        SubDirectory => { },
        Struct => 'Thumbnail',
        List => 'Alt',
    },
    ThumbnailsHeight    => { List => 1 },
    ThumbnailsWidth     => { List => 1 },
    ThumbnailsFormat    => { List => 1 },
    ThumbnailsImage     => {
        # Eventually may want to handle this like a normal thumbnail image
        # -- but not yet!  (need to write EncodeBase64() routine....)
        # Name => 'ThumbnailImage',
        List => 1,
        # translate Base64-encoded thumbnail
        ValueConv => 'Image::ExifTool::XMP::DecodeBase64($val)',
        ValueConvInv => 'Image::ExifTool::XMP::EncodeBase64($val)',
    },
);

# XMP Rights Management schema properties (xmpRights, xapRights)
%Image::ExifTool::XMP::xmpRights = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpRights', 2 => 'Author' },
    NAMESPACE => 'xmpRights',
    NOTES => 'XMP Rights Management schema tags.',
    Certificate     => { },
    Marked          => { Writable => 'boolean' },
    Owner           => { List => 'Bag' },
    UsageTerms      => { Writable => 'lang-alt' },
    WebStatement    => { },
);

# XMP Media Management schema properties (xmpMM, xapMM)
%Image::ExifTool::XMP::xmpMM = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpMM', 2 => 'Other' },
    NAMESPACE => 'xmpMM',
    NOTES => 'XMP Media Management schema tags.',
    DerivedFrom     => {
        SubDirectory => { },
        Struct => 'ResourceRef',
    },
    DerivedFromInstanceID       => { },
    DerivedFromDocumentID       => { },
    DerivedFromVersionID        => { },
    DerivedFromRenditionClass   => { },
    DerivedFromRenditionParams  => { },
    DerivedFromManager          => { },
    DerivedFromManagerVariant   => { },
    DerivedFromManageTo         => { },
    DerivedFromManageUI         => { },
    DocumentID      => { },
    History         => {
        SubDirectory => { },
        Struct => 'ResourceEvent',
        List => 'Seq',
    },
    # we treat these like list items since History is a list
    HistoryAction           => { List => 1 },
    HistoryInstanceID       => { List => 1 },
    HistoryParameters       => { List => 1 },
    HistorySoftwareAgent    => { List => 1 },
    HistoryWhen             => { List => 1, Groups => { 2 => 'Time' }, %dateTimeInfo },
    InstanceID      => { }, #PH (CS3)
    ManagedFrom     => { SubDirectory => { }, Struct => 'ResourceRef' },
    ManagedFromInstanceID       => { },
    ManagedFromDocumentID       => { },
    ManagedFromVersionID        => { },
    ManagedFromRenditionClass   => { },
    ManagedFromRenditionParams  => { },
    ManagedFromManager          => { },
    ManagedFromManagerVariant   => { },
    ManagedFromManageTo         => { },
    ManagedFromManageUI         => { },
    Manager         => { Groups => { 2 => 'Author' } },
    ManageTo        => { Groups => { 2 => 'Author' } },
    ManageUI        => { },
    ManagerVariant  => { },
    PreservedFileName => { },   # undocumented
    RenditionClass  => { },
    RenditionParams => { },
    VersionID       => { },
    Versions        => {
        SubDirectory => { },
        Struct => 'Version',
        List => 'Seq',
    },
    VersionsComments    => { List => 1 },   # we treat these like list items
    VersionsEvent       => { SubDirectory => { }, Struct => 'ResourceEvent' },
    VersionsEventAction         => { List => 1 },
    VersionsEventInstanceID     => { List => 1 },
    VersionsEventParameters     => { List => 1 },
    VersionsEventSoftwareAgent  => { List => 1 },
    VersionsEventWhen           => { List => 1, Groups => { 2 => 'Time' }, %dateTimeInfo },
    VersionsModifyDate          => { List => 1, Groups => { 2 => 'Time' }, %dateTimeInfo },
    VersionsModifier            => { List => 1 },
    VersionsVersion             => { List => 1 },
    LastURL                     => { },
    RenditionOf         => { SubDirectory => { }, Struct => 'ResourceRef' },
    RenditionOfInstanceID       => { },
    RenditionOfDocumentID       => { },
    RenditionOfVersionID        => { },
    RenditionOfRenditionClass   => { },
    RenditionOfRenditionParams  => { },
    RenditionOfManager          => { },
    RenditionOfManagerVariant   => { },
    RenditionOfManageTo         => { },
    RenditionOfManageUI         => { },
    SaveID          => { Writable => 'integer' },
);

# XMP Basic Job Ticket schema properties (xmpBJ, xapBJ)
%Image::ExifTool::XMP::xmpBJ = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpBJ', 2 => 'Other' },
    NAMESPACE => 'xmpBJ',
    NOTES => 'XMP Basic Job Ticket schema tags.',
    # Note: JobRef is a List of structures.  To accomplish this, we set the XMP
    # List=>'Bag', but since SubDirectory is defined, this tag isn't writable
    # directly.  Then we need to set List=>1 for the members so the Writer logic
    # will allow us to add list elements.
    JobRef => {
        SubDirectory => { },
        Struct => 'JobRef',
        List => 'Bag',
    },
    JobRefName  => { List => 1 },   # we treat these like list items
    JobRefId    => { List => 1 },
    JobRefUrl   => { List => 1 },
);

# XMP Paged-Text schema properties (xmpTPg)
%Image::ExifTool::XMP::xmpTPg = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpTPg', 2 => 'Image' },
    NAMESPACE => 'xmpTPg',
    NOTES => 'XMP Paged-Text schema tags.',
    MaxPageSize => { SubDirectory => { }, Struct => 'Dimensions' },
    MaxPageSizeW    => { Writable => 'real' },
    MaxPageSizeH    => { Writable => 'real' },
    MaxPageSizeUnit => { },
    NPages      => { Writable => 'integer' },
    Fonts       => {
        SubDirectory => { },
        Struct => 'Font',
        List => 'Bag',
    },
    FontsFontName       => { List => 1 },
    FontsFontFamily     => { List => 1 },
    FontsFontFace       => { List => 1 },
    FontsFontType       => { List => 1 },
    FontsVersionString  => { List => 1 },
    FontsComposite      => { List => 1, Writable => 'boolean' },
    FontsFontFileName   => { List => 1 },
    FontsChildFontFiles => { List => 1 },
    Colorants   => {
        SubDirectory => { },
        Struct => 'Colorant',
        List => 'Seq',
    },
    ColorantsSwatchName => { List => 1 },
    ColorantsMode       => { List => 1 },
    ColorantsType       => { List => 1 },
    ColorantsCyan       => { List => 1, Writable => 'real' },
    ColorantsMagenta    => { List => 1, Writable => 'real' },
    ColorantsYellow     => { List => 1, Writable => 'real' },
    ColorantsBlack      => { List => 1, Writable => 'real' },
    ColorantsRed        => { List => 1, Writable => 'integer' },
    ColorantsGreen      => { List => 1, Writable => 'integer' },
    ColorantsBlue       => { List => 1, Writable => 'integer' },
    ColorantsL          => { List => 1, Writable => 'real' },
    ColorantsA          => { List => 1, Writable => 'integer' },
    ColorantsB          => { List => 1, Writable => 'integer' },
    PlateNames  => { List => 'Seq' },
);

# XMP Dynamic Media schema properties (xmpDM)
%Image::ExifTool::XMP::xmpDM = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpDM', 2 => 'Image' },
    NAMESPACE => 'xmpDM',
    NOTES => 'XMP Dynamic Media schema tags.',
    projectRef => {
        SubDirectory => { },
        Struct => 'ProjectLink',
    },
    projectRefType      => { },
    projectRefPath      => { },
    videoFrameRate      => { },
    videoFrameSize => {
        SubDirectory => { },
        Struct => 'Dimensions',
    },
    videoFrameSizeW     => { Writable => 'real' },
    videoFrameSizeH     => { Writable => 'real' },
    videoFrameSizeUnit  => { },
    videoPixelAspectRatio => { Writable => 'rational' },
    videoPixelDepth     => { },
    videoColorSpace     => { },
    videoAlphaMode      => { },
    videoAlphaPremultipleColor => {
        SubDirectory => { },
        Struct => 'Colorant',
    },
    videoAlphaPremultipleColorSwatchName => { },
    videoAlphaPremultipleColorMode       => { },
    videoAlphaPremultipleColorType       => { },
    videoAlphaPremultipleColorCyan       => { Writable => 'real' },
    videoAlphaPremultipleColorMagenta    => { Writable => 'real' },
    videoAlphaPremultipleColorYellow     => { Writable => 'real' },
    videoAlphaPremultipleColorBlack      => { Writable => 'real' },
    videoAlphaPremultipleColorRed        => { Writable => 'integer' },
    videoAlphaPremultipleColorGreen      => { Writable => 'integer' },
    videoAlphaPremultipleColorBlue       => { Writable => 'integer' },
    videoAlphaPremultipleColorL          => { Writable => 'real' },
    videoAlphaPremultipleColorA          => { Writable => 'integer' },
    videoAlphaPremultipleColorB          => { Writable => 'integer' },
    videoAlphaUnityIsTransparent => { Writable => 'boolean' },
    videoCompressor     => { },
    videoFieldOrder     => { },
    pullDown            => { },
    audioSampleRate     => { Writable => 'integer' },
    audioSampleType     => { },
    audioChannelType    => { },
    audioCompressor     => { },
    speakerPlacement    => { },
    fileDataRate        => { Writable => 'rational' },
    tapeName            => { },
    altTapeName         => { },
    startTimecode => {
        SubDirectory => { },
        Struct => 'Timecode',
    },
    startTimecodeTimeValue  => { },
    startTimecodeTimeFormat => { },
    altTimecode => {
        SubDirectory => { },
        Struct => 'Timecode',
    },
    altTimecodeTimeValue    => { },
    altTimecodeTimeFormat   => { },
    duration            => { },
    scene               => { Avoid => 1 },
    shotName            => { },
    shotDate            => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    shotLocation        => { },
    logComment          => { },
    markers => {
        SubDirectory => { },
        Struct => 'Marker',
        List => 'Seq',
    },
    markersStartTime    => { List => 1 },
    markersDuration     => { List => 1 },
    markersComment      => { List => 1 },
    markersName         => { List => 1 },
    markersLocation     => { List => 1 },
    markersTarget       => { List => 1 },
    markersType         => { List => 1 },
    contributedMedia => {
        SubDirectory => { },
        Struct => 'Media',
        List => 'Bag',
    },
    contributedMediaPath         => { List => 1 },
    contributedMediaTrack        => { List => 1 },
    contributedMediaStartTime    => { List => 1 },
    contributedMediaDuration     => { List => 1 },
    contributedMediaManaged      => { List => 1, Writable => 'boolean' },
    contributedMediaWebStatement => { List => 1 },
    absPeakAudioFilePath => { },
    relativePeakAudioFilePath => { },
    videoModDate    => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    audioModDate    => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    metadataModDate => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    artist          => { Avoid => 1, Groups => { 2 => 'Author' } },
    album           => { },
    trackNumber     => { Writable => 'integer' },
    genre           => { },
    copyright       => { Avoid => 1, Groups => { 2 => 'Author' } },
    releaseDate     => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    composer        => { Groups => { 2 => 'Author' } },
    engineer        => { },
    tempo           => { Writable => 'real' },
    instrument      => { },
    introTime       => { },
    outCue          => { },
    relativeTimestamp => { },
    loop            => { Writable => 'boolean' },
    numberOfBeats   => { Writable => 'real' },
    key             => { },
    stretchMode     => { },
    timeScaleParams => {
        SubDirectory => { },
        Struct => 'TimeScaleStretch',
    },
    timeScaleParamsQuality  => { },
    timeScaleParamsFrameSize=> { Writable => 'real' },
    timeScaleParamsFrameOverlappingPercentage => { Writable => 'real' },
    resampleParams => {
        SubDirectory => { },
        Struct => 'ResampleStretch',
    },
    resampleParamsQuality   => { },
    beatSpliceParams => {
        SubDirectory => { },
        Struct => 'BeatSpliceStretch',
    },
    beatSpliceParamsUseFileBeatsMarker => { Writable => 'boolean' },
    beatSpliceParamsRiseInDecibel      => { Writable => 'real' },
    beatSpliceParamsRiseInTimeDuration => { },
    timeSignature   => { },
    scaleType       => { },
);

# PDF schema properties (pdf)
%Image::ExifTool::XMP::pdf = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-pdf', 2 => 'Image' },
    NAMESPACE => 'pdf',
    NOTES => q{
        Adobe PDF schema tags.  The official XMP specification defines only
        Keywords, PDFVersion and Producer.  The other tags are included because they
        have been observed in PDF files, but Creator, Subject and Title are avoided
        when writing due to name conflicts with XMP-dc tags.
    },
    Author      => { Groups => { 2 => 'Author' } }, #PH
    ModDate     => { Groups => { 2 => 'Time' }, %dateTimeInfo }, #PH
    CreationDate=> { Groups => { 2 => 'Time' }, %dateTimeInfo }, #PH
    Creator     => { Groups => { 2 => 'Author' }, Avoid => 1 },
    Subject     => { Avoid => 1 },
    Title       => { Avoid => 1 },
    Keywords    => { },
    PDFVersion  => { },
    Producer    => { Groups => { 2 => 'Author' } },
);

# Photoshop schema properties (photoshop)
%Image::ExifTool::XMP::photoshop = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-photoshop', 2 => 'Image' },
    NAMESPACE => 'photoshop',
    NOTES => 'Adobe Photoshop schema tags.',
    AuthorsPosition => { Groups => { 2 => 'Author' } },
    CaptionWriter   => { Groups => { 2 => 'Author' } },
    Category        => { },
    City            => { Groups => { 2 => 'Location' } },
    Country         => { Groups => { 2 => 'Location' } },
    ColorMode       => { }, #PH
    Credit          => { Groups => { 2 => 'Author' } },
    DateCreated     => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    History         => { }, #PH (CS3)
    Headline        => { },
    Instructions    => { },
    ICCProfile      => { Name => 'ICCProfileName' }, #PH
    LegacyIPTCDigest=> { }, #PH
    SidecarForExtension => { }, #PH (CS3)
    Source          => { Groups => { 2 => 'Author' } },
    State           => { Groups => { 2 => 'Location' } },
    # the documentation doesn't show this as a 'Bag', but that's the
    # way Photoshop7.0 writes it - PH
    SupplementalCategories  => { List => 'Bag' },
    TransmissionReference   => { },
    Urgency         => { Writable => 'integer' },
);

# Photoshop Camera Raw Schema properties (crs) - (ref 8,PH)
%Image::ExifTool::XMP::crs = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-crs', 2 => 'Image' },
    NAMESPACE => 'crs',
    NOTES => 'Photoshop Camera Raw Schema tags.',
    AlreadyApplied  => { Writable => 'boolean' }, #PH (written by LightRoom beta 4.1)
    AutoBrightness  => { Writable => 'boolean' },
    AutoContrast    => { Writable => 'boolean' },
    AutoExposure    => { Writable => 'boolean' },
    AutoShadows     => { Writable => 'boolean' },
    BlueHue         => { Writable => 'integer' },
    BlueSaturation  => { Writable => 'integer' },
    Brightness      => { Writable => 'integer' },
    CameraProfile   => { },
    ChromaticAberrationB=> { Writable => 'integer' },
    ChromaticAberrationR=> { Writable => 'integer' },
    ColorNoiseReduction => { Writable => 'integer' },
    Contrast        => { Writable => 'integer', Avoid => 1 },
    CropTop         => { Writable => 'real' },
    CropLeft        => { Writable => 'real' },
    CropBottom      => { Writable => 'real' },
    CropRight       => { Writable => 'real' },
    CropAngle       => { Writable => 'real' },
    CropWidth       => { Writable => 'real' },
    CropHeight      => { Writable => 'real' },
    CropUnits => {
        Writable => 'integer',
        PrintConv => {
            0 => 'pixels',
            1 => 'inches',
            2 => 'cm',
        },
    },
    Exposure        => { Writable => 'real' },
    GreenHue        => { Writable => 'integer' },
    GreenSaturation => { Writable => 'integer' },
    HasCrop         => { Writable => 'boolean' },
    HasSettings     => { Writable => 'boolean' },
    LuminanceSmoothing  => { Writable => 'integer' },
    RawFileName     => { },
    RedHue          => { Writable => 'integer' },
    RedSaturation   => { Writable => 'integer' },
    Saturation      => { Writable => 'integer', Avoid => 1 },
    Shadows         => { Writable => 'integer' },
    ShadowTint      => { Writable => 'integer' },
    Sharpness       => { Writable => 'integer', Avoid => 1 },
    Temperature     => { Writable => 'integer' },
    Tint            => { Writable => 'integer' },
    ToneCurve       => { List => 'Seq' },
    ToneCurveName => {
        PrintConv => {
            Linear           => 'Linear',
           'Medium Contrast' => 'Medium Contrast',
           'Strong Contrast' => 'Strong Contrast',
            Custom           => 'Custom',
        },
    },
    Version         => { },
    VignetteAmount  => { Writable => 'integer' },
    VignetteMidpoint=> { Writable => 'integer' },
    WhiteBalance    => {
        Avoid => 1,
        PrintConv => {
           'As Shot'    => 'As Shot',
            Auto        => 'Auto',
            Daylight    => 'Daylight',
            Cloudy      => 'Cloudy',
            Shade       => 'Shade',
            Tungsten    => 'Tungsten',
            Fluorescent => 'Fluorescent',
            Flash       => 'Flash',
            Custom      => 'Custom',
        },
    },
    # new tags observed in Adobe Lightroom output - PH
    CameraProfileDigest         => { },
    Clarity                     => { Writable => 'integer' },
    ConvertToGrayscale          => { Writable => 'boolean' },
    Defringe                    => { Writable => 'integer' },
    FillLight                   => { Writable => 'integer' },
    HighlightRecovery           => { Writable => 'integer' },
    HueAdjustmentAqua           => { Writable => 'integer' },
    HueAdjustmentBlue           => { Writable => 'integer' },
    HueAdjustmentGreen          => { Writable => 'integer' },
    HueAdjustmentMagenta        => { Writable => 'integer' },
    HueAdjustmentOrange         => { Writable => 'integer' },
    HueAdjustmentPurple         => { Writable => 'integer' },
    HueAdjustmentRed            => { Writable => 'integer' },
    HueAdjustmentYellow         => { Writable => 'integer' },
    IncrementalTemperature      => { Writable => 'integer' },
    IncrementalTint             => { Writable => 'integer' },
    LuminanceAdjustmentAqua     => { Writable => 'integer' },
    LuminanceAdjustmentBlue     => { Writable => 'integer' },
    LuminanceAdjustmentGreen    => { Writable => 'integer' },
    LuminanceAdjustmentMagenta  => { Writable => 'integer' },
    LuminanceAdjustmentOrange   => { Writable => 'integer' },
    LuminanceAdjustmentPurple   => { Writable => 'integer' },
    LuminanceAdjustmentRed      => { Writable => 'integer' },
    LuminanceAdjustmentYellow   => { Writable => 'integer' },
    ParametricDarks             => { Writable => 'integer' },
    ParametricHighlights        => { Writable => 'integer' },
    ParametricHighlightSplit    => { Writable => 'integer' },
    ParametricLights            => { Writable => 'integer' },
    ParametricMidtoneSplit      => { Writable => 'integer' },
    ParametricShadows           => { Writable => 'integer' },
    ParametricShadowSplit       => { Writable => 'integer' },
    SaturationAdjustmentAqua    => { Writable => 'integer' },
    SaturationAdjustmentBlue    => { Writable => 'integer' },
    SaturationAdjustmentGreen   => { Writable => 'integer' },
    SaturationAdjustmentMagenta => { Writable => 'integer' },
    SaturationAdjustmentOrange  => { Writable => 'integer' },
    SaturationAdjustmentPurple  => { Writable => 'integer' },
    SaturationAdjustmentRed     => { Writable => 'integer' },
    SaturationAdjustmentYellow  => { Writable => 'integer' },
    SharpenDetail               => { Writable => 'integer' },
    SharpenEdgeMasking          => { Writable => 'integer' },
    SharpenRadius               => { Writable => 'real' },
    SplitToningBalance          => { Writable => 'integer' },
    SplitToningHighlightHue     => { Writable => 'integer' },
    SplitToningHighlightSaturation => { Writable => 'integer' },
    SplitToningShadowHue        => { Writable => 'integer' },
    SplitToningShadowSaturation => { Writable => 'integer' },
    Vibrance                    => { Writable => 'integer' },
    # new tags written by LR 1.4 (not sure in what version they first appeared)
    GrayMixerRed                => { Writable => 'integer' },
    GrayMixerOrange             => { Writable => 'integer' },
    GrayMixerYellow             => { Writable => 'integer' },
    GrayMixerGreen              => { Writable => 'integer' },
    GrayMixerAqua               => { Writable => 'integer' },
    GrayMixerBlue               => { Writable => 'integer' },
    GrayMixerPurple             => { Writable => 'integer' },
    GrayMixerMagenta            => { Writable => 'integer' },
    RetouchInfo                 => { List => 'Seq' },
    RedEyeInfo                  => { List => 'Seq' },
);

# Tiff schema properties (tiff)
%Image::ExifTool::XMP::tiff = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-tiff', 2 => 'Image' },
    NAMESPACE => 'tiff',
    PRIORITY => 0, # not as reliable as actual TIFF tags
    NOTES => 'EXIF schema for TIFF tags.',
    ImageWidth  => { Writable => 'integer' },
    ImageLength => {
        Name => 'ImageHeight',
        Notes => 'called ImageLength in the XMP specification',
        Writable => 'integer',
    },
    BitsPerSample => { Writable => 'integer', List => 'Seq' },
    Compression => {
        Writable => 'integer',
        PrintConv => \%Image::ExifTool::Exif::compression,
    },
    PhotometricInterpretation => {
        Writable => 'integer',
        PrintConv => \%Image::ExifTool::Exif::photometricInterpretation,
    },
    Orientation => {
        Writable => 'integer',
        PrintConv => \%Image::ExifTool::Exif::orientation,
    },
    SamplesPerPixel => { Writable => 'integer' },
    PlanarConfiguration => {
        Writable => 'integer',
        PrintConv => {
            1 => 'Chunky',
            2 => 'Planar',
        },
    },
    YCbCrSubSampling => {
        PrintConv => {
            '1 1' => 'YCbCr4:4:4',
            '2 1' => 'YCbCr4:2:2',
            '2 2' => 'YCbCr4:2:0',
            '4 1' => 'YCbCr4:1:1',
            '4 2' => 'YCbCr4:1:0',
            '1 2' => 'YCbCr4:4:0',
        },
    },
    YCbCrPositioning => {
        Writable => 'integer',
        PrintConv => {
            1 => 'Centered',
            2 => 'Co-sited',
        },
    },
    XResolution => { Writable => 'rational' },
    YResolution => { Writable => 'rational' },
    ResolutionUnit => {
        Writable => 'integer',
        PrintConv => {
            1 => 'None',
            2 => 'inches',
            3 => 'cm',
        },
    },
    TransferFunction      => { Writable => 'integer',  List => 'Seq' },
    WhitePoint            => { Writable => 'rational', List => 'Seq' },
    PrimaryChromaticities => { Writable => 'rational', List => 'Seq' },
    YCbCrCoefficients     => { Writable => 'rational', List => 'Seq' },
    ReferenceBlackWhite   => { Writable => 'rational', List => 'Seq' },
    DateTime => {
        Description => 'Date/Time Modified',
        Groups => { 2 => 'Time' },
        %dateTimeInfo,
    },
    ImageDescription => { Writable => 'lang-alt' },
    Make  => { Groups => { 2 => 'Camera' } },
    Model => {
        Description => 'Camera Model Name',
        Groups => { 2 => 'Camera' },
    },
    Software  => { },
    Artist    => { Groups => { 2 => 'Author' } },
    Copyright => {
        Groups => { 2 => 'Author' },
        Writable => 'lang-alt',
    },
    NativeDigest => { }, #PH
);

# Exif schema properties (exif)
%Image::ExifTool::XMP::exif = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-exif', 2 => 'Image' },
    NAMESPACE => 'exif',
    PRIORITY => 0, # not as reliable as actual EXIF tags
    NOTES => 'EXIF schema for EXIF tags.',
    ExifVersion     => { },
    FlashpixVersion => { },
    ColorSpace => {
        Writable => 'integer',
        PrintConv => {
            1 => 'sRGB',
            2 => 'Adobe RGB',
            0xffff => 'Uncalibrated',
            0xffffffff => 'Uncalibrated',
        },
    },
    ComponentsConfiguration => {
        List => 'Seq',
        Writable => 'integer',
        PrintConv => {
            0 => '.',
            1 => 'Y',
            2 => 'Cb',
            3 => 'Cr',
            4 => 'R',
            5 => 'G',
            6 => 'B',
        },
    },
    CompressedBitsPerPixel => {
        Writable => 'rational',
    },
    PixelXDimension => {
        Name => 'ExifImageWidth',
        Notes => 'called PixelXDimension by the XMP spec',
        Writable => 'integer',
    },
    PixelYDimension => {
        Name => 'ExifImageHeight',
        Notes => 'called PixelYDimension by the XMP spec',
        Writable => 'integer',
    },
    MakerNote => { },
    UserComment => {
        Writable => 'lang-alt',
    },
    RelatedSoundFile => { },
    DateTimeOriginal => {
        Description => 'Date/Time Original',
        Groups => { 2 => 'Time' },
        %dateTimeInfo,
    },
    DateTimeDigitized => {
        Description => 'Date/Time Digitized',
        Groups => { 2 => 'Time' },
        %dateTimeInfo,
    },
    ExposureTime => {
        Writable => 'rational',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        PrintConvInv => 'eval $val',
    },
    FNumber => {
        Writable => 'rational',
        PrintConv => 'sprintf("%.1f",$val)',
        PrintConvInv => '$val',
    },
    ExposureProgram => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            1 => 'Manual',
            2 => 'Program AE',
            3 => 'Aperture-priority AE',
            4 => 'Shutter speed priority AE',
            5 => 'Creative (Slow speed)',
            6 => 'Action (High speed)',
            7 => 'Portrait',
            8 => 'Landscape',
        },
    },
    SpectralSensitivity => {
        Groups => { 2 => 'Camera' },
    },
    ISOSpeedRatings => {
        Name => 'ISO',
        Writable => 'integer',
        List => 'Seq',
    },
    OECF => {
        Name => 'Opto-ElectricConvFactor',
        Groups => { 2 => 'Camera' },
        SubDirectory => { },
        Struct => 'OECF',
    },
    OECFColumns => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    OECFRows => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    OECFNames => {
        Groups => { 2 => 'Camera' },
        List => 'Seq',
    },
    OECFValues => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
        List => 'Seq',
    },
    ShutterSpeedValue => {
        Writable => 'rational',
        ValueConv => 'abs($val)<100 ? 1/(2**$val) : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
        ValueConvInv => '$val>0 ? -log($val)/log(2) : 0',
        # do eval to convert things like '1/100'
        PrintConvInv => 'eval $val',
    },
    ApertureValue => {
        Writable => 'rational',
        ValueConv => 'sqrt(2) ** $val',
        PrintConv => 'sprintf("%.1f",$val)',
        ValueConvInv => '$val>0 ? 2*log($val)/log(2) : 0',
        PrintConvInv => '$val',
    },
    BrightnessValue => {
        Writable => 'rational',
    },
    ExposureBiasValue => {
        Name => 'ExposureCompensation',
        Writable => 'rational',
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
        PrintConvInv => '$val',
    },
    MaxApertureValue => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
        ValueConv => 'sqrt(2) ** $val',
        PrintConv => 'sprintf("%.1f",$val)',
        ValueConvInv => '$val>0 ? 2*log($val)/log(2) : 0',
        PrintConvInv => '$val',
    },
    SubjectDistance => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
        PrintConv => '$val eq "inf" ? $val : "$val m"',
        PrintConvInv => '$val=~s/\s*m$//;$val',
    },
    MeteringMode => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            1 => 'Average',
            2 => 'Center-weighted average',
            3 => 'Spot',
            4 => 'Multi-spot',
            5 => 'Multi-segment',
            6 => 'Partial',
            255 => 'Other',
        },
    },
    LightSource => {
        Groups => { 2 => 'Camera' },
        PrintConv =>  \%Image::ExifTool::Exif::lightSource,
    },
    Flash => {
        Groups => { 2 => 'Camera' },
        SubDirectory => { },
        Struct => 'Flash',
    },
    FlashFired => {
        Groups => { 2 => 'Camera' },
        Writable => 'boolean',
    },
    FlashReturn => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'No return detection',
            2 => 'Return not detected',
            3 => 'Return detected',
        },
    },
    FlashMode => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Unknown',
            1 => 'On',
            2 => 'Off',
            3 => 'Auto',
        },
    },
    FlashFunction => {
        Groups => { 2 => 'Camera' },
        Writable => 'boolean',
    },
    FlashRedEyeMode => {
        Groups => { 2 => 'Camera' },
        Writable => 'boolean',
    },
    FocalLength=> {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
        PrintConv => 'sprintf("%.1f mm",$val)',
        PrintConvInv => '$val=~s/\s*mm$//;$val',
    },
    SubjectArea => {
        Writable => 'integer',
        List => 'Seq',
    },
    FlashEnergy => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
    },
    SpatialFrequencyResponse => {
        Groups => { 2 => 'Camera' },
        SubDirectory => { },
        Struct => 'OECF',
    },
    SpatialFrequencyResponseColumns => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    SpatialFrequencyResponseRows => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    SpatialFrequencyResponseNames => {
        Groups => { 2 => 'Camera' },
        List => 'Seq',
    },
    SpatialFrequencyResponseValues => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
        List => 'Seq',
    },
    FocalPlaneXResolution => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
    },
    FocalPlaneYResolution => {
        Groups => { 2 => 'Camera' },
        Writable => 'rational',
    },
    FocalPlaneResolutionUnit => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            1 => 'None', # (not standard EXIF)
            2 => 'inches',
            3 => 'cm',
            4 => 'mm',   # (not standard EXIF)
            5 => 'um',   # (not standard EXIF)
        },
    },
    SubjectLocation => {
        Writable => 'integer',
        List => 'Seq',
    },
    ExposureIndex => {
        Writable => 'rational',
    },
    SensingMethod => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            1 => 'Not defined',
            2 => 'One-chip color area',
            3 => 'Two-chip color area',
            4 => 'Three-chip color area',
            5 => 'Color sequential area',
            7 => 'Trilinear',
            8 => 'Color sequential linear',
        },
    },
    FileSource => {
        Writable => 'integer',
        PrintConv => {
            1 => 'Film Scanner',
            2 => 'Reflection Print Scanner',
            3 => 'Digital Camera',
        }
    },
    SceneType  => { Writable => 'integer', PrintConv => { 1 => 'Directly photographed' } },
    CFAPattern => {
        SubDirectory => { },
        Struct => 'CFAPattern',
    },
    CFAPatternColumns   => { Writable => 'integer' },
    CFAPatternRows      => { Writable => 'integer' },
    CFAPatternValues    => { List => 'Seq', Writable => 'integer' },
    CustomRendered => {
        Writable => 'integer',
        PrintConv => {
            0 => 'Normal',
            1 => 'Custom',
        },
    },
    ExposureMode => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Auto',
            1 => 'Manual',
            2 => 'Auto bracket',
        },
    },
    WhiteBalance => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Auto',
            1 => 'Manual',
        },
    },
    DigitalZoomRatio => { Writable => 'rational' },
    FocalLengthIn35mmFilm => {
        Name => 'FocalLengthIn35mmFormat',
        Writable => 'integer',
        Groups => { 2 => 'Camera' },
        PrintConv => '"$val mm"',
        PrintConvInv => '$val=~s/\s*mm$//;$val',
    },
    SceneCaptureType => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Standard',
            1 => 'Landscape',
            2 => 'Portrait',
            3 => 'Night',
        },
    },
    GainControl => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'None',
            1 => 'Low gain up',
            2 => 'High gain up',
            3 => 'Low gain down',
            4 => 'High gain down',
        },
    },
    Contrast => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
        },
        PrintConvInv => 'Image::ExifTool::Exif::ConvertParameter($val)',
    },
    Saturation => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Normal',
            1 => 'Low',
            2 => 'High',
        },
        PrintConvInv => 'Image::ExifTool::Exif::ConvertParameter($val)',
    },
    Sharpness => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Normal',
            1 => 'Soft',
            2 => 'Hard',
        },
        PrintConvInv => 'Image::ExifTool::Exif::ConvertParameter($val)',
    },
    DeviceSettingDescription => {
        Groups => { 2 => 'Camera' },
        SubDirectory => { },
        Struct => 'DeviceSettings',
    },
    DeviceSettingDescriptionColumns => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    DeviceSettingDescriptionRows => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
    },
    DeviceSettingDescriptionSettings => {
        Groups => { 2 => 'Camera' },
        List => 'Seq',
    },
    SubjectDistanceRange => {
        Groups => { 2 => 'Camera' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Unknown',
            1 => 'Macro',
            2 => 'Close',
            3 => 'Distant',
        },
    },
    ImageUniqueID   => { },
    GPSVersionID    => { Groups => { 2 => 'Location' } },
    GPSLatitude     => { Groups => { 2 => 'Location' }, %latConv },
    GPSLongitude    => { Groups => { 2 => 'Location' }, %longConv },
    GPSAltitudeRef  => {
        Groups => { 2 => 'Location' },
        Writable => 'integer',
        PrintConv => {
            0 => 'Above Sea Level',
            1 => 'Below Sea Level',
        },
    },
    GPSAltitude => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
        PrintConv => '$val eq "inf" ? $val : "$val m"',
        PrintConvInv => '$val=~s/\s*m$//;$val',
    },
    GPSTimeStamp => {
        Name => 'GPSDateTime',
        Groups => { 2 => 'Time' },
        Notes => q{
            a date/time tag called GPSTimeStamp by the XMP specification.  This tag is
            renamed here to prevent direct copy from EXIF:GPSTimeStamp which is a
            time-only tag.  Instead, the value of this tag should be taken from
            Composite:GPSDateTime when copying from EXIF
        },
        %dateTimeInfo,
    },
    GPSSatellites   => { Groups => { 2 => 'Location' } },
    GPSStatus => {
        Groups => { 2 => 'Location' },
        PrintConv => {
            A => 'Measurement Active',
            V => 'Measurement Void',
        },
    },
    GPSMeasureMode => {
        Groups => { 2 => 'Location' },
        Writable => 'integer',
        PrintConv => {
            2 => '2-Dimensional',
            3 => '3-Dimensional',
        },
    },
    GPSDOP => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSSpeedRef => {
        Groups => { 2 => 'Location' },
        PrintConv => {
            K => 'km/h',
            M => 'mph',
            N => 'knots',
        },
    },
    GPSSpeed => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSTrackRef => {
        Groups => { 2 => 'Location' },
        PrintConv => {
            M => 'Magnetic North',
            T => 'True North',
        },
    },
    GPSTrack => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSImgDirectionRef => {
        PrintConv => {
            M => 'Magnetic North',
            T => 'True North',
        },
    },
    GPSImgDirection => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSMapDatum     => { Groups => { 2 => 'Location' } },
    GPSDestLatitude => { Groups => { 2 => 'Location' }, %latConv },
    GPSDestLongitude=> { Groups => { 2 => 'Location' }, %longConv },
    GPSDestBearingRef => {
        Groups => { 2 => 'Location' },
        PrintConv => {
            M => 'Magnetic North',
            T => 'True North',
        },
    },
    GPSDestBearing => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSDestDistanceRef => {
        Groups => { 2 => 'Location' },
        PrintConv => {
            K => 'Kilometers',
            M => 'Miles',
            N => 'Nautical Miles',
        },
    },
    GPSDestDistance => {
        Groups => { 2 => 'Location' },
        Writable => 'rational',
    },
    GPSProcessingMethod => { Groups => { 2 => 'Location' } },
    GPSAreaInformation  => { Groups => { 2 => 'Location' } },
    GPSDifferential => {
        Groups => { 2 => 'Location' },
        Writable => 'integer',
        PrintConv => {
            0 => 'No Correction',
            1 => 'Differential Corrected',
        },
    },
    NativeDigest => { }, #PH
);

# Auxiliary schema properties (aux) - not fully documented
%Image::ExifTool::XMP::aux = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-aux', 2 => 'Camera' },
    NAMESPACE => 'aux',
    NOTES => 'Photoshop Auxiliary schema tags.',
    Firmware        => { }, #7
    FlashCompensation => { Writable => 'rational' }, #7
    ImageNumber     => { }, #7
    LensInfo        => { }, #7
    Lens            => { },
    OwnerName       => { }, #7
    SerialNumber    => { },
    LensID          => {
        # prevent this from getting set from a LensID that has been converted
        ValueConvInv => q{
            warn "Expected one or more integer values" if $val =~ /[^\d ]/;
            return $val;
        },
    },
);

# IPTC Core schema properties (Iptc4xmpCore)
%Image::ExifTool::XMP::iptcCore = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-iptcCore', 2 => 'Author' },
    NAMESPACE => 'Iptc4xmpCore',
    NOTES => q{
        IPTC Core schema tags.  The actual IPTC Core namespace schema prefix is
        "Iptc4xmpCore", which is the prefix recorded in the file, but ExifTool
        shortens this for the "XMP-iptcCore" family 1 group name.
    },
    CountryCode         => { Groups => { 2 => 'Location' } },
    CreatorContactInfo => {
        SubDirectory => { },
        Struct => 'ContactInfo',
    },
    CreatorContactInfoCiAdrCity   => { Description => 'Creator City' },
    CreatorContactInfoCiAdrCtry   => { Description => 'Creator Country' },
    CreatorContactInfoCiAdrExtadr => { Description => 'Creator Address' },
    CreatorContactInfoCiAdrPcode  => { Description => 'Creator Postal Code' },
    CreatorContactInfoCiAdrRegion => { Description => 'Creator Region' },
    CreatorContactInfoCiEmailWork => { Description => 'Creator Work Email' },
    CreatorContactInfoCiTelWork   => { Description => 'Creator Work Telephone' },
    CreatorContactInfoCiUrlWork   => { Description => 'Creator Work URL' },
    IntellectualGenre   => { Groups => { 2 => 'Other' } },
    Location            => { Groups => { 2 => 'Location' } },
    Scene               => { Groups => { 2 => 'Other' }, List => 'Bag' },
    SubjectCode         => { Groups => { 2 => 'Other' }, List => 'Bag' },
);

# PixelLive schema properties (PixelLive) (ref 3)
%Image::ExifTool::XMP::PixelLive = (
    GROUPS => { 1 => 'XMP-PixelLive', 2 => 'Image' },
    NAMESPACE => 'PixelLive',
    WRITE_PROC => \&WriteXMP,
    NOTES => q{
        PixelLive schema tags.  These tags are not writable becase they are very
        uncommon and I haven't been able to locate a reference which gives the
        namespace URI.
    },
    AUTHOR    => { Name => 'Author',   Avoid => 1, Groups => { 2 => 'Author'} },
    COMMENTS  => { Name => 'Comments', Avoid => 1 },
    COPYRIGHT => { Name => 'Copyright',Avoid => 1, Groups => { 2 => 'Author'} },
    DATE      => { Name => 'Date',     Avoid => 1, Groups => { 2 => 'Time'} },
    GENRE     => { Name => 'Genre',    Avoid => 1 },
    TITLE     => { Name => 'Title',    Avoid => 1 },
);

# Picture Licensing Universal System schema properties (xmpPLUS)
%Image::ExifTool::XMP::xmpPLUS = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-xmpPLUS', 2 => 'Author' },
    NAMESPACE => 'xmpPLUS',
    NOTES => 'XMP Picture Licensing Universal System (PLUS) schema tags.',
    CreditLineReq   => { Writable => 'boolean' },
    ReuseAllowed    => { Writable => 'boolean' },
);

# PLUS License Data Format 1.2.0 (plus) (ref 10)
%Image::ExifTool::XMP::plus = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-plus', 2 => 'Author' },
    NAMESPACE => 'plus',
    NOTES => 'PLUS License Data Format 1.2.0 schema tags.',
    Version  => { Name => 'PLUSVersion' },
    Licensee => {
        SubDirectory => { },
        Struct => 'Licensee',
        List => 'Seq',
    },
    LicenseeLicenseeID   => { Name => 'LicenseeID',   List => 1 },
    LicenseeLicenseeName => { Name => 'LicenseeName', List => 1 },
    EndUser => {
        SubDirectory => { },
        Struct => 'EndUser',
        List => 'Seq',
    },
    EndUserEndUserID    => { Name => 'EndUserID',   List => 1 },
    EndUserEndUserName  => { Name => 'EndUserName', List => 1 },
    Licensor => {
        SubDirectory => { },
        Struct => 'Licensor',
        List => 'Seq',
    },
    LicensorLicensorID              => { Name => 'LicensorID',              List => 1 },
    LicensorLicensorName            => { Name => 'LicensorName',            List => 1 },
    LicensorLicensorStreetAddress   => { Name => 'LicensorStreetAddress',   List => 1 },
    LicensorLicensorExtendedAddress => { Name => 'LicensorExtendedAddress', List => 1 },
    LicensorLicensorCity            => { Name => 'LicensorCity',            List => 1 },
    LicensorLicensorRegion          => { Name => 'LicensorRegion',          List => 1 },
    LicensorLicensorPostalCode      => { Name => 'LicensorPostalCode',      List => 1 },
    LicensorLicensorCountry         => { Name => 'LicensorCountry',         List => 1 },
    LicensorLicensorTelephoneType1  => {
        Name => 'LicensorTelephoneType1',
        List => 1,
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/work'  => 'Work',
            'http://ns.useplus.org/ldf/vocab/cell'  => 'Cell',
            'http://ns.useplus.org/ldf/vocab/fax'   => 'FAX',
            'http://ns.useplus.org/ldf/vocab/home'  => 'Home',
            'http://ns.useplus.org/ldf/vocab/pager' => 'Pager',
        },
    },
    LicensorLicensorTelephone1      => { Name => 'LicensorTelephone1',      List => 1 },
    LicensorLicensorTelephoneType2  => {
        Name => 'LicensorTelephoneType2', 
        List => 1,
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/work'  => 'Work',
            'http://ns.useplus.org/ldf/vocab/cell'  => 'Cell',
            'http://ns.useplus.org/ldf/vocab/fax'   => 'FAX',
            'http://ns.useplus.org/ldf/vocab/home'  => 'Home',
            'http://ns.useplus.org/ldf/vocab/pager' => 'Pager',
        },
    },
    LicensorLicensorTelephone2      => { Name => 'LicensorTelephone2',      List => 1 },
    LicensorLicensorEmail           => { Name => 'LicensorEmail',           List => 1 },
    LicensorLicensorURL             => { Name => 'LicensorURL',             List => 1 },
    LicensorNotes               => { Writable => 'lang-alt' },
    MediaSummaryCode            => { },
    LicenseStartDate            => { Writable => 'date' },
    LicenseEndDate              => { Writable => 'date' },
    MediaConstraints            => { Writable => 'lang-alt' },
    RegionConstraints           => { Writable => 'lang-alt' },
    ProductOrServiceConstraints => { Writable => 'lang-alt' },
    ImageFileConstraints => {
        List => 'Bag',
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/IF-MFN' => 'Maintain File Name',
            'http://ns.useplus.org/ldf/vocab/IF-MID' => 'Maintain ID in File Name',
            'http://ns.useplus.org/ldf/vocab/IF-MMD' => 'Maintain Metadata',
            'http://ns.useplus.org/ldf/vocab/IF-MFT' => 'Maintain File Type',
        },
    },
    ImageAlterationConstraints => {
        List => 'Bag',
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/AL-CRP' => 'No Cropping',
            'http://ns.useplus.org/ldf/vocab/AL-FLP' => 'No Flipping',
            'http://ns.useplus.org/ldf/vocab/AL-RET' => 'No Retouching',
            'http://ns.useplus.org/ldf/vocab/AL-CLR' => 'No Colorization',
            'http://ns.useplus.org/ldf/vocab/AL-DCL' => 'No De-Colorization',
            'http://ns.useplus.org/ldf/vocab/AL-MRG' => 'No Merging',
        },
    },
    ImageDuplicationConstraints => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/DP-NDC' => 'No Duplication Constraints',
            'http://ns.useplus.org/ldf/vocab/DP-LIC' => 'Duplication Only as Necessary Under License',
            'http://ns.useplus.org/ldf/vocab/DP-NOD' => 'No Duplication',
        },
    },
    ModelReleaseStatus => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/MR-NON' => 'None',
            'http://ns.useplus.org/ldf/vocab/MR-NAP' => 'Not Applicable',
            'http://ns.useplus.org/ldf/vocab/MR-UMR' => 'Unlimited Model Releases',
            'http://ns.useplus.org/ldf/vocab/MR-LMR' => 'Limited or Incomplete Model Releases',
        },
    },
    ModelReleaseID      => { List => 'Bag' },
    MinorModelAgeDisclosure => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/AG-UNK' => 'Age Unknown',
            'http://ns.useplus.org/ldf/vocab/AG-A25' => 'Age 25 or Over',
            'http://ns.useplus.org/ldf/vocab/AG-A24' => 'Age 24',
            'http://ns.useplus.org/ldf/vocab/AG-A23' => 'Age 23',
            'http://ns.useplus.org/ldf/vocab/AG-A22' => 'Age 22',
            'http://ns.useplus.org/ldf/vocab/AG-A21' => 'Age 21',
            'http://ns.useplus.org/ldf/vocab/AG-A20' => 'Age 20',
            'http://ns.useplus.org/ldf/vocab/AG-A19' => 'Age 19',
            'http://ns.useplus.org/ldf/vocab/AG-A18' => 'Age 18',
            'http://ns.useplus.org/ldf/vocab/AG-A17' => 'Age 17',
            'http://ns.useplus.org/ldf/vocab/AG-A16' => 'Age 16',
            'http://ns.useplus.org/ldf/vocab/AG-A15' => 'Age 15',
            'http://ns.useplus.org/ldf/vocab/AG-U14' => 'Age 14 or Under',
        },
    },
    PropertyReleaseStatus => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/PR-NON' => 'None',
            'http://ns.useplus.org/ldf/vocab/PR-NAP' => 'Not Applicable',
            'http://ns.useplus.org/ldf/vocab/PR-UPR' => 'Unlimited Property Releases',
            'http://ns.useplus.org/ldf/vocab/PR-LPR' => 'Limited or Incomplete Property Releases',
        },
    },
    PropertyReleaseID   => { List => 'Bag' },
    OtherConstraints    => { Writable => 'lang-alt' },
    CreditLineRequired => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/CR-NRQ' => 'Not Required',
            'http://ns.useplus.org/ldf/vocab/CR-COI' => 'Credit on Image',
            'http://ns.useplus.org/ldf/vocab/CR-CAI' => 'Credit Adjacent To Image',
            'http://ns.useplus.org/ldf/vocab/CR-CCA' => 'Credit in Credits Area',
        },
    },
    AdultContentWarning => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/CW-NRQ' => 'Not Required',
            'http://ns.useplus.org/ldf/vocab/CW-AWR' => 'Adult Content Warning Required',
            'http://ns.useplus.org/ldf/vocab/CW-UNK' => 'Unknown',
        },
    },
    OtherLicenseRequirements    => { Writable => 'lang-alt' },
    TermsAndConditionsText      => { Writable => 'lang-alt' },
    TermsAndConditionsURL       => { },
    OtherConditions             => { Writable => 'lang-alt' },
    ImageType => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/TY-PHO' => 'Photographic Image',
            'http://ns.useplus.org/ldf/vocab/TY-ILL' => 'Illustrated Image',
            'http://ns.useplus.org/ldf/vocab/TY-MCI' => 'Multimedia or Composited Image',
            'http://ns.useplus.org/ldf/vocab/TY-VID' => 'Video',
            'http://ns.useplus.org/ldf/vocab/TY-OTR' => 'Other',
        },
    },
    LicensorImageID     => { },
    FileNameAsDelivered => { },
    ImageFileFormatAsDelivered => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/FF-JPG' => 'JPEG Interchange Formats (JPG, JIF, JFIF)',
            'http://ns.useplus.org/ldf/vocab/FF-TIF' => 'Tagged Image File Format (TIFF)',
            'http://ns.useplus.org/ldf/vocab/FF-GIF' => 'Graphics Interchange Format (GIF)',
            'http://ns.useplus.org/ldf/vocab/FF-RAW' => 'Proprietary RAW Image Format',
            'http://ns.useplus.org/ldf/vocab/FF-DNG' => 'Digital Negative (DNG)',
            'http://ns.useplus.org/ldf/vocab/FF-EPS' => 'Encapsulated PostScript (EPS)',
            'http://ns.useplus.org/ldf/vocab/FF-BMP' => 'Windows Bitmap (BMP)',
            'http://ns.useplus.org/ldf/vocab/FF-PSD' => 'Photoshop Document (PSD)',
            'http://ns.useplus.org/ldf/vocab/FF-PIC' => 'Macintosh Picture (PICT)',
            'http://ns.useplus.org/ldf/vocab/FF-PNG' => 'Portable Network Graphics (PNG)',
            'http://ns.useplus.org/ldf/vocab/FF-WMP' => 'Windows Media Photo (HD Photo)',
            'http://ns.useplus.org/ldf/vocab/FF-OTR' => 'Other',
	    },
    },
    ImageFileSizeAsDelivered => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/SZ-U01' => 'Up to 1 MB',
            'http://ns.useplus.org/ldf/vocab/SZ-U10' => 'Up to 10 MB',
            'http://ns.useplus.org/ldf/vocab/SZ-U30' => 'Up to 30 MB',
            'http://ns.useplus.org/ldf/vocab/SZ-U50' => 'Up to 50 MB',
            'http://ns.useplus.org/ldf/vocab/SZ-G50' => 'Greater than 50 MB',
        },
    },
    CopyrightStatus => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/CS-PRO' => 'Protected',
            'http://ns.useplus.org/ldf/vocab/CS-PUB' => 'Public Domain',
            'http://ns.useplus.org/ldf/vocab/CS-UNK' => 'Unknown',
        },
    },
    CopyrightRegistrationNumber => { },
    FirstPublicationDate        => { Writable => 'date' },
    CopyrightOwner => {
        SubDirectory => { },
        Struct => 'CopyrightOwner',
        List => 'Seq',
    },
    CopyrightOwnerCopyrightOwnerID   => { Name => 'CopyrightOwnerID',   List => 1 },
    CopyrightOwnerCopyrightOwnerName => { Name => 'CopyrightOwnerName', List => 1 },
    CopyrightOwnerImageID            => { },
    ImageCreator => {
        SubDirectory => { },
        Struct => 'ImageCreator',
        List => 'Seq',
    },
    ImageCreatorImageCreatorID   => { Name => 'ImageCreatorID',   List => 1 },
    ImageCreatorImageCreatorName => { Name => 'ImageCreatorName', List => 1 },
    ImageCreatorImageID          => { },
    ImageSupplier => {
        SubDirectory => { },
        Struct => 'ImageSupplier',
        List => 'Seq',
    },
    ImageSupplierImageSupplierID   => { Name => 'ImageSupplierID',   List => 1 },
    ImageSupplierImageSupplierName => { Name => 'ImageSupplierName', List => 1 },
    ImageSupplierImageID    => { },
    LicenseeImageID         => { },
    LicenseeImageNotes      => { Writable => 'lang-alt' },
    OtherImageInfo          => { Writable => 'lang-alt' },
    LicenseID               => { },
    LicensorTransactionID   => { List => 'Bag' },
    LicenseeTransactionID   => { List => 'Bag' },
    LicenseeProjectReference=> { List => 'Bag' },
    LicenseTransactionDate  => { Writable => 'date' },
    Reuse => {
        PrintConv => {
            'http://ns.useplus.org/ldf/vocab/RE-REU' => 'Repeat Use',
            'http://ns.useplus.org/ldf/vocab/RE-NAP' => 'Not Applicable',
        },
    },
    OtherLicenseDocuments   => { List => 'Bag' },
    OtherLicenseInfo        => { Writable => 'lang-alt' },
    # Note: these are Bag's of lang-alt lists -- a nested list tag!
    Custom1     => { List => 'Bag', Writable => 'lang-alt' },
    Custom2     => { List => 'Bag', Writable => 'lang-alt' },
    Custom3     => { List => 'Bag', Writable => 'lang-alt' },
    Custom4     => { List => 'Bag', Writable => 'lang-alt' },
    Custom5     => { List => 'Bag', Writable => 'lang-alt' },
    Custom6     => { List => 'Bag', Writable => 'lang-alt' },
    Custom7     => { List => 'Bag', Writable => 'lang-alt' },
    Custom8     => { List => 'Bag', Writable => 'lang-alt' },
    Custom9     => { List => 'Bag', Writable => 'lang-alt' },
    Custom10    => { List => 'Bag', Writable => 'lang-alt' },
);

# Creative Commons schema properties (cc) (ref 5)
%Image::ExifTool::XMP::cc = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-cc', 2 => 'Author' },
    NAMESPACE => 'cc',
    NOTES => 'Creative Commons schema tags.',
    license => { },
);

# Description Explorer schema properties (dex) (ref 6)
%Image::ExifTool::XMP::dex = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-dex', 2 => 'Image' },
    NAMESPACE => 'dex',
    NOTES => q{
        Description Explorer schema tags.  These tags are not very common.  The
        Source and Rating tags are avoided when writing due to name conflicts with
        other XMP tags.
    },
    crc32       => { Name => 'CRC32', Writable => 'integer' },
    source      => { Avoid => 1 },
    shortdescription => {
        Name => 'ShortDescription',
        Writable => 'lang-alt',
    },
    licensetype => {
        Name => 'LicenseType',
        PrintConv => {
            unknown        => 'Unknown',
            shareware      => 'Shareware',
            freeware       => 'Freeware',
            adware         => 'Adware',
            demo           => 'Demo',
            commercial     => 'Commercial',
           'public domain' => 'Public Domain',
           'open source'   => 'Open Source',
        },
    },
    revision    => { },
    rating      => { Avoid => 1 },
    os          => { Name => 'OS', Writable => 'integer' },
    ffid        => { Name => 'FFID' },
);

# IView MediaPro schema properties (mediapro) (ref PH)
%Image::ExifTool::XMP::MediaPro = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-mediapro', 2 => 'Image' },
    NAMESPACE => 'mediapro',
    NOTES => 'IView MediaPro schema tags.',
    Event       => { },
    Location    => {
        Avoid => 1,
        Groups => { 2 => 'Location' },
        Notes => 'avoided due to conflict with XMP-iptcCore:Location',
    },
    Status      => { },
    People      => { List => 'Bag' },
    UserFields  => { List => 'Bag' },
    CatalogSets => { List => 'Bag' },
);

# Microsoft Photo schema properties (MicrosoftPhoto) (ref PH)
%Image::ExifTool::XMP::Microsoft = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-microsoft', 2 => 'Image' },
    NAMESPACE => 'MicrosoftPhoto',
    NOTES => q{
        Microsoft Photo schema tags.  This is likely not a complete list, but
        represents tags which have been observed in sample images.  The actual
        namespace prefix is "MicrosoftPhoto", but ExifTool shortens this to
        "XMP-microsoft" in the family 1 group name.
    },
    CameraSerialNumber => { },
    DateAcquired       => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    FlashManufacturer  => { },
    FlashModel         => { },
    LastKeywordIPTC    => { List => 'Bag' },
    LastKeywordXMP     => { List => 'Bag' },
    LensManufacturer   => { },
    LensModel          => { },
    Rating => {
        Name => 'RatingPercent',
        Notes => q{
            normal Rating values of 1,2,3,4 and 5 stars correspond to RatingPercent
            values of 1,25,50,75 and 99 respectively
        },
    },
);

# Adobe Lightroom schema properties (lr) (ref PH)
%Image::ExifTool::XMP::Lightroom = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-lr', 2 => 'Image' },
    NAMESPACE => 'lr',
    NOTES => 'Adobe Lightroom "lr" schema tags.',
    privateRTKInfo => { },
    hierarchicalSubject => { List => 'Bag' },
);

# DICOM schema properties (DICOM) (ref PH, written by CS3)
%Image::ExifTool::XMP::DICOM = (
    %xmpTableDefaults,
    GROUPS => { 1 => 'XMP-DICOM', 2 => 'Image' },
    NAMESPACE => 'DICOM',
    NOTES => 'DICOM schema tags.',
    # change some tag names to correspond with DICOM tags
    PatientName             => { Name => 'PatientsName' },
    PatientID               => { },
    PatientSex              => { Name => 'PatientsSex' },
    PatientDOB              => {
        Name => 'PatientsBirthDate',
        Groups => { 2 => 'Time' },
        %dateTimeInfo,
    },
    StudyID                 => { },
    StudyPhysician          => { },
    StudyDateTime           => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    StudyDescription        => { },
    SeriesNumber            => { },
    SeriesModality          => { },
    SeriesDateTime          => { Groups => { 2 => 'Time' }, %dateTimeInfo },
    SeriesDescription       => { },
    EquipmentInstitution    => { },
    EquipmentManufacturer   => { },
);

# SVG schema properties (ref 9)
%Image::ExifTool::XMP::SVG = (
    GROUPS => { 0 => 'SVG', 1 => 'SVG', 2 => 'Image' },
    NAMESPACE => 'svg',
    LANG_INFO => \&GetLangInfo,
    NOTES => q{
        SVG (Scalable Vector Graphics) image tags.  By default, only the top-level
        SVG and Metadata tags are extracted from these images, but all graphics tags
        may be extracted by setting the Unknown option to 2 (-U on the command
        line).  The SVG tags are not part of XMP as such, but are included with the
        XMP module for convenience.
    },
    version    => 'SVGVersion',
    id         => 'ID',
    metadataId => 'MetadataID',
    width      => 'ImageWidth',
    height     => 'ImageHeight',
);

# table to add tags in other namespaces
%Image::ExifTool::XMP::otherSVG = (
    GROUPS => { 0 => 'SVG', 2 => 'Unknown' },
    LANG_INFO => \&GetLangInfo,
);

# table to add tags in other namespaces
%Image::ExifTool::XMP::other = (
    GROUPS => { 2 => 'Unknown' },
    LANG_INFO => \&GetLangInfo,
);

# Composite XMP tags
%Image::ExifTool::XMP::Composite = (
    # get latitude/logitude reference from XMP lat/long tags
    # (used to set EXIF GPS position from XMP tags)
    GPSLatitudeRef => {
        Require => {
            0 => 'XMP:GPSLatitude',
        },
        ValueConv => '$val[0] < 0 ? "S" : "N"',
        PrintConv => {
            N => 'North',
            S => 'South',
        },
    },
    GPSLongitudeRef => {
        Require => {
            0 => 'XMP:GPSLongitude',
        },
        ValueConv => '$val[0] < 0 ? "W" : "E"',
        PrintConv => {
            E => 'East',
            W => 'West',
        },
    },
);

# add our composite tags
Image::ExifTool::AddCompositeTags('Image::ExifTool::XMP');

#------------------------------------------------------------------------------
# AutoLoad our writer routines when necessary
#
sub AUTOLOAD
{
    return Image::ExifTool::DoAutoLoad($AUTOLOAD, @_);
}

#------------------------------------------------------------------------------
# Escape necessary XML characters in UTF-8 string
# Inputs: 0) string to be escaped
# Returns: escaped string
my %charName = ('"'=>'quot', '&'=>'amp', "'"=>'#39', '<'=>'lt', '>'=>'gt');
sub EscapeXML($)
{
    my $str = shift;
    $str =~ s/([&><'"])/&$charName{$1};/sg; # escape necessary XML characters
    return $str;
}

#------------------------------------------------------------------------------
# Unescape XML character references (entities and numerical)
# Inputs: 0) string to be unescaped
#         1) optional hash reference to convert entity names to numbers
# Returns: unescaped string
my %charNum = ('quot'=>34, 'amp'=>38, 'apos'=>39, 'lt'=>60, 'gt'=>62);
sub UnescapeXML($;$)
{
    my ($str, $conv) = @_;
    $conv = \%charNum unless $conv;
    $str =~ s/&(#?\w+);/UnescapeChar($1,$conv)/sge;
    return $str;
}

#------------------------------------------------------------------------------
# Convert XML character reference to UTF-8
# Inputs: 0) XML character reference stripped of the '&' and ';' (ie. 'quot', '#34', '#x22')
#         1) hash reference for looking up character numbers by name
# Returns: UTF-8 equivalent (or original character on conversion error)
sub UnescapeChar($$)
{
    my ($ch, $conv) = @_;
    my $val = $$conv{$ch};
    unless (defined $val) {
        if ($ch =~ /^#x([0-9a-fA-F]+)$/) {
            $val = hex($1);
        } elsif ($ch =~ /^#(\d+)$/) {
            $val = $1;
        } else {
            return "&$ch;"; # should issue a warning here?
        }
    }
    if ($val < 0x80) {
        return chr($val);   # simple ASCII
    } elsif ($] >= 5.006001) {
        return pack('C0U', $val);
    } else {
        return Image::ExifTool::PackUTF8($val);
    }
}

#------------------------------------------------------------------------------
# Utility routine to decode a base64 string
# Inputs: 0) base64 string
# Returns:   reference to decoded data
sub DecodeBase64($)
{
    local($^W) = 0; # unpack('u',...) gives bogus warning in 5.00[123]
    my $str = shift;

    # truncate at first unrecognized character (base 64 data
    # may only contain A-Z, a-z, 0-9, +, /, =, or white space)
    $str =~ s/[^A-Za-z0-9+\/= \t\n\r\f].*//s;
    # translate to uucoded and remove padding and white space
    $str =~ tr/A-Za-z0-9+\/= \t\n\r\f/ -_/d;

    # convert the data to binary in chunks
    my $chunkSize = 60;
    my $uuLen = pack('c', 32 + $chunkSize * 3 / 4); # calculate length byte
    my $dat = '';
    my ($i, $substr);
    # loop through the whole chunks
    my $len = length($str) - $chunkSize;
    for ($i=0; $i<=$len; $i+=$chunkSize) {
        $substr = substr($str, $i, $chunkSize);     # get a chunk of the data
        $dat .= unpack('u', $uuLen . $substr);      # decode it
    }
    $len += $chunkSize;
    # handle last partial chunk if necessary
    if ($i < $len) {
        $uuLen = pack('c', 32 + ($len-$i) * 3 / 4); # recalculate length
        $substr = substr($str, $i, $len-$i);        # get the last partial chunk
        $dat .= unpack('u', $uuLen . $substr);      # decode it
    }
    return \$dat;
}

#------------------------------------------------------------------------------
# Generate a name for this XMP tag
# Inputs: 0) reference to tag property name list
# Returns: tagID and outtermost interesting namespace
sub GetXMPTagID($)
{
    my $props = shift;
    my ($tag, $prop, $namespace);
    foreach $prop (@$props) {
        # split name into namespace and property name
        # (Note: namespace can be '' for property qualifiers)
        my ($ns, $nm) = ($prop =~ /(.*?):(.*)/) ? ($1, $2) : ('', $prop);
        $nm =~ s/ .*//;     # remove nodeID if it exists
        if ($ignoreNamespace{$ns}) {
            # special case: don't ignore rdf numbered items
            next unless $prop =~ /^rdf:(_\d+)$/;
            $tag .= $1;
        } else {
            # all uppercase is ugly, so convert it
            if ($nm !~ /[a-z]/) {
                my $xlatNS = $$xlatNamespace{$ns} || $ns;
                my $info = $Image::ExifTool::XMP::Main{$xlatNS};
                my $table;
                if (ref $info eq 'HASH' and $info->{SubDirectory}) {
                    $table = GetTagTable($info->{SubDirectory}->{TagTable});
                }
                unless ($table and $table->{$nm}) {
                    $nm = lc($nm);
                    $nm =~ s/_([a-z])/\u$1/g;
                }
            }
            if (defined $tag) {
                $tag .= ucfirst($nm);       # add to tag name
            } else {
                $tag = $nm;
            }
        }
        # save namespace of first property to contribute to tag name
        $namespace = $ns unless $namespace;
    }
    if (wantarray) {
        return ($tag, $namespace);
    } else {
        return $tag;
    }
}

#------------------------------------------------------------------------------
# Get localized version of tagInfo hash
# Inputs: 0) tagInfo hash ref, 1) language code (ie. "x-default")
# Returns: new tagInfo hash ref, or undef if invalid
sub GetLangInfo($$)
{
    my ($tagInfo, $langCode) = @_;
    # only allow alternate language tags in lang-alt lists
    return undef unless $$tagInfo{Writable} and $$tagInfo{Writable} eq 'lang-alt';
    $langCode =~ tr/_/-/;   # RFC 3066 specifies '-' as a separator
    return Image::ExifTool::GetLangInfo($tagInfo, $langCode);
}

#------------------------------------------------------------------------------
# Get standard case for language code
# Inputs: 0) Language code
# Returns: Language code in standard case
sub StandardLangCase($)
{
    my $lang = shift;
    # make 2nd subtag uppercase only if it is 2 letters
    return lc($1) . uc($2) . lc($3) if $lang =~ /^([a-z]{2,3}|[xi])(-[a-z]{2})\b(.*)/i;
    return lc($lang);
}

#------------------------------------------------------------------------------
# Scan for XMP in a file
# Inputs: 0) ExifTool object ref, 1) RAF reference
# Returns: 1 if xmp was found, 0 otherwise
# Notes: Currently only recognizes UTF8-encoded XMP
sub ScanForXMP($$)
{
    my ($exifTool, $raf) = @_;
    my ($buff, $xmp);
    my $lastBuff = '';

    $exifTool->VPrint(0,"Scanning for XMP\n");
    for (;;) {
        defined $buff or $raf->Read($buff, 65536) or return 0;
        unless (defined $xmp) {
            $lastBuff .= $buff;
            unless ($lastBuff =~ /(<\?xpacket begin=)/g) {
                # must keep last 15 bytes to match 16-byte "xpacket begin" string
                $lastBuff = length($buff) <= 15 ? $buff : substr($buff, -15);
                undef $buff;
                next;
            }
            $xmp = $1;
            $buff = substr($lastBuff, pos($lastBuff));
        }
        $xmp .= $buff;
        my $pos = length($xmp) - length($buff) - 18; # 18 is length("<xpacket end...")-1
        pos($xmp) = $pos if $pos > 0;
        if ($xmp =~ /<\?xpacket end=['"][wr]['"]\?>/g) {
            $xmp = substr($xmp, 0, pos($xmp));
            # XMP is not valid if it contains null bytes
            pos($xmp) = 0;
            last unless $xmp =~ /\0/g;
            my $null = pos $xmp;
            while ($xmp =~ /\0/g) {
                $null = pos($xmp);
            }
            # re-parse beginning after last null byte
            $buff = substr($xmp, $null);
            $lastBuff = '';
            undef $xmp;
        } else {
            undef $buff;
        }
    }
    unless ($exifTool->{VALUE}->{FileType}) {
        $exifTool->{FILE_TYPE} = $exifTool->{FILE_EXT};
        $exifTool->SetFileType('<unknown file containing XMP>');
    }
    my %dirInfo = (
        DataPt => \$xmp,
        DirLen => length $xmp,
        DataLen => length $xmp,
    );
    ProcessXMP($exifTool, \%dirInfo);
    return 1;
}

#------------------------------------------------------------------------------
# Convert XMP date/time to EXIF format
# Inputs: 0) XMP date/time string, 1) set if we aren't sure this is a date
# Returns: EXIF date/time
sub ConvertXMPDate($;$)
{
    my ($val, $unsure) = @_;
    if ($val =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}:\d{2})(:\d{2})?(\S*)$/) {
        my $s = $5 || ':00';        # seconds may be missing
        $val = "$1:$2:$3 $4$s$6";   # convert back to EXIF time format
    } elsif (not $unsure and $val =~ /^(\d{4})(-\d{2}){0,2}/) {
        $val =~ tr/-/:/;
    }
    return $val;
}

#------------------------------------------------------------------------------
# We found an XMP property name/value
# Inputs: 0) ExifTool object ref, 1) Pointer to tag table
#         2) reference to array of XMP property names (last is current property)
#         3) property value, 4) xml:lang attribute (or undef)
# Returns: 1 if valid tag was found
sub FoundXMP($$$$;$)
{
    local $_;
    my ($exifTool, $tagTablePtr, $props, $val, $lang) = @_;

    my ($tag, $namespace) = GetXMPTagID($props);
    return 0 unless $tag;   # ignore things that aren't valid tags

    # translate namespace if necessary
    $namespace = $$xlatNamespace{$namespace} if $$xlatNamespace{$namespace};
    my $info = $tagTablePtr->{$namespace};
    my $table;
    if ($info) {
        $table = $info->{SubDirectory}->{TagTable} or warn "Missing TagTable for $tag!\n";
    } elsif ($$props[0] eq 'svg:svg') {
        if (not $namespace) {
            # disambiguate MetadataID by adding back the 'metadata' we ignored
            $tag = 'metadataId' if $tag eq 'id' and $$props[1] eq 'svg:metadata';
            # use SVG namespace in SVG files if nothing better to use
            $table = 'Image::ExifTool::XMP::SVG';
        } elsif (not grep /^rdf:/, @$props) {
            # only other SVG information if not inside RDF (call it XMP if in RDF)
            $table = 'Image::ExifTool::XMP::otherSVG';
        }
    }
    $table or $table = 'Image::ExifTool::XMP::other';

    # change pointer to the table for this namespace
    $tagTablePtr = GetTagTable($table);

    # look up this tag in the appropriate table
    my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);

    unless ($tagInfo) {
        if ($exifTool->{OPTIONS}->{Verbose}) {
            my $group1 = $namespace ? "XMP-$namespace" : $tagTablePtr->{GROUPS}->{1};
            $exifTool->VPrint(0, $exifTool->{INDENT}, "[adding $group1:$tag]\n");
        }
        # construct tag information for this unknown tag
        $tagInfo = { Name => ucfirst($tag), WasAdded => 1 };
        # make this a List type if necessary and not lang-alt
        $$tagInfo{List} = $1 if @$props > 2 and not $lang and
            $$props[-1] =~ /^rdf:li \d+$/ and $$props[-2] =~ /^rdf:(Bag|Seq|Alt)/;
        Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
    }
    if (defined $lang and lc($lang) ne 'x-default') {
        $lang = StandardLangCase($lang);
        my $langInfo = GetLangInfo($tagInfo, $lang);
        $tagInfo = $langInfo if $langInfo;
    }
    if ($exifTool->{OPTIONS}->{Charset} ne 'UTF8' and $val =~ /[\x80-\xff]/) {
        # convert from UTF-8 to specified characterset
        $val = $exifTool->UTF82Charset($val);
    }
    # convert rational and date values to a more sensible format
    my $fmt = $$tagInfo{Writable};
    my $new = $$tagInfo{WasAdded};
    if ($fmt or $new) {
        if (($new or $fmt eq 'rational') and $val =~ m{^(-?\d+)/(-?\d+)$}) {
            $val = $1 / $2 if $2;       # calculate quotient
        } elsif ($new or $fmt eq 'date') {
            $val = ConvertXMPDate($val, $new);
        }
    }
    $tag = $exifTool->FoundTag($tagInfo, UnescapeXML($val));
    $exifTool->SetGroup1($tag, "$tagTablePtr->{GROUPS}->{0}-$namespace") if $namespace;

    if ($exifTool->Options('Verbose')) {
        my $tagID = join('/',@$props);
        $exifTool->VerboseInfo($tagID, $tagInfo, Value=>$val);
    }
    return 1;
}

#------------------------------------------------------------------------------
# Recursively parse nested XMP data element
# Inputs: 0) ExifTool object reference
#         1) Pointer to tag table
#         2) reference to XMP data
#         3) start of xmp element
#         4) reference to array of enclosing XMP property names (undef if none)
#         5) reference to blank node information hash
# Returns: Number of contained XMP elements
sub ParseXMPElement($$$;$$$)
{
    my ($exifTool, $tagTablePtr, $dataPt, $start, $propListPt, $blankInfo) = @_;
    my $count = 0;
    my $isWriting = $exifTool->{XMP_CAPTURE};
    my $isSVG = $$exifTool{XMP_IS_SVG};

    $start or $start = 0;
    $propListPt or $propListPt = [ ];

    my $processBlankInfo;
    # create empty blank node information hash if necessary
    $blankInfo or $blankInfo = $processBlankInfo = { Prop => { } };
    # keep track of current nodeID at this nesting level
    my $oldNodeID = $$blankInfo{NodeID};

    pos($$dataPt) = $start;
    Element: for (;;) {
        # reset nodeID before processing each element
        my $nodeID = $$blankInfo{NodeID} = $oldNodeID;
        # get next element
        last unless $$dataPt =~ m/<([\w:-]+)(.*?)>/sg;
        my ($prop, $attrs) = ($1, $2);
        my $val = '';
        # only look for closing token if this is not an empty element
        # (empty elements end with '/', ie. <a:b/>)
        if ($attrs !~ s/\/$//) {
            my $nesting = 1;
            for (;;) {
# this match fails with perl 5.6.2 (perl bug!), but it works without
# the '(.*?)', so do it the hard way instead...
#                $$dataPt =~ m/(.*?)<\/$prop>/sg or last Element;
#                my $val2 = $1;
                my $pos = pos($$dataPt);
                $$dataPt =~ m/<\/$prop>/sg or last Element;
                my $len = pos($$dataPt) - $pos - length($prop) - 3;
                my $val2 = substr($$dataPt, $pos, $len);
                # increment nesting level for each contained similar opening token
                ++$nesting while $val2 =~ m/<$prop\b.*?(\/?)>/sg and $1 ne '/';
                $val .= $val2;
                --$nesting or last;
                $val .= "</$prop>";
            }
        }
        if ($prop eq 'rdf:li') {
            # add index to list items so we can keep them in order
            # (this also enables us to keep structure elements grouped properly
            # for lists of structures, like JobRef)
            $prop .= sprintf(' %.3d', $count);
        } elsif ($prop eq 'rdf:Description') {
            # trim comments and whitespace from rdf:Description properties only
            $val =~ s/<!--.*?-->//g;
            $val =~ s/^\s*(.*)\s*$/$1/;
        } elsif ($prop eq 'xmp:xmpmeta') {
            # patch MicrosoftPhoto unconformity
            $prop = 'x:xmpmeta';
        }

        # extract property attributes
        my (%attrs, @attrs);
        while ($attrs =~ m/(\S+?)=(['"])(.*?)\2/sg) {
            push @attrs, $1;    # preserve order
            $attrs{$1} = $3;
        }

        # add nodeID to property path (with leading ' #') if it exists
        if (defined $attrs{'rdf:nodeID'}) {
            $nodeID = $$blankInfo{NodeID} = $attrs{'rdf:nodeID'};
            delete $attrs{'rdf:nodeID'};
            $prop .= ' #' . $nodeID;
        }

        # push this property name onto our hierarchy list
        push @$propListPt, $prop;

        if ($isSVG) {
            # ignore everything but top level SVG tags and metadata unless Unknown set
            unless ($exifTool->{OPTIONS}->{Unknown} > 1 or $exifTool->{OPTIONS}->{Verbose}) {
                if (@$propListPt > 1 and $$propListPt[1] !~ /\b(metadata|desc|title)$/) {
                    pop @$propListPt;
                    next;
                }
            }
            if ($prop eq 'svg' or $prop eq 'metadata') {
                # add svg namespace prefix if missing to ignore these entries in the tag name
                $$propListPt[-1] = "svg:$prop";
            }
        }

        # handle properties inside element attributes (RDF shorthand format):
        # (attributes take the form a:b='c' or a:b="c")
        my ($shortName, $shorthand, $ignored);
        foreach $shortName (@attrs) {
            my $propName = $shortName;
            my ($ns, $name);
            if ($propName =~ /(.*?):(.*)/) {
                $ns = $1;   # specified namespace
                $name = $2;
            } elsif ($prop =~ /(\S*?):/) {
                $ns = $1;   # assume same namespace as parent
                $name = $propName;
                $propName = "$ns:$name";    # generate full property name
            } else {
                # a property qualifier is the only property name that may not
                # have a namespace, and a qualifier shouldn't have attributes,
                # but what the heck, let's allow this anyway
                $ns = '';
                $name = $propName;
            }
            # keep track of the namespace prefixes used
            if ($ns eq 'xmlns') {
                my $stdNS = $uri2ns{$attrs{$shortName}};
                # translate namespace if non-standard (except 'x' and 'iX')
                if ($stdNS and $name ne $stdNS and $stdNS ne 'x' and $stdNS ne 'iX') {
                    # make a copy of the standard translations so we can modify it
                    $xlatNamespace = { %stdXlatNS } if $xlatNamespace eq \%stdXlatNS;
                    # translate this namespace prefix to the standard version
                    $$xlatNamespace{$name} = $stdXlatNS{$stdNS} || $stdNS;
                }
            }
            if ($isWriting) {
                # keep track of our namespaces when writing
                if ($ns eq 'xmlns') {
                    my $stdNS = $uri2ns{$attrs{$shortName}};
                    unless ($stdNS and ($stdNS eq 'x' or $stdNS eq 'iX')) {
                        my $nsUsed = $exifTool->{XMP_NS};
                        $$nsUsed{$name} = $attrs{$shortName} unless defined $$nsUsed{$name};
                    }
                    next;
                } elsif ($recognizedAttrs{$propName}) {
                    # save UUID to use same ID when writing
                    if ($propName eq 'rdf:about') {
                        if (not $exifTool->{XMP_UUID}) {
                            $exifTool->{XMP_UUID} = $attrs{$shortName};
                        } elsif ($exifTool->{XMP_UUID} ne $attrs{$shortName}) {
                            $exifTool->Error("Multiple XMP UUID's not handled", 1);
                        }
                    }
                    next;
                }
            }
            if ($ignoreNamespace{$ns}) {
                $ignored = $propName;
                next;
            }
            my $shortVal = $attrs{$shortName};
            delete $attrs{$shortName};  # don't re-use this attribute
            push @$propListPt, $propName;
            # save this shorthand XMP property
            if (defined $nodeID) {
                SaveBlankInfo($blankInfo, $propListPt, $shortVal);
            } elsif ($isWriting) {
                CaptureXMP($exifTool, $propListPt, $shortVal);
            } else {
                FoundXMP($exifTool, $tagTablePtr, $propListPt, $shortVal);
            }
            pop @$propListPt;
            $shorthand = 1;
        }
        if ($isWriting) {
            if (ParseXMPElement($exifTool, $tagTablePtr, \$val, 0, $propListPt, $blankInfo)) {
                # undefine value since we found more properties within this one
                undef $val;
                # set an error on any ignored attributes here, because they will be lost
                $exifTool->{XMP_ERROR} = "Can't handle XMP attribute '$ignored'" if $ignored;
            }
            if (defined $val and (length $val or not $shorthand)) {
                if (defined $nodeID) {
                    SaveBlankInfo($blankInfo, $propListPt, $val, \%attrs);
                } else {
                    CaptureXMP($exifTool, $propListPt, $val, \%attrs);
                }
            }
        } else {
            # if element value is empty, take value from 'resource' attribute
            # (preferentially) or 'about' attribute (if no 'resource')
            my $wasEmpty;
            if ($val eq '' and ($attrs =~ /\bresource=(['"])(.*?)\1/ or
                                $attrs =~ /\babout=(['"])(.*?)\1/))
            {
                $val = $2;
                $wasEmpty = 1;
            }
            # look for additional elements contained within this one
            if (!ParseXMPElement($exifTool, $tagTablePtr, \$val, 0, $propListPt, $blankInfo)) {
                # there are no contained elements, so this must be a simple property value
                # (unless we already extracted shorthand values from this element)
                if (length $val or not $shorthand) {
                    if (defined $nodeID) {
                        SaveBlankInfo($blankInfo, $propListPt, $val);
                    } elsif ($$propListPt[-1] eq 'rdf:type' and $wasEmpty) {
                        # do not extract empty structure types (for now)
                    } else {
                        FoundXMP($exifTool, $tagTablePtr, $propListPt, $val, $attrs{'xml:lang'});
                    }
                }
            }
        }
        pop @$propListPt;
        ++$count;
    }
#
# process resources referenced by blank nodeID's
#
    if ($processBlankInfo and %{$$blankInfo{Prop}}) {
        ProcessBlankInfo($exifTool, $tagTablePtr, $blankInfo, $isWriting);
        %$blankInfo = ();   # free some memory
    }
    return $count;  # return the number of elements found at this level
}

#------------------------------------------------------------------------------
# Process XMP data
# Inputs: 0) ExifTool object reference, 1) DirInfo reference, 2) Pointer to tag table
# Returns: 1 on success
# Notes: The following flavours of XMP files are currently recognized:
# - standard XMP with xpacket, x:xmpmeta and rdf:RDF elements
# - XMP that is missing the xpacket and/or x:xmpmeta elements
# - mutant Microsoft XMP with xmp:xmpmeta element
# - XML files beginning with "<xml"
# - SVG files that begin with "<svg" or "<!DOCTYPE svg"
# - XMP and XML files beginning with a UTF-8 byte order mark
# - UTF-8, UTF-16 and UTF-32 encoded XMP
# - erroneously double-UTF8 encoded XMP
# - otherwise valid files with leading XML comment
sub ProcessXMP($$;$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my ($dirStart, $dirLen, $dataLen);
    my ($buff, $fmt, $isXML, $isRDF, $isSVG);
    my $rtnVal = 0;
    my $bom = 0;

    if ($dataPt) {
        $dirStart = $$dirInfo{DirStart} || 0;
        $dirLen = $$dirInfo{DirLen} || (length($$dataPt) - $dirStart);
        $dataLen = $$dirInfo{DataLen} || length($$dataPt);
    } else {
        # read information from XMP file
        my $raf = $$dirInfo{RAF} or return 0;
        $raf->Read($buff, 256) or return 0;
        my ($buf2, $buf3, $double);
        ($buf2 = $buff) =~ tr/\0//d;    # cheap conversion to UTF-8
        # remove leading comments if they exist (ie. ImageIngester)
        while ($buf2 =~ /^<!--/) {
            # remove the comment if it is complete
            if ($buf2 =~ s/^<!--.*?-->\s+//s) {
                # continue with parsing if we have more than 128 bytes remaining
                next if length $buf2 > 128;
            } else {
                # don't read more than 10k when looking for the end of comment
                return 0 if length($buf2) > 10000;
            }
            $raf->Read($buf3, 256) or last; # read more data if available
            $buff .= $buf3;
            $buf3 =~ tr/\0//d;
            $buf2 .= $buf3;
        }
        # check to see if this is XMP format
        # (CS2 writes .XMP files without the "xpacket begin")
        unless ($buf2 =~ /^(<\?xpacket begin=|<x(mp)?:x[ma]pmeta)/) {
            # also recognize XML files and .XMP files with BOM and without x:xmpmeta
            if ($buf2 =~ /^(\xfe\xff)(<\?xml|<rdf:RDF|<x(mp)?:x[ma]pmeta)/g) {
                $fmt = 'n';     # UTF-16 or 32 MM with BOM
            } elsif ($buf2 =~ /^(\xff\xfe)(<\?xml|<rdf:RDF|<x(mp)?:x[ma]pmeta)/g) {
                $fmt = 'v';     # UTF-16 or 32 II with BOM
            } elsif ($buf2 =~ /^(\xef\xbb\xbf)?(<\?xml|<rdf:RDF|<x(mp)?:x[ma]pmeta)/g) {
                $fmt = 0;       # UTF-8 with BOM or unknown encoding without BOM
            } elsif ($buf2 =~ /^(\xfe\xff|\xff\xfe|\xef\xbb\xbf)(<\?xpacket begin=)/g) {
                $double = $1;   # double-encoded UTF
            } else {
                return 0;       # not recognized XMP or XML
            }
            $bom = 1 if $1;
            if ($2 eq '<?xml') {
                unless ($buf2 =~ /<x(mp)?:x[ma]pmeta/) {
                    # identify SVG images by DOCTYPE if available
                    if ($buf2 =~ /<!DOCTYPE\s+(\w+)/) {
                        return 0 unless $1 eq 'svg';
                        $isSVG = 1;
                    } elsif ($buf2 =~ /<svg[\s>]/) {
                        $isSVG = 1;
                    } elsif ($buf2 =~ /<rdf:RDF/) {
                        $isRDF = 1;
                    }
                    if ($isSVG and $exifTool->{XMP_CAPTURE}) {
                        $exifTool->Error("ExifTool does not yet support writing of SVG images");
                        return 0;
                    }
                }
                $isXML = 1;
            } elsif ($2 eq '<rdf:RDF') {
                $isRDF = 1;     # recognize XMP without x:xmpmeta element
            }
            if ($buff =~ /^\0\0/) {
                $fmt = 'N';     # UTF-32 MM with or without BOM
            } elsif ($buff =~ /^..\0\0/) {
                $fmt = 'V';     # UTF-32 II with or without BOM
            } elsif (not $fmt) {
                if ($buff =~ /^\0/) {
                    $fmt = 'n'; # UTF-16 MM without BOM
                } elsif ($buff =~ /^.\0/) {
                    $fmt = 'v'; # UTF-16 II without BOM
                }
            }
        }
        $raf->Seek(0, 2) or return 0;
        my $size = $raf->Tell() or return 0;
        $raf->Seek(0, 0) or return 0;
        $raf->Read($buff, $size) == $size or return 0;
        # decode the first layer of double-encoded UTF text
        if ($double) {
            $buff = substr($buff, length $double);  # remove leading BOM
            Image::ExifTool::SetWarning(undef);     # clear old warning
            local $SIG{'__WARN__'} = \&Image::ExifTool::SetWarning;
            my $tmp;
            # assume that character data has been re-encoded in UTF, so re-pack
            # as characters and look for warnings indicating a false assumption
            if ($double eq "\xef\xbb\xbf") {
                $tmp = Image::ExifTool::UTF82Unicode($buff, 'C');
            } else {
                my $fmt = ($double eq "\xfe\xff") ? 'n' : 'v';
                $tmp = pack('C*', unpack("$fmt*",$buff));
            }
            if (Image::ExifTool::GetWarning()) {
                $exifTool->Warn('Superfluous BOM at start of XMP');
            } else {
                $exifTool->Warn('XMP is double UTF-encoded');
                $buff = $tmp;   # use the decoded XMP
            }
            $size = length $buff;
        }
        $dataPt = \$buff;
        $dirStart = 0;
        $dirLen = $dataLen = $size;
        $exifTool->SetFileType($isSVG ? 'SVG' : undef);
    }

    # take substring if necessary
    if ($dataLen != $dirStart + $dirLen) {
        $buff = substr($$dataPt, $dirStart, $dirLen);
        $dataPt = \$buff;
        $dirStart = 0;
    }
    # extract XMP as a block if specified
    if ($exifTool->{REQ_TAG_LOOKUP}->{xmp} and not $isSVG) {
        $exifTool->FoundTag('XMP', substr($$dataPt, $dirStart, $dirLen));
    }
    if ($exifTool->Options('Verbose') and not $exifTool->{XMP_CAPTURE}) {
        $exifTool->VerboseDir($isSVG ? 'SVG' : 'XMP', 0, $dirLen);
    }
#
# convert UTF-16 or UTF-32 encoded XMP to UTF-8 if necessary
#
    my $begin = '<?xpacket begin=';
    pos($$dataPt) = $dirStart;
    delete $$exifTool{XMP_IS_XML};
    delete $$exifTool{XMP_IS_SVG};
    if ($isXML or $isRDF) {
        $$exifTool{XMP_IS_XML} = $isXML;
        $$exifTool{XMP_IS_SVG} = $isSVG;
        $$exifTool{XMP_NO_XPACKET} = 1 + $bom;
    } elsif ($$dataPt =~ /\G\Q$begin\E/gc) {
        delete $$exifTool{XMP_NO_XPACKET};
    } elsif ($$dataPt =~ /<x(mp)?:x[ma]pmeta/gc) {
        $$exifTool{XMP_NO_XPACKET} = 1 + $bom;
    } else {
        delete $$exifTool{XMP_NO_XPACKET};
        # check for UTF-16 encoding (insert one \0 between characters)
        $begin = join "\0", split //, $begin;
        # must reset pos because it was killed by previous unsuccessful //g match
        pos($$dataPt) = $dirStart;
        if ($$dataPt =~ /\G(\0)?\Q$begin\E\0./g) {
            # validate byte ordering by checking for U+FEFF character
            if ($1) {
                # should be big-endian since we had a leading \0
                $fmt = 'n' if $$dataPt =~ /\G\xfe\xff/g;
            } else {
                $fmt = 'v' if $$dataPt =~ /\G\0\xff\xfe/g;
            }
        } else {
            # check for UTF-32 encoding (with three \0's between characters)
            $begin =~ s/\0/\0\0\0/g;
            pos($$dataPt) = $dirStart;
            if ($$dataPt !~ /\G(\0\0\0)?\Q$begin\E\0\0\0./g) {
                $fmt = 0;   # set format to zero as indication we didn't find encoded XMP
            } elsif ($1) {
                # should be big-endian
                $fmt = 'N' if $$dataPt =~ /\G\0\0\xfe\xff/g;
            } else {
                $fmt = 'V' if $$dataPt =~ /\G\0\0\0\xff\xfe\0\0/g;
            }
        }
        defined $fmt or $exifTool->Warn('XMP character encoding error');
    }
    if ($fmt) {
        # translate into UTF-8
        if ($] >= 5.006001) {
            $buff = pack('C0U*', unpack("x$dirStart$fmt*",$$dataPt));
        } else {
            $buff = Image::ExifTool::PackUTF8(unpack("x$dirStart$fmt*",$$dataPt));
        }
        $dataPt = \$buff;
        $dirStart = 0;
    }
    # initialize namespace translation
    $xlatNamespace = \%stdXlatNS;

    # avoid scanning for XMP later in case ScanForXMP is set
    $$exifTool{FoundXMP} = 1;

    # parse the XMP
    $tagTablePtr or $tagTablePtr = GetTagTable('Image::ExifTool::XMP::Main');
    $rtnVal = 1 if ParseXMPElement($exifTool, $tagTablePtr, $dataPt, $dirStart);

    # return DataPt if successful in case we want it for writing
    $$dirInfo{DataPt} = $dataPt if $rtnVal and $$dirInfo{RAF};

    return $rtnVal;
}


1;  #end

__END__

=head1 NAME

Image::ExifTool::XMP - Read XMP meta information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

XMP stands for Extensible Metadata Platform.  It is a format based on XML
that Adobe developed for embedding metadata information in image files.
This module contains the definitions required by Image::ExifTool to read XMP
information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.adobe.com/products/xmp/pdfs/xmpspec.pdf>

=item L<http://www.w3.org/TR/rdf-syntax-grammar/>

=item L<http://www.portfoliofaq.com/pfaq/v7mappings.htm>

=item L<http://www.iptc.org/IPTC4XMP/>

=item L<http://creativecommons.org/technology/xmp>

=item L<http://www.optimasc.com/products/fileid/xmp-extensions.pdf>

=item L<http://www.w3.org/TR/SVG11/>

=item L<http://ns.useplus.org/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/XMP Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
