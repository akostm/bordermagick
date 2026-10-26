# Test photos: plasma "landscapes" with chosen metadata, small so the tests are quick.
# Sourced by the test scripts; make_photos DIR creates them once.
make_photos() {
  local d=$1
  [[ -f "$d/.done" ]] && return
  mkdir -p "$d"
  magick -seed 1 -size 900x600 plasma:skyblue-sandybrown -blur 0x1 -quality 92 "$d/fuji_33.jpg"
  exiftool -q -overwrite_original -Make=FUJIFILM -Model=X-T20 "-LensModel=XF18-55mmF2.8-4 R LM OIS" \
    -FocalLength=35.8 -FNumber=11 -ExposureTime=1/340 -ISO=200 "-DateTimeOriginal=2023:10:05 11:12:30" \
    -XMP:Title=Erechtheion -XMP:City=Athens "$d/fuji_33.jpg"
  magick -seed 2 -size 600x900 plasma:darkolivegreen-khaki -blur 0x1 -quality 92 "$d/sony_portrait.jpg"
  exiftool -q -overwrite_original -Make=SONY -Model=ILCE-7M4 "-LensModel=FE 24-70mm F2.8 GM" \
    -FocalLength=50 -FNumber=2.8 -ExposureTime=1/500 -ISO=400 "-DateTimeOriginal=2024:06:01 18:00:00" \
    -XMP:City=Zürich "$d/sony_portrait.jpg"
  magick -seed 3 -size 800x800 plasma:navy-orange -blur 0x1 -quality 92 "$d/no_exif.jpg"
  touch "$d/.done"
}
