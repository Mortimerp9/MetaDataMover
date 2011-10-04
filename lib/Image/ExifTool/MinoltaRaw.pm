#------------------------------------------------------------------------------
# File:         MinoltaRaw.pm
#
# Description:  Read/write Konica-Minolta RAW (MRW) meta information
#
# Revisions:    03/11/2006 - P. Harvey Split out from Minolta.pm
#
# References:   1) http://www.cybercom.net/~dcoffin/dcraw/
#               2) http://www.chauveau-central.net/mrw-format/
#------------------------------------------------------------------------------

package Image::ExifTool::MinoltaRaw;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);

$VERSION = '1.04';

sub ProcessMRW($$;$);

# Minolta MRW tags
%Image::ExifTool::MinoltaRaw::Main = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    PROCESS_PROC => \&Image::ExifTool::MinoltaRaw::ProcessMRW,
    NOTES => 'These tags are used in Minolta RAW format (MRW) images.',
    "\0TTW" => { # TIFF Tags
        Name => 'MinoltaTTW',
        SubDirectory => {
            TagTable => 'Image::ExifTool::Exif::Main',
            # this EXIF information starts with a TIFF header
            ProcessProc => \&Image::ExifTool::ProcessTIFF,
            WriteProc => \&Image::ExifTool::WriteTIFF,
        },
    },
    "\0PRD" => { # Raw Picture Dimensions
        Name => 'MinoltaPRD',
        SubDirectory => { TagTable => 'Image::ExifTool::MinoltaRaw::PRD' },
    },
    "\0WBG" => { # White Balance Gains
        Name => 'MinoltaWBG',
        SubDirectory => { TagTable => 'Image::ExifTool::MinoltaRaw::WBG' },
    },
    "\0RIF" => { # Requested Image Format
        Name => 'MinoltaRIF',
        SubDirectory => { TagTable => 'Image::ExifTool::MinoltaRaw::RIF' },
    },
    # "\0CSA" is padding
);

# Minolta MRW PRD information (ref 2)
%Image::ExifTool::MinoltaRaw::PRD = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    0 => {
        Name => 'FirmwareID',
        Format => 'string[8]',
    },
    8 => {
        Name => 'SensorHeight',
        Format => 'int16u',
    },
    10 => {
        Name => 'SensorWidth',
        Format => 'int16u',
    },
    12 => {
        Name => 'ImageHeight',
        Format => 'int16u',
    },
    14 => {
        Name => 'ImageWidth',
        Format => 'int16u',
    },
    16 => {
        Name => 'RawDepth',
        Format => 'int8u',
    },
    17 => {
        Name => 'BitDepth',
        Format => 'int8u',
    },
    18 => {
        Name => 'StorageMethod',
        Format => 'int8u',
        PrintConv => {
            82 => 'Padded',
            89 => 'Linear',
        },
    },
    23 => {
        Name => 'BayerPattern',
        Format => 'int8u',
        PrintConv => {
            1 => 'RGGB',
            4 => 'GBRG',
        },
    },
);

# Minolta MRW WBG information (ref 2)
%Image::ExifTool::MinoltaRaw::WBG = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    0 => {
        Name => 'WBScale',
        Format => 'int8u[4]',
    },
    4 => {
        Name => 'WBLevels',
        Format => 'int16u[4]',
    },
);

# Minolta MRW RIF information (ref 2)
%Image::ExifTool::MinoltaRaw::RIF = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    FIRST_ENTRY => 0,
    1 => {
        Name => 'Saturation',
        Format => 'int8s',
    },
    2 => {
        Name => 'Contrast',
        Format => 'int8s',
    },
    3 => {
        Name => 'Sharpness',
        Format => 'int8s',
    },
    4 => {
        Name => 'WBMode',
        PrintConv => 'Image::ExifTool::MinoltaRaw::ConvertWBMode($val)',
    },
    5 => {
        Name => 'ProgramMode',
        PrintConv => {
            0 => 'None',
            1 => 'Portrait',
            2 => 'Text',
            3 => 'Night Portrait',
            4 => 'Sunset',
            5 => 'Sports',
        },
    },
    6 => {
        Name => 'ISOSetting',
        ValueConv => '2 ** (($val-48)/8) * 100',
        ValueConvInv => '48 + 8*log($val/100)/log(2)',
        PrintConv => 'int($val + 0.5)',
        PrintConvInv => '$val',
    },
    7 => {
        Name => 'ColorMode',
        PrintHex => 1,
        PrintConv => {
            0 => 'Normal',
            1 => 'Black & White',
            2 => 'Vivid color',
            3 => 'Solarization',
            4 => 'Adobe RGB',
            13 => 'Natural sRGB',
            14 => 'Natural+ sRGB',
            0x84 => 'Adobe RGB', # what does the high bit mean?
        },
    },
    56 => {
        Name => 'ColorFilter',
        Format => 'int8s',
    },
    57 => 'BWFilter',
    58 => {
        Name => 'ZoneMatching',
        PrintConv => {
            0 => 'ISO Setting Used',
            1 => 'High Key',
            2 => 'Low Key',
        },
    },
    59 => {
        Name => 'Hue',
        Format => 'int8s',
    },
    60 => {
        Name => 'ColorTemperature',
        ValueConv => '$val * 100',
        ValueConvInv => '$val / 100',
    },
);

