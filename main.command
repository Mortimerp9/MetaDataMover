#!/usr/bin/perl

# main.command
# AutoExifMover

#  Created by Pierre Andrews on 01/07/2007.
#  Copyright 2007-2008 Pierre Andrews. All rights reserved.
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 3 of the License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


# add our 'lib' directory to the include list BEFORE 'use Image::ExifTool'
my $exeDir;
BEGIN {
    # get exe directory
    $exeDir = ($0 =~ /(.*)[\\\/]/) ? $1 : '.';
    # add lib directory at start of include path
    unshift @INC, "$exeDir/lib";
}

use Image::ExifTool;
use File::Path;
use File::Basename;
use File::Copy;

#my $homedir=`ksh -c "(cd ~ 2>/dev/null && /bin/pwd)"`; 
#chomp($homedir);
$homedir = $ENV{'HOME'};

my $exifTool = new Image::ExifTool;
my $pattern = $ENV{'pathPattern'};
if(!$pattern) {
	$pattern = "%Y_%m_%d/";
}
$exifTool->Options(DateFormat => $pattern);

while(<>) {
	chomp;
	
	if(-e $_) {	
		
		my $file = $_;
		my $name;
		my $dir;
		my $suffix;
		my $with_basename=0;
		($name,$dir,$suffix) = fileparse($file,qr/\.[^.]*$/);
		my $destPath = $ENV{'directoryPath'};
		if(!$destPath) { $destPath = $dir; }
		my $info = $exifTool->ImageInfo($file, 'DateTimeOriginal');
		my $path = $$info{'DateTimeOriginal'};
		if(!$path) {
			$info = $exifTool->ImageInfo($file, 'FileModifyDate');
			$path = $$info{'FileModifyDate'};
		}
		if(!$path && $pattern !~ /%[A-Za-z]/) {
			$path = $pattern;
		} 
		if($path) {
			while($path =~ /:([a-zA-Z]+):/g) {
			    $label = $1;
				if($label =~ /basename/i) {
					$with_basename=true;
					$path =~ s/:basename:/$name/g;
				} elsif($label =~ /ext/i) {
					$path =~ s/:ext:/$suffix/g;
				} else {
					my $info = $exifTool->ImageInfo($_, "$label");
					if($$info{"$label"}) {
						my $value = $$info{"$label"};
						$value =~ s/^\s+//;
						$value =~ s/\s+$//;
						$value =~ s/\//_/;
						chomp($value);
						$value =~ s/ /_/g;
						$path =~ s/:$label:/$value/g;
					} else {
						$path =~ s/:$label://g;
					}
				}
			}
			$path =~ s/[^A-Za-z0-9_\/.\-~]/_/g;
			$path = $destPath.'/'.$path;
			$path =~ s/^~/$homedir/; 
			
			($new_name,$new_dir,$new_suffix) = fileparse($path,qr/\.[^.]*$/);
			if($new_name && !$with_basename) {
				$path = $new_dir.'/'.$new_name.$new_suffix;
			}
			if(!$new_name) {
				$path .= $name.$suffix;
				$new_name = $name;
				$new_suffix = $suffix;
			}
			if(!$new_suffix || $new_suffix!=$suffix) {
				$path .= $suffix;
			}
			
			
			if(!$ENV{'test'}) { mkpath($new_dir); }
			if(!$ENV{'overwrite'}) {
				if(-e $path) {
					if($path !~ /:cnt:/i) {
						$path =~ s/(\.[^.]*)$/_:cnt:$1/;
					}
					my $local_cnt = 1;
					$new_path = $path;
					$new_path =~ s/:cnt:/$local_cnt/g;
					while(-e $new_path) {
						$local_cnt++;
						$new_path = $path;
						$new_path =~ s/:cnt:/$local_cnt/g;
					}
					$path = $new_path;
				}
				$path =~ s/_+/_/g;
				$path =~ s/_:cnt://g;
			} else {
				$path =~ s/:cnt://g;			
			}

			if(!$ENV{'test'}) {
				if($ENV{'action'} == 1) {
					move($file,$path);
				} else {
					copy($file,$path);
				}
			}
			print $path."\n";
		}
	}
}
