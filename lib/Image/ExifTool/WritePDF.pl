#------------------------------------------------------------------------------
# File:         WritePDF.pl
#
# Description:  Write PDF meta information
#
# Revisions:    12/08/2007 - P. Harvey Created
#
# References:   1) http://partners.adobe.com/public/developer/pdf/index_reference.html
#
# Notes:        The special "PDF-update" group can be deleted to revert exiftool updates
#------------------------------------------------------------------------------
package Image::ExifTool::PDF;

use strict;

sub WriteObject($$);
sub EncodeString($);

# comments to mark beginning and end of ExifTool incremental update
my $beginComment = '%BeginExifToolUpdate';
my $endComment   = '%EndExifToolUpdate ';

my $keyExt;     # crypt key extension
my $pdfVer;     # version of PDF file we are currently writing


#------------------------------------------------------------------------------
# Validate raw PDF values for writing (string date integer real boolean name)
# Inputs: 0) ExifTool object ref, 1) tagInfo hash ref, 2) raw value ref
# Returns: error string or undef (and possibly changes value) on success
sub CheckPDF($$$)
{
    my ($exifTool, $tagInfo, $valPtr) = @_;
    my $format = $$tagInfo{Writable} || $tagInfo->{Table}->{WRITABLE};
    if (not $format) {
        return 'No writable format';
    } elsif ($format eq 'string') {
        # convert to Unicode if necessary
        if ($$valPtr =~ /[\x80-\xff]/) {
            $$valPtr = "\xfe\xff" . $exifTool->Charset2Unicode($$valPtr, 'MM');
        }
    } elsif ($format eq 'date') {
        # be flexible about this for now
        return 'Bad date format' unless $$valPtr =~ /^\d{4}/;
    } elsif ($format eq 'integer') {
        return 'Not an integer' unless Image::ExifTool::IsInt($$valPtr);
    } elsif ($format eq 'real') {
        return 'Not a real number' unless $$valPtr =~ /^[+-]?(?=\d|\.\d)\d*(\.\d*)?$/;
    } elsif ($format eq 'boolean') {
        $$valPtr = ($$valPtr and $$valPtr !~ /^f/i) ? 'true' : 'false';
    } elsif ($format eq 'name') {
        return 'Invalid PDF name' if $$valPtr =~ /\0/;
    } else {
        return "Invalid PDF format '$format'";
    }
    return undef;   # value is OK
}

