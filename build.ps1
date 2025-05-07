$owner = 'Ryubing'
$repo  = 'Stable-Releases'

mkdir dist

# New-Item -ItemType Directory -Path dist

cd dist

curl -L -o ProdKeys.net-v19.0.1.zip https://files.prodkeys.net/ProdKeys.net-v19.0.1.zip
curl -L -o Firmware.19.0.1.zip https://github.com/THZoria/NX_Firmware/releases/download/19.0.1/Firmware.19.0.1.zip


$tagsUrl = "https://api.github.com/repos/$owner/$repo/tags"
$allTags = Invoke-RestMethod -Uri $tagsUrl -Headers @{ 'User-Agent' = 'PowerShell' }

$latestTag = $allTags[0].name
Write-Host "latest tag:  $latestTag"

# $filename = "ryujinx-$latestTag-win_x64.zip"
$filename = "ryujinx-win_x64.zip"
$downloadUrl = "https://github.com/$owner/$repo/releases/download/$latestTag/$filename"
Write-Host "download $downloadUrl"

# Invoke-WebRequest -Uri $downloadUrl -OutFile $filename
curl -o $filename $downloadUrl

cd ..

ls dist


Expand-Archive -Path "dist/ProdKeys.net-v19.0.1.zip" -DestinationPath "ProdKeys"
Expand-Archive -Path "dist/Firmware.19.0.1.zip" -DestinationPath "Firmware"
Expand-Archive -Path "dist/ryujinx-win_x64.zip" -DestinationPath "ryujinx-win"

mv -rf ./ryujinx-win/publish ./ryujinx

mkdir ryujinx/portable

cd ryujinx

$process = Start-Process ./Ryujinx.exe -PassThru

Start-Sleep -Seconds 10

Stop-Process -Id $process.Id

ls portable

cp -rf ../ProdKeys/*.keys ./portable/system
cp -rf ../Firmware/* ./portable/bis/system/Contents/registered

# cd ..

zip -r -q ../dist/ryujinx.zip .


# Compress-Archive -Path "." -DestinationPath "../dist/ryujinx.zip"
#  "../dist/ryujinx.zip"

ls dist
