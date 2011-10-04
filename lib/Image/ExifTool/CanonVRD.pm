#------------------------------------------------------------------------------
# File:         CanonVRD.pm
#
# Description:  Read/write Canon VRD information
#
# Revisions:    10/30/2006 - P. Harvey Created
#------------------------------------------------------------------------------

package Image::ExifTool::CanonVRD;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);

$VERSION = '1.05';

sub ProcessCanonVRD($$);

my $debug;  # set this to 1 for offsets relative to binary data start

my %noYes = ( 0 => 'No', 1 => 'Yes' );

# main tag table IPTC-format records in CanonVRD trailer
%Image::ExifTool::CanonVRD::Main = (
    VARS => { ID_LABEL => 'Index' }, # change TagID label in documentation
    NOTES => q{
        Canon Digital Photo Professional writes VRD (Recipe Data) information as a
        trailer record to JPEG, TIFF, CRW and CR2 images, or as a stand-alone VRD
        file. The tags listed below represent information found in this record.  The
        complete VRD data record may be accessed as a block using the Extra
        'CanonVRD' tag, but this tag is not extracted or copied unless specified
        explicitly.
    },
    0 => {
        Name => 'VRD1',
        Size => 0x272,  # size of version 1.0 edit information in bytes
        SubDirectory => { TagTable => 'Image::ExifTool::CanonVRD::Ver1' },
    },
    1 => {
        Name => 'VRDStampTool',
        # (size is variable, and obtained from int32u at end of last directory)
        Size => 0,      # size is variable, and obtained from int32u at directory start
        SubDirectory => { TagTable => 'Image::ExifTool::CanonVRD::StampTool' },
    },
    2 => {
        Name => 'VRD2',
        Size => undef,  # size is the remaining edit data
        SubDirectory => { TagTable => 'Image::ExifTool::CanonVRD::Ver2' },
    },
);

# VRD version 1 tags
%Image::ExifTool::CanonVRD::Ver1 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    GROUPS => { 2 => 'Image' },
#
# RAW image adjustment
#
    0x002 => {
        Name => 'VRDVersion',
        Format => 'int16u',
        Writable => 0,
        PrintConv => 'sprintf("%.2f", $val / 100)',
    },
    # 0x006 related somehow to RGB levels
    0x008 => {
        Name => 'WBAdjRGBLevels',
        Format => 'int16u[3]',
    },
    0x018 => {
        Name => 'WhiteBalanceAdj',
        Format => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'Daylight',
            2 => 'Cloudy',
            3 => 'Tungsten',
            4 => 'Fluorescent',
            5 => 'Flash',
            8 => 'Shade',
            9 => 'Kelvin',
            30 => 'Manual (Click)',
            31 => 'Shot Settings',
        },
    },
    0x01a => {
        Name => 'WBAdjColorTemp',
        Format => 'int16u',
    },
    # 0x01c similar to 0x006
    # 0x01e similar to 0x008
    0x024 => {
        Name => 'WBFineTuneActive',
        Format => 'int16u',
        PrintConv => \%noYes,
    },
    0x028 => {
        Name => 'WBFineTuneSaturation',
        Format => 'int16u',
    },
    0x02c => {
        Name => 'WBFineTuneTone',
        Format => 'int16u',
    },
    0x02e => {
        Name => 'RawColorAdj',
        Format => 'int16u',
        PrintConv => {
            0 => 'Shot Settings',
            1 => 'Faithful',
            2 => 'Custom',
        },
    },
    0x030 => {
        Name => 'RawCustomSaturation',
        Format => 'int32s',
    },
    0x034 => {
        Name => 'RawCustomTone',
        Format => 'int32s',
    },
    0x038 => {
        Name => 'RawBrightnessAdj',
        Format => 'int32s',
        ValueConv => '$val / 6000',
        ValueConvInv => 'int($val * 6000 + ($val < 0 ? -0.5 : 0.5))',
        PrintConv => 'sprintf("%.2f",$val)',
        PrintConvInv => '$val',
    },
    0x03c => {
        Name => 'ToneCurveProperty',
        Format => 'int16u',
        PrintConv => {
            0 => 'Shot Settings',
            1 => 'Linear',
            2 => 'Custom 1',
            3 => 'Custom 2',
            4 => 'Custom 3',
            5 => 'Custom 4',
            6 => 'Custom 5',
        },
    },
    # 0x040 usually "10 9 2"
    0x07a => {
        Name => 'DynamicRangeMin',
        Format => 'int16u',
    },
    0x07c => {
        Name => 'DynamicRangeMax',
        Format => 'int16u',
    },
    # 0x0c6 usually "10 9 2"
