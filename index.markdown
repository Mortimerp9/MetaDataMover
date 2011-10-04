---
title: MetaDataMover Mac OS X Automator Action
layout: default
---

Principle
=========

This is an  action for [Mac OS X Automator](http://www.apple.com/macosx/features/automator/) that takes a special path pattern and will try to rename the files it get in inputs according to that pattern.

We call it a "path pattern" because it can contain elements that will be replaced for each file with information coming for the meta data stored in the file.


Example of moving photos
------------------------

Let's make an example. The script supports the EXIF meta data field included in photo files by your camera. It can therefore use them to move the images.

![Example Results](img/folder.png "Example Results")


Let's say you have a bunch of images that you would want to move in directories named from the date they were taken at, like:


    2007
       08
         12
           IMG_1.jpg
           IMG_2.jpg
	   07
	     25
           IMG_3.jpg
    2006
        01
          28
           IMG_4.jpg


You can set the path pattern parameter of the Automator action with the pattern: `%Y/%m/%d/`

The action will extract information from the EXIF data and replace the special markers in the pattern:
- `%Y` will be replaced by the year
- `%m` will be replaced by the month
- `%d` will be replaced by the day

the directory structure will be created and the file moved in the right directory.

There is more detail later on how the patterns work, but this is the basic idea.

Installation
============


Download and open the following [disk image](downloads/MetaDataMover.dmg.zip).

Check out the license and move the **MetaDataMove.action** file in the directory **~/Library/Automator/** (for a particular user) or **/Library/Automator/** (for all users)

Extract the archive and inside you will find _MetaDataMover.action_, move this file  in the directory **~/Library/Automator/** (for a particular user) or **/Library/Automator/** (for all users)



Using the Action
================

Once installed, you will find the action in Automator under the _Finder_ application. Just drag and drop it in the workflow just after an action that returns a list of files.

The action will return a list of the moved/renamed files.

Here are the option:

![MetaDataMover screenshot](img/MetaDataMover.png)

1- do you wish to copy or move the files, default is copy,
2- what path pattern should be used. This is the pattern for the moving/renaming of the file. The default is for EXIF patterns: `%Y/%m/%d/`,
3- in which root directory to put the new files. The path pattern will be applied from that directory. The default is the directory where the current file is,
4- you can check this option and follow the action by the "View Results" action from Automator to do a test run,
5- you can check this option if you are OK with the action overwriting existing file. The default is to not overwrite existing files, see [clash](#clash).


Special Patterns Elements
=========================

Most of the pattern -- except for the date notation in the EXIF case -- elements follow a simple notation, they are the name of a field in the file metadata with columns (':') around. You can use more than once the same marker in the pattern if you wish.

The available meta data fields change according to the file type you are passing to the action. The main fields for photos, music files and PDF are discussed later. Generally, the action uses [ExifTool by Phil Harvey](http://www.sno.phy.queensu.ca/~phil/exiftool/) and therefore, the fields read by this tool can be used, for more details, please see [ExifTool tag names documentation](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/index.html).

The action also offers some basic pattern elements:
- `:basename:` is the name of the file, without extensions,
- `:ext:` is the extension of the file, with the period (`.`),
- `:cnt:` will be replaced by the clash avoidance (see [clash](#clash)) counter if a file with the same name already exists, otherwise, it will just be removed.

Detailed Behaviour
==================

Here are the specifics on how the action deals with the different possible cases.

Trailing Slash
--------------

If the path pattern finishes with a `/`, then it is taken as the directory where the file should be moved, without being renamed.

File Renaming
-------------

If the path pattern doesn't finish with a `/`, the last part of the path is supposed to be the renaming pattern for the file. If it doesn't contain an extension (. followed by something), then the extension of the original file will be used.

File Clash avoiding
-------------------
<a id="clash"/>

If the option _overwrite_ is not checked, the action will avoid replacing an existing file with a file it is renaming. The action has two choices then:
- if the path pattern you specified uses the `:cnt:` special marker, it will replace this by a counter.
- otherwise, the action will add a counter at the end of the file name, just before the file extension.
The action will start with the counter at 1 and try to write the file, if a file with the same counter already exist, it will increment the counter until it finds a new file name.

----------------------------------------------------------------------

Introduction to Photo meta data
===============================

&nbsp;

EXIF Date Patterns
------------------

The photo files containing EXIF metadata can use another special notation to extract the date when the photo was taken (as described in the previous example). The date pattern format is the one provided by the strftime tool. Check out [its man page for details](http://bama.ua.edu/cgi-bin/man-cgi?strftime+3C). Here are useful fields:

<table class="spip" summary="">
<caption>Useful time/date formating</caption>
<thead><tr class="row_first"><th scope="col"> <strong class="spip">Pattern</strong> </th><th scope="col"> <strong class="spip">Meaning</strong></th></tr></thead>
<tbody>
<tr class="row_even"><td> %d </td><td>    The day of the month as a decimal number (range 01 to 31). </td></tr>
<tr class="row_odd"><td>%H  </td><td>   The hour as a decimal number using a 24-hour clock (range 00 to 23). </td></tr>

<tr class="row_even"><td> %I </td><td>    The hour as a decimal number using a 12-hour clock (range 01 to 12). </td></tr>
<tr class="row_odd"><td> %S </td><td> seconds </td></tr>
<tr class="row_even"><td> %m </td><td>    The month as a decimal number (range 01 to 12). </td></tr>
<tr class="row_odd"><td> %M </td><td>    The minute as a decimal number (range 00 to 59). </td></tr>

<tr class="row_even"><td> %s  </td><td>   The number of seconds since the Epoch, i.e., since 1970-01-01 00:00:00 UTC. </td></tr>
<tr class="row_odd"><td> %u  </td><td>   The day of the week as a decimal, range 1 to 7, Monday being 1. </td></tr>
<tr class="row_even"><td>  %y  </td><td>   The year as a decimal number without a century (range 00 to 99). </td></tr>
<tr class="row_odd"><td> %Y </td><td>    The year as a decimal number including the century. </td></tr>

</tbody>
</table>

EXIF Patterns Elements
----------------------

You can also tell the tool to extract other EXIF information by putting the EXIF field name between columns (`:`) in the pattern. For example, `%Y/%m/%d/:Model:/` will put the photos in subdirectories by date and then by model of camera.

<table class="spip" summary="">
<caption>Useful EXIF fields</caption>
<thead><tr class="row_first"><th scope="col"><strong class="spip">Field</strong></th><th scope="col"><strong class="spip">Meaning</strong></th></tr></thead>
<tbody>
<tr class="row_even"><td>:Model:</td><td> the name of the camera model </td></tr>
<tr class="row_odd"><td>:Manufacturer:</td><td> the camera brand </td></tr>
<tr class="row_even"><td> :ISO:</td><td>the iso setting</td></tr>

<tr class="row_odd"><td>:FNumber:</td><td> the aperture in f value </td></tr>
</tbody>
</table>

--------------------------------------------------------------------------------

Introduction to Music files meta data
=====================================

Most of the modern music file formats like mp3 support meta data fields to store the name of the track, the performing artist, etc... The action can extract these fields and can be used to organise a music collection automatically.

<table class="spip" summary="">
<caption>Useful ID3 fields</caption>
<thead><tr class="row_first"><th scope="col"><strong class="spip">Field</strong></th><th scope="col"><strong class="spip">Meaning</strong></th></tr></thead>
<tbody>
<tr class="row_even"><td>:Artist:</td><td> the performing artist </td></tr>
<tr class="row_odd"><td>:Album:</td><td> the album of this track </td></tr>
<tr class="row_even"><td>:Title:</td><td>the title of this track</td></tr>

<tr class="row_odd"><td>:Genre:</td><td> the genre classification of this track </td></tr>
</tbody>
</table>

--------------------------------------------------------------------------------

Organising PDF Documents
========================

You can also use the automator action to organise your pdf documents if they contain the right metadata. If the author of the file has tagged it with the right information, you can extract his name, etc... etc...

<table class="spip" summary="">
<caption>Useful PDF fields</caption>
<thead><tr class="row_first"><th scope="col"><strong class="spip">Field</strong></th><th scope="col"><strong class="spip">Meaning</strong></th></tr></thead>
<tbody>
<tr class="row_even"><td>:Title:</td><td> the document title </td></tr>
<tr class="row_odd"><td>:Creator:</td><td> the document creator </td></tr>

<tr class="row_even"><td>:Author:</td><td>the document author</td></tr>
</tbody>
</table>

---------

Other file formats supported
============================

This automator action is based on the great ExifTool library. It will support all metadata format supported by that library. For details on each format and the tags availlable for that format, see the [exiftool tag names documentation page](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/index.html) or go directly to the format you are interested in from this list:
- [JPEG](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/JPEG.html)
- [EXIF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/EXIF.html)
- [IPTC](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/IPTC.html)
- [XMP](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/XMP.html)
- [GPS](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/GPS.html)
- [GeoTiff](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/GeoTiff.html)
- [ICC_Profile](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/ICC_Profile.html)
- [PrintIM](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PrintIM.html)
- [Photoshop](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Photoshop.html)
- [Canon](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Canon.html)
- [CanonCustom](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/CanonCustom.html)
- [Casio](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Casio.html)
- [FujiFilm](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/FujiFilm.html)
- [HP](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/HP.html)
- [JVC](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/JVC.html)
- [Kodak](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Kodak.html)
- [Leaf](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Leaf.html)
- [Minolta](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Minolta.html)
- [Nikon](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Nikon.html)
- [NikonCapture](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/NikonCapture.html)
- [Olympus](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Olympus.html)
- [Panasonic](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Panasonic.html)
- [Pentax](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Pentax.html)
- [Ricoh](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Ricoh.html)
- [Sanyo](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Sanyo.html)
- [Sigma](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Sigma.html)
- [Sony](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Sony.html)
- [Unknown](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Unknown.html)
- [DNG](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/DNG.html)
- [MinoltaRaw](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MinoltaRaw.html)
- [CanonRaw](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/CanonRaw.html)
- [KyoceraRaw](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/KyoceraRaw.html)
- [SigmaRaw](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/SigmaRaw.html)
- [JFIF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/JFIF.html)
- [FlashPix](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/FlashPix.html)
- [APP12](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/APP12.html)
- [AFCP](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/AFCP.html)
- [CanonVRD](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/CanonVRD.html)
- [FotoStation](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/FotoStation.html)
- [PhotoMechanic](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PhotoMechanic.html)
- [MIE](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MIE.html)
- [ID3](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/ID3.html)
- [Jpeg2000](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Jpeg2000.html)
- [BMP](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/BMP.html)
- [PICT](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PICT.html)
- [PNG](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PNG.html)
- [MNG](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MNG.html)
- [MIFF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MIFF.html)
- [PDF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PDF.html)
- [PostScript](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/PostScript.html)
- [ITC](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/ITC.html)
- [Vorbis](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Vorbis.html)
- [FLAC](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/FLAC.html)
- [APE](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/APE.html)
- [MPC](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MPC.html)
- [MPEG](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/MPEG.html)
- [QuickTime](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/QuickTime.html)
- [Flash](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Flash.html)
- [Real](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Real.html)
- [RIFF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/RIFF.html)
- [AIFF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/AIFF.html)
- [ASF](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/ASF.html)
- [DICOM](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/DICOM.html)
- [HTML](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/HTML.html)
- [Extra](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Extra.html)
- [Composite](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Composite.html)
- [Shortcuts](http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/Shortcuts.html)


------------------------------------------------------------------------------

Localisation
============

The script is already localised in _French_, _Italian_ and _English._ If you want to propose a new localisation, contact me.
