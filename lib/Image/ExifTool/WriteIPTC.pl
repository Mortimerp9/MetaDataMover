#------------------------------------------------------------------------------
# File:         WriteIPTC.pl
#
# Description:  Write IPTC meta information
#
# Revisions:    12/15/2004 - P. Harvey Created
#------------------------------------------------------------------------------

package Image::ExifTool::IPTC;

use strict;

# mandatory IPTC tags for each record
my %mandatory = (
    1 => {
        0  => 4,        # EnvelopeRecordVersion
    },
    2 => {
        0  => 4,        # ApplicationRecordVersion
    },
    3 => {
        0  => 4,        # NewsPhotoVersion
    },
);

# manufacturer strings for IPTCPictureNumber
my %manufacturer = (
    1 => 'Associated Press, USA',
    2 => 'Eastman Kodak Co, USA',
    3 => 'Hasselblad Electronic Imaging, Sweden',
    4 => 'Tecnavia SA, Switzerland',
    5 => 'Nikon Corporation, Japan',
    6 => 'Coatsworth Communications Inc, Canada',
    7 => 'Agence France Presse, France',
    8 => 'T/One Inc, USA',
    9 => 'Associated Newspapers, UK',
    10 => 'Reuters London',
    11 => 'Sandia Imaging Systems Inc, USA',
    12 => 'Visualize, Spain',
);

my %iptcCharsetInv = ( 'UTF8' => "\x1b%G" );

# ISO 2022 Character Coding Notes
# -------------------------------
# Character set designation: (0x1b I F, or 0x1b I I F)
# Initial character 0x1b (ESC)
# Intermediate character I:
#   0x28 ('(') - G0, 94 chars
#   0x29 (')') - G1, 94 chars
#   0x2a ('*') - G2, 94 chars
#   0x2b ('+') - G3, 94 chars
#   0x2c (',') - G1, 96 chars
#   0x2d ('-') - G2, 96 chars
#   0x2e ('.') - G3, 96 chars
#   0x24 I ('$I') - multiple byte graphic sets (I from above)
#   I 0x20 ('I ') - dynamically redefinable character sets
# Final character:
#   0x30 - 0x3f = private character set
#   0x40 - 0x7f = standardized character set
# Character set invocation:
#   G0 : SI = 0x15
#   G1 : SO = 0x14,             LS1R = 0x1b 0x7e ('~')
#   G2 : LS2 = 0x1b 0x6e ('n'), LS2R = 0x1b 0x7d ('}')
#   G3 : LS3 = 0x1b 0x6f ('o'), LS3R = 0x1b 0x7c ('|')
#   (the locking shift "R" codes shift into 0x80-0xff space)
# Single character invocation:
#   G2 : SS2 = 0x1b 0x8e (or 0x4e in 7-bit)
#   G3 : SS3 = 0x1b 0x8f (or 0x4f in 7-bit)
# Control chars (designated and invoked)
#   C0 : 0x1b 0x21 F (0x21 = '!')
#   C1 : 0x1b 0x22 F (0x22 = '"')
# Complete codes (control+graphics, designated and involked)
#   0x1b 0x25 F   (0x25 = '%')
#   0x1b 0x25 I F
#   0x1b 0x25 0x47 ("\x1b%G") - UTF-8
#   0x1b 0x25 0x40 ("\x1b%@") - return to ISO 2022
# -------------------------------

#------------------------------------------------------------------------------
# Inverse print conversion for CodedCharacterSet
# Inputs: 0) value
sub PrintInvCodedCharset($)
{
    my $val = shift;
    my $code = $iptcCharsetInv{uc($val)};
    unless ($code) {
        if (($code = $val) =~ s/ESC /\x1b/g) {  # translate ESC chars
            $code =~ s/, \x1b/\x1b/g;   # remove comma separators
            $code =~ tr/ //d;           # remove spaces
        } else {
            warn "Bad syntax (use 'UTF8' or 'ESC X Y[, ...]')\n";
        }
    }
    return $code;
}