#
# RGB image adjustment
#
    0x110 => {
        Name => 'ToneCurveActive',
        Format => 'int16u',
        PrintConv => \%noYes,
    },
    0x114 => {
        Name => 'BrightnessAdj',
        Format => 'int8s',
    },
    0x115 => {
        Name => 'ContrastAdj',
        Format => 'int8s',
    },
    0x116 => {
        Name => 'SaturationAdj',
        Format => 'int16s',
    },
    0x11e => {
        Name => 'ColorToneAdj',
        Notes => 'in degrees, so -1 is the same as 359',
        Format => 'int32s',
    },
    0x160 => {
        Name => 'RedCurvePoints',
        Format => 'int16u[21]',
        PrintConv => 'Image::ExifTool::CanonVRD::ToneCurvePrint($val)',
        PrintConvInv => 'Image::ExifTool::CanonVRD::ToneCurvePrintInv($val)',
    },
    0x19a => {
        Name => 'GreenCurvePoints',
        Format => 'int16u[21]',
        PrintConv => 'Image::ExifTool::CanonVRD::ToneCurvePrint($val)',
        PrintConvInv => 'Image::ExifTool::CanonVRD::ToneCurvePrintInv($val)',
    },
    0x1d4 => {
        Name => 'BlueCurvePoints',
        Format => 'int16u[21]',
        PrintConv => 'Image::ExifTool::CanonVRD::ToneCurvePrint($val)',
        PrintConvInv => 'Image::ExifTool::CanonVRD::ToneCurvePrintInv($val)',
    },
    0x18a => {
        Name => 'RedCurveLimits',
        Notes => '4 numbers: input and output highlight and shadow points',
        Format => 'int16u[4]',
    },
    0x1c4 => {
        Name => 'GreenCurveLimits',
        Format => 'int16u[4]',
    },
    0x1fe => {
        Name => 'BlueCurveLimits',
        Format => 'int16u[4]',
    },
    0x20e => {
        Name => 'RGBCurvePoints',
        Format => 'int16u[21]',
        PrintConv => 'Image::ExifTool::CanonVRD::ToneCurvePrint($val)',
        PrintConvInv => 'Image::ExifTool::CanonVRD::ToneCurvePrintInv($val)',
    },
    0x238 => {
        Name => 'RGBCurveLimits',
        Format => 'int16u[4]',
    },
    0x244 => {
        Name => 'CropActive',
        Format => 'int16u',
        PrintConv => \%noYes,
    },
    0x246 => {
        Name => 'CropLeft',
        Notes => 'crop coordinates in original unrotated image',
        Format => 'int16u',
    },
    0x248 => {
        Name => 'CropTop',
        Format => 'int16u',
    },
    0x24a => {
        Name => 'CropWidth',
        Format => 'int16u',
    },
    0x24c => {
        Name => 'CropHeight',
        Format => 'int16u',
    },
    0x260 => {
        Name => 'CropAspectRatio',
        Format => 'int16u',
        PrintConv => {
            0 => 'Free',
            1 => '3:2',
            2 => '2:3',
            3 => '4:3',
            4 => '3:4',
            5 => 'A-size Landscape',
            6 => 'A-size Portrait',
            7 => 'Letter-size Landscape',
            8 => 'Letter-size Portrait',
            9 => '4:5',
            10 => '5:4',
            11 => '1:1',
        },
    },
    0x262 => {
        Name => 'ConstrainedCropWidth',
        Format => 'float',
        PrintConv => 'sprintf("%.7g",$val)',
        PrintConvInv => '$val',
    },
    0x266 => {
        Name => 'ConstrainedCropHeight',
        Format => 'float',
        PrintConv => 'sprintf("%.7g",$val)',
        PrintConvInv => '$val',
    },
    0x26a => {
        Name => 'CheckMark',
        Format => 'int16u',
        PrintConv => {
            0 => 'Clear',
            1 => 1,
            2 => 2,
            3 => 3,
        },
    },
    0x26e => {
        Name => 'Rotation',
        Format => 'int16u',
        PrintConv => {
            0 => 0,
            1 => 90,
            2 => 180,
            3 => 270,
        },
    },
    0x270 => {
        Name => 'WorkColorSpace',
        Format => 'int16u',
        PrintConv => {
            0 => 'sRGB',
            1 => 'Adobe RGB',
            2 => 'Wide Gamut RGB',
            3 => 'Apple RGB',
            4 => 'ColorMatch RGB',
        },
    },
    # (VRD 1.0 edit data ends here -- 0x272 bytes long)
);

