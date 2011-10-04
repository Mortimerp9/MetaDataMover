#------------------------------------------------------------------------------
# File:         PDF.pm
#
# Description:  Read PDF meta information
#
# Revisions:    07/11/2005 - P. Harvey Created
#               07/25/2005 - P. Harvey Add support for encrypted documents
#
# References:   1) http://partners.adobe.com/public/developer/pdf/index_reference.html
#               2) http://search.cpan.org/dist/Crypt-RC4/
#------------------------------------------------------------------------------

package Image::ExifTool::PDF;

use strict;
use vars qw($VERSION $AUTOLOAD);
use Image::ExifTool qw(:DataAccess :Utils);
require Exporter;

$VERSION = '1.15';

sub FetchObject($$$$);
sub ExtractObject($$;$$);
sub ReadToNested($;$);
sub ProcessDict($$$$;$$);
sub ReadPDFValue($);
sub CheckPDF($$$);

my $cryptInfo;      # encryption object reference (plus additional information)
my $lastFetched;    # last fetched object reference (used for decryption)
my %warnedOnce;     # hash of warnings we issued
my %streamObjs;     # hash of stream objects
my %fetched;        # dicts fetched in verbose mode (to avoid cyclical recursion)
my $pdfVer;         # version of PDF file being processed

# tags in main PDF directories
%Image::ExifTool::PDF::Main = (
    VARS => { CAPTURE => ['Main','Prev'] },
    Info => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Info',
        },
    },
    Root => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Root',
        },
    },
);

# tags in PDF Info directory
%Image::ExifTool::PDF::Info = (
    GROUPS => { 2 => 'Image' },
    VARS => { CAPTURE => ['Info'] },
    EXTRACT_UNKNOWN => 1, # extract all unknown tags in this directory
    WRITE_PROC => \&Image::ExifTool::DummyWriteProc,
    CHECK_PROC => \&CheckPDF,
    WRITABLE => 'string',
    NOTES => q{
        As well as the tags listed below, the PDF specification allows for
        user-defined tags to exist in the Info dictionary.  These tags, which should
        have corresponding XMP-pdfx entries in the XMP of the PDF XML Metadata
        object, are also extracted by ExifTool.

        B<Writable> specifies the value format, and may be C<string>, C<date>,
        C<integer>, C<real>, C<boolean> or C<name> for PDF tags.
    },
    Title       => { },
    Author      => { Groups => { 2 => 'Author' } },
    Subject     => { },
    Keywords    => { List => 'string' },  # this is a string list
    Creator     => { },
    Producer    => { },
    CreationDate => {
        Name => 'CreateDate',
        Writable => 'date',
        Groups => { 2 => 'Time' },
        Shift => 'Time',
        PrintConv => '$self->ConvertDateTime($val)',
        PrintConvInv => '$self->InverseDateTime($val)', 
    },
    ModDate => {
        Name => 'ModifyDate',
        Writable => 'date',
        Groups => { 2 => 'Time' },
        Shift => 'Time',
        PrintConv => '$self->ConvertDateTime($val)',
        PrintConvInv => '$self->InverseDateTime($val)', 
    },
    Trapped => {
        Writable => 0,
        # remove leading '/' from '/True' or '/False'
        ValueConv => '$val=~s{^/}{}; $val',
        ValueConvInv => '"/$val"',
    },
    'AAPL:Keywords' => { #PH
        Name => 'AppleKeywords',
        List => 'array', # this is an array of values
        Notes => q{
            keywords written by Apple utilities, although they seem to use PDF:Keywords
            when reading
        },
    },
);

# tags in the PDF Root document catalog
%Image::ExifTool::PDF::Root = (
    # note: can't capture previous versions of Root since they are not parsed
    VARS => { CAPTURE => ['Root'] },
    NOTES => 'This is the PDF document catalog.',
    Metadata => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Metadata',
        },
    },
    Pages => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Pages',
        },
    },
    Version => 'PDFVersion',
);

# tags in PDF Pages directory
%Image::ExifTool::PDF::Pages = (
    GROUPS => { 2 => 'Image' },
    Count => 'PageCount',
    Kids => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Kids',
        },
    },
);

# tags in PDF Kids directory
%Image::ExifTool::PDF::Kids = (
    Metadata => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Metadata',
        },
    },
    PieceInfo => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::PieceInfo',
        },
    },
    Resources => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Resources',
        },
    },
);

# tags in PDF Resources directory
%Image::ExifTool::PDF::Resources = (
    ColorSpace => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::ColorSpace',
        },
    },
);

# tags in PDF ColorSpace directory
%Image::ExifTool::PDF::ColorSpace = (
    DefaultRGB => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::DefaultRGB',
        },
    },
);

# tags in PDF DefaultRGB directory
%Image::ExifTool::PDF::DefaultRGB = (
    ICCBased => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::ICCBased',
        },
    },
);

# tags in PDF ICCBased directory
%Image::ExifTool::PDF::ICCBased = (
    _stream => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::ICC_Profile::Main',
        },
    },
);

# tags in PDF PieceInfo directory
%Image::ExifTool::PDF::PieceInfo = (
    AdobePhotoshop => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::AdobePhotoshop',
        },
    },
);

# tags in PDF AdobePhotoshop directory
%Image::ExifTool::PDF::AdobePhotoshop = (
    Private => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::Private',
        },
    },
);

# tags in PDF Private directory
%Image::ExifTool::PDF::Private = (
    ImageResources => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::PDF::ImageResources',
        },
    },
);

# tags in PDF ImageResources directory
%Image::ExifTool::PDF::ImageResources = (
    _stream => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::Photoshop::Main',
        },
    },
);

# tags in PDF Metadata directory
%Image::ExifTool::PDF::Metadata = (
    GROUPS => { 2 => 'Image' },
    XML_stream => { # this is the stream for a Subtype /XML dictionary (not a real tag)
        Name => 'XMP',
        SubDirectory => {
            TagTable => 'Image::ExifTool::XMP::Main',
        },
    },
);

# unknown tags for use in verbose option
%Image::ExifTool::PDF::Unknown = (
    GROUPS => { 2 => 'Unknown' },
);

#------------------------------------------------------------------------------
# AutoLoad our writer routines when necessary
#
sub AUTOLOAD
{
    return Image::ExifTool::DoAutoLoad($AUTOLOAD, @_);
}

#------------------------------------------------------------------------------
# Issue one warning of each type
# Inputs: 0) ExifTool object reference, 1) warning
sub WarnOnce($$)
{
    my ($exifTool, $warn) = @_;
    unless ($warnedOnce{$warn}) {
        $warnedOnce{$warn} = 1;
        $exifTool->Warn($warn);
    }
}

