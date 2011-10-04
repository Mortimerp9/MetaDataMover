#------------------------------------------------------------------------------
# File:         HtmlDump.pm
#
# Description:  Dump information in hex to HTML page
#
# Revisions:    12/05/2005 - P. Harvey Created
#------------------------------------------------------------------------------

package Image::ExifTool::HtmlDump;

use strict;
use vars qw($VERSION);
use Image::ExifTool;    # only for FinishTiffDump()

$VERSION = '1.21';

sub DumpTable($$$;$$$$$);
sub Open($$$;@);
sub Write($@);

my ($bkgStart, $bkgEnd, $bkgSpan);

my $htmlHeader1 = <<_END_PART_1_;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN"
 "http://www.w3.org/TR/1998/REC-html40-19980424/loose.dtd">
<html>
<head>
<title>
_END_PART_1_

# Note: Don't change font-weight style because it can affect line height
my $htmlHeader2 = <<_END_PART_2_;
</title>
<style type="text/css">
<!--
/* character style ID's */
.D { color: #000000 } /* default color */
.V { color: #ff0000 } /* duplicate block 1 */
.W { color: #004400 } /* normal block 1 */
.X { color: #ff4488 } /* duplicate block 2 */
.Y { color: #448844 } /* normal block 2 */
.U { color: #cc8844 } /* unused data block */
.H { color: #0000ff } /* highlighted tag name */
.F { color: #aa00dd } /* actual offset differs */
.M { text-decoration: underline } /* maker notes data */
/* table styles */
table.dump {
  border-top: 1px solid gray;
  border-bottom: 1px solid gray;
}
table.dump td { padding: .2em .3em }
td.c2 {
  border-left: 1px solid gray;
  border-right: 1px solid gray;
}
pre   { margin: 0 }
table { font-size: .9em }
body  { color: black; background: white }
-->
</style>
<script language="JavaScript" type="text/JavaScript">
<!-- Begin
var t = new Array;
var mspan = new Array;
function GetElementsByClass(classname, tagname) {
  var found = new Array();
  var list = document.getElementsByTagName(tagname);
  var len = list.length;
  for (var i=0, j=0; i<len; ++i) {
    var classes = list[i].className.split(' ');
    for (var k=0; k<classes.length; ++k) {
      if (classes[k] == classname) {
        found[j++] = list[i];
        break;
      }
    }
  }
  delete list;
  return found;
}
function high(e,on) {
  var targ;
  if (e.target) targ = e.target;
  else if (e.srcElement) targ = e.srcElement;
  if (targ.nodeType == 3) targ = targ.parentNode; // defeat Safari bug
  if (!targ.name) targ = targ.parentNode; // go up another level if necessary
  if (targ.name && document.getElementsByName) {
    var col;
    var tip;
    if (on) {
      col = "#ffcc99";
      if (targ.name.substring(0,1) == 't') {
        var index = parseInt(targ.name.substring(1));
        tip = t[index];
        if (tip) delete t[index];
      }
    } else {
      col = "transparent";
    }
    // highlight anchor elements with the same name and add tool tip
    var list = document.getElementsByName(targ.name);
    for (var i=0; i<list.length; ++i) {
      list[i].style.background = col;
      if (tip) list[i].title += tip;
    }
    // use class name to highlight span elements if necessary
    for (var i=0; i<mspan.length; ++i) {
      if (mspan[i] != targ.name) continue;
      list = GetElementsByClass(targ.name, 'span');
      for (var j=0; j<list.length; ++j) {
        list[j].style.background = col;
      }
      break;
    }
  }
}
_END_PART_2_

my $htmlHeader3 = q[
// End --->
</script></head>
<body><noscript><b class=V>--&gt;
Enable JavaScript for active highlighting and information tool tips!
</b></noscript><table class=dump cellspacing=0 cellpadding=2>
<tr><td valign='top'><pre>];

my $preMouse = q(<pre onmouseover="high(event,1)" onmouseout="high(event,0)">);

#------------------------------------------------------------------------------
# New - create new HtmlDump object
# Inputs: 0) reference to HtmlDump object or HtmlDump class name
sub new
{
    local $_;
    my $that = shift;
    my $class = ref($that) || $that || 'Image::ExifTool::HtmlDump';
    return bless { Block => {}, TipNum => 0 }, $class;
}

#------------------------------------------------------------------------------
# Add information to dump
# Inputs: 0) HTML dump hash ref, 1) absolute offset in file, 2) data size,
#         3) comment string, 4) tool tip (or SAME to use previous tip),
#         5) bit flags (see below), 6) true to use same tooltip as last call
# Bits: 0x01 - print at start of line
#       0x02 - print red address
#       0x04 - maker notes data ('M'-class span)
#       0x08 - limit block length
# Notes: Block will be shown in 'unused' color if comment string begins with '['
sub Add($$$$;$$)
{
    my ($self, $start, $size, $msg, $tip, $flag, $sameTip) = @_;
    my $block = $$self{Block};
    $$block{$start} or $$block{$start} = [ ];
    if ($tip and $tip eq 'SAME') {
        $tip = '';
    } else {
        $tip = defined $tip ? '\n' . $tip : '';
        my $m = $msg;
        $m =~ s/<.*?>//g;       # remove html format codes
        $tip = "$m$tip";        # add msg as first line in tooltip
        # add size if not already done
        $tip .= "\\n($size bytes)" unless $tip =~ /\\nSize:/;
        ++$self->{TipNum};
    }
    push @{$$block{$start}}, [ $size, $msg, $tip, $flag, $self->{TipNum} ];
}

#------------------------------------------------------------------------------
# Print dump information to HTML page
# Inputs: 0) Dump information hash reference, 1) source file RAF reference,
#         2) data pointer, 3) data position, 4) output file or scalar reference,
#         5) limit level (1-3), 6) title
# Returns: non-zero if useful output was generated,
#          or -1 on error loading data and ERROR is set to offending data name
sub Print($$;$$$$$)
{
    local $_;
    my ($self, $raf, $dataPt, $dataPos, $outfile, $level, $title) = @_;
    my ($i, $buff, $rtnVal, $limit, $err);
    my $block = $$self{Block};
    $dataPos = 0 unless $dataPos;
    $outfile = \*STDOUT unless ref $outfile;
    $title = 'HtmlDump' unless $title;
    $level or $level = 0;
    my $tell = $raf->Tell();
    my @starts = sort { $a <=> $b } keys %$block;
    my $pos = 0;
    my $dataEnd = $dataPos + ($dataPt ? length($$dataPt) : 0);
    # initialize member variables
    $$self{Open} = [];
    $$self{Closed} = [];
    $$self{TipList} = [];
    $$self{MSpanList} = [];
    $$self{Cols} = [ '', '', '', '' ];  # text columns
    # set dump size limits (limits are 4x smaller if bit 0x08 set in flags)
    if ($level <= 1) {
        $limit = 1024;
    } elsif ($level <= 2) {
        $limit = 16384;
    } else {
        $limit = 256 * 1024 * 1024; # never dump bigger than 256 MB
    }
    $$self{Limit} = $limit;
    # pre-initialize open/closed hashes for all columns
    for ($i=0; $i<4; ++$i) {
        $self->{Open}->[$i] = { ID => [ ], Element => { } };
        $self->{Closed}->[$i] = { ID => [ ], Element => { } };
    }
    $bkgStart = $bkgEnd = 0;
    $bkgSpan = '';
    my $index = 0;  # initialize tooltip index
    my (@names, $wasUnused);
    for ($i=0; $i<@starts; ++$i) {
        my $start = $starts[$i];
        my $parmList = $$block{$start};
        my $len = $start - $pos;
        if ($len > 0 and not $wasUnused) {
            # we have an unused bytes before this data block
            --$i;           # dump the data block next time around
            $start = $pos;  # dump the unused bytes now
            my $str = ($len > 1) ? "unused $len bytes" : 'pad byte';
            $parmList = [ [ $len, "[$str]", undef, 0x108 ] ];
            $wasUnused = 1; # avoid re-dumping unused bytes if we get a read error
        } else {
            undef $wasUnused;
        }
        my $parms;
        foreach $parms (@$parmList) {
            my ($len, $msg, $tip, $flag, $tipNum) = @$parms;
            next unless $len > 0;
            $flag = 0 unless defined $flag;
            # generate same name for all blocks indexed by this tooltip
            my $name;
            $name = $names[$tipNum] if defined $tipNum;
            my $idx = $index;
            if ($name) {
                # get index from existing ID
                $idx = substr($name, 1);
            } else {
                $name = "t$index";
                $names[$tipNum] = $name if defined $tipNum;
                ++$index;
            }
            if ($flag == 4) {
                $bkgStart = $start - $dataPos;
                $bkgEnd = $bkgStart + $len;
                $bkgSpan = "<span class='$name M'>";
                push @{$self->{MSpanList}}, $name;
                next;
            }
            # loop until we read the value properly
            my ($end, $try);
            for ($try=0; $try<2; ++$try) {
                $end = $start + $len;
                # only load as much of the block as we are going to dump
                my $size = ($len > $limit) ? $limit / 2 : $len;
                if ($start >= $dataPos and $end <= $dataEnd) {
                    $buff = substr($$dataPt, $start-$dataPos, $size);
                    if ($len != $size) {
                        $buff .= substr($$dataPt, $start-$dataPos+$len-$size, $size);
                    }
                } else {
                    $buff = '';
                    if ($raf->Seek($start, 0) and $raf->Read($buff, $size) == $size) {
                        # read end of block
                        if ($len != $size) {
                            my $buf2 = '';
                            unless ($raf->Seek($start+$len-$size, 0) and
                                    $raf->Read($buf2, $size) == $size)
                            {
                                $err = $msg;
                                # reset $len to the actual length of available data
                                $raf->Seek(0, 2);
                                $len = $raf->Tell() - $start;
                                $tip .= "\\nError: Only $len bytes available!" if $tip;
                                next;
                            }
                            $buff .= $buf2;
                            undef $buf2;
                        }
                    } else {
                        $err = $msg;
                    }
                }
                last;
            }
            $tip and $self->{TipList}->[$idx] = $tip;
            next unless length $buff;
            # set flag to continue this line if next block is contiguous
            if ($i+1 < @starts and $parms eq $$parmList[-1] and
                ($end == $starts[$i+1] or ($end < $starts[$i+1] and $end >= $pos)))
            {
                my $nextFlag = $block->{$starts[$i+1]}->[0]->[3] || 0;
                $flag |= 0x100 unless $flag & 0x01 or $nextFlag & 0x01;
            }
            $self->DumpTable($start-$dataPos, \$buff, $msg, $name,
                             $flag, $len, $pos-$dataPos);
            undef $buff;
            $pos = $end if $pos < $end;
        }
    }
    $self->Open('','');     # close all open elements
    $raf->Seek($tell,0);

    # write output HTML file
    Write($outfile, $htmlHeader1, $title);
    if ($self->{Cols}->[0]) {
        Write($outfile, $htmlHeader2);
        my $mspan = \@{$$self{MSpanList}};
        for ($i=0; $i<@$mspan; ++$i) {
            Write($outfile, qq(mspan[$i] = "$$mspan[$i]";\n));
        }
        my $tips = \@{$$self{TipList}};
        for ($i=0; $i<@$tips; ++$i) {
            Write($outfile, qq(t[$i] = "$$tips[$i]";\n)) if defined $$tips[$i];
        }
        delete $$self{TipList};
        Write($outfile, $htmlHeader3, $self->{Cols}->[0]);
        Write($outfile, '</pre></td><td valign="top">',
                        $preMouse, $self->{Cols}->[1]);
        Write($outfile, '</pre></td><td class=c2 valign="top">',
                        $preMouse, $self->{Cols}->[2]);
        Write($outfile, '</pre></td><td valign="top">',
                        $preMouse, $self->{Cols}->[3]);
        Write($outfile, "</pre></td></tr></table>\n");
        $rtnVal = 1;
    } else {
        Write($outfile, "$title</title></head><body>\n",
                        "No EXIF or TIFF information found in image\n");
        $rtnVal = 0;
    }
    Write($outfile, "</body></html>\n");
    for ($i=0; $i<4; ++$i) {
        $self->{Cols}->[$i] = '';   # free memory
    }
    if ($err) {
        $err =~ tr/()//d;
        $$self{ERROR} = $err;
        return -1;
    }
    return $rtnVal;
}

#------------------------------------------------------------------------------
# Open or close a specified html element
# Inputs: 0) HtmlDump object ref, 1) element id, 2) element string,
#         3-N) list of column numbers (empty for all columns)
# - element id may be '' to close all elements
# - element string may be '' to close element by ID (or 0 to close without reopening)
# - element id and string may both be 1 to reopen temporarily closed elements
sub Open($$$;@)
{
    my ($self, $id, $element, @colNums) = @_;

    # loop through specified columns
    @colNums or @colNums = (0 .. $#{$self->{Open}});
    my $col;
    foreach $col (@colNums) {
        # get information about open elements in this column
        my $opHash = $self->{Open}->[$col];
        my $opElem = $$opHash{Element};
        if ($element) {
            # next if already open
            next if $$opElem{$id} and $$opElem{$id} eq $element;
        } elsif ($id and not $$opElem{$id}) {
            # next if already closed and nothing to reopen
            next unless $element eq '' and @{$self->{Closed}->[$col]->{ID}};
        }
        my $opID = $$opHash{ID};
        my $clHash = $self->{Closed}->[$col];
        my $clID = $$clHash{ID};
        my $clElem = $$clHash{Element};
        # get reference to output column list (use temp list if available)
        my $cols = $$self{TmpCols} || $$self{Cols};
        # close everything down to this element if necessary
        if ($$opElem{$id} or not $id) {
            while (@$opID) {
                my $tid = pop @$opID;
                my $e = $$opElem{$tid};
                $e =~ s/^<(\S+).*/<\/$1>/s;
                $$cols[$col] .= $e;
                if ($id eq $tid or not $id) {
                    delete $$opElem{$tid};
                    last if $id;
                    next;
                }
                # add this to the temporarily closed list
                # (because we really didn't want to close it)
                push @$clID, $tid;
                $$clElem{$tid} = $$opElem{$tid};
                delete $$opElem{$tid};
            }
            unless ($id) {
                # forget all temporarily closed elements
                $clID = $$clHash{ID} = [ ];
                $clElem = $$clHash{Element} = { };
            }
        } elsif ($$clElem{$id}) {
            # delete from the list of temporarily closed elements
            delete $$clElem{$id};
            @$clID = grep !/^$id$/, @$clID;
        }
        next if $element eq '0'; # 0 = don't reopen temporarily closed elements

        # re-open temporarily closed elements
        while (@$clID) {
            my $tid = pop @$clID;
            $$cols[$col] .= $$clElem{$tid};
            push @$opID, $tid;
            $$opElem{$tid} = $$clElem{$tid};
            delete $$clElem{$tid};
        }
        # open specified element
        if ($element and $element ne '1') {
            $$cols[$col] .= $element;
            push @$opID, $id;
            $$opElem{$id} = $element;
        }
    }
}

#------------------------------------------------------------------------------
# Dump a block of data in HTML table form
# Inputs: 0) HtmlDump object ref, 1) data position, 2) block pointer,
#         3) message, 4) object name, 5) flag, 6) full block length (actual
#         data may be shorter), 7) data end position
sub DumpTable($$$;$$$$$)
{
    my ($self, $pos, $blockPt, $msg, $name, $flag, $len, $endPos) = @_;
    $len = length $$blockPt unless defined $len;
    $endPos = 0 unless $endPos;
    my ($f0, $dblRef, $id);
    my $skipped = 0;
    if (($endPos and $pos < $endPos) or $flag & 0x02) {
        # display double-reference addresses in red
        $f0 = "<span class=V>";
        $dblRef = 1 if $endPos and $pos < $endPos;
    } else {
        $f0 = '';
    }
    my @c = ('','','','');
    $$self{TmpCols} = \@c;
    if ($name) {
        if ($msg and $msg =~ /^\[/) {
            $id = 'U';
        } else {
            if ($$self{A}) {
                $id = 'X';
                $$self{A} = 0;
            } else {
                $id = 'V';
                $$self{A} = 1;
            }
            ++$id unless $dblRef;
        }
        $name = qq{<a name=$name class=$id>};
        $msg and $msg = "$name$msg</a>";
    } else {
        $name = '';
    }
    # use base-relative offsets from now on
    my $cols = 0;
    my $p = $pos;
    if ($$self{Cont}) {
        $cols = $pos & 0x0f;
        $c[1] .= ($cols == 8) ? '  ' : ' ';
    } else {
        my $addr = $pos < 0 ? sprintf("-%.4x",-$pos) : sprintf("%5.4x",$pos);
        $self->Open('fgd', $f0, 0);
        $self->Open('fgd', '', 3);
        $c[0] .= "$addr";
        $p -= $pos & 0x0f unless $flag & 0x01;
        if ($p < $pos) {
            $self->Open('bkg', '', 1, 2); # don't underline white space
            $cols = $pos - $p;
            my $n = 3 * $cols;
            ++$n if $cols > 7;
            $c[1] .= ' ' x $n;
            $c[2] .= ' ' x $cols;
            $p = $pos;
        }
    }
    # loop through each column of hex numbers
    for (;;) {
        $self->Open('bkg', ($p>=$bkgStart and $p<$bkgEnd) ? $bkgSpan : '', 1, 2);
        $self->Open('a', $name, 1, 2);
        my $ch = substr($$blockPt,$p-$pos-$skipped,1);
        $c[1] .= sprintf("%.2x", ord($ch));
        # make the character HTML-friendly
        $ch =~ tr/\x00-\x1f\x7f-\xff/./;
        $ch =~ s/&/&amp;/g;
        $ch =~ s/>/&gt;/g;
        $ch =~ s/</&lt;/g;
        $c[2] .= $ch;
        ++$p;
        ++$cols;
        # close necessary elements
        if ($p >= $bkgEnd) {
            # close without reopening if closing anchor later
            my $arg = ($p - $pos >= $len) ? 0 : '';
            $self->Open('bkg', $arg, 1, 2);
        }
        if ($dblRef and $p >= $endPos) {
            $dblRef = 0;
            ++$id;
            $name =~ s/class=\w\b/class=$id/;
            $f0 = '';
            $self->Open('fgd', $f0, 0);
        }
        if ($p - $pos >= $len) {
            $self->Open('a', '', 1, 2);     # close our anchor
            last;
        }
        if ($cols < 16) {
            $c[1] .= ($cols == 8 ? '  ' : ' ');
            next;
        } elsif ($flag & 0x01 and $cols < $len) {
            $c[1] .= ' ';
            next;   # put it all on one line
        }
        unless ($$self{Msg}) {
            $c[3] .= $msg;
            $msg = '';
        }
        $_ .= "\n" foreach @c;  # add CR to all lines
        $$self{Msg} = 0;
        # limit data length if specified
        if ($$self{Limit}) {
            my $div = ($flag & 0x08) ? 4 : 1;
            my $lim = $$self{Limit} / (2 * $div) - 16;
            if ($p - $pos > $lim and $len - $p + $pos > $lim) {
                my $n = ($len - $p + $pos - $lim) & ~0x0f;
                if ($n > 16) { # (no use just cutting out one line)
                    $self->Open('bkg', '', 1, 2); # no underline
                    my $note = "[snip $n bytes]";
                    $note = (' ' x (24-length($note)/2)) . $note;
                    $c[0] .= "  ...\n";
                    $c[1] .= $note . (' ' x (48-length($note))) . "\n";
                    $c[2] .= "     [snip]     \n";
                    $c[3] .= "\n";
                    $p += $n;
                    $skipped += $len - length $$blockPt;
                }
            }
        }
        $c[0] .= ($p < 0 ? sprintf("-%.4x",-$p) : sprintf("%5.4x",$p));
        $cols = 0;
    }
    if ($msg) {
        $msg = " $msg" if $$self{Msg};
        $c[3] .= $msg;
    }
    if ($flag & 0x100 and $cols < 16) {    # continue on same line?
        $$self{Cont} = 1;
        $$self{Msg} = 1 if $msg;
    } else {
        $_ .= "\n" foreach @c;
        $$self{Msg} = 0;
        $$self{Cont} = 0;
    }
    # add temporary column data to our real columns
    my $i;
    for ($i=0; $i<4; ++$i) {
        $self->{Cols}->[$i] .= $c[$i];
    }
    delete $$self{TmpCols};
}

#------------------------------------------------------------------------------
# Finish dumping of TIFF image data
# Inputs: 0) HtmlDump object ref, 1) ExifTool object ref, 2) length of file
# (this really belongs in Image::ExifTool::Exif, but is placed here so it
#  is only compiled when needed)
sub FinishTiffDump($$$)
{
    my ($self, $exifTool, $size) = @_;
    my ($tag, $key, $start, $blockInfo, $i);

    # list of all indirectly referenced TIFF data tags
    my %offsetPair = (
        StripOffsets      => 'StripByteCounts',
        TileOffsets       => 'TileByteCounts',
        FreeOffsets       => 'FreeByteCounts',
        ThumbnailOffset   => 'ThumbnailLength',
        PreviewImageStart => 'PreviewImageLength',
        JpgFromRawStart   => 'JpgFromRawLength',
        OtherImageStart   => 'OtherImageLength',
        ImageOffset       => 'ImageByteCount',
        AlphaOffset       => 'AlphaByteCount',
    );

    # add TIFF data to html dump
    foreach $tag (keys %offsetPair) {
        my $info = $exifTool->GetInfo($tag);
        next unless %$info;
        foreach $key (%$info) {
            my $name = Image::ExifTool::GetTagName($key);
            my $grp1 = $exifTool->GetGroup($key, 1);
            my $info2 = $exifTool->GetInfo($offsetPair{$tag}, { Group1 => $grp1 });
            next unless %$info2;
            my ($key2) = keys %$info2;
            my $offsets = $$info{$key};
            my $byteCounts = $$info2{$key2};
            # (long lists may be SCALAR references)
            my @offsets = split ' ', (ref $offsets ? $$offsets : $offsets);
            my @byteCounts = split ' ', (ref $byteCounts ? $$byteCounts : $byteCounts);
            my $num = scalar @offsets;
            my $li = 0;
            my $padBytes = 0;
            for ($i=0; @offsets and @byteCounts; ++$i) {
                my $offset = shift @offsets;
                my $byteCount = shift @byteCounts;
                my $end = $offset + $byteCount;
                if (@offsets and @byteCounts) {
                    # show data as contiguous if only normal pad bytes between blocks
                    if ($end & 0x01 and $end + 1 == $offsets[0]) {
                        $end += 1;
                        ++$padBytes;    # count them
                    }
                    if ($end == $offsets[0]) {
                        # combine these two blocks
                        $byteCounts[0] += $offsets[0] - $offset;
                        $offsets[0] = $offset;
                        next;
                    }
                }
                my $msg = $exifTool->GetGroup($key, 1) . ':' . $tag;
                $msg =~ s/(Offsets?|Start)$/ /;
                if ($num > 1) {
                    $msg .= "$li-" if $li != $i;
                    $msg .= "$i ";
                    $li = $i + 1;
                }
                $msg .= "data";
                my $tip = "Size: $byteCount bytes";
                $tip .= ", incl. $padBytes pad bytes" if $padBytes;
                $self->Add($offset, $byteCount, "($msg)", $tip, 0x08);
            }
        }
    }
    # find offset of last dumped information, and dump any unknown trailer
    my $last = 0;
    my $block = $$self{Block};
    foreach $start (keys %$block) {
        foreach $blockInfo (@{$$block{$start}}) {
            my $end = $start + $$blockInfo[0];
            $last = $end if $last < $end;
        }
    }
    my $diff = $size - $last;
    if ($diff > 0 and ($last or $exifTool->Options('Unknown'))) {
        if ($diff > 1 or $size & 0x01) {
            $self->Add($last, $diff, "[unknown data]", "Size: $diff bytes", 0x08);
        } else {
            $self->Add($last, $diff, "[trailing pad byte]", undef, 0x08);
        }
    }
}

#------------------------------------------------------------------------------
# utility routine to write to file or memory
# Inputs: 0) file or scalar reference, 1-N) list of stuff to write
# Returns: true on success
sub Write($@)
{
    my $outfile = shift;
    if (UNIVERSAL::isa($outfile,'GLOB')) {
        return print $outfile @_;
    } elsif (ref $outfile eq 'SCALAR') {
        $$outfile .= join('', @_);
        return 1;
    }
    return 0;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::HtmlDump - Dump information in hex to HTML page

=head1 SYNOPSIS

    use Image::ExifTool::HtmlDump;
    my $dump = new Image::ExifTool::HtmlDump;
    $dump->Add($start, $size, $comment);
    $dump->Print($dumpInfo, $raf, $dataPt, $dataPos, $outfile);

=head1 DESCRIPTION

This module contains code used to generate an HTML-based hex dump of
information for debugging purposes.  This is code is called when the
ExifTool 'HtmlDump' option is used.

Currently, only EXIF and TIFF information is dumped.

=head1 BUGS

Due to a memory allocation bug in ActivePerl 5.8.x for Windows, this code
may run extremely slowly when processing large files with this version of
Perl.

An HTML 4 compliant browser is needed to properly display the generated HTML
page, but note that some of these browsers (like Mozilla) may not properly
display linefeeds in the tool tips.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

