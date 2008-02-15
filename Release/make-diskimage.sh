# Create a read-only disk image of the contents of a folder
#
# Usage: make-diskimage <image_file>
#                       <src_folder>
#                       <volume_name>
#                       <eula_resource_file>
#
# make-diskimage.sh $(BUILD_DIR)/$(RELEASE_NAME).dmg $(ADIUM_DIR) "Adium X $(VERSION)" dmg_adium.scpt $(ART_DIR)
#

set -e;

DMG_DIRNAME=`dirname $1`
DMG_DIR=`cd $DMG_DIRNAME > /dev/null; pwd`
DMG_NAME=`basename $1`
DMG_TEMP_NAME=${DMG_DIR}/rw.${DMG_NAME}
VOLUME_NAME=$2
EULA_RSRC=$3

# Create the image
echo "Creating disk image..."
rm -f "${DMG_TEMP_NAME}"
cp ./Release/Stage.dmg ${DMG_TEMP_NAME}

# mount it
echo "Mounting disk image..."
MOUNT_DIR="/Volumes/${VOLUME_NAME}"
DEV_NAME=`hdiutil attach -readwrite -noverify -noautoopen "${DMG_TEMP_NAME}" | egrep '^/dev/' | sed 1q | awk '{print $1}'`

cp -r $TARGET_BUILD_DIR/*.action ${MOUNT_DIR} #/"MetaDataMover Installer.app/Contents/Resources/Actions/"

# make the top window open itself on mount:
if [ -x /usr/local/bin/openUp ]; then
    /usr/local/bin/openUp "${MOUNT_DIR}"
fi

# unmount
echo "Unmounting disk image..."
hdiutil detach "${DEV_NAME}"

# compress image
echo "Compressing disk image..."
hdiutil convert "${DMG_TEMP_NAME}" -format UDZO -imagekey zlib-level=9 -o "${DMG_DIR}/${DMG_NAME}"
rm -f "${DMG_TEMP_NAME}"

# adding EULA resources
if [ ! -z "${EULA_RSRC}" -a "${EULA_RSRC}" != "-null-" ]; then
        echo "adding EULA resources"
        hdiutil unflatten "${DMG_DIR}/${DMG_NAME}"
		/Developer/Tools/Rez /Developer/Headers/FlatCarbon/*.r "${EULA_RSRC}" -a -o "${DMG_DIR}/${DMG_NAME}"
        hdiutil flatten "${DMG_DIR}/${DMG_NAME}"
fi

echo "Disk image done"
exit 0
