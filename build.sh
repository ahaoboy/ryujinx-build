#!/bin/bash

# Define variables
owner='Ryubing'
repo='Stable-Releases'

# Create the 'dist' directory
mkdir dist

# Change to the 'dist' directory
cd dist

# Download zip files using curl
curl -L -o ProdKeys.net-v19.0.1.zip https://files.prodkeys.net/ProdKeys.net-v19.0.1.zip
curl -L -o Firmware.19.0.1.zip https://github.com/THZoria/NX_Firmware/releases/download/19.0.1/Firmware.19.0.1.zip

# Fetch the latest tag from GitHub API
# tagsUrl="https://api.github.com/repos/$owner/$repo/tags"
# allTags=$(curl -s -H "User-Agent: Bash" "$tagsUrl")
# latestTag=$(echo "$allTags" | jq -r '.[0].name')
# echo "latest tag: $latestTag"
# Define filename and construct download URL
# filename="ryujinx-$latestTag-win_x64.zip"
# downloadUrl="https://github.com/$owner/$repo/releases/download/$latestTag/$filename"
# echo "download $downloadUrl"

# Fetch the latest tag from Ryujinx API
tagsUrl="https://git.ryujinx.app/api/v4/projects/ryubing%2Fryujinx/releases"
allTags=$(curl -s -H "User-Agent: Bash" "$tagsUrl")
latestTag=$(echo "$allTags" | jq -r '.[0].tag_name')
echo "latest tag: $latestTag"

# Define filename and construct download URL
filename="ryujinx-$latestTag-win_x64.zip"
downloadUrl="https://git.ryujinx.app/api/v4/projects/1/packages/generic/Ryubing/$latestTag/$filename"
echo "download $downloadUrl"

# Download the file
curl -L -o "$filename" "$downloadUrl"

# Return to the parent directory
cd ..

# List contents of 'dist' (using ls, assuming it's an alias or available)
ls dist

# Extract the downloaded zip files
unzip -q "dist/ProdKeys.net-v19.0.1.zip" -d "ProdKeys"
unzip -q "dist/Firmware.19.0.1.zip" -d "Firmware"
unzip -q "dist/$filename" -d "ryujinx-win"

# Move the 'publish' directory to 'ryujinx'
mv ./ryujinx-win/publish ./ryujinx

# Create 'portable' directory inside 'ryujinx'
mkdir ./ryujinx/portable

# Change to the 'ryujinx' directory
cd ryujinx

# Run Ryujinx.exe in the background and capture its PID
# Note: If running on Linux, you may need Wine (e.g., 'wine ./Ryujinx.exe &')

./Ryujinx.exe &
pid=$!

# Wait for 10 seconds
sleep 10

# Terminate the process
kill $pid

# List contents of 'portable'
ls portable

ls ../ProdKeys/ProdKeys.net-v19.0.1
# ls ../Firmware

# Copy files to their respective directories
cp -r ../ProdKeys/ProdKeys.net-v19.0.1/*.keys ./portable/system
cp -r ../Firmware/* ./portable/bis/system/Contents/registered

# rename Firmware
for file in ./portable/bis/system/Contents/registered/*; do
    nca=$(basename "$file")

    if [[ $nca == *.cnmt.nca ]]; then
        xxx=${nca%.cnmt.nca}
    elif [[ $nca == *.nca ]]; then
        xxx=${nca%.nca}
    else
        continue
    fi

    mv "$file" "00"

    folder="./portable/bis/system/Contents/registered/$xxx.nca"
    mkdir "$folder"

    mv "00" "$folder/00"
done

# add games dir
sed -i 's/"game_dirs": \[\]/"game_dirs": ["portable\/games"]/g' ./portable/Config.json

rm ../dist/$filename
zip -r -q ../dist/$filename .

# List contents of '../dist' from the current directory
ls ../dist

echo "tag=$latestTag" >> $GITHUB_OUTPUT