#------------------------------------------------------------------------------
# validate raw values for writing
# Inputs: 0) ExifTool object reference, 1) tagInfo hash reference,
#         2) raw value reference
# Returns: error string or undef (and possibly changes value) on success
sub CheckIPTC($$$)
{
    my ($exifTool, $tagInfo, $valPtr) = @_;
    my $format = $$tagInfo{Format} || $tagInfo->{Table}->{FORMAT} || '';
    if ($format =~ /^int(\d+)/) {
        my $bytes = int(($1 || 0) / 8);
        if ($bytes ne 1 and $bytes ne 2 and $bytes ne 4) {
            return "Can't write $bytes-byte integer";
        }
        my $val = $$valPtr;
        unless (Image::ExifTool::IsInt($val)) {
            return 'Not an integer' unless Image::ExifTool::IsHex($val);
            $val = $$valPtr = hex($val);
        }
        my $n;
        for ($n=0; $n<$bytes; ++$n) { $val >>= 8; }
        return "Value too large for $bytes-byte format" if $val;
    } elsif ($format =~ /^(string|digits)\[?(\d+),?(\d*)\]?$/) {
        my ($fmt, $minlen, $maxlen) = ($1, $2, $3);
        my $len = length $$valPtr;
        if ($fmt eq 'digits') {
            return 'Non-numeric characters in value' unless $$valPtr =~ /^\d+$/;
            # left pad with zeros if necessary
            $$valPtr = ('0' x ($len - $minlen)) . $$valPtr if $len < $minlen;
        }
        if ($minlen) {
            $maxlen or $maxlen = $minlen;
            return "String too short (minlen is $minlen)" if $len < $minlen;
            return "String too long (maxlen is $maxlen)" if $len > $maxlen;
        }
    } else {
        return "Bad IPTC Format ($format)";
    }
    return undef;
}

#------------------------------------------------------------------------------
# format IPTC data for writing
# Inputs: 0) ExifTool object ref, 1) tagInfo pointer,
#         2) value reference (changed if necessary),
#         3) reference to character set for translation (changed if necessary)
#         4) record number, 5) flag set to read value (instead of write)
sub FormatIPTC($$$$$;$)
{
    my ($exifTool, $tagInfo, $valPtr, $xlatPtr, $rec, $read) = @_;
    return unless $$tagInfo{Format};
    if ($$tagInfo{Format} =~ /^int(\d+)/) {
        if ($read) {
            my $len = length($$valPtr);
            if ($len <= 8) {    # limit integer conversion to 8 bytes long
                my $val = 0;
                my $i;
                for ($i=0; $i<$len; ++$i) {
                    $val = $val * 256 + ord(substr($$valPtr, $i, 1));
                }
                $$valPtr = $val;
            }
        } else {
            my $len = int(($1 || 0) / 8);
            if ($len == 1) {        # 1 byte
                $$valPtr = chr($$valPtr);
            } elsif ($len == 2) {   # 2-byte integer
                $$valPtr = pack('n', $$valPtr);
            } else {                # 4-byte integer
                $$valPtr = pack('N', $$valPtr);
            }
        }
    } elsif ($$tagInfo{Format} =~ /^string/) {
        if ($rec == 1) {
            if ($$tagInfo{Name} eq 'CodedCharacterSet') {
                $$xlatPtr = HandleCodedCharset($exifTool, $$valPtr);
            }
        } elsif ($$xlatPtr and $rec < 7 and $$valPtr =~ /[\x80-\xff]/) {
            TranslateCodedString($exifTool, $valPtr, $xlatPtr, $read);
        }
    }
}

#------------------------------------------------------------------------------
# generate IPTC-format date
# Inputs: 0) EXIF-format date string (YYYY:MM:DD) or date/time string
# Returns: IPTC-format date string (YYYYMMDD), or undef and issue warning on error
sub IptcDate($)
{
    my $val = shift;
    unless ($val =~ s/.*(\d{4}):?(\d{2}):?(\d{2}).*/$1$2$3/) {
        warn "Invalid date format (use YYYY:MM:DD)\n";
        undef $val;
    }
    return $val;
}