#------------------------------------------------------------------------------
# PrintConv for WBMode
sub ConvertWBMode($)
{
    my $val = shift;
    my %mrwWB = (
        0 => 'Auto',
        1 => 'Daylight',
        2 => 'Cloudy',
        3 => 'Tungsten',
        4 => 'Flash/Fluorescent',
        5 => 'Fluorescent',
        6 => 'Shade',
        7 => 'User 1',
        8 => 'User 2',
        9 => 'User 3',
        10 => 'Temperature',
    );
    my $lo = $val & 0x0f;
    my $wbstr = $mrwWB{$lo} || "Unknown ($lo)";
    my $hi = $val >> 4;
    $wbstr .= ' (' . ($hi - 8) . ')' if $hi >= 6 and $hi <=12;
    return $wbstr;
}

#------------------------------------------------------------------------------
# Read or write Minolta MRW file
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 on success, 0 if this wasn't a valid MRW file, or -1 on write error
# Notes: File pointer must be set to start of MRW in RAF upon entry
sub ProcessMRW($$;$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $raf = $$dirInfo{RAF};
    my $outfile = $$dirInfo{OutFile};
    my $verbose = $exifTool->Options('Verbose');
    my $out = $exifTool->Options('TextOut');
    my ($data, $err, $outBuff);

    if ($$dirInfo{DataPt}) {
        # make a RAF object for MRW information extracted from other file types
        $raf = new File::RandomAccess($$dirInfo{DataPt});
        # MRW information in DNG images may not start at beginning of data block
        $raf->Seek($$dirInfo{DirStart}, 0) if $$dirInfo{DirStart};
    }
    $raf->Read($data,8) == 8 or return 0;
    # "\0MRM" for big-endian (MRW images), and
    # "\0MRI" for little-endian (MRWInfo in ARW images)
    $data =~ /^\0MR([MI])/ or return 0;
    SetByteOrder($1 . $1);
    $exifTool->SetFileType() unless $exifTool->{VALUE}->{FileType};
    $tagTablePtr = GetTagTable('Image::ExifTool::MinoltaRaw::Main');
    if ($outfile) {
        $exifTool->InitWriteDirs('TIFF'); # use same write dirs as TIFF
        $outBuff = '';
    }
    my $pos = $raf->Tell();
    my $offset = Get32u(\$data, 4) + $pos;
    my $rtnVal = 1;
    $verbose and printf $out "  [MRW Data Offset: 0x%x]\n", $offset;
    # loop through MRW segments (ref 1)
    while ($pos < $offset) {
        $raf->Read($data,8) == 8 or $err = 1, last;
        $pos += 8;
        my $tag = substr($data, 0, 4);
        my $len = Get32u(\$data, 4);
        if ($verbose) {
            print $out "MRW ",$exifTool->Printable($tag)," segment ($len bytes):\n";
            if ($verbose > 2) {
                $raf->Read($data,$len) == $len and $raf->Seek($pos,0) or $err = 1, last;
                my %parms = (Addr => $pos, Out => $out);
                $parms{MaxLen} = 96 unless $verbose > 3;
                Image::ExifTool::HexDump(\$data,undef,%parms);
            }
        }
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        if ($tagInfo and $$tagInfo{SubDirectory}) {
            my $subTable = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
            my $buff;
            $raf->Read($buff, $len) == $len or $err = 1, last;
            my %subdirInfo = (
                DataPt => \$buff,
                DataLen => $len,
                DataPos => $pos,
                DirStart => 0,
                DirLen => $len,
                DirName => $$tagInfo{Name},
                Parent => 'MRW',
                NoTiffEnd => 1, # no end-of-TIFF check
            );
            if ($outfile) {
                my $writeProc = $tagInfo->{SubDirectory}->{WriteProc};
                my $val = $exifTool->WriteDirectory(\%subdirInfo, $subTable, $writeProc);
                if (defined $val and length $val) {
                    # pad to an even 4 bytes (can't hurt, and it seems to be the standard)
                    $val .= "\0" x (4 - (length($val) & 0x03)) if length($val) & 0x03;
                    $outBuff .= $tag . Set32u(length $val) . $val;
                } elsif (not defined $val) {
                    $outBuff .= $data . $buff;  # copy over original information
                }
            } else {
                my $processProc = $tagInfo->{SubDirectory}->{ProcessProc};
                $exifTool->ProcessDirectory(\%subdirInfo, $subTable, $processProc);
            }
        } elsif ($outfile) {
            # add this segment to the output buffer
            my $buff;
            $raf->Read($buff, $len) == $len or $err = 1, last;
            $outBuff .= $data . $buff;
        } else {
            # skip this segment
            $raf->Seek($pos+$len, 0) or $err = 1, last;
        }
        $pos += $len;
    }
    $pos == $offset or $err = 1;    # meta information length check

    if ($outfile) {
        # write the file header then the buffered meta information
        Write($outfile, "\0MRM", Set32u(length $outBuff), $outBuff) or $rtnVal = -1;
        # copy over image data
        while ($raf->Read($outBuff, 65536)) {
            Write($outfile, $outBuff) or $rtnVal = -1;
        }
    }
    $err and $exifTool->Error("MRW format error");
    return $rtnVal;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::MinoltaRaw - Read/write Konica-Minolta RAW (MRW) information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to read and
write Konica-Minolta RAW (MRW) images.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=item L<http://www.chauveau-central.net/mrw-format/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/MinoltaRaw Tags>,
L<Image::ExifTool::Minolta(3pm)|Image::ExifTool::Minolta>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