# VRD Stamp Tool tags
%Image::ExifTool::CanonVRD::StampTool = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Image' },
    0x00 => {
        Name => 'StampToolCount',
        Format => 'int32u',
    },
);

# VRD version 2 and 3 tags
%Image::ExifTool::CanonVRD::Ver2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    WRITE_PROC => \&Image::ExifTool::WriteBinaryData,
    CHECK_PROC => \&Image::ExifTool::CheckBinaryData,
    WRITABLE => 1,
    GROUPS => { 2 => 'Image' },
    NOTES => 'Tags added in DPP version 2.0 and later.',
    0x04 => {
        Name => 'PictureStyle',
        Format => 'int16u',
        PrintConv => {
            0 => 'Standard',
            1 => 'Portrait',
            2 => 'Landscape',
            3 => 'Neutral',
            4 => 'Faithful',
            5 => 'Monochrome',
        },
    },
    0x1a => {
        Name => 'RawColorToneAdj',
        Format => 'int16s',
    },
    0x1c => {
        Name => 'RawSaturationAdj',
        Format => 'int16s',
    },
    0x1e => {
        Name => 'RawContrastAdj',
        Format => 'int16s',
    },
    0x20 => {
        Name => 'RawLinear',
        Format => 'int16u',
        PrintConv => \%noYes,
    },
    0x22 => {
        Name => 'RawSharpnessAdj',
        Format => 'int16s',
    },
    0x24 => {
        Name => 'RawHighlightPoint',
        Format => 'int16s',
    },
    0x26 => {
        Name => 'RawShadowPoint',
        Format => 'int16s',
    },
    0x74 => {
        Name => 'MonochromeFilterEffect',
        Format => 'int16s',
        PrintConv => {
            -2 => 'None',
            -1 => 'Yellow',
            0 => 'Orange',
            1 => 'Red',
            2 => 'Green',
        },
    },
    0x76 => {
        Name => 'MonochromeToningEffect',
        Format => 'int16s',
        PrintConv => {
            -2 => 'None',
            -1 => 'Sepia',
            0 => 'Blue',
            1 => 'Purple',
            2 => 'Green',
        },
    },
    0x78 => {
        Name => 'MonochromeContrast',
        Format => 'int16s',
    },
    0x7a => {
        Name => 'MonochromeLinear',
        Format => 'int16u',
        PrintConv => \%noYes,
    },
    0x7c => {
        Name => 'MonochromeSharpness',
        Format => 'int16s',
    },
    # (VRD 2.0 edit data ends here -- offset 0xb2)
    0xbc => {
        Name => 'ChrominanceNoiseReduction',
        Format => 'int16u',
        PrintConv => {
            0   => 'Off',
            58  => 'Low',
            100 => 'High',
        },
    },
    0xbe => {
        Name => 'LuminanceNoiseReduction',
        Format => 'int16u',
        PrintConv => {
            0   => 'Off',
            65  => 'Low',
            100 => 'High',
        },
    },
    0xc0 => {
        Name => 'ChrominanceNR_TIFF_JPEG',
        Format => 'int16u',
        PrintConv => {
            0   => 'Off',
            33  => 'Low',
            100 => 'High',
        },
    }
    # (VRD 3.0 edit data ends here -- offset 0xc4)
);

#------------------------------------------------------------------------------
# Tone curve print conversion
sub ToneCurvePrint($)
{
    my $val = shift;
    my @vals = split ' ', $val;
    return $val unless @vals == 21;
    my $n = shift @vals;
    return $val unless $n >= 2 and $n <= 10;
    $val = '';
    while ($n--) {
        $val and $val .= ' ';
        $val .= '(' . shift(@vals) . ',' . shift(@vals) . ')';
    }
    return $val;
}

#------------------------------------------------------------------------------
# Inverse print conversion for tone curve
sub ToneCurvePrintInv($)
{
    my $val = shift;
    my @vals = ($val =~ /\((\d+),(\d+)\)/g);
    return undef unless @vals >= 4 and @vals <= 20 and not @vals & 0x01;
    unshift @vals, scalar(@vals) / 2;
    while (@vals < 21) { push @vals, 0 }
    return join(' ',@vals);
}

