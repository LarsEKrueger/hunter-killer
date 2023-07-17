#! /bin/bash
#
# Script to create a release for uploading to mods.factorio.com

set -e

errorHelp() {
  echo "mk-release.sh: $1"
  echo ""
  echo "mk-release.sh: Create a release for mods.factorio.com"
  echo "USAGE: mk-release [OPTIONS] <version>"
  echo ""
  echo "Options:"
  echo "  -h"
  echo "  --help -- Display help."
  echo ""
  echo "Parameters:"
  echo ""
  echo "  <version> -- Version string as major.minor.patch"
  exit 1
}


while (( $# > 0 )) ; do
  if [ $1 == "-h" ] || [  $1 == "--help" ] ; then
    errorHelp "Display help text."

  # elsif( $ARGV[$opti] eq "-%%%")  
  # {
  #   $opti++;
  #   %%%
  # }

  # elsif( $ARGV[$opti] eq "-%%%")  
  # {
  #   $opti++;
  #   errorHelp( "Missing argument after -%%%") if( $opti>=scalar @ARGV);
  #
  #   %%% = %%% $ARGV[$opti] %%% ;
  #   %%%
  #   $opti++;
  # }

  else
    break
  fi
  shift
done

if (( $# < 1 )) ; then
  errorHelp "Not enough parameters"
fi

version="$1"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ; then
  errorHelp "Parameter '${version}' is not a version number"
fi

# Patch info.json
sed -i "s/\"version\": \"[0-9]\+\.[0-9]\+\.[0-9]\+\"/\"version\": \"$version\"/" info.json

# Commit the changes
git commit -a -m "Version bump to ${version}"

# Create a tag
git tag "v${version}"

# Create release zip
zipfolder="../hunter-killer-${version}"
mkdir ${zipfolder}
cp *.json README.md LICENSE *.lua ${zipfolder}
pushd ..
zip -r "hunter-killer-${version}.zip" "hunter-killer-${version}"
popd

rm -r "${zipfolder}"
