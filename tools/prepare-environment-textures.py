"""Derive modest-sized game textures from downloaded NASA visual references."""
from pathlib import Path
from PIL import Image
import hashlib, json

ROOT = Path(__file__).resolve().parents[1]
REF = Path('D:/apollo-ref/environment')
OUT = ROOT/'assets'/'textures'
OUT.mkdir(parents=True, exist_ok=True)
items = [
    ('earth-april-nasa-blue-marble.jpg','earth.jpg',(4096,2048),
     'https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/april/world.200404.3x5400x2700.jpg',
     'NASA Earth Observatory, Blue Marble Next Generation, April2004 composite'),
    ('moon-lroc-4k.tif','moon.jpg',(4096,2048),
     'https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_16bit_srgb_4k.tif',
     'NASA/Goddard SVS, Ernie Wright; LRO camera team, CGI Moon Kit'),
]
records=[]
for original,name,size,url,credit in items:
    source=REF/original
    image=Image.open(source).convert('RGB')
    image.thumbnail(size,Image.Resampling.LANCZOS)
    image.save(OUT/name,quality=92,subsampling=0)
    records.append({'source':str(source),'url':url,'credit':credit,
                    'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                    'output':str((OUT/name).relative_to(ROOT)), 'size':list(image.size)})
cloud_path=REF/'earth-clouds-nasa-2048.jpg'
if cloud_path.exists():
    base=Image.open(OUT/'earth.jpg').convert('RGB')
    clouds=Image.open(cloud_path).convert('L').resize(base.size,Image.Resampling.LANCZOS)
    # A180-degree alignment is used for this illustrative composite. This
    # preview does not claim a verified historical cloud registration.
    from PIL import ImageChops
    clouds=ImageChops.offset(clouds,base.width//2,0)
    clouds=clouds.point(lambda x:int(x*.84))
    Image.composite(Image.new('RGB',base.size,(238,244,255)),base,clouds).save(OUT/'earth.jpg',quality=92,subsampling=0)
    records.append({'source':str(cloud_path),
                    'url':'https://assets.science.nasa.gov/content/dam/science/esd/eo/content-feature/bluemarble/images/cloud_combined_2048.jpg',
                    'credit':'NASA/Goddard, Reto Stockli; Blue Marble cloud mosaic',
                    'sha256':hashlib.sha256(cloud_path.read_bytes()).hexdigest(),
                    'output':'assets/textures/earth.jpg',
                    'treatment':'Cloud layer aligned by180-degree shift and composited over April2004 land/ocean map.'})
records.append({'source':str(REF/'starmap-2020-4k.exr'),
                'url':'https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr',
                'credit':'NASA/Goddard SVS; Hipparcos2,Tycho2,GaiaDR2 star catalogs',
                'sha256':hashlib.sha256((REF/'starmap-2020-4k.exr').read_bytes()).hexdigest(),
                'output':'assets/textures/stars.png', 'treatment':'Linear EXR converted to sRGB in Blender.'})
(ROOT/'assets'/'environment-sources.json').write_text(json.dumps({
    'schemaVersion':1,'assets':records,
    'limitation':'Earth/Moon viewing directions are illustrative until verified trajectory and attitude are connected. The2004 Earth composite is not a1970 photograph.'
},indent=2)+'\n',encoding='utf-8')
print('Prepared NASA Earth and lunar textures with source hashes')
