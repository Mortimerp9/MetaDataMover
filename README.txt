Author: Pierre Andrews
Version: 1.0
Release: 10 August 2007
URL: http://6v8.gamboni.org/Move-Rename-Images-according-to.html
License: GPL

======================================================================

This is an Automator action (for Apple Automator.app) that takes a list of images as input and will move them according to a special pattern which can contain EXIF data.

You will need to install:
http://www.sno.phy.queensu.ca/~phil/exiftool/install.html#OSX

Install the action file in ~/Library/Automator/ or /Library/Automator

In the current version, if a file with the same path already exist, the auto mover will erase it. So be careful. This is in the TODO list.

======================================================================

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

----------------------------------------------------------------------

For example, if you have a bunch of images that you want to move in directories named from the date they were taken, like:
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

You can pass them to this automator action with the pattern:
%Y/%m/%d/

From the EXIF data,
%Y will be replaced by the year
%m will be replaced by the month
%d will be replaced by the day

the directory structure will be created and the file moved in the right directory.

The date format is the one provided by the strftime tool. See it's man page for details.

You can also tell the tool to extract other EXIF information by putting the field name between ':' in the pattern:
%Y/%m/%d/:Model:/
will put the photos in subdirectories by date and model of the camera.

This will only work on files with EXIF fields and on system with exiftool installed.

There are also special patterns:
:basename: is the name of the file, without extensions
:ext: is the extension of the file, with the .
:cnt: is a counter for the file.
