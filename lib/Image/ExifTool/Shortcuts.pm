#------------------------------------------------------------------------------
# File:         Shortcuts.pm
#
# Description:  ExifTool shortcut tags
#
# Revisions:    02/07/2004 - P. Harvey Moved out of Exif.pm
#               09/15/2004 - P. Harvey Added D70Boring from Greg Troxel
#               01/11/2005 - P. Harvey Added Canon20D from Christian Koller
#               03/03/2005 - P. Harvey Added user defined shortcuts
#               03/26/2005 - P. Harvey Added Nikon from Tom Christiansen
#------------------------------------------------------------------------------

package Image::ExifTool::Shortcuts;

use strict;
use vars qw($VERSION);

$VERSION = '1.20';

# this is a special table used to define command-line shortcuts
%Image::ExifTool::Shortcuts::Main = (
    # this shortcut allows the three common date/time tags to be shifted at once
    AllDates => [
        'DateTimeOriginal',
        'CreateDate',
        'ModifyDate',
    ],
    # This is a shortcut to some common information which is useful in most images
    Common => [
        'FileName',
        'FileSize',
        'Model',
        'DateTimeOriginal',
        'ImageSize',
        'Quality',
        'FocalLength',
        'ShutterSpeed',
        'Aperture',
        'ISO',
        'WhiteBalance',
        'Flash',
    ],
    # This shortcut provides the same information as the Canon utilities
    Canon => [
        'FileName',
        'Model',
        'DateTimeOriginal',
        'ShootingMode',
        'ShutterSpeed',
        'Aperture',
        'MeteringMode',
        'ExposureCompensation',
        'ISO',
        'Lens',
        'FocalLength',
        'ImageSize',
        'Quality',
        'FlashOn',
        'FlashType',
        'ConditionalFEC',
        'RedEyeReduction',
        'ShutterCurtainHack',
        'WhiteBalance',
        'FocusMode',
        'Contrast',
        'Sharpness',
        'Saturation',
        'ColorTone',
        'FileSize',
        'FileNumber',
        'DriveMode',
        'OwnerName',
        'SerialNumber',
    ],
    # courtesy of Christian Koller
    Canon20D => [
        'FileName',
        'Model',
        'DateTimeOriginal',
        'ShootingMode',
        'ShutterSpeedValue', #changed for 20D
        'ApertureValue', #changed for 20D
        'MeteringMode',
        'ExposureCompensation',
        'ISO',
        'Lens',
        'FocalLength',
        #'ImageSize', #wrong in CR2
        'ExifImageWidth', #instead
        'ExifImageHeight', #instead
        'Quality',
        'FlashOn',
        'FlashType',
        'ConditionalFEC',
        'RedEyeReduction',
        'ShutterCurtainHack',
        'WhiteBalance',
        'FocusMode',
        'Contrast',
        'Sharpness',
        'Saturation',
        'ColorTone',
        'ColorSpace', # new
        'LongExposureNoiseReduction', #new
        'FileSize',
        'FileNumber',
        'DriveMode',
        'OwnerName',
        'SerialNumber',
    ],
    Nikon => [
        'Model',
        'SubSecDateTimeOriginal',
        'ShutterCount',
        'LensSpec',
        'FocalLength',
        'ImageSize',
        'ShutterSpeed',
        'Aperture',
        'ISO',
        'NoiseReduction',
        'ExposureProgram',
        'ExposureCompensation',
        'WhiteBalance',
        'WhiteBalanceFineTune',
        'ShootingMode',
        'Quality',
        'MeteringMode',
        'FocusMode',
        'ImageOptimization',
        'ToneComp',
        'ColorHue',
        'ColorSpace',
        'HueAdjustment',
        'Saturation',
        'Sharpness',
        'Flash',
        'FlashMode',
        'FlashExposureComp',
    ],
    # This shortcut may be useful when copying tags between files to either
    # copy the maker notes as a block or prevent it from being copied
    MakerNotes => [
        'MakerNotes',   # (for RIFF MakerNotes)
        'MakerNoteCanon',
        'MakerNoteCasio',
        'MakerNoteCasio2',
        'MakerNoteFujiFilm',
        'MakerNoteHP',
        'MakerNoteHP2',
        'MakerNoteHP4',
        'MakerNoteHP6',
        'MakerNoteISL',
        'MakerNoteJVC',
        'MakerNoteJVCText',
        'MakerNoteKodak1a',
        'MakerNoteKodak1b',
        'MakerNoteKodak2',
        'MakerNoteKodak3',
        'MakerNoteKodak4',
        'MakerNoteKodak5',
        'MakerNoteKodak6a',
        'MakerNoteKodak6b',
        'MakerNoteKodak7',
        'MakerNoteKodak8a',
        'MakerNoteKodak8b',
        'MakerNoteKodakUnknown',
        'MakerNoteKyocera',
        'MakerNoteMinolta',
        'MakerNoteMinolta2',
        'MakerNoteMinolta3',
        'MakerNoteNikon',
        'MakerNoteNikon2',
        'MakerNoteNikon3',
        'MakerNoteOlympus',
        'MakerNoteOlympus2',
        'MakerNoteLeica',
        'MakerNoteLeica2',
        'MakerNoteLeica3',
        'MakerNotePanasonic',
        'MakerNotePanasonic2',
        'MakerNotePentax',
        'MakerNotePentax2',
        'MakerNotePentax3',
        'MakerNotePentax4',
        'MakerNoteRicoh',
        'MakerNoteRicohText',
        'MakerNoteSanyo',
        'MakerNoteSanyoC4',
        'MakerNoteSanyoPatch',
        'MakerNoteSigma',
        'MakerNoteSony',
        'MakerNoteSony2',
        'MakerNoteSony3',
        'MakerNoteSony4',
        'MakerNoteSonySRF',
        'MakerNoteUnknown',
    ],
);

# load user-defined shortcuts if available
if (defined %Image::ExifTool::Shortcuts::UserDefined) {
    my $shortcut;
    foreach $shortcut (keys %Image::ExifTool::Shortcuts::UserDefined) {
        my $val = $Image::ExifTool::Shortcuts::UserDefined{$shortcut};
        # also allow simple aliases
        $val = [ $val ] unless ref $val eq 'ARRAY';
        # save the user-defined shortcut or alias
        $Image::ExifTool::Shortcuts::Main{$shortcut} = $val;
    }
}


1; # end

__END__

=head1 NAME

Image::ExifTool::Shortcuts - ExifTool shortcut tags

=head1 SYNOPSIS

This module is required by Image::ExifTool.

=head1 DESCRIPTION

This module contains definitions for tag name shortcuts used by
Image::ExifTool.  You can customize this file to add your own shortcuts.

Individual users may also add their own shortcuts to the .ExifTool_config
file in their home directory (or the directory specified by the
EXIFTOOL_HOME environment variable).  The shortcuts are defined in a hash
called %Image::ExifTool::Shortcuts::UserDefined.  The keys of the hash are
the shortcut names, and the elements are either tag names or references to
lists of tag names.

An example shortcut definition in .ExifTool_config:

    %Image::ExifTool::Shortcuts::UserDefined = (
        MyShortcut => ['createdate','exif:exposuretime','aperture'],
        MyAlias => 'FocalLengthIn35mmFormat',
    );

In this example, MyShortcut is a shortcut for the CreateDate,
EXIF:ExposureTime and Aperture tags, and MyAlias is a shortcut for
FocalLengthIn35mmFormat.

=head1 AUTHOR

Copyright 2003-2008, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
