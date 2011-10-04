#------------------------------------------------------------------------------
# File:         PrintIM.pm
#
# Description:  Read PrintIM meta information
#
# Revisions:    04/07/2004  - P. Harvey Created
#------------------------------------------------------------------------------

package Image::ExifTool::PrintIM;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess);

$VERSION = '1.04';

sub ProcessPrintIM($$$);

# PrintIM table (is this proprietary? I can't find any documentation on this)
%Image::ExifTool::PrintIM::Main = (
    PROCESS_PROC => \&ProcessPrintIM,
    GROUPS => { 0 => 'PrintIM', 1 => 'PrintIM', 2 => 'Printing' },
    PRINT_CONV => 'sprintf("0x%.8x", $val)',
    TAG_PREFIX => 'PrintIM',
);


#------------------------------------------------------------------------------
# Process PrintIM IFD
# Inputs: 0) ExifTool object ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 on success
sub ProcessPrintIM($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $offset = $$dirInfo{DirStart};
    my $size = $$dirInfo{DirLen};
    my $verbose = $exifTool->Options('Verbose');

    unless ($size) {
        $exifTool->Warn('Empty PrintIM data');
        return 0;
    }
    unless ($size > 15) {
        $exifTool->Warn('Bad PrintIM data');
        return 0;
    }
    unless (substr($$dataPt, $offset, 7) eq 'PrintIM') {
        $exifTool->Warn('Invalid PrintIM header');
        return 0;
    }
    # check size of PrintIM block
    my $num = Get16u($dataPt, $offset + 14);
    if ($size < 16 + $num * 6) {
        # size is too big, maybe byte ordering is wrong
        ToggleByteOrder();
        $num = Get16u($dataPt, $offset + 14);
        if ($size < 16 + $num * 6) {
            $exifTool->Warn('Bad PrintIM size');
            return 0;
        }
    }
    $verbose and $exifTool->VerboseDir('PrintIM', $num);
    my $n;
    for ($n=0; $n<$num; ++$n) {
        my $pos = $offset + 16 + $n * 6;
        my $tag = Get16u($dataPt, $pos);
        my $val = Get32u($dataPt, $pos + 2);
        $exifTool->HandleTag($tagTablePtr, $tag, $val,
            Index  => $n,
            DataPt => $dataPt,
            Size   => 4,
            Start  => $pos + 2,
        );
    }
    return 1;
}


1;  # end

__END__

=head1 NAME

Image::ExifTool::PrintIM - Read PrintIM meta information

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Print Image Matching meta information.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/PrintIM Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