#------------------------------------------------------------------------------
# Read/write Canon VRD file
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 if this was a Canon VRD file, 0 otherwise, -1 on write error
sub ProcessVRD($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $buff;
    my $num = $raf->Read($buff, 0x1c);
    if (not $num and $$dirInfo{OutFile}) {
        # create new VRD file from scratch
        my $newVal = $exifTool->GetNewValues('CanonVRD');
        if ($newVal) {
            $exifTool->VPrint(0, "  Writing CanonVRD as a block\n");
            Write($$dirInfo{OutFile}, $newVal) or return -1;
            ++$exifTool->{CHANGED};
        } else {
            $exifTool->Error('No CanonVRD information to write');
        }
    } else {
        $num == 0x1c or return 0;
        $buff =~ /^CANON OPTIONAL DATA\0/ or return 0;
        $exifTool->SetFileType();
        $$dirInfo{DirName} = 'CanonVRD';    # set directory name for verbose output
        my $result = ProcessCanonVRD($exifTool, $dirInfo);
        return $result if $result < 0;
        $result or $exifTool->Warn('Format error in VRD file');
    }
    return 1;
}

#------------------------------------------------------------------------------
# Read/write CanonVRD information
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 on success, 0 not valid VRD, or -1 error writing
# - updates DataPos to point to start of CanonVRD information
# - updates DirLen to trailer length
sub ProcessCanonVRD($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $offset = $$dirInfo{Offset} || 0;
    my $outfile = $$dirInfo{OutFile};
    my $verbose = $exifTool->Options('Verbose');
    my $out = $exifTool->Options('TextOut');
    my ($buff, $footer, $header, $err);
    my ($blockLen, $blockType, $recLen, $size);

    # read and validate the trailer footer
    $raf->Seek(-64-$offset, 2)    or return 0;
    $raf->Read($footer, 64) == 64 or return 0;
    $footer =~ /^CANON OPTIONAL DATA\0(.{4})/s or return 0;
    $size = unpack('N', $1);

    # read and validate the header too
    # (header is 0x1c bytes and footer is 0x40 bytes)
    unless ($size > 12 and ($size & 0x80000000) == 0 and
            $raf->Seek(-$size-0x5c, 1) and
            $raf->Read($header, 0x1c) == 0x1c and
            $header =~ /^CANON OPTIONAL DATA\0/ and
            $raf->Read($buff, $size) == $size)
    {
        $exifTool->Warn('Bad CanonVRD trailer');
        return 0;
    }
    # extract CanonVRD block if Binary option set, or if requested
    if ($exifTool->{OPTIONS}->{Binary} or $exifTool->{REQ_TAG_LOOKUP}->{canonvrd}) {
        $exifTool->FoundTag('CanonVRD', $header . $buff . $footer);
    }
    # set variables returned in dirInfo hash
    $$dirInfo{DataPos} = $raf->Tell() - $size - 0x1c;
    $$dirInfo{DirLen} = $size + 0x5c;

    if ($outfile) {
        # delete CanonVRD information if specified
        if ($exifTool->{DEL_GROUP}->{CanonVRD} or $exifTool->{DEL_GROUP}->{Trailer} or
            # also delete if writing as a block (will get added back again later)
            $exifTool->{NEW_VALUE}->{$Image::ExifTool::Extra{CanonVRD}})
        {
            if ($exifTool->{FILE_TYPE} eq 'VRD') {
                my $newVal = $exifTool->GetNewValues('CanonVRD');
                if ($newVal) {
                    $verbose and printf $out "  Writing CanonVRD as a block\n";
                    Write($outfile, $newVal) or return -1;
                    ++$exifTool->{CHANGED};
                } else {
                    $exifTool->Error("Can't delete all CanonVRD information from a VRD file");
                }
            } else {
                $verbose and printf $out "  Deleting CanonVRD trailer\n";
                ++$exifTool->{CHANGED};
            }
            return 1;
        }
        # write now and return if CanonVRD was set as a block
        my $val = $exifTool->GetNewValues('CanonVRD');
        if ($val) {
            $verbose and print $out "  Writing CanonVRD as a block\n";
            Write($outfile, $val) or return -1;
            ++$exifTool->{CHANGED};
            return 1;
        }
    } elsif ($verbose or $exifTool->{HTML_DUMP}) {
        $exifTool->DumpTrailer($dirInfo);
    }

    # validate VRD trailer and get position and length of edit record
    SetByteOrder('MM');
    my $pos = 0;
    my $vrdPos = $$dirInfo{DataPos} + length($header);
Block: for (;;) {
        if ($pos + 8 > $size) {
            last if $pos == $size;
            $blockLen = $size;  # mark as invalid
        } else {
            $blockType = Get32u(\$buff, $pos);
            $blockLen = Get32u(\$buff, $pos + 4);
        }
        $pos += 8;          # move to start of block
        if ($pos + $blockLen > $size) {
            $exifTool->Warn('Possibly corrupt CanonVRD block');
            last;
        }
        printf $out "  CanonVRD block %x ($blockLen bytes at offset 0x%x)\n",
            $blockType, $pos + $vrdPos if $verbose > 1 and not $outfile;
        # process edit-data block
        if ($blockType == 0xffff00f4) {
            my $blockEnd = $pos + $blockLen;
            my $recNum;
            for ($recNum=0;; ++$recNum, $pos+=$recLen) {
                if ($pos + 4 > $blockEnd) {
                    last Block if $pos == $blockEnd;  # all done if we arrived at end
                    $recLen = $blockEnd;    # mark as invalid
                } else {
                    $recLen = Get32u(\$buff, $pos);
                }
                $pos += 4;      # move to start of record
                if ($pos + $recLen > $blockEnd) {
                    $exifTool->Warn('Possibly corrupt CanonVRD record');
                    last Block;
                }
                printf $out "  CanonVRD record ($recLen bytes at offset 0x%x)\n",
                    $pos + $vrdPos if $verbose > 1 and not $outfile;

                # our edit information is the first record
                # (don't process if simply deleting VRD)
                next if $recNum;

                # process VRD edit information
                my $tagTablePtr = GetTagTable('Image::ExifTool::CanonVRD::Main');
                my $index;
                my $editData = substr($buff, $pos, $recLen);
                my %subdirInfo = (
                    DataPt => \$editData,
                    DataPos => $debug ? 0 : $vrdPos + $pos,
                );
                my $start = 0;
                for ($index=0; ; ++$index) {
                    my $tagInfo = $$tagTablePtr{$index} or last;
                    my $dirLen;
                    my $maxLen = $recLen - $start;
                    if ($$tagInfo{Size}) {
                        $dirLen = $$tagInfo{Size};
                    } elsif (defined $$tagInfo{Size}) {
                        # get size from int32u at $start
                        last unless $start + 4 <= $recLen;
                        $dirLen = Get32u(\$editData, $start);
                        $start += 4; # skip the length word
                    } else {
                        $dirLen = $maxLen;
                    }
                    $dirLen > $maxLen and $dirLen = $maxLen;
                    if ($dirLen) {
                        my $subTable = GetTagTable($tagInfo->{SubDirectory}->{TagTable});
                        my $subName = $$tagInfo{Name};
                        $subdirInfo{DirStart} = $start;
                        $subdirInfo{DirLen} = $dirLen;
                        $subdirInfo{DirName} = $subName;
                        if ($outfile) {
                            # rewrite CanonVRD information
                            $verbose and print $out "  Rewriting Canon $subName\n";
                            my $newVal = $exifTool->WriteDirectory(\%subdirInfo, $subTable);
                            substr($buff, $pos+$start, $dirLen) = $newVal if $newVal;
                        } else {
                            Image::ExifTool::HexDump(\$editData, $dirLen,
                                Start  => $start,
                                Addr   => 0,
                                Prefix => $$tagInfo{Name}
                            ) if $debug;
                            # extract CanonVRD information
                            $exifTool->ProcessDirectory(\%subdirInfo, $subTable);
                        }
                    }
                    # next directory starts at the end of this one
                    $start += $dirLen;
                }
            }
        } else {
            $pos += $blockLen;  # skip other blocks
        }
    }
    # write CanonVRD trailer
    Write($outfile, $header, $buff, $footer) or $err = 1 if $outfile;

    undef $buff;
    return $err ? -1 : 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::CanonVRD - Read/write Canon VRD information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to read and
write VRD Recipe Data information as written by the Canon Digital Photo
Professional software.  This information is written to VRD files, and as a
trailer in JPEG, CRW and CR2 images.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/CanonVRD Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