#------------------------------------------------------------------------------
# Convert PDFDocEncoding characters to Unicode
# Inputs: 0) PDF text string, 1) Unicode pack format (n,N,v or V)
# Returns: Unicode string
my %pdf2unicode = (
    0x18 => 0x02d8,    0x82 => 0x2021,    0x8c => 0x201e,    0x96 => 0x0152,
    0x19 => 0x02c7,    0x83 => 0x2026,    0x8d => 0x201c,    0x97 => 0x0160,
    0x1a => 0x02c6,    0x84 => 0x2014,    0x8e => 0x201d,    0x98 => 0x0178,
    0x1b => 0x02d9,    0x85 => 0x2013,    0x8f => 0x2018,    0x99 => 0x017d,
    0x1c => 0x02dd,    0x86 => 0x0192,    0x90 => 0x2019,    0x9a => 0x0131,
    0x1d => 0x02db,    0x87 => 0x2044,    0x91 => 0x201a,    0x9b => 0x0142,
    0x1e => 0x02da,    0x88 => 0x2039,    0x92 => 0x2122,    0x9c => 0x0153,
    0x1f => 0x02dc,    0x89 => 0x203a,    0x93 => 0xfb01,    0x9d => 0x0161,
    0x80 => 0x2022,    0x8a => 0x2212,    0x94 => 0xfb02,    0x9e => 0x017e,
    0x81 => 0x2020,    0x8b => 0x2030,    0x95 => 0x0141,    0xa0 => 0x20ac,
);
sub PDF2Unicode($$)
{
    local $_;
    my ($val, $fmt) = @_;
    my @pdf = unpack('C*',$val);
    foreach (@pdf) {
        next unless $pdf2unicode{$_};
        $_ = $pdf2unicode{$_};
    }
    # repack as a Unicode string
    return pack("$fmt*", @pdf);
}

#------------------------------------------------------------------------------
# Convert from PDF to EXIF-style date/time
# Inputs: 0) PDF date/time string (D:yyyymmddhhmmss+hh'mm')
# Returns: EXIF date string (yyyy:mm:dd hh:mm:ss+hh:mm)
sub ConvertPDFDate($)
{
    my $date = shift;
    # remove optional 'D:' prefix
    $date =~ s/^D://;
    # fill in default values if necessary
    #              yyyymmddhhmmss
    my $default = '00000101000000';
    if (length $date < length $default) {
        $date .= substr($default, length $date);
    }
    $date =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(.*)/ or return $date;
    $date = "$1:$2:$3 $4:$5:$6";
    if ($7) {
        my @t = split /'/, $7;
        $date .= $t[0];
        $date .= ':' . ($t[1] || 0) if $t[0] ne 'Z';
    }
    return $date;
}

#------------------------------------------------------------------------------
# Locate any object in the XRef tables (including compressed objects)
# Inputs: 0) XRef reference, 1) object reference string (or free object number)
# Returns: offset to object in file or compressed object reference string,
#          0 if object is free, or undefined on error
sub LocateAnyObject($$)
{
    my ($xref, $ref) = @_;
    return undef unless $xref;
    return $$xref{$ref} if exists $$xref{$ref};
    # get the object number
    return undef unless $ref =~ /^(\d+)/;
    my $objNum = $1;
    # return 0 if the object number has been reused (old object is free)
    return 0 if defined $$xref{$objNum};
#
# scan our XRef stream dictionaries for this object
#
    return undef unless $$xref{dicts};
    my $dict;
    foreach $dict (@{$$xref{dicts}}) {
        # quick check to see if the object is in the range for this xref stream
        next if $objNum >= $$dict{Size};
        my $index = $$dict{Index};
        next if $objNum < $$index[0];
        # scan the tables for the specified object
        my $size = $$dict{_entry_size};
        my $num = scalar(@$index) / 2;
        my $tot = 0;
        my $i;
        for ($i=0; $i<$num; ++$i) {
            my $start = $$index[$i*2];
            my $count = $$index[$i*2+1];
            # table is in ascending order, so quit if we have passed the object
            last if $objNum < $start;
            if ($objNum < $start + $count) {
                my $offset = $size * ($objNum - $start + $tot);
                last if $offset + $size > length $$dict{_stream};
                my @c = unpack("x$offset C$size", $$dict{_stream});
                # extract values from this table entry
                # (can be 1, 2, 3, 4, etc.. bytes per value)
                my (@t, $j, $k);
                my $w = $$dict{W};
                for ($j=0; $j<3; ++$j) {
                    # use default value if W entry is 0 (as per spec)
                    $$w[$j] or $t[$j] = ($j ? 1 : 0), next;
                    $t[$j] = shift(@c);
                    for ($k=1; $k < $$w[$j]; ++$k) {
                        $t[$j] = 256 * $t[$j] + shift(@c);
                    }
                }
                # by default, use "o g R" as the xref key
                # (o = object number, g = generation number)
                my $ref2 = "$objNum $t[2] R";
                if ($t[0] == 1) {
                    # normal object reference:
                    # $t[1]=offset of object from start, $t[2]=generation number
                    $$xref{$ref2} = $t[1];
                } elsif ($t[0] == 2) {
                    # compressed object reference:
                    # $t[1]=stream object number, $t[2]=index of object in stream
                    $ref2 = "$objNum 0 R";
                    $$xref{$ref2} = "I$t[2] $t[1] 0 R";
                } elsif ($t[0] == 0) {
                    # free object:
                    # $t[1]=next free object in linked list, $t[2]=generation number
                    $$xref{$ref2} = 0;
                } else {
                    # treat as a null object
                    $$xref{$ref2} = undef;
                }
                $$xref{$objNum} = $t[1];    # remember offsets by object number too
                return $$xref{$ref} if $ref eq $ref2;
                return 0;   # object is free or was reused
            }
            $tot += $count;
        }
    }
    return undef;
}

#------------------------------------------------------------------------------
# Locate a regular object in the XRef tables (does not include compressed objects)
# Inputs: 0) XRef reference, 1) object reference string (or free object number)
# Returns: offset to object in file, 0 if object is free,
#          or undef on error or if object was compressed
sub LocateObject($$)
{
    my ($xref, $ref) = @_;
    my $offset = LocateAnyObject($xref, $ref);
    return undef if $offset and $offset =~ /^I/;
    return $offset;
}