#------------------------------------------------------------------------------
# Format value for writing to PDF file
# Inputs: 0) value, 1) format string (string,date,integer,real,boolean,name)
# Returns: formatted value or undef on error
# Notes: Called at write time, so $pdfVer may be checked
sub WritePDFValue($$)
{
    my ($val, $format) = @_;
    if (not $format) {
        return undef;
    } elsif ($format eq 'string') {
        EncodeString(\$val);
    } elsif ($format eq 'date') {
        # convert date to "D:YYYYMMDDHHMMSS+-hh'mm'" format
        $val =~ s/([-+]\d{2}):(\d{2})/$1'$2'/;  # change timezone delimiters if necessary
        $val =~ tr/ ://d;                       # remove spaces and colons
        $val =  "D:$val";                       # add leading "D:"
        EncodeString(\$val);
    } elsif ($format =~ /^(integer|real|boolean)$/) {
        # no reformatting necessary
    } elsif ($format eq 'name') {
        return undef if $val =~ /\0/;
        if ($pdfVer >= 1.2) {
            $val =~ s/([\t\n\f\r ()<>[\]{}\/%#])/sprintf('#%.2x',ord $1)/sge;
        } else {
            return undef if $val =~ /[\t\n\f\r ()<>[\]{}\/%]/;
        }
        $val = "/$val"; # add leading '/'
    } else {
        return undef;
    }
    return $val;
}

#------------------------------------------------------------------------------
# Encode PDF string
# Inputs: 0) reference to PDF string
# Returns: (updates string with encoded data)
sub EncodeString($)
{
    my $strPt = shift;
    if (ref $$strPt eq 'ARRAY') {
        my $str;
        foreach $str (@{$$strPt}) {
            EncodeString(\$str);
        }
        return;
    }
    Crypt($strPt, $keyExt);  # encrypt if necessary
    # encode as hex if we have any control characters (except tab)
    if ($$strPt=~/[\x00-\x08\x0a-\x1f\x7f\xff]/) {
        # encode as hex
        my $str='';
        my $len = length $$strPt;
        my $i = 0;
        for (;;) {
            my $n = $len - $i or last;
            $n = 40 if $n > 40; # break into reasonable-length lines
            $str .= $/ if $i;
            $str .= unpack('H*', substr($$strPt, $i, $n));
            $i += $n;
        }
        $$strPt = "<$str>";
    } else {
        $$strPt =~ s/([()\\])/\\$1/g;   # must escape round brackets and backslashes
        $$strPt = "($$strPt)";
    }
}

#------------------------------------------------------------------------------
# Get free entries from xref stream dictionary that we wrote previously
# Inputs: 0) xref dictionary reference
# Returns: free entry hash (keys are object numbers, values are xref entry list refs)
sub GetFreeEntries($)
{
    my $dict = shift;
    my %xrefFree;
    # from the start we have only written xref stream entries in 'CNn' format,
    # so we can simplify things for now and only support this type of entry
    my $w = $$dict{W};
    if (ref $w eq 'ARRAY' and "@$w" eq '1 4 2') {
        my $size = $$dict{_entry_size}; # this will be 7 for 'CNn'
        my $index = $$dict{Index};
        my $len = length $$dict{_stream};
        # scan the table for free objects
        my $num = scalar(@$index) / 2;
        my $pos = 0;
        my ($i, $j);
        for ($i=0; $i<$num; ++$i) {
            my $start = $$index[$i*2];
            my $count = $$index[$i*2+1];
            for ($j=0; $j<$count; ++$j) {
                last if $pos + $size > $len;
                my @t = unpack("x$pos CNn", $$dict{_stream});
                # add entry if object was free
                $xrefFree{$start+$j} = [ $t[1], $t[2], 'f' ] if $t[0] == 0;
                $pos += $size;  # step to next entry
            }
        }
    }
    return \%xrefFree;
}

#------------------------------------------------------------------------------
# Write PDF object
# Inputs: 0) output file or scalar ref, 1) PDF object
# Returns: true on success
# Notes: inserts white space before object, but none afterward
sub WriteObject($$)
{
    my ($outfile, $obj) = @_;
    if (ref $obj eq 'SCALAR') {
        Write($outfile, ' ', $$obj) or return 0;
    } elsif (ref $obj eq 'ARRAY') {
        # write array
        Write($outfile, @$obj > 10 ? $/ : ' ', '[') or return 0;
        my $item;
        foreach $item (@$obj) {
            WriteObject($outfile, $item) or return 0;
        }
        Write($outfile, ' ]') or return 0;
    } elsif (ref $obj eq 'HASH') {
        # write dictionary
        my $tag;
        Write($outfile, $/, '<<') or return 0;
        # add "Length" entry if this is a stream
        if ($$obj{_stream}) {
            $$obj{Length} = length $$obj{_stream};
            push @{$$obj{_tags}}, 'Length';
        }
        # don't write my internal entries
        my %wrote = ( _tags => 1, _stream => 1, _decrypted => 1,
                      _oldFilter => 1, _entry_size => 1, _table => 1 );
        # write tags in original order, adding new ones later alphabetically
        foreach $tag (@{$$obj{_tags}}, sort keys %$obj) {
            next if $wrote{$tag} or not defined $$obj{$tag};
            Write($outfile, $/, "/$tag") or return 0;
            WriteObject($outfile, $$obj{$tag}) or return 0;
            $wrote{$tag} = 1;
        }
        Write($outfile, $/, '>>') or return 0;
        if ($$obj{_stream}) {
            # (a single 0x0d may not follow 'stream', so use 0x0d+0x0a here to be sure)
            Write($outfile, $/, "stream\x0d\x0a") or return 0;
            # encrypt stream if necessary
            if ($$obj{_decrypted}) {
                delete $$obj{_decrypted};
                CryptStream($obj, $keyExt);
            }
            Write($outfile, $$obj{_stream}, $/, 'endstream') or return 0;
        }
    } else {
        # write string, number, name or object reference
        Write($outfile, ' ', $obj);
    }
    return 1;
}

#------------------------------------------------------------------------------
# Write PDF File
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 on success, 0 if not valid PDF file, -1 on write error
# Notes: dictionary structure:  Main --+--> Info
#                                      +--> Root --> Metadata
sub WritePDF($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $outfile = $$dirInfo{OutFile};
    my ($buff, $len, %capture, %newXRef, %newObj, $objRef);
    my ($out, $id, $gen, $obj);

    # create a new ExifTool object and use it to read PDF and XMP information
    my $newTool = new Image::ExifTool;
    $newTool->Options(List => 1);
    $$newTool{PDF_CAPTURE} = \%capture;
    my $info = $newTool->ImageInfo($raf, 'XMP', 'PDF:*', 'Error', 'Warning');
    # not a valid PDF file unless we got a version number
    $pdfVer = $$info{PDFVersion} or return 0;

    # check version number
    if ($pdfVer > 1.6) {
        if ($pdfVer >= 2.0) {
            $exifTool->Error("Can't yet write PDF version $pdfVer"); # (future major version changes)
            return 1;
        }
        $exifTool->Warn("ExifTool is untested with PDF version $pdfVer files", 1);
    }
    # fail if we had any serious errors while extracting information
    if ($capture{Error} or $$info{Error}) {
        $exifTool->Error($capture{Error} || $$info{Error});
        return 1;
    }
    # make sure we have everything we need to rewrite this file
    foreach $obj (qw(Main Root xref)) {
        next if $capture{$obj};
        # any warning we received may give a clue about why this object is missing
        $exifTool->Error($$info{Warning}) if $$info{Warning};
        $exifTool->Error("Can't find $obj object");
        return 1;
    }

    # copy file up to start of previous exiftool update or end of file
    $raf->Seek(-64,2) and $raf->Read($buff,64) and $raf->Seek(0,0) or return -1;
    my $rtn = 1;
    my $prevUpdate;
    if ($buff =~ /$endComment(\d+)\s+$/s) {
        $prevUpdate = $1;
        # rewrite the file up to the original EOF
        my $size = $prevUpdate;
        for (;;) {
            last unless $size;
            my $n = $size > 65536 ? 65536 : $size;
            $raf->Read($buff, $n) == $n or $rtn = -1, last;
            Write($outfile, $buff) or $rtn = -1;
            $size -= $n;
        }
        # verify that we are now at the start of an ExifTool update
        unless ($raf->Read($buff, length $beginComment) and $buff eq $beginComment) {
            $exifTool->Error('Previous ExifTool update is corrupted');
            return $rtn;
        }
        $raf->Seek($prevUpdate, 0) or $rtn = -1;
        if ($exifTool->{DEL_GROUP}->{'PDF-update'}) {
            $exifTool->VPrint(0, "  Reverted previous ExifTool updates\n");
            ++$$exifTool{CHANGED};
            return $rtn;
        }
    } elsif ($exifTool->{DEL_GROUP}->{'PDF-update'}) {
        $exifTool->Error('File contains no previous ExifTool update');
        return $rtn;
    } else {
        # rewrite the whole file
        while ($raf->Read($buff, 65536)) {
            Write($outfile, $buff) or $rtn = -1;
        }
    }
    $out = $exifTool->Options('TextOut') if $exifTool->Options('Verbose');
#
# create our new PDF objects to write
#
    my $xref = $capture{xref};
    my $mainDict = $capture{Main};
    my $metaRef = $capture{Root}->{Metadata};
    my $nextObject;

    # start by finding reference for info object in case it was deleted
    # in a previous edit so we can re-use it here if adding PDF Info
    my $prevInfoRef;
    if ($prevUpdate) {
        unless ($capture{Prev}) {
            $exifTool->Error("Can't locate trailer dictionary prior to last edit");
            return $rtn;
        }
        $prevInfoRef = $capture{Prev}->{Info};
        # start from previous size so the xref table doesn't continue
        # to grow if we repeatedly add and delete the Metadata object
        $nextObject = $capture{Prev}->{Size};
        # don't re-use Meta reference if object was added in a previous update
        undef $metaRef if $metaRef and $$metaRef=~/^(\d+)/ and $1 >= $nextObject;
    } else {
        $prevInfoRef = $$mainDict{Info};
        $nextObject = $$mainDict{Size};
    }

    # delete entire PDF group if specified
    my $infoChanged = 0;
    if ($exifTool->{DEL_GROUP}->{PDF} and $capture{Info}) {
        delete $capture{Info};
        $info = { XMP => $$info{XMP} }; # remove extracted PDF tags
        print $out "  Deleting PDF Info dictionary\n" if $out;
        ++$infoChanged;
    }

    # create new Info dictionary if necessary
    $capture{Info} = { _tags => [ ] } unless $capture{Info};
    my $infoDict = $capture{Info};

    # must pre-determine Info reference to be used in encryption
    my $infoRef = $prevInfoRef || \ "$nextObject 0 R";
    $keyExt = $$infoRef;

    # must set line separator before calling WritePDFValue()
    my $oldSep = $/;
    $/ = $capture{newline};

    # rewrite PDF Info tags
    my $newTags = $exifTool->GetNewTagInfoHash(\%Image::ExifTool::PDF::Info);
    my $tagID;
    foreach $tagID (sort keys %$newTags) {
        my $tagInfo = $$newTags{$tagID};
        my $newValueHash = $exifTool->GetNewValueHash($tagInfo);
        my (@vals, $deleted);
        my $tag = $$tagInfo{Name};
        my $val = $$info{$tag};
        my $tagKey = $tag;
        unless (defined $val) {
            # must check for tag key with copy number
            ($tagKey) = grep /^$tag/, keys %$info;
            $val = $$info{$tagKey} if $tagKey;
        }
        if (defined $val) {
            my @oldVals;
            if (ref $val eq 'ARRAY') {
                @oldVals = @$val;
                $val = shift @oldVals;
            }
            for (;;) {
                if (Image::ExifTool::IsOverwriting($newValueHash, $val) > 0) {
                    $deleted = 1;
                    print $out "    - PDF:$tag = '",$exifTool->Printable($val),"'\n" if $out;
                    ++$infoChanged;
                } else {
                    push @vals, $val;
                }
                last unless @oldVals;
                $val = shift @oldVals;
            }
            # don't write this out if we deleted all values
            delete $$infoDict{$tagID} unless @vals;
        }
        # decide whether we want to write this tag
        # (always create native PDF information, so don't check IsCreating())
        next unless $deleted or $$tagInfo{List} or not exists $$infoDict{$tagID};

        # add new values to existing ones
        my @newVals = Image::ExifTool::GetNewValues($newValueHash);
        if (@newVals) {
            push @vals, @newVals;
            ++$infoChanged;
            if ($out) {
                foreach $val (@newVals) {
                    print $out "    + PDF:$tag = '",$exifTool->Printable($val),"'\n";
                }
            }
        }
        unless (@vals) {
            # remove this entry from the Info dictionary if no values remain
            delete $$infoDict{$tagID};
            next;
        }
        # format value(s) for writing to PDF file
        my $writable = $$tagInfo{Writable} || $Image::ExifTool::PDF::Info{WRITABLE};
        if (not $$tagInfo{List}) {
            $val = WritePDFValue(shift @vals, $writable);
        } elsif ($$tagInfo{List} eq 'array') {
            foreach $val (@vals) {
                $val = WritePDFValue($val, $writable);
                defined $val or undef(@vals), last;
            }
            $val = @vals ? \@vals : undef;
        } else {
            $val = WritePDFValue(join(', ', @vals), $writable);
        }
        if (defined $val) {
            $$infoDict{$tagID} = $val;
            ++$infoChanged;
        } else {
            $exifTool->Warn("Error converting $$tagInfo{Name} value");
        }
    }
    if ($infoChanged) {
        $$exifTool{CHANGED} += $infoChanged;
    } elsif ($prevUpdate) {
        # must still write Info dictionary if it was previously updated
        my $oldPos = LocateObject($xref, $$infoRef);
        $infoChanged = 1 if $oldPos and $oldPos > $prevUpdate;
    }

    # create new Info dictionary if necessary
    if ($infoChanged) {
        # increment object count if we used a new object here
        if (scalar(keys %{$capture{Info}}) > 1) {
            $newObj{$$infoRef} = $capture{Info};# save to write later
            $$mainDict{Info} = $infoRef;        # add reference to trailer dictionary
            ++$nextObject unless $prevInfoRef;
        } else {
            # remove Info from Main (trailer) dictionary
            delete $$mainDict{Info};
            # write free entry in xref table if Info existed prior to all edits
            $newObj{$$infoRef} = '' if $prevInfoRef;
        }
    }

    # rewrite XMP
    my %xmpInfo = (
        DataPt => $$info{XMP},
        Parent => 'PDF',
    );
    my $xmpTable = GetTagTable('Image::ExifTool::XMP::Main');
    my $oldChanged = $$exifTool{CHANGED};
    my $newXMP = $exifTool->WriteDirectory(\%xmpInfo, $xmpTable);
    $newXMP = $$info{XMP} ? ${$$info{XMP}} : '' unless defined $newXMP;

    # WriteDirectory() will increment CHANGED erroneously if non-existent
    # XMP is deleted as a block -- so check for this
    unless ($newXMP or $$info{XMP}) {
        $$exifTool{CHANGED} = $oldChanged;
        $exifTool->VPrint(0, "  (XMP not changed -- still empty)\n");
    }
    my ($metaChanged, $rootChanged);

    if ($$exifTool{CHANGED} != $oldChanged and defined $newXMP) {
        $metaChanged = 1;
    } elsif ($prevUpdate and $capture{Root}->{Metadata}) {
        # must still write Metadata dictionary if it was previously updated
        my $oldPos = LocateObject($xref, ${$capture{Root}->{Metadata}});
        $metaChanged = 1 if $oldPos and $oldPos > $prevUpdate;
    }
    if ($metaChanged) {
        if ($newXMP) {
            unless ($metaRef) {
                # allocate new PDF object
                $metaRef = \ "$nextObject 0 R";
                ++$nextObject;
                $capture{Root}->{Metadata} = $metaRef;
                $rootChanged = 1;   # set flag to replace Root dictionary
            }
            # create the new metadata dictionary to write later
            $newObj{$$metaRef} = {
                Type       => '/Metadata',
                Subtype    => '/XML',
              # Length     => length $newXMP, (set by WriteObject)
                _tags      => [ qw(Type Subtype Length) ],
                _stream    => $newXMP,
                _decrypted => 1,
            };
        } elsif ($capture{Root}->{Metadata}) {
            # free existing metadata object
            $newObj{${$capture{Root}->{Metadata}}} = '';
            delete $capture{Root}->{Metadata};
            $rootChanged = 1;   # set flag to replace Root dictionary
        }
    }
    # add new Root dictionary if necessary
    my $rootRef = $$mainDict{Root};
    unless ($rootRef) {
        $exifTool->Error("Can't find Root dictionary");
        $/ = $oldSep;
        return $rtn;
    }
    if (not $rootChanged and $prevUpdate) {
        # must still write Root dictionary if it was previously updated
        my $oldPos = LocateObject($xref, $$rootRef);
        $rootChanged = 1 if $oldPos and $oldPos > $prevUpdate;
    }
    $newObj{$$rootRef} = $capture{Root} if $rootChanged;
#
# write incremental update if anything was changed
#
    if ($$exifTool{CHANGED}) {
        # remember position of original EOF
        my $oldEOF = Tell($outfile);
        Write($outfile, $beginComment) or $rtn = -1;

        # write new objects
        foreach $objRef (sort keys %newObj) {
            $objRef =~ /^(\d+) (\d+)/ or $rtn = -1, print("xxx $objRef-\n"), last;
            ($id, $gen) = ($1, $2);
            if (not $newObj{$objRef}) {
                ++$gen if $gen < 65535;
                # write free entry in xref table
                $newXRef{$id} = [ 0, $gen, 'f' ];
                next;
            }
            # create new entry for xref table
            $newXRef{$id} = [ Tell($outfile) + length($/), $gen, 'n' ];
            $keyExt = "$id $gen obj";  # (must set for stream encryption)
            Write($outfile, $/, $keyExt) or $rtn = -1;
            WriteObject($outfile, $newObj{$objRef}) or $rtn = -1;
            Write($outfile, $/, 'endobj') or $rtn = -1;
        }

        # Prev points to old xref table
        $$mainDict{Prev} = $capture{startxref} unless $prevUpdate;

        # add xref entry for head of free-object list
        $newXRef{0} = [ 0, 65535, 'f' ];

        # must insert free xref entries from previous exiftool update if applicable
        if ($prevUpdate) {
            my $mainFree;
            # extract free entries from our previous Main xref stream
            if ($$mainDict{Type} and $$mainDict{Type} eq '/XRef') {
                $mainFree = GetFreeEntries($xref->{dicts}->[0]);
            } else {
                # free entries from Main xref table already captured for us
                $mainFree = $capture{mainFree};
            }
            foreach $id (sort { $a <=> $b } keys %$mainFree) {
                $newXRef{$id} = $$mainFree{$id} unless $newXRef{$id};
            }
        }

        # connect linked list of free object in our xref table
        my $prevFree = 0;
        foreach $id (sort { $b <=> $a } keys %newXRef) { # (reverse sort)
            next unless $newXRef{$id}->[2] eq 'f';  # skip if not free
            # no need to add free entry for objects added by us
            # in previous edits then freed again
            if ($id >= $nextObject) {
                delete $newXRef{$id};   # Note: deleting newXRef entry!
                next;
            }
            $newXRef{$id}->[0] = $prevFree;
            $prevFree = $id;
        }

        # prepare our main dictionary for writing
        $$mainDict{Size} = $nextObject;    # update number of objects
        # must change the ID if it exists
        if (ref $$mainDict{ID} eq 'ARRAY' and @{$$mainDict{ID}} > 1) {
            # increment first byte since this is an easy change to make
            $id = $mainDict->{ID}->[1];
            if ($id =~ /^<([0-9a-f]{2})/i) {
                my $byte = unpack('H2',chr((hex($1) + 1) & 0xff));
                substr($id, 1, 2) = $byte;
            } elsif ($id =~ /^\((.)/s) {
                substr($id, 1, 1) = chr((ord($1) + 1) & 0xff);
            }
            $mainDict->{ID}->[1] = $id;
        }

        # remember position of xref table in file (we will write this next)
        my $startxref = Tell($outfile) + length($/);

        # must write xref as a stream in xref-stream-only files
        if ($$mainDict{Type} and $$mainDict{Type} eq '/XRef') {

            # delete encoding-related entries since we aren't encoding our stream
            delete $$mainDict{Filter};
            delete $$mainDict{DecodeParms};
            delete $$mainDict{DL};
            # create entry for the xref stream object itself
            $newXRef{$nextObject++} = [ Tell($outfile) + length($/), 0, 'n' ];
            $$mainDict{Size} = $nextObject;
            # create xref stream and Index entry
            $$mainDict{W} = [ 1, 4, 2 ];    # int8u, int32u, int16u ('CNn')
            $$mainDict{Index} = [ ];
            $$mainDict{_stream} = '';
            my @ids = sort { $a <=> $b } keys %newXRef;
            while (@ids) {
                my $startID = $ids[0];
                for (;;) {
                    $id = shift @ids;
                    my ($pos, $gen, $type) = @{$newXRef{$id}};
                    if ($pos > 0xffffffff) {
                        $exifTool->Error('Huge files not yet supported');
                        last;
                    }
                    $$mainDict{_stream} .= pack('CNn', $type eq 'f' ? 0 : 1, $pos, $gen);
                    last if not @ids or $ids[0] != $id + 1;
                }
                # add Index entries for this section of the xref stream
                push @{$$mainDict{Index}}, $startID, $id - $startID + 1;
            }
            # write the xref stream object
            $keyExt = "$id 0 obj";  # (set anyway, but xref stream should NOT be encrypted)
            Write($outfile, $/, $keyExt) or $rtn = -1;
            WriteObject($outfile, $mainDict) or $rtn = -1;
            Write($outfile, $/, 'endobj') or $rtn = -1;

        } else {

            # write new xref table
            Write($outfile, $/, 'xref', $/) or $rtn = -1;
            # lines must be exactly 20 bytes, so pad newline if necessary
            my $endl = (length($/) == 1 ? ' ' : '') . $/;
            my @ids = sort { $a <=> $b } keys %newXRef;
            while (@ids) {
                my $startID = $ids[0];
                $buff = '';
                for (;;) {
                    $id = shift @ids;
                    $buff .= sprintf("%.10d %.5d %s%s", @{$newXRef{$id}}, $endl);
                    last if not @ids or $ids[0] != $id + 1;
                }
                # write this (contiguous-numbered object) section of the xref table
                Write($outfile, $startID, ' ', $id - $startID + 1, $/, $buff) or $rtn = -1;
            }
     
            # write main (trailer) dictionary        
            Write($outfile, 'trailer') or $rtn = -1;
            WriteObject($outfile, $mainDict) or $rtn = -1;
        }
        # write pointer to main xref table and EOF marker
        Write($outfile, $/, 'startxref', $/, $startxref, $/, '%%EOF', $/) or $rtn = -1;

        # write trailing comment to allow our edit to be easily reverted
        Write($outfile, $endComment, $oldEOF, $/) or $rtn = -1;

    } elsif ($prevUpdate) {

        # nothing new changed, so copy over previous incremental update
        $raf->Seek($prevUpdate, 0) or $rtn = -1;
        while ($raf->Read($buff, 65536)) {
            Write($outfile, $buff) or $rtn = -1;
        }
    }
    undef $newTool;
    undef %capture;
    $/ = $oldSep;   # restore original separator
    return $rtn;
}


1; # end

__END__

=head1 NAME

Image::ExifTool::WritePDF.pl - Write PDF meta information

=head1 SYNOPSIS

These routines are autoloaded by Image::ExifTool::PDF.

=head1 DESCRIPTION

This file contains routines to write PDF metadata.

=head1 NOTES

When writing a PDF, exiftool does not modify the existing data.  Instead,
the PDF file is appended with an incremental update which can easily be
removed to revert the file (by using ExifTool to delete the special
C<PDF-update> pseudo group).

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://partners.adobe.com/public/developer/pdf/index_reference.html>

=back

=head1 SEE ALSO

L<Image::ExifTool::PDF(3pm)|Image::ExifTool::PDF>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
