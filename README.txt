Author: Pierre Andrews
Version: 1.0
Release: 10 August 2007
URL: http://6v8.gamboni.org/Move-Rename-Files-according-to.html
License: GPL

======================================================================

This is an action for Mac OS X Automator that takes a special path pattern and will try to rename the files it get in inputs according to that pattern.

We call it a "path pattern" because it can contain elements that will be replaced for each file with information coming for the meta data stored in the file.

======================================================================

Example of moving photos

Let’s make an example. The script supports the EXIF meta data field included in photo files by your camera. It can therefore use them to move the images.
PNG - 23.2 kb
Example Results

Let’s say you have a bunch of images that you would want to move in directories named from the date they were taken at, like:

    * 2007
          o 08
                + 12
                      # IMG_1.jpg
                      # IMG_2.jpg
          o 07
                + 25
                      # IMG_3.jpg
    * 2006
          o 01
                + 28
                      # IMG_4.jpg

You can set the path pattern parameter of the Automator action with the pattern: %Y/%m/%d/

The action will extract information from the EXIF data and replace the special markers in the pattern:

    * %Y will be replaced by the year
    * %m will be replaced by the month
    * %d will be replaced by the day

the directory structure will be created and the file moved in the right directory.

======================================================================

Installation

Once built, move the MetaDataMove.action file in the directory  /Library/Automator/ (for a particular user) or /Library/Automator/ (for all users)

======================================================================

Special Patterns Elements

Most of the pattern — except for the date notation in the EXIF case — elements follow a simple notation, they are the name of a field in the file metadata with columns (’:’) around. You can use more than once the same marker in the pattern if you wish.

The available meta data fields change according to the file type you are passing to the action. The main fields for photos, music files and PDF are discussed later. Generally, the action uses ExifTool by Phil Harvey and therefore, the fields read by this tool can be used, for more details, please see ExifTool tag names documentation.

The action also offers some basic pattern elements:

    * :basename: is the name of the file, without extensions,
    * :ext: is the extension of the file, with the period (.),
    * :cnt: will be replaced by the clash avoidance (see later) counter if a file with the same name already exists, otherwise, it will just be removed.

Detailed Behaviour

Here are the specifics on how the action deals with the different possible cases.

Trailing Slash

If the path pattern finishes with a /, then it is taken as the directory where the file should be moved, without being renamed.

File Renaming

If the path pattern doesn’t finish with a /, the last part of the path is supposed to be the renaming pattern for the file. If it doesn’t contain an extension (. followed by something), then the extension of the original file will be used.

File Clash avoiding

If the option overwrite is not checked, the action will avoid replacing an existing file with a file it is renaming. The action has two choices then:

    * if the path pattern you specified uses the :cnt: special marker, it will replace this by a counter.
    * otherwise, the action will add a counter at the end of the file name, just before the file extension. The action will start with the counter at 1 and try to write the file, if a file with the same counter already exist, it will increment the counter until it finds a new file name.

======================================================================

This code uses ExifTool by Phil Harvey for all the metadata extraction:
http://www.sno.phy.queensu.ca/~phil/exiftool/

======================================================================

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

----------------------------------------------------------------------