#------------------------------------------------------------------------------
# generate IPTC-format time
# Inputs: 0) EXIF-format time string (HH:MM:SS[+/-HH:MM]) or date/time string
# Returns: IPTC-format time string (HHMMSS+HHMM), or undef and issue warning on error
sub IptcTime($)
{
    my $val = shift;
    if ($val =~ /\s*\b(\d{1,2}):?(\d{2}):?(\d{2})(\S*)\s*$/) {
        $val = sprintf("%.2d%.2d%.2d",$1,$2,$3);
        my $tz = $4;
        if ($tz =~ /([+-]\d{1,2}):?(\d{2})/) {
            $tz = sprintf("%+.2d%.2d",$1,$2);
        } elsif ($tz !~ /Z/i and eval 'require POSIX') {
            # use local timezone by default
            $tz = POSIX::strftime('%z',localtime);
            $tz =~ /^[-+]\d{4}$/ or $tz = '+0000';
        } else {
            $tz = '+0000';  # don't know the time zone
        }
        $val .= $tz;
    } else {
        warn "Invalid time format (use HH:MM:SS[+/-HH:MM])\n";
        undef $val;     # time format error
    }
    return $val;
}

#------------------------------------------------------------------------------
# Convert picture number
# Inputs: 0) value
# Returns: Converted value
sub ConvertPictureNumber($)
{
    my $val = shift;
    if ($val eq "\0" x 16) {
        $val = 'Unknown';
    } elsif (length $val >= 16) {
        my @vals = unpack('nNA8n', $val);
        $val = $vals[0];
        my $manu = $manufacturer{$val};
        $val .= " ($manu)" if $manu;
        $val .= ', equip ' . $vals[1];
        $vals[2] =~ s/(\d{4})(\d{2})(\d{2})/$1:$2:$3/;
        $val .= ", $vals[2], no. $vals[3]";
    } else {
        $val = '<format error>'
    }
    return $val;
}

#------------------------------------------------------------------------------
# Inverse picture number conversion
# Inputs: 0) value
# Returns: Converted value (or undef on error)
sub InvConvertPictureNumber($)
{
    my $val = shift;
    $val =~ s/\(.*\)//g;    # remove manufacturer description
    $val =~ tr/://d;        # remove date separators
    $val =~ tr/0-9/ /c;     # turn remaining non-numbers to spaces
    my @vals = split ' ', $val;
    if (@vals >= 4) {
        $val = pack('nNA8n', @vals);
    } elsif ($val =~ /unknown/i) {
        $val = "\0" x 16;
    } else {
        undef $val;
    }
    return $val;
}