#------------------------------------------------------------------------------
# Fetch indirect object from file (from inside a stream if required)
# Inputs: 0) ExifTool object reference, 1) object reference string,
#         2) xref lookup, 3) object name (for warning messages)
# Returns: object data or undefined on error
sub FetchObject($$$$)
{
    my ($exifTool, $ref, $xref, $tag) = @_;
    $lastFetched = $ref;    # save this for decoding if necessary
    my $offset = LocateAnyObject($xref, $ref);
    unless ($offset) {
        $exifTool->Warn("Bad $tag reference") unless defined $offset;
        return undef;
    }
    my ($data, $obj);
    if ($offset =~ s/^I(\d+) //) {
        my $index = $1; # object index in stream
        my ($objNum) = split ' ', $ref; # save original object number
        $ref = $offset; # now a reference to the containing stream object
        $obj = $streamObjs{$ref};
        unless ($obj) {
            # don't try to load the same object stream twice
            return undef if defined $obj;
            $streamObjs{$ref} = '';
            # load the parent object stream
            $obj = FetchObject($exifTool, $ref, $xref, $tag);
            # make sure it contains everything we need
            return undef unless defined $obj and ref($obj) eq 'HASH';
            return undef unless $$obj{First} and $$obj{N};
            return undef unless DecodeStream($exifTool, $obj);
            # add a special '_table' entry to this dictionary which contains
            # the list of object number/offset pairs from the stream header
            my $num = $$obj{N} * 2;
            my @table = split ' ', $$obj{_stream}, $num;
            return undef unless @table == $num;
            # remove everything before first object in stream
            $$obj{_stream} = substr($$obj{_stream}, $$obj{First});
            $table[$num-1] =~ s/^(\d+).*/$1/;  # trim excess from last number
            $$obj{_table} = \@table;
            # save the object stream so we don't have to re-load it later
            $streamObjs{$ref} = $obj;
        }
        # verify that we have the specified object
        my $i = 2 * $index;
        my $table = $$obj{_table};
        unless ($index < $$obj{N} and $$table[$i] == $objNum) {
            $exifTool->Warn("Bad index for stream object $tag");
            return undef;
        }
        # extract the object at the specified index in the stream
        # (offsets in table are in sequential order, so we can subract from
        #  the next offset to get the object length)
        $offset = $$table[$i + 1];
        my $len = ($$table[$i + 3] || length($$obj{_stream})) - $offset;
        $data = substr($$obj{_stream}, $offset, $len);
        return ExtractObject($exifTool, \$data);
    }
    my $raf = $exifTool->{RAF};
    $raf->Seek($offset, 0) or $exifTool->Warn("Bad $tag offset"), return undef;
    # verify that we are reading the expected object
    $raf->ReadLine($data) or $exifTool->Warn("Error reading $tag data"), return undef;
    ($obj = $ref) =~ s/R/obj/;
    unless ($data =~ s/^$obj//) {
        $exifTool->Warn("$tag object ($obj) not found at $offset");
        return undef;
    }
    return ExtractObject($exifTool, \$data, $raf, $xref);
}

#------------------------------------------------------------------------------
# Convert PDF value to something readable
# Inputs: 0) PDF object data
# Returns: converted object
sub ReadPDFValue($)
{
    my $str = shift;
    # decode all strings in an array
    if (ref $str eq 'ARRAY') {
        # create new list to not alter the original data when rewriting
        my ($val, @vals);
        foreach $val (@$str) {
            push @vals, ReadPDFValue($val);
        }
        return \@vals;
    }
    length $str or return $str;
    my $delim = substr($str, 0, 1);
    if ($delim eq '(') {    # literal string
        $str = $1 if $str =~ /.*?\((.*)\)/s;    # remove brackets
        # decode escape sequences in literal strings
        while ($str =~ /\\(.)/sg) {
            my $n = pos($str) - 2;
            my $c = $1;
            my $r;
            if ($c =~ /[0-7]/) {
                # get up to 2 more octal digits
                $c .= $1 if $str =~ /\G([0-7]{1,2})/g;
                # convert octal escape code
                $r = chr(oct($c) & 0xff);
            } elsif ($c eq "\x0d") {
                # the string is continued if the line ends with '\'
                # (also remove "\x0d\x0a")
                $c .= $1 if $str =~ /\G(\x0a)/g;
                $r = '';
            } elsif ($c eq "\x0a") {
                $r = '';
            } else {
                # convert escaped characters
                ($r = $c) =~ tr/nrtbf/\n\r\t\b\f/;
            }
            substr($str, $n, length($c)+1) = $r;
            # continue search after this character
            pos($str) = $n + length($r);
        }
        Crypt(\$str, $lastFetched) if $cryptInfo;
    } elsif ($delim eq '<') {   # hex string
        # decode hex data
        $str =~ tr/0-9A-Fa-f//dc;
        $str .= '0' if length($str) & 0x01; # (by the spec)
        $str = pack('H*', $str);
        Crypt(\$str, $lastFetched) if $cryptInfo;
    } elsif ($delim eq '/') {   # name
        $str = substr($str, 1);
        # convert escape codes (PDF 1.2 or later)
        $str =~ s/#([0-9a-f]{2})/chr(hex($1))/sgei if $pdfVer >= 1.2;
    }
    return $str;
}

