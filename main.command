#!/usr/bin/perl

# main.command
# AutoExifMover

#  Created by Pierre Andrews on 01/07/2007.
#  Copyright 2007 Pierre Andrews. All rights reserved.

#use lib "/usr/bin/lib/";

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

while(<>) {
	chomp;
	
	if(-e $_) {	
		my $exifTool = new Image::ExifTool;
		my $pattern = $ENV{'pathPattern'};
		if(!$pattern) {
			$pattern = "%Y_%m_%d/";
		}
		$exifTool->Options(DateFormat => $pattern);
		
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
		if(!$path && $pattern !~ /%[A-Za-z]/) {
			$path = $pattern;
		} 
		if($path) {
			while($path =~ /:([a-zA-Z]+):/g) {
				if($1 =~ /basename/i) {
					$with_basename=true;
					$path =~ s/:basename:/$name/g;
				} elsif($1 =~ /ext/i) {
					$path =~ s/:ext:/$suffix/g;
				} else {
					my $info = $exifTool->ImageInfo($_, "$1");
					if($$info{"$1"}) {
						my $i = $$info{"$1"};
						my $x = $1;
						$i =~ s/ /_/g;
						chomp($i);
						$path =~ s/:$x:/$i/g;
					} else {
						$path =~ s/:$1://g;
					}
				}
			}
			$path =~ s/[^A-Za-z0-9_\/.-~]/_/g;
			$path = $destPath.'/'.$path;
			
			$homedir=`ksh -c "(cd ~ 2>/dev/null && /bin/pwd)"`; 
			chomp($homedir);
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
			}

			if(!$ENV{'test'}) {
				if($ENV{'action'} == 'move') {
					move($file,$path);
				} else {
					copy($file,$path);
				}
			}
			print $path."\n";
		}
	}
}