#------------------------------------------------------------------------------
# Write IPTC data record
# Inputs: 0) ExifTool object reference, 1) source dirInfo reference,
#         2) tag table reference
# Returns: IPTC data block (may be empty if no IPTC data)
# Notes: Increments ExifTool CHANGED flag for each tag changed
sub WriteIPTC($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    $exifTool or return 1;    # allow dummy access to autoload this package
    my $dataPt = $$dirInfo{DataPt};
    unless ($dataPt) {
        my $emptyData = '';
        $dataPt = \$emptyData;
    }
    my $start = $$dirInfo{DirStart} || 0;
    my $dirLen = $$dirInfo{DirLen};
    my $verbose = $exifTool->Options('Verbose');
    my $out = $exifTool->Options('TextOut');
    my ($tagInfo, %iptcInfo, $tag);

    # begin by assuming IPTC is coded in Latin unless otherwise specified
    my $xlat = $exifTool->Options('Charset');
    undef $xlat if $xlat eq 'Latin';

    # make sure our dataLen is defined (note: allow zero length directory)
    unless (defined $dirLen) {
        my $dataLen = $$dirInfo{DataLen};
        $dataLen = length($$dataPt) unless defined $dataLen;
        $dirLen = $dataLen - $start;
    }
    # quick check for improperly byte-swapped IPTC
    if ($dirLen >= 4 and substr($$dataPt, $start, 1) ne "\x1c" and
                         substr($$dataPt, $start + 3, 1) eq "\x1c")
    {
        $exifTool->Warn('IPTC data was improperly byte-swapped');
        my $newData = pack('N*', unpack('V*', substr($$dataPt, $start, $dirLen) . "\0\0\0"));
        $dataPt = \$newData;
        $start = 0;
        # NOTE: MUST NOT access $dirInfo DataPt, DirStart or DataLen after this!
    }
    # generate lookup so we can find the record numbers
    my %recordNum;
    foreach $tag (Image::ExifTool::TagTableKeys($tagTablePtr)) {
        $tagInfo = $tagTablePtr->{$tag};
        $$tagInfo{SubDirectory} or next;
        my $table = $tagInfo->{SubDirectory}->{TagTable} or next;
        my $subTablePtr = Image::ExifTool::GetTagTable($table);
        $recordNum{$subTablePtr} = $tag;
        Image::ExifTool::GenerateTagIDs($subTablePtr);
    }

    # loop through new values and accumulate all IPTC information
    # into lists based on their IPTC record type
    foreach $tagInfo ($exifTool->GetNewTagInfoList()) {
        my $table = $$tagInfo{Table};
        my $record = $recordNum{$table};
        # ignore tags we aren't writing to this directory
        next unless defined $record;
        $iptcInfo{$record} = [] unless defined $iptcInfo{$record};
        push @{$iptcInfo{$record}}, $tagInfo;
    }

    # get sorted list of records used.  Might as well be organized and
    # write our records in order of record number first, then tag number
    my @recordList = sort { $a <=> $b } keys %iptcInfo;
    my ($record, %set);
    foreach $record (@recordList) {
        # sort tagInfo lists by tagID
        @{$iptcInfo{$record}} = sort { $$a{TagID} <=> $$b{TagID} } @{$iptcInfo{$record}};
        # build hash of all tagIDs to set
        foreach $tagInfo (@{$iptcInfo{$record}}) {
            $set{$record}->{$$tagInfo{TagID}} = $tagInfo;
        }
    }
    # run through the old IPTC data, inserting our records in
    # sequence and deleting existing records where necessary
    # (the IPTC specification states that records must occur in
    # numerical order, but tags within records need not be ordered)
    my $pos = $start;
    my $tail = $pos;        # old data written up to this point
    my $dirEnd = $start + $dirLen;
    my $newData = '';
    my $lastRec = -1;
    my $lastRecPos = 0;
    my $allMandatory = 0;
    my %foundRec;           # found flags: 0x01-existed before, 0x02-deleted, 0x04-created

    for (;;$tail=$pos) {
        # get next IPTC record from input directory
        my ($id, $rec, $tag, $len, $valuePtr);
        if ($pos + 5 <= $dirEnd) {
            my $buff = substr($$dataPt, $pos, 5);
            ($id, $rec, $tag, $len) = unpack("CCCn", $buff);
            if ($id == 0x1c) {
                if ($rec < $lastRec) {
                    if ($rec == 0) {
                        return undef if $exifTool->Warn("IPTC record 0 encountered, subsequent records ignored", 1);
                        undef $rec;
                        $pos = $dirEnd;
                        $len = 0;
                    } else {
                        return undef if $exifTool->Warn("IPTC doesn't conform to spec: Records out of sequence", 1);
                    }
                }
                # handle extended IPTC entry if necessary
                $pos += 5;      # step to after field header
                if ($len & 0x8000) {
                    my $n = $len & 0x7fff;  # get num bytes in length field
                    if ($pos + $n <= $dirEnd and $n <= 8) {
                        # determine length (a big-endian, variable sized int)
                        for ($len = 0; $n; ++$pos, --$n) {
                            $len = $len * 256 + ord(substr($$dataPt, $pos, 1));
                        }
                    } else {
                        $len = $dirEnd;     # invalid length
                    }
                }
                $valuePtr = $pos;
                $pos += $len;   # step $pos to next entry
                # make sure we don't go past the end of data
                # (this can only happen if original data is bad)
                $pos = $dirEnd if $pos > $dirEnd;
            } else {
                undef $rec;
            }
        }
        if (not defined $rec or $rec != $lastRec) {
            # write out all our records that come before this one
            for (;;) {
                my $newRec = $recordList[0];
                if (not defined $newRec or $newRec != $lastRec) {
                    # handle mandatory tags in last record unless it was empty
                    if (length $newData > $lastRecPos) {
                        if ($allMandatory > 1) {
                            # entire lastRec contained mandatory tags, and at least one tag
                            # was deleted, so delete entire record unless we specifically
                            # added a mandatory tag
                            my $num = 0;
                            foreach (keys %{$foundRec{$lastRec}}) {
                                my $code = $foundRec{$lastRec}->{$_};
                                $num = 0, last if $code & 0x04;
                                ++$num if ($code & 0x03) == 0x01;
                            }
                            if ($num) {
                                $newData = substr($newData, 0, $lastRecPos);
                                $verbose > 1 and print $out "    - $num mandatory tags\n";
                            }
                        } elsif ($mandatory{$lastRec} and
                                 $tagTablePtr eq \%Image::ExifTool::IPTC::Main)
                        {
                            # add required mandatory tags
                            my $mandatory = $mandatory{$lastRec};
                            my ($mandTag, $subTablePtr);
                            foreach $mandTag (sort { $a <=> $b } keys %$mandatory) {
                                next if $foundRec{$lastRec}->{$mandTag};
                                unless ($subTablePtr) {
                                    $tagInfo = $tagTablePtr->{$lastRec};
                                    $tagInfo and $$tagInfo{SubDirectory} or warn("WriteIPTC: Internal error 1\n"), next;
                                    $tagInfo->{SubDirectory}->{TagTable} or next;
                                    $subTablePtr = Image::ExifTool::GetTagTable($tagInfo->{SubDirectory}->{TagTable});
                                }
                                $tagInfo = $subTablePtr->{$mandTag} or warn("WriteIPTC: Internal error 2\n"), next;
                                my $value = $mandatory->{$mandTag};
                                $verbose > 1 and print $out "    + IPTC:$$tagInfo{Name} = '$value' (mandatory)\n";
                                # apply necessary format conversions
                                FormatIPTC($exifTool, $tagInfo, \$value, \$xlat, $lastRec);
                                $len = length $value;
                                # generate our new entry
                                my $entry = pack("CCCn", 0x1c, $lastRec, $mandTag, length($value));
                                $newData .= $entry . $value;    # add entry to new IPTC data
                                ++$exifTool->{CHANGED};
                            }
                        }
                    }
                    last unless defined $newRec;
                    $lastRec = $newRec;
                    $lastRecPos = length $newData;
                    $allMandatory = 1;
                }
                $tagInfo = ${$iptcInfo{$newRec}}[0];
                my $newTag = $$tagInfo{TagID};
                # compare current entry with entry next in line to write out
                # (write out our tags in numerical order even though
                # this isn't required by the IPTC spec)
                last if defined $rec and $rec <= $newRec;
                my $newValueHash = $exifTool->GetNewValueHash($tagInfo);
                # only add new values if...
                my ($doSet, @values);
                my $found = $foundRec{$newRec}->{$newTag} || 0;
                if ($found & 0x02) {
                    # ...tag existed before and was deleted
                    $doSet = 1;
                } elsif ($$tagInfo{List}) {
                    # ...tag is List and it existed before or we are creating it
                    $doSet = 1 if $found or Image::ExifTool::IsCreating($newValueHash);
                } else {
                    # ...tag didn't exist before and we are creating it
                    $doSet = 1 if not $found and Image::ExifTool::IsCreating($newValueHash);
                }
                if ($doSet) {
                    @values = Image::ExifTool::GetNewValues($newValueHash);
                    @values and $foundRec{$newRec}->{$newTag} = $found | 0x04;
                    # write tags for each value in list
                    my $value;
                    foreach $value (@values) {
                        $verbose > 1 and print $out "    + IPTC:$$tagInfo{Name} = '$value'\n";
                        # reset allMandatory flag if a non-mandatory tag is written
                        if ($allMandatory) {
                            my $mandatory = $mandatory{$newRec};
                            $allMandatory = 0 unless $mandatory and $mandatory->{$newTag};
                        }
                        # apply necessary format conversions
                        FormatIPTC($exifTool, $tagInfo, \$value, \$xlat, $newRec);
                        # (note: IPTC string values are NOT null terminated)
                        $len = length $value;
                        # generate our new entry
                        my $entry = pack("CCC", 0x1c, $newRec, $newTag);
                        if ($len <= 0x7fff) {
                            $entry .= pack("n", $len);
                        } else {
                            # extended dataset tag
                            $entry .= pack("nN", 0x8004, $len);
                        }
                        $newData .= $entry . $value;    # add entry to new IPTC data
                        ++$exifTool->{CHANGED};
                    }
                }
                # remove this tagID from the sorted write list
                shift @{$iptcInfo{$newRec}};
                shift @recordList unless @{$iptcInfo{$newRec}};
            }
            # all done if no more records to write
            last unless defined $rec;
            # update last record variables
            $lastRec = $rec;
            $lastRecPos = length $newData;
            $allMandatory = 1;
        }
        # set flag indicating we found this tag
        $foundRec{$rec}->{$tag} = 1;
        # write out this record unless we are setting it with a new value
        $tagInfo = $set{$rec}->{$tag};
        if ($tagInfo) {
            my $newValueHash = $exifTool->GetNewValueHash($tagInfo);
            $len = $pos - $valuePtr;
            my $val = substr($$dataPt, $valuePtr, $len);
            my $oldXlat = $xlat;
            FormatIPTC($exifTool, $tagInfo, \$val, \$xlat, $rec, 1);
            if (Image::ExifTool::IsOverwriting($newValueHash, $val)) {
                $xlat = $oldXlat;   # don't change translation (not writing this value)
                $verbose > 1 and print $out "    - IPTC:$$tagInfo{Name} = '$val'\n";
                ++$exifTool->{CHANGED};
                # set deleted flag to indicate we found and deleted this tag
                $foundRec{$rec}->{$tag} |= 0x02;
                # set allMandatory flag to 2 indicating a tag was removed
                $allMandatory and ++$allMandatory;
                next;
            }
        } elsif ($rec == 1 and $tag == 90) {
            # handle CodedCharacterSet tag
            my $val = substr($$dataPt, $valuePtr, $pos - $valuePtr);
            $xlat = HandleCodedCharset($exifTool, $val);
        }
        # reset allMandatory flag if a non-mandatory tag is written
        if ($allMandatory) {
            my $mandatory = $mandatory{$rec};
            unless ($mandatory and $mandatory->{$tag}) {
                $allMandatory = 0;
            }
        }
        # write out the record
        $newData .= substr($$dataPt, $tail, $pos-$tail);
    }
    # make sure the rest of the data is zero
    if ($tail < $dirEnd) {
        my $trailer = substr($$dataPt, $tail, $dirEnd-$tail);
        if ($trailer =~ /[^\0]/) {
            return undef if $exifTool->Warn('Unrecognized data in IPTC trailer', 1);
        }
    }
    return $newData;
}


1; # end

__END__

=head1 NAME

Image::ExifTool::WriteIPTC.pl - Write IPTC meta information

=head1 SYNOPSIS

This file is autoloaded by Image::ExifTool::IPTC.

=head1 DESCRIPTION

This file contains routines to write IPTC metadata, plus a few other
seldom-used routines.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool::IPTC(3pm)|Image::ExifTool::IPTC>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