#------------------------------------------------------------------------------
# Extract PDF object from combination of buffered data and file
# Inputs: 0) ExifTool object reference, 1) data reference,
#         2) optional raf reference, 3) optional xref table
# Returns: converted PDF object or undef on error
#          a) dictionary object --> hash reference
#          b) array object --> array reference
#          c) indirect reference --> scalar reference
#          d) string, name, integer, boolean, null --> scalar value
# - updates $$dataPt on return to contain unused data
# - creates two bogus entries ('_stream' and '_tags') in dictionaries to represent
#   the stream data and a list of the tags (not including '_stream' and '_tags')
#   in their original order
sub ExtractObject($$;$$)
{
    my ($exifTool, $dataPt, $raf, $xref) = @_;
    my (@tags, $data, $objData);
    my $dict = { };
    my $delim;

    for (;;) {
        if ($$dataPt =~ /^\s*(<{1,2}|\[|\()/s) {
            $delim = $1;
            $objData = ReadToNested($dataPt, $raf);
            return undef unless defined $objData;
            last;
        } elsif ($$dataPt =~ s{^\s*(\S[^[(/<>\s]*)\s*}{}s) {
#
# extract boolean, numerical, string, name, null object or indirect reference
#
            $objData = $1;
            # look for an indirect reference
            if ($objData =~ /^\d+$/ and $$dataPt =~ s/^(\d+)\s+R//s) {
                $objData .= "$1 R";
                $objData = \$objData;   # return scalar reference
            }
            return $objData;    # return simple scalar or scalar reference
        }
        $raf and $raf->ReadLine($data) or return undef;
        $$dataPt .= $data;
    }
#
# return literal string or hex string without parsing
#
    if ($delim eq '(' or $delim eq '<') {
        return $objData;
#
# extract array
#
    } elsif ($delim eq '[') {
        $objData =~ /.*?\[(.*)\]/s or return;
        my $data = $1;    # brackets removed
        my @list;
        for (;;) {
            last unless $data =~ m{\s*(\S[^[(/<>\s]*)}sg;
            my $val = $1;
            if ($val =~ /^(<{1,2}|\[|\()/) {
                my $pos = pos($data) - length($val);
                # nested dict, array, literal string or hex string
                my $buff = substr($data, $pos);
                $val = ReadToNested(\$buff);
                last unless defined $val;
                pos($data) = $pos + length($val);
                $val = ExtractObject($exifTool, \$val);
            } elsif ($val =~ /^\d/) {
                my $pos = pos($data);
                if ($data =~ /\G\s+(\d+)\s+R/g) {
                    $val = \ "$val $1 R";   # make a reference
                } else {
                    pos($data) = $pos;
                }
            }
            push @list, $val;
        }
        return \@list;
    }
#
# extract dictionary
#
    # Note: entries are not necessarily separated by whitespace (doh!)
    # ie) "/Tag/Name", "/Tag(string)", "/Tag[array]", etc are legal!
    # Also, they may be separated by a comment (ie. "/Tag%comment\nValue"),
    # but comments have already been removed
    while ($objData =~ m{(\s*)/([^/[\]()<>{}\s]+)\s*(\S[^[(/<>\s]*)}sg) {
        my $tag = $2;
        my $val = $3;
        if ($val =~ /^(<{1,2}|\[|\()/) {
            # nested dict, array, literal string or hex string
            $objData = substr($objData, pos($objData)-length($val));
            $val = ReadToNested(\$objData, $raf);
            last unless defined $val;
            $val = ExtractObject($exifTool, \$val);
            pos($objData) = 0;
        } elsif ($val =~ /^\d/) {
            my $pos = pos($objData);
            if ($objData =~ /\G\s+(\d+)\s+R/sg) {
                $val = \ "$val $1 R";   # make a reference
            } else {
                pos($objData) = $pos;
            }
        }
        if ($$dict{$tag}) {
            # duplicate dictionary entries are not allowed
            $exifTool->Warn('Duplicate $tag entry in dictionary (ignored)');
        } else {
            # save the entry
            push @tags, $tag;
            $$dict{$tag} = $val;
        }
    }
    return undef unless @tags;
    $$dict{_tags} = \@tags;
    return $dict unless $raf;   # direct objects can not have streams
#
# extract the stream object
#
    # dictionary must specify stream Length
    my $length = $$dict{Length} or return $dict;
    if (ref $length) {
        $length = $$length;
        my $oldpos = $raf->Tell();
        # get the location of the object specifying the length
        # (compressed objects are not allowd)
        my $offset = LocateObject($xref, $length) or return $dict;
        $offset or $exifTool->Warn('Bad Length object'), return $dict;
        $raf->Seek($offset, 0) or $exifTool->Warn('Bad Length offset'), return $dict;
        # verify that we are reading the expected object
        $raf->ReadLine($data) or $exifTool->Warn('Error reading Length data'), return $dict;
        $length =~ s/R/obj/;
        unless ($data =~ /^$length/) {
            $exifTool->Warn("Length object ($length) not found at $offset");
            return $dict;
        }
        $raf->ReadLine($data) or $exifTool->Warn('Error reading stream Length'), return $dict;
        $data =~ /(\d+)/ or $exifTool->Warn('Stream length not found'), return $dict;
        $length = $1;
        $raf->Seek($oldpos, 0); # restore position to start of stream
    }
    # extract the trailing stream data
    for (;;) {
        # find the stream token
        if ($$dataPt =~ /(\S+)/) {
            last unless $1 eq 'stream';
            # read an extra line because it may contain our \x0a
            $$dataPt .= $data if $raf->ReadLine($data);
            # remove our stream header
            $$dataPt =~ s/^\s*stream(\x0a|\x0d\x0a)//s;
            my $more = $length - length($$dataPt);
            if ($more > 0) {
                unless ($raf->Read($data, $more) == $more) {
                    $exifTool->Warn('Error reading stream data');
                    $$dataPt = '';
                    return $dict;
                }
                $$dict{_stream} = $$dataPt . $data;
                $$dataPt = '';
            } elsif ($more < 0) {
                $$dict{_stream} = substr($$dataPt, 0, $length);
                $$dataPt = substr($$dataPt, $length);
            } else {
                $$dict{_stream} = $$dataPt;
                $$dataPt = '';
            }
            last;
        }
        $raf->ReadLine($data) or last;
        $$dataPt .= $data;
    }
    return $dict;
}

#------------------------------------------------------------------------------
# Read to nested delimiter
# Inputs: 0) data reference, 1) optional raf reference
# Returns: data up to and including matching delimiter (or undef on error)
# - updates data reference with trailing data
# - unescapes characters in literal strings
sub ReadToNested($;$)
{
    my ($dataPt, $raf) = @_;
    # matching closing delimiters
    my %closingDelim = (
        '<<' => '>>',
        '('  => ')',
        '['  => ']',
        '<'  => '>',
    );
    my @delim = ('');   # closing delimiter list, most deeply nested first
    pos($$dataPt) = 0;  # begin at start of data
    for (;;) {
        unless ($$dataPt =~ /(\\*)(\(|\)|<{1,2}|>{1,2}|\[|\]|%)/g) {
            # must read some more data
            my $buff;
            last unless $raf and $raf->ReadLine($buff);
            $$dataPt .= $buff;
            pos($$dataPt) = length($$dataPt) - length($buff);
            next;
        }
        # are we in a literal string?
        if ($delim[0] eq ')') {
            # ignore escaped delimiters (preceeded by odd number of \'s)
            next if length($1) & 0x01;
            # ignore all delimiters but unescaped braces
            next unless $2 eq '(' or $2 eq ')';
        } elsif ($2 eq '%') {
            # ignore the comment
            my $pos = pos($$dataPt) - 1;
            # remove everything from '%' up to but not including newline
            $$dataPt =~ /.*/g;
            my $end = pos($$dataPt);
            $$dataPt = substr($$dataPt, 0, $pos) . substr($$dataPt, $end);
            pos($$dataPt) = $pos;
            next;
        }
        if ($closingDelim{$2}) {
            # push the corresponding closing delimiter
            unshift @delim, $closingDelim{$2};
            next;
        }
        unless ($2 eq $delim[0]) {
            # handle the case where we find a ">>>" and interpret it
            # as ">> >" instead of "> >>"
            next unless $2 eq '>>' and $delim[0] eq '>';
            pos($$dataPt) = pos($$dataPt) - 1;
        }
        my $delim = shift @delim;   # remove from nesting list
        next if $delim[0];          # keep going if we have more nested delimiters
        my $pos = pos($$dataPt);
        my $buff = substr($$dataPt, 0, $pos);
        $$dataPt = substr($$dataPt, $pos);
        return $buff;   # success!
    }
    return undef;   # didn't find matching delimiter
}

#------------------------------------------------------------------------------
# Decode filtered stream
# Inputs: 0) ExifTool object reference, 1) dictionary reference
# Returns: true if stream has been decoded OK
sub DecodeStream($$)
{
    my ($exifTool, $dict) = @_;

    return 0 unless $$dict{_stream}; # no stream to decode
    # apply decryption first if required
    if ($cryptInfo and not $$dict{_decrypted}) {
        $$dict{_decrypted} = 1;
        CryptStream($dict, $lastFetched);
    }
    return 1 unless $$dict{Filter};
    if ($$dict{Filter} eq '/FlateDecode') {
        if (eval 'require Compress::Zlib') {
            my $inflate = Compress::Zlib::inflateInit();
            my ($buff, $stat);
            $inflate and ($buff, $stat) = $inflate->inflate($$dict{_stream});
            if ($inflate and $stat == Compress::Zlib::Z_STREAM_END()) {
                $$dict{_stream} = $buff;
                # move Filter to prevent double decoding
                $$dict{_oldFilter} = $$dict{Filter};
                $$dict{Filter} = '';
            } else {
                $exifTool->Warn('Error inflating stream');
                return 0;
            }
        } else {
            WarnOnce($exifTool,'Install Compress::Zlib to process filtered streams');
            return 0;
        }
#
# apply anti-predictor if necessary
#
        return 1 unless $$dict{DecodeParms};
        my $pre = $dict->{DecodeParms}->{Predictor};
        return 1 unless $pre and $pre != 1;
        if ($pre != 12) {
            # currently only support 'up' prediction
            WarnOnce($exifTool,"FlateDecode Predictor $pre not currently supported");
            return 0;
        }
        my $cols = $dict->{DecodeParms}->{Columns};
        unless ($cols) {
            # currently only support 'up' prediction
            WarnOnce($exifTool,'No Columns for decoding stream');
            return 0;
        }
        my @bytes = unpack('C*', $$dict{_stream});
        my @pre = (0) x $cols;  # initialize predictor array
        my $buff = '';
        while (@bytes > $cols) {
            unless (($_ = shift @bytes) == 2) {
                WarnOnce($exifTool, "Unsupported PNG filter $_"); # (yes, PNG)
                return 0;
            }
            foreach (@pre) {
                $_ = ($_ + shift(@bytes)) & 0xff;
            }
            $buff .= pack('C*', @pre);
        }
        $$dict{_stream} = $buff;
    } else {
        WarnOnce($exifTool, "Unsupported Filter $$dict{Filter}");
        return 0;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Initialize state for RC4 en/decryption (ref 2)
# Inputs: 0) RC4 key string
# Returns: RC4 key hash reference
sub RC4Init($)
{
    my @key = unpack('C*', shift);
    my @state = (0 .. 255);
    my ($i, $j) = (0, 0);
    while ($i < 256) {
        my $st = $state[$i];
        $j = ($j + $st + $key[$i % scalar(@key)]) & 0xff;
        $state[$i++] = $state[$j];
        $state[$j] = $st;
    }
    return { State => \@state, XY => [ 0, 0 ] };
}

#------------------------------------------------------------------------------
# Apply RC4 en/decryption (ref 2)
# Inputs: 0) data reference, 1) RC4 key hash reference or RC4 key string
# - can call this method directly with a key string, or with with the key
#   reference returned by RC4Init
# - RC4 is a symmetric algorithm, so encryption is the same as decryption
sub RC4Crypt($$)
{
    my ($dataPt, $key) = @_;
    $key = RC4Init($key) unless ref $key eq 'HASH';
    my $state = $$key{State};
    my ($x, $y) = @{$$key{XY}};

    my @data = unpack('C*', $$dataPt);
    foreach (@data) {
         $x = ($x + 1) & 0xff;
         my $stx = $$state[$x];
         $y = ($stx + $y) & 0xff;
         my $sty = $$state[$x] = $$state[$y];
         $$state[$y] = $stx;
         $_ ^= $$state[($stx + $sty) & 0xff];
     }
     $$key{XY} = [ $x, $y ];
     $$dataPt = pack('C*', @data);
}

#------------------------------------------------------------------------------
# Initialize decryption
# Inputs: 0) ExifTool object reference, 1) Encrypt dictionary reference,
#         2) ID from file trailer dictionary
# Returns: error string or undef on success (and generates Encryption tag)
sub DecryptInit($$$)
{
    my ($exifTool, $encrypt, $id) = @_;
    unless ($encrypt and ref $encrypt eq 'HASH') {
        return 'Error loading Encrypt object';
    }
    my $filt = $$encrypt{Filter};
    unless ($filt and $filt =~ s/^\///) {
        return 'Encrypt dictionary has no Filter!';
    }
    my $ver = $$encrypt{V} || 0;
    my $rev = $$encrypt{R} || 0;
    $exifTool->FoundTag('Encryption', "$filt v$ver.$rev");
    unless ($$encrypt{Filter} eq '/Standard') {
        $$encrypt{Filter} =~ s/^\///;
        return "PDF '$$encrypt{Filter}' encryption not currently supported";
    }
    unless ($$encrypt{O} and $$encrypt{P} and $$encrypt{U}) {
        return 'Incomplete Encrypt specification';
    }
    unless ($ver == 1 or $ver == 2) {
        return "Encryption algorithm $ver currently not supported";
    }
    $id or return "Can't decrypt (no document ID)";
    unless (eval 'require Digest::MD5') {
        return 'Install Digest::MD5 to process encrypted PDF';
    }
    # calculate file-level en/decryption key
    my $pad = "\x28\xBF\x4E\x5E\x4E\x75\x8A\x41\x64\x00\x4E\x56\xFF\xFA\x01\x08".
              "\x2E\x2E\x00\xB6\xD0\x68\x3E\x80\x2F\x0C\xA9\xFE\x64\x53\x69\x7A";
    my $o = ReadPDFValue($$encrypt{O});
    my $key = $pad . $o . pack('V', $$encrypt{P}) . $id;
    my $rep = 1;
    $$encrypt{meta} = 1; # set flag that Metadata is encrypted
    if ($rev >= 3) {
        # in rev 4 (not yet supported), metadata streams may not be encrypted
        if ($$encrypt{EncryptMetadata} and $$encrypt{EncryptMetadata} =~ /false/i) {
            delete $$encrypt{meta};     # Meta data isn't encrypted after all
            $key .= "\xff\xff\xff\xff"; # must add this if metadata not encrypted
        }
        $rep += 50; # repeat MD5 50 more times if revision is 3 or greater
    }
    my ($len, $i);
    if ($ver == 1) {
        $len = 5;
    } else {
        $len = $$encrypt{Length} || 40;
        $len >= 40 or return 'Bad Encrypt Length';
        $len = int($len / 8);
    }
    for ($i=0; $i<$rep; ++$i) {
        $key = substr(Digest::MD5::md5($key), 0, $len);
    }
    # decrypt U to see if a user password is required
    my $u = ReadPDFValue($$encrypt{U});
    my $dat;
    if ($rev >= 3) {
        $dat = Digest::MD5::md5($pad . $id);
        RC4Crypt(\$dat, $key);
        for ($i=1; $i<=19; ++$i) {
            my @key = unpack('C*', $key);
            foreach (@key) { $_ ^= $i; }
            RC4Crypt(\$dat, pack('C*', @key));
        }
        $dat .= substr($u, 16);
    } else {
        $dat = $pad;
        RC4Crypt(\$dat, $key);
    }
    $dat eq $u or return 'Document is password encrypted';
    $$encrypt{key} = $key;  # save the file-level encryption key
    $cryptInfo = $encrypt;  # save a reference to the Encrypt object
    return undef;           # success!
}

#------------------------------------------------------------------------------
# Decrypt/Encrypt data
# Inputs: 0) data ref, 1) PDF object reference to use as crypt key extension
sub Crypt($$)
{
    return unless $cryptInfo;
    my ($dataPt, $keyExt) = @_;
    my $key = $$cryptInfo{key};
    my $len = length($key) + 5;
    return unless $keyExt =~ /^(I\d+ )?(\d+) (\d+)/;
    $key .= substr(pack('V', $2), 0, 3) . substr(pack('V', $3), 0, 2);
    $len = 16 if $len > 16;
    $key = substr(Digest::MD5::md5($key), 0, $len);
    RC4Crypt($dataPt, $key);
}

#------------------------------------------------------------------------------
# Decrypt/Encrypt stream data
# Inputs: 0) dictionary ref, 1) PDF object reference to use as crypt key extension
sub CryptStream($$)
{
    my ($dict, $keyExt) = @_;
    my $type = $$dict{Type} || '';
    # XRef streams are not encrypted, and Metadata may or may not be encrypted
    if ($type ne '/XRef' and ($$cryptInfo{meta} or $type ne '/Metadata')) {
        Crypt(\$$dict{_stream}, $keyExt);
    }
}

#------------------------------------------------------------------------------
# Process PDF dictionary extract tag values
# Inputs: 0) ExifTool object reference, 1) tag table reference
#         2) dictionary reference, 3) cross-reference table reference,
#         4) nesting depth, 5) dictionary capture type
sub ProcessDict($$$$;$$)
{
    my ($exifTool, $tagTablePtr, $dict, $xref, $nesting, $type) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my @tags = @{$$dict{_tags}};
    my $index = 0;
    my $next;

    $nesting = ($nesting || 0) + 1;
    if ($nesting > 50) {
        WarnOnce($exifTool, 'Nesting too deep (directory ignored)');
        return;
    }
    # save entire dictionary for rewriting if specified
    if ($$exifTool{PDF_CAPTURE} and $$tagTablePtr{VARS} and
        $tagTablePtr->{VARS}->{CAPTURE})
    {
        my $name;
        foreach $name (@{$tagTablePtr->{VARS}->{CAPTURE}}) {
            next if $exifTool->{PDF_CAPTURE}->{$name};
            # make sure we load the right type if indicated
            next if $type and $type ne $name;
            $exifTool->{PDF_CAPTURE}->{$name} = $dict;
            last;
        }
    }
#
# extract information from all tags in the dictionary
#
    for (;;) {
        my ($tag, $tagInfo);
        if (@tags) {
            $tag = shift @tags;
        } elsif (defined $next and not $next) {
            $tag = 'Next';
            $next = 1;
        } else {
            last;
        }
        if ($$tagTablePtr{$tag}) {
            $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        }
        my $val = $$dict{$tag};
        if ($verbose) {
            my ($val2, $extra);
            if (ref $val eq 'SCALAR') {
                $extra = ", indirect object ($$val)";
                if ($fetched{$$val}) {
                    $val2 = "ref($$val)";
                } elsif ($tag eq 'Next' and not $next) {
                    # handle 'Next' links after all others
                    $next = 0;
                    next;
                } else {
                    $fetched{$$val} = 1;
                    $val = FetchObject($exifTool, $$val, $xref, $tag);
                    $val2 = '<err>' unless defined $val;
                }
            } elsif (ref $val eq 'HASH') {
                $extra = ', direct dictionary';
            } elsif (ref $val eq 'ARRAY') {
                $extra = ', direct array of ' . scalar(@$val) . ' objects';
            } else {
                $extra = ', direct object';
            }
            my $isSubdir;
            if (ref $val eq 'HASH') {
                $isSubdir = 1;
            } elsif (ref $val eq 'ARRAY') {
                # recurse into objects in arrays only if they are lists of
                # dictionaries or indirect objects which could be dictionaries
                $isSubdir = 1 if @$val;
                foreach (@$val) {
                    next if ref $_ eq 'HASH' or ref $_ eq 'SCALAR';
                    undef $isSubdir;
                    last;
                }
            }
            if ($isSubdir) {
                # create bogus subdirectory to recurse into this dict
                $tagInfo or $tagInfo = {
                    Name => $tag,
                    SubDirectory => {
                        TagTable => 'Image::ExifTool::PDF::Unknown',
                    },
                };
            } elsif (ref $val eq 'ARRAY') {
                my @list = @$val;
                foreach (@list) {
                    $_ = "ref($$_)" if ref $_ eq 'SCALAR';
                }
                $val2 = '[' . join(',',@list) . ']';
            }
            $exifTool->VerboseInfo($tag, $tagInfo,
                Value => $val2 || $val,
                Extra => $extra,
                Index => $index++,
            );
        }
        unless ($tagInfo) {
            # add any tag found in Info directory to table
            next unless $$tagTablePtr{EXTRACT_UNKNOWN};
            my $name = $tag;
            $name =~ s/[^-\w]/_/g;  # translate invalid characters in tag name
            $tagInfo = { Name => $name };
            Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
        }
        unless ($$tagInfo{SubDirectory}) {
            $val = ReadPDFValue($val);
            my $format = $$tagInfo{Format} || $$tagInfo{Writable} || 'string';
            $val = ConvertPDFDate($val) if $format eq 'date';
            # convert from UTF-16 (big endian) to UTF-8 or Latin if necessary
            # unless this is binary data (hex-encoded strings would not have been converted)
            if (ref $val) {
                next if ref $val ne 'ARRAY';
                my $v;
                foreach $v (@$val) {
                    $exifTool->FoundTag($tagInfo, $v);
                }
            } else {
                if (not $$tagInfo{Binary} and $val =~ /[\x18-\x1f\x80-\xff]/) {
                    # text string is already in Unicode if it starts with "\xfe\xff",
                    # otherwise we must first convert from PDFDocEncoding
                    $val = PDF2Unicode($val, 'n') unless $val =~ s/^\xfe\xff//;
                    $val = $exifTool->Unicode2Charset($val, 'MM');
                }
                if ($$tagInfo{List}) {
                    # separate tokens in comma or whitespace delimited lists
                    my @values = ($val =~ /,/) ? split /,+\s*/, $val : split ' ', $val;
                    foreach $val (@values) {
                        $exifTool->FoundTag($tagInfo, $val);
                    }
                } else {
                    # a simple tag value
                    $exifTool->FoundTag($tagInfo, $val);
                }
            }
            next;
        }
        # process the subdirectory
        my @subDicts;
        if (ref $val eq 'ARRAY') {
            @subDicts = @{$val};
        } else {
            @subDicts = ( $val );
        }
        # loop through all values of this tag
        for (;;) {
            my $subDict = shift @subDicts or last;
            if (ref $subDict eq 'SCALAR') {
                # only fetch once (other copies are obsolete)
                next if $fetched{$$subDict};
                # load dictionary via an indirect reference
                $fetched{$$subDict} = 1;
                $subDict = FetchObject($exifTool, $$subDict, $xref, $tag);
                $subDict or $exifTool->Warn("Error reading $tag object"), next;
            }
            if (ref $subDict eq 'ARRAY') {
                # convert array of key/value pairs to a hash
                next if @$subDict < 2;
                my %hash = ( _tags => [] );
                while (@$subDict >= 2) {
                    my $key = shift @$subDict;
                    $key =~ s/^\///;
                    push @{$hash{_tags}}, $key;
                    $hash{$key} = shift @$subDict;
                }
                $subDict = \%hash;
            } else {
                next unless ref $subDict eq 'HASH';
            }
            my $subTablePtr = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
            if (not $verbose) {
                ProcessDict($exifTool, $subTablePtr, $subDict, $xref, $nesting);
            } elsif ($next) {
                # handle 'Next' links at this level to avoid deep recursion
                undef $next;
                $index = 0;
                $tagTablePtr = $subTablePtr;
                $dict = $subDict;
                @tags = @{$$subDict{_tags}};
                $exifTool->VerboseDir($tag, scalar(@tags));
            } else {
                my $oldIndent = $exifTool->{INDENT};
                my $oldDir = $exifTool->{DIR_NAME};
                $exifTool->{INDENT} .= '| ';
                $exifTool->{DIR_NAME} = $tag;
                $exifTool->VerboseDir($tag, scalar(@{$$subDict{_tags}}));
                ProcessDict($exifTool, $subTablePtr, $subDict, $xref, $nesting);
                $exifTool->{INDENT} = $oldIndent;
                $exifTool->{DIR_NAME} = $oldDir;
            }
        }
    }
#
# extract information from stream object if it exists (ie. Metadata stream)
#
    return unless $$dict{_stream};
    my $tag = '_stream';
    # add Subtype (if it exists) to stream name and remove leading '/'
    ($tag = $$dict{Subtype} . $tag) =~ s/^\/// if $$dict{Subtype};
    return unless $$tagTablePtr{$tag};
    my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
    # decode stream if necessary
    DecodeStream($exifTool, $dict) or return;
    # extract information from stream
    my %dirInfo = (
        DataPt   => \$$dict{_stream},
        DataLen  => length $$dict{_stream},
        DirStart => 0,
        DirLen   => length $$dict{_stream},
        Parent   => 'PDF',
    );
    my $subTablePtr = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
    unless ($exifTool->ProcessDirectory(\%dirInfo, $subTablePtr)) {
        $exifTool->Warn("Error processing $$tagInfo{Name} information");
    }
}

#------------------------------------------------------------------------------
# Extract information from PDF file
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 0 if not a PDF file, 1 on success, otherwise a negative error number
sub ReadPDF($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $verbose = $exifTool->Options('Verbose');
    my ($buff, $encrypt, $id);
#
# validate PDF file
#
    $raf->Read($buff, 10) >= 8 or return 0;
    $buff =~ /^%PDF-(\d+\.\d+)/ or return 0;
    $pdfVer = $1;
    $exifTool->SetFileType();   # set the FileType tag
    $exifTool->Warn("May not be able to read a PDF version $pdfVer file") if $pdfVer >= 2.0;
    # store PDFVersion tag
    my $tagTablePtr = GetTagTable('Image::ExifTool::PDF::Root');
    $exifTool->FoundTag($exifTool->GetTagInfo($tagTablePtr, 'Version'), $pdfVer);
    $tagTablePtr = GetTagTable('Image::ExifTool::PDF::Main');
#
# read the xref tables referenced from startxref at the end of the file
#
    my @xrefOffsets;
    $raf->Seek(0, 2) or return -2;
    # the %%EOF must occur within the last 1024 bytes of the file (PDF spec, appendix H)
    my $len = $raf->Tell();
    $len = 1024 if $len > 1024;
    $raf->Seek(-$len, 2) or return -2;
    $raf->Read($buff, $len) == $len or return -3;
    # find the last xref table in the file (may be multiple %%EOF marks)
    $buff =~ /.*startxref(\x0d\x0a|\x0a\x0a|\x0d|\x0a)(\d+)\1%%EOF/s or return -4;
    $/ = $1;    # set input record separator
    push @xrefOffsets, $2, 'Main';
    my (%xref, @mainDicts, %loaded, $mainFree);
    # initialize variables to capture when rewriting
    my $capture = $$exifTool{PDF_CAPTURE};
    if ($capture) {
        $capture->{startxref} = $2;
        $capture->{xref} = \%xref;
        $capture->{newline} = $/;
        $capture->{mainFree} = $mainFree = { };
    }
    while (@xrefOffsets) {
        my $offset = shift @xrefOffsets;
        my $type = shift @xrefOffsets;
        next if $loaded{$offset};   # avoid infinite recursion
        unless ($raf->Seek($offset, 0)) {
            %loaded or return -5;
            $exifTool->Warn('Bad offset for secondary xref table');
            next;
        }
        # Note: care must be taken because ReadLine may read more than we want if
        # the newline sequence for this table is different than the rest of the file
        unless ($raf->ReadLine($buff)) {
            %loaded or return -6;
            $exifTool->Warn('Bad offset for secondary xref table');
            next;
        }
        my $loadXRefStream;
        if ($buff =~ s/^xref\s+//s) {
            # load xref table
            for (;;) {
                # read another line if necessary
                $raf->ReadLine($buff) or return -6 unless $buff =~ /\S/;
                last if $buff =~ s/^\s*trailer\s+//s;
                $buff =~ s/\s*(\d+)\s+(\d+)\s+//s or return -4;
                my ($start, $num) = ($1, $2);
                $num and $raf->Seek(-length($buff), 1) or return -4;
                my $i;
                for ($i=0; $i<$num; ++$i) {
                    $raf->Read($buff, 20) == 20 or return -6;
                    $buff =~ /^\s*(\d{10}) (\d{5}) (f|n)/s or return -4;
                    my $num = $start + $i;
                    # save offset for newest copy of all objects
                    # (or next object number for free objects)
                    unless (defined $xref{$num}) {
                        my ($offset, $gen) = (int($1), int($2));
                        $xref{$num} = $offset;
                        if ($3 eq 'f') {
                            # save free objects in last xref table for rewriting
                            $$mainFree{$num} =  [ $offset, $gen, 'f' ] if $mainFree;
                            next;
                        }
                        # also save offset keyed by object reference string
                        $xref{"$num $gen R"} = $offset;
                    }
                }
                %xref or return -4; # xref table may not be empty
                $buff = '';
            }
            undef $mainFree;    # only do this for the last xref table
        } elsif ($buff =~ s/^(\d+)\s+(\d+)\s+obj//s) {
            # this is a PDF-1.5 cross-reference stream dictionary
            $loadXRefStream = 1;
        } else {
            %loaded or return -4;
            $exifTool->Warn('Invalid secondary xref table');
            next;
        }
        my $mainDict = ExtractObject($exifTool, \$buff, $raf, \%xref);
        unless (ref $mainDict eq 'HASH') {
            %loaded or return -8;
            $exifTool->Warn('Error loading secondary dictionary');
            next;
        }
        if ($loadXRefStream) {
            # decode and save our XRef stream from PDF-1.5 file
            # (but parse it later as required to save time)
            # Note: this technique can potentially result in an old object
            # being used if the file was incrementally updated and an older
            # object from an xref table was replaced by a newer object in an
            # xref stream.  But doing so isn't a good idea (if allowed at all)
            # because a PDF 1.4 consumer would also make this same mistake.
            if ($$mainDict{Type} eq '/XRef' and $$mainDict{W} and
                @{$$mainDict{W}} > 2 and $$mainDict{Size} and
                DecodeStream($exifTool, $mainDict))
            {
                # create Index entry if it doesn't exist
                $$mainDict{Index} or $$mainDict{Index} = [ 0, $$mainDict{Size} ];
                # create '_entry_size' entry for internal use
                my $w = $$mainDict{W};
                my $size = 0;
                foreach (@$w) { $size += $_; }
                $$mainDict{_entry_size} = $size;
                # save this stream dictionary to use later if required
                $xref{dicts} = [] unless $xref{dicts};
                push @{$xref{dicts}}, $mainDict;
            } else {
                %loaded or return -9;
                $exifTool->Warn('Invalid xref stream in secondary dictionary');
            }
        }
        $loaded{$offset} = 1;
        # load XRef stream in hybrid file if it exists
        push @xrefOffsets, $$mainDict{XRefStm}, 'XRefStm' if $$mainDict{XRefStm};
        $encrypt = $$mainDict{Encrypt} if $$mainDict{Encrypt};
        if ($$mainDict{ID} and ref $$mainDict{ID} eq 'ARRAY') {
            $id = ReadPDFValue($mainDict->{ID}->[0]);
        }
        push @mainDicts, $mainDict, $type;
        # load previous xref table if it exists
        push @xrefOffsets, $$mainDict{Prev}, 'Prev' if $$mainDict{Prev};
    }
#
# extract encryption information if necessary
#
    if ($encrypt) {
        if (ref $encrypt eq 'SCALAR') {
            $encrypt = FetchObject($exifTool, $$encrypt, \%xref, 'Encrypt');
        }
        # generate Encryption tag information
        my $err = DecryptInit($exifTool, $encrypt, $id);
        if ($err) {
            $exifTool->Warn($err);
            $$capture{Error} = $err if $capture;
            return -1;
        }
    }
#
# extract the information beginning with each of the main dictionaries
#
    while (@mainDicts) {
        my $dict = shift @mainDicts;
        my $type = shift @mainDicts;
        if ($verbose) {
            my $n = scalar(@{$$dict{_tags}});
            $exifTool->VPrint(0, "PDF dictionary with $n entries:\n");
        }
        ProcessDict($exifTool, $tagTablePtr, $dict, \%xref, 0, $type);
    }
    return 1;
}

#------------------------------------------------------------------------------
# ReadPDF() warning strings for each error return value
my %pdfWarning = (
    # -1 is reserved as error return value with no associated warning
    -2 => 'Error seeking in file',
    -3 => 'Error reading file',
    -4 => 'Invalid xref table',
    -5 => 'Invalid xref offset',
    -6 => 'Error reading xref table',
    -7 => 'Error reading trailer',
    -8 => 'Error reading main dictionary',
    -9 => 'Invalid xref stream in main dictionary',
);

#------------------------------------------------------------------------------
# Extract information from PDF file
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 if this was a valid PDF file
sub ProcessPDF($$)
{
    my ($exifTool, $dirInfo) = @_;

    undef $cryptInfo;   # (must not delete after returning)
    my $oldsep = $/;
    my $result = ReadPDF($exifTool, $dirInfo);
    $/ = $oldsep;   # restore input record separator in case it was changed
    if ($result < 0) {
        $exifTool->Warn($pdfWarning{$result}) if $pdfWarning{$result};
        $result = 1;
    }
    # clean up and return
    undef %warnedOnce;
    undef %streamObjs;
    undef %fetched;
    return $result;
}

1; # end


__END__

=head1 NAME

Image::ExifTool::PDF - Read PDF meta information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This code reads meta information from PDF (Adobe Portable Document Format)
files.  It supports object streams introduced in PDF-1.5 but only with a
limited set of Filter and Predictor algorithms, and it decodes encrypted
information but only with a limited number of algorithms.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://partners.adobe.com/public/developer/pdf/index_reference.html>

=item L<Crypt::RC4|Crypt::RC4>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/PDF Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
