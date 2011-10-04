#------------------------------------------------------------------------------
# File:         GIF.pm
#
# Description:  Read and write GIF meta information
#
# Revisions:    10/18/2005 - P. Harvey Separated from ExifTool.pm
#
# References:   http://www.w3.org/Graphics/GIF/spec-gif89a.txt
#
# Notes:        GIF really doesn't have much meta information, except for
#               comments which are allowed in GIF89a images
#------------------------------------------------------------------------------

package Image::ExifTool::GIF;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);

$VERSION = '1.05';

# road map of directory locations in GIF images
my %gifMap = (
    XMP => 'GIF',
);

#------------------------------------------------------------------------------
# Process meta information in GIF image
# Inputs: 0) ExifTool object reference, 1) Directory information ref
# Returns: 1 on success, 0 if this wasn't a valid GIF file, or -1 if
#          an output file was specified and a write error occurred
sub ProcessGIF($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $outfile = $$dirInfo{OutFile};
    my $raf = $$dirInfo{RAF};
    my $verbose = $exifTool->Options('Verbose');
    my $out = $exifTool->Options('TextOut');
    my ($a, $s, $ch, $length, $buff);
    my ($err, $newComment, $setComment);
    my ($addDirs, %doneDir);

    # verify this is a valid GIF file
    return 0 unless $raf->Read($buff, 6) == 6
        and $buff =~ /^GIF(8[79]a)$/
        and $raf->Read($s, 4) == 4;

    my $ver = $1;
    my $rtnVal = 0;

    if ($outfile) {
        $exifTool->InitWriteDirs(\%gifMap, 'XMP'); # make XMP the preferred group for GIF
        $addDirs = $exifTool->{ADD_DIRS};
        # determine if we are editing the File:Comment tag
        my $delGroup = $exifTool->{DEL_GROUP};
        if ($$delGroup{File}) {
            $setComment = 1;
            if ($$delGroup{File} == 2) {
                $newComment = $exifTool->GetNewValues('Comment');
            }
        } else {
            my $newValueHash;
            $newComment = $exifTool->GetNewValues('Comment', \$newValueHash);
            $setComment = 1 if $newValueHash;
        }
        # change to GIF 89a if adding comment or XMP
        $buff = 'GIF89a' if $$addDirs{XMP} or defined $newComment;
        Write($outfile, $buff, $s) or $err = 1;
    } else {
        my ($w, $h) = unpack("v"x2, $s);
        $exifTool->SetFileType();   # set file type
        $exifTool->FoundTag('GIFVersion', $ver);
        $exifTool->FoundTag('ImageWidth', $w);
        $exifTool->FoundTag('ImageHeight', $h);
    }
    if ($raf->Read($s, 3) == 3) {
        Write($outfile, $s) or $err = 1 if $outfile;
        if (ord($s) & 0x80) { # does this image contain a color table?
            # calculate color table size
            $length = 3 * (2 << (ord($s) & 0x07));
            $raf->Read($buff, $length) == $length or return 0; # skip color table
            Write($outfile, $buff) or $err = 1 if $outfile;
        }
        # write the comment first if necessary
        if ($outfile and defined $newComment) {
            # write comment marker
            Write($outfile, "\x21\xfe") or $err = 1;
            $verbose and print $out "  + Comment = $newComment\n";
            my $len = length($newComment);
            # write out the comment in 255-byte chunks, each
            # chunk beginning with a length byte
            my $n;
            for ($n=0; $n<$len; $n+=255) {
                my $size = $len - $n;
                $size > 255 and $size = 255;
                my $str = substr($newComment,$n,$size);
                Write($outfile, pack('C',$size), $str) or $err = 1;
            }
            Write($outfile, "\0") or $err = 1;  # empty chunk as terminator
            undef $newComment;
            ++$exifTool->{CHANGED};     # increment file changed flag
        }
        my $comment;
Block:  for (;;) {
            last unless $raf->Read($ch, 1);
            if ($outfile and ord($ch) != 0x21) {
                # add application extension containing XMP block if necessary
                # (this will place XMP before the first non-extension block)
                if (exists $$addDirs{XMP} and not defined $doneDir{XMP}) {
                    $doneDir{XMP} = 1;
                    # write new XMP data
                    my $tagTablePtr = GetTagTable('Image::ExifTool::XMP::Main');
                    my %dirInfo = ( Parent => 'GIF' );
                    $verbose and print $out "Creating XMP application extension block:\n";
                    $buff = $exifTool->WriteDirectory(\%dirInfo, $tagTablePtr);
                    if (defined $buff and length $buff) {
                        my $lz = pack('C*',1,reverse(0..255),0);
                        Write($outfile, "\x21\xff\x0bXMP DataXMP", $buff, $lz) or $err = 1;
                        ++$doneDir{XMP};    # set to 2 to indicate we added XMP
                    } else {
                        $verbose and print $out "  -> no XMP to add\n";
                    }
                }
            }
            if (ord($ch) == 0x2c) {
                Write($outfile, $ch) or $err = 1 if $outfile;
                # image descriptor
                last unless $raf->Read($buff, 8) == 8;
                last unless $raf->Read($ch, 1);
                Write($outfile, $buff, $ch) or $err = 1 if $outfile;
                if (ord($ch) & 0x80) { # does color table exist?
                    $length = 3 * (2 << (ord($ch) & 0x07));
                    # skip the color table
                    last unless $raf->Read($buff, $length) == $length;
                    Write($outfile, $buff) or $err = 1 if $outfile;
                }
                # skip "LZW Minimum Code Size" byte
                last unless $raf->Read($buff, 1);
                Write($outfile,$buff) or $err = 1 if $outfile;
                # skip image blocks
                for (;;) {
                    last unless $raf->Read($ch, 1);
                    Write($outfile, $ch) or $err = 1 if $outfile;
                    last unless ord($ch);
                    last unless $raf->Read($buff, ord($ch));
                    Write($outfile,$buff) or $err = 1 if $outfile;
                }
                next;  # continue with next field
            }
#               last if ord($ch) == 0x3b;  # normal end of GIF marker
            unless (ord($ch) == 0x21) {
                if ($outfile) {
                    Write($outfile, $ch) or $err = 1;
                    # copy the rest of the file
                    while ($raf->Read($buff, 65536)) {
                        Write($outfile, $buff) or $err = 1;
                    }
                }
                $rtnVal = 1;
                last;
            }
            # get extension block type/size
            last unless $raf->Read($s, 2) == 2;
            # get marker and block size
            ($a,$length) = unpack("C"x2, $s);
            if ($a == 0xfe) {  # is this a comment?
                if ($setComment) {
                    ++$exifTool->{CHANGED}; # increment the changed flag
                } else {
                    Write($outfile, $ch, $s) or $err = 1 if $outfile;
                }
                while ($length) {
                    last unless $raf->Read($buff, $length) == $length;
                    if ($verbose > 2 and not $outfile) {
                        Image::ExifTool::HexDump(\$buff, undef, Out => $out);
                    }
                    # add buffer to comment string
                    $comment = defined $comment ? $comment . $buff : $buff;
                    last unless $raf->Read($ch, 1);  # read next block header
                    $length = ord($ch);  # get next block size

                    # write or delete comment
                    next unless $outfile;
                    if ($setComment) {
                        $verbose and print $out "  - Comment = $buff\n";
                    } else {
                        Write($outfile, $buff, $ch) or $err = 1;
                    }
                }
                last if $length;    # was a read error if length isn't zero
                unless ($outfile) {
                    $rtnVal = 1;
                    $exifTool->FoundTag('Comment', $comment) if $comment;
                    undef $comment;
                    # assume no more than one comment in FastScan mode
                    last if $exifTool->Options('FastScan');
                }
                next;
            } elsif ($a == 0xff and $length == 0x0b) {
                # look for XMP data
                last unless $raf->Read($buff, $length) == $length;
                if ($verbose) {
                    my @a = unpack('a8a3', $buff);
                    s/\0.*//s foreach @a;
                    print $out "Application Extension: @a\n";
                }
                if ($buff eq 'XMP DataXMP') {
                    my $hdr = "$ch$s$buff";
                    # read XMP data
                    my $xmp = '';
                    for (;;) {
                        $raf->Read($ch, 1) or last Block;   # read next block header
                        $length = ord($ch) or last;         # get next block size
                        $raf->Read($buff, $length) == $length or last Block;
                        $xmp .= $ch . $buff;
                    }
                    # get length of XMP without landing zone data
                    # (note that LZ data may not be exactly the same as what we use)
                    my $xmpLen;
                    if ($xmp =~ /<\?xpacket end=['"][wr]['"]\?>/g) {
                        $xmpLen = pos($xmp);
                    } else {
                        $xmpLen = length($xmp);
                    }
                    my %dirInfo = (
                        DataPt  => \$xmp,
                        DataLen => length $xmp,
                        DirLen  => $xmpLen,
                        Parent  => 'GIF',
                    );
                    my $tagTablePtr = GetTagTable('Image::ExifTool::XMP::Main');
                    if ($outfile) {
                        if ($doneDir{XMP} and $doneDir{XMP} > 1) {
                            $exifTool->Warn('Duplicate XMP block created');
                        }
                        my $newXMP = $exifTool->WriteDirectory(\%dirInfo, $tagTablePtr);
                        if (not defined $newXMP) {
                            Write($outfile, $hdr, $xmp) or $err = 1;  # write original XMP
                            $doneDir{XMP} = 1;
                        } elsif (length $newXMP) {
                            if ($newXMP =~ /\0/) { # (check just to be safe)
                                $exifTool->Error('XMP contained NULL character');
                            } else {
                                # write new XMP and landing zone
                                my $lz = pack('C*',1,reverse(0..255),0);
                                Write($outfile, $hdr, $newXMP, $lz) or $err = 1;
                            }
                            $doneDir{XMP} = 1;
                        } # else we are deleting the XMP
                    } else {
                        $exifTool->ProcessDirectory(\%dirInfo, $tagTablePtr);
                    }
                    next;
                } else {
                    $raf->Seek(-$length, 1) or last;
                }
            }
            Write($outfile, $ch, $s) or $err = 1 if $outfile;
            # skip the block
            while ($length) {
                last unless $raf->Read($buff, $length) == $length;
                Write($outfile, $buff) or $err = 1 if $outfile;
                last unless $raf->Read($ch, 1);  # read next block header
                Write($outfile, $ch) or $err = 1 if $outfile;
                $length = ord($ch);  # get next block size
            }
        }
        $exifTool->FoundTag('Comment', $comment) if $comment and not $outfile;
    }
    # set return value to -1 if we only had a write error
    $rtnVal = -1 if $rtnVal and $err;
    return $rtnVal;
}


1;  #end

__END__

=head1 NAME

Image::ExifTool::GIF - Read and write GIF meta information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to read and
write GIF meta information.  GIF87a images contain no meta information, and
only the Comment tag is currently supported in GIF89a images.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.w3.org/Graphics/GIF/spec-gif89a.txt>

=back

=head1 SEE ALSO

L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
